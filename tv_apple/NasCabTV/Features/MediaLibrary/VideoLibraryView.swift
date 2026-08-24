import SwiftUI
import UIKit

// MARK: - Album / Collection / Smart Album Services

@MainActor
enum TVVideoAlbumService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVVideoAlbumListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder
        ]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVVideoAlbumListResult> = await api.apiPost(
            "/api/video/album/list",
            body: body,
            dataParser: { data, _ in
                TVVideoAlbumListResult(json: data)
            }
        )
        return response
    }
}

@MainActor
enum TVVideoCollectionService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVVideoCollectionListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder
        ]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVVideoCollectionListResult> = await api.apiPost(
            "/api/video/collection/list",
            body: body,
            dataParser: { data, _ in
                TVVideoCollectionListResult(json: data)
            }
        )
        return response
    }
}

@MainActor
enum TVVideoSmartAlbumService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVVideoSmartAlbumListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder
        ]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVVideoSmartAlbumListResult> = await api.apiPost(
            "/api/video/smart_album/list",
            body: body,
            dataParser: { data, _ in
                TVVideoSmartAlbumListResult(json: data)
            }
        )
        return response
    }
}

// MARK: - Album Videos List Page

struct TVVideoAlbumVideosView: View {
    let title: String
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: TVVideoItem?

    private var typeSuffix: String {
        if let albumId, albumId > 0 {
            return L10n.videoTabCustomAlbum
        }
        if let collectionId, collectionId > 0 {
            return L10n.videoTabCollection
        }
        if let smartAlbumId, smartAlbumId > 0 {
            return L10n.videoTabSmartAlbum
        }
        return ""
    }

    private var navTitle: String {
        guard !typeSuffix.isEmpty else { return title }
        return "\(title) - \(typeSuffix)"
    }

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

                TVVideoGridSection(
                    mediaType: "",
                    albumId: albumId,
                    collectionId: collectionId,
                    smartAlbumId: smartAlbumId,
                    onSelect: { item in
                        selectedItem = item
                    }
                )
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                    }
                }
            }
            .fullScreenCover(item: $selectedItem) { item in
                TVVideoDetailView(item: item)
            }
        }
    }
}

// MARK: - 演职人员出演影片列表（与影集/专辑列表同风格，顶部显示演职人员名称）

struct TVVideoPersonVideosView: View {
    /// 页面标题，如 "导演-张三" 或 "演员-李四"
    let title: String
    let personName: String
    let isDirector: Bool
    /// 与当前详情 mediaType 一致，season 会解析为 tv
    let mediaType: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: TVVideoItem?

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

                TVVideoGridSection(
                    mediaType: mediaType,
                    actors: isDirector ? [] : [personName],
                    directors: isDirector ? [personName] : [],
                    onSelect: { selectedItem = $0 }
                )
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                    }
                }
            }
            .fullScreenCover(item: $selectedItem) { item in
                TVVideoDetailView(item: item)
            }
        }
    }
}

// MARK: - 顶部 Tab

private enum TVVideoLibraryTab: CaseIterable, Identifiable {
    case movie
    case tv
    case recentPlay
    case favorite
    case customAlbum
    case smartAlbum
    case collection

    var id: String { title }

    var title: String {
        switch self {
        case .movie: return L10n.videoTabMovie
        case .tv: return L10n.videoTabTv
        case .recentPlay: return L10n.videoTabRecentPlay
        case .favorite: return L10n.videoTabFavorite
        case .customAlbum: return L10n.videoTabCustomAlbum
        case .smartAlbum: return L10n.videoTabSmartAlbum
        case .collection: return L10n.videoTabCollection
        }
    }

    /// 列表类型：favorite=收藏列表，recent=最近播放（API 用 sort view_time desc），空=普通
    var listTypeParam: String {
        switch self {
        case .favorite: return "favorite"
        case .recentPlay: return "recent"
        default: return ""
        }
    }

    var mediaTypeParam: String {
        switch self {
        case .movie: return "movie"
        case .tv: return "tv"
        default: return ""
        }
    }
}

// MARK: - 排序模型

enum TVVideoSortBy: String, CaseIterable, Identifiable {
    case viewTime = "view_time"
    case favoriteTime = "favorite_time"
    case year = "year"
    case score = "score"
    case createTime = "create_time"
    case name = "name"

    var id: String { rawValue }
}

enum TVVideoSortOrder: String, CaseIterable, Identifiable {
    case asc
    case desc

    var id: String { rawValue }
}

private struct TVVideoSortOption: Identifiable, Equatable {
    let id = UUID()
    let by: TVVideoSortBy
    let order: TVVideoSortOrder
    let labelKey: String
}

private let tvVideoSortOptions: [TVVideoSortOption] = [
    TVVideoSortOption(by: .viewTime, order: .desc, labelKey: "video_list_sort_view_time_desc"),
    TVVideoSortOption(by: .viewTime, order: .asc, labelKey: "video_list_sort_view_time_asc"),
    TVVideoSortOption(by: .favoriteTime, order: .desc, labelKey: "video_list_sort_favorite_time_desc"),
    TVVideoSortOption(by: .favoriteTime, order: .asc, labelKey: "video_list_sort_favorite_time_asc"),
    TVVideoSortOption(by: .createTime, order: .desc, labelKey: "create_time_desc"),
    TVVideoSortOption(by: .createTime, order: .asc, labelKey: "create_time_asc"),
    TVVideoSortOption(by: .year, order: .desc, labelKey: "video_list_sort_year_desc"),
    TVVideoSortOption(by: .year, order: .asc, labelKey: "video_list_sort_year_asc"),
    TVVideoSortOption(by: .score, order: .desc, labelKey: "video_list_sort_score_desc"),
    TVVideoSortOption(by: .score, order: .asc, labelKey: "video_list_sort_score_asc"),
    TVVideoSortOption(by: .name, order: .asc, labelKey: "name_asc"),
    TVVideoSortOption(by: .name, order: .desc, labelKey: "name_desc"),
]

private let tvAlbumSortOptions: [TVVideoSortOption] = [
    TVVideoSortOption(by: .createTime, order: .desc, labelKey: "create_time_desc"),
    TVVideoSortOption(by: .createTime, order: .asc, labelKey: "create_time_asc"),
    TVVideoSortOption(by: .name, order: .asc, labelKey: "name_asc"),
    TVVideoSortOption(by: .name, order: .desc, labelKey: "name_desc"),
]

// MARK: - ViewModel

@MainActor
final class TVVideoListViewModel: ObservableObject {
    @Published private(set) var items: [TVVideoItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortBy: TVVideoSortBy = .viewTime
    @Published var sortOrder: TVVideoSortOrder = .desc
    @Published var availablePaths: [TVVideoPathItem] = []
    @Published var selectedPaths: Set<String> = []

    private var page: Int = 1
    private var hasNextPage: Bool = true
    private let mediaType: String
    private let listType: String
    private let albumId: Int?
    private let collectionId: Int?
    private let smartAlbumId: Int?
    private let initialActors: [String]
    private let initialDirectors: [String]

    init(
        mediaType: String,
        listType: String = "",
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        actors: [String] = [],
        directors: [String] = []
    ) {
        self.mediaType = mediaType
        self.listType = listType.trimmingCharacters(in: .whitespaces)
        self.albumId = albumId
        self.collectionId = collectionId
        self.smartAlbumId = smartAlbumId
        self.initialActors = actors
        self.initialDirectors = directors

        // 最近播放：固定按观看时间倒序（API 无 listType recent，仅用 sort view_time desc）
        if self.listType == "recent" {
            sortBy = .viewTime
            sortOrder = .desc
        }
        if self.listType == "favorite" {
            sortBy = .favoriteTime
            sortOrder = .desc
        }

        // 恢复排序持久化设置（非 listType 列表时）
        guard self.listType.isEmpty else { return }
        let defaults = UserDefaults.standard
        let keyPrefix = "tv_video_sort_\(mediaType.isEmpty ? "all" : mediaType)"
        if let byRaw = defaults.string(forKey: "\(keyPrefix)_by"),
           let savedBy = TVVideoSortBy(rawValue: byRaw) {
            sortBy = savedBy
        }
        if let orderRaw = defaults.string(forKey: "\(keyPrefix)_order"),
           let savedOrder = TVVideoSortOrder(rawValue: orderRaw) {
            sortOrder = savedOrder
        }
    }

    var hasSourceFilter: Bool {
        !selectedPaths.isEmpty
    }

    var sourceFilterCount: Int {
        selectedPaths.count
    }

    var currentSortLabel: String {
        if let option = tvVideoSortOptions.first(where: { $0.by == sortBy && $0.order == sortOrder }) {
            return L10n.tr(option.labelKey)
        }
        return L10n.videoSortTitle
    }

    /// 是否为收藏 tab（仅收藏 tab 显示按收藏时间排序选项）
    var isFavoriteTab: Bool { listType == "favorite" }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasNextPage = true

        if listType == "recent" {
            let response = await TVVideoListService.loadHistory()
            guard response.success, let data = response.data else {
                errorMessage = response.message ?? L10n.networkFailure
                isLoading = false
                isInitialLoaded = true
                items = []
                hasNextPage = false
                return
            }
            items = data.items
            hasNextPage = false
            if !data.validPaths.isEmpty {
                availablePaths = data.validPaths
            }
            isLoading = false
            isInitialLoaded = true
            return
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchParam = trimmedSearch.isEmpty ? nil : trimmedSearch
        let sourceListParam = selectedPaths.isEmpty ? [] : Array(selectedPaths)

        let response = await TVVideoListService.loadPage(
            mediaType: mediaType,
            page: page,
            pageSize: 30,
            listType: listType,
            albumId: albumId,
            collectionId: collectionId,
            smartAlbumId: smartAlbumId,
            search: searchParam,
            sourceList: sourceListParam,
            actors: initialActors,
            directors: initialDirectors,
            sortBy: sortBy.rawValue,
            sortOrder: sortOrder.rawValue
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
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

    func loadMoreIfNeeded(current item: TVVideoItem?) async {
        guard listType != "recent" else { return }
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        errorMessage = nil

        let nextPage = page + 1
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchParam = trimmedSearch.isEmpty ? nil : trimmedSearch
        let sourceListParam = selectedPaths.isEmpty ? [] : Array(selectedPaths)

        let response = await TVVideoListService.loadPage(
            mediaType: mediaType,
            page: nextPage,
            pageSize: 30,
            listType: listType,
            albumId: albumId,
            collectionId: collectionId,
            smartAlbumId: smartAlbumId,
            search: searchParam,
            sourceList: sourceListParam,
            actors: initialActors,
            directors: initialDirectors,
            sortBy: sortBy.rawValue,
            sortOrder: sortOrder.rawValue
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.hasNextPage
        isLoading = false
    }

    // MARK: - Intent

    func applySearch(text: String) {
        let newValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchText = newValue
        Task { [weak self] in
            await self?.reload()
        }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { [weak self] in
            await self?.reload()
        }
    }

    func applySort(by: TVVideoSortBy, order: TVVideoSortOrder) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order

        // 持久化当前排序设置
        let defaults = UserDefaults.standard
        let keyPrefix = "tv_video_sort_\(mediaType.isEmpty ? "all" : mediaType)"
        defaults.set(by.rawValue, forKey: "\(keyPrefix)_by")
        defaults.set(order.rawValue, forKey: "\(keyPrefix)_order")

        Task { [weak self] in
            await self?.reload()
        }
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

@MainActor
final class TVAlbumListViewModel<Item>: ObservableObject where Item: Identifiable & Equatable {
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortBy: TVVideoSortBy = .createTime
    @Published var sortOrder: TVVideoSortOrder = .desc

    private var page: Int = 1
    private var hasNextPage: Bool = true
    private let storageKeyPrefix: String
    private let loadPageBlock: (
        _ page: Int,
        _ pageSize: Int,
        _ keyword: String?,
        _ sortBy: String,
        _ sortOrder: String
    ) async -> APIResponse<Any>

    init(
        storageKeyPrefix: String,
        loadPage: @escaping (
            _ page: Int,
            _ pageSize: Int,
            _ keyword: String?,
            _ sortBy: String,
            _ sortOrder: String
        ) async -> APIResponse<Any>
    ) {
        self.storageKeyPrefix = storageKeyPrefix
        self.loadPageBlock = loadPage

        let defaults = UserDefaults.standard
        if let byRaw = defaults.string(forKey: "\(storageKeyPrefix)_by"),
           let savedBy = TVVideoSortBy(rawValue: byRaw) {
            sortBy = savedBy
        }
        if let orderRaw = defaults.string(forKey: "\(storageKeyPrefix)_order"),
           let savedOrder = TVVideoSortOrder(rawValue: orderRaw) {
            sortOrder = savedOrder
        }
    }

    var currentSortLabel: String {
        if let option = tvAlbumSortOptions.first(where: { $0.by == sortBy && $0.order == sortOrder }) {
            return L10n.tr(option.labelKey)
        }
        return L10n.videoSortTitle
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

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchParam = trimmedSearch.isEmpty ? nil : trimmedSearch

        let response = await loadPageBlock(
            page,
            30,
            searchParam,
            sortBy.rawValue,
            sortOrder.rawValue
        )

        guard response.success, let anyData = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
            return
        }

        if let albumResult = anyData as? TVVideoAlbumListResult, Item.self == TVVideoAlbumItem.self {
            items = albumResult.items as? [Item] ?? []
            hasNextPage = albumResult.pagination.page * albumResult.pagination.pageSize < albumResult.pagination.total
        } else if let smartResult = anyData as? TVVideoSmartAlbumListResult, Item.self == TVVideoSmartAlbumItem.self {
            items = smartResult.items as? [Item] ?? []
            hasNextPage = smartResult.pagination.page * smartResult.pagination.pageSize < smartResult.pagination.total
        } else if let collectionResult = anyData as? TVVideoCollectionListResult, Item.self == TVVideoCollectionItem.self {
            items = collectionResult.items as? [Item] ?? []
            hasNextPage = collectionResult.pagination.page * collectionResult.pagination.pageSize < collectionResult.pagination.total
        } else {
            items = []
            hasNextPage = false
        }

        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: Item?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        errorMessage = nil

        let nextPage = page + 1
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchParam = trimmedSearch.isEmpty ? nil : trimmedSearch

        let response = await loadPageBlock(
            nextPage,
            30,
            searchParam,
            sortBy.rawValue,
            sortOrder.rawValue
        )

        guard response.success, let anyData = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            return
        }

        page = nextPage

        if let albumResult = anyData as? TVVideoAlbumListResult, Item.self == TVVideoAlbumItem.self {
            if let newItems = albumResult.items as? [Item] {
                items.append(contentsOf: newItems)
            }
            hasNextPage = albumResult.pagination.page * albumResult.pagination.pageSize < albumResult.pagination.total
        } else if let smartResult = anyData as? TVVideoSmartAlbumListResult, Item.self == TVVideoSmartAlbumItem.self {
            if let newItems = smartResult.items as? [Item] {
                items.append(contentsOf: newItems)
            }
            hasNextPage = smartResult.pagination.page * smartResult.pagination.pageSize < smartResult.pagination.total
        } else if let collectionResult = anyData as? TVVideoCollectionListResult, Item.self == TVVideoCollectionItem.self {
            if let newItems = collectionResult.items as? [Item] {
                items.append(contentsOf: newItems)
            }
            hasNextPage = collectionResult.pagination.page * collectionResult.pagination.pageSize < collectionResult.pagination.total
        }

        isLoading = false
    }

    // MARK: - Intent

    func applySearch(text: String) {
        let newValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        searchText = newValue
        Task { [weak self] in
            await self?.reload()
        }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { [weak self] in
            await self?.reload()
        }
    }

    func applySort(by: TVVideoSortBy, order: TVVideoSortOrder) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order

        let defaults = UserDefaults.standard
        defaults.set(by.rawValue, forKey: "\(storageKeyPrefix)_by")
        defaults.set(order.rawValue, forKey: "\(storageKeyPrefix)_order")

        Task { [weak self] in
            await self?.reload()
        }
    }
}

// MARK: - 主入口

struct VideoLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: TVVideoLibraryTab = .movie
    @State private var activeDetailItem: TVVideoItem?

    var body: some View {
        NavigationStack {
            ZStack {
                // 先铺一层纯黑，确保完全遮住首页背景
                Color.black
                    .ignoresSafeArea()
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

                VStack(alignment: .leading, spacing: 32) {
                    headerBar
                        .focusSection()
                    tabBar
                        .focusSection()
                    tabContent
                        .focusSection()
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 40)
            }
            .navigationTitle(L10n.homeMediaLibrary)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $activeDetailItem) { item in
                TVVideoDetailView(item: item)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.backward")
                    .font(.title2)
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Spacer()

            Text(L10n.homeMediaLibrary)
                .font(.title)
                .fontWeight(.bold)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(TVVideoLibraryTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.title)
                                .font(.headline)
                                .foregroundStyle(tab == selectedTab ? Color.white : Color.secondary)
                            Rectangle()
                                .fill(tab == selectedTab ? Color.accentColor : Color.clear)
                                .frame(height: 3)
                                .cornerRadius(1.5)
                        }
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(NCTabBarButtonStyle())
                }
            }
            .padding(.trailing, 40)
        }
        .clipped()
        .frame(height: 52)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .movie:
            TVVideoGridSection(
                mediaType: "movie",
                listType: "",
                onSelect: { item in
                    activeDetailItem = item
                }
            )
        case .tv:
            TVVideoGridSection(
                mediaType: "tv",
                listType: "",
                onSelect: { item in
                    activeDetailItem = item
                }
            )
        case .recentPlay:
            TVVideoGridSection(
                mediaType: "",
                listType: "recent",
                onSelect: { item in
                    activeDetailItem = item
                }
            )
        case .favorite:
            TVVideoGridSection(
                mediaType: "",
                listType: "favorite",
                onSelect: { item in
                    activeDetailItem = item
                }
            )
        case .customAlbum:
            TVAlbumGridSection(mode: .album)
        case .smartAlbum:
            TVAlbumGridSection(mode: .smartAlbum)
        case .collection:
            TVAlbumGridSection(mode: .collection)
        }
    }
}

// MARK: - 网格 Section

private enum TVVideoGridActiveSheet: Identifiable {
    case sort
    case source

    var id: Int {
        switch self {
        case .sort: return 1
        case .source: return 2
        }
    }
}

private struct TVVideoGridSection: View {
    let mediaType: String
    let listType: String
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?
    let initialActors: [String]
    let initialDirectors: [String]
    let onSelect: (TVVideoItem) -> Void
    @StateObject private var viewModel: TVVideoListViewModel
    @State private var activeSheet: TVVideoGridActiveSheet?

    init(
        mediaType: String,
        listType: String = "",
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        actors: [String] = [],
        directors: [String] = [],
        onSelect: @escaping (TVVideoItem) -> Void = { _ in }
    ) {
        self.mediaType = mediaType
        self.listType = listType
        self.albumId = albumId
        self.collectionId = collectionId
        self.smartAlbumId = smartAlbumId
        self.initialActors = actors
        self.initialDirectors = directors
        self.onSelect = onSelect
        _viewModel = StateObject(
            wrappedValue: TVVideoListViewModel(
                mediaType: mediaType,
                listType: listType,
                albumId: albumId,
                collectionId: collectionId,
                smartAlbumId: smartAlbumId,
                actors: actors,
                directors: directors
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let desiredWidth: CGFloat = maxWidth < 1000 ? 216 : 252
            let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 64
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 32) {
                if listType != "recent" {
                    TVVideoFilterBar(
                        viewModel: viewModel,
                        onShowSort: { activeSheet = .sort },
                        onShowSource: { activeSheet = .source }
                    )
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                }

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            TVVideoPosterCard(
                                item: item,
                                onTap: { onSelect(item) }
                            )
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMoreIfNeeded(current: item)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 40) // 左右留白，避免放大后紧贴边缘
                    .padding(.top, 32)        // 顶部留白，避免放大后被遮挡
                    .padding(.bottom, 128)     // 底部留白，避免放大后被下缘裁剪
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
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .sort:
                TVVideoSortSheet(viewModel: viewModel)
            case .source:
                TVVideoSourceSheet(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Album Videos Context

private struct TVAlbumVideosContext: Identifiable {
    let id = UUID()
    let title: String
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?
}

// MARK: - Album Grid Section

private enum TVAlbumSectionMode {
    case album
    case smartAlbum
    case collection

    var storageKeyPrefix: String {
        switch self {
        case .album: return "tv_album_sort_custom"
        case .smartAlbum: return "tv_album_sort_smart"
        case .collection: return "tv_album_sort_collection"
        }
    }
}

private struct TVAlbumGridSection: View {
    let mode: TVAlbumSectionMode

    @StateObject private var albumViewModel: TVAlbumListViewModel<TVVideoAlbumItem>
    @StateObject private var smartViewModel: TVAlbumListViewModel<TVVideoSmartAlbumItem>
    @StateObject private var collectionViewModel: TVAlbumListViewModel<TVVideoCollectionItem>
    @State private var isShowingSortSheet = false
    @State private var activeVideosContext: TVAlbumVideosContext?

    init(mode: TVAlbumSectionMode) {
        self.mode = mode

        _albumViewModel = StateObject(
            wrappedValue: TVAlbumListViewModel<TVVideoAlbumItem>(
                storageKeyPrefix: TVAlbumSectionMode.album.storageKeyPrefix,
                loadPage: { page, pageSize, keyword, sortBy, sortOrder in
                    let res = await TVVideoAlbumService.loadPage(
                        page: page,
                        pageSize: pageSize,
                        keyword: keyword,
                        sortBy: sortBy,
                        sortOrder: sortOrder
                    )
                    return APIResponse<Any>(
                        success: res.success,
                        data: res.data,
                        message: res.message,
                        code: res.code,
                        rawResponse: res.rawResponse
                    )
                }
            )
        )

        _smartViewModel = StateObject(
            wrappedValue: TVAlbumListViewModel<TVVideoSmartAlbumItem>(
                storageKeyPrefix: TVAlbumSectionMode.smartAlbum.storageKeyPrefix,
                loadPage: { page, pageSize, keyword, sortBy, sortOrder in
                    let res = await TVVideoSmartAlbumService.loadPage(
                        page: page,
                        pageSize: pageSize,
                        keyword: keyword,
                        sortBy: sortBy,
                        sortOrder: sortOrder
                    )
                    return APIResponse<Any>(
                        success: res.success,
                        data: res.data,
                        message: res.message,
                        code: res.code,
                        rawResponse: res.rawResponse
                    )
                }
            )
        )

        _collectionViewModel = StateObject(
            wrappedValue: TVAlbumListViewModel<TVVideoCollectionItem>(
                storageKeyPrefix: TVAlbumSectionMode.collection.storageKeyPrefix,
                loadPage: { page, pageSize, keyword, sortBy, sortOrder in
                    let res = await TVVideoCollectionService.loadPage(
                        page: page,
                        pageSize: pageSize,
                        keyword: keyword,
                        sortBy: sortBy,
                        sortOrder: sortOrder
                    )
                    return APIResponse<Any>(
                        success: res.success,
                        data: res.data,
                        message: res.message,
                        code: res.code,
                        rawResponse: res.rawResponse
                    )
                }
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            // 基础卡片尺寸放大一倍
            let baseDesiredWidth: CGFloat = maxWidth < 1000 ? 216 : 252
            let desiredWidth: CGFloat = baseDesiredWidth * 2
            let columnsCount = max(2, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 64
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 32) {
                albumFilterBar
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        switch mode {
                        case .album:
                            ForEach(albumViewModel.items) { item in
                                TVAlbumPosterCard(
                                    title: item.name,
                                    previews: item.previews,
                                    albumId: item.id,
                                    collectionId: nil,
                                    smartAlbumId: nil
                                ) {
                                    activeVideosContext = TVAlbumVideosContext(
                                        title: item.name,
                                        albumId: item.id,
                                        collectionId: nil,
                                        smartAlbumId: nil
                                    )
                                }
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .onAppear {
                                        Task {
                                            await albumViewModel.loadMoreIfNeeded(current: item)
                                        }
                                    }
                            }
                        case .smartAlbum:
                            ForEach(smartViewModel.items) { item in
                                TVAlbumPosterCard(
                                    title: item.name,
                                    previews: item.previews,
                                    albumId: nil,
                                    collectionId: nil,
                                    smartAlbumId: item.id
                                ) {
                                    activeVideosContext = TVAlbumVideosContext(
                                        title: item.name,
                                        albumId: nil,
                                        collectionId: nil,
                                        smartAlbumId: item.id
                                    )
                                }
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .onAppear {
                                        Task {
                                            await smartViewModel.loadMoreIfNeeded(current: item)
                                        }
                                    }
                            }
                        case .collection:
                            ForEach(collectionViewModel.items) { item in
                                TVAlbumPosterCard(
                                    title: item.name,
                                    previews: item.previews,
                                    albumId: nil,
                                    collectionId: item.id,
                                    smartAlbumId: nil
                                ) {
                                    activeVideosContext = TVAlbumVideosContext(
                                        title: item.name,
                                        albumId: nil,
                                        collectionId: item.id,
                                        smartAlbumId: nil
                                    )
                                }
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .onAppear {
                                        Task {
                                            await collectionViewModel.loadMoreIfNeeded(current: item)
                                        }
                                    }
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
                switch mode {
                case .album:
                    albumOverlay(viewModel: albumViewModel)
                case .smartAlbum:
                    albumOverlay(viewModel: smartViewModel)
                case .collection:
                    albumOverlay(viewModel: collectionViewModel)
                }
            }
            .task {
                switch mode {
                case .album:
                    await albumViewModel.loadInitialIfNeeded()
                case .smartAlbum:
                    await smartViewModel.loadInitialIfNeeded()
                case .collection:
                    await collectionViewModel.loadInitialIfNeeded()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            switch mode {
            case .album:
                TVAlbumSortSheet(viewModel: albumViewModel)
            case .smartAlbum:
                TVAlbumSortSheet(viewModel: smartViewModel)
            case .collection:
                TVAlbumSortSheet(viewModel: collectionViewModel)
            }
        }
        .fullScreenCover(item: $activeVideosContext) { ctx in
            TVVideoAlbumVideosView(
                title: ctx.title,
                albumId: ctx.albumId,
                collectionId: ctx.collectionId,
                smartAlbumId: ctx.smartAlbumId
            )
        }
    }

    @ViewBuilder
    private var albumFilterBar: some View {
        switch mode {
        case .album:
            TVAlbumFilterBar(viewModel: albumViewModel, onShowSort: { isShowingSortSheet = true })
        case .smartAlbum:
            TVAlbumFilterBar(viewModel: smartViewModel, onShowSort: { isShowingSortSheet = true })
        case .collection:
            TVAlbumFilterBar(viewModel: collectionViewModel, onShowSort: { isShowingSortSheet = true })
        }
    }

    private func albumOverlay<Item>(
        viewModel: TVAlbumListViewModel<Item>
    ) -> some View where Item: Identifiable & Equatable {
        Group {
            if viewModel.isLoading && !viewModel.isInitialLoaded {
                ProgressView()
                    .scaleEffect(1.4)
            } else if viewModel.items.isEmpty && viewModel.isInitialLoaded {
                Text(viewModel.errorMessage ?? L10n.noData)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Album Filter / Search

private struct TVAlbumFilterBar<VM: ObservableObject>: View where VM: TVAlbumFilterViewModelProtocol {
    @ObservedObject var viewModel: VM
    let onShowSort: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            TVAlbumSearchBar(viewModel: viewModel)
                .frame(maxWidth: 620)

            Spacer()

            Button(action: onShowSort) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline)
                    Text(viewModel.currentSortLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
    }
}

private protocol TVAlbumFilterViewModelProtocol: AnyObject {
    var searchText: String { get set }
    var currentSortLabel: String { get }
    func applySearch(text: String)
    func clearSearchAndReload()
}

extension TVAlbumListViewModel: TVAlbumFilterViewModelProtocol {}

private struct TVAlbumSearchBar<VM: ObservableObject & TVAlbumFilterViewModelProtocol>: View {
    @ObservedObject var viewModel: VM

    var body: some View {
        NCSearchInput(
            placeholder: L10n.videoSearchHint,
            text: $viewModel.searchText,
            onSearch: { viewModel.applySearch(text: viewModel.searchText) }
        )
    }
}

// MARK: - Album Sort Sheet

private struct TVAlbumSortSheet<Item>: View where Item: Identifiable & Equatable {
    @ObservedObject var viewModel: TVAlbumListViewModel<Item>

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.videoSortTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tvAlbumSortOptions) { option in
                            NCModalOptionButton(
                                label: L10n.tr(option.labelKey),
                                isSelected: viewModel.sortBy == option.by && viewModel.sortOrder == option.order
                            ) {
                                viewModel.applySort(by: option.by, order: option.order)
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

// MARK: - Album Poster Card

private struct TVAlbumPosterCard: View {
    let title: String
    let previews: [Any]
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?
    let onTap: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            albumPreviewContent()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(title)
                    .font(.system(size: 30))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .center)
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardFocusBorderOnlyStyle(cornerRadius: 18))
    }

    @ViewBuilder
    private func albumPreviewContent() -> some View {
        let paths = previewFilePaths()
        if paths.isEmpty {
            // 无预览图时的占位背景 + 图标
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            let displayPaths = Array(paths.prefix(4))
            let spacing = 1.0 / UIScreen.main.scale
            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let totalHeight = proxy.size.height
                let count = CGFloat(displayPaths.count)
                let itemWidth = count > 0
                    ? (totalWidth - spacing * (count - 1)) / count
                    : totalWidth

                HStack(spacing: spacing) {
                    ForEach(Array(displayPaths.enumerated()), id: \.offset) { _, path in
                        NCRemoteImage(url: tinyURL(for: path), contentMode: .fill)
                            .frame(width: itemWidth, height: totalHeight)
                            .clipped()
                    }
                }
                .frame(width: totalWidth, height: totalHeight, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func previewFilePaths() -> [String] {
        var result: [String] = []
        for any in previews {
            if let albumPreview = any as? TVVideoAlbumPreviewItem {
                let fp = albumPreview.firstFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let full = albumPreview.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
                let path = !fp.isEmpty ? fp : full
                if !path.isEmpty {
                    result.append(path)
                }
            } else if let smartPreview = any as? TVVideoSmartAlbumPreviewItem {
                let fp = smartPreview.firstFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let full = smartPreview.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
                let path = !fp.isEmpty ? fp : full
                if !path.isEmpty {
                    result.append(path)
                }
            } else if let collectionPreview = any as? TVVideoCollectionPreviewItem {
                let fp = collectionPreview.firstFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let full = collectionPreview.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
                let path = !fp.isEmpty ? fp : full
                if !path.isEmpty {
                    result.append(path)
                }
            }
        }
        return result
    }

    private func tinyURL(for filePath: String) -> URL? {
        let api = APIClient.shared
        var base = api.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        if base.hasSuffix("/") {
            base.removeLast()
        }

        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 与 Flutter `Uri.encodeComponent` 行为保持一致
        let allowed: CharacterSet = {
            var set = CharacterSet()
            set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
            return set
        }()
        let encodedPath = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed

        var urlString = "\(base)/api/file/tiny?path=\(encodedPath)"
        if api.isP2pMode {
            urlString += "&p2pChannel=file"
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            let encToken = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
            urlString += "&accessToken=\(encToken)"
        }
        urlString += "&size=500"

        return URL(string: urlString)
    }
}

// MARK: - 搜索 / 筛选栏

private struct TVVideoFilterBar: View {
    @ObservedObject var viewModel: TVVideoListViewModel
    let onShowSort: () -> Void
    let onShowSource: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            TVVideoSearchBar(viewModel: viewModel)
                .frame(maxWidth: 620)

            Spacer()

            Button(action: onShowSort) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline)
                    Text(viewModel.currentSortLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Button(action: onShowSource) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.subheadline)
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
    }
}

// MARK: - 搜索框

private struct TVVideoSearchBar: View {
    @ObservedObject var viewModel: TVVideoListViewModel

    var body: some View {
        NCSearchInput(
            placeholder: L10n.videoSearchHint,
            text: $viewModel.searchText,
            onSearch: { viewModel.applySearch(text: viewModel.searchText) }
        )
    }
}

// MARK: - 排序弹层

private struct TVVideoSortSheet: View {
    @ObservedObject var viewModel: TVVideoListViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.videoSortTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tvVideoSortOptionsFiltered) { option in
                            NCModalOptionButton(
                                label: L10n.tr(option.labelKey),
                                isSelected: viewModel.sortBy == option.by && viewModel.sortOrder == option.order
                            ) {
                                viewModel.applySort(by: option.by, order: option.order)
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

    /// 仅当 tab 为收藏时显示按收藏时间排序选项
    private var tvVideoSortOptionsFiltered: [TVVideoSortOption] {
        viewModel.isFavoriteTab
            ? tvVideoSortOptions
            : tvVideoSortOptions.filter { $0.by != .favoriteTime }
    }
}

// MARK: - 来源目录筛选弹层

private struct TVVideoSourceSheet: View {
    @ObservedObject var viewModel: TVVideoListViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 1100, maxHeight: 720) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(L10n.videoSourceTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(L10n.reset) {
                        viewModel.resetSourceFilter()
                    }
                    .buttonStyle(NCPlainFocusButtonStyle())
                }
                .focusSection()

                if viewModel.availablePaths.isEmpty {
                    Text(L10n.noData)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
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
                                            if !item.valid {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(Color.red.opacity(0.8))
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(NCPlainFocusButtonStyle())
                                .padding(.horizontal, 12)
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

// MARK: - 简单跑马灯文本（用于选中状态下的标题）

private struct TVMarqueeText: View {
    let text: String
    let font: Font
    @State private var animate = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 40) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                Text(text)
                    .font(font)
                    .lineLimit(1)
            }
            .offset(x: animate ? -width : 0)
            .animation(
                Animation.linear(duration: max(6, Double(text.count) * 0.25))
                    .repeatForever(autoreverses: false),
                value: animate
            )
            .onAppear {
                animate = true
            }
        }
        .clipped()
    }
}

// MARK: - 单个海报卡片

private struct TVVideoPosterCard: View {
    let item: TVVideoItem
    let onTap: () -> Void
    @Environment(\.isFocused) private var isFocused

    private var title: String {
        let nfo = item.nfoName.trimmingCharacters(in: .whitespaces)
        let name = !nfo.isEmpty ? nfo : item.filename
        return name
    }

    private var subtitle: String {
        var parts: [String] = []
        if item.nfoYear > 0 {
            parts.append("\(item.nfoYear)")
        }
        let meta = TVVideoMetaUtils.buildMetaSubtitle(for: item)
        if !meta.isEmpty {
            parts.append(meta)
        }
        return parts.joined(separator: " · ")
    }

    private var ratingText: String? {
        guard item.nfoScore > 0 else { return nil }
        return String(format: "%.1f", item.nfoScore)
    }

    private var typeText: String {
        TVVideoMetaUtils.mediaTypeText(item.mediaType)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .overlay {
                            NCRemoteImage(
                                url: TVVideoImageUtils.posterURL(for: item),
                                contentMode: .fill
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.8),
                            Color.black.opacity(0.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)

                    VStack {
                        HStack {
                            if let ratingText {
                                pill(
                                    text: ratingText,
                                    bg: Color.black.opacity(0.5),
                                    fg: Color(red: 229/255, green: 181/255, blue: 39/255)
                                )
                            }
                            Spacer()
                            if !typeText.trimmingCharacters(in: .whitespaces).isEmpty {
                                pill(
                                    text: typeText,
                                    bg: Color.black.opacity(0.5),
                                    fg: .white.opacity(0.95)
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 10)

                        Spacer()
                    }
                    .padding(.bottom, 10)
                }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 24))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .center)

                    // 保留一行副标题的占位，这样有无副标题时整体高度一致，顶部/底部对齐
                    Text(subtitle.isEmpty ? " " : subtitle)
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .opacity(subtitle.isEmpty ? 0 : 1)
                }
                .padding(.bottom, 6)
            }
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.12))
    }

    private func pill(text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(bg)
            )
            .foregroundStyle(fg)
    }
}

