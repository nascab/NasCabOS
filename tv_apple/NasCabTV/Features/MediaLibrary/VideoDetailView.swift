import SwiftUI

@MainActor
final class TVVideoDetailViewModel: ObservableObject {
    @Published private(set) var detail: TVVideoDetailResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingEpisodes = false
    @Published private(set) var episodesPage: TVVideoEpisodePage?
    @Published private(set) var errorMessage: String?
    @Published var episodeAsc: Bool = true

    @Published private(set) var episodeTotal: Int = 0
    @Published private(set) var episodePage: Int = 1
    let episodePageSize: Int = 20

    let item: TVVideoItem

    init(item: TVVideoItem) {
        self.item = item
    }

    var displayItem: TVVideoItem {
        detail?.item.id == item.id ? (detail?.item ?? item) : item
    }

    var history: TVVideoDetailHistory? {
        detail?.history
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }


        let response = await TVVideoDetailService.getDetail(indexId: item.id)
        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            return
        }
        detail = data


        // 保持与之前行为一致：始终为剧/季预加载剧集数据（用于分页），
        // 具体是否在详情页展示由视图层控制。
        if shouldShowEpisodes {
            await loadEpisodes(page: 1)
        } else {
            episodesPage = nil
            episodeTotal = 0
            episodePage = 1
        }
    }

    private var mediaType: String {
        displayItem.mediaType.lowercased()
    }
    
    /// 是否需要为当前详情自动加载剧集数据（与 Flutter `_needAutoLoadEpisodes` 保持一致）
    var shouldShowEpisodes: Bool {
        if mediaType == "season" { return true }
        if mediaType == "tv" {
            // 多季剧：不在当前详情自动加载剧集，仅展示季列表
            return displayItem.seasonCount <= 1
        }
        return false
    }

    var episodeTotalPages: Int {
        guard episodePageSize > 0 else { return 0 }
        return Int(ceil(Double(episodeTotal) / Double(episodePageSize)))
    }

    func loadEpisodes(page: Int) async {
        guard !isLoadingEpisodes else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        let response = await TVVideoDetailService.getEpisodes(
            indexId: item.id,
            page: page,
            pageSize: episodePageSize,
            sortAsc: episodeAsc
        )
        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            return
        }
        episodesPage = data
        episodeTotal = data.total
        episodePage = data.page

    }

    func toggleEpisodeSort() async {
        episodeAsc.toggle()
        let totalPages = episodeTotalPages
        let current = episodePage
        let mirrored = totalPages > 0 ? max(1, min(totalPages, totalPages - current + 1)) : 1
        await loadEpisodes(page: mirrored)
    }

    func jumpToEpisodePage(_ page: Int) async {
        let totalPages = episodeTotalPages
        guard totalPages > 0 else { return }
        let p = max(1, min(totalPages, page))
        await loadEpisodes(page: p)
    }

    func setFavorite(_ isFavorite: Bool) async -> Bool {
        await TVVideoDetailService.setFavorite(indexId: displayItem.id, to: isFavorite)
    }

    func scanChanges() async -> Bool {
        let res = await TVVideoDetailService.scanChanges(indexId: displayItem.id)
        return res.success
    }
}

// MARK: - Detail View

private enum DetailFocus: Hashable {
    case back
    case play
}

struct TVVideoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TVVideoDetailViewModel
    @FocusState private var preferredFocus: DetailFocus?

    init(item: TVVideoItem) {
        _viewModel = StateObject(wrappedValue: TVVideoDetailViewModel(item: item))
    }

    private var displayItem: TVVideoItem {
        viewModel.displayItem
    }

    private var titleText: String {
        let nfo = displayItem.nfoName.trimmingCharacters(in: .whitespaces)
        return nfo.isEmpty ? displayItem.filename : nfo
    }

    private var metaLine: String {
        var parts: [String] = []
        if displayItem.mediaType.lowercased() == "tv" {
            if displayItem.seasonCount > 1 {
                parts.append(L10n.tr("video_detail_seasons_total", params: ["num": "\(displayItem.seasonCount)"]))
            } else {
                // 单季或无季文件夹时显示集数
                let total = viewModel.episodeTotal
                parts.append(L10n.tr("video_detail_episodes_total", params: ["num": "\(total)"]))
            }
        }
        if displayItem.nfoYear > 0 {
            parts.append("\(displayItem.nfoYear)")
        }
        let meta = TVVideoMetaUtils.buildMetaSubtitle(for: displayItem)
        if !meta.isEmpty {
            parts.append(meta)
        }
        return parts.joined(separator: " · ")
    }

    private var ratingText: String? {
        guard displayItem.nfoScore > 0 else { return nil }
        return String(format: "%.1f", displayItem.nfoScore)
    }

    private var typeText: String {
        TVVideoMetaUtils.mediaTypeText(displayItem.mediaType)
    }

    /// 电影时在文件名下方显示的一行：时长 · 大小（有值才显示）
    private var movieDurationAndSizeLine: String? {
        guard displayItem.mediaType.lowercased() == "movie" else { return nil }
        let dur = displayItem.durationSeconds
        let size = displayItem.fileSizeBytes
        if dur <= 0 && size <= 0 { return nil }
        var parts: [String] = []
        if dur > 0 {
            parts.append("\(L10n.videoDetailDuration) \(formatMovieDuration(dur))")
        }
        if size > 0 {
            parts.append("\(L10n.videoDetailFileSize) \(formatFileSize(size))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatMovieDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        if m > 0 {
            return String(format: "%d min", m)
        }
        return String(format: "%d s", total)
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let b = Int64(max(0, bytes))
        let gb = 1_073_741_824.0
        let mb = 1_048_576.0
        let kb = 1024.0
        if Double(b) >= gb {
            return String(format: "%.1f GB", Double(b) / gb)
        }
        if Double(b) >= mb {
            return String(format: "%.1f MB", Double(b) / mb)
        }
        if Double(b) >= kb {
            return String(format: "%.0f KB", Double(b) / kb)
        }
        return "\(b) B"
    }

    private var progressRatio: Double {
        guard let history = viewModel.history else { return 0 }
        guard history.durationSeconds > 0 else { return 0 }
        return min(1, max(0, Double(history.playbackSeconds) / Double(history.durationSeconds)))
    }

    private var hasEpisodes: Bool {
        let total = viewModel.episodesPage?.total ?? 0
        let shouldShow = viewModel.shouldShowEpisodes
        guard showEpisodesInDetail else { return false }
        return total > 0
    }

    // 仅控制「是否在详情页展示剧集」，与剧集加载条件保持一致
    private var showEpisodesInDetail: Bool {
        let v = viewModel.shouldShowEpisodes
        return v
    }

    private var episodePager: some View {
        let totalPages = viewModel.episodeTotalPages
        let total = viewModel.episodeTotal
        let current = viewModel.episodePage
        let size = viewModel.episodePageSize
        let asc = viewModel.episodeAsc

        return Group {
            if totalPages > 1 {
                HStack(spacing: 8) {
                    ForEach(1...totalPages, id: \.self) { pageIndex in
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
                    Spacer()
                }
            }
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

    /// 剧集副标题一行：第 x 集 · 时长 · 大小（有则显示）
    private func episodeSubtitleLine(for ep: TVVideoEpisodeItem) -> String {
        var parts: [String] = []
        if ep.episodNumber > 0 {
            parts.append(L10n.tr("video_detail_episode_no", params: ["ep": "\(ep.episodNumber)"]))
        }
        if ep.durationSeconds > 0 {
            parts.append(formatMovieDuration(ep.durationSeconds))
        }
        if ep.fileSizeBytes > 0 {
            parts.append(formatFileSize(ep.fileSizeBytes))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 160) // 80*2 horizontal padding
            ZStack {
                backgroundLayer

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        topBar
                            .focusSection()

                        HStack(alignment: .top, spacing: 36) {
                            posterArea
                            infoArea
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: contentWidth)
                        .focusSection()

                        VStack(alignment: .leading, spacing: 24) {
                            storylineSection
                            if hasEpisodes, let page = viewModel.episodesPage {
                                episodeSection(page: page)
                            }
                            if !seasons.isEmpty {
                                seasonSection
                            }
                            if !people.isEmpty {
                                peopleSection
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusSection()
                        .padding(.bottom, 80)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 80)
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .fullScreenCover(item: $activeSeasonItem) { season in
            TVVideoDetailView(item: season)
        }
        .fullScreenCover(item: $activePlayContext) { context in
            TVVideoPlayerView(
                playlist: context.playlist,
                initialIndex: context.initialIndex,
                initialSeekSeconds: context.initialSeekSeconds,
                ignoreFindSub: 0
            )
            .onAppear {
                MusicPlayerService.shared.stop()
            }
        }
        .fullScreenCover(item: $activePersonVideosContext) { ctx in
            TVVideoPersonVideosView(
                title: ctx.title,
                personName: ctx.personName,
                isDirector: ctx.isDirector,
                mediaType: ctx.mediaType
            )
        }
        .task {
            await viewModel.load()
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            DispatchQueue.main.async {
                preferredFocus = .play
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NCRemoteImage(
                url: TVVideoImageUtils.fanartURL(for: displayItem, size: 1200),
                placeholder: Color.black,
                contentMode: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.88),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 20) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.backward")
                    .font(.title2)
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($preferredFocus, equals: .back)

            Text(L10n.videoDetailPageTitle)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }

    // MARK: - Left Poster

    private var posterArea: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 270, height: 360)
                    .overlay {
                        NCRemoteImage(
                            url: TVVideoImageUtils.posterURL(for: displayItem, size: 600),
                            placeholder: Color.white.opacity(0.06),
                            contentMode: .fill
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .top) {
                        VStack {
                            HStack {
                                if let ratingText {
                                    Text(ratingText)
                                        .font(.system(size: 16, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                        .foregroundStyle(Color(red: 229/255, green: 181/255, blue: 39/255))
                                }
                                Spacer()
                                if !typeText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(typeText)
                                        .font(.system(size: 16, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                        )
                                        .foregroundStyle(Color.white.opacity(0.95))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            Spacer()
                        }
                    }
            }
            .shadow(radius: 18, y: 8)
        }
    }

    // MARK: - Title row (logo 在电影名字右边)

    private var titleRowWithLogo: some View {
        let logoPath = displayItem.logoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if !logoPath.isEmpty, let url = TVVideoImageUtils.tinyArtworkURL(forPath: logoPath) {
                HStack(alignment: .bottom, spacing: 20) {
                    Text(titleText)
                        .font(.system(size: 40, weight: .heavy))
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 160, height: 64)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: 280, maxHeight: 120)
                }
            } else {
                Text(titleText)
                    .font(.system(size: 40, weight: .heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Right Info

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                titleRowWithLogo
                if displayItem.mediaType.lowercased() == "movie", !displayItem.filename.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(displayItem.filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if displayItem.mediaType.lowercased() == "movie", let durationSizeLine = movieDurationAndSizeLine {
                    Text(durationSizeLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !metaLine.isEmpty {
                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            actionRow

            let mediaType = displayItem.mediaType.lowercased()
            if progressRatio > 0, mediaType != "tv" {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progressRatio)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)

                    if let history = viewModel.history {
                        if mediaType == "season" {
                            let epNum = history.episodeNumber ?? 0
                            Text(
                                L10n.tr(
                                    "video_detail_watched_episode",
                                    params: [
                                        "time": formatSeconds(history.playbackSeconds),
                                        "num": epNum > 0 ? "\(epNum)" : "-"
                                    ]
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        } else if mediaType != "tv" {
                            Text(
                                L10n.tr(
                                    "video_detail_watched",
                                    params: ["time": formatSeconds(history.playbackSeconds)]
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let d = max(0, seconds)
        let h = d / 3600
        let m = (d % 3600) / 60
        let s = d % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Actions

    @State private var isTogglingFavorite = false
    @State private var isFavoriteState: Bool?
    @State private var alertMessage: String?
    @State private var showScanSuccessToast = false
    @State private var activePlayContext: TVVideoPlayContext?

    private var effectiveFavorite: Bool {
        if let v = isFavoriteState { return v }
        return displayItem.isFavorite
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                Task {
                    let res = await TVVideoDetailService.getTvPlayInfo(indexId: displayItem.id)
                    guard res.success, let data = res.data else {
                        alertMessage = res.message ?? L10n.networkFailure
                        return
                    }
                    let items = data.playlist
                        .map { dict -> TVVideoPlaylistItem? in
                            let rawPath = (dict["path"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = (dict["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !rawPath.isEmpty else { return nil }
                            return TVVideoPlaylistItem(path: rawPath, name: name.isEmpty ? rawPath : name)
                        }
                        .compactMap { $0 }

                    guard !items.isEmpty else {
                        alertMessage = L10n.networkFailure
                        return
                    }

                    if APIClient.shared.isP2pMode {
                        LocalPlaybackProxy.shared.start()
                        for _ in 0..<30 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            if LocalPlaybackProxy.shared.isRunning { break }
                        }
                    }

                    let historySeconds = viewModel.history?.playbackSeconds ?? 0
                    let idx = max(0, min(data.initialIndex, items.count - 1))
                    activePlayContext = TVVideoPlayContext(
                        playlist: items,
                        initialIndex: idx,
                        initialSeekSeconds: historySeconds
                    )
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text(
                        viewModel.history != nil
                            ? L10n.videoDetailContinuePlay
                            : L10n.playLabel
                    )
                    .font(.headline)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.blue)
                )
                .foregroundStyle(Color.white)
            }
            .buttonStyle(NCCardButtonStyle(cornerRadius: 22, focusScale: 1.06))
            .focused($preferredFocus, equals: .play)

            if hasEpisodes {
                EmptyView()
            }

            Button {
                guard !isTogglingFavorite else { return }
                Task {
                    isTogglingFavorite = true
                    let next = !effectiveFavorite
                    let ok = await viewModel.setFavorite(next)
                    if ok {
                        isFavoriteState = next
                    } else {
                        alertMessage = L10n.networkFailure
                    }
                    isTogglingFavorite = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: effectiveFavorite ? "heart.fill" : "heart")
                    Text(
                        effectiveFavorite
                            ? L10n.favoriteRemove
                            : L10n.favoriteAdd
                    )
                    .font(.subheadline)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Button {
                Task {
                    let ok = await viewModel.scanChanges()
                    if ok {
                        withAnimation {
                            showScanSuccessToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showScanSuccessToast = false
                            }
                        }
                    } else {
                        alertMessage = L10n.networkFailure
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(L10n.videoDetailScanChanges)
                        .font(.subheadline)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Spacer()
        }
        .alert(item: Binding(
            get: {
                alertMessage.map { LocalizedErrorMessage(message: $0) }
            },
            set: { newValue in
                alertMessage = newValue?.message
            }
        )) { wrapper in
            Alert(
                title: Text(wrapper.message),
                dismissButton: .default(Text(L10n.ok))
            )
        }
        .overlay(alignment: .bottom) {
            if showScanSuccessToast {
                Text(L10n.videoDetailScanSuccess)
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                    )
                    .foregroundStyle(Color.black)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private struct LocalizedErrorMessage: Identifiable {
        let id = UUID()
        let message: String
    }

    // MARK: - Storyline

    @State private var isShowingStorylineDialog = false
    private var storylineSection: some View {
        let text = displayItem.nfoStoryline.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = text.isEmpty ? L10n.videoDetailStorylineEmpty : text

        return Button {
            isShowingStorylineDialog = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.videoDetailStoryline)
                    .font(.headline)
                Text(content)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .buttonStyle(.plain)
        .alert(isPresented: $isShowingStorylineDialog) {
            Alert(
                title: Text(L10n.videoDetailStoryline),
                message: Text(content),
                dismissButton: .default(Text(L10n.ok))
            )
        }
    }

    // MARK: - Seasons

    @State private var activeSeasonItem: TVVideoItem?
    @State private var activePersonVideosContext: PersonVideosContext?

    private var seasons: [TVVideoItem] {
        let list = viewModel.detail?.seasons ?? []
        return list
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                L10n.tr(
                    "video_detail_season_list_title",
                    params: ["count": "\(seasons.count)"]
                )
            )
            .font(.headline)

            ScrollView(.horizontal) {
                //季列表卡片
                let cardWidth: CGFloat = 270
                let cardHeight: CGFloat = 360
                HStack(spacing: 14) {
                    ForEach(seasons) { season in
                        Button {
                            activeSeasonItem = season
                        } label: {
                            VStack(spacing: 0) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(width: cardWidth, height: cardHeight)
                                    NCRemoteImage(
                                        url: TVVideoImageUtils.posterURL(for: season, size: 300),
                                        placeholder: Color.white.opacity(0.06),
                                        contentMode: .fill
                                    )
                                    .frame(width: cardWidth, height: cardHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                Text(
                                    season.nfoName.isEmpty
                                        ? season.filename
                                        : season.nfoName
                                )
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(1)
                                .frame(width: cardWidth)
                                .padding(8)
                            }
                        }
                        .buttonStyle(NCCardButtonStyle(cornerRadius: 14, focusScale: 1.0))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Episodes

    private func episodeSection(page: TVVideoEpisodePage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text("\(L10n.videoDetailEpisodes) (\(page.total))")
                    .font(.headline)

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
                        .font(.footnote)
                    }
                }
                .buttonStyle(NCPlainFocusButtonStyle())
            }

            episodePager

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(page.items) { ep in
                    Button {
                        Task {
                            let allItems = page.items
                                .map { item -> TVVideoPlaylistItem? in
                                    let rawPath = item.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !rawPath.isEmpty else { return nil }
                                    return TVVideoPlaylistItem(path: rawPath, name: name.isEmpty ? rawPath : name)
                                }
                                .compactMap { $0 }

                            guard
                                !allItems.isEmpty,
                                let index = page.items.firstIndex(of: ep),
                                index < allItems.count
                            else {
                                return
                            }

                            var seekSeconds = 0
                            if let history = viewModel.history,
                               let epNum = history.episodeNumber,
                               epNum > 0,
                               epNum == ep.episodNumber {
                                seekSeconds = history.playbackSeconds
                            }

                            if APIClient.shared.isP2pMode {
                                LocalPlaybackProxy.shared.start()
                                for _ in 0..<30 {
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                    if LocalPlaybackProxy.shared.isRunning { break }
                                }
                            }

                            activePlayContext = TVVideoPlayContext(
                                playlist: allItems,
                                initialIndex: index,
                                initialSeekSeconds: seekSeconds
                            )
                        }
                    } label: {
                        HStack(spacing: 14) {
                            NCRemoteImage(
                                url: episodeImageURL(for: ep),
                                placeholder: Color.white.opacity(0.06),
                                contentMode: .fill
                            )
                            .frame(width: 180, height: 125)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            VStack(alignment: .leading, spacing: 6) {
                                if ep.episodNumber > 0 || ep.durationSeconds > 0 || ep.fileSizeBytes > 0 {
                                    Text(episodeSubtitleLine(for: ep))
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
                    .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.04))
                }
            }
        }
    }

    // MARK: - People

    private var people: [Person] {
        var result: [Person] = []
        result.append(contentsOf: parsePeople(from: displayItem.rawDirectorJson, role: L10n.videoDetailDirectors))
        result.append(contentsOf: parsePeople(from: displayItem.rawActorJson, role: L10n.videoDetailActors))
        return result
    }

    private struct Person: Identifiable {
        let id = UUID()
        let name: String
        let role: String
        let tmdbId: String
        let thumb: String?

        @MainActor
        var imageURL: URL? {
            TVVideoImageUtils.personImageURL(tmdbId: tmdbId, thumb: thumb, size: 240)
        }
    }

    private func parsePeople(from json: String, role: String) -> [Person] {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { dict in
            let name = (dict["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let tmdbId = (dict["tmdbId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let thumb = (dict["thumb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Person(name: name, role: role, tmdbId: tmdbId, thumb: thumb?.isEmpty == true ? nil : thumb)
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.videoDetailPeople)
                .font(.headline)

            ScrollView(.horizontal) {
                //演职人员卡片
                let cardWidth: CGFloat = 180
                let cardHeight: CGFloat = 210
                HStack(spacing: 12) {
                    ForEach(people) { person in
                        Button {
                            let resolved = displayItem.mediaType.lowercased() == "season" ? "tv" : displayItem.mediaType.lowercased()
                            activePersonVideosContext = PersonVideosContext(
                                title: "\(person.role)-\(person.name)",
                                personName: person.name,
                                isDirector: person.role == L10n.videoDetailDirectors,
                                mediaType: resolved
                            )
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: cardWidth, height: cardHeight)
                                    ZStack {
                                        NCRemoteImage(
                                            url: person.imageURL,
                                            placeholder: Color.white.opacity(0.08),
                                            contentMode: .fill,
                                            failureView: AnyView(personImagePlaceholder(cardWidth: cardWidth, cardHeight: cardHeight))
                                        )
                                        .frame(width: cardWidth, height: cardHeight)
                                        if person.imageURL == nil {
                                            personImagePlaceholder(cardWidth: cardWidth, cardHeight: cardHeight)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Text(person.name)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .frame(width: cardWidth)
                                Text(person.role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: cardWidth)
                            }
                        }
                        .buttonStyle(NCCardButtonStyle(cornerRadius: 12, focusScale: 1.0))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// 演职人员图片加载失败或无 URL 时，显示 50% 卡片宽度的小人图标
    private func personImagePlaceholder(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let size = cardWidth * 0.5
        return ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - 播放上下文 & 演职人员影片列表跳转上下文

private struct TVVideoPlayContext: Identifiable {
    let id = UUID()
    let playlist: [TVVideoPlaylistItem]
    let initialIndex: Int
    let initialSeekSeconds: Int
}

private struct PersonVideosContext: Identifiable {
    let id = UUID()
    let title: String
    let personName: String
    let isDirector: Bool
    let mediaType: String
}

