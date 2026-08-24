import Foundation
import SwiftUI

@MainActor
final class ServerListViewModel: ObservableObject {
    @Published var savedServers: [ServerInfo] = []
    @Published var discoveredServers: [ServerInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false

    @Published var navigateToAddServer = false
    @Published var navigateToEditServer = false
    @Published var navigateToPairCode = false
    @Published var selectedServer: ServerInfo?

    @Published var showDeleteConfirm = false
    @Published var serverToDelete: ServerInfo?

    @Published var showPasswordPrompt = false
    @Published var passwordPromptServer: ServerInfo?
    /// true = 密码错误重试，false = 每次登录都需输入密码（登录前弹框）
    @Published var passwordPromptIsRetry = true
    /// 登录前弹密码框时使用的 baseUrlOverride（P2P 模式需要）
    private var passwordPromptBaseUrlOverride: String?

    @Published var show2FAPrompt = false
    @Published var twoFATempToken: String?
    @Published var twoFAServer: ServerInfo?

    /// 当前是否为“编辑服务器并验证登录”流程，成功后只保存不跳转首页
    @Published var isEditValidationFlow = false

    /// 登录成功后展示首页（程序打开后默认进服务器列表，登录成功才进首页）
    @Published var showHomeAfterLogin = false

    private let storage = ServerStorageService.shared
    private let auth = AuthService.shared
    private let api = APIClient.shared
    private let p2p = P2PService.shared
    private let udpListener = UdpBroadcastListener()

    func loadServers() {
        savedServers = storage.loadServers()
        removeSavedFromDiscovered()
    }

    func startUdpListening() {
        udpListener.setOnServerDiscovered { [weak self] serverInfo in
            self?.handleDiscoveredServer(serverInfo)
        }
        udpListener.startListening()
    }

    func stopUdpListening() {
        udpListener.stopListening()
    }

    private func removeSavedFromDiscovered() {
        let savedIds = Set(savedServers.map { $0.serverId.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard !savedIds.isEmpty else { return }
        discoveredServers.removeAll { savedIds.contains($0.serverId.trimmingCharacters(in: .whitespaces)) }
    }

    private func handleDiscoveredServer(_ serverInfo: [String: Any]) {
        guard let host = serverInfo["host"] as? String, !host.isEmpty else { return }
        let port: Int
        if let p = serverInfo["port"] as? Int { port = p }
        else if let s = serverInfo["port"] as? String, let p = Int(s) { port = p }
        else { return }
        let serverId = (serverInfo["serverId"] as? String) ?? ""
        let httpsPort = (serverInfo["httpsPort"] as? Int).map(String.init) ?? ""
        let hostname = serverInfo["hostname"] as? String ?? ""
        let platform = serverInfo["platform"] as? String ?? "unknown"
        let serverUrl = "http://\(host):\(port)"

        if let idx = savedServers.firstIndex(where: { $0.serverId.trimmingCharacters(in: .whitespaces) == serverId && !serverId.isEmpty }) {
            var s = savedServers[idx]
            s.serverUrl = serverUrl
            s.serverHost = host
            s.serverPortHttp = String(port)
            s.serverPortHttps = httpsPort
            s.serverHostName = hostname
            s.serverPlatform = platform
            savedServers[idx] = s
            storage.addServer(s)
            return
        }

        let exists = discoveredServers.contains { $0.serverId.trimmingCharacters(in: .whitespaces) == serverId && !serverId.isEmpty }
        if exists { return }

        let item = ServerInfo(
            serverId: serverId,
            serverUrl: serverUrl,
            userInputUrl: nil,
            serverName: "NasCabServer",
            serverHost: host,
            serverPortHttp: String(port),
            serverPortHttps: httpsPort,
            serverHostName: hostname,
            serverPlatform: platform,
            isAutoScanned: true,
            isLocalServer: false,
            isP2p: false,
            pairCode: nil,
            requirePasswordEveryLogin: false
        )
        if savedServers.contains(where: { $0.serverId.trimmingCharacters(in: .whitespaces) == item.serverId.trimmingCharacters(in: .whitespaces) && !item.serverId.isEmpty }) {
            return
        }
        discoveredServers.append(item)
    }

    // MARK: - Server Tap

    /// 与 Flutter `server_list_controller` 一致：IP 直连(serverUrl) > 局域网(lan) > P2P；探测超时与 P2P 对齐，避免过短误走中继
    private static let directProbeTimeout: TimeInterval = 8

    /// tvOS 同桌面端：始终允许尝试局域网 IP（无「仅移动蜂窝跳过 LAN」场景）
    private static var onWifiForLanProbe: Bool { true }

    private static func isServerStatusIncomplete(_ s: ServerStatusResponse?) -> Bool {
        guard let s else { return true }
        return !s.success || !s.isNasCabServer
    }

    /// 处理服务器点击：顺序探测，不在 IP 可用时并行/等待 P2P（避免后台 P2P 抢连覆盖 baseUrl）
    func handleServerTap(_ server: ServerInfo) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let hasPairCode = server.hasPairCode
        let hasDirectUrl = server.hasDirectUrl && server.serverUrl.trimmingCharacters(in: .whitespaces) != NetworkConfig.p2pBaseUrl
        let onWifi = Self.onWifiForLanProbe

        do {
            var status: ServerStatusResponse?
            var usingP2p = false

            if hasPairCode {
                // 1) serverUrl 直连：仅在「类 WiFi」或 serverUrl 为公网时尝试（对齐 Flutter）
                if hasDirectUrl,
                   (onWifi || !Self.isUrlPrivateLan(server.serverUrl)) {
                    p2p.disconnect()
                    let url = server.serverUrl.trimmingCharacters(in: .whitespaces)
                    api.setBaseUrl(url)
                    status = await auth.checkServerStatus(timeout: Self.directProbeTimeout)
                }

                // 2) 局域网 IPv4 + 端口
                if Self.isServerStatusIncomplete(status) {
                    let lan = (server.lanIpv4 ?? "").trimmingCharacters(in: .whitespaces)
                    let httpP = server.serverPortHttp.trimmingCharacters(in: .whitespaces)
                    let httpsP = server.serverPortHttps.trimmingCharacters(in: .whitespaces)
                    let port = httpP.isEmpty ? (httpsP.isEmpty ? "9000" : httpsP) : httpP
                    let lanUrl = lan.isEmpty ? "" : "http://\(lan):\(port)"
                    let lanUrlAlreadyTried = !lanUrl.isEmpty && Self.normalizeUrl(lanUrl) == Self.normalizeUrl(server.serverUrl)

                    if !lan.isEmpty && onWifi && !lanUrlAlreadyTried {
                        p2p.disconnect()
                        api.setBaseUrl(lanUrl)
                        let lanStatus = await auth.checkServerStatus(timeout: Self.directProbeTimeout)
                        let statusServerId = (lanStatus.serverData?["serverId"] as? String) ?? ""
                        let itemServerId = server.serverId.trimmingCharacters(in: .whitespaces)
                        if lanStatus.success,
                           lanStatus.isNasCabServer,
                           !statusServerId.isEmpty,
                           statusServerId == itemServerId {
                            status = lanStatus
                            usingP2p = false
                        }
                    }
                }

                // 3) P2P
                if Self.isServerStatusIncomplete(status) {
                    usingP2p = true
                    try await ensureP2pConnected(server)
                    api.setBaseUrl(NetworkConfig.p2pBaseUrl)
                    status = await auth.checkServerStatus(timeout: Self.directProbeTimeout)
                }
            } else if hasDirectUrl {
                p2p.disconnect()
                api.setBaseUrl(server.serverUrl)
                status = await auth.checkServerStatus(timeout: Self.directProbeTimeout)
            }

            guard let s = status, s.success, s.isNasCabServer else {
                showErrorAlert(L10n.serverConnectFail)
                return
            }

            let hasSuperAdmin = s.serverData?["hasSuperAdmin"] as? Bool ?? false
            if !hasSuperAdmin {
                selectedServer = server
                navigateToAddServer = true
                return
            }

            if server.isAutoScanned {
                var mutable = server
                if usingP2p {
                    mutable.serverId = (s.serverData?["serverId"] as? String) ?? server.serverId
                    mutable.serverHostName = (s.serverData?["hostname"] as? String) ?? server.serverHostName
                    mutable.serverPlatform = (s.serverData?["platform"] as? String) ?? server.serverPlatform
                }
                selectedServer = mutable
                navigateToAddServer = true
                return
            }

            if server.requirePasswordEveryLogin {
                passwordPromptServer = server
                passwordPromptIsRetry = false
                passwordPromptBaseUrlOverride = usingP2p ? NetworkConfig.p2pBaseUrl : nil
                showPasswordPrompt = true
                return
            }

            await loginToServer(server, baseUrlOverride: usingP2p ? NetworkConfig.p2pBaseUrl : nil, isEditValidation: false)
        } catch {
            showErrorAlert(L10n.tr("server_status_check_failed_with_error", params: ["error": error.localizedDescription]))
        }
    }

    /// 与 Flutter connectP2pByPairCode：遇 P2P_DEVICE_OFFLINE 时重试
    private func ensureP2pConnected(_ server: ServerInfo) async throws {
        guard let code = server.pairCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty else {
            throw P2PError.emptyPairCode
        }
        let maxRetries = 3
        let retryDelay: TimeInterval = 1.5
        for attempt in 1...maxRetries {
            do {
                try await p2p.connectByPairCode(code)
                return
            } catch {
                let msg = error.localizedDescription
                let offline =
                    msg.range(of: "P2P_DEVICE_OFFLINE", options: .caseInsensitive) != nil
                    || msg.range(of: "offline", options: .caseInsensitive) != nil
                if offline && attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
    }

    /// 与 Flutter connectP2pByPairCodeAndCheckServerStatus(timeout: 20s) 一致，中继首包可能较慢
    private static let pairCodeConnectCheckTimeout: TimeInterval = 20

    /// 标准化 URL 用于比较（与 Flutter `_normalizeUrl` 一致）
    private static func normalizeUrl(_ url: String) -> String {
        let t = url.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t), let host = u.host else { return t.lowercased() }
        let scheme = (u.scheme ?? "http").lowercased()
        let hostLower = host.lowercased()
        let portPart = u.port != nil ? ":\(u.port!)" : ""
        var path = u.path
        while path.hasSuffix("/"), path.count > 1 { path.removeLast() }
        return "\(scheme)://\(hostLower)\(portPart)\(path)"
    }

    /// 是否为私有 IPv4 局域网地址（与 Flutter `_isPrivateIpv4` 一致）
    private static func isUrlPrivateLan(_ urlString: String) -> Bool {
        guard let u = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let host = u.host, Self.isIpv4(host) else { return false }
        return Self.isPrivateIpv4(host)
    }

    private static func isIpv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let n = Int(p), (0...255).contains(n) else { return false }
        }
        return true
    }

    private static func isPrivateIpv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]),
              let b = Int(parts[1]) else { return false }
        if a == 10 { return true }
        if a == 172 && b >= 16 && b <= 31 { return true }
        if a == 192 && b == 168 { return true }
        if a == 127 { return true }
        return false
    }

    // MARK: - Login

    func loginToServer(_ server: ServerInfo, baseUrlOverride: String? = nil, isEditValidation: Bool = false) async {
        if isEditValidation { isEditValidationFlow = true }
        if let override = baseUrlOverride?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            api.setBaseUrl(override)
        } else if !api.isP2pMode {
            let url = server.serverUrl.trimmingCharacters(in: .whitespaces)
            if !url.isEmpty { api.setBaseUrl(url) }
        }

        let result = await auth.login(serverInfo: server)
        if result.success {
            if result.twoFactorRequired, let tempToken = result.tempToken, !tempToken.isEmpty {
                twoFAServer = server
                twoFATempToken = tempToken
                show2FAPrompt = true
                return
            }
            handleLoginSuccess(server, result, isEditValidation: isEditValidation)
        } else {
            if result.code == 999 {
                passwordPromptServer = server
                passwordPromptIsRetry = true
                showPasswordPrompt = true
            } else {
                showErrorAlert(result.message ?? L10n.authLoginFailure)
            }
        }
    }

    func submitTwoFactor(code: String) async {
        guard let server = twoFAServer, let tempToken = twoFATempToken else { return }
        isLoading = true
        defer { isLoading = false }

        let result = await auth.verifyTwoFactorLogin(tempToken: tempToken, code: code)
        show2FAPrompt = false
        if result.success {
            handleLoginSuccess(server, result, isEditValidation: isEditValidationFlow)
        } else {
            showErrorAlert(result.message ?? L10n.authLoginFailure)
        }
    }

    func retryLoginWithPassword(_ password: String) async {
        guard var server = passwordPromptServer else { return }
        showPasswordPrompt = false
        server.password = password
        isLoading = true
        defer { isLoading = false }
        await loginToServer(server, baseUrlOverride: passwordPromptBaseUrlOverride, isEditValidation: isEditValidationFlow)
        passwordPromptBaseUrlOverride = nil
    }

    private func handleLoginSuccess(_ server: ServerInfo, _ result: LoginResponse, isEditValidation: Bool = false) {
        var mutable = server
        mutable.accessToken = result.accessToken
        mutable.serverId = result.serverId ?? "unknown"
        mutable.serverPlatform = result.platform ?? "unknown"
        mutable.serverHostName = result.hostname ?? "unknown"
        mutable.refreshToken = result.refreshToken

        if let httpPort = result.httpPort { mutable.serverPortHttp = httpPort }
        if let httpsPort = result.httpsPort { mutable.serverPortHttps = httpsPort }
        // 若服务器返回了最新配对码则更新本地，表示服务器配对码已变更（与 Flutter _handleLoginSuccess 逻辑一致）
        if let pair = result.pairCode?.trimmingCharacters(in: .whitespaces), !pair.isEmpty {
            mutable.pairCode = pair
        }
        if let lan = result.lanIpv4?.trimmingCharacters(in: .whitespaces), !lan.isEmpty {
            mutable.lanIpv4 = lan
            mutable.lanHttpPort = result.httpPort
            mutable.lanHttpsPort = result.httpsPort
            let currentUrl = mutable.serverUrl.trimmingCharacters(in: .whitespaces)
            if currentUrl.isEmpty {
                let rawPort = (result.httpPort ?? result.httpsPort)?.trimmingCharacters(in: .whitespaces) ?? ""
                let port = rawPort.isEmpty ? "9000" : rawPort
                mutable.serverUrl = "http://\(lan):\(port)"
                mutable.userInputUrl = mutable.serverUrl
            }
        }
        mutable.isP2p = mutable.serverUrl.trimmingCharacters(in: .whitespaces).isEmpty && mutable.hasPairCode

        storage.addServer(mutable)
        loadServers()

        if isEditValidation {
            isEditValidationFlow = false
            navigateToEditServer = false
            return
        }
        showHomeAfterLogin = true
        api.setAuthInfo(
            serverId: mutable.serverId,
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
            expiresIn: result.expiresIn!,
            shellSupported: result.shellSupported,
            serverVersion: result.serverVersion
        )
    }

    // MARK: - Pair Code

    func addServerByPairCode(_ code: String) async {
        print("[P2P] ServerListViewModel: addServerByPairCode start, code length=\(code.count)")
        // 配对码页使用 PairCodeInputView 本地 isConnecting；勿开全局 isLoading，避免根 overlay 与 tvOS 层级干扰

        do {
            print("[P2P] ServerListViewModel: calling p2p.connectAndCheckStatus timeout=\(Self.pairCodeConnectCheckTimeout)")
            let status = try await p2p.connectAndCheckStatus(code, timeout: Self.pairCodeConnectCheckTimeout)
            print("[P2P] ServerListViewModel: connectAndCheckStatus returned success=\(status.success) isNasCabServer=\(status.isNasCabServer)")
            guard status.success, status.isNasCabServer else {
                print("[P2P] ServerListViewModel: guard failed, showing serverConnectFail")
                showErrorAlert(L10n.serverConnectFail)
                return
            }

            let serverId = (status.serverData?["serverId"] as? String) ?? ""
            print("[P2P] ServerListViewModel: building candidate serverId=\(serverId)")

            // 如果本地已存在同 serverId 的服务器，仅用于回填展示信息，不在此阶段写入数据库
            let matches = savedServers.filter {
                let id = $0.serverId.trimmingCharacters(in: .whitespaces)
                return !id.isEmpty && id == serverId
            }
            let preferred = matches.count == 1 ? matches.first : nil

            // 通过配对码新增服务器：不预先保存到本地，仅构造一个临时 ServerInfo 供添加页使用
            // 添加页中用户填写用户名/密码并登录成功后，才在 handleLoginSuccess 中真正写入数据库
            let candidate = ServerInfo(
                serverId: serverId,
                serverUrl: "",              // 不展示服务器地址，由 P2P 通道负责
                userInputUrl: nil,
                serverName: preferred?.serverName ?? "NasCabServer",
                serverHost: "",
                serverPortHttp: (status.serverData?["httpPort"] as? String) ?? "",
                serverPortHttps: (status.serverData?["httpsPort"] as? String) ?? "",
                serverHostName: (status.serverData?["hostname"] as? String) ?? "",
                serverPlatform: (status.serverData?["platform"] as? String) ?? "unknown",
                isAutoScanned: false,
                isLocalServer: false,
                isP2p: true,
                pairCode: code,
                requirePasswordEveryLogin: false
            )

            selectedServer = candidate
            navigateToAddServer = true
            print("[P2P] ServerListViewModel: success, navigateToAddServer=true")
        } catch {
            print("[P2P] ServerListViewModel: catch error type=\(type(of: error)) desc=\(error.localizedDescription)")
            showErrorAlert(error.localizedDescription)
        }
    }

    // MARK: - CRUD

    func deleteServer(_ server: ServerInfo) {
        storage.removeServer(server)
        loadServers()
    }

    func confirmDelete(_ server: ServerInfo) {
        serverToDelete = server
        showDeleteConfirm = true
    }

    func executeDelete() {
        guard let server = serverToDelete else { return }
        deleteServer(server)
        serverToDelete = nil
        showDeleteConfirm = false
    }

    func editServer(_ server: ServerInfo) {
        selectedServer = server
        navigateToEditServer = true
    }

    /// 编辑服务器时先验证登录，成功后再保存并关闭编辑页
    func saveEditedServer(_ server: ServerInfo) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let hasPairCode = server.hasPairCode
        let hasDirectUrl = server.hasDirectUrl && server.serverUrl.trimmingCharacters(in: .whitespaces) != NetworkConfig.p2pBaseUrl

        do {
            var baseUrlOverride: String? = nil
            if hasDirectUrl {
                p2p.disconnect()
                api.setBaseUrl(server.serverUrl)
            } else if hasPairCode {
                let lan = (server.lanIpv4 ?? "").trimmingCharacters(in: .whitespaces)
                let httpP = server.serverPortHttp.trimmingCharacters(in: .whitespaces)
                let httpsP = server.serverPortHttps.trimmingCharacters(in: .whitespaces)
                let port = httpP.isEmpty ? (httpsP.isEmpty ? "9000" : httpsP) : httpP
                if !lan.isEmpty {
                    p2p.disconnect()
                    let lanUrl = "http://\(lan):\(port)"
                    api.setBaseUrl(lanUrl)
                    let lanStatus = await auth.checkServerStatus(timeout: 2)
                    let statusServerId = (lanStatus.serverData?["serverId"] as? String) ?? ""
                    let itemServerId = server.serverId.trimmingCharacters(in: .whitespaces)
                    if lanStatus.success, lanStatus.isNasCabServer, !statusServerId.isEmpty, statusServerId == itemServerId {
                        baseUrlOverride = nil
                    } else {
                        try await p2p.connectByPairCode(server.pairCode!)
                        baseUrlOverride = NetworkConfig.p2pBaseUrl
                    }
                } else {
                    try await p2p.connectByPairCode(server.pairCode!)
                    baseUrlOverride = NetworkConfig.p2pBaseUrl
                }
            }
            await loginToServer(server, baseUrlOverride: baseUrlOverride, isEditValidation: true)
        } catch {
            showErrorAlert(L10n.tr("server_status_check_failed_with_error", params: ["error": error.localizedDescription]))
        }
    }

    func editPairCode(_ server: ServerInfo) {
        selectedServer = server
        navigateToPairCode = true
    }

    func updatePairCode(_ server: ServerInfo, newCode: String) {
        var mutable = server
        mutable.pairCode = newCode
        storage.addServer(mutable)
        loadServers()
    }

    // MARK: - Helpers

    private func showErrorAlert(_ message: String) {
        print("[P2P] ServerListViewModel: showErrorAlert message=\(message)")
        errorMessage = message
        showError = true
    }
}
