import Foundation

struct ServerInfo: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case serverId, serverUrl, userInputUrl, lanIpv4, lanHttpPort, lanHttpsPort
        case serverName, serverHost, serverPortHttp, serverPortHttps
        case serverHostName, serverPlatform, isAutoScanned, isLocalServer, isP2p
        case pairCode, username, password, requirePasswordEveryLogin
        case accessToken, refreshToken, lastLoginTime
    }

    init(
        serverId: String,
        serverUrl: String,
        userInputUrl: String? = nil,
        lanIpv4: String? = nil,
        lanHttpPort: String? = nil,
        lanHttpsPort: String? = nil,
        serverName: String,
        serverHost: String,
        serverPortHttp: String,
        serverPortHttps: String,
        serverHostName: String,
        serverPlatform: String,
        isAutoScanned: Bool,
        isLocalServer: Bool,
        isP2p: Bool,
        pairCode: String? = nil,
        username: String? = nil,
        password: String? = nil,
        requirePasswordEveryLogin: Bool = false,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        lastLoginTime: Date? = nil
    ) {
        self.serverId = serverId
        self.serverUrl = serverUrl
        self.userInputUrl = userInputUrl
        self.lanIpv4 = lanIpv4
        self.lanHttpPort = lanHttpPort
        self.lanHttpsPort = lanHttpsPort
        self.serverName = serverName
        self.serverHost = serverHost
        self.serverPortHttp = serverPortHttp
        self.serverPortHttps = serverPortHttps
        self.serverHostName = serverHostName
        self.serverPlatform = serverPlatform
        self.isAutoScanned = isAutoScanned
        self.isLocalServer = isLocalServer
        self.isP2p = isP2p
        self.pairCode = pairCode
        self.username = username
        self.password = password
        self.requirePasswordEveryLogin = requirePasswordEveryLogin
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.lastLoginTime = lastLoginTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try c.decode(String.self, forKey: .serverId)
        serverUrl = try c.decode(String.self, forKey: .serverUrl)
        userInputUrl = try c.decodeIfPresent(String.self, forKey: .userInputUrl)
        lanIpv4 = try c.decodeIfPresent(String.self, forKey: .lanIpv4)
        lanHttpPort = try c.decodeIfPresent(String.self, forKey: .lanHttpPort)
        lanHttpsPort = try c.decodeIfPresent(String.self, forKey: .lanHttpsPort)
        serverName = try c.decode(String.self, forKey: .serverName)
        serverHost = try c.decode(String.self, forKey: .serverHost)
        serverPortHttp = try c.decode(String.self, forKey: .serverPortHttp)
        serverPortHttps = try c.decode(String.self, forKey: .serverPortHttps)
        serverHostName = try c.decode(String.self, forKey: .serverHostName)
        serverPlatform = try c.decode(String.self, forKey: .serverPlatform)
        isAutoScanned = try c.decode(Bool.self, forKey: .isAutoScanned)
        isLocalServer = try c.decode(Bool.self, forKey: .isLocalServer)
        isP2p = try c.decode(Bool.self, forKey: .isP2p)
        pairCode = try c.decodeIfPresent(String.self, forKey: .pairCode)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        password = try c.decodeIfPresent(String.self, forKey: .password)
        requirePasswordEveryLogin = try c.decodeIfPresent(Bool.self, forKey: .requirePasswordEveryLogin) ?? false
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        lastLoginTime = try c.decodeIfPresent(Date.self, forKey: .lastLoginTime)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serverId, forKey: .serverId)
        try c.encode(serverUrl, forKey: .serverUrl)
        try c.encodeIfPresent(userInputUrl, forKey: .userInputUrl)
        try c.encodeIfPresent(lanIpv4, forKey: .lanIpv4)
        try c.encodeIfPresent(lanHttpPort, forKey: .lanHttpPort)
        try c.encodeIfPresent(lanHttpsPort, forKey: .lanHttpsPort)
        try c.encode(serverName, forKey: .serverName)
        try c.encode(serverHost, forKey: .serverHost)
        try c.encode(serverPortHttp, forKey: .serverPortHttp)
        try c.encode(serverPortHttps, forKey: .serverPortHttps)
        try c.encode(serverHostName, forKey: .serverHostName)
        try c.encode(serverPlatform, forKey: .serverPlatform)
        try c.encode(isAutoScanned, forKey: .isAutoScanned)
        try c.encode(isLocalServer, forKey: .isLocalServer)
        try c.encode(isP2p, forKey: .isP2p)
        try c.encodeIfPresent(pairCode, forKey: .pairCode)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(password, forKey: .password)
        try c.encode(requirePasswordEveryLogin, forKey: .requirePasswordEveryLogin)
        try c.encodeIfPresent(accessToken, forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encodeIfPresent(lastLoginTime, forKey: .lastLoginTime)
    }

    var id: String { uniqueKey }

    var serverId: String
    var serverUrl: String
    var userInputUrl: String?
    var lanIpv4: String?
    var lanHttpPort: String?
    var lanHttpsPort: String?
    var serverName: String
    var serverHost: String
    var serverPortHttp: String
    var serverPortHttps: String
    var serverHostName: String
    var serverPlatform: String
    var isAutoScanned: Bool
    var isLocalServer: Bool
    var isP2p: Bool
    var pairCode: String?
    var username: String?
    var password: String?
    /// 每次登录都需要输入密码：勾选后，每次登录此服务器都会弹出密码输入框
    var requirePasswordEveryLogin: Bool = false
    var accessToken: String?
    var refreshToken: String?
    var lastLoginTime: Date?

    var hasPairCode: Bool {
        !(pairCode ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    var hasDirectUrl: Bool {
        !serverUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var uniqueKey: String {
        let user = (username ?? "").trimmingCharacters(in: .whitespaces)
        let sid = serverId.trimmingCharacters(in: .whitespaces)
        if !sid.isEmpty { return "sid:\(sid)|u:\(user)" }
        let code = (pairCode ?? "").trimmingCharacters(in: .whitespaces)
        if !code.isEmpty { return "pair:\(code)|u:\(user)" }
        let url = serverUrl.trimmingCharacters(in: .whitespaces)
        if !url.isEmpty { return "url:\(url)|u:\(user)" }
        let input = (userInputUrl ?? "").trimmingCharacters(in: .whitespaces)
        if !input.isEmpty { return "input:\(input)|u:\(user)" }
        return "empty|u:\(user)"
    }

    var platformFriendlyName: String {
        switch serverPlatform.lowercased() {
        case "linux": return "Linux"
        case "win32": return "Windows"
        case "darwin": return "macOS"
        default: return serverPlatform
        }
    }

    var platformIconName: String {
        switch serverPlatform.lowercased() {
        case "darwin": return "desktopcomputer"
        case "win32": return "pc"
        case "linux": return "server.rack"
        default: return "server.rack"
        }
    }

    var maskedPairCode: String {
        guard let code = pairCode?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return "" }
        if code.count <= 2 { return String(repeating: "*", count: code.count) }
        let left = (code.count - 2) / 2
        let start = code.index(code.startIndex, offsetBy: left)
        let end = code.index(start, offsetBy: 2)
        return code.replacingCharacters(in: start..<end, with: "**")
    }

    static func merged(_ existing: ServerInfo, with incoming: ServerInfo) -> ServerInfo {
        func pick(_ a: String?, _ b: String?) -> String? {
            let v = (a ?? "").trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? b : a
        }
        func pickRequired(_ a: String, _ b: String) -> String {
            a.trimmingCharacters(in: .whitespaces).isEmpty ? b : a
        }
        var out = ServerInfo(
            serverId: pickRequired(incoming.serverId, existing.serverId),
            serverUrl: pickRequired(incoming.serverUrl, existing.serverUrl),
            userInputUrl: pick(incoming.userInputUrl, existing.userInputUrl),
            lanIpv4: pick(incoming.lanIpv4, existing.lanIpv4),
            lanHttpPort: pick(incoming.lanHttpPort, existing.lanHttpPort),
            lanHttpsPort: pick(incoming.lanHttpsPort, existing.lanHttpsPort),
            serverName: pickRequired(incoming.serverName, existing.serverName),
            serverHost: pickRequired(incoming.serverHost, existing.serverHost),
            serverPortHttp: pickRequired(incoming.serverPortHttp, existing.serverPortHttp),
            serverPortHttps: pickRequired(incoming.serverPortHttps, existing.serverPortHttps),
            serverHostName: pickRequired(incoming.serverHostName, existing.serverHostName),
            serverPlatform: pickRequired(incoming.serverPlatform, existing.serverPlatform),
            isAutoScanned: existing.isAutoScanned && incoming.isAutoScanned,
            isLocalServer: existing.isLocalServer || incoming.isLocalServer,
            isP2p: false,
            // 登录成功后服务器若返回新配对码，优先用 incoming，使本地与服务器一致
            pairCode: pick(incoming.pairCode, existing.pairCode),
            username: pick(incoming.username, existing.username),
            password: pick(incoming.password, existing.password),
            requirePasswordEveryLogin: incoming.requirePasswordEveryLogin,
            accessToken: pick(incoming.accessToken, existing.accessToken),
            refreshToken: pick(incoming.refreshToken, existing.refreshToken),
            lastLoginTime: incoming.lastLoginTime ?? existing.lastLoginTime
        )
        out.isP2p = out.serverUrl.trimmingCharacters(in: .whitespaces).isEmpty
            && !(out.pairCode ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return out
    }
}
