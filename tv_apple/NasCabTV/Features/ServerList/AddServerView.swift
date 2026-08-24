import SwiftUI

struct AddServerView: View {
    let server: ServerInfo?
    var isEditing: Bool = false
    let onSave: (ServerInfo) -> Void

    @State private var serverUrl: String = ""
    @State private var serverName: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var pairCode: String = ""
    @State private var requirePasswordEveryLogin: Bool = false
    @State private var showValidation = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case url, name, username, password, pairCode
    }

    /// 是否为通过配对码进入的添加/编辑流程
    private var isP2pMode: Bool {
        (server?.isP2p ?? false) && (server?.hasPairCode ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                headerSection
                formSection
                buttonSection
            }
            .padding(64)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color(.systemIndigo).opacity(0.1), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { populateFields() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: isEditing ? "server.rack" : "plus.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text(isEditing ? L10n.edit : L10n.serverAddTitle)
                .font(.title)
                .fontWeight(.bold)

            if let server, !server.serverHostName.isEmpty {
                Text(server.serverHostName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formSection: some View {
        VStack(spacing: 24) {
            // 普通手动添加时显示服务器地址；配对码添加时隐藏服务器地址输入
            if !isP2pMode {
                NCTextField(
                    label: L10n.serverAddUrl,
                    placeholder: L10n.serverAddUrlHint,
                    text: $serverUrl,
                    icon: "link",
                    isRequired: true,
                    showValidation: showValidation,
                    isFocused: focusedField == .url
                )
                .focused($focusedField, equals: .url)
            }

            NCTextField(
                label: L10n.serverAddName,
                placeholder: L10n.serverAddNameHint,
                text: $serverName,
                icon: "tag",
                isFocused: focusedField == .name
            )
            .focused($focusedField, equals: .name)

            // 配对码添加流程中，展示不可编辑的配对码；手动添加时不显示配对码输入框
            if isP2pMode {
                NCTextField(
                    label: L10n.serverAddByPairCodeTitle,
                    placeholder: L10n.serverPairCodePlaceholder,
                    text: $pairCode,
                    icon: "link.circle"
                )
                // 仅用于展示，不允许修改或获得焦点
                .allowsHitTesting(false)
            }

            Divider().background(Color.gray.opacity(0.3))

            NCTextField(
                label: L10n.serverAddUsername,
                placeholder: L10n.serverAddUsernameHint,
                text: $username,
                icon: "person",
                isRequired: true,
                showValidation: showValidation,
                isFocused: focusedField == .username
            )
            .focused($focusedField, equals: .username)

            NCSecureField(
                label: L10n.serverAddPassword,
                placeholder: L10n.serverAddPasswordHint,
                text: $password,
                icon: "lock",
                isRequired: true,
                showValidation: showValidation,
                isFocused: focusedField == .password
            )
            .focused($focusedField, equals: .password)

            Toggle(L10n.serverAddRequirePasswordEveryLogin, isOn: $requirePasswordEveryLogin)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var buttonSection: some View {
        HStack(spacing: 32) {
            NCSecondaryButton(title: L10n.cancel) { dismiss() }
            // 使用与配对码确认相同的主按钮样式，统一视觉风格
            NCPrimaryButton(title: L10n.ok, color: .purple) { saveServer() }
        }
    }

    // MARK: - Logic

    private func populateFields() {
        guard let server else {
            // 新增服务器时设置默认名称
            serverName = "NasCabServer"
            return
        }
        serverUrl = server.userInputUrl ?? server.serverUrl
        serverName = server.serverName
        username = server.username ?? ""
        password = server.password ?? ""
        pairCode = server.pairCode ?? ""
        requirePasswordEveryLogin = server.requirePasswordEveryLogin
    }

    private func saveServer() {
        showValidation = true
        let url = serverUrl.trimmingCharacters(in: .whitespaces)
        let code = pairCode.trimmingCharacters(in: .whitespaces)
        let user = username.trimmingCharacters(in: .whitespaces)
        let pwd = password.trimmingCharacters(in: .whitespaces)

        guard !user.isEmpty, !pwd.isEmpty else { return }
        guard !url.isEmpty || !code.isEmpty else { return }

        var info = server ?? ServerInfo(
            serverId: "",
            serverUrl: url,
            serverName: serverName.trimmingCharacters(in: .whitespaces),
            serverHost: "",
            serverPortHttp: "",
            serverPortHttps: "",
            serverHostName: "",
            serverPlatform: "unknown",
            isAutoScanned: false,
            isLocalServer: false,
            isP2p: url.isEmpty && !code.isEmpty,
            requirePasswordEveryLogin: false
        )

        info.serverUrl = url
        info.userInputUrl = url
        info.serverName = serverName.trimmingCharacters(in: .whitespaces)
        info.username = user
        info.password = pwd
        info.isAutoScanned = false
        if !code.isEmpty {
            info.pairCode = code
        }
        info.isP2p = url.isEmpty && !code.isEmpty
        info.requirePasswordEveryLogin = requirePasswordEveryLogin
        if requirePasswordEveryLogin {
            info.password = nil  // 不保存密码，每次登录都弹框输入
        }

        onSave(info)
    }
}
