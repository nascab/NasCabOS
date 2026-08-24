import Foundation

/// UDP 广播监听：监听端口 8888，解析 NasCab 服务发现报文，与 Flutter 端 UdpBroadcastListener 协议一致
final class UdpBroadcastListener {
    static let broadcastPort: UInt16 = 8888

    typealias ServerDiscoveredHandler = ([String: Any]) -> Void

    private var socket: Int32 = -1
    private var receiveSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "UdpBroadcastListener.receive")
    private var onServerDiscovered: ServerDiscoveredHandler?

    var isListening: Bool { socket >= 0 }

    func setOnServerDiscovered(_ handler: @escaping ServerDiscoveredHandler) {
        onServerDiscovered = handler
    }

    func startListening() {
        guard socket < 0 else { return }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            print("[UDP] socket create failed: \(errno)")
            return
        }
        socket = fd

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.broadcastPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            print("[UDP] bind failed: \(errno)")
            stopListening()
            return
        }

        receiveSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        receiveSource?.setEventHandler { [weak self] in
            self?.receive()
        }
        receiveSource?.resume()
        print("[UDP] listening on port \(Self.broadcastPort)")
    }

    private func receive() {
        guard socket >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 2048)
        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let n = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                recvfrom(socket, &buf, buf.count, 0, ptr, &len)
            }
        }
        guard n > 0 else { return }
        let data = Data(bytes: buf, count: n)
        guard let message = String(data: data, encoding: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["service"] as? String == "nascab-pro-service",
              json["host"] != nil,
              json["port"] != nil else {
            return
        }
        var serverInfo = json
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    serverInfo["discovered_ip"] = String(cString: hostBuffer)
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onServerDiscovered?(serverInfo)
        }
    }

    func stopListening() {
        receiveSource?.cancel()
        receiveSource = nil
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
        print("[UDP] stopped")
    }

    deinit {
        stopListening()
    }
}
