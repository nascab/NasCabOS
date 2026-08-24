import SwiftUI
import UIKit

// MARK: - 无代理 URLSession（避免 127.0.0.1 请求触发 PAC 查询导致 XPC 报错与缩略图加载失败）

private enum NCImageLoadingSession {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()
}

// MARK: - Focus-Aware Card Button Style

struct NCCardButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20
    var focusScale: CGFloat = 1.05

    func makeBody(configuration: Configuration) -> some View {
        NCCardButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            focusScale: focusScale
        )
    }
}

private struct NCCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let focusScale: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused
                            ? LinearGradient(
                                colors: [.white.opacity(0.7), .accentColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: isFocused ? 3 : 0
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? focusScale : 1.0))
            .rotation3DEffect(
                .degrees(isFocused ? 1.5 : 0),
                axis: (x: 0.3, y: 1, z: 0),
                perspective: 0.5
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 卡片仅描边焦点样式（不放大、不 3D，仅通用 border，用于影集/智能影集/合集等）

struct NCCardFocusBorderOnlyStyle: ButtonStyle {
    var cornerRadius: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        NCCardFocusBorderOnlyBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

private struct NCCardFocusBorderOnlyBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused
                            ? LinearGradient(
                                colors: [.white.opacity(0.7), .accentColor.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: isFocused ? 3 : 0
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Plain Focus Button Style

struct NCPlainFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NCPlainFocusBody(configuration: configuration)
    }
}

private struct NCPlainFocusBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white.opacity(0.1) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? Color.white.opacity(0.4) : .clear, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 顶部 Tab 栏按钮样式（不放大、焦点边框不溢出，用于横向可滑动 TabBar）

/// 与 NCPlainFocusButtonStyle 视觉一致，但焦点时不放大（scaleEffect 仅按下时缩小），便于在 ScrollView 内使用且边框不溢出。
struct NCTabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NCTabBarFocusBody(configuration: configuration)
    }
}

private struct NCTabBarFocusBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white.opacity(0.1) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? Color.white.opacity(0.4) : .clear, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 全屏模态面板（排序/来源等统一样式）

/// 全屏半透明背景 + 居中卡片容器，用于排序、来源筛选等弹层，统一视觉与圆角/描边。
/// - Parameters:
///   - dimBackground: 若为 true（默认）则全屏半透明遮罩；若为 false 仅渲染卡片（用于 sheet 内嵌时）
///   - maxWidth / maxHeight: 卡片内容区最大宽高
struct NCModalPanelContainer<Content: View>: View {
    var dimBackground: Bool = true
    var maxWidth: CGFloat = 900
    var maxHeight: CGFloat = 600
    @ViewBuilder let content: () -> Content

    private var cardContent: some View {
        content()
            .padding(32)
            .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.black.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipped()
            .padding(40)
    }

    var body: some View {
        Group {
            if dimBackground {
                NavigationStack {
                    ZStack {
                        Color.black.opacity(0.68)
                            .ignoresSafeArea()
                        cardContent
                    }
                }
            } else {
                NavigationStack {
                    cardContent
                }
            }
        }
    }
}

/// 排序/来源列表中的单行选项：勾选图标 + 文案，统一样式与焦点。
struct NCModalOptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.body)
            }
        }
        .buttonStyle(NCPlainFocusButtonStyle())
    }
}

// MARK: - Text Field（自定义 tvOS 深色圆角样式）

struct NCTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var isRequired: Bool = false
    var showValidation: Bool = false
    var isFocused: Bool = false

    private var isInvalid: Bool {
        showValidation && isRequired && text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain) // tvOS 不支持 .roundedBorder，使用自定义圆角背景
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInvalid
                                ? Color.red.opacity(0.8)
                                : (isFocused ? Color.white.opacity(0.8) : Color.white.opacity(0.18)),
                            lineWidth: isFocused || isInvalid ? 2.5 : 1
                        )
                )
                .shadow(color: isFocused ? Color.black.opacity(0.6) : .clear, radius: 10, y: 4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

// MARK: - Secure Field（同样风格）

struct NCSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var isRequired: Bool = false
    var showValidation: Bool = false
    var isFocused: Bool = false

    private var isInvalid: Bool {
        showValidation && isRequired && text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isRequired {
                    Text("*").foregroundStyle(.red)
                }
            }

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInvalid
                                ? Color.red.opacity(0.8)
                                : (isFocused ? Color.white.opacity(0.8) : Color.white.opacity(0.18)),
                            lineWidth: isFocused || isInvalid ? 2.5 : 1
                        )
                )
                .shadow(color: isFocused ? Color.black.opacity(0.6) : .clear, radius: 10, y: 4)
                .animation(.easeInOut(duration: 0.18), value: isFocused)
        }
    }
}

// MARK: - Primary Button

struct NCPrimaryButton: View {
    let title: String
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 16))
    }
}

// MARK: - Secondary Button

struct NCSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 16))
    }
}

// MARK: - Action Card

struct NCActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(NCCardButtonStyle())
    }
}

// MARK: - P2P Connection Status Badge

struct NCConnectionBadge: View {
    let state: P2PService.P2PConnectionState

    private var badgeColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var badgeIcon: String {
        switch state {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var badgeText: String {
        switch state {
        case .connected: return "P2P"
        case .connecting: return L10n.tr("connecting")
        case .reconnecting: return L10n.tr("reconnecting")
        case .failed: return L10n.tr("connection_failed")
        case .disconnected: return ""
        }
    }

    var body: some View {
        if state != .disconnected {
            HStack(spacing: 6) {
                if state == .connecting || state == .reconnecting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: badgeIcon)
                        .font(.caption2)
                }
                Text(badgeText)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(badgeColor.opacity(0.15))
            )
        }
    }
}

// MARK: - 远程图片（直连与 P2P 代理通用；使用无代理 URLSession 避免 PAC/XPC 报错并提高缩略图加载成功率）

struct NCRemoteImage: View {
    let url: URL?
    var placeholder: Color = Color.white.opacity(0.04)
    var contentMode: ContentMode = .fill
    /// 加载失败后重试次数（P2P/局域网下可提高成功率）
    var maxRetries: Int = 1
    /// url 不为 nil 但加载失败时的占位视图（nil 表示沿用 placeholder 颜色）
    var failureView: AnyView? = nil

    @State private var loadedImage: UIImage?
    @State private var loadFailed = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loadFailed {
                if let failureView {
                    failureView
                } else {
                    Image("404")
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                placeholder
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                loadedImage = nil
                loadFailed = false
                return
            }
            loadTask?.cancel()
            loadedImage = nil
            loadFailed = false
            loadTask = Task {
                await loadImage(from: url, retryLeft: maxRetries)
            }
            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadImage(from url: URL, retryLeft: Int) async {
        do {
            let (data, response) = try await NCImageLoadingSession.session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                await retryIfNeeded(from: url, retryLeft: retryLeft)
                return
            }
            guard let image = UIImage(data: data) else {
                await retryIfNeeded(from: url, retryLeft: retryLeft)
                return
            }
            if !Task.isCancelled {
                loadedImage = image
            }
        } catch {
            await retryIfNeeded(from: url, retryLeft: retryLeft)
        }
    }

    private func retryIfNeeded(from url: URL, retryLeft: Int) async {
        guard retryLeft > 0, !Task.isCancelled else {
            if !Task.isCancelled {
                loadFailed = true
            }
            return
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        await loadImage(from: url, retryLeft: retryLeft - 1)
    }
}

// MARK: - Section Header

struct NCSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Optional Focus Modifier（用于可选 FocusState 绑定）

private struct OptionalFocusedModifier: ViewModifier {
    let binding: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let b = binding {
            content.focused(b)
        } else {
            content
        }
    }
}

// MARK: - Search Input（tvOS 推荐：按钮 + Sheet 输入，避免系统 TextField 白底与取消后无法再聚焦）

/// 卡片式搜索入口：点击后弹出 Sheet 内输入，避免系统 TextField 焦点白底和取消后无法再次进入输入界面的问题。
struct NCSearchInput: View {
    let placeholder: String
    @Binding var text: String
    let onSearch: () -> Void
    /// 可选：父视图通过 FocusState 控制焦点（如 onExitCommand 时拉回搜索区）
    var isFocused: FocusState<Bool>.Binding? = nil

    @State private var showSheet = false
    @State private var sheetText = ""

    var body: some View {
        Button {
            sheetText = text
            showSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(text.isEmpty ? placeholder : text)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 20, focusScale: 1.02))
        .modifier(OptionalFocusedModifier(binding: isFocused))
        .fullScreenCover(isPresented: $showSheet) {
            NCSearchInputSheet(
                placeholder: placeholder,
                text: $sheetText,
                onSubmit: {
                    text = sheetText
                    onSearch()
                    showSheet = false
                },
                onCancel: {
                    showSheet = false
                }
            )
        }
    }
}

private struct NCSearchInputSheet: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum FocusField { case field, clear }
    @FocusState private var focusedField: FocusField?

    /// 记录打开时是否已有搜索内容，用于决定初始焦点
    @State private var hasInitialText = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(placeholder, text: $text)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .field)
                            .submitLabel(.search)
                            .onSubmit { onSubmit() }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)

                    HStack(spacing: 24) {
                        Button {
                            text = ""
                            onSubmit()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                Text(L10n.clear)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(NCPlainFocusButtonStyle())
                        .focused($focusedField, equals: .clear)

                        Spacer()

                        Button {
                            onCancel()
                        } label: {
                            HStack(spacing: 8) {
                                Text(L10n.cancel)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(NCPlainFocusButtonStyle())

                        Button {
                            onSubmit()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text(L10n.search)
                            }
                        }
                        .buttonStyle(NCPlainFocusButtonStyle())
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .onAppear {
                hasInitialText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // 有已有搜索内容时聚焦清除按钮，否则聚焦输入框
                focusedField = hasInitialText ? .clear : .field
            }
        }
    }
}
