import Foundation

struct LoginResponse {
    let success: Bool
    let message: String?
    let accessToken: String?
    let refreshToken: String?
    let user: [String: Any]?
    let twoFactorRequired: Bool
    let tempToken: String?
    let platform: String?
    let hostname: String?
    let serverId: String?
    let httpPort: String?
    let httpsPort: String?
    let lanIpv4: String?
    let p2pRemoteAccessEnabled: Bool
    let pairCode: String?
    let expiresIn: Int?
    let code: Int?
    let shellSupported: Bool
    /// 服务端版本号（登录成功时返回，如 `6.0.0`）
    let serverVersion: String?

    init(
        success: Bool,
        message: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        user: [String: Any]? = nil,
        twoFactorRequired: Bool = false,
        tempToken: String? = nil,
        platform: String? = nil,
        hostname: String? = nil,
        serverId: String? = nil,
        httpPort: String? = nil,
        httpsPort: String? = nil,
        lanIpv4: String? = nil,
        p2pRemoteAccessEnabled: Bool = false,
        pairCode: String? = nil,
        expiresIn: Int? = nil,
        code: Int? = nil,
        shellSupported: Bool = false,
        serverVersion: String? = nil
    ) {
        self.success = success
        self.message = message
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
        self.twoFactorRequired = twoFactorRequired
        self.tempToken = tempToken
        self.platform = platform
        self.hostname = hostname
        self.serverId = serverId
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.lanIpv4 = lanIpv4
        self.p2pRemoteAccessEnabled = p2pRemoteAccessEnabled
        self.pairCode = pairCode
        self.expiresIn = expiresIn
        self.code = code
        self.shellSupported = shellSupported
        self.serverVersion = serverVersion
    }

    static func from(json data: [String: Any], httpCode: Int) -> LoginResponse {
        LoginResponse(
            success: true,
            accessToken: data["accessToken"] as? String,
            refreshToken: data["refreshToken"] as? String,
            user: data["user"] as? [String: Any],
            twoFactorRequired: data["twoFactorRequired"] as? Bool ?? false,
            tempToken: data["tempToken"] as? String,
            platform: data["platform"] as? String,
            hostname: data["hostname"] as? String,
            serverId: data["serverId"] as? String,
            httpPort: stringValue(data["httpPort"]),
            httpsPort: stringValue(data["httpsPort"]),
            lanIpv4: stringValue(data["lanIpv4"]),
            p2pRemoteAccessEnabled: data["p2pRemoteAccessEnabled"] as? Bool ?? false,
            pairCode: stringValue(data["pairCode"]),
            expiresIn: data["expiresIn"] as? Int,
            code: httpCode,
            shellSupported: {
                if let b = data["shellSupported"] as? Bool { return b }
                if let n = data["shellSupported"] as? Int { return n == 1 }
                return false
            }(),
            serverVersion: data["serverVersion"] as? String
        )
    }

    private static func stringValue(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s }
        return "\(v)"
    }
}

struct ServerStatusResponse {
    let success: Bool
    let message: String?
    let isNasCabServer: Bool
    let serverData: [String: Any]?
}
