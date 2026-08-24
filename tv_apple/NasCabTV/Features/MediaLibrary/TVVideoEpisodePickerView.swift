import SwiftUI

struct TVVideoEpisodePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: TVVideoDetailViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(.systemIndigo).opacity(0.16),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                            .focusSection()
                        pager
                            .focusSection()
                        episodeList
                            .focusSection()
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.backward")
                    .font(.title2)
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Text(L10n.videoDetailEpisodes)
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Button {
                Task { await viewModel.toggleEpisodeSort() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.episodeAsc ? "arrow.up" : "arrow.down")
                    Text(
                        viewModel.episodeAsc
                            ? L10n.videoDetailSortAsc
                            : L10n.videoDetailSortDesc
                    )
                    .font(.subheadline)
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
    }

    private func episodeImageURL(for ep: TVVideoEpisodeItem) -> URL? {
        let poster = ep.posterPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !poster.isEmpty {
            return TVVideoImageUtils.tinyArtworkURL(forPath: poster)
        }
        let full = ep.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty {
            return TVVideoImageUtils.tinyArtworkURL(forPath: full)
        }
        return nil
    }

    private var pager: some View {
        let totalPages = viewModel.episodeTotalPages
        let total = viewModel.episodeTotal
        let current = viewModel.episodePage

        return Group {
            if totalPages > 1 {
                WrapHStack(spacing: 8) {
                    ForEach(1...totalPages, id: \.self) { pageIndex in
                        let size = viewModel.episodePageSize
                        let asc = viewModel.episodeAsc
                        let start = asc
                            ? (pageIndex - 1) * size + 1
                            : max(1, total - pageIndex * size + 1)
                        let end = asc
                            ? min(total, pageIndex * size)
                            : max(1, total - (pageIndex - 1) * size)
                        let label = "\(start)-\(end)"
                        let selected = pageIndex == current

                        Button {
                            Task { await viewModel.jumpToEpisodePage(pageIndex) }
                        } label: {
                            Text(label)
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            selected
                                                ? Color.white.opacity(0.16)
                                                : Color.white.opacity(0.06)
                                        )
                                )
                        }
                        .buttonStyle(NCPlainFocusButtonStyle())
                    }
                }
            }
        }
    }

    private var episodeList: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.episodesPage?.items ?? []) { ep in
                Button {
                    // TODO: 接入播放器，按需要播放指定集
                } label: {
                    HStack(spacing: 14) {
                        NCRemoteImage(
                            url: episodeImageURL(for: ep),
                            placeholder: Color.white.opacity(0.06),
                            contentMode: .fill
                        )
                        .frame(width: 220, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        VStack(alignment: .leading, spacing: 6) {
                            if ep.episodNumber > 0 {
                                Text(
                                    L10n.tr(
                                        "video_detail_episode_no",
                                        params: ["ep": "\(ep.episodNumber)"]
                                    )
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            Text(ep.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            if !ep.storyline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(ep.storyline)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.0))
            }
        }
    }
}

/// 简单的自动换行 HStack（用于页码）
private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
    }
}


