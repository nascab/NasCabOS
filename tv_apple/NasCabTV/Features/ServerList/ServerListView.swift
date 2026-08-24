import SwiftUI

struct ServerListView: View {
    @StateObject private var viewModel = ServerListViewModel()
    @AppStorage("selected_language") private var selectedLanguage: String = L10n.systemLanguageCode
    @State private var showLanguagePicker = false
    var onLoginSuccess: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                mainContent
            }
            .navigationTitle(L10n.serverListTitle)
            .onAppear {
                viewModel.loadServers()
                viewModel.startUdpListening()
            }
            .onDisappear { viewModel.stopUdpListening() }
            .alert(L10n.delete, isPresented: $viewModel.showDeleteConfirm) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.delete, role: .destructive) {
                    viewModel.executeDelete()
                }
            } message: {
                if let server = viewModel.serverToDelete {
                    let name = server.serverName.isEmpty ? server.serverHostName : server.serverName
                    Text(L10n.tr("server_delete_confirm_message", params: ["serverName": name]))
                }
            }
            .sheet(isPresented: $viewModel.showPasswordPrompt) {
                PasswordPromptView(
                    isRetry: viewModel.passwordPromptIsRetry,
                    onSubmit: { password in
                        Task { await viewModel.retryLoginWithPassword(password) }
                    }
                )
            }
            .sheet(isPresented: $viewModel.show2FAPrompt) {
                TwoFactorPromptView { code in
                    Task { await viewModel.submitTwoFactor(code: code) }
                }
            }
            .onChange(of: viewModel.showHomeAfterLogin) { newValue in
                if newValue {
                    onLoginSuccess?()
                    viewModel.showHomeAfterLogin = false
                }
            }
            .navigationDestination(isPresented: $viewModel.navigateToAddServer) {
                AddServerView(
                    server: viewModel.selectedServer,
                    onSave: { server in
                        viewModel.navigateToAddServer = false
                        Task { await viewModel.handleServerTap(server) }
                    }
                )
            }
            .navigationDestination(isPresented: $viewModel.navigateToEditServer) {
                if let server = viewModel.selectedServer {
                    AddServerView(
                        server: server,
                        isEditing: true,
                        onSave: { updated in
                            Task { await viewModel.saveEditedServer(updated) }
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $viewModel.navigateToPairCode) {
                let initialCode = viewModel.selectedServer?.pairCode ?? ""
                PairCodeInputView(
                    viewModel: viewModel,
                    initialCode: initialCode,
                    onSubmit: { code in
                        viewModel.navigateToPairCode = false
                        // initialCode 为空：通过“配对码连接”新增服务器，只关闭配对码页面，不写入数据库
                        guard !initialCode.isEmpty, let server = viewModel.selectedServer else { return }
                        // initialCode 非空：编辑已保存服务器的配对码，允许立刻更新数据库
                        viewModel.updatePairCode(server, newCode: code)
                    }
                )
            }
            .confirmationDialog(L10n.language, isPresented: $showLanguagePicker, titleVisibility: .visible) {
                ForEach(L10n.supportedLocales, id: \.code) { locale in
                    Button(locale.name) {
                        L10n.setLanguage(locale.code)
                        selectedLanguage = locale.code
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    loadingOverlay
                }
            }
        }
        // 挂在 NavigationStack 上，避免从「配对码」子页触发时 alert 出现在导航页下层（tvOS）
        .alert(L10n.error, isPresented: $viewModel.showError) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .id(selectedLanguage)
    }

    // MARK: - Components

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(.systemIndigo).opacity(0.15),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                headerSection
                    .focusSection()
                savedServersSection
                    .focusSection()
                if !viewModel.discoveredServers.isEmpty {
                    discoveredServersSection
                        .focusSection()
                }
                actionButtonsSection
                    .focusSection()
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
        }
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
            }
            Spacer()
            languageBar
        }
        .padding(.bottom, 8)
    }

    private var languageBar: some View {
        HStack {
            Spacer()
            Button(action: { showLanguagePicker = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text(currentLanguageName)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
    }

    private var currentLanguageName: String {
        L10n.supportedLocales.first(where: { $0.code == selectedLanguage })?.name ?? selectedLanguage
    }

    private var savedServersSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.serverSaved, icon: "externaldrive.connected.to.line.below")

            if viewModel.savedServers.isEmpty {
                emptyStateCard
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 24),
                        GridItem(.flexible(), spacing: 24)
                    ],
                    spacing: 20
                ) {
                    ForEach(viewModel.savedServers) { server in
                        ServerCardView(
                            server: server,
                            onLogin: { Task { await viewModel.handleServerTap(server) } },
                            onEdit: { viewModel.editServer(server) },
                            onEditPairCode: { viewModel.editPairCode(server) },
                            onDelete: { viewModel.confirmDelete(server) }
                        )
                    }
                }
            }
        }
    }

    private var discoveredServersSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.serverScanned, icon: "wifi")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 24),
                    GridItem(.flexible(), spacing: 24)
                ],
                spacing: 20
            ) {
                ForEach(viewModel.discoveredServers) { server in
                    ServerCardView(
                        server: server,
                        onLogin: { Task { await viewModel.handleServerTap(server) } },
                        onEdit: {},
                        onEditPairCode: {},
                        onDelete: {}
                    )
                }
            }
        }
    }

    private var actionButtonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            NCSectionHeader(title: L10n.tr("quick_actions"), icon: "bolt.fill")

            HStack(spacing: 32) {
                NCActionCard(
                    title: L10n.serverAdd,
                    icon: "plus.circle.fill",
                    color: .accentColor
                ) {
                    viewModel.selectedServer = nil
                    viewModel.navigateToAddServer = true
                }

                NCActionCard(
                    title: L10n.serverAddByPairCodeTitle,
                    icon: "link.circle.fill",
                    color: .purple
                ) {
                    viewModel.selectedServer = nil
                    viewModel.navigateToPairCode = true
                }
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(.quaternary)
            Text(L10n.serverAdd)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(L10n.authLoginLoading)
                    .font(.headline)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Password Prompt

struct PasswordPromptView: View {
    /// true = 密码错误重试，false = 每次登录都需输入密码
    var isRetry: Bool = true
    let onSubmit: (String) -> Void
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    private var titleText: String {
        isRetry ? L10n.authPasswordError : L10n.password
    }

    private var messageText: String {
        isRetry ? L10n.authPasswordErrorMessage : L10n.serverRequirePasswordPromptMessage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(.systemIndigo).opacity(0.1), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)

                    Text(titleText)
                        .font(.title2)

                    Text(messageText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 24) {
                        NCSecureField(
                            label: L10n.password,
                            placeholder: L10n.authPasswordHint,
                            text: $password,
                            icon: "lock",
                            isFocused: isFieldFocused
                        )
                        .focused($isFieldFocused)

                        HStack(spacing: 32) {
                            NCSecondaryButton(title: L10n.cancel) { dismiss() }
                            NCPrimaryButton(title: L10n.ok, color: .purple) {
                                guard !password.isEmpty else { return }
                                onSubmit(password)
                            }
                        }
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .padding(64)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 2FA Prompt

struct TwoFactorPromptView: View {
    let onSubmit: (String) -> Void
    @State private var code = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)

                Text(L10n.auth2faTitle)
                    .font(.title2)

                Text(L10n.auth2faCodeLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)

                NCTextField(
                    label: L10n.auth2faCodeLabel,
                    placeholder: L10n.auth2faCodeLabel,
                    text: $code,
                    icon: "number",
                    isFocused: isFieldFocused
                )
                .focused($isFieldFocused)

                HStack(spacing: 24) {
                    NCSecondaryButton(title: L10n.cancel) { dismiss() }
                    NCPrimaryButton(title: L10n.ok) {
                        guard !code.isEmpty else { return }
                        onSubmit(code)
                    }
                }
            }
            .padding(64)
            .navigationTitle(L10n.auth2faTitle)
        }
    }
}
