import Foundation
import SwiftUI

// MARK: - Photo Album List ViewModel

private let photoAlbumSortOptions: [(sortBy: String, sortOrder: String, labelKey: String)] = [
    ("create_time", "desc", "create_time_desc"),
    ("create_time", "asc", "create_time_asc"),
    ("name", "asc", "name_asc"),
    ("name", "desc", "name_desc"),
]

@MainActor
final class TVPhotoAlbumListViewModel: ObservableObject {
    @Published private(set) var items: [TVPhotoAlbumItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortBy: String = "create_time"
    @Published var sortOrder: String = "desc"

    private var page: Int = 1
    private var hasNextPage: Bool = true
    private let storageKeyPrefix: String

    init(storageKeyPrefix: String = "tv_photo_album_sort") {
        self.storageKeyPrefix = storageKeyPrefix
        let defaults = UserDefaults.standard
        if let by = defaults.string(forKey: "\(storageKeyPrefix)_by") { sortBy = by }
        if let order = defaults.string(forKey: "\(storageKeyPrefix)_order") { sortOrder = order }
    }

    var currentSortLabel: String {
        if let opt = photoAlbumSortOptions.first(where: { $0.sortBy == sortBy && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.photoTimelineSortTitle
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

        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoAlbumService.loadPage(
            page: page,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
            return
        }

        items = data.items
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: TVPhotoAlbumItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        errorMessage = nil
        let nextPage = page + 1
        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoAlbumService.loadPage(
            page: nextPage,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
    }

    func applySearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespaces)
        Task { await reload() }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { await reload() }
    }

    func applySort(by: String, order: String) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        UserDefaults.standard.set(by, forKey: "\(storageKeyPrefix)_by")
        UserDefaults.standard.set(order, forKey: "\(storageKeyPrefix)_order")
        Task { await reload() }
    }
}

@MainActor
final class TVPhotoSmartAlbumListViewModel: ObservableObject {
    @Published private(set) var items: [TVPhotoSmartAlbumItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortBy: String = "create_time"
    @Published var sortOrder: String = "desc"

    private var page: Int = 1
    private var hasNextPage: Bool = true
    private let storageKeyPrefix: String

    init(storageKeyPrefix: String = "tv_photo_smart_album_sort") {
        self.storageKeyPrefix = storageKeyPrefix
        let defaults = UserDefaults.standard
        if let by = defaults.string(forKey: "\(storageKeyPrefix)_by") { sortBy = by }
        if let order = defaults.string(forKey: "\(storageKeyPrefix)_order") { sortOrder = order }
    }

    var currentSortLabel: String {
        if let opt = photoAlbumSortOptions.first(where: { $0.sortBy == sortBy && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.photoTimelineSortTitle
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

        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoSmartAlbumService.loadPage(
            page: page,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
            return
        }

        items = data.items
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: TVPhotoSmartAlbumItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        errorMessage = nil
        let nextPage = page + 1
        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoSmartAlbumService.loadPage(
            page: nextPage,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
    }

    func applySearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespaces)
        Task { await reload() }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { await reload() }
    }

    func applySort(by: String, order: String) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        UserDefaults.standard.set(by, forKey: "\(storageKeyPrefix)_by")
        UserDefaults.standard.set(order, forKey: "\(storageKeyPrefix)_order")
        Task { await reload() }
    }
}

@MainActor
final class TVPhotoCollectionListViewModel: ObservableObject {
    @Published private(set) var items: [TVPhotoCollectionItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortBy: String = "create_time"
    @Published var sortOrder: String = "desc"

    private var page: Int = 1
    private var hasNextPage: Bool = true
    private let storageKeyPrefix: String

    init(storageKeyPrefix: String = "tv_photo_collection_sort") {
        self.storageKeyPrefix = storageKeyPrefix
        let defaults = UserDefaults.standard
        if let by = defaults.string(forKey: "\(storageKeyPrefix)_by") { sortBy = by }
        if let order = defaults.string(forKey: "\(storageKeyPrefix)_order") { sortOrder = order }
    }

    var currentSortLabel: String {
        if let opt = photoAlbumSortOptions.first(where: { $0.sortBy == sortBy && $0.sortOrder == sortOrder }) {
            return L10n.tr(opt.labelKey)
        }
        return L10n.photoTimelineSortTitle
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

        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoCollectionService.loadPage(
            page: page,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
            return
        }

        items = data.items
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: TVPhotoCollectionItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        errorMessage = nil
        let nextPage = page + 1
        let keyword = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let response = await TVPhotoCollectionService.loadPage(
            page: nextPage,
            pageSize: 30,
            keyword: keyword,
            sortBy: sortBy,
            sortOrder: sortOrder
        )

        guard response.success, let data = response.data else {
            isLoading = false
            return
        }

        page = nextPage
        items.append(contentsOf: data.items)
        hasNextPage = data.pagination.page * data.pagination.pageSize < data.pagination.total
        isLoading = false
    }

    func applySearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespaces)
        Task { await reload() }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { await reload() }
    }

    func applySort(by: String, order: String) {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        UserDefaults.standard.set(by, forKey: "\(storageKeyPrefix)_by")
        UserDefaults.standard.set(order, forKey: "\(storageKeyPrefix)_order")
        Task { await reload() }
    }
}
