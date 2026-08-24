import Foundation
import Alamofire
import Network

/// 与 Flutter/Android 对齐：直连优先，中继连上后做升级探测
enum P2pIcePreference {
    case auto       // STUN + TURN，直连可用则直连
    case directOnly // 仅 STUN/直连，用于升级探测
    case relayOnly  // 仅 TURN
}

enum P2pTransportKind {
    case unknown
    case direct  // host / srflx / prflx
    case relay
}

@MainActor
final class P2PService: ObservableObject {
    static let shared = P2PService()

    @Published private(set) var isConnected = false
    @Published private(set) var pairCode: String = ""
    @Published private(set) var connectionState: P2PConnectionState = .disconnected
    @Published private(set) var lastError: String?
    /// 当前使用的 TURN 中继地址（例如 xxx.nas.cab:8443），仅在 P2P 中继模式下有意义
    @Published private(set) var relayAddress: String = ""
    /// 当前传输类型：直连或中继（与 Flutter/Android 一致）
    @Published private(set) var transportKind: P2pTransportKind = .unknown

    /// 中继连上后回调（如升级检测），由外部设置
    var onRelayConnected: (() -> Void)?

    enum P2PConnectionState: String {
        case disconnected
        case connecting
        case connected
        case failed
        case reconnecting
    }

    private var sessionId: String = ""
    private var signaling: WebSocketSignaling?
    private var rtcClient: WebRTCClient?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var allowReconnect = false

    /// 当前 ICE 偏好（用于升级探测时先试 directOnly）
    private var icePreference: P2pIcePreference = .auto
    private var autoSwitchInProgress = false
    private var lastAutoSwitchAttemptAtMs: Int64 = 0
    private var lastAutoSwitchProbeAtMs: Int64 = 0
    private var pathMonitor: NWPathMonitor?
    private var pathMonitorQueue: DispatchQueue?
    /// 与 Flutter `Timer.periodic(60s)` 一致：网络无变化时仍定期尝试 relay→direct
    private var relayUpgradePeriodicTimer: Timer?

    /// 与 Flutter `_p2pConnectQueue` 一致：并发 `connectByPairCode` 会互相 cleanup 掉对方的 WS/RTC，导致中继下偶发「信令超时 / 未连接就发 API」
    private var connectSerialTask: Task<Void, Error>?

    // MARK: - Connect

    /// - Parameters:
    ///   - iceTransportPolicy: 可选，仅 DEBUG 有效。"relay" 表示仅中继；nil 表示自动（含直连）
    ///   - icePreference: 与 Flutter 对齐：auto 含直连+中继；directOnly 仅直连（用于升级探测）
    func connectByPairCode(_ code: String, iceTransportPolicy: String? = nil, icePreference pref: P2pIcePreference = .auto) async throws {
        if let previous = connectSerialTask {
            print("[P2P] P2PService: connectByPairCode queued (waiting for previous connect)")
            try? await previous.value
        }
        let task = Task { try await self.connectByPairCodeBody(code: code, iceTransportPolicy: iceTransportPolicy, icePreference: pref) }
        connectSerialTask = task
        defer { connectSerialTask = nil }
        try await task.value
    }

    private func connectByPairCodeBody(code: String, iceTransportPolicy: String?, icePreference pref: P2pIcePreference) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            print("[P2P] P2PService: connectByPairCode empty code")
            throw P2PError.emptyPairCode
        }

        #if DEBUG
        let policy = iceTransportPolicy ?? DevConnectModeManager.load().p2pIceTransportPolicy
        #else
        let policy: String? = nil
        #endif

        icePreference = pref
        if pref == .relayOnly { transportKind = .relay }
        else if pref == .directOnly { transportKind = .direct }
        else { transportKind = .unknown }

        print("[P2P] P2PService: connectByPairCode start iceTransportPolicy=\(policy ?? "nil") preference=\(pref)")
        connectionState = .connecting
        lastError = nil

        do {
            // 与 Flutter `connectP2pByPairCode` 一致：新一轮连接前取消待处理的重连，避免旧 WS 关闭触发 scheduleReconnect 与本次抢连
            reconnectTimer?.invalidate()
            reconnectTimer = nil

            try await cleanupConnection(disableReconnect: false)
            print("[P2P] P2PService: cleanup done, creating session")

            let session = try await createP2pSession(pairCode: trimmed)
            guard let wsUrl = session["wsUrl"] as? String,
                  let sid = session["sessionId"] as? String,
                  !wsUrl.isEmpty, !sid.isEmpty else {
                print("[P2P] P2PService: invalidSession (missing wsUrl or sessionId)")
                throw P2PError.invalidSession
            }
            print("[P2P] P2PService: session created sid=\(sid.prefix(8))... wsUrl host=\(URL(string: wsUrl)?.host ?? "?")")

            sessionId = sid
            pairCode = trimmed
            allowReconnect = true

            print("[P2P] P2PService: connectSignaling start")
            var iceServers = try await connectSignaling(wsUrl: wsUrl)
            iceServers = try applyIcePreference(iceServers, pref)
            print("[P2P] P2PService: connectSignaling done, iceServers count=\(iceServers.count)")

            relayAddress = extractTurnServerAddress(from: iceServers)

            print("[P2P] P2PService: startWebRTC start")
            try await startWebRTC(sessionId: sid, iceServers: iceServers, iceTransportPolicy: policy)
            print("[P2P] P2PService: startWebRTC done, connected")

            isConnected = true
            connectionState = .connected
            reconnectAttempts = 0

            APIClient.shared.setBaseUrl(NetworkConfig.p2pBaseUrl)
            LocalPlaybackProxy.shared.start()
            savePairCode(trimmed)
            startAutoSwitchMonitor()

            // 与 Flutter/Android 对齐：约 800ms 后取 transport 类型；若为 relay 则立即触发升级探测并执行中继连上回调
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let self, let rtc = self.rtcClient, self.isConnected else { return }
                let stats = await rtc.getTransportStats()
                let type = (stats["type"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                switch type {
                case "relay":
                    self.transportKind = .relay
                    self.onRelayConnected?()
                    await self.runAutoSwitchProbe(ignoreThrottle: true)
                case "host", "srflx", "prflx":
                    self.transportKind = .direct
                default:
                    break
                }
            }

            print("[P2P] P2PService: connectByPairCode success")
        } catch {
            print("[P2P] P2PService: connectByPairCode catch \(type(of: error)) \(error.localizedDescription)")
            connectionState = .failed
            lastError = error.localizedDescription
            isConnected = false
            try? await cleanupConnection(disableReconnect: false)
            throw error
        }
    }

    func connectAndCheckStatus(_ code: String, timeout: TimeInterval = 20) async throws -> ServerStatusResponse {
        print("[P2P] P2PService: connectAndCheckStatus start timeout=\(timeout)")
        try await connectByPairCode(code)
        print("[P2P] P2PService: connectAndCheckStatus P2P connected, calling checkServerStatus")
        let status = await AuthService.shared.checkServerStatus(timeout: timeout)
        print("[P2P] P2PService: connectAndCheckStatus checkServerStatus success=\(status.success) isNasCabServer=\(status.isNasCabServer)")
        return status
    }

    // MARK: - Send API Request via P2P

    func sendApiRequest(
        method: String,
        path: String,
        headers: [String: String],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 300
    ) async throws -> P2pApiResponse {
        guard let rtc = rtcClient, isConnected else {
            print("[P2P] P2PService: sendApiRequest notConnected rtc=\(rtcClient != nil) isConnected=\(isConnected)")
            throw P2PError.notConnected
        }
        print("[P2P] P2PService: sendApiRequest \(method) \(path)")
        let result = try await rtc.sendRequest(
            channel: .api,
            method: method,
            path: path,
            headers: headers,
            bodyBytes: bodyBytes,
            timeout: timeout
        )
        print("[P2P] P2PService: sendApiRequest done status=\(result.status)")
        return result
    }

    // MARK: - Send File Request via P2P (for large payloads / thumbnails)

    func sendFileRequest(
        method: String,
        path: String,
        headers: [String: String] = [:],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 300
    ) async throws -> P2pApiResponse {
        guard let rtc = rtcClient, isConnected else {
            print("[P2P] P2PService: sendFileRequest notConnected rtc=\(rtcClient != nil) isConnected=\(isConnected)")
            throw P2PError.notConnected
        }
        print("[P2P] P2PService: sendFileRequest \(method) \(path)")
        let result = try await rtc.sendRequest(
            channel: .file,
            method: method,
            path: path,
            headers: headers,
            bodyBytes: bodyBytes,
            timeout: timeout
        )
        print("[P2P] P2PService: sendFileRequest done status=\(result.status)")
        return result
    }

    /// 流式文件请求：用于视频/大文件播放，边收边下发给本地代理，避免整 body 进内存。
    func sendFileStreamRequest(
        method: String,
        path: String,
        headers: [String: String] = [:],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 600
    ) -> AsyncThrowingStream<P2pStreamEvent, Error> {
        let pathLog = path.count > 80 ? String(path.prefix(80)) + "..." : path
        guard let rtc = rtcClient, isConnected else {
            print("[P2P] P2PService: sendFileStreamRequest notConnected path=\(pathLog)")
            return AsyncThrowingStream { $0.finish(throwing: P2PError.notConnected) }
        }
        print("[P2P] P2PService: sendFileStreamRequest start path=\(pathLog)")
        return rtc.sendStreamRequest(
            channel: P2pRtcChannel.file,
            method: method,
            path: path,
            headers: headers,
            bodyBytes: bodyBytes,
            timeout: timeout
        )
    }

    /// 流式视频请求：与 file 分离的独立通道，避免图片/小文件请求挤占导致播放器超时断开。
    func sendVideoStreamRequest(
        method: String,
        path: String,
        headers: [String: String] = [:],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 600
    ) -> AsyncThrowingStream<P2pStreamEvent, Error> {
        let pathLog = path.count > 80 ? String(path.prefix(80)) + "..." : path
        guard let rtc = rtcClient, isConnected else {
            print("[P2P] P2PService: sendVideoStreamRequest notConnected path=\(pathLog)")
            return AsyncThrowingStream { $0.finish(throwing: P2PError.notConnected) }
        }
        print("[P2P] P2PService: sendVideoStreamRequest start path=\(pathLog)")
        return rtc.sendStreamRequest(
            channel: P2pRtcChannel.video,
            method: method,
            path: path,
            headers: headers,
            bodyBytes: bodyBytes,
            timeout: timeout
        )
    }

    /// 取消流式请求，通知后端停止发送并释放本地流上下文（播放器退出或连接关闭时调用）
    func cancelStreamRequest(channel: P2pRtcChannel, id: String) {
        guard !id.isEmpty, let rtc = rtcClient else { return }
        rtc.sendCancel(channel: channel, id: id)
    }

    func sendStreamAck(channel: P2pRtcChannel, id: String, delta: Int) {
        guard delta > 0, !id.isEmpty, let rtc = rtcClient else { return }
        rtc.sendStreamAck(channel: channel, id: id, delta: delta)
    }

    // MARK: - Disconnect

    func disconnect() {
        Task { @MainActor in
            try? await cleanupConnection(disableReconnect: true)
            isConnected = false
            connectionState = .disconnected
            sessionId = ""
            pairCode = ""
            LocalPlaybackProxy.shared.stop()
        }
    }

    func ensureConnected(timeout: TimeInterval = 15) async -> Bool {
        if isConnected { return true }
        let code = storedPairCode
        guard !code.isEmpty else { return false }
        do {
            try await connectByPairCode(code)
            return true
        } catch {
            return false
        }
    }

    var storedPairCode: String {
        (UserDefaults.standard.string(forKey: "p2p_last_pair_code") ?? "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private: Signaling Connection

    private func connectSignaling(wsUrl: String) async throws -> [[String: Any]] {
        let ws = WebSocketSignaling()
        signaling = ws

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[[String: Any]], Error>) in
            let handler = SignalingReadyHandler(continuation: cont)
            ws.delegate = handler
            ws.connect(to: wsUrl)
        }
    }

    // MARK: - Private: WebRTC

    private func startWebRTC(sessionId: String, iceServers: [[String: Any]], iceTransportPolicy: String? = nil) async throws {
        guard let ws = signaling else { throw P2PError.invalidSession }

        let rtc = WebRTCClient(
            sessionId: sessionId,
            iceServers: iceServers,
            iceTransportPolicy: iceTransportPolicy,
            sendWsJson: { [weak ws] payload in
                ws?.send(json: payload)
            }
        )
        rtcClient = rtc

        ws.delegate = SignalingForwardHandler(rtcClient: rtc, onClose: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.connectionState = .disconnected
                self.rtcClient?.close()
                self.rtcClient = nil
                self.signaling?.disconnect()
                self.signaling = nil
                self.scheduleReconnect()
            }
        })

        try await rtc.start(channels: [.api, .file, .video])
    }

    // MARK: - Private: Cleanup

    private func cleanupConnection(disableReconnect: Bool) async throws {
        stopAutoSwitchMonitor()
        transportKind = .unknown
        if disableReconnect {
            allowReconnect = false
            reconnectTimer?.invalidate()
            reconnectTimer = nil
            reconnectAttempts = 0
        }
        rtcClient?.close()
        rtcClient = nil
        // 先取消 delegate，避免 disconnect/cancel 触发 signalingDidClose → 误 scheduleReconnect（与主动重连抢时序）
        signaling?.delegate = nil
        signaling?.disconnect()
        signaling = nil
        relayAddress = ""
    }

    // MARK: - Private: Reconnect

    private func scheduleReconnect() {
        guard allowReconnect, !pairCode.isEmpty else { return }
        guard reconnectTimer == nil else { return }

        let exp = min(reconnectAttempts, 5)
        let baseSeconds = 2 * (1 << exp)
        let clampedBase = min(baseSeconds, 30)
        // 加入轻微随机抖动，避免大量设备同时重连造成“惊群”
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let jitterFactor = 0.8 + Double(nowMs % 400) / 1000.0 // 0.8 ~ 1.199
        var seconds = Int(round(Double(clampedBase) * jitterFactor))
        if seconds < 1 { seconds = 1 }
        reconnectAttempts += 1

        connectionState = .reconnecting
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.pairCode.isEmpty else { return }
                self.reconnectTimer = nil
                do {
                    try await self.connectByPairCode(self.pairCode)
                    self.reconnectAttempts = 0
                } catch {
                    self.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - Private: ICE preference (align Flutter/Android)

    private func applyIcePreference(_ servers: [[String: Any]], _ pref: P2pIcePreference) throws -> [[String: Any]] {
        if pref == .auto { return servers }
        var out: [[String: Any]] = []
        for s in servers {
            var urlList: [String] = []
            if let u = s["urls"] as? String, !u.trimmingCharacters(in: .whitespaces).isEmpty { urlList.append(u) }
            else if let arr = s["urls"] as? [Any] { urlList = arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            let hasTurn = urlList.contains { isTurnUrl($0) }
            if pref == .directOnly {
                if hasTurn {
                    let next = urlList.filter { !isTurnUrl($0) }
                    if next.isEmpty { continue }
                    var copy = s
                    copy["urls"] = next.count == 1 ? next[0] : next
                    out.append(copy)
                } else {
                    out.append(s)
                }
            } else if pref == .relayOnly {
                if !hasTurn { continue }
                let next = urlList.filter { isTurnUrl($0) }
                if next.isEmpty { continue }
                var copy = s
                copy["urls"] = next.count == 1 ? next[0] : next
                out.append(copy)
            }
        }
        if pref == .relayOnly, out.isEmpty {
            throw P2PError.wsError("p2p_relay_not_available")
        }
        return out.isEmpty ? servers : out
    }

    // MARK: - Private: Auto upgrade relay -> direct (align Flutter/Android)

    private func startAutoSwitchMonitor() {
        guard pathMonitor == nil else { return }
        let queue = DispatchQueue(label: "nascab.p2p.path")
        pathMonitorQueue = queue
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.runAutoSwitchProbe(ignoreThrottle: false) }
        }
        monitor.start(queue: queue)
        relayUpgradePeriodicTimer?.invalidate()
        relayUpgradePeriodicTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runAutoSwitchProbe(ignoreThrottle: false)
            }
        }
        Task { await runAutoSwitchProbe(ignoreThrottle: false) }
    }

    private func stopAutoSwitchMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        pathMonitorQueue = nil
        relayUpgradePeriodicTimer?.invalidate()
        relayUpgradePeriodicTimer = nil
        autoSwitchInProgress = false
        lastAutoSwitchAttemptAtMs = 0
        lastAutoSwitchProbeAtMs = 0
    }

    private func shouldAutoUpgradeRelayToDirect() -> Bool {
        #if DEBUG
        if DevConnectModeManager.load() == .p2pRelay { return false }
        #endif
        guard isConnected, transportKind == .relay, icePreference == .auto else { return false }
        return true
    }

    private func runAutoSwitchProbe(ignoreThrottle: Bool) async {
        guard shouldAutoUpgradeRelayToDirect() else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if !ignoreThrottle, nowMs - lastAutoSwitchProbeAtMs < 10_000 { return }
        lastAutoSwitchProbeAtMs = nowMs
        await attemptUpgradeRelayToDirect()
    }

    private func attemptUpgradeRelayToDirect() async {
        guard shouldAutoUpgradeRelayToDirect(), !autoSwitchInProgress else { return }
        // 与 Flutter `_anyP2pRtcHasPendingRequests`：有 in-flight 请求时不切换，避免中继传输中被整连接重建打断
        if rtcClient?.hasPendingRequests == true { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if nowMs - lastAutoSwitchAttemptAtMs < 20_000 { return }
        lastAutoSwitchAttemptAtMs = nowMs
        let code = pairCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }

        autoSwitchInProgress = true
        let prev = icePreference
        do {
            try await connectByPairCode(code, icePreference: .directOnly)
            try await Task.sleep(nanoseconds: 650_000_000)
            let stats = await rtcClient?.getTransportStats() ?? [:]
            let type = (stats["type"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if type == "relay" || type.isEmpty {
                throw P2PError.wsError("p2p_direct_not_available")
            }
            transportKind = .direct
        } catch {
            try? await connectByPairCode(code, icePreference: .auto)
        }
        if prev == .auto {
            icePreference = .auto
        }
        autoSwitchInProgress = false
    }

    // MARK: - Private: Session Creation

    private func isTurnUrl(_ url: String) -> Bool {
        let lower = url.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasPrefix("turn:") || lower.hasPrefix("turns:")
    }

    /// 从 ICE 服务器列表中提取人类可读的 TURN 地址（host:port）
    private func extractTurnServerAddress(from iceServers: [[String: Any]]) -> String {
        for server in iceServers {
            guard let urlsValue = server["urls"] else { continue }
            var urlList: [String] = []
            if let s = urlsValue as? String {
                let u = s.trimmingCharacters(in: .whitespaces)
                if !u.isEmpty { urlList.append(u) }
            } else if let arr = urlsValue as? [Any] {
                for e in arr {
                    let u = String(describing: e).trimmingCharacters(in: .whitespaces)
                    if !u.isEmpty { urlList.append(u) }
                }
            }
            for u in urlList where isTurnUrl(u) {
                var noScheme = u
                if noScheme.lowercased().hasPrefix("turn:") {
                    noScheme = String(noScheme.dropFirst("turn:".count))
                } else if noScheme.lowercased().hasPrefix("turns:") {
                    noScheme = String(noScheme.dropFirst("turns:".count))
                }
                let parts = noScheme.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
                let hostPart = parts.count == 2 ? String(parts[1]) : String(parts[0])
                let trimmedHost = hostPart.trimmingCharacters(in: .whitespaces)
                if trimmedHost.isEmpty { continue }
                if let qIndex = trimmedHost.firstIndex(of: "?") {
                    return String(trimmedHost[..<qIndex]).trimmingCharacters(in: .whitespaces)
                }
                return trimmedHost
            }
        }
        return ""
    }

    private func savePairCode(_ code: String) {
        UserDefaults.standard.set(code, forKey: "p2p_last_pair_code")
    }

    /// 与 Flutter `ApiController._createP2pSession` 一致：配对会话 HTTP 使用较长超时（tvOS / 弱网下 3s 易 -1001）
    private static let p2pSessionHttpTimeout: TimeInterval = NetworkConfig.defaultTimeout

    /// Alamofire 的 `response.error` 常为 AFError，URLError 在 `userInfo` 链上
    private static func firstUrlErrorCode(in error: Error?) -> Int? {
        guard var current = error.map({ $0 as NSError }) else { return nil }
        for _ in 0..<6 {
            if current.domain == NSURLErrorDomain { return current.code }
            guard let next = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return nil }
            current = next
        }
        return nil
    }

    private func createP2pSession(pairCode: String, linkLabel: String? = nil) async throws -> [String: Any] {
        let url = "\(NetworkConfig.signalApiBaseUrl)/api/p2p/pair/session/create"
        print("[P2P] P2PService: createP2pSession POST \(url) timeout=\(Self.p2pSessionHttpTimeout)s")
        var body: [String: Any] = ["pairCode": pairCode]
        if let label = linkLabel?.trimmingCharacters(in: .whitespaces), !label.isEmpty {
            body["link"] = label
        }

        var headers: HTTPHeaders = [.contentType("application/json")]
        if let jwt = UserDefaults.standard.string(forKey: "nascab_os_jwt"),
           !jwt.trimmingCharacters(in: .whitespaces).isEmpty {
            headers.add(.authorization(bearerToken: jwt))
        }

        let evaluator = DisabledTrustEvaluator()
        let manager = ServerTrustManager(
            allHostsMustBeEvaluated: false,
            evaluators: ["*": evaluator]
        )
        var config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.p2pSessionHttpTimeout
        config.timeoutIntervalForResource = Self.p2pSessionHttpTimeout + 5
        let session = Session(configuration: config, serverTrustManager: manager)

        let response = await session.request(
            url,
            method: .post,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: headers
        ).serializingData(automaticallyCancelling: true).response

        if let httpResponse = response.response,
           (200..<300).contains(httpResponse.statusCode),
           let data = response.data {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[P2P] P2PService: createP2pSession invalidResponse (not JSON)")
                throw P2PError.invalidResponse
            }
            if let dataMap = json["data"] as? [String: Any] {
                print("[P2P] P2PService: createP2pSession success (data)")
                return dataMap
            }
            print("[P2P] P2PService: createP2pSession success (root)")
            return json
        }

        if let urlCode = Self.firstUrlErrorCode(in: response.error) {
            switch urlCode {
            case NSURLErrorTimedOut:
                print("[P2P] P2PService: createP2pSession URLError timedOut")
                throw P2PError.pairSessionTimeout
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                print("[P2P] P2PService: createP2pSession URLError code=\(urlCode)")
                throw P2PError.pairSessionNetworkFailed
            default:
                break
            }
        }

        let code = response.response?.statusCode ?? 0
        print("[P2P] P2PService: createP2pSession HTTP failed statusCode=\(code)")
        throw P2PError.sessionCreationFailed(code)

    }
}

// MARK: - P2PError

enum P2PError: LocalizedError {
    case emptyPairCode
    case invalidSession
    case sessionCreationFailed(Int)
    /// 配对会话 HTTP 超时（与「配对码错误」区分）
    case pairSessionTimeout
    /// DNS / 无网络 / 无法连接信令域名等
    case pairSessionNetworkFailed
    case invalidResponse
    case notConnected
    case wsError(String)

    var errorDescription: String? {
        switch self {
        case .emptyPairCode: return L10n.serverPairCodeEmpty
        case .invalidSession: return L10n.serverP2pSessionInvalid
        case .sessionCreationFailed(let code):
            if code == 0 {
                return L10n.tr("server_connect_timeout")
            }
            return "\(L10n.serverPairCodeInvalid) (\(code))"
        case .pairSessionTimeout: return L10n.tr("server_connect_timeout")
        case .pairSessionNetworkFailed: return L10n.networkFailure
        case .invalidResponse: return L10n.serverConnectFail
        case .notConnected: return L10n.serverConnectFail
        case .wsError(let msg): return Self.localizeWsError(msg)
        }
    }

    /// `wsError` 内部为稳定英文 key，对用户展示走 L10n
    private static func localizeWsError(_ raw: String) -> String {
        switch raw {
        case "p2p_ready_timeout": return L10n.tr("p2p_error_ready_timeout")
        case "p2p_timeout": return L10n.tr("p2p_error_request_timeout")
        case "p2p_closed": return L10n.tr("p2p_error_connection_closed")
        case "p2p_dc_closed": return L10n.tr("p2p_error_connection_closed")
        case "p2p_stream_cancelled": return L10n.tr("p2p_error_stream_cancelled")
        case "p2p_connect_timeout": return L10n.tr("server_connect_timeout")
        case "p2p_relay_not_available": return L10n.tr("p2p_error_relay_not_available")
        case "p2p_direct_not_available": return L10n.tr("p2p_error_direct_not_available")
        case "p2p_signaling_timeout": return L10n.tr("p2p_error_signaling_timeout")
        case "p2p_ws_closed": return L10n.tr("p2p_error_ws_closed")
        default:
            if raw.hasPrefix("p2p_ws_error_") {
                let code = String(raw.dropFirst("p2p_ws_error_".count))
                return L10n.tr("p2p_error_ws_with_code", params: ["code": code])
            }
            return L10n.tr("p2p_error_generic", params: ["detail": raw])
        }
    }
}

// MARK: - Signaling Helpers

private final class SignalingReadyHandler: WebSocketSignalingDelegate {
    private var continuation: CheckedContinuation<[[String: Any]], Error>?
    private var completed = false
    /// 中继 / 跨城信令可能 >3s 才收到 session:ready；超时后取消，避免误杀已成功会话
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<[[String: Any]], Error>) {
        self.continuation = continuation
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 25_000_000_000)
            } catch {
                return
            }
            await MainActor.run { [weak self] in
                self?.timeoutIfNeeded()
            }
        }
    }

    deinit {
        timeoutTask?.cancel()
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    func timeoutIfNeeded() {
        guard !completed else { return }
        completed = true
        cancelTimeout()
        print("[P2P] SignalingReadyHandler: timeoutIfNeeded (25s)")
        continuation?.resume(throwing: P2PError.wsError("p2p_signaling_timeout"))
        continuation = nil
    }

    func signalingDidReceiveSessionReady(sessionId: String, iceServers: [[String: Any]]) {
        guard !completed else { return }
        completed = true
        cancelTimeout()
        print("[P2P] SignalingReadyHandler: sessionReady sid=\(sessionId.prefix(8))... iceServers=\(iceServers.count)")
        continuation?.resume(returning: iceServers)
        continuation = nil
    }

    func signalingDidReceiveWebRTCMessage(_ message: [String: Any]) {}

    func signalingDidReceiveError(code: String) {
        guard !completed else { return }
        completed = true
        cancelTimeout()
        print("[P2P] SignalingReadyHandler: error code=\(code)")
        continuation?.resume(throwing: P2PError.wsError("p2p_ws_error_\(code)"))
        continuation = nil
    }

    func signalingDidClose() {
        guard !completed else { return }
        completed = true
        cancelTimeout()
        print("[P2P] SignalingReadyHandler: closed")
        continuation?.resume(throwing: P2PError.wsError("p2p_ws_closed"))
        continuation = nil
    }
}

private final class SignalingForwardHandler: WebSocketSignalingDelegate {
    private weak var rtcClient: WebRTCClient?
    private let onClose: () -> Void

    init(rtcClient: WebRTCClient, onClose: @escaping () -> Void) {
        self.rtcClient = rtcClient
        self.onClose = onClose
    }

    func signalingDidReceiveSessionReady(sessionId: String, iceServers: [[String: Any]]) {}

    func signalingDidReceiveWebRTCMessage(_ message: [String: Any]) {
        rtcClient?.handleWsMessage(message)
    }

    func signalingDidReceiveError(code: String) {
        onClose()
    }

    func signalingDidClose() {
        onClose()
    }
}
