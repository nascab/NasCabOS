import Foundation

struct APIState {
    var serverId: String = ""
    var accessToken: String?
    var refreshToken: String?
    var baseUrl: String = NetworkConfig.localhostBaseUrl
    var isAuthenticated: Bool = false
    var expiresAt: Date?
    var shellSupported: Bool = false
    /// 登录接口返回的服务端版本（如 `6.0.0`）；未知时为空，版本比较与 Flutter 一致按「未知视为满足」处理。
    var serverVersion: String?

    var isTokenExpiringSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow <= NetworkConfig.tokenExpiryThreshold
    }

    var isP2pMode: Bool {
        baseUrl.trimmingCharacters(in: .whitespaces) == NetworkConfig.p2pBaseUrl
    }

    /// 与 Flutter `ServerVersionUtil.isAtLeast(..., unknownAsSupported: true)` 对齐。
    func isServerMajorVersionAtLeast(_ major: Int) -> Bool {
        Self.isServerMajorVersionAtLeast(serverVersion, major: major)
    }

    private static func isServerMajorVersionAtLeast(_ version: String?, major: Int) -> Bool {
        guard let m = parseMajorVersion(version) else { return true }
        return m >= major
    }

    private static func parseMajorVersion(_ version: String?) -> Int? {
        guard var v = version?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if v.lowercased().hasPrefix("v") { v.removeFirst() }
        let head = v.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? v
        guard let range = head.range(of: "^\\d+", options: .regularExpression) else { return nil }
        return Int(String(head[range]))
    }
}
