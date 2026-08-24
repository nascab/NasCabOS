import Foundation
import CryptoKit

@MainActor
final class AuthService {
    static let shared = AuthService()
    private let api = APIClient.shared

    func checkServerStatus(timeout: TimeInterval = 5) async -> ServerStatusResponse {
        print("[P2P] AuthService: checkServerStatus start timeout=\(timeout) isP2pMode=\(api.isP2pMode)")
        let response: APIResponse<[String: Any]> = await api.apiGet(
            "/api/auth/isNasCabServer",
            timeout: timeout,
            maxRetries: timeout <= 3 ? 0 : 1,  // 短超时用于探测，不重试
            dataParser: { data, _ in data }
        )
        return parseServerStatusResponse(response)
    }

    /// 向指定 baseUrl 探测，不修改当前 api.baseUrl，用于并行直连/LAN 检测
    func checkServerStatusAt(baseUrl: String, timeout: TimeInterval = 3) async -> ServerStatusResponse {
        let response: APIResponse<[String: Any]> = await api.getToBaseUrl(baseUrl, endpoint: "/api/auth/isNasCabServer", timeout: timeout)
        return parseServerStatusResponse(response)
    }

    private func parseServerStatusResponse(_ response: APIResponse<[String: Any]>) -> ServerStatusResponse {
        let isNasCab = (response.data?["isNasCabOSServer"] as? Bool) == true
        print("[P2P] AuthService: checkServerStatus response success=\(response.success) isNasCabOSServer=\(isNasCab) message=\(response.message ?? "nil")")
        guard response.success else {
            return ServerStatusResponse(
                success: false,
                message: response.message,
                isNasCabServer: false,
                serverData: nil
            )
        }
        return ServerStatusResponse(
            success: true,
            message: response.message,
            isNasCabServer: isNasCab,
            serverData: response.data
        )
    }

    func login(serverInfo: ServerInfo) async -> LoginResponse {
        _ = DeviceFingerprint.getOrCreateVideoPlayerDeviceId()
        var body: [String: Any] = [
            "username": serverInfo.username ?? "",
            "password": obfuscatePassword(serverInfo.password ?? ""),
        ]
        body["device_fingerprint"] = DeviceFingerprint.getDeviceFingerprintPayload()
        let response: APIResponse<LoginResponse> = await api.apiPost(
            "/api/auth/login",
            body: body,
            dataParser: { data, code in LoginResponse.from(json: data, httpCode: code) }
        )
        guard response.success, let data = response.data else {
            return LoginResponse(
                success: false,
                message: response.message ?? L10n.authLoginFailure,
                code: response.code
            )
        }
        return data
    }

    func verifyTwoFactorLogin(tempToken: String, code: String) async -> LoginResponse {
        _ = DeviceFingerprint.getOrCreateVideoPlayerDeviceId()
        var body: [String: Any] = [
            "tempToken": tempToken,
            "code": code,
        ]
        body["device_fingerprint"] = DeviceFingerprint.getDeviceFingerprintPayload()
        let response: APIResponse<LoginResponse> = await api.apiPost(
            "/api/auth/2fa/login/verify",
            body: body,
            dataParser: { data, code in LoginResponse.from(json: data, httpCode: code) }
        )
        guard response.success, let data = response.data else {
            return LoginResponse(
                success: false,
                message: response.message ?? L10n.authLoginFailure,
                code: response.code
            )
        }
        return data
    }

    func refreshToken(_ refreshToken: String) async -> LoginResponse {
        let body: [String: Any] = ["refreshToken": refreshToken]
        let response: APIResponse<LoginResponse> = await api.apiPost(
            "/api/auth/refreshJwt",
            body: body,
            dataParser: { data, code in LoginResponse.from(json: data, httpCode: code) }
        )
        guard response.success, let data = response.data else {
            return LoginResponse(
                success: false,
                message: response.message ?? L10n.authTokenRefreshFailure
            )
        }
        return data
    }

    func createSuperAdmin(
        username: String,
        password: String,
        securityQuestion: String,
        securityAnswer: String
    ) async -> LoginResponse {
        let body: [String: Any] = [
            "username": username,
            "password": obfuscatePassword(password),
            "question": securityQuestion,
            "answer": sha256Hash(securityAnswer),
        ]
        let response: APIResponse<LoginResponse> = await api.apiPost(
            "/api/auth/createSuperAdmin",
            body: body,
            dataParser: { data, code in LoginResponse.from(json: data, httpCode: code) }
        )
        guard response.success, let data = response.data else {
            return LoginResponse(
                success: false,
                message: response.message ?? L10n.adminCreateFailure
            )
        }
        return data
    }

    /// 退出登录：调用服务端 logout，然后清除本地认证信息
    func logout() async {
        if let refreshToken = api.state.refreshToken, !refreshToken.isEmpty {
            let body: [String: Any] = ["refreshToken": refreshToken]
            _ = await api.apiPost(
                "/api/auth/logout",
                body: body,
                dataParser: { _, _ in () as Void }
            )
        }
        api.clearAuthInfo()
        P2PService.shared.disconnect()
    }

    // MARK: - Password Utilities

    private func obfuscatePassword(_ password: String) -> String {
        let b64 = Data(password.utf8).base64EncodedString()
        return "b64:\(b64)"
    }

    private func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
