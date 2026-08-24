// P2P 信令紧凑二进制协议（与服务端 signalingBinary.js / quickshare 一致）

import Foundation

/// NPS\x01
private let magic: [UInt8] = [0x4e, 0x50, 0x53, 0x01]

private let typePing: UInt8 = 0x01
private let typePong: UInt8 = 0x02
private let typeSessionReady: UInt8 = 0x10
private let typeSessionClosed: UInt8 = 0x11
private let typeWebrtcOffer: UInt8 = 0x20
private let typeWebrtcAnswer: UInt8 = 0x21
private let typeWebrtcCandidate: UInt8 = 0x22
private let typeError: UInt8 = 0x23
private let typeDeviceReady: UInt8 = 0x30
private let typeDevicePairCode: UInt8 = 0x31
private let typeSessionClientConnected: UInt8 = 0x32
private let typeWebrtcDeviceReady: UInt8 = 0x33

private func encodeVarint(_ n: Int) -> Data {
    var v = UInt64(n < 0 ? 0 : n)
    var out = [UInt8]()
    while v >= 0x80 {
        out.append(UInt8((v & 0x7f) | 0x80))
        v >>= 7
    }
    out.append(UInt8(v & 0xff))
    return Data(out)
}

private func decodeVarint(_ data: Data, offset: inout Int) -> Int? {
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

private func encodeString(_ s: String) -> Data {
    let utf8 = Array(s.utf8)
    if utf8.isEmpty { return Data([0]) }
    return encodeVarint(utf8.count) + Data(utf8)
}

private func decodeString(_ data: Data, offset: inout Int) -> String? {
    guard let len = decodeVarint(data, offset: &offset), offset + len <= data.count else { return nil }
    if len == 0 {
        offset += 0
        return ""
    }
    let slice = data[offset..<(offset + len)]
    offset += len
    return String(data: slice, encoding: .utf8)
}

enum P2pSignalingBinary {
    static func isSignalingBinary(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        return data[0] == magic[0] && data[1] == magic[1] && data[2] == magic[2] && data[3] == magic[3]
    }

    static func encodeSignaling(_ msg: [String: Any]) -> Data? {
        guard let type = msg["type"] as? String else { return nil }
        var mt: UInt8
        switch type {
        case "ping": mt = typePing
        case "pong": mt = typePong
        case "session:ready": mt = typeSessionReady
        case "session:closed": mt = typeSessionClosed
        case "webrtc:offer": mt = typeWebrtcOffer
        case "webrtc:answer": mt = typeWebrtcAnswer
        case "webrtc:candidate": mt = typeWebrtcCandidate
        case "error": mt = typeError
        case "device:ready": mt = typeDeviceReady
        case "device:pairCode": mt = typeDevicePairCode
        case "session:client_connected": mt = typeSessionClientConnected
        case "webrtc:device_ready": mt = typeWebrtcDeviceReady
        default: return nil
        }

        var out = Data(magic)
        out.append(mt)

        if mt == typePing || mt == typePong {
            let ts = (msg["ts"] as? NSNumber)?.intValue ?? (msg["ts"] as? Int) ?? 0
            out.append(encodeVarint(ts))
            return out
        }
        if mt == typeSessionReady {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            let ice = msg["iceServers"]
            let iceJson: String
            if let arr = ice as? [[String: Any]], let d = try? JSONSerialization.data(withJSONObject: arr), let s = String(data: d, encoding: .utf8) {
                iceJson = s
            } else {
                iceJson = "[]"
            }
            out.append(encodeString(iceJson))
            return out
        }
        if mt == typeSessionClosed {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            out.append(encodeString(msg["reason"] as? String ?? ""))
            return out
        }
        if mt == typeWebrtcOffer {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            let offer = msg["offer"] as? [String: Any] ?? [:]
            out.append(encodeString(offer["type"] as? String ?? ""))
            out.append(encodeString(offer["sdp"] as? String ?? ""))
            return out
        }
        if mt == typeWebrtcAnswer {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            let answer = msg["answer"] as? [String: Any] ?? [:]
            out.append(encodeString(answer["type"] as? String ?? ""))
            out.append(encodeString(answer["sdp"] as? String ?? ""))
            return out
        }
        if mt == typeWebrtcCandidate {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            let c = msg["candidate"] as? [String: Any] ?? [:]
            out.append(encodeString(c["candidate"] as? String ?? ""))
            out.append(encodeString(c["sdpMid"] as? String ?? ""))
            let idx = (c["sdpMLineIndex"] as? NSNumber)?.intValue ?? (c["sdpMLineIndex"] as? Int) ?? 0
            out.append(encodeVarint(idx))
            return out
        }
        if mt == typeError {
            out.append(encodeString(msg["code"] as? String ?? ""))
            return out
        }
        if mt == typeDeviceReady || mt == typeDevicePairCode {
            out.append(encodeString(msg["deviceId"] as? String ?? ""))
            out.append(encodeString(msg["serverId"] as? String ?? ""))
            out.append(encodeString(msg["pairCode"] as? String ?? ""))
            return out
        }
        if mt == typeSessionClientConnected {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            let ice = msg["iceServers"]
            let iceJson: String
            if let arr = ice as? [[String: Any]], let d = try? JSONSerialization.data(withJSONObject: arr), let s = String(data: d, encoding: .utf8) {
                iceJson = s
            } else {
                iceJson = "[]"
            }
            out.append(encodeString(iceJson))
            return out
        }
        if mt == typeWebrtcDeviceReady {
            out.append(encodeString(msg["sessionId"] as? String ?? ""))
            return out
        }
        return nil
    }

    static func decodeSignaling(_ data: Data) -> [String: Any]? {
        guard data.count >= 5, isSignalingBinary(data) else { return nil }
        let mt = data[4]
        var offset = 5

        func readStr() -> String? {
            decodeString(data, offset: &offset)
        }
        func readVar() -> Int? {
            decodeVarint(data, offset: &offset)
        }

        if mt == typePing {
            guard let ts = readVar() else { return nil }
            return ["type": "ping", "ts": ts]
        }
        if mt == typePong {
            guard let ts = readVar() else { return nil }
            return ["type": "pong", "ts": ts]
        }
        if mt == typeSessionReady {
            guard let sessionId = readStr(), let iceJson = readStr() else { return nil }
            var iceServers: [[String: Any]] = []
            if let d = iceJson.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                iceServers = arr
            }
            return ["type": "session:ready", "sessionId": sessionId, "iceServers": iceServers]
        }
        if mt == typeSessionClosed {
            guard let sessionId = readStr() else { return nil }
            let reason = readStr()
            var out: [String: Any] = ["type": "session:closed", "sessionId": sessionId]
            if let r = reason, !r.isEmpty { out["reason"] = r }
            return out
        }
        if mt == typeWebrtcOffer {
            guard let sessionId = readStr(), let type = readStr(), let sdp = readStr() else { return nil }
            return ["type": "webrtc:offer", "sessionId": sessionId, "offer": ["type": type, "sdp": sdp]]
        }
        if mt == typeWebrtcAnswer {
            let sessionId = readStr()
            guard let type = readStr(), let sdp = readStr() else { return nil }
            var out: [String: Any] = ["type": "webrtc:answer", "answer": ["type": type, "sdp": sdp]]
            if let s = sessionId, !s.isEmpty { out["sessionId"] = s }
            return out
        }
        if mt == typeWebrtcCandidate {
            guard let sessionId = readStr(), let candidate = readStr() else { return nil }
            let sdpMid = readStr()
            let sdpMLineIndex = readVar() ?? 0
            return ["type": "webrtc:candidate", "sessionId": sessionId, "candidate": ["candidate": candidate, "sdpMid": sdpMid ?? "", "sdpMLineIndex": sdpMLineIndex]]
        }
        if mt == typeError {
            guard let code = readStr() else { return nil }
            return ["type": "error", "code": code]
        }
        if mt == typeDeviceReady {
            guard let deviceId = readStr(), let serverId = readStr(), let pairCode = readStr() else { return nil }
            return ["type": "device:ready", "deviceId": deviceId, "serverId": serverId, "pairCode": pairCode]
        }
        if mt == typeDevicePairCode {
            guard let deviceId = readStr(), let serverId = readStr(), let pairCode = readStr() else { return nil }
            return ["type": "device:pairCode", "deviceId": deviceId, "serverId": serverId, "pairCode": pairCode]
        }
        if mt == typeSessionClientConnected {
            guard let sessionId = readStr(), let iceJson = readStr() else { return nil }
            var iceServers: [[String: Any]] = []
            if let d = iceJson.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
                iceServers = arr
            }
            return ["type": "session:client_connected", "sessionId": sessionId, "iceServers": iceServers]
        }
        if mt == typeWebrtcDeviceReady {
            guard let sessionId = readStr() else { return nil }
            return ["type": "webrtc:device_ready", "sessionId": sessionId]
        }
        return nil
    }

    /// 从 WebSocket 消息（Data 或 String 转 Data）解码
    static func decodeSignaling(from messageData: Data) -> [String: Any]? {
        decodeSignaling(messageData)
    }

    static func decodeSignaling(fromUtf8String s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return decodeSignaling(d)
    }
}
