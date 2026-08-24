import Foundation

/// 开发模式下可强制切换的连接通道：直连、P2P直连、P2P中继
enum DevConnectMode: String, CaseIterable {
    case direct
    case p2pDirect
    case p2pRelay

    var displayName: String {
        switch self {
        case .direct: return L10n.devConnectModeDirect
        case .p2pDirect: return L10n.devConnectModeP2pDirect
        case .p2pRelay: return L10n.devConnectModeP2pRelay
        }
    }

    /// P2P 连接时传给 WebRTC 的 iceTransportPolicy：nil = 自动，relay = 仅中继
    var p2pIceTransportPolicy: String? {
        switch self {
        case .direct: return nil
        case .p2pDirect: return nil  // 不限制，优先直连
        case .p2pRelay: return "relay"
        }
    }
}

/// 开发模式连接通道管理：持久化与应用
enum DevConnectModeManager {
    private static let key = "dev_connect_mode"

    static func load() -> DevConnectMode {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: key),
              let mode = DevConnectMode(rawValue: raw) else {
            return .direct
        }
        return mode
        #else
        return .direct
        #endif
    }

    static func save(_ mode: DevConnectMode) {
        #if DEBUG
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        #endif
    }

    /// 应用当前模式：直连则切到服务器 URL 并断开 P2P；P2P 则切到 p2p.local 并可能重连
    @MainActor
    static func apply(mode: DevConnectMode, apiClient: APIClient, p2pService: P2PService) async {
        #if DEBUG
        switch mode {
        case .direct:
            p2pService.disconnect()
            if let server = currentServer() {
                let url = server.serverUrl.trimmingCharacters(in: .whitespaces)
                if !url.isEmpty {
                    apiClient.setBaseUrl(url)
                }
            }
        case .p2pDirect, .p2pRelay:
            apiClient.setBaseUrl(NetworkConfig.p2pBaseUrl)
            let code = p2pService.storedPairCode
            if !code.isEmpty {
                try? await p2pService.connectByPairCode(code, iceTransportPolicy: mode.p2pIceTransportPolicy)
            }
        }
        #endif
    }

    @MainActor
    private static func currentServer() -> ServerInfo? {
        let serverId = APIClient.shared.state.serverId.trimmingCharacters(in: .whitespaces)
        if serverId.isEmpty { return ServerStorageService.shared.getLastSelected() }
        return ServerStorageService.shared.loadServers().first { $0.serverId == serverId }
    }
}
