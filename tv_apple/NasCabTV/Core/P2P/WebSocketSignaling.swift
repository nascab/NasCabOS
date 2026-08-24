import Foundation

protocol WebSocketSignalingDelegate: AnyObject {
    func signalingDidReceiveSessionReady(sessionId: String, iceServers: [[String: Any]])
    func signalingDidReceiveWebRTCMessage(_ message: [String: Any])
    func signalingDidReceiveError(code: String)
    func signalingDidClose()
}

final class WebSocketSignaling: NSObject {
    var delegate: WebSocketSignalingDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTimer: Timer?
    private var isConnected = false

    func connect(to urlString: String) {
        guard let url = URL(string: urlString) else {
            print("[P2P] WebSocketSignaling: connect invalid_ws_url")
            delegate?.signalingDidReceiveError(code: "invalid_ws_url")
            return
        }
        print("[P2P] WebSocketSignaling: connect start host=\(url.host ?? "?")")
        let config = URLSessionConfiguration.default
        // 中继 / 远距离信令需更长；过短会导致 WS 未收齐 session:ready 即被 URLSession 断开
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
        startHeartbeat()
    }

    /// 发送信令（紧凑二进制 NPS，与服务端一致）
    func send(json: [String: Any]) {
        guard let task = webSocketTask, isConnected else { return }
        guard let data = P2pSignalingBinary.encodeSignaling(json) else { return }
        task.send(.data(data)) { _ in }
    }

    func disconnect() {
        isConnected = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Private

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self, self.isConnected else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()
            case .failure(let err):
                print("[P2P] WebSocketSignaling: receive failure \(err.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }
        guard !data.isEmpty else { return }

        guard let json = P2pSignalingBinary.decodeSignaling(data) else { return }

        let type = json["type"] as? String ?? ""
        if type != "pong" { print("[P2P] WebSocketSignaling: msg type=\(type)") }

        switch type {
        case "pong":
            break

        case "session:ready":
            let sessionId = json["sessionId"] as? String ?? ""
            let iceServers = json["iceServers"] as? [[String: Any]] ?? []
            delegate?.signalingDidReceiveSessionReady(sessionId: sessionId, iceServers: iceServers)

        case "session:closed":
            print("[P2P] WebSocketSignaling: session:closed")
            handleDisconnect()

        case "error":
            let code = (json["code"] as? String) ?? (json["errorCode"] as? String) ?? "P2P_ERROR"
            print("[P2P] WebSocketSignaling: error code=\(code)")
            delegate?.signalingDidReceiveError(code: code)
            handleDisconnect()

        default:
            if type.hasPrefix("webrtc:") {
                if delegate != nil {
                    print("[P2P] WebSocketSignaling: forwarding \(type) to delegate")
                }
                delegate?.signalingDidReceiveWebRTCMessage(json)
            }
        }
    }

    private func handleDisconnect() {
        guard isConnected else { return }
        print("[P2P] WebSocketSignaling: handleDisconnect")
        isConnected = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        webSocketTask = nil
        delegate?.signalingDidClose()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.isConnected else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            self.send(json: ["type": "ping", "ts": nowMs])
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketSignaling: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[P2P] WebSocketSignaling: didOpenWithProtocol")
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("[P2P] WebSocketSignaling: didCloseWith closeCode=\(closeCode.rawValue)")
        handleDisconnect()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
