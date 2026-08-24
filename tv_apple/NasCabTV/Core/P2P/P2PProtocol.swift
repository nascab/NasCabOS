import Foundation

// MARK: - Channel Types

enum P2pRtcChannel: String, CaseIterable {
    case api
    case file
    /// 专用于视频播放的大流量通道：与 file 分离，避免图片/小文件请求挤占导致播放器超时断开。
    case video
}

// MARK: - Response Types

struct P2pApiResponse {
    let status: Int
    let headers: [String: String]
    let bodyBytes: Data
}

/// 流式 P2P 响应事件（用于视频/大文件边收边播，避免整 body 进内存）
enum P2pStreamEvent {
    case response(status: Int, headers: [String: String], id: String)
    case chunk(data: Data, id: String, wireBytes: Int)
    case end
}

// MARK: - P2P Control Binary Protocol (compact binary, matches server dataChannelProxy)

/// 与服务端 p2pConnectWorker/dataChannelProxy 一致的紧凑二进制控制消息。
/// 信令从 JSON 改为二进制后，Data Channel 上的控制消息使用此格式。
enum P2pControlBinary {
    static let magic: [UInt8] = [0x4e, 0x50, 0x43, 0x01] // "NPC\x01"
    static let magicData = Data(magic)

    enum ControlType: UInt8 {
        case ready = 0x01
        case ping = 0x02
        case pong = 0x03
        case req = 0x10
        case reqBegin = 0x11
        case reqEnd = 0x12
        case reqCancel = 0x13
        case cancel = 0x14
        case resBegin = 0x20
        case resEnd = 0x21
        case flow = 0x22
        case ack = 0x30
        case wsOpen = 0x40
        case wsSend = 0x41
        case wsClose = 0x42
        case wsOpenOk = 0x43
        case wsOpenError = 0x44
        case wsMessage = 0x45
        case wsError = 0x46
    }

    /// 判断是否为控制消息（魔术头）
    static func isControl(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        return data[0] == magic[0] && data[1] == magic[1] && data[2] == magic[2] && data[3] == magic[3]
    }

    // MARK: Varint (unsigned LEB128, matches server encodeVarint/decodeVarint)
    static func encodeVarint(_ n: Int) -> Data {
        var v = UInt64(n < 0 ? 0 : n)
        var out = [UInt8]()
        while v >= 0x80 {
            out.append(UInt8((v & 0x7f) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v & 0xff))
        return Data(out)
    }

    static func decodeVarint(_ data: Data, offset: inout Int) -> Int? {
        var shift = 0
        var result: UInt64 = 0
        while offset < data.count {
            let b = UInt64(data[offset] & 0xff)
            offset += 1
            result |= (b & 0x7f) << shift
            if (b & 0x80) == 0 {
                return result <= UInt64(Int.max) ? Int(result) : Int.max
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    // MARK: String (varint length + utf8; empty = single 0x00)
    static func encodeString(_ s: String) -> Data {
        let utf8 = Array(s.utf8)
        if utf8.isEmpty { return Data([0]) }
        return encodeVarint(utf8.count) + Data(utf8)
    }

    static func decodeString(_ data: Data, offset: inout Int) -> String? {
        guard let len = decodeVarint(data, offset: &offset), offset + len <= data.count else { return nil }
        if len == 0 {
            return ""
        }
        let slice = data[offset..<(offset + len)]
        offset += len
        return String(data: slice, encoding: .utf8)
    }

    // MARK: Map<String,String>
    static func encodeMapStrStr(_ map: [String: String]) -> Data {
        let entries = map.filter { !$0.key.isEmpty }
        var out = encodeVarint(entries.count)
        for (k, v) in entries {
            out.append(encodeString(k))
            out.append(encodeString(v))
        }
        return out
    }

    static func decodeMapStrStr(_ data: Data, offset: inout Int) -> [String: String]? {
        guard let count = decodeVarint(data, offset: &offset) else { return nil }
        var out: [String: String] = [:]
        for _ in 0..<count {
            guard let k = decodeString(data, offset: &offset), let v = decodeString(data, offset: &offset) else { return nil }
            if !k.isEmpty { out[k] = v }
        }
        return out
    }

    // MARK: Decode control message -> [String: Any] for existing handlers
    static func decodeControl(_ data: Data, prefix: String) -> [String: Any]? {
        guard isControl(data), data.count >= 5 else { return nil }
        let mt = data[4]
        var offset = 5

        func readVar() -> Int? { P2pControlBinary.decodeVarint(data, offset: &offset) }
        func readStr() -> String? { P2pControlBinary.decodeString(data, offset: &offset) }
        func readMap() -> [String: String]? { P2pControlBinary.decodeMapStrStr(data, offset: &offset) }

        switch mt {
        case ControlType.ping.rawValue, ControlType.pong.rawValue:
            guard let ts = readVar() else { return nil }
            let suffix = mt == ControlType.ping.rawValue ? "ping" : "pong"
            return ["type": "\(prefix):\(suffix)", "ts": ts]
        case ControlType.ready.rawValue:
            guard let chunkBinaryV2 = readVar() else { return nil }
            return ["type": "\(prefix):ready", "features": ["chunkBinaryV2": chunkBinaryV2 != 0]]
        case ControlType.reqEnd.rawValue, ControlType.reqCancel.rawValue, ControlType.cancel.rawValue, ControlType.resEnd.rawValue:
            guard let id = readStr() else { return nil }
            let suffix: String
            switch mt {
            case ControlType.reqEnd.rawValue: suffix = "req:end"
            case ControlType.reqCancel.rawValue: suffix = "req:cancel"
            case ControlType.cancel.rawValue: suffix = "cancel"
            case ControlType.resEnd.rawValue: suffix = "res:end"
            default: suffix = ""
            }
            return ["type": "\(prefix):\(suffix)", "id": id]
        case ControlType.ack.rawValue:
            guard let id = readStr(), let delta = readVar() else { return nil }
            return ["type": "\(prefix):ack", "id": id, "delta": delta]
        case ControlType.flow.rawValue:
            guard let id = readStr(), let action = readStr() else { return nil }
            return ["type": "\(prefix):flow", "id": id, "action": action]
        case ControlType.req.rawValue, ControlType.reqBegin.rawValue:
            guard let id = readStr(), let method = readStr(), let path = readStr(), let headers = readMap() else { return nil }
            if mt == ControlType.reqBegin.rawValue {
                guard let length = readVar() else { return nil }
                return ["type": "\(prefix):req:begin", "id": id, "method": method, "path": path, "headers": headers, "length": length]
            }
            return ["type": "\(prefix):req", "id": id, "method": method, "path": path, "headers": headers]
        case ControlType.resBegin.rawValue:
            guard let id = readStr(), let status = readVar(), let headers = readMap(), let length = readVar() else { return nil }
            var headersAny: [String: Any] = [:]
            for (k, v) in headers { headersAny[k] = v }
            return ["type": "\(prefix):res:begin", "id": id, "status": status, "headers": headersAny, "length": length]
        default:
            return nil
        }
    }

    // MARK: Encode control message (client -> server)
    static func encodeControl(prefix: String, type: ControlType, payload: [String: Any]) -> Data? {
        var parts = Data(magic)
        parts.append(type.rawValue)

        switch type {
        case .ping, .pong:
            guard let ts = payload["ts"] as? Int else { return nil }
            parts.append(encodeVarint(ts))
            return parts
        case .reqEnd, .reqCancel, .cancel, .resEnd:
            guard let id = payload["id"] as? String else { return nil }
            parts.append(encodeString(id))
            return parts
        case .ack:
            guard let id = payload["id"] as? String, let delta = payload["delta"] as? Int else { return nil }
            parts.append(encodeString(id))
            parts.append(encodeVarint(delta))
            return parts
        case .req:
            guard let id = payload["id"] as? String, let method = payload["method"] as? String, let path = payload["path"] as? String,
                  let headers = payload["headers"] as? [String: String] else { return nil }
            parts.append(encodeString(id))
            parts.append(encodeString(method))
            parts.append(encodeString(path))
            parts.append(encodeMapStrStr(headers))
            return parts
        case .reqBegin:
            guard let id = payload["id"] as? String, let method = payload["method"] as? String, let path = payload["path"] as? String,
                  let headers = payload["headers"] as? [String: String], let length = payload["length"] as? Int else { return nil }
            parts.append(encodeString(id))
            parts.append(encodeString(method))
            parts.append(encodeString(path))
            parts.append(encodeMapStrStr(headers))
            parts.append(encodeVarint(length))
            return parts
        default:
            return nil
        }
    }
}

// MARK: - Binary Frame Protocol

enum P2pBinaryFrame {
    static let versionV1: UInt8 = 0x01
    static let versionV2: UInt8 = 0x02
    static let chunkSize = 64 * 1024

    struct ParsedFrame {
        let version: UInt8
        let requestId: String
        let flags: UInt8
        let payload: Data
    }

    static func parse(_ data: Data) -> ParsedFrame? {
        guard data.count >= 2 else { return nil }
        let ver = data[data.startIndex]
        guard ver == versionV1 || ver == versionV2 else { return nil }

        var offset = data.startIndex + 1
        let idLen = Int(data[offset])
        offset += 1

        let hasFlags = ver == versionV2
        let headerExtra = hasFlags ? 1 : 0
        guard offset + idLen + headerExtra <= data.endIndex else { return nil }

        let idData = data[offset..<(offset + idLen)]
        guard let requestId = String(data: idData, encoding: .utf8), !requestId.isEmpty else {
            return nil
        }
        offset += idLen

        var flags: UInt8 = 0
        if hasFlags {
            flags = data[offset]
            offset += 1
        }

        let payload = data[offset...]
        return ParsedFrame(
            version: ver,
            requestId: requestId,
            flags: flags,
            payload: Data(payload)
        )
    }

    static func buildHeader(version: UInt8, requestId: String, flags: UInt8 = 0) -> Data {
        let idBytes = Array(requestId.utf8)
        let idLen = UInt8(min(idBytes.count, 255))
        if version == versionV2 {
            var header = Data(capacity: Int(idLen) + 3)
            header.append(version)
            header.append(idLen)
            header.append(contentsOf: idBytes.prefix(Int(idLen)))
            header.append(flags)
            return header
        } else {
            var header = Data(capacity: Int(idLen) + 2)
            header.append(version)
            header.append(idLen)
            header.append(contentsOf: idBytes.prefix(Int(idLen)))
            return header
        }
    }
}

// MARK: - Request ID Generator

enum P2pRequestId {
    private static var counter: UInt64 = 0

    static func generate() -> String {
        counter += 1
        let ts = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let rand = UInt32.random(in: 0..<(1 << 30))
        return "\(ts)_\(rand)_\(counter)"
    }
}

// MARK: - Channel State

final class P2pStreamContext {
    let continuation: AsyncThrowingStream<P2pStreamEvent, Error>.Continuation

    init(continuation: AsyncThrowingStream<P2pStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }
}

final class RtcChannelState {
    let channel: P2pRtcChannel
    let prefix: String
    var isReady = false

    var pending: [String: CheckedContinuation<P2pApiResponse, Error>] = [:]
    var pendingChunks: [String: PendingChunk] = [:]
    /// 流式请求：不缓冲整 body，按 chunk 下发
    var pendingStreamContexts: [String: P2pStreamContext] = [:]

    var txPackets: Int = 0
    var txBytes: Int = 0
    var rxPackets: Int = 0
    var rxBytes: Int = 0
    var lastTxAtMs: Int64 = 0
    var lastRxAtMs: Int64 = 0

    var cachedChunkId: String?
    var cachedChunkIdBytes: Data?

    init(channel: P2pRtcChannel) {
        self.channel = channel
        self.prefix = channel.rawValue
    }
}

final class PendingChunk {
    let status: Int
    let headers: [String: String]
    var builder = Data()

    init(status: Int, headers: [String: String]) {
        self.status = status
        self.headers = headers
    }
}
