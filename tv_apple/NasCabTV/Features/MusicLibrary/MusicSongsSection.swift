import SwiftUI

@MainActor
final class MusicSongsViewModel: ObservableObject {
    @Published private(set) var items: [MusicItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var sortBy = "mtime"
    @Published var sortOrder = "desc"
    @Published var availablePaths: [MusicSourcePathItem] = []
    @Published var selectedPaths: Set<String> = []

    private var page = 1
    private var hasNextPage = true
    private let listType: String
    private let isFavorite: Bool
    private let isHistory: Bool

    init(listType: String = "", isFavorite: Bool = false, isHistory: Bool = false) {
        self.listType = listType
        self.isFavorite = isFavorite
        self.isHistory = isHistory
        if isHistory { sortBy = "view_time"; sortOrder = "desc" }
        if isFavorite { sortBy = "favorite_time"; sortOrder = "desc" }
    }

    var isFavoriteList: Bool { isFavorite }
    var isHistoryList: Bool { isHistory }

    struct SortOption: Identifiable {
        let id = UUID()
        let sortBy: String
        let sortOrder: String
        let label: String
        let labelKey: String
    }

    var availableSortOptions: [SortOption] {
        var options: [SortOption] = [
            SortOption(sortBy: "mtime", sortOrder: "desc", label: "最近添加（新→旧）", labelKey: "music_list_sort_mtime_desc"),
            SortOption(sortBy: "mtime", sortOrder: "asc", label: "最近添加（旧→新）", labelKey: "music_list_sort_mtime_asc"),
            SortOption(sortBy: "title", sortOrder: "asc", label: "标题升序", labelKey: "music_list_sort_title_asc"),
            SortOption(sortBy: "title", sortOrder: "desc", label: "标题降序", labelKey: "music_list_sort_title_desc"),
            SortOption(sortBy: "year", sortOrder: "desc", label: "年份降序", labelKey: "music_list_sort_year_desc"),
            SortOption(sortBy: "year", sortOrder: "asc", label: "年份升序", labelKey: "music_list_sort_year_asc"),
            SortOption(sortBy: "duration", sortOrder: "desc", label: "时长降序", labelKey: "music_list_sort_duration_desc"),
            SortOption(sortBy: "duration", sortOrder: "asc", label: "时长升序", labelKey: "music_list_sort_duration_asc"),
            SortOption(sortBy: "ctime", sortOrder: "desc", label: "创建时间降序", labelKey: "create_time_desc"),
            SortOption(sortBy: "ctime", sortOrder: "asc", label: "创建时间升序", labelKey: "create_time_asc"),
        ]
        if isFavoriteList {
            options.insert(
                SortOption(sortBy: "favorite_time", sortOrder: "desc", label: "收藏时间降序", labelKey: "music_list_sort_favorite_time_desc"),
                at: 0
            )
            options.insert(
                SortOption(sortBy: "favorite_time", sortOrder: "asc", label: "收藏时间升序", labelKey: "music_list_sort_favorite_time_asc"),
                at: 1
            )
        }
        if isHistoryList {
            options.insert(
                SortOption(sortBy: "view_time", sortOrder: "desc", label: "最近播放时间", labelKey: "music_list_sort_view_time_desc"),
                at: 0
            )
        }
        return options
    }

    var currentSortLabel: String {
        if let opt = availableSortOptions.first(where: { $0.sortBy == sortBy && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.videoSortTitle
    }

    var hasSourceFilter: Bool {
        !selectedPaths.isEmpty
    }

    var sourceFilterCount: Int {
        selectedPaths.count
    }

    func applySort(by: String, order: String) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        Task { await reload() }
    }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasNextPage = true

        let sourceListParam = selectedPaths.isEmpty ? nil : Array(selectedPaths)

        let response = await MusicService.listSongs(
            page: page,
            pageSize: 30,
            listType: listType,
            isFavorite: isFavorite,
            isHistory: isHistory,
            search: searchText.isEmpty ? nil : searchText,
            sourceList: sourceListParam,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            items = []
            hasNextPage = false
            isLoading = false
            isInitialLoaded = true
            return
        }

        items = data.items
        hasNextPage = data.pagination.hasNextPage
        if (!hasSourceFilter || availablePaths.isEmpty) && !data.validPaths.isEmpty {
            availablePaths = data.validPaths
        }
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: MusicItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        let nextPage = page + 1

        let sourceListParam = selectedPaths.isEmpty ? nil : Array(selectedPaths)

        let response = await MusicService.listSongs(
            page: nextPage,
            pageSize: 30,
            listType: listType,
            isFavorite: isFavorite,
            isHistory: isHistory,
            search: searchText.isEmpty ? nil : searchText,
            sourceList: sourceListParam,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.hasNextPage
        isLoading = false
    }

    func applySearch() {
        Task { await reload() }
    }

    func toggleSource(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if selectedPaths.contains(trimmed) {
            selectedPaths.remove(trimmed)
        } else {
            selectedPaths.insert(trimmed)
        }
        Task { [weak self] in
            await self?.reload()
        }
    }

    func resetSourceFilter() {
        guard !selectedPaths.isEmpty else { return }
        selectedPaths.removeAll()
        Task { [weak self] in
            await self?.reload()
        }
    }
}

// MARK: - Songs Section View

struct MusicSongsSection: View {
    /// `queue` 为当前列表已加载的全部曲目（与界面一致，含分页已加载部分），用于上一首/下一首。
    let onSelectPlayable: (MusicItem, [MusicItem]) -> Void
    let onSelectSeries: (MusicItem) -> Void

    @StateObject private var viewModel: MusicSongsViewModel
    @State private var isShowingSortSheet = false

    init(
        listType: String = "",
        isFavorite: Bool = false,
        isHistory: Bool = false,
        onSelectPlayable: @escaping (MusicItem, [MusicItem]) -> Void,
        onSelectSeries: @escaping (MusicItem) -> Void
    ) {
        self.onSelectPlayable = onSelectPlayable
        self.onSelectSeries = onSelectSeries
        _viewModel = StateObject(wrappedValue: MusicSongsViewModel(listType: listType, isFavorite: isFavorite, isHistory: isHistory))
    }
    @State private var isShowingSourceSheet = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    MusicSearchBar(text: $viewModel.searchText, onSearch: { viewModel.applySearch() })
                        .frame(maxWidth: 620)

                    Spacer()

                    Button {
                        isShowingSortSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(viewModel.currentSortLabel)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(NCPlainFocusButtonStyle())

                    Button {
                        isShowingSourceSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "externaldrive.connected.to.line.below")
                            Text(L10n.videoSourceTitle)
                                .font(.subheadline)
                            if viewModel.sourceFilterCount > 0 {
                                Text("\(viewModel.sourceFilterCount)")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.25))
                                    )
                            }
                        }
                    }
                    .buttonStyle(NCPlainFocusButtonStyle())
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.items) { item in
                            MusicSongRow(item: item) {
                                if item.isSeries {
                                    onSelectSeries(item)
                                } else {
                                    onSelectPlayable(item, viewModel.items)
                                }
                            }
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(current: item) }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 32)
                    .padding(.bottom, 128)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .center) {
                if viewModel.isLoading && !viewModel.isInitialLoaded {
                    ProgressView()
                        .scaleEffect(1.4)
                } else if viewModel.items.isEmpty && viewModel.isInitialLoaded {
                    Text(viewModel.errorMessage ?? L10n.noData)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                await viewModel.loadInitialIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $isShowingSourceSheet) {
            MusicSourceSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            MusicSortSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Song Row

struct MusicSongRow: View {
    let item: MusicItem
    let onTap: () -> Void

    private var coverFilePath: String {
        let base = item.isSeries ? item.firstFilePath : item.fullPath
        if !base.isEmpty { return base }
        let p = item.path.trimmingCharacters(in: .whitespaces)
        let f = item.filename.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || f.isEmpty { return "" }
        return p.hasSuffix("/") ? "\(p)\(f)" : "\(p)/\(f)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                MusicCoverImage(item: item, filePath: coverFilePath, size: 80)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle)
                        .font(.system(size: 24))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !item.displaySubtitle.isEmpty {
                        Text(item.displaySubtitle)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.duration > 0 {
                    Text(formatDuration(item.duration))
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 16, focusScale: 1.02))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Source Filter Sheet (music)

private struct MusicSourceSheet: View {
    @ObservedObject var viewModel: MusicSongsViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 1100, maxHeight: 720) {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.videoSourceTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                if viewModel.availablePaths.isEmpty {
                    Text(L10n.noData)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            let isAllSelected = viewModel.selectedPaths.isEmpty
                            NCModalOptionButton(
                                label: L10n.photoTimelineAllSource,
                                isSelected: isAllSelected
                            ) { viewModel.resetSourceFilter() }

                            ForEach(viewModel.availablePaths) { item in
                                let isSelected = viewModel.selectedPaths.contains(item.path)
                                Button {
                                    viewModel.toggleSource(path: item.path)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(
                                            systemName: isSelected
                                                ? "checkmark.circle.fill"
                                                : "circle"
                                        )
                                        .foregroundStyle(
                                            isSelected ? Color.accentColor : .secondary
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.path)
                                                .font(.body)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                            if !item.valid {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.red.opacity(0.8))
                                            }
                                        }
                                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(NCPlainFocusButtonStyle())
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                    }
                    .clipped()
                    .focusSection()
                }

                Spacer()
            }
        }
    }
}

// MARK: - Search Bar（使用 NCSearchInput 避免 tvOS TextField 白底与取消后无法再聚焦）

struct MusicSearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void
    let placeholder: String

    init(text: Binding<String>, placeholder: String = L10n.musicSearchHint, onSearch: @escaping () -> Void) {
        _text = text
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    var body: some View {
        NCSearchInput(placeholder: placeholder, text: $text, onSearch: onSearch)
    }
}

// MARK: - Sort Sheet

private struct MusicSortSheet: View {
    @ObservedObject var viewModel: MusicSongsViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.videoSortTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.availableSortOptions) { option in
                            NCModalOptionButton(
                                label: L10n.tr(option.labelKey),
                                isSelected: viewModel.sortBy == option.sortBy && viewModel.sortOrder == option.sortOrder
                            ) {
                                viewModel.applySort(by: option.sortBy, order: option.sortOrder)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .clipped()

                Spacer()
            }
        }
    }
}
