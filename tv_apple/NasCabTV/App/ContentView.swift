import SwiftUI

struct ContentView: View {
    @EnvironmentObject var apiClient: APIClient
    @State private var showHome = false
    @State private var showSessionExpiredAlert = false

    /// 程序打开后默认进入服务器列表页，用户从服务器列表登录成功后才进入首页
    /// 使用根视图切换而非 fullScreenCover，避免底层页面透出重影
    var body: some View {
        Group {
            if showHome {
                HomeView(onLogout: { showHome = false })
            } else {
                ServerListView(onLoginSuccess: { showHome = true })
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showHome)
        .onReceive(NotificationCenter.default.publisher(for: .nasCabAuthSessionExpired)) { _ in
            showHome = false
            showSessionExpiredAlert = true
        }
        .alert(L10n.error, isPresented: $showSessionExpiredAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.serviceSessionExpired)
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var apiClient: APIClient
    var onLogout: (() -> Void)? = nil
    @EnvironmentObject var p2pService: P2PService
    @AppStorage("selected_language") private var selectedLanguage: String = L10n.systemLanguageCode
    @AppStorage(VideoPlaybackSettings.defaultsKey) private var defaultPlaybackQuality: String = VideoPlaybackSettings.qualityOriginal
    @State private var showLanguagePicker = false
    @State private var showVideoPlaybackSettings = false
    @State private var showLogoutConfirm = false
    @State private var devConnectMode = DevConnectModeManager.load()
    @State private var connectivityStatus: ConnectivityStatus = .checking
    @State private var isApplyingChannel = false
    @State private var showVideoLibrary = false
    @State private var showPhotoLibrary = false
    @State private var showMusicLibrary = false
    @State private var showMusicPlayerSheet = false
    @StateObject private var musicPlayerService = MusicPlayerService.shared
    @State private var showExitConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(alignment: .leading, spacing: 48) {
                        headerSection
                            .focusSection()
                        featureCardsSection
                            .focusSection()
                        #if DEBUG
                        devChannelSection
                            .focusSection()
                        #endif
                    }
                    .padding(.horizontal, 64)
                    .padding(.vertical, 48)
                }
                .fullScreenCover(isPresented: $showVideoLibrary) {
                    VideoLibraryView()
                }
                .fullScreenCover(isPresented: $showPhotoLibrary) {
                    PhotoLibraryView()
                }
                .fullScreenCover(isPresented: $showMusicLibrary) {
                    MusicLibraryView()
                }
                .fullScreenCover(isPresented: $showMusicPlayerSheet) {
                    MusicPlayerSheetView()
                }
                .fullScreenCover(isPresented: $showVideoPlaybackSettings) {
                    VideoPlaybackSettingsView()
                }
            }
            .navigationTitle("")
            .onExitCommand {
                showExitConfirm = true
            }
            .confirmationDialog(L10n.homeLogoutConfirmTitle, isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button(L10n.homeLogout, role: .destructive) {
                    Task { await performLogout() }
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.homeLogoutConfirmMessage)
            }
            .alert(L10n.language, isPresented: $showLanguagePicker) {
                ForEach(L10n.supportedLocales, id: \.code) { locale in
                    Button(locale.name) {
                        L10n.setLanguage(locale.code)
                        selectedLanguage = locale.code
                    }
                }
                Button("✕", role: .cancel) {}
            }
            .alert(L10n.tr("server_list_exit_title"), isPresented: $showExitConfirm) {
                Button(L10n.ok, role: .destructive) {
                    exit(0)
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.tr("server_list_exit_content"))
            }
            .onAppear {
                devConnectMode = DevConnectModeManager.load()
                Task { await updateConnectivity() }
            }
        }
        .id(selectedLanguage)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(.systemIndigo).opacity(0.12),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerSection: some View {
        HStack(spacing: 16) {
            Image(systemName: "appletv")
                .font(.system(size: 52))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("NasCabOS TV")
                    .font(.title)
                    .fontWeight(.bold)
                Text(channelDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private var currentLanguageName: String {
        L10n.supportedLocales.first(where: { $0.code == selectedLanguage })?.name ?? selectedLanguage
    }

    /// 顶部地址/通道信息展示逻辑
    private var channelDisplayText: String {
        if !apiClient.isP2pMode {
            return apiClient.baseUrl
        }
        #if DEBUG
        // 开发模式下：P2P 中继模式显示具体 TURN 地址，类似 Flutter 的 connectChannelDisplayValue
        if devConnectMode == .p2pRelay {
            let addr = p2pService.relayAddress.trimmingCharacters(in: .whitespaces)
            return addr.isEmpty ? "P2P" : "P2P \(addr)"
        }
        return "P2P"
        #else
        // 正式模式：只区分 P2P 直连 / 中继，不暴露具体节点
        switch devConnectMode {
        case .p2pRelay:
            return L10n.devConnectModeP2pRelay
        default:
            return L10n.devConnectModeP2pDirect
        }
        #endif
    }

    private var featureCardsSection: some View {
        VStack(alignment: .leading, spacing: 40) {
            HStack(spacing: 40) {
                HomeFeatureCard(
                    title: L10n.homeMediaLibrary,
                    icon: "home_video",
                    color: .orange
                ) {
                    showVideoLibrary = true
                }
                HomeFeatureCard(
                    title: L10n.homePhotoManagement,
                    icon: "home_photo",
                    color: .mint
                ) {
                    showPhotoLibrary = true
                }
            }
            HStack(spacing: 40) {
                HomeMusicFeatureCard(showMusicLibrary: $showMusicLibrary)
                HomeFeatureCard(
                    title: L10n.homeLogout,
                    icon: "home_logout",
                    color: .gray
                ) {
                    showLogoutConfirm = true
                }
            }
            languageCardSection
            videoPlaybackSettingsSection
        }
    }

    private var videoPlaybackSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.tr("home_video_playback_settings"), icon: "play.rectangle")
            HStack(spacing: 32) {
                NCActionCard(
                    title: VideoPlaybackSettings.label(for: defaultPlaybackQuality),
                    icon: "play.rectangle",
                    color: .orange
                ) {
                    showVideoPlaybackSettings = true
                }
            }
        }
    }

    private var languageCardSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.language, icon: "globe")
            HStack(spacing: 32) {
                NCActionCard(
                    title: currentLanguageName,
                    icon: "globe",
                    color: .accentColor
                ) {
                    showLanguagePicker = true
                }
            }
        }
    }

    #if DEBUG
    private var devChannelSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.serverConnectChannel, icon: "antenna.radiowaves.left.and.right")
            HStack(spacing: 24) {
                Button(action: cycleDevConnectMode) {
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(devConnectMode.displayName)
                                .font(.headline)
                            Text(connectivityStatus.displayText)
                                .font(.caption)
                                .foregroundStyle(connectivityStatus.color)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(NCCardButtonStyle(cornerRadius: 20))
                .disabled(isApplyingChannel)
            }
            if isApplyingChannel {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text(L10n.serverConnecting)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    #endif

    private func cycleDevConnectMode() {
        #if DEBUG
        let all = DevConnectMode.allCases
        guard let idx = all.firstIndex(of: devConnectMode) else { return }
        let next = all[(idx + 1) % all.count]
        devConnectMode = next
        DevConnectModeManager.save(next)
        Task {
            isApplyingChannel = true
            await DevConnectModeManager.apply(mode: next, apiClient: apiClient, p2pService: p2pService)
            isApplyingChannel = false
            await updateConnectivity()
        }
        #endif
    }

    private func updateConnectivity() async {
        connectivityStatus = .checking
        if apiClient.isP2pMode {
            switch p2pService.connectionState {
            case .connected: connectivityStatus = .ok
            case .connecting, .reconnecting: connectivityStatus = .checking
            case .failed, .disconnected: connectivityStatus = .fail
            }
        } else {
            let status = await AuthService.shared.checkServerStatus(timeout: 3)
            connectivityStatus = status.success && status.isNasCabServer ? .ok : .fail
        }
    }

    private func performLogout() async {
        await AuthService.shared.logout()
        onLogout?()
    }
}

// MARK: - Home Now Playing Card (only when music is playing)

struct HomeNowPlayingCard: View {
    @Binding var showPlayerSheet: Bool

    var body: some View {
        Button(action: { showPlayerSheet = true }) {
            VStack(spacing: 24) {
                ZStack {
                    Image(systemName: "music.note")
                        .font(.system(size: 56))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .pink.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    MusicPlayingIndicator()
                        .frame(width: 120, height: 120)
                }
                Text(L10n.musicNowPlaying)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 28, focusScale: 1.08))
    }
}

// MARK: - Home Music Feature Card (with playing animation)

struct HomeMusicFeatureCard: View {
    @Binding var showMusicLibrary: Bool
    @StateObject private var playerService = MusicPlayerService.shared
    @Environment(\.isFocused) private var isFocused: Bool

    var body: some View {
        Button(action: { showMusicLibrary = true }) {
            VStack(spacing: 24) {
                ZStack {
                    Image("home_music")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .shadow(color: isFocused ? Color.pink.opacity(0.8) : .clear,
                                radius: isFocused ? 25 : 0)

                    if playerService.isPlaying {
                        MusicPlayingIndicator()
                            .frame(width: 120, height: 120)
                    }
                }
                Text(L10n.homeMusicLibrary)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .padding(.horizontal, 32)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 28, focusScale: 1.08))
    }
}

// MARK: - Home Feature Card

struct HomeFeatureCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 24) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .shadow(
                        color: isFocused ? color.opacity(0.8) : .clear,
                        radius: isFocused ? 25 : 0
                    )
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .padding(.horizontal, 32)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 28, focusScale: 1.08))
    }
}

// MARK: - Connectivity Status

private enum ConnectivityStatus {
    case ok
    case fail
    case checking

    var displayText: String {
        switch self {
        case .ok: return L10n.connectivityOk
        case .fail: return L10n.connectivityFail
        case .checking: return L10n.connectivityChecking
        }
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .fail: return .red
        case .checking: return .orange
        }
    }
}
