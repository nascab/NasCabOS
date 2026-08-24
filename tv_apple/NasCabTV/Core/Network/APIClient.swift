import Foundation
import Alamofire

extension Notification.Name {
    /// JWT / 刷新令牌失效且无法续期时发出；UI 应回到服务器列表并提示用户（对齐 Flutter 刷新失败体验）
    static let nasCabAuthSessionExpired = Notification.Name("NasCabOS TV.authSessionExpired")
}

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published private(set) var state = APIState()

    private var refreshTimer: Timer?
    /// 多个请求同时 401 时合并为一次 refresh，避免并发重复打 refresh 接口
    private var refreshCoalescedTask: Task<Bool, Never>?
    private let session: Session
    private let serverTrustManager: ServerTrustManager

    private init() {
        let evaluator = DisabledTrustEvaluator()
        let manager = ServerTrustManager(
            allHostsMustBeEvaluated: false,
            evaluators: ["*": evaluator]
        )
        self.serverTrustManager = manager
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = NetworkConfig.defaultTimeout
        configuration.timeoutIntervalForResource = 60
        self.session = Session(
            configuration: configuration,
            serverTrustManager: manager
        )
        loadStoredTokens()
    }

    // MARK: - State Management

    var baseUrl: String { state.baseUrl }
    var accessToken: String? { state.accessToken }
    var isAuthenticated: Bool { state.isAuthenticated }
    var isP2pMode: Bool { state.isP2pMode }
    var serverVersion: String? { state.serverVersion }

    func setBaseUrl(_ url: String) {
        state.baseUrl = url
        UserDefaults.standard.set(url, forKey: "auth_baseUrl")
    }

    func setAuthInfo(
        serverId: String,
        accessToken: String,
        refreshToken: String,
        expiresIn: Int,
        shellSupported: Bool = false,
        serverVersion: String? = nil
    ) {
        state.serverId = serverId
        state.accessToken = accessToken
        state.refreshToken = refreshToken
        state.isAuthenticated = true
        state.expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresIn))
        state.shellSupported = shellSupported
        if let raw = serverVersion?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            state.serverVersion = raw
        }
        saveTokensToStorage()
        startTokenRefreshTimer()
    }

    func clearAuthInfo() {
        state.accessToken = nil
        state.refreshToken = nil
        state.isAuthenticated = false
        state.expiresAt = nil
        state.serverVersion = nil
        clearStoredTokens()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - HTTP Requests

    func apiGet<T>(
        _ endpoint: String,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        maxRetries: Int? = nil,
        dataParser: (([String: Any], Int) -> T)? = nil
    ) async -> APIResponse<T> {
        await apiRequest(
            method: .get,
            endpoint: endpoint,
            queryParams: queryParams,
            timeout: timeout,
            maxRetries: maxRetries,
            dataParser: dataParser
        )
    }

    func apiPost<T>(
        _ endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        maxRetries: Int? = nil,
        dataParser: (([String: Any], Int) -> T)? = nil
    ) async -> APIResponse<T> {
        await apiRequest(
            method: .post,
            endpoint: endpoint,
            body: body,
            queryParams: queryParams,
            timeout: timeout,
            maxRetries: maxRetries,
            dataParser: dataParser
        )
    }

    /// GET 原始文本响应（如 subtitle-vtt），非 JSON 包装。
    func fetchPlainText(
        _ endpoint: String,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = 30
    ) async -> String? {
        do {
            let (data, statusCode) = try await sendRequest(
                method: .get,
                endpoint: endpoint,
                queryParams: queryParams,
                timeout: timeout
            )
            guard (200..<300).contains(statusCode) else { return nil }
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return nil }
            return text
        } catch {
            return nil
        }
    }

    /// 向指定 baseUrl 发 GET，不修改当前 state.baseUrl，用于并行探测（直连/LAN）
    func getToBaseUrl(_ baseUrl: String, endpoint: String, timeout: TimeInterval = 3) async -> APIResponse<[String: Any]> {
        let fullUrl = "\(baseUrl.trimmingCharacters(in: .whitespacesAndNewlines))\(endpoint)"
        guard let url = URL(string: fullUrl) else {
            return .failure(L10n.networkFailure)
        }
        var config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 2
        let oneOff = Session(configuration: config, serverTrustManager: serverTrustManager)
        var headers: HTTPHeaders = [:]
        headers.add(name: "Accept-Language", value: L10n.currentLanguageCode.replacingOccurrences(of: "_", with: "-"))
        if let token = state.accessToken {
            headers.add(.authorization(bearerToken: token))
        }
        let request = oneOff.request(url, method: .get, headers: headers).validate(statusCode: 100..<600)
        let response = await request.serializingData(automaticallyCancelling: true).response
        guard let httpResponse = response.response, let data = response.data else {
            return .failure(L10n.networkFailure + ": \(response.error?.localizedDescription ?? "")")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(L10n.networkFailure)
        }
        return APIResponse.fromJSON(httpCode: httpResponse.statusCode, json: json, dataParser: { d, _ in d })
    }

    private func apiRequest<T>(
        method: HTTPMethod,
        endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        maxRetries: Int? = nil,
        dataParser: (([String: Any], Int) -> T)? = nil
    ) async -> APIResponse<T> {
        let maxAttempts = (maxRetries ?? NetworkConfig.defaultMaxRetries) + 1
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                let response = try await sendRequest(
                    method: method,
                    endpoint: endpoint,
                    body: body,
                    queryParams: queryParams,
                    timeout: timeout
                )
                return handleResponse(response, dataParser: dataParser)
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(NetworkConfig.defaultRetryDelay * 1_000_000_000))
                }
            }
        }

        return .failure(L10n.networkFailure + ": \(lastError?.localizedDescription ?? "")")
    }

    private func sendRequest(
        method: HTTPMethod,
        endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, Int) {
        if state.isP2pMode {
            return try await sendRequestViaP2P(
                method: method,
                endpoint: endpoint,
                body: body,
                queryParams: queryParams,
                timeout: timeout
            )
        }

        var didRetryAfterRefresh = false
        while true {
            let (data, statusCode) = try await sendDirectRequestOnce(
                method: method,
                endpoint: endpoint,
                body: body,
                queryParams: queryParams,
                timeout: timeout
            )

            if statusCode != 401 {
                return (data, statusCode)
            }

            if Self.isRefreshJwtEndpoint(endpoint) {
                handleAuthSessionExpiredAfterRefreshJwt401()
                return (data, statusCode)
            }

            if Self.isTwoFactorRequiredResponse(data) {
                return (data, statusCode)
            }

            if didRetryAfterRefresh {
                return (data, statusCode)
            }

            let refreshed = await refreshAuthToken()
            if !refreshed {
                return (data, statusCode)
            }
            didRetryAfterRefresh = true
        }
    }

    private func sendDirectRequestOnce(
        method: HTTPMethod,
        endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, Int) {
        let fullUrl = "\(state.baseUrl)\(endpoint)"
        var urlComponents = URLComponents(string: fullUrl)
        if let queryParams {
            urlComponents?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = urlComponents?.url else {
            throw URLError(.badURL)
        }

        var headers: HTTPHeaders = [:]
        if let token = state.accessToken {
            headers.add(.authorization(bearerToken: token))
        }
        headers.add(name: "Accept-Language", value: L10n.currentLanguageCode.replacingOccurrences(of: "_", with: "-"))

        let encoding: ParameterEncoding = method == .get ? URLEncoding.default : JSONEncoding.default
        let parameters = (method == .get) ? nil : body

        if method != .get, body != nil {
            headers.add(.contentType("application/json"))
        }

        let sessionToUse: Session
        if let t = timeout, t > 0, t < 6 {
            var config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = t
            config.timeoutIntervalForResource = t + 2
            sessionToUse = Session(configuration: config, serverTrustManager: serverTrustManager)
        } else {
            sessionToUse = session
        }

        let request = sessionToUse.request(
            url,
            method: method,
            parameters: parameters,
            encoding: encoding,
            headers: headers
        ).validate(statusCode: 100..<600)

        let response = await request.serializingData(automaticallyCancelling: true).response

        guard let httpResponse = response.response else {
            throw response.error ?? URLError(.unknown)
        }
        guard let data = response.data else {
            throw URLError(.cannotDecodeContentData)
        }

        return (data, httpResponse.statusCode)
    }

    private static func isRefreshJwtEndpoint(_ endpoint: String) -> Bool {
        endpoint.contains("/api/auth/refreshJwt")
    }

    private static func isTwoFactorRequiredResponse(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String else { return false }
        return code == "twofa.TWO_FACTOR_REQUIRED"
    }

    /// 对齐 Flutter：`/api/auth/refreshJwt` 返回 401 时视为登录态不可恢复
    private func handleAuthSessionExpiredAfterRefreshJwt401() {
        clearAuthInfo()
        P2PService.shared.disconnect()
        NotificationCenter.default.post(name: .nasCabAuthSessionExpired, object: nil)
    }

    private func handleResponse<T>(_ response: (Data, Int), dataParser: (([String: Any], Int) -> T)?) -> APIResponse<T> {
        let (data, statusCode) = response
        guard !data.isEmpty else {
            return .failure(L10n.networkFailure)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(L10n.networkFailure)
        }
        return APIResponse.fromJSON(httpCode: statusCode, json: json, dataParser: dataParser)
    }

    // MARK: - Token Management

    func refreshAuthToken() async -> Bool {
        if let existing = refreshCoalescedTask {
            return await existing.value
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            defer { self.refreshCoalescedTask = nil }
            return await self.performRefreshAuthTokenBody()
        }
        refreshCoalescedTask = task
        return await task.value
    }

    private func performRefreshAuthTokenBody() async -> Bool {
        guard let refreshToken = state.refreshToken else { return false }
        let response: APIResponse<LoginResponse> = await apiPost(
            "/api/auth/refreshJwt",
            body: ["refreshToken": refreshToken],
            dataParser: { data, code in LoginResponse.from(json: data, httpCode: code) }
        )
        guard response.success, let data = response.data,
              let token = data.accessToken,
              let refresh = data.refreshToken,
              let serverId = data.serverId,
              let expires = data.expiresIn else {
            return false
        }
        setAuthInfo(
            serverId: serverId,
            accessToken: token,
            refreshToken: refresh,
            expiresIn: expires,
            shellSupported: state.shellSupported
        )
        return true
    }

    private func startTokenRefreshTimer() {
        refreshTimer?.invalidate()
        guard state.isAuthenticated else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: NetworkConfig.tokenRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.state.isTokenExpiringSoon {
                    _ = await self.refreshAuthToken()
                }
            }
        }
    }

    // MARK: - Storage

    private func loadStoredTokens() {
        let stored = UserDefaults.standard
        if let url = stored.string(forKey: "auth_baseUrl"), !url.isEmpty {
            state.baseUrl = url
        }
        state.serverId = stored.string(forKey: "auth_serverId") ?? ""
        let storedAccess = stored.string(forKey: "auth_accessToken")
        let storedRefresh = stored.string(forKey: "auth_refreshToken")
        let expiryTimestamp = stored.integer(forKey: "auth_expiresIn")
        state.shellSupported = stored.bool(forKey: "auth_shellSupported")
        let storedVer = stored.string(forKey: "auth_serverVersion")?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.serverVersion = (storedVer?.isEmpty == false) ? storedVer : nil

        var expiry: Date?
        if expiryTimestamp > 0 {
            expiry = Date(timeIntervalSince1970: TimeInterval(expiryTimestamp / 1000))
        }
        let isValid = expiry != nil && expiry! > Date()

        state.accessToken = isValid ? storedAccess : nil
        state.refreshToken = storedRefresh
        state.isAuthenticated = isValid && storedAccess != nil
        state.expiresAt = expiry

        startTokenRefreshTimer()

        if !isValid, let refresh = storedRefresh, !refresh.isEmpty {
            Task { _ = await refreshAuthToken() }
        }
    }

    private func saveTokensToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(state.baseUrl, forKey: "auth_baseUrl")
        defaults.set(state.serverId, forKey: "auth_serverId")
        defaults.set(state.accessToken ?? "", forKey: "auth_accessToken")
        defaults.set(state.refreshToken ?? "", forKey: "auth_refreshToken")
        defaults.set(Int(state.expiresAt?.timeIntervalSince1970 ?? 0) * 1000, forKey: "auth_expiresIn")
        defaults.set(state.shellSupported, forKey: "auth_shellSupported")
        defaults.set(state.serverVersion ?? "", forKey: "auth_serverVersion")
    }

    private func clearStoredTokens() {
        let keys = ["auth_accessToken", "auth_refreshToken", "auth_expiresIn", "auth_serverId", "auth_baseUrl", "auth_shellSupported", "auth_serverVersion"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - P2P Request Proxy

    private func sendRequestViaP2P(
        method: HTTPMethod,
        endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, Int) {
        var didRetryAfterRefresh = false
        while true {
            let (data, statusCode) = try await sendP2pRequestOnce(
                method: method,
                endpoint: endpoint,
                body: body,
                queryParams: queryParams,
                timeout: timeout
            )

            if statusCode != 401 {
                return (data, statusCode)
            }

            if Self.isRefreshJwtEndpoint(endpoint) {
                handleAuthSessionExpiredAfterRefreshJwt401()
                return (data, statusCode)
            }

            if Self.isTwoFactorRequiredResponse(data) {
                return (data, statusCode)
            }

            if didRetryAfterRefresh {
                return (data, statusCode)
            }

            let refreshed = await refreshAuthToken()
            if !refreshed {
                return (data, statusCode)
            }
            didRetryAfterRefresh = true
        }
    }

    private func sendP2pRequestOnce(
        method: HTTPMethod,
        endpoint: String,
        body: [String: Any]? = nil,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, Int) {
        var path = endpoint
        if let queryParams, !queryParams.isEmpty {
            var components = URLComponents(string: path)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let full = components?.string {
                path = full
            }
        }

        var headers: [String: String] = [:]
        if let token = state.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        headers["Accept-Language"] = L10n.currentLanguageCode.replacingOccurrences(of: "_", with: "-")

        var bodyData = Data()
        if method != .get, let body, !body.isEmpty {
            headers["Content-Type"] = "application/json"
            bodyData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        }

        print("[P2P] APIClient: sendRequestViaP2P \(method.rawValue) \(path)")
        let response = try await P2PService.shared.sendApiRequest(
            method: method.rawValue,
            path: path,
            headers: headers,
            bodyBytes: bodyData,
            timeout: timeout ?? NetworkConfig.defaultTimeout
        )
        print("[P2P] APIClient: sendRequestViaP2P response status=\(response.status)")

        return (response.bodyBytes, response.status)
    }

    // MARK: - Pair Code Validation

    static func validatePairCode(_ value: String?) -> String? {
        let s = (value ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return L10n.serverPairCodeEmpty }
        if s.count < 4 { return L10n.serverPairCodeInvalid }
        if s.count > 32 { return L10n.serverPairCodeInvalid }
        return nil
    }
}
