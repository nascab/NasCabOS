import SwiftUI

// MARK: - Album / Artist Grid Section

@MainActor
final class MusicAlbumArtistViewModel: ObservableObject {
    @Published private(set) var items: [AlbumArtistItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var sortBy = "count"
    @Published var sortOrder = "desc"
    @Published var availablePaths: [MusicSourcePathItem] = []
    @Published var selectedPaths: Set<String> = []

    private var page = 1
    private var hasNextPage = true
    private let keyType: String

    init(keyType: String) {
        self.keyType = keyType
    }

    struct SortOption: Identifiable {
        let id = UUID()
        let sortBy: String
        let sortOrder: String
        let labelKey: String
    }

    var availableSortOptions: [SortOption] {
        [
            SortOption(sortBy: "count", sortOrder: "desc", labelKey: "music_group_sort_count_desc"),
            SortOption(sortBy: "name", sortOrder: "asc", labelKey: "music_group_sort_name_asc"),
        ]
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

    func applySort(by: String, order: String) async {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        await reload()
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

        let response: APIResponse<AlbumArtistListResult>
        if keyType.lowercased() == "artist" {
            response = await MusicService.listArtists(
                page: page,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder,
                sourceList: sourceListParam
            )
        } else {
            response = await MusicService.listAlbums(
                page: page,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder,
                sourceList: sourceListParam
            )
        }

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
        if availablePaths.isEmpty {
            availablePaths = data.validPaths
        }
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: AlbumArtistItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        let nextPage = page + 1

        let sourceListParam = selectedPaths.isEmpty ? nil : Array(selectedPaths)

        let response: APIResponse<AlbumArtistListResult>
        if keyType.lowercased() == "artist" {
            response = await MusicService.listArtists(
                page: nextPage,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder,
                sourceList: sourceListParam
            )
        } else {
            response = await MusicService.listAlbums(
                page: nextPage,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder,
                sourceList: sourceListParam
            )
        }

        guard response.success, let data = response.data else {
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.hasNextPage
        isLoading = false
    }
}

struct MusicAlbumArtistGridSection: View {
    let keyType: String
    let onSelect: (AlbumArtistItem) -> Void

    @StateObject private var viewModel: MusicAlbumArtistViewModel
    @State private var isShowingSortSheet = false
    @State private var isShowingSourceSheet = false

    init(keyType: String, onSelect: @escaping (AlbumArtistItem) -> Void) {
        self.keyType = keyType
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: MusicAlbumArtistViewModel(keyType: keyType))
    }

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let desiredWidth: CGFloat = maxWidth < 1000 ? 200 : 240
            let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 48
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    let placeholder = keyType.lowercased() == "artist" ? L10n.musicSearchArtistHint : L10n.musicSearchAlbumHint
                    MusicSearchBar(text: $viewModel.searchText, placeholder: placeholder, onSearch: { Task { await viewModel.reload() } })
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
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            MusicAlbumArtistCard(
                                item: item,
                                keyType: keyType
                            ) {
                                onSelect(item)
                            }
                            .frame(maxWidth: .infinity)
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
            MusicAlbumArtistSourceSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            MusicAlbumArtistSortSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Album/Artist Source Sheet

private struct MusicAlbumArtistSourceSheet: View {
    @ObservedObject var viewModel: MusicAlbumArtistViewModel

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

// MARK: - Album/Artist Sort Sheet

private struct MusicAlbumArtistSortSheet: View {
    @ObservedObject var viewModel: MusicAlbumArtistViewModel

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
                                Task {
                                    await viewModel.applySort(by: option.sortBy, order: option.sortOrder)
                                }
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

struct MusicAlbumArtistCard: View {
    let item: AlbumArtistItem
    let keyType: String
    let onTap: () -> Void

    private var coverFilePath: String { item.firstFilePath }

    private var fallbackName: String {
        let idx = (abs(item.name.hashValue) % 20) + 1
        return "other\(idx)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            MusicCoverImage(filePath: coverFilePath, size: 400, fallbackName: fallbackName)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(item.name)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if item.indexCount > 0 {
                    Text(L10n.musicItemCount(item.indexCount))
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.08))
    }
}

// MARK: - Playlist Grid Section

@MainActor
final class MusicPlaylistViewModel: ObservableObject {
    @Published private(set) var items: [MusicPlaylistItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var sortBy = "create_time"
    @Published var sortOrder = "desc"

    private var page = 1
    private var hasNextPage = true

    struct SortOption: Identifiable {
        let id = UUID()
        let sortBy: String
        let sortOrder: String
        let labelKey: String
    }

    var availableSortOptions: [SortOption] {
        [
            SortOption(sortBy: "create_time", sortOrder: "desc", labelKey: "music_playlist_sort_create_time_desc"),
            SortOption(sortBy: "name", sortOrder: "asc", labelKey: "music_playlist_sort_name_asc"),
        ]
    }

    var currentSortLabel: String {
        if let opt = availableSortOptions.first(where: { $0.sortBy == sortBy && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.videoSortTitle
    }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func applySort(by: String, order: String) async {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        await reload()
    }

    func applySearch() async {
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasNextPage = true

        let response = await MusicService.listPlaylists(
            page: page,
            pageSize: 30,
            search: searchText.isEmpty ? nil : searchText,
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
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: MusicPlaylistItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        let nextPage = page + 1
        let response = await MusicService.listPlaylists(
            page: nextPage,
            pageSize: 30,
            search: searchText.isEmpty ? nil : searchText,
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
}

struct MusicPlaylistGridSection: View {
    let onSelect: (MusicPlaylistItem) -> Void

    @StateObject private var viewModel = MusicPlaylistViewModel()
    @State private var isShowingSortSheet = false

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            // 自建歌单卡片放大约 30%
            let baseDesiredWidth: CGFloat = maxWidth < 1000 ? 200 : 240
            let desiredWidth: CGFloat = baseDesiredWidth * 1.3
            let columnsCount = max(3, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 48
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    MusicSearchBar(text: $viewModel.searchText, placeholder: L10n.musicSearchTitleHint, onSearch: { Task { await viewModel.applySearch() } })
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
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            MusicPlaylistCard(item: item) {
                                onSelect(item)
                            }
                            .frame(maxWidth: .infinity)
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
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            MusicPlaylistSortSheet(viewModel: viewModel)
        }
    }
}

private struct MusicPlaylistSortSheet: View {
    @ObservedObject var viewModel: MusicPlaylistViewModel

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
                                Task {
                                    await viewModel.applySort(by: option.sortBy, order: option.sortOrder)
                                }
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

struct MusicPlaylistCard: View {
    let item: MusicPlaylistItem
    let onTap: () -> Void

    private var previewPaths: [String] {
        item.previews.prefix(4).map { $0.fullPath }.filter { !$0.isEmpty }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { playlistPreviewContent() }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(item.name)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.08))
    }

    @ViewBuilder
    private func playlistPreviewContent() -> some View {
        if previewPaths.isEmpty {
            Image("default_cover")
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if previewPaths.count == 1 {
            MusicCoverImage(filePath: previewPaths[0], size: 400, fallbackName: "default_cover")
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            let spacing = 1.0 / (UIScreen.main.scale)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let count = CGFloat(min(previewPaths.count, 4))
                let itemW = (w - spacing * (count - 1)) / 2
                let itemH = (h - spacing) / 2
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(Array(previewPaths.prefix(2).enumerated()), id: \.offset) { i, p in
                            MusicCoverImage(filePath: p, size: 200, fallbackName: "default_cover")
                                .frame(width: itemW, height: itemH)
                                .clipped()
                        }
                    }
                    HStack(spacing: spacing) {
                        ForEach(Array(previewPaths.dropFirst(2).prefix(2).enumerated()), id: \.offset) { i, p in
                            MusicCoverImage(filePath: p, size: 200, fallbackName: "default_cover")
                                .frame(width: itemW, height: itemH)
                                .clipped()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Collection Grid Section

@MainActor
final class MusicCollectionViewModel: ObservableObject {
    @Published private(set) var items: [MusicCollectionItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var sortField = "create_time"
    @Published var sortOrder = "desc"

    private var page = 1
    private var hasNextPage = true

    struct SortOption: Identifiable {
        let id = UUID()
        let sortField: String
        let sortOrder: String
        let labelKey: String
    }

    var availableSortOptions: [SortOption] {
        [
            SortOption(sortField: "create_time", sortOrder: "desc", labelKey: "music_collection_sort_create_time_desc"),
            SortOption(sortField: "name", sortOrder: "asc", labelKey: "music_collection_sort_name_asc"),
        ]
    }

    var currentSortLabel: String {
        if let opt = availableSortOptions.first(where: { $0.sortField == sortField && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.videoSortTitle
    }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func applySort(field: String, order: String) async {
        guard sortField != field || sortOrder != order else { return }
        sortField = field
        sortOrder = order
        await reload()
    }

    func applySearch() async {
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasNextPage = true

        let response = await MusicService.listCollections(
            page: page,
            pageSize: 20,
            keyword: searchText.isEmpty ? nil : searchText,
            sortField: sortField,
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
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: MusicCollectionItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        let nextPage = page + 1
        let response = await MusicService.listCollections(
            page: nextPage,
            pageSize: 20,
            keyword: searchText.isEmpty ? nil : searchText,
            sortField: sortField,
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
}

struct MusicCollectionGridSection: View {
    let onSelect: (MusicCollectionItem) -> Void

    @StateObject private var viewModel = MusicCollectionViewModel()
    @State private var isShowingSortSheet = false

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            // 与视频合集区域对齐的宽度与间距
            let baseDesiredWidth: CGFloat = maxWidth < 1000 ? 216 : 252
            let desiredWidth: CGFloat = baseDesiredWidth * 2
            let columnsCount = max(2, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 64
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    MusicSearchBar(text: $viewModel.searchText, placeholder: L10n.musicSearchTitleHint, onSearch: { Task { await viewModel.applySearch() } })
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
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            MusicCollectionCard(item: item) {
                                onSelect(item)
                            }
                            .frame(maxWidth: .infinity)
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
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            MusicCollectionSortSheet(viewModel: viewModel)
        }
    }
}

private struct MusicCollectionSortSheet: View {
    @ObservedObject var viewModel: MusicCollectionViewModel

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
                                isSelected: viewModel.sortField == option.sortField && viewModel.sortOrder == option.sortOrder
                            ) {
                                Task {
                                    await viewModel.applySort(field: option.sortField, order: option.sortOrder)
                                }
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

struct MusicCollectionCard: View {
    let item: MusicCollectionItem
    let onTap: () -> Void

    private var previewPaths: [String] {
        item.previews.prefix(4).map { p in
            let path = (p.showType.trimmingCharacters(in: .whitespaces).lowercased() == "series" ? p.firstFilePath : p.fullPath).trimmingCharacters(in: .whitespaces)
            return path
        }.filter { !$0.isEmpty }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { collectionPreviewContent() }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(item.name)
                    .font(.system(size: 24))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.08))
    }

    @ViewBuilder
    private func collectionPreviewContent() -> some View {
        if previewPaths.isEmpty {
            Image("default_cover")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if previewPaths.count == 1 {
            MusicCoverImage(filePath: previewPaths[0], size: 800, fallbackName: "default_cover")
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            let spacing = 1.0 / UIScreen.main.scale
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let totalHeight = geo.size.height
                let displayPaths = Array(previewPaths.prefix(4))
                let count = CGFloat(displayPaths.count)
                let itemWidth = count > 0
                    ? (totalWidth - spacing * (count - 1)) / count
                    : totalWidth

                HStack(spacing: spacing) {
                    ForEach(Array(displayPaths.enumerated()), id: \.offset) { idx, p in
                        MusicCoverImage(
                            filePath: p,
                            size: 400,
                            fallbackName: "default_cover"
                        )
                        .frame(width: itemWidth, height: totalHeight)
                        .clipped()
                    }
                }
                .frame(width: totalWidth, height: totalHeight, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
