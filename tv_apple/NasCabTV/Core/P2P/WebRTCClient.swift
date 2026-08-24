import Foundation
import LiveKitWebRTC

final class WebRTCClient: NSObject {
    let sessionId: String
    let iceServers: [[String: Any]]
    let iceTransportPolicy: String?
    let sendWsJson: ([String: Any]) -> Void

    private var peerConnection: LKRTCPeerConnection?
    private var factory: LKRTCPeerConnectionFactory?
    private var channels: [P2pRtcChannel: DataChannelWrapper] = [:]
    private var heartbeatTimer: Timer?

    // Single continuation + countdown replaces concurrent-dict approach
    private var pendingReadyCount = 0
    private var allReadyContinuation: CheckedContinuation<Void, Error>?
    /// 诊断：各 DataChannel 收到多少条消息（含 binary/text）
    private var diagDcRxCount: [P2pRtcChannel: Int] = [:]

    /// 远端 candidate 可能在 webrtc:answer 的 setRemoteDescription 完成前到达；提前 add 会失败，需排队（对齐服务端 proxyPendingStore）
    private var remoteDescriptionApplied = false
    private var pendingRemoteIceCandidates: [LKRTCIceCandidate] = []

    init(
        sessionId: String,
        iceServers: [[String: Any]],
        iceTransportPolicy: String? = nil,
        sendWsJson: @escaping ([String: Any]) -> Void
    ) {
        self.sessionId = sessionId
        self.iceServers = iceServers
        self.iceTransportPolicy = iceTransportPolicy
        self.sendWsJson = sendWsJson
        super.init()
    }

    /// 是否有进行中的 P2P 请求（与 Flutter `P2pRtcClient.hasPendingRequests` 一致，用于 relay→direct 升级前保护）
    var hasPendingRequests: Bool {
        for (_, wrapper) in channels {
            let s = wrapper.state
            if !s.pending.isEmpty || !s.pendingChunks.isEmpty || !s.pendingStreamContexts.isEmpty {
                return true
            }
        }
        return false
    }

    // MARK: - Start

    func start(channels requestedChannels: [P2pRtcChannel] = [.api, .file, .video]) async throws {
        print("[P2P] WebRTCClient: start channels=\(requestedChannels.map(\.rawValue))")
        let sid = sessionId.trimmingCharacters(in: .whitespaces)
        guard !sid.isEmpty else {
            print("[P2P] WebRTCClient: start invalidSession empty sid")
            throw P2PError.invalidSession
        }

        let rtcIceServers = iceServers.compactMap { serverDict -> LKRTCIceServer? in
            let urls: [String]
            if let urlStr = serverDict["urls"] as? String {
                urls = [urlStr]
            } else if let urlArr = serverDict["urls"] as? [String] {
                urls = urlArr
            } else if let url = serverDict["url"] as? String {
                urls = [url]
            } else {
                return nil
            }
            guard !urls.isEmpty else { return nil }
            let username = serverDict["username"] as? String ?? ""
            let credential = serverDict["credential"] as? String ?? ""
            return LKRTCIceServer(urlStrings: urls, username: username, credential: credential)
        }

        let config = LKRTCConfiguration()
        config.iceServers = rtcIceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        // 与 Flutter createPeerConnection 一致：预热候选池，减轻 relay / IPv6 竞速
        config.iceCandidatePoolSize = 2
        if let policy = iceTransportPolicy?.trimmingCharacters(in: .whitespaces),
           policy == "relay" {
            config.iceTransportPolicy = .relay
        }

        // Pass nil constraints — data-only connection needs no audio/video offer constraints.
        // Passing a dictionary here triggers a crash in the ObjC WebRTC internals that
        // treats the NSDictionary as NSArray<RTCPair *>.
        let emptyConstraints = LKRTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        let fac = LKRTCPeerConnectionFactory()
        factory = fac
        guard let pc = fac.peerConnection(with: config, constraints: emptyConstraints, delegate: self) else {
            throw P2PError.invalidSession
        }
        peerConnection = pc

        for ch in requestedChannels {
            let dcConfig = LKRTCDataChannelConfiguration()
            dcConfig.isOrdered = true
            guard let dc = pc.dataChannel(forLabel: ch.rawValue, configuration: dcConfig) else {
                throw P2PError.invalidSession
            }
            let wrapper = DataChannelWrapper(channel: ch, dataChannel: dc, client: self)
            dc.delegate = wrapper
            channels[ch] = wrapper
        }

        let offer = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LKRTCSessionDescription, Error>) in
            pc.offer(for: emptyConstraints) { sdp, error in
                if let error { cont.resume(throwing: error); return }
                guard let sdp else { cont.resume(throwing: P2PError.invalidSession); return }
                cont.resume(returning: sdp)
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        print("[P2P] WebRTCClient: offer sent, waiting for answer + \(requestedChannels.count)x \(requestedChannels.map(\.rawValue).joined(separator: ",")):ready on DC")
        sendWsJson([
            "type": "webrtc:offer",
            "sessionId": sid,
            "offer": ["type": offer.type.sdpString, "sdp": offer.sdp]
        ])

        // Wait for all channels to signal ready（与 Flutter `p2p_rtc_stub.start` 的 20s 一致；ICE/中继较慢时 3s 易误判失败）
        let expectedCount = requestedChannels.count
        let readyTimeoutNs: UInt64 = 20_000_000_000
        let timeoutTask = Task { [weak self] in
            try await Task.sleep(nanoseconds: readyTimeoutNs)
            DispatchQueue.main.async {
                guard let self else { return }
                if let cont = self.allReadyContinuation {
                    print("[P2P] WebRTCClient: ready timeout 20s fired")
                    self.logReadyDiagnostics(tag: "timeout")
                    self.allReadyContinuation = nil
                    cont.resume(throwing: P2PError.wsError("p2p_ready_timeout"))
                }
            }
        }

        print("[P2P] WebRTCClient: blocking until \(expectedCount) channel(s) receive binary/text :ready (pendingReadyCount=\(expectedCount))")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.pendingReadyCount = expectedCount
            self.allReadyContinuation = cont
        }
        timeoutTask.cancel()
        print("[P2P] WebRTCClient: start done (all channels ready)")
    }

    // MARK: - Handle Signaling Messages

    func handleWsMessage(_ msg: [String: Any]) {
        guard let pc = peerConnection else {
            print("[P2P] WebRTCClient: handleWsMessage dropped (no peerConnection) type=\(msg["type"] ?? "?")")
            return
        }
        let msgType = msg["type"] as? String ?? ""
        let sid = msg["sessionId"] as? String ?? ""
        if msgType == "webrtc:answer" {
            print("[P2P] WebRTCClient: handleWsMessage type=\(msgType) sid=\(sid.prefix(8))... mySid=\(sessionId.prefix(8))...")
        } else if msgType == "webrtc:candidate" {
            print("[P2P] WebRTCClient: handleWsMessage type=\(msgType) sid=\(sid.prefix(8))... mySid=\(sessionId.prefix(8))...")
        }
        // 仅对 webrtc:answer / webrtc:candidate 放宽 sessionId：服务端可能带 device sessionId，必须接受否则无法建链
        let skipBySessionId = !sid.isEmpty && sid != sessionId && msgType != "webrtc:answer" && msgType != "webrtc:candidate"
        if skipBySessionId { return }

        if msgType == "webrtc:answer" {
            // 兼容服务端 JSON 反序列化后 answer 为 NSDictionary 等类型
            let answerAny = msg["answer"]
            let answerDict: [String: Any]? = (answerAny as? [String: Any])
                ?? (answerAny as? NSDictionary).flatMap { $0 as? [String: Any] }
            guard let answer = answerDict else {
                print("[P2P] WebRTCClient: webrtc:answer missing or invalid answer, answer type=\(type(of: answerAny))")
                return
            }
            print("[P2P] WebRTCClient: received webrtc:answer sdpBytes=\(((answer["sdp"] as? String)?.count ?? 0))")
            let sdpType = (answer["type"] as? String) ?? (answer["type"] as? NSString).map(String.init) ?? ""
            let sdp = (answer["sdp"] as? String) ?? (answer["sdp"] as? NSString).map(String.init) ?? ""
            guard !sdpType.isEmpty, !sdp.isEmpty else {
                print("[P2P] WebRTCClient: webrtc:answer empty type or sdp")
                return
            }
            let rtcType = LKRTCSessionDescription.type(for: sdpType)
            let desc = LKRTCSessionDescription(type: rtcType, sdp: sdp)
            DispatchQueue.main.async { [weak self] in
                guard let self, let pc = self.peerConnection else { return }
                let sigBefore = pc.signalingState
                pc.setRemoteDescription(desc) { [weak self] err in
                    guard let self else { return }
                    if let err {
                        print("[P2P] WebRTCClient: setRemoteDescription FAILED err=\(err.localizedDescription) signalingWas=\(String(describing: sigBefore))")
                        self.pendingRemoteIceCandidates.removeAll()
                    } else {
                        self.remoteDescriptionApplied = true
                        print("[P2P] WebRTCClient: setRemoteDescription OK signalingNow=\(String(describing: pc.signalingState)) ice=\(String(describing: pc.iceConnectionState)) pendingRemoteIce=\(self.pendingRemoteIceCandidates.count)")
                        self.flushPendingRemoteIceCandidates()
                    }
                }
            }
        }

        if msgType == "webrtc:candidate", let c = msg["candidate"] as? [String: Any] {
            let candidate = c["candidate"] as? String ?? ""
            guard !candidate.isEmpty else { return }
            let rawMid = c["sdpMid"] as? String
            let sdpMidForIce: String? = {
                guard let m = rawMid else { return nil }
                let t = m.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }()
            let sdpMLineIndex: Int32
            if let idx = c["sdpMLineIndex"] as? Int {
                sdpMLineIndex = Int32(idx)
            } else if let idx = c["sdpMLineIndex"] as? Int32 {
                sdpMLineIndex = idx
            } else {
                sdpMLineIndex = 0
            }
            let iceCandidate = LKRTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMidForIce)
            DispatchQueue.main.async { [weak self] in
                self?.enqueueOrAddRemoteIceCandidate(iceCandidate, candPrefix: String(candidate.prefix(48)))
            }
        }
    }

    private func enqueueOrAddRemoteIceCandidate(_ ice: LKRTCIceCandidate, candPrefix: String) {
        guard peerConnection != nil else { return }
        if !remoteDescriptionApplied {
            pendingRemoteIceCandidates.append(ice)
            print("[P2P] WebRTCClient: queue remote ICE (awaiting setRemoteDescription) pending=\(pendingRemoteIceCandidates.count) candPrefix=\(candPrefix)...")
            return
        }
        addRemoteIceCandidateNow(ice, candPrefix: candPrefix)
    }

    private func flushPendingRemoteIceCandidates() {
        guard !pendingRemoteIceCandidates.isEmpty else { return }
        let q = pendingRemoteIceCandidates
        pendingRemoteIceCandidates.removeAll()
        print("[P2P] WebRTCClient: applying \(q.count) queued remote ICE candidates")
        for ice in q {
            addRemoteIceCandidateNow(ice, candPrefix: String(ice.sdp.prefix(48)))
        }
    }

    private func addRemoteIceCandidateNow(_ ice: LKRTCIceCandidate, candPrefix: String) {
        guard let pc = peerConnection else { return }
        let sig = pc.signalingState
        pc.add(ice) { err in
            if let err {
                print("[P2P] WebRTCClient: addIceCandidate FAILED err=\(err.localizedDescription) signaling=\(String(describing: sig)) ice=\(String(describing: pc.iceConnectionState)) candPrefix=\(candPrefix)...")
            }
        }
    }

    /// 超时或排查时打印：信令/ICE、各 DC 状态、是否收到过 DC 消息、是否已收到 :ready
    private func logReadyDiagnostics(tag: String) {
        guard let pc = peerConnection else {
            print("[P2P] WebRTCClient: diagnostics [\(tag)] peerConnection=nil pendingReadyCount=\(pendingReadyCount)")
            return
        }
        print("[P2P] WebRTCClient: diagnostics [\(tag)] pendingReadyCount=\(pendingReadyCount) signaling=\(String(describing: pc.signalingState)) ice=\(String(describing: pc.iceConnectionState)) gathering=\(String(describing: pc.iceGatheringState))")
        let order = [P2pRtcChannel.api, .file, .video].filter { channels[$0] != nil }
        for ch in order {
            guard let wrap = channels[ch] else { continue }
            let rs = wrap.dataChannel.readyState
            let rx = diagDcRxCount[ch] ?? 0
            print("[P2P] WebRTCClient: diagnostics [\(tag)] ch=\(ch.rawValue) dcState=\(String(describing: rs)) appReady=\(wrap.state.isReady) dcRxMsgs=\(rx)")
        }
    }

    // MARK: - Send Request

    /// 流式请求：边收边通过 AsyncStream 下发，用于视频/大文件，避免整 body 进内存。
    func sendStreamRequest(
        channel: P2pRtcChannel,
        method: String,
        path: String,
        headers: [String: String],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 300
    ) -> AsyncThrowingStream<P2pStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let wrapper = channels[channel], wrapper.state.isReady else {
                continuation.finish(throwing: P2PError.notConnected)
                return
            }
            let dc = wrapper.dataChannel
            let prefix = channel.rawValue
            let id = P2pRequestId.generate()

            var safeHeaders = headers
            safeHeaders.removeValue(forKey: "Host")
            safeHeaders.removeValue(forKey: "host")
            safeHeaders.removeValue(forKey: "Content-Length")
            safeHeaders.removeValue(forKey: "content-length")

            wrapper.state.pendingStreamContexts[id] = P2pStreamContext(continuation: continuation)

            if bodyBytes.isEmpty {
                sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .req, payload: [
                    "id": id, "method": method, "path": path, "headers": safeHeaders
                ])
            } else {
                sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .reqBegin, payload: [
                    "id": id, "method": method, "path": path, "headers": safeHeaders,
                    "length": bodyBytes.count
                ])
                let header = P2pBinaryFrame.buildHeader(version: P2pBinaryFrame.versionV1, requestId: id)
                var offset = 0
                while offset < bodyBytes.count {
                    let end = min(offset + P2pBinaryFrame.chunkSize, bodyBytes.count)
                    let piece = bodyBytes[offset..<end]
                    var packet = Data(capacity: header.count + piece.count)
                    packet.append(header)
                    packet.append(piece)
                    sendBinary(on: dc, state: wrapper.state, data: packet)
                    offset = end
                }
                sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .reqEnd, payload: ["id": id])
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let streamCtx = wrapper.state.pendingStreamContexts.removeValue(forKey: id) {
                    streamCtx.continuation.finish(throwing: P2PError.wsError("p2p_timeout"))
                }
            }
        }
    }

    func sendRequest(
        channel: P2pRtcChannel,
        method: String,
        path: String,
        headers: [String: String],
        bodyBytes: Data = Data(),
        timeout: TimeInterval = 300
    ) async throws -> P2pApiResponse {
        guard let wrapper = channels[channel] else {
            throw P2PError.notConnected
        }
        guard wrapper.state.isReady else {
            throw P2PError.notConnected
        }
        let dc = wrapper.dataChannel
        let prefix = channel.rawValue
        let id = P2pRequestId.generate()

        var safeHeaders = headers
        safeHeaders.removeValue(forKey: "Host")
        safeHeaders.removeValue(forKey: "host")
        safeHeaders.removeValue(forKey: "Content-Length")
        safeHeaders.removeValue(forKey: "content-length")

        return try await withCheckedThrowingContinuation { cont in
            wrapper.state.pending[id] = cont

            Task {
                do {
                    if bodyBytes.isEmpty {
                        self.sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .req, payload: [
                            "id": id, "method": method, "path": path, "headers": safeHeaders
                        ])
                    } else {
                        self.sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .reqBegin, payload: [
                            "id": id, "method": method, "path": path, "headers": safeHeaders,
                            "length": bodyBytes.count
                        ])

                        let header = P2pBinaryFrame.buildHeader(version: P2pBinaryFrame.versionV1, requestId: id)
                        var offset = 0
                        while offset < bodyBytes.count {
                            let end = min(offset + P2pBinaryFrame.chunkSize, bodyBytes.count)
                            let piece = bodyBytes[offset..<end]
                            var packet = Data(capacity: header.count + piece.count)
                            packet.append(header)
                            packet.append(piece)
                            self.sendBinary(on: dc, state: wrapper.state, data: packet)
                            offset = end
                        }

                        self.sendControl(on: dc, state: wrapper.state, prefix: prefix, type: .reqEnd, payload: ["id": id])
                    }

                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        if let pendingCont = wrapper.state.pending.removeValue(forKey: id) {
                            wrapper.state.pendingChunks.removeValue(forKey: id)
                            pendingCont.resume(throwing: P2PError.wsError("p2p_timeout"))
                        }
                    }
                } catch {
                    wrapper.state.pending.removeValue(forKey: id)
                    wrapper.state.pendingChunks.removeValue(forKey: id)
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Transport Stats (for relay vs direct detection)

    /// Returns transport stats; key "type" is the local candidate type: "host", "srflx", "prflx", "relay".
    func getTransportStats() async -> [String: String] {
        guard let pc = peerConnection else { return [:] }
        return await withCheckedContinuation { cont in
            pc.statistics { report in
                var out: [String: String] = [:]
                let stats = report.statistics
                guard let pair = stats.values.first(where: { stat in
                    (stat.type == "candidate-pair" || stat.type == "transport") &&
                    (stat.values["state"] as? String == "succeeded" || stat.values["state"] as? String == "connected")
                }) ?? stats.values.first(where: { $0.type == "candidate-pair" }) else {
                    cont.resume(returning: out)
                    return
                }
                if let localId = pair.values["localCandidateId"] as? String,
                   let local = stats[localId] {
                    let candidateType = (local.values["candidateType"] as? String) ?? (local.values["type"] as? String) ?? ""
                    if !candidateType.isEmpty {
                        out["type"] = candidateType
                    }
                }
                cont.resume(returning: out)
            }
        }
    }

    // MARK: - Close

    func close() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        if let cont = allReadyContinuation {
            allReadyContinuation = nil
            cont.resume(throwing: P2PError.wsError("p2p_closed"))
        }
        pendingReadyCount = 0
        remoteDescriptionApplied = false
        pendingRemoteIceCandidates.removeAll()

        for (_, wrapper) in channels {
            wrapper.dataChannel.close()
            for (_, cont) in wrapper.state.pending {
                cont.resume(throwing: P2PError.wsError("p2p_closed"))
            }
            wrapper.state.pending.removeAll()
            wrapper.state.pendingChunks.removeAll()
            for (_, streamCtx) in wrapper.state.pendingStreamContexts {
                streamCtx.continuation.finish(throwing: P2PError.wsError("p2p_closed"))
            }
            wrapper.state.pendingStreamContexts.removeAll()
        }
        channels.removeAll()

        peerConnection?.close()
        peerConnection = nil
        factory = nil
    }

    // MARK: - Internal Message Handling

    fileprivate func onChannelOpen(_ channel: P2pRtcChannel) {
        guard let wrap = channels[channel] else { return }
        print("[P2P] WebRTCClient: DataChannel OPEN label=\(channel.rawValue) readyState=\(String(describing: wrap.dataChannel.readyState)) ice=\(peerConnection.map { String(describing: $0.iceConnectionState) } ?? "nil") pendingReady=\(pendingReadyCount)")
    }

    fileprivate func onChannelClosed(_ channel: P2pRtcChannel) {
        guard let wrapper = channels[channel] else { return }
        for (_, cont) in wrapper.state.pending {
            cont.resume(throwing: P2PError.wsError("p2p_dc_closed"))
        }
        wrapper.state.pending.removeAll()
        wrapper.state.pendingChunks.removeAll()
        for (_, streamCtx) in wrapper.state.pendingStreamContexts {
            streamCtx.continuation.finish(throwing: P2PError.wsError("p2p_dc_closed"))
        }
        wrapper.state.pendingStreamContexts.removeAll()

        if let cont = allReadyContinuation {
            allReadyContinuation = nil
            cont.resume(throwing: P2PError.wsError("p2p_dc_closed"))
        }
    }

    fileprivate func onChannelMessage(_ channel: P2pRtcChannel, buffer: LKRTCDataBuffer) {
        guard let wrapper = channels[channel] else { return }
        let state = wrapper.state
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        state.rxPackets += 1
        state.rxBytes += buffer.data.count
        state.lastRxAtMs = nowMs
        diagDcRxCount[channel, default: 0] += 1
        let n = diagDcRxCount[channel] ?? 0

        let bytes = buffer.data
        if buffer.isBinary {
            // 优先识别紧凑二进制控制消息（与服务端 p2pConnectWorker 一致）
            if P2pControlBinary.isControl(bytes) {
                if let msg = P2pControlBinary.decodeControl(bytes, prefix: state.prefix) {
                    let t = msg["type"] as? String ?? "?"
                    if n <= 5 || t.hasSuffix(":ready") {
                        print("[P2P] WebRTCClient: DC rx[\(channel.rawValue)] #\(n) control decoded type=\(t) bytes=\(bytes.count)")
                    }
                    onChannelJsonMessage(state, msg: msg, dc: wrapper.dataChannel)
                } else {
                    let head = bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("[P2P] WebRTCClient: DC rx[\(channel.rawValue)] #\(n) control MAGIC ok but decodeControl=nil bytes=\(bytes.count) head=\(head)")
                }
                return
            }
            // 再识别 chunk 格式：V1=0x01
            if bytes.count > 0 && bytes[0] == 0x01 {
                if n <= 3 {
                    print("[P2P] WebRTCClient: DC rx[\(channel.rawValue)] #\(n) chunk v1 bytes=\(bytes.count)")
                }
                handleBinaryChunk(state, bytes: bytes, dc: wrapper.dataChannel)
                return
            }
            // 兼容旧版 JSON over binary
            guard let text = String(data: bytes, encoding: .utf8), !text.isEmpty else { return }
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if n <= 5 {
                let ty = json["type"] as? String ?? "?"
                print("[P2P] WebRTCClient: DC rx[\(channel.rawValue)] #\(n) json-in-binary type=\(ty) bytes=\(bytes.count)")
            }
            onChannelJsonMessage(state, msg: json, dc: wrapper.dataChannel)
        } else {
            guard let text = String(data: buffer.data, encoding: .utf8), !text.isEmpty else { return }
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            if n <= 5 {
                let ty = json["type"] as? String ?? "?"
                print("[P2P] WebRTCClient: DC rx[\(channel.rawValue)] #\(n) text-json type=\(ty)")
            }
            onChannelJsonMessage(state, msg: json, dc: wrapper.dataChannel)
        }
    }

    private func onChannelJsonMessage(_ state: RtcChannelState, msg: [String: Any], dc: LKRTCDataChannel) {
        let prefix = state.prefix
        let type = msg["type"] as? String ?? ""

        if type == "\(prefix):ready" {
            print("[P2P] WebRTCClient: channel \(prefix) :ready received pendingReadyCount before=\(pendingReadyCount)")
            state.isReady = true

            // Countdown: when all channels ready, resume the single continuation
            pendingReadyCount = max(0, pendingReadyCount - 1)
            print("[P2P] WebRTCClient: channel \(prefix) :ready pendingReadyCount after=\(pendingReadyCount)")
            if pendingReadyCount == 0, let cont = allReadyContinuation {
                print("[P2P] WebRTCClient: all channels ready, resuming")
                allReadyContinuation = nil
                cont.resume()
            }

            startHeartbeatIfNeeded()
            return
        }

        // 诊断：收到了 DC 消息但不是本通道的 :ready（例如错通道、协议不匹配）
        if !type.isEmpty, !type.hasPrefix("\(prefix):"), allReadyContinuation != nil {
            print("[P2P] WebRTCClient: DC msg unexpected type=\(type) expectedPrefix=\(prefix):… (still waiting :ready)")
        }

        if type == "\(prefix):ping" {
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            sendControl(on: dc, state: state, prefix: prefix, type: .pong, payload: ["ts": ts])
            return
        }
        if type == "\(prefix):pong" { return }

        if type == "\(prefix):res:begin" {
            let id = msg["id"] as? String ?? ""
            guard !id.isEmpty else { return }
            let status = (msg["status"] as? Int) ?? 500
            var headers = [String: String]()
            if let raw = msg["headers"] as? [String: Any] {
                for (k, v) in raw {
                    let key = k.trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty else { continue }
                    headers[key.lowercased()] = "\(v)"
                }
            }
            if let streamCtx = state.pendingStreamContexts[id] {
                streamCtx.continuation.yield(.response(status: status, headers: headers, id: id))
                return
            }
            guard state.pending[id] != nil else { return }
            state.pendingChunks[id] = PendingChunk(status: status, headers: headers)
            return
        }

        if type == "\(prefix):res:end" {
            let id = msg["id"] as? String ?? ""
            guard !id.isEmpty else { return }
            if let streamCtx = state.pendingStreamContexts.removeValue(forKey: id) {
                streamCtx.continuation.yield(.end)
                streamCtx.continuation.finish()
                return
            }
            guard let chunk = state.pendingChunks.removeValue(forKey: id) else { return }
            guard let cont = state.pending.removeValue(forKey: id) else { return }

            cont.resume(returning: P2pApiResponse(status: chunk.status, headers: chunk.headers, bodyBytes: chunk.builder))
            return
        }
    }

    private func handleBinaryChunk(_ state: RtcChannelState, bytes: Data, dc: LKRTCDataChannel) {
        guard let frame = P2pBinaryFrame.parse(bytes) else { return }

        if let streamCtx = state.pendingStreamContexts[frame.requestId] {
            let payload = frame.payload
            let wireBytes = frame.payload.count
            if !payload.isEmpty, wireBytes > 0 {
                streamCtx.continuation.yield(.chunk(data: payload, id: frame.requestId, wireBytes: wireBytes))
            }
            return
        }

        guard let chunk = state.pendingChunks[frame.requestId] else { return }
        chunk.builder.append(frame.payload)
    }

    func sendStreamAck(channel: P2pRtcChannel, id: String, delta: Int) {
        guard delta > 0, !id.isEmpty else { return }
        guard let wrapper = channels[channel] else { return }
        let dc = wrapper.dataChannel
        let state = wrapper.state
        guard dc.readyState == .open else { return }
        sendControl(on: dc, state: state, prefix: state.prefix, type: .ack, payload: [
            "id": id,
            "delta": delta
        ])
    }

    /// 取消流式请求，通知后端停止发送并让本地消费端立即退出
    func sendCancel(channel: P2pRtcChannel, id: String) {
        guard let wrapper = channels[channel], !id.isEmpty else { return }
        let prefix = channel.rawValue
        if wrapper.dataChannel.readyState == .open {
            sendControl(on: wrapper.dataChannel, state: wrapper.state, prefix: prefix, type: .cancel, payload: ["id": id])
        }
        if let streamCtx = wrapper.state.pendingStreamContexts.removeValue(forKey: id) {
            streamCtx.continuation.finish(throwing: P2PError.wsError("p2p_stream_cancelled"))
        }
    }

    // MARK: - Send Helpers

    /// 发送紧凑二进制控制消息（与服务端 dataChannelProxy 一致）
    private func sendControl(on dc: LKRTCDataChannel, state: RtcChannelState, prefix: String, type: P2pControlBinary.ControlType, payload: [String: Any]) {
        guard let data = P2pControlBinary.encodeControl(prefix: prefix, type: type, payload: payload) else { return }
        let buffer = LKRTCDataBuffer(data: data, isBinary: true)
        dc.sendData(buffer)
        state.txPackets += 1
        state.txBytes += data.count
        state.lastTxAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func sendJson(on dc: LKRTCDataChannel, state: RtcChannelState, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let buffer = LKRTCDataBuffer(data: data, isBinary: false)
        dc.sendData(buffer)
        state.txPackets += 1
        state.txBytes += data.count
        state.lastTxAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func sendBinary(on dc: LKRTCDataChannel, state: RtcChannelState, data: Data) {
        let buffer = LKRTCDataBuffer(data: data, isBinary: true)
        dc.sendData(buffer)
        state.txPackets += 1
        state.txBytes += data.count
        state.lastTxAtMs = Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func startHeartbeatIfNeeded() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            for (_, wrapper) in self.channels {
                guard wrapper.state.isReady else { continue }
                self.sendControl(on: wrapper.dataChannel, state: wrapper.state, prefix: wrapper.state.prefix, type: .ping, payload: ["ts": nowMs])
            }
        }
    }
}

// MARK: - LKRTCPeerConnectionDelegate

extension WebRTCClient: LKRTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {
        print("[P2P] WebRTCClient: ICE state -> \(String(describing: newState)) signaling=\(String(describing: peerConnection.signalingState)) pendingReady=\(pendingReadyCount)")
        if newState == .failed || newState == .closed || newState == .disconnected {
            DispatchQueue.main.async { [weak self] in
                self?.logReadyDiagnostics(tag: "ice_\(String(describing: newState))")
                self?.close()
            }
        }
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        let candidateStr = candidate.sdp
        guard !candidateStr.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sdpMid = candidate.sdpMid
        let sdpMLineIndex = candidate.sdpMLineIndex
        let sid = sessionId
        // 与 Flutter p2p_rtc_stub：中继 typ relay 延迟 4s，便于直连优先；仅 TURN/relay 模式则立即发送
        let skipRelayDelay = (iceTransportPolicy?.trimmingCharacters(in: .whitespaces).lowercased() == "relay")
        if !skipRelayDelay, Self.isRelayTypCandidate(sdp: candidateStr) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, let pc = self.peerConnection else { return }
                if pc.connectionState == .connected {
                    print("[P2P] WebRTCClient: skip delayed relay ICE (already connected) sid=\(sid.prefix(8))...")
                    return
                }
                self.sendLocalIceCandidate(sdp: candidateStr, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sessionId: sid)
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.sendLocalIceCandidate(sdp: candidateStr, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, sessionId: sid)
        }
    }

    private func sendLocalIceCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32, sessionId sid: String) {
        var midOut: String = ""
        if let m = sdpMid?.trimmingCharacters(in: .whitespaces), !m.isEmpty {
            midOut = m
        }
        sendWsJson([
            "type": "webrtc:candidate",
            "sessionId": sid,
            "candidate": [
                "candidate": sdp,
                "sdpMid": midOut,
                "sdpMLineIndex": sdpMLineIndex
            ]
        ])
    }

    /// ICE candidate 单行里含 `typ relay` 即为 TURN 中继候选
    private static func isRelayTypCandidate(sdp: String) -> Bool {
        sdp.range(of: " typ relay", options: .caseInsensitive) != nil
    }

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}

    func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}
}

// MARK: - DataChannelWrapper (LKRTCDataChannelDelegate)

private final class DataChannelWrapper: NSObject, LKRTCDataChannelDelegate {
    let channel: P2pRtcChannel
    let dataChannel: LKRTCDataChannel
    let state: RtcChannelState
    private weak var client: WebRTCClient?

    init(channel: P2pRtcChannel, dataChannel: LKRTCDataChannel, client: WebRTCClient) {
        self.channel = channel
        self.dataChannel = dataChannel
        self.state = RtcChannelState(channel: channel)
        self.client = client
        super.init()
    }

    func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
        let readyState = dataChannel.readyState
        let ch = channel
        let label = dataChannel.label ?? "?"
        print("[P2P] WebRTCClient: DataChannel stateChange label=\(label) channel=\(ch.rawValue) -> \(String(describing: readyState))")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch readyState {
            case .open:
                self.client?.onChannelOpen(ch)
            case .closed:
                self.client?.onChannelClosed(ch)
            default:
                break
            }
        }
    }

    func dataChannel(_ dataChannel: LKRTCDataChannel, didReceiveMessageWith buffer: LKRTCDataBuffer) {
        // Copy data before dispatching — the buffer object may be reused by WebRTC
        let dataCopy = Data(buffer.data)
        let isBinary = buffer.isBinary
        let ch = channel
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let copiedBuffer = LKRTCDataBuffer(data: dataCopy, isBinary: isBinary)
            self.client?.onChannelMessage(ch, buffer: copiedBuffer)
        }
    }
}

// MARK: - SDP Type Helper

private extension LKRTCSdpType {
    var sdpString: String {
        switch self {
        case .offer: return "offer"
        case .prAnswer: return "prAnswer"
        case .answer: return "answer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }
}
