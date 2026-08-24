import SwiftUI

// MARK: - Music Detail View (Album / Artist / Playlist / Collection song list)

@MainActor
final class MusicDetailViewModel: ObservableObject {
    @Published private(set) var items: [MusicItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var sortBy: String
    @Published var sortOrder: String

    private var page = 1
    private var hasNextPage = true
    private let context: MusicDetailContext

    init(context: MusicDetailContext) {
        self.context = context
        if context.collectionId != nil {
            sortBy = "mtime"
            sortOrder = "desc"
        } else {
            sortBy = "mtime"
            sortOrder = "asc"
        }
    }

    struct SortOption: Identifiable {
        let id = UUID()
        let sortBy: String
        let sortOrder: String
        let labelKey: String
    }

    var availableSortOptions: [SortOption] {
        [
            SortOption(sortBy: "mtime", sortOrder: "desc", labelKey: "music_list_sort_mtime_desc"),
            SortOption(sortBy: "mtime", sortOrder: "asc", labelKey: "music_list_sort_mtime_asc"),
            SortOption(sortBy: "title", sortOrder: "asc", labelKey: "music_list_sort_title_asc"),
            SortOption(sortBy: "title", sortOrder: "desc", labelKey: "music_list_sort_title_desc"),
            SortOption(sortBy: "year", sortOrder: "desc", labelKey: "music_list_sort_year_desc"),
            SortOption(sortBy: "year", sortOrder: "asc", labelKey: "music_list_sort_year_asc"),
            SortOption(sortBy: "duration", sortOrder: "desc", labelKey: "music_list_sort_duration_desc"),
            SortOption(sortBy: "duration", sortOrder: "asc", labelKey: "music_list_sort_duration_asc"),
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

    func reload() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasNextPage = true

        let response: APIResponse<MusicListResult>
        if let listId = context.listId, listId > 0 {
            response = await MusicService.listSongs(
                page: page,
                pageSize: 30,
                listType: "playlist",
                listId: listId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else if let seriesIndexId = context.seriesIndexId, seriesIndexId > 0 {
            response = await MusicService.listSongs(
                page: page,
                pageSize: 30,
                seriesIndexId: seriesIndexId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else if let collectionId = context.collectionId, collectionId > 0 {
            response = await MusicService.listSongs(
                page: page,
                pageSize: 30,
                collectionId: collectionId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else {
            let artists = context.keyType.lowercased() == "artist" ? [context.name] : nil
            let albums = context.keyType.lowercased() == "album" ? [context.name] : nil
            response = await MusicService.listSongs(
                page: page,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                artists: artists,
                albums: albums,
                sortBy: sortBy,
                sortOrder: sortOrder
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
        isLoading = false
        isInitialLoaded = true
    }

    func loadMoreIfNeeded(current item: MusicItem?) async {
        guard !isLoading, hasNextPage else { return }
        guard let item, let last = items.last, item.id == last.id else { return }

        isLoading = true
        let nextPage = page + 1

        let response: APIResponse<MusicListResult>
        if let listId = context.listId, listId > 0 {
            response = await MusicService.listSongs(
                page: nextPage,
                pageSize: 30,
                listType: "playlist",
                listId: listId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else if let seriesIndexId = context.seriesIndexId, seriesIndexId > 0 {
            response = await MusicService.listSongs(
                page: nextPage,
                pageSize: 30,
                seriesIndexId: seriesIndexId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else if let collectionId = context.collectionId, collectionId > 0 {
            response = await MusicService.listSongs(
                page: nextPage,
                pageSize: 30,
                collectionId: collectionId,
                search: searchText.isEmpty ? nil : searchText,
                sortBy: sortBy,
                sortOrder: sortOrder
            )
        } else {
            let artists = context.keyType.lowercased() == "artist" ? [context.name] : nil
            let albums = context.keyType.lowercased() == "album" ? [context.name] : nil
            response = await MusicService.listSongs(
                page: nextPage,
                pageSize: 30,
                search: searchText.isEmpty ? nil : searchText,
                artists: artists,
                albums: albums,
                sortBy: sortBy,
                sortOrder: sortOrder
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

    func applySearch() async {
        await reload()
    }

    func applySort(by: String, order: String) async {
        guard sortBy != by || sortOrder != order else { return }
        sortBy = by
        sortOrder = order
        await reload()
    }
}

struct MusicDetailView: View {
    let context: MusicDetailContext
    let onPlayTrack: (MusicItem, [MusicItem], Int) -> Void
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MusicDetailViewModel
    @State private var childContext: MusicDetailContext?
    @State private var isShowingSortSheet = false

    init(context: MusicDetailContext, onPlayTrack: @escaping (MusicItem, [MusicItem], Int) -> Void, onDismiss: (() -> Void)? = nil) {
        self.context = context
        self.onPlayTrack = onPlayTrack
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: MusicDetailViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.pink.opacity(0.12),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 24) {
                        MusicSearchBar(text: $viewModel.searchText, onSearch: { Task { await viewModel.applySearch() } })
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
                    .padding(.horizontal, 64)
                    .padding(.top, 16)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.items) { item in
                                MusicSongRow(
                                    item: item,
                                    onTap: {
                                        if item.isSeries {
                                            childContext = MusicDetailContext(
                                                keyType: "series",
                                                name: item.displayTitle,
                                                firstFilePath: item.firstFilePath,
                                                listId: nil,
                                                seriesIndexId: item.id,
                                                collectionId: nil
                                            )
                                        } else {
                                            let idx = viewModel.items.firstIndex(where: { $0.id == item.id }) ?? 0
                                            onPlayTrack(item, viewModel.items, idx)
                                        }
                                    }
                                )
                                .onAppear {
                                    Task { await viewModel.loadMoreIfNeeded(current: item) }
                                }
                            }
                        }
                        .padding(.horizontal, 64)
                        .padding(.top, 32)
                        .padding(.bottom, 128)
                    }
                }
            }
            .navigationTitle(context.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        if let d = onDismiss { d() } else { dismiss() }
                    }) {
                        Image(systemName: "chevron.backward")
                    }
                }
            }
            .fullScreenCover(item: $childContext) { ctx in
                MusicDetailView(context: ctx, onPlayTrack: { item, queue, idx in onPlayTrack(item, queue, idx) }, onDismiss: { childContext = nil })
            }
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
            .fullScreenCover(isPresented: $isShowingSortSheet) {
                MusicDetailSortSheet(viewModel: viewModel)
            }
        }
    }
}

private struct MusicDetailSortSheet: View {
    @ObservedObject var viewModel: MusicDetailViewModel

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
