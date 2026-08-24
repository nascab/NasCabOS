import SwiftUI

struct ServerCardView: View {
    let server: ServerInfo
    let onLogin: () -> Void
    let onEdit: () -> Void
    let onEditPairCode: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var p2pService = P2PService.shared
    @State private var showActionMenu = false

    var body: some View {
        Button(action: {
            if server.isAutoScanned {
                onLogin()
            } else {
                showActionMenu = true
            }
        }) {
            HStack(spacing: 24) {
                platformIcon
                serverInfoSection
                Spacer()
                if server.isP2p || server.hasPairCode {
                    p2pBadge
                }
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(NCCardButtonStyle())
        .confirmationDialog(serverDisplayName, isPresented: $showActionMenu, titleVisibility: .visible) {
            Button(L10n.login) { onLogin() }
            Button(L10n.edit) { onEdit() }
            if server.hasPairCode {
                Button(L10n.serverMenuEditPairCode) { onEditPairCode() }
            }
            Button(L10n.delete, role: .destructive) { onDelete() }
        }
    }

    private var platformIcon: some View {
        Image(systemName: server.platformIconName)
            .font(.system(size: 42))
            .foregroundStyle(.secondary)
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.15))
            )
    }

    @ViewBuilder
    private var p2pBadge: some View {
        if p2pService.pairCode == server.pairCode && server.hasPairCode {
            NCConnectionBadge(state: p2pService.connectionState)
        } else if server.isP2p {
            NCConnectionBadge(state: .disconnected)
        }
    }

    private var serverInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if server.isLocalServer {
                    Text(L10n.serverLocalServer)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                if server.isAutoScanned, !server.isLocalServer {
                    Text(L10n.serverScanned)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.8)))
                        .foregroundStyle(.white)
                }
                Text(serverDisplayName)
                    .font(.headline)
                    .lineLimit(1)
            }

            Text(server.isP2p ? "P2P" : server.serverUrl)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !server.maskedPairCode.isEmpty {
                Text("\(L10n.serverPairCodeDisplay): \(server.maskedPairCode)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let username = server.username, !username.isEmpty {
                Text("\(L10n.username): \(username)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    /// 第一行标题：优先显示用户设置的「服务器名称」，主机名（服务端返回的 hostname，可能为 MAC 等）作为次要信息
    private var serverDisplayName: String {
        let hostname = server.serverHostName
        let name = server.serverName.trimmingCharacters(in: .whitespaces)
        if hostname.isEmpty && name.isEmpty { return "Unknown Server" }
        if name.isEmpty { return hostname }
        if hostname.isEmpty { return name }
        return "\(name) (\(hostname))"
    }
}
