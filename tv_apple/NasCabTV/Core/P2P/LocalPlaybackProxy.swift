import Foundation
import Network

/// 本地 HTTP 代理：在 P2P 模式下将播放器发出的 HTTP 请求（原片、转码、HLS 分片等）转发到 P2PService，
/// 使 VLC 等使用自有网络栈的播放器能通过 WebRTC 通道正常拉流。
@MainActor
final class LocalPlaybackProxy: ObservableObject {
    static let shared = LocalPlaybackProxy()

    @Published private(set) var isRunning = false
    @Published private(set) var port: Int?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "nascab.localplaybackproxy.queue", qos: .userInitiated)

    private init() {}

    /// 在 127.0.0.1 上启动代理，端口由系统分配。仅在 P2P 模式下需要调用。
    func start() {
        guard !isRunning else { return }
        guard APIClient.shared.isP2pMode else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params, on: 0)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            self.port = Int(port)
                            self.isRunning = true
                            print("[P2P] LocalPlaybackProxy: listening on 127.0.0.1:\(port)")
                        }
                    case .failed(let error):
                        print("[P2P] LocalPlaybackProxy: listener failed \(error)")
                        self.stop()
                    case .cancelled:
                        self.isRunning = false
                        self.port = nil
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in
                    await self?.handle(connection: conn)
                }
            }

            listener.start(queue: queue)
        } catch {
            print("[P2P] LocalPlaybackProxy: start failed \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = nil
    }

    /// 当 P2P 断开时调用，停止代理
    func stopIfNeeded() {
        if !APIClient.shared.isP2pMode {
            stop()
        }
    }

    /// 用于构建播放器 URL 的 base（不含末尾斜杠）。P2P 模式下且代理已启动时返回 http://127.0.0.1:port，否则返回 nil。
    var baseURL: String? {
        guard APIClient.shared.isP2pMode, isRunning, let p = port else { return nil }
        return "http://127.0.0.1:\(p)"
    }

    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed(_):
                return
            default:
                break
            }
        }
        connection.start(queue: queue)

        var buffer = Data()
        var readRequest: (() -> Void)?
        readRequest = { [weak self] in
            guard let self else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let error = error {
                    print("[P2P] LocalPlaybackProxy: connection receive error \(error)")
                    connection.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                }

                guard let (method, path, headers, body) = self.parseRequest(buffer) else {
                    if isComplete || (data?.isEmpty == true && !buffer.isEmpty) {
                        self.sendError(connection: connection, status: 400, message: "Bad Request")
                        connection.cancel()
                    } else {
                        readRequest?()
                    }
                    return
                }

                Task { @MainActor in
                    await self.forwardAndRespond(connection: connection, method: method, path: path, headers: headers, body: body)
                }
            }
        }
        readRequest?()
    }

    private func parseRequest(_ data: Data) -> (method: String, path: String, headers: [String: String], body: Data)? {
        let sep = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: sep) else { return nil }
        let headerData = data[..<range.lowerBound]
        let bodyStart = range.upperBound
        guard let headerBlock = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard requestLine.count >= 2 else { return nil }
        let method = String(requestLine[0]).uppercased()
        let path = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let idx = line.firstIndex(of: ":")
            guard let idx else { continue }
            let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = headers["content-length"].flatMap { Int($0) } ?? 0
        if contentLength > 0 {
            let bodyEnd = bodyStart + contentLength
            guard data.count >= bodyEnd else { return nil }
            let body = data.subdata(in: bodyStart..<bodyEnd)
            return (method, path, headers, body)
        }
        return (method, path, headers, Data())
    }

    private func forwardAndRespond(connection: NWConnection, method: String, path: String, headers: [String: String], body: Data) async {
        let p2pPath = path.hasPrefix("/") ? path : "/" + path
        let pathForLog = (p2pPath as NSString).length > 80 ? String(p2pPath.prefix(80)) + "..." : p2pPath
        print("[P2P] LocalPlaybackProxy: request \(method) \(pathForLog)")

        do {
            if method == "POST" {
                let reqHeaders = ["Content-Type": headers["content-type"] ?? "application/json"]
                let response = try await P2PService.shared.sendApiRequest(
                    method: method,
                    path: p2pPath,
                    headers: reqHeaders,
                    bodyBytes: body,
                    timeout: 60
                )
                let responseData = buildHTTPResponse(status: response.status, headers: response.headers, body: response.bodyBytes)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let isLongRequest = isLongPlaybackRequest(path: p2pPath, headers: headers)
            if APIClient.shared.isP2pMode {
                let ok = await P2PService.shared.ensureConnected(timeout: isLongRequest ? 12 : 1.5)
                if !ok {
                    sendError(connection: connection, status: 503, message: "P2P not ready")
                    connection.cancel()
                    return
                }
            }

            // GET/HEAD：使用流式请求，边收边转发给播放器，避免大视频整 body 进内存（与 Flutter sendP2pStreamRequest 一致）
            let p2pHeaders = buildP2pRequestHeaders(path: p2pPath, headers: headers)
            print("[P2P] LocalPlaybackProxy: \(method) stream start path=\(pathForLog)")
            let streamChannel = preferredStreamChannel(path: p2pPath, headers: headers)
            let stream: AsyncThrowingStream<P2pStreamEvent, Error> = (streamChannel == .video)
                ? P2PService.shared.sendVideoStreamRequest(
                    method: method,
                    path: p2pPath,
                    headers: p2pHeaders,
                    bodyBytes: Data(),
                    timeout: 600
                )
                : P2PService.shared.sendFileStreamRequest(
                    method: method,
                    path: p2pPath,
                    headers: p2pHeaders,
                    bodyBytes: Data(),
                    timeout: 600
                )

            var responseStatus = 0
            var responseHeaders: [String: String] = [:]
            var responseHeadersLower: [String: String] = [:]
            var headerSent = false
            var shouldChunked = false
            var chunkCount = 0
            var streamRequestId: String?
            defer {
                if let id = streamRequestId {
                    Task { @MainActor in
                        P2PService.shared.cancelStreamRequest(channel: streamChannel, id: id)
                    }
                }
            }

            for try await event in stream {
                switch event {
                case .response(let status, let headers, let id):
                    streamRequestId = id
                    responseStatus = status
                    responseHeaders = headers
                    responseHeadersLower = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
                    print("[P2P] LocalPlaybackProxy: stream response status=\(status) path=\(pathForLog)")
                    // 与 Android P2pLocalHttpProxy.normalizeResponseHeaders 一致：
                    // 当 206 仅返回 Content-Range 而无 Content-Length 时，从 Content-Range 计算长度，避免使用 chunked，
                    // 提高部分播放器（包括 KSPlayer/AVFoundation）对分段响应的兼容性。
                    if responseStatus == 206,
                       responseHeadersLower["content-length"] == nil,
                       let crRaw = responseHeadersLower["content-range"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                       crRaw.lowercased().hasPrefix("bytes") {
                        let afterBytes = crRaw.replacingOccurrences(of: "bytes", with: "", options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let rangePart = afterBytes.split(separator: "/").first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if let dashIndex = rangePart.firstIndex(of: "-") {
                            let startStr = String(rangePart[..<dashIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                            let endStr = String(rangePart[rangePart.index(after: dashIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let start = Int(startStr), let end = Int(endStr), end >= start {
                                let length = end - start + 1
                                let lenStr = String(length)
                                responseHeaders["Content-Length"] = lenStr
                                responseHeadersLower["content-length"] = lenStr
                            }
                        }
                    }
                    if method == "HEAD" {
                        let statusLine = "HTTP/1.1 \(status) \(statusText(status))\r\n"
                        var headerBlock = statusLine
                        for (k, v) in headers {
                            let lk = k.lowercased()
                            if lk == "transfer-encoding" { continue }
                            if lk == "connection" { continue }
                            headerBlock += "\(k): \(v)\r\n"
                        }
                        if responseHeadersLower["accept-ranges"] == nil,
                           (p2pPath.hasPrefix("/api/file/rawFile") || p2pPath.hasPrefix("/api/videoPlayer/")) {
                            headerBlock += "Accept-Ranges: bytes\r\n"
                        }
                        headerBlock += "Connection: close\r\n"
                        headerBlock += "\r\n"
                        if let data = headerBlock.data(using: .utf8) {
                            guard await sendAndWait(connection: connection, data: data) else {
                                print("[P2P] LocalPlaybackProxy: send headers failed (connection closed) path=\(pathForLog)")
                                connection.cancel()
                                return
                            }
                        }
                        connection.cancel()
                        return
                    }
                case .chunk(let data, let id, let wireBytes):
                    guard !data.isEmpty, wireBytes > 0 else { continue }
                    if !headerSent {
                        let clRaw = responseHeadersLower["content-length"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let cl = Int(clRaw) ?? -1
                        let hasContentLength = cl > 0
                        shouldChunked = !hasContentLength
                        let statusLine = "HTTP/1.1 \(responseStatus) \(statusText(responseStatus))\r\n"
                        var headerBlock = statusLine
                        for (k, v) in responseHeaders {
                            let lk = k.lowercased()
                            if lk == "transfer-encoding" { continue }
                            if lk == "connection" { continue }
                            if shouldChunked && lk == "content-length" { continue }
                            headerBlock += "\(k): \(v)\r\n"
                        }
                        if responseHeadersLower["accept-ranges"] == nil,
                           (p2pPath.hasPrefix("/api/file/rawFile") || p2pPath.hasPrefix("/api/videoPlayer/")) {
                            headerBlock += "Accept-Ranges: bytes\r\n"
                        }
                        if shouldChunked {
                            headerBlock += "Transfer-Encoding: chunked\r\n"
                        }
                        headerBlock += "Connection: close\r\n"
                        headerBlock += "\r\n"
                        if let headerData = headerBlock.data(using: .utf8) {
                            guard await sendAndWait(connection: connection, data: headerData) else {
                                print("[P2P] LocalPlaybackProxy: send headers failed (connection closed) path=\(pathForLog)")
                                connection.cancel()
                                return
                            }
                        }
                        headerSent = true
                    }
                    chunkCount += 1
                    if chunkCount == 1 {
                        print("[P2P] LocalPlaybackProxy: first chunk size=\(data.count) path=\(pathForLog)")
                    }
                    let toSend: Data
                    if !shouldChunked {
                        toSend = data
                    } else {
                        let chunkHeader = String(format: "%x\r\n", data.count)
                        var chunkData = Data(chunkHeader.utf8)
                        chunkData.append(data)
                        chunkData.append(Data("\r\n".utf8))
                        toSend = chunkData
                    }
                    // 前 2 个 chunk 同步写出，确保播放器尽快收到首包，避免 VLC 在“首包未完全写出”时超时关闭
                    if chunkCount <= 2 {
                        guard await sendAndWait(connection: connection, data: toSend) else {
                            print("[P2P] LocalPlaybackProxy: send chunk \(chunkCount) failed (connection closed) path=\(pathForLog)")
                            connection.cancel()
                            return
                        }
                        P2PService.shared.sendStreamAck(channel: streamChannel, id: id, delta: wireBytes)
                    } else {
                        guard await sendAndWait(connection: connection, data: toSend) else {
                            print("[P2P] LocalPlaybackProxy: send chunk \(chunkCount) failed (connection closed) path=\(pathForLog)")
                            connection.cancel()
                            return
                        }
                        P2PService.shared.sendStreamAck(channel: streamChannel, id: id, delta: wireBytes)
                    }
                case .end:
                    print("[P2P] LocalPlaybackProxy: stream end chunks=\(chunkCount) path=\(pathForLog)")
                    streamRequestId = nil
                    if !headerSent {
                        let statusLine = "HTTP/1.1 \(responseStatus) \(statusText(responseStatus))\r\n"
                        var headerBlock = statusLine
                        for (k, v) in responseHeaders {
                            let lk = k.lowercased()
                            if lk == "transfer-encoding" { continue }
                            if lk == "connection" { continue }
                            headerBlock += "\(k): \(v)\r\n"
                        }
                        if responseHeadersLower["accept-ranges"] == nil,
                           (p2pPath.hasPrefix("/api/file/rawFile") || p2pPath.hasPrefix("/api/videoPlayer/")) {
                            headerBlock += "Accept-Ranges: bytes\r\n"
                        }
                        headerBlock += "Content-Length: 0\r\n"
                        headerBlock += "Connection: close\r\n"
                        headerBlock += "\r\n"
                        if let headerData = headerBlock.data(using: .utf8) {
                            _ = await sendAndWait(connection: connection, data: headerData)
                        }
                        headerSent = true
                    }
                    if shouldChunked {
                        _ = await sendAndWait(connection: connection, data: Data("0\r\n\r\n".utf8))
                    }
                    connection.cancel()
                    return
                }
            }
            print("[P2P] LocalPlaybackProxy: stream finished without .end path=\(pathForLog)")
            if !headerSent {
                sendError(connection: connection, status: 502, message: "Proxy stream ended without response")
            }
            connection.cancel()
        } catch {
            print("[P2P] LocalPlaybackProxy: proxy error path=\(pathForLog) error=\(error)")
            sendError(connection: connection, status: 502, message: "Proxy error: \(error.localizedDescription)")
            connection.cancel()
        }
    }

    private func preferredStreamChannel(path: String, headers: [String: String]) -> P2pRtcChannel {
        if parseP2pChannelMark(path: path) == "video" { return .video }
        if path.hasPrefix("/api/videoPlayer/") { return .video }
        if path.hasPrefix("/api/file/rawFile") { return .video }
        if headers["range"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return .video }
        return .file
    }

    private func parseP2pChannelMark(path: String) -> String? {
        guard let comps = URLComponents(string: "http://127.0.0.1\(path)") else { return nil }
        let v = comps.queryItems?.first(where: { $0.name.lowercased() == "p2pchannel" })?.value
        let out = v?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (out?.isEmpty == false) ? out : nil
    }

    private func isLongPlaybackRequest(path: String, headers: [String: String]) -> Bool {
        if path.hasPrefix("/api/videoPlayer/") { return true }
        if path.hasPrefix("/api/file/rawFile") { return true }
        if headers["range"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return true }
        return false
    }

    /// 等待本次 send 完成后再继续；返回 false 表示连接已断（对端关闭等），调用方应停止后续发送并避免再写。
    private func sendAndWait(connection: NWConnection, data: Data) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            connection.send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: error == nil)
            })
        }
    }

    /// 构建 P2P 请求头：补充 Authorization（与 Flutter _proxyViaP2p 一致）
    private func buildP2pRequestHeaders(path: String, headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            let lk = k.lowercased()
            if lk == "host" { continue }
            if lk == "content-length" { continue }
            if lk == "connection" { continue }
            out[k] = v
        }

        if out["authorization"]?.trimmingCharacters(in: .whitespaces).isEmpty != false,
           (path as NSString).range(of: "accessToken=").location == NSNotFound,
           let token = APIClient.shared.accessToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty {
            out["Authorization"] = "Bearer \(token)"
        }
        return out
    }

    private func buildHTTPResponse(status: Int, headers: [String: String], body: Data) -> Data {
        var lines: [String] = []
        lines.append("HTTP/1.1 \(status) \(statusText(status))")
        for (k, v) in headers {
            lines.append("\(k): \(v)")
        }
        if !body.isEmpty, headers["content-length"] == nil {
            lines.append("Content-Length: \(body.count)")
        }
        lines.append("")
        lines.append("")

        var data = lines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }

    private func sendError(connection: NWConnection, status: Int, message: String) {
        let body = message.data(using: .utf8) ?? Data()
        let headers = ["Content-Length": "\(body.count)", "Content-Type": "text/plain; charset=utf-8"]
        let data = buildHTTPResponse(status: status, headers: headers, body: body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// 限制同时在途的 send 数量，提高代理到播放器的吞吐，减少因逐块等待导致的超时或对端关闭。
private actor SendThrottle {
    var inFlight = 0
    let maxInFlight: Int
    var slotWaiters: [CheckedContinuation<Void, Never>] = []
    var allDoneWaiters: [CheckedContinuation<Void, Never>] = []
    var failed = false

    init(maxInFlight: Int = 4) {
        self.maxInFlight = maxInFlight
    }

    func waitSlot() async {
        if inFlight < maxInFlight {
            inFlight += 1
            return
        }
        await withCheckedContinuation { slotWaiters.append($0) }
        inFlight += 1
    }

    func sendCompleted(error: Error? = nil) {
        if error != nil { failed = true }
        inFlight -= 1
        if inFlight == 0 {
            for w in allDoneWaiters { w.resume() }
            allDoneWaiters = []
        }
        if !slotWaiters.isEmpty {
            slotWaiters.removeFirst().resume()
        }
    }

    func waitAll() async {
        if inFlight == 0 { return }
        await withCheckedContinuation { allDoneWaiters.append($0) }
    }

    func checkFailed() -> Bool { failed }
}
