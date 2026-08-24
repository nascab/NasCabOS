import SwiftUI

// MARK: - Photo Library Tabs

private enum TVPhotoLibraryTab: CaseIterable, Identifiable {
    case timeline
    case year
    case today
    case favorites
    case customAlbum
    case smartAlbum
    case collection

    var id: String { title }

    var title: String {
        switch self {
        case .timeline: return L10n.photoTimelineTabTimeline
        case .year: return L10n.photoTimelineTabYear
        case .today: return L10n.photoTimelineTabToday
        case .favorites: return L10n.videoTabFavorite
        case .customAlbum: return L10n.photoTabAlbum
        case .smartAlbum: return L10n.photoTabSmartAlbum
        case .collection: return L10n.photoTabCollection
        }
    }
}

// MARK: - Main View

struct PhotoLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: TVPhotoLibraryTab = .timeline

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
            .navigationTitle(L10n.homePhotoManagement)
            .toolbar(.hidden, for: .navigationBar)
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

            Text(L10n.homePhotoManagement)
                .font(.title)
                .fontWeight(.bold)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(TVPhotoLibraryTab.allCases) { tab in
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
        case .timeline:
            TVPhotoTimelineSection()
        case .year:
            TVPhotoYearSection()
        case .today:
            TVPhotoTodaySection()
        case .favorites:
            TVPhotoTimelineSection(listType: "favorite")
        case .customAlbum:
            TVPhotoAlbumGridSection(mode: .album)
        case .smartAlbum:
            TVPhotoAlbumGridSection(mode: .smartAlbum)
        case .collection:
            TVPhotoAlbumGridSection(mode: .collection)
        }
    }
}

// MARK: - Timeline Section (Main Grid with Date Grouping)

private struct TVPhotoDetailContext: Identifiable {
    let id = UUID()
    let photos: [TVPhotoTimelinePhotoItem]
    let initialIndex: Int
}

private struct TVPhotoTimelineSection: View {
    @StateObject private var viewModel: TVPhotoTimelineViewModel
    @FocusState private var filterAreaFocused: Bool
    @State private var isShowingSortSheet = false
    @State private var isShowingSourceSheet = false
    @State private var isShowingFileTypeSheet = false
    @State private var isShowingMonthSheet = false
    init(listType: String? = nil) {
        _viewModel = StateObject(wrappedValue: TVPhotoTimelineViewModel(listType: listType))
    }

    @State private var detailContext: TVPhotoDetailContext?

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let desiredWidth: CGFloat = maxWidth < 1000 ? 180 : 220
            let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 48
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                TVPhotoFilterBar(
                    viewModel: viewModel,
                    filterAreaFocused: $filterAreaFocused,
                    onShowSort: { isShowingSortSheet = true },
                    onShowSource: { isShowingSourceSheet = true },
                    onShowFileType: { isShowingFileTypeSheet = true },
                    onShowMonth: { isShowingMonthSheet = true }
                )
                .padding(.horizontal, 40)
                .padding(.top, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(viewModel.groupedSections) { section in
                            VStack(alignment: .leading, spacing: 20) {
                                Text(section.dateLabel)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                                    ForEach(Array(section.photos.enumerated()), id: \.element.id) { offset, photo in
                                        TVPhotoThumbCard(photo: photo) {
                                            let allPhotos = viewModel.groupedSections.flatMap { $0.photos }
                                            if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                                                detailContext = TVPhotoDetailContext(photos: allPhotos, initialIndex: idx)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
                    .padding(.bottom, 128)
                }
                .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .focusSection()
            .overlay(alignment: .center) {
                if viewModel.isLoading && !viewModel.isInitialLoaded {
                    ProgressView()
                        .scaleEffect(1.4)
                } else if viewModel.groupedSections.isEmpty && viewModel.isInitialLoaded {
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
            TVPhotoSortSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $isShowingSourceSheet) {
            TVPhotoSourceSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $isShowingFileTypeSheet) {
            TVPhotoFileTypeSheet(viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $isShowingMonthSheet) {
            TVPhotoMonthSheet(viewModel: viewModel)
        }
        .fullScreenCover(item: $detailContext) { ctx in
            TVPhotoDetailView(photos: ctx.photos, initialIndex: ctx.initialIndex)
        }
    }
}

// MARK: - Year Section

private struct TVPhotoYearSection: View {
    @StateObject private var viewModel = TVPhotoYearViewModel()
    @State private var selectedYearContext: TVPhotoYearContext?

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let desiredWidth: CGFloat = 280
            let columnsCount = max(2, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 48
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.photoTimelineYearsTitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 48)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(viewModel.items) { item in
                            TVPhotoYearCard(item: item) {
                                selectedYearContext = TVPhotoYearContext(year: item.year)
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
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
        .fullScreenCover(item: $selectedYearContext) { ctx in
            TVPhotoYearDetailView(year: ctx.year)
        }
    }
}

private struct TVPhotoYearContext: Identifiable {
    let id: Int
    let year: Int
    init(year: Int) {
        self.year = year
        self.id = year
    }
}

// MARK: - Today Section

private struct TVPhotoTodaySection: View {
    @StateObject private var viewModel = TVPhotoTodayViewModel()
    @State private var detailContext: TVPhotoDetailContext?

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let desiredWidth: CGFloat = maxWidth < 1000 ? 180 : 220
            let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 48
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 24) {
                TVPhotoTodayFilterBar(viewModel: viewModel)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        ForEach(Array(viewModel.photos.enumerated()), id: \.element.id) { offset, photo in
                            TVPhotoThumbCard(photo: photo) {
                                let allPhotos = viewModel.photos
                                if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                                    detailContext = TVPhotoDetailContext(photos: allPhotos, initialIndex: idx)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 24)
                    .padding(.bottom, 128)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .center) {
                if viewModel.isLoading && !viewModel.isInitialLoaded {
                    ProgressView()
                        .scaleEffect(1.4)
                } else if viewModel.photos.isEmpty && viewModel.isInitialLoaded {
                    Text(viewModel.errorMessage ?? L10n.noData)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                await viewModel.loadInitialIfNeeded()
            }
        }
        .fullScreenCover(item: $detailContext) { ctx in
            TVPhotoDetailView(photos: ctx.photos, initialIndex: ctx.initialIndex)
        }
    }
}

// MARK: - Photo Album Timeline Context (for navigation)

private struct TVPhotoAlbumTimelineContext: Identifiable {
    let id = UUID()
    let title: String
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?
    let typeLabel: String
}

// MARK: - Photo Album Section Mode

private enum TVPhotoAlbumSectionMode {
    case album
    case smartAlbum
    case collection

    var storageKeyPrefix: String {
        switch self {
        case .album: return "tv_photo_album_sort"
        case .smartAlbum: return "tv_photo_smart_album_sort"
        case .collection: return "tv_photo_collection_sort"
        }
    }

    var typeLabel: String {
        switch self {
        case .album: return L10n.photoTabAlbum
        case .smartAlbum: return L10n.photoTabSmartAlbum
        case .collection: return L10n.photoTabCollection
        }
    }
}

// MARK: - Photo Album Grid Section

private struct TVPhotoAlbumGridSection: View {
    let mode: TVPhotoAlbumSectionMode

    @StateObject private var albumViewModel = TVPhotoAlbumListViewModel(storageKeyPrefix: "tv_photo_album_sort")
    @StateObject private var smartViewModel = TVPhotoSmartAlbumListViewModel(storageKeyPrefix: "tv_photo_smart_album_sort")
    @StateObject private var collectionViewModel = TVPhotoCollectionListViewModel(storageKeyPrefix: "tv_photo_collection_sort")
    @State private var isShowingSortSheet = false
    @State private var activeTimelineContext: TVPhotoAlbumTimelineContext?

    var body: some View {
        GeometryReader { proxy in
            let maxWidth = proxy.size.width
            let baseDesiredWidth: CGFloat = maxWidth < 1000 ? 216 : 252
            let desiredWidth: CGFloat = baseDesiredWidth * 2
            let columnsCount = max(2, Int((maxWidth / desiredWidth).rounded(.down)))
            let spacing: CGFloat = 64
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            VStack(alignment: .leading, spacing: 32) {
                TVPhotoAlbumFilterBarWrapper(
                mode: mode,
                albumVM: albumViewModel,
                smartVM: smartViewModel,
                collectionVM: collectionViewModel,
                onShowSort: { isShowingSortSheet = true }
            )
                    .padding(.horizontal, 40)
                    .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                        switch mode {
                        case .album:
                            ForEach(albumViewModel.items) { item in
                                TVPhotoAlbumCard(
                                    title: item.name,
                                    previewPaths: item.previews.map(\.fullPath)
                                ) {
                                    activeTimelineContext = TVPhotoAlbumTimelineContext(
                                        title: item.name,
                                        albumId: item.id,
                                        collectionId: nil,
                                        smartAlbumId: nil,
                                        typeLabel: mode.typeLabel
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task { await albumViewModel.loadMoreIfNeeded(current: item) }
                                }
                            }
                        case .smartAlbum:
                            ForEach(smartViewModel.items) { item in
                                TVPhotoAlbumCard(
                                    title: item.name,
                                    previewPaths: item.previews.map(\.fullPath)
                                ) {
                                    activeTimelineContext = TVPhotoAlbumTimelineContext(
                                        title: item.name,
                                        albumId: nil,
                                        collectionId: nil,
                                        smartAlbumId: item.id,
                                        typeLabel: mode.typeLabel
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task { await smartViewModel.loadMoreIfNeeded(current: item) }
                                }
                            }
                        case .collection:
                            ForEach(collectionViewModel.items) { item in
                                TVPhotoAlbumCard(
                                    title: item.name,
                                    previewPaths: item.previews.map(\.fullPath)
                                ) {
                                    activeTimelineContext = TVPhotoAlbumTimelineContext(
                                        title: item.name,
                                        albumId: nil,
                                        collectionId: item.id,
                                        smartAlbumId: nil,
                                        typeLabel: mode.typeLabel
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    Task { await collectionViewModel.loadMoreIfNeeded(current: item) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 32)
                    .padding(.bottom, 128)
                }
                .focusSection()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .center) {
                switch mode {
                case .album:
                    if albumViewModel.isLoading && !albumViewModel.isInitialLoaded {
                        ProgressView().scaleEffect(1.4)
                    } else if albumViewModel.items.isEmpty && albumViewModel.isInitialLoaded {
                        Text(albumViewModel.errorMessage ?? L10n.noData)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                case .smartAlbum:
                    if smartViewModel.isLoading && !smartViewModel.isInitialLoaded {
                        ProgressView().scaleEffect(1.4)
                    } else if smartViewModel.items.isEmpty && smartViewModel.isInitialLoaded {
                        Text(smartViewModel.errorMessage ?? L10n.noData)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                case .collection:
                    if collectionViewModel.isLoading && !collectionViewModel.isInitialLoaded {
                        ProgressView().scaleEffect(1.4)
                    } else if collectionViewModel.items.isEmpty && collectionViewModel.isInitialLoaded {
                        Text(collectionViewModel.errorMessage ?? L10n.noData)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                switch mode {
                case .album: await albumViewModel.loadInitialIfNeeded()
                case .smartAlbum: await smartViewModel.loadInitialIfNeeded()
                case .collection: await collectionViewModel.loadInitialIfNeeded()
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingSortSheet) {
            TVPhotoAlbumSortSheetWrapper(
                mode: mode,
                albumVM: albumViewModel,
                smartVM: smartViewModel,
                collectionVM: collectionViewModel
            )
        }
        .fullScreenCover(item: $activeTimelineContext) { ctx in
            TVPhotoAlbumTimelineView(
                title: ctx.title,
                albumId: ctx.albumId,
                collectionId: ctx.collectionId,
                smartAlbumId: ctx.smartAlbumId,
                typeLabel: ctx.typeLabel
            )
        }
    }
}

// MARK: - Photo Album Filter Bar

private struct TVPhotoAlbumFilterBarWrapper: View {
    let mode: TVPhotoAlbumSectionMode
    @ObservedObject var albumVM: TVPhotoAlbumListViewModel
    @ObservedObject var smartVM: TVPhotoSmartAlbumListViewModel
    @ObservedObject var collectionVM: TVPhotoCollectionListViewModel
    let onShowSort: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Group {
                switch mode {
                case .album:
                    TVPhotoAlbumSearchBarContent(viewModel: albumVM)
                case .smartAlbum:
                    TVPhotoAlbumSearchBarContentForSmart(viewModel: smartVM)
                case .collection:
                    TVPhotoAlbumSearchBarContentForCollection(viewModel: collectionVM)
                }
            }
            .frame(maxWidth: 520)

            Spacer()

            Button(action: onShowSort) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline)
                    Text(currentSortLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
    }

    private var currentSortLabel: String {
        switch mode {
        case .album: return albumVM.currentSortLabel
        case .smartAlbum: return smartVM.currentSortLabel
        case .collection: return collectionVM.currentSortLabel
        }
    }
}

private struct TVPhotoAlbumSearchBarContent: View {
    @ObservedObject var viewModel: TVPhotoAlbumListViewModel

    var body: some View {
        NCSearchInput(
            placeholder: L10n.photoAlbumSearchHint,
            text: $viewModel.searchText,
            onSearch: { viewModel.applySearch(text: viewModel.searchText) }
        )
    }
}

private struct TVPhotoAlbumSearchBarContentForSmart: View {
    @ObservedObject var viewModel: TVPhotoSmartAlbumListViewModel

    var body: some View {
        NCSearchInput(
            placeholder: L10n.photoAlbumSearchHint,
            text: $viewModel.searchText,
            onSearch: { viewModel.applySearch(text: viewModel.searchText) }
        )
    }
}

private struct TVPhotoAlbumSearchBarContentForCollection: View {
    @ObservedObject var viewModel: TVPhotoCollectionListViewModel

    var body: some View {
        NCSearchInput(
            placeholder: L10n.photoAlbumSearchHint,
            text: $viewModel.searchText,
            onSearch: { viewModel.applySearch(text: viewModel.searchText) }
        )
    }
}

// MARK: - Photo Album Sort Sheet

private struct TVPhotoAlbumSortSheetWrapper: View {
    let mode: TVPhotoAlbumSectionMode
    @ObservedObject var albumVM: TVPhotoAlbumListViewModel
    @ObservedObject var smartVM: TVPhotoSmartAlbumListViewModel
    @ObservedObject var collectionVM: TVPhotoCollectionListViewModel
    @Environment(\.dismiss) private var dismiss

    private let options: [(sortBy: String, sortOrder: String, labelKey: String)] = [
        ("create_time", "desc", "create_time_desc"),
        ("create_time", "asc", "create_time_asc"),
        ("name", "asc", "name_asc"),
        ("name", "desc", "name_desc"),
    ]

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.photoTimelineSortTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(options, id: \.labelKey) { opt in
                        NCModalOptionButton(
                            label: L10n.tr(opt.labelKey),
                            isSelected: isSelected(opt)
                        ) {
                            applySort(by: opt.sortBy, order: opt.sortOrder)
                            dismiss()
                        }
                    }
                }

                Spacer()
            }
        }
    }

    private func isSelected(_ opt: (sortBy: String, sortOrder: String, labelKey: String)) -> Bool {
        switch mode {
        case .album: return albumVM.sortBy == opt.sortBy && albumVM.sortOrder == opt.sortOrder
        case .smartAlbum: return smartVM.sortBy == opt.sortBy && smartVM.sortOrder == opt.sortOrder
        case .collection: return collectionVM.sortBy == opt.sortBy && collectionVM.sortOrder == opt.sortOrder
        }
    }

    private func applySort(by: String, order: String) {
        switch mode {
        case .album: albumVM.applySort(by: by, order: order)
        case .smartAlbum: smartVM.applySort(by: by, order: order)
        case .collection: collectionVM.applySort(by: by, order: order)
        }
    }
}

// MARK: - Photo Album Card (with preview)

private struct TVPhotoAlbumCard: View {
    let title: String
    let previewPaths: [String]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { albumPreviewContent() }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(title)
                    .font(.system(size: 26))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.12))
    }

    @ViewBuilder
    private func albumPreviewContent() -> some View {
        let paths = previewPaths.filter { !$0.isEmpty }
        if paths.isEmpty {
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "photo.fill")
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
                let itemWidth = count > 0 ? (totalWidth - spacing * (count - 1)) / count : totalWidth

                HStack(spacing: spacing) {
                    ForEach(Array(displayPaths.enumerated()), id: \.offset) { _, path in
                        if let url = TVVideoImageUtils.tinyArtworkURL(forPath: path) {
                            NCRemoteImage(url: url, contentMode: .fill)
                                .frame(width: itemWidth, height: totalHeight)
                                .clipped()
                        }
                    }
                }
                .frame(width: totalWidth, height: totalHeight, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - Photo Album Timeline View (full screen, with album filter)

struct TVPhotoAlbumTimelineView: View {
    let title: String
    let albumId: Int?
    let collectionId: Int?
    let smartAlbumId: Int?
    let typeLabel: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TVPhotoTimelineViewModel
    @State private var detailContext: TVPhotoDetailContext?
    @FocusState private var filterAreaFocused: Bool
    @State private var isShowingSortSheet = false
    @State private var isShowingSourceSheet = false
    @State private var isShowingFileTypeSheet = false
    @State private var isShowingMonthSheet = false

    init(
        title: String,
        albumId: Int?,
        collectionId: Int?,
        smartAlbumId: Int?,
        typeLabel: String
    ) {
        self.title = title
        self.albumId = albumId
        self.collectionId = collectionId
        self.smartAlbumId = smartAlbumId
        self.typeLabel = typeLabel
        _viewModel = StateObject(wrappedValue: TVPhotoTimelineViewModel(
            albumId: albumId,
            collectionId: collectionId,
            smartAlbumId: smartAlbumId
        ))
    }

    private var navTitle: String {
        "\(title) · \(typeLabel)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [Color.black, Color(.systemIndigo).opacity(0.16), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                GeometryReader { proxy in
                    let maxWidth = proxy.size.width
                    let desiredWidth: CGFloat = maxWidth < 1000 ? 180 : 220
                    let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
                    let spacing: CGFloat = 48
                    let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.backward")
                                    .font(.title2)
                            }
                            .buttonStyle(NCPlainFocusButtonStyle())
                            Spacer()
                            Text(navTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 64)

                        TVPhotoFilterBar(
                            viewModel: viewModel,
                            filterAreaFocused: $filterAreaFocused,
                            onShowSort: { isShowingSortSheet = true },
                            onShowSource: { isShowingSourceSheet = true },
                            onShowFileType: { isShowingFileTypeSheet = true },
                            onShowMonth: { isShowingMonthSheet = true }
                        )
                        .padding(.horizontal, 40)
                        .padding(.top, 8)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 32) {
                                ForEach(viewModel.groupedSections) { section in
                                    VStack(alignment: .leading, spacing: 20) {
                                        Text(section.dateLabel)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)

                                        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                                            ForEach(Array(section.photos.enumerated()), id: \.element.id) { _, photo in
                                                TVPhotoThumbCard(photo: photo) {
                                                    let allPhotos = viewModel.groupedSections.flatMap { $0.photos }
                                                    if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                                                        detailContext = TVPhotoDetailContext(photos: allPhotos, initialIndex: idx)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.top, 24)
                            .padding(.bottom, 128)
                        }
                    }
                    .overlay(alignment: .center) {
                        if viewModel.isLoading && !viewModel.isInitialLoaded {
                            ProgressView().scaleEffect(1.4)
                        } else if viewModel.groupedSections.isEmpty && viewModel.isInitialLoaded {
                            Text(viewModel.errorMessage ?? L10n.noData)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(navTitle)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $detailContext) { ctx in
                TVPhotoDetailView(photos: ctx.photos, initialIndex: ctx.initialIndex)
            }
            .fullScreenCover(isPresented: $isShowingSortSheet) {
                TVPhotoSortSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $isShowingSourceSheet) {
                TVPhotoSourceSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $isShowingFileTypeSheet) {
                TVPhotoFileTypeSheet(viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $isShowingMonthSheet) {
                TVPhotoMonthSheet(viewModel: viewModel)
            }
            .task {
                await viewModel.loadInitialIfNeeded()
            }
        }
    }
}

// MARK: - Today Filter Bar (Search + Sort only)

private struct TVPhotoTodayFilterBar: View {
    @ObservedObject var viewModel: TVPhotoTodayViewModel

    var body: some View {
        HStack(spacing: 24) {
            NCSearchInput(
                placeholder: L10n.photoTimelineSearchHint,
                text: $viewModel.searchText,
                onSearch: { viewModel.applySearch(text: viewModel.searchText) }
            )
            .frame(maxWidth: 520)

            Spacer()

            Button(action: { viewModel.toggleSortOrder() }) {
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

// MARK: - Filter Bar

private struct TVPhotoFilterBar: View {
    @ObservedObject var viewModel: TVPhotoTimelineViewModel
    @FocusState.Binding var filterAreaFocused: Bool
    let onShowSort: () -> Void
    let onShowSource: () -> Void
    let onShowFileType: () -> Void
    let onShowMonth: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            NCSearchInput(
                placeholder: L10n.photoTimelineSearchHint,
                text: $viewModel.searchText,
                onSearch: { viewModel.applySearch(text: viewModel.searchText) },
                isFocused: $filterAreaFocused
            )
            .frame(maxWidth: 520)

            Spacer()

            Button(action: onShowSort) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline)
                    Text(viewModel.currentSortLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(viewModel.sortOrder == "desc" ? .primary : .secondary)
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Button(action: onShowFileType) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.fileType != "all" ? "photo.fill" : "photo")
                        .font(.subheadline)
                    Text(viewModel.fileTypeLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                    if viewModel.fileType != "all" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Button(action: onShowSource) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.subheadline)
                    Text(L10n.photoTimelineFilterSource)
                        .font(.subheadline)
                    if viewModel.sourceFilterCount > 0 {
                        Text("\(viewModel.sourceFilterCount)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                    }
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())

            Button(action: onShowMonth) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.selectedMonth != nil ? "calendar.badge.checkmark" : "calendar")
                        .font(.subheadline)
                    Text(viewModel.monthFilterLabel)
                        .font(.subheadline)
                        .lineLimit(1)
                    if viewModel.selectedMonth != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
    }
}


// MARK: - Sort Sheet

private struct TVPhotoSortSheet: View {
    @ObservedObject var viewModel: TVPhotoTimelineViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.photoTimelineSortTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    NCModalOptionButton(
                        label: viewModel.isFavoriteList ? L10n.videoSortFavoriteTimeDesc : L10n.photoTimelineSortDesc,
                        isSelected: viewModel.sortOrder == "desc"
                    ) { viewModel.applySortOrder("desc") }
                    NCModalOptionButton(
                        label: viewModel.isFavoriteList ? L10n.videoSortFavoriteTimeAsc : L10n.photoTimelineSortAsc,
                        isSelected: viewModel.sortOrder == "asc"
                    ) { viewModel.applySortOrder("asc") }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Source Sheet

private struct TVPhotoSourceSheet: View {
    @ObservedObject var viewModel: TVPhotoTimelineViewModel

    var body: some View {
        NCModalPanelContainer(maxWidth: 1100, maxHeight: 720) {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.photoTimelineFilterSource)
                    .font(.title2)
                    .fontWeight(.bold)

                if viewModel.availablePaths.isEmpty {
                    Text(L10n.noData)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        Button {
                            viewModel.resetSourceFilter()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: viewModel.selectedPaths.isEmpty ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.selectedPaths.isEmpty ? Color.accentColor : .secondary)
                                Text(L10n.photoTimelineAllSource)
                                    .font(.body)
                            }
                        }
                        .buttonStyle(NCPlainFocusButtonStyle())
                        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))

                        ForEach(viewModel.availablePaths) { item in
                            let isSelected = viewModel.selectedPaths.contains(item.path)
                            Button {
                                viewModel.toggleSource(path: item.path)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.path)
                                            .font(.body)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if !item.valid {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(Color.red.opacity(0.8))
                                        }
                                    }
                                }
                            }
                            .buttonStyle(NCPlainFocusButtonStyle())
                            .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        }
                    }
                    .listStyle(.plain)
                    .clipped()
                }

                Spacer()
            }
            .focusSection()
        }
    }
}

// MARK: - File Type Sheet

private struct TVPhotoFileTypeSheet: View {
    @ObservedObject var viewModel: TVPhotoTimelineViewModel

    private let options: [(value: String, label: String)] = [
        ("all", "all"),
        ("photo", "timeline_photos"),
        ("video", "timeline_videos"),
        ("livephoto", "timeline_live_photos"),
    ]

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 600) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.photoTimelineFilterFileType)
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(options, id: \.value) { opt in
                        NCModalOptionButton(
                            label: L10n.tr(opt.label),
                            isSelected: viewModel.fileType == opt.value
                        ) {
                            viewModel.applyFileType(opt.value)
                        }
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Month Sheet

private struct TVPhotoMonthSheet: View {
    @ObservedObject var viewModel: TVPhotoTimelineViewModel
    @State private var frozenMonths: [String] = []

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 720) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.photoTimelineFilterMonth)
                    .font(.title2)
                    .fontWeight(.bold)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        NCModalOptionButton(
                            label: L10n.photoTimelineAllTime,
                            isSelected: viewModel.selectedMonth == nil
                        ) {
                            viewModel.clearMonthFilter()
                        }

                        ForEach(frozenMonths, id: \.self) { monthKey in
                            let isSelected = viewModel.selectedMonth == monthKey
                            NCModalOptionButton(
                                label: viewModel.monthDisplayLabel(for: monthKey),
                                isSelected: isSelected
                            ) {
                                viewModel.applyMonthFilter(monthKey)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .clipped()
                .focusSection()

                Spacer()
            }
            .onAppear {
                frozenMonths = viewModel.availableMonths
            }
        }
    }
}

// MARK: - Photo Thumb Card

private struct TVPhotoThumbCard: View {
    let photo: TVPhotoTimelinePhotoItem
    let onSelect: () -> Void

    init(photo: TVPhotoTimelinePhotoItem, onSelect: @escaping () -> Void = {}) {
        self.photo = photo
        self.onSelect = onSelect
    }

    private var thumbURL: URL? {
        let path = photo.fullpath.isEmpty ? photo.path : photo.fullpath
        return TVVideoImageUtils.tinyArtworkURL(forPath: path)
    }

    private var durationText: String {
        let s = photo.duration
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.04))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        NCRemoteImage(url: thumbURL, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if photo.isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .shadow(radius: 2)
                                Text(durationText)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(6)
                        }
                    }
                }
                if photo.isLivePhoto {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "livephoto")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 16, focusScale: 1.08))
    }
}

// MARK: - Year Card

private struct TVPhotoYearCard: View {
    let item: TVPhotoTimelineYearItem
    let onTap: () -> Void
    @Environment(\.isFocused) private var isFocused

    private var thumbURL: URL? {
        guard let cover = item.cover else { return nil }
        let path = cover.fullpath.isEmpty ? cover.path : cover.fullpath
        return TVVideoImageUtils.tinyArtworkURL(forPath: path)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.04))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            if let url = thumbURL {
                                NCRemoteImage(url: url, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            } else {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                Text(L10n.tr("photo_timeline_year_title", params: ["year": "\(item.year)"]))
                    .font(.system(size: 28))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(L10n.photoTimelinePhotosCount(item.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
        .buttonStyle(NCCardButtonStyle(cornerRadius: 18, focusScale: 1.12))
    }
}

// MARK: - Photo Detail View (大图预览)

struct TVPhotoDetailView: View {
    let photos: [TVPhotoTimelinePhotoItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showVideoPlayer = false
    @State private var isAutoPlaying = false
    @State private var toastMessage: String?
    @FocusState private var isBaseFocused: Bool

    init(photos: [TVPhotoTimelinePhotoItem], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = min(max(0, initialIndex), max(0, photos.count - 1))
        _currentIndex = State(initialValue: min(max(0, initialIndex), max(0, photos.count - 1)))
    }

    private var currentPhoto: TVPhotoTimelinePhotoItem? {
        guard currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    private func imageURL(for photo: TVPhotoTimelinePhotoItem) -> URL? {
        let path = photo.fullpath.isEmpty ? photo.path : photo.fullpath
        if photo.isVideo {
            return TVVideoImageUtils.tinyArtworkURL(forPath: path, size: 640)
        }
        return TVVideoImageUtils.rawFileURL(forPath: path, size: 4000)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if let photo = currentPhoto {
                    if photo.isVideo {
                        ZStack {
                            if let url = imageURL(for: photo) {
                                NCRemoteImage(url: url, contentMode: .fit)
                                    .id(photo.id)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                Color.white.opacity(0.08)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            Button {
                                showVideoPlayer = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 140, height: 140)
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 100))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                            }
                            .buttonStyle(NCPlainFocusButtonStyle())
                        }
                    } else if let url = imageURL(for: photo) {
                        NCRemoteImage(url: url, contentMode: .fit)
                            .id(photo.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                }
            }
            .focusSection()

            if !isAutoPlaying {
                VStack(spacing: 0) {
                    Spacer()
                    if let photo = currentPhoto {
                        Text(photo.filename)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 48)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.5))
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }

            if let message = toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.95)))
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: toastMessage)
            }
        }
        .onChange(of: toastMessage) { newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    toastMessage = nil
                }
            }
        }
        .background(
            Group {
                if isAutoPlaying {
                    Color.clear
                        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
                            if photos.count > 1 {
                                currentIndex = (currentIndex + 1) % photos.count
                            }
                        }
                }
            }
        )
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let photo = currentPhoto {
                TVPhotoVideoPlayerView(photo: photo)
            }
        }
        .focusable(true)
        .focused($isBaseFocused)
        .onAppear { isBaseFocused = true }
        .onMoveCommand { direction in
            guard photos.count > 1 else { return }
            switch direction {
            case .left:
                currentIndex = (currentIndex - 1 + photos.count) % photos.count
            case .right:
                currentIndex = (currentIndex + 1) % photos.count
            default:
                break
            }
        }
        .onPlayPauseCommand {
            if let photo = currentPhoto, photo.isVideo {
                showVideoPlayer = true
                return
            }
            guard photos.count > 1 else { return }
            if isAutoPlaying {
                isAutoPlaying = false
                toastMessage = L10n.tr("photo_detail_auto_play_stop")
            } else {
                isAutoPlaying = true
                toastMessage = L10n.tr("photo_detail_auto_play_start")
            }
        }
        .onExitCommand {
            if isAutoPlaying {
                isAutoPlaying = false
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Photo Video Player (单视频播放)

private struct TVPhotoVideoPlayerView: View {
    let photo: TVPhotoTimelinePhotoItem
    @Environment(\.dismiss) private var dismiss

    private var playlist: [TVVideoPlaylistItem] {
        let path = photo.fullpath.isEmpty ? photo.path : photo.fullpath
        return [TVVideoPlaylistItem(path: path, name: photo.filename)]
    }

    var body: some View {
        TVVideoPlayerView(
            playlist: playlist,
            initialIndex: 0,
            ignorePlaybackHistory: true,
            ignoreFindSub: 1
        )
            .onAppear {
                MusicPlayerService.shared.stop()
            }
    }
}

// MARK: - Year Detail View

struct TVPhotoYearDetailView: View {
    let year: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TVPhotoTimelineViewModel
    @State private var detailContext: TVPhotoDetailContext?

    init(year: Int) {
        self.year = year
        _viewModel = StateObject(wrappedValue: TVPhotoTimelineViewModel(initialYear: year))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [Color.black, Color(.systemIndigo).opacity(0.16), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                GeometryReader { proxy in
                    let maxWidth = proxy.size.width
                    let desiredWidth: CGFloat = maxWidth < 1000 ? 180 : 220
                    let columnsCount = max(4, Int((maxWidth / desiredWidth).rounded(.down)))
                    let spacing: CGFloat = 48
                    let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.backward")
                                    .font(.title2)
                            }
                            .buttonStyle(NCPlainFocusButtonStyle())
                            Spacer()
                            Text(L10n.tr("photo_timeline_year_title", params: ["year": "\(year)"]))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 64)

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 32) {
                                ForEach(viewModel.groupedSections) { section in
                                    VStack(alignment: .leading, spacing: 20) {
                                        Text(section.dateLabel)
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)

                                        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                                            ForEach(Array(section.photos.enumerated()), id: \.element.id) { _, photo in
                                                TVPhotoThumbCard(photo: photo) {
                                                    let allPhotos = viewModel.groupedSections.flatMap { $0.photos }
                                                    if let idx = allPhotos.firstIndex(where: { $0.id == photo.id }) {
                                                        detailContext = TVPhotoDetailContext(photos: allPhotos, initialIndex: idx)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 64)
                            .padding(.vertical, 24)
                        }
                    }
                    .overlay(alignment: .center) {
                        if viewModel.isLoading && !viewModel.isInitialLoaded {
                            ProgressView()
                                .scaleEffect(1.4)
                        }
                    }
                }
            }
            .fullScreenCover(item: $detailContext) { ctx in
                TVPhotoDetailView(photos: ctx.photos, initialIndex: ctx.initialIndex)
            }
            .task {
                await viewModel.loadInitialIfNeeded()
            }
        }
    }
}
