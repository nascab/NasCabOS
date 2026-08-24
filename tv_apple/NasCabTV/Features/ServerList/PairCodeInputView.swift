import SwiftUI

struct PairCodeInputView: View {
    @ObservedObject var viewModel: ServerListViewModel
    var initialCode: String = ""
    let onSubmit: (String) -> Void

    @State private var code: String = ""
    @State private var errorText: String?
    @State private var isConnecting = false
    @State private var showHelp = false

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                headerSection
                inputSection
                helpSection
                buttonSection
            }
            .padding(64)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color.purple.opacity(0.1), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            code = initialCode
        }
        .alert(L10n.serverPairCodeHowTitle, isPresented: $showHelp) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.serverPairCodeHelpDetail)
        }
        .overlay {
            if isConnecting {
                connectingOverlay
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.purple)
            }

            Text(L10n.serverAddByPairCodeTitle)
                .font(.title)
                .fontWeight(.bold)

            Text(L10n.serverAddByPairCodeContent)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NCTextField(
                label: L10n.serverAddByPairCodeTitle,
                placeholder: L10n.serverPairCodePlaceholder,
                text: $code,
                icon: "link.circle",
                isFocused: isCodeFieldFocused
            )
            .focused($isCodeFieldFocused)
            .onChange(of: code) { newValue in
                errorText = APIClient.validatePairCode(newValue)
            }

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 600)
    }

    private var helpSection: some View {
        Button(action: { showHelp = true }) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                Text(L10n.serverPairCodeHowTitle)
            }
            .font(.subheadline)
            .foregroundStyle(.purple)
        }
        .buttonStyle(NCPlainFocusButtonStyle())
    }

    private var buttonSection: some View {
        HStack(spacing: 32) {
            NCSecondaryButton(title: L10n.cancel) { dismiss() }
                .frame(width: 200)

            NCPrimaryButton(title: L10n.ok, color: .purple) { submitCode() }
                .frame(width: 200)
                .disabled(APIClient.validatePairCode(code) != nil)
        }
    }

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                Text(L10n.serverConnecting)
                    .font(.headline)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Actions

    private func submitCode() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard APIClient.validatePairCode(trimmed) == nil else {
            print("[P2P] PairCodeInputView: submitCode skipped, validation failed")
            return
        }

        if !initialCode.isEmpty {
            print("[P2P] PairCodeInputView: submitCode edit mode, calling onSubmit")
            onSubmit(trimmed)
            return
        }

        print("[P2P] PairCodeInputView: submitCode start, code length=\(trimmed.count)")
        isConnecting = true
        Task {
            await viewModel.addServerByPairCode(trimmed)
            isConnecting = false
            print("[P2P] PairCodeInputView: addServerByPairCode done, showError=\(viewModel.showError), errorMessage=\(viewModel.errorMessage ?? "nil")")
            if !viewModel.showError {
                print("[P2P] PairCodeInputView: success, calling onSubmit")
                onSubmit(trimmed)
            } else {
                print("[P2P] PairCodeInputView: failed, not calling onSubmit (alert should show)")
            }
        }
    }
}
