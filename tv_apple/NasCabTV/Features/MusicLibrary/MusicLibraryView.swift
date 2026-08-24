import SwiftUI

// MARK: - Music Library Tabs

private enum MusicLibraryTab: CaseIterable, Identifiable {
    case songs
    case favorites
    case albums
    case artists
    case playlists
    case collections

    var id: String { title }

    var title: String {
        switch self {
        case .songs: return L10n.musicTabSongs
        case .favorites: return L10n.videoTabFavorite
        case .albums: return L10n.musicTabAlbums
        case .artists: return L10n.musicTabArtists
        case .playlists: return L10n.musicTabPlaylists
        case .collections: return L10n.musicTabCollections
        }
    }
}

// MARK: - Main Music Library View

struct MusicLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerService = MusicPlayerService.shared
    @State private var selectedTab: MusicLibraryTab = .songs
    @State private var activeDetailContext: MusicDetailContext?
    @State private var showPlayerSheet = false

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
            .navigationTitle(L10n.homeMusicLibrary)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $activeDetailContext) { ctx in
                MusicDetailView(context: ctx, onPlayTrack: { item, queue, startIndex in
                    playerService.play(item: item, queue: queue, startIndex: startIndex)
                    activeDetailContext = nil
                    showPlayerSheet = true
                })
            }
            .fullScreenCover(isPresented: $showPlayerSheet) {
                MusicPlayerSheetView()
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

            Text(L10n.homeMusicLibrary)
                .font(.title)
                .fontWeight(.bold)

            Spacer()

            if playerService.isPlaying {
                Button {
                    showPlayerSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.headline)
                        Text(L10n.musicNowPlaying)
                            .font(.subheadline)
                        MusicPlayingIndicator()
                            .frame(width: 24, height: 16)
                            .padding(.horizontal, 10)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(NCPlainFocusButtonStyle())
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(MusicLibraryTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.title)
                                .font(.headline)
                                .foregroundStyle(tab == selectedTab ? Color.white : Color.secondary)
                            Rectangle()
                                .fill(tab == selectedTab ? Color.pink : Color.clear)
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
        case .songs:
            MusicSongsSection(
                onSelectPlayable: { item, queue in
                    let playable = queue.filter { !$0.isSeries }
                    guard let start = playable.firstIndex(where: { $0.id == item.id }) else {
                        playerService.play(item: item)
                        showPlayerSheet = true
                        return
                    }
                    playerService.play(item: playable[start], queue: playable, startIndex: start)
                    showPlayerSheet = true
                },
                onSelectSeries: { item in
                    activeDetailContext = MusicDetailContext(
                        keyType: "series",
                        name: item.displayTitle,
                        firstFilePath: item.firstFilePath,
                        listId: nil,
                        seriesIndexId: item.id,
                        collectionId: nil
                    )
                }
            )
        case .favorites:
            MusicSongsSection(
                isFavorite: true,
                onSelectPlayable: { item, queue in
                    let playable = queue.filter { !$0.isSeries }
                    guard let start = playable.firstIndex(where: { $0.id == item.id }) else {
                        playerService.play(item: item)
                        showPlayerSheet = true
                        return
                    }
                    playerService.play(item: playable[start], queue: playable, startIndex: start)
                    showPlayerSheet = true
                },
                onSelectSeries: { item in
                    activeDetailContext = MusicDetailContext(
                        keyType: "series",
                        name: item.displayTitle,
                        firstFilePath: item.firstFilePath,
                        listId: nil,
                        seriesIndexId: item.id,
                        collectionId: nil
                    )
                }
            )
        case .albums:
            MusicAlbumArtistGridSection(
                keyType: "album",
                onSelect: { item in
                    activeDetailContext = MusicDetailContext(
                        keyType: "album",
                        name: item.name,
                        firstFilePath: item.firstFilePath,
                        listId: nil,
                        seriesIndexId: nil,
                        collectionId: nil
                    )
                }
            )
        case .artists:
            MusicAlbumArtistGridSection(
                keyType: "artist",
                onSelect: { item in
                    activeDetailContext = MusicDetailContext(
                        keyType: "artist",
                        name: item.name,
                        firstFilePath: item.firstFilePath,
                        listId: nil,
                        seriesIndexId: nil,
                        collectionId: nil
                    )
                }
            )
        case .playlists:
            MusicPlaylistGridSection(onSelect: { item in
                activeDetailContext = MusicDetailContext(
                    keyType: "playlist",
                    name: item.name,
                    firstFilePath: "",
                    listId: item.id,
                    seriesIndexId: nil,
                    collectionId: nil
                )
            })
        case .collections:
            MusicCollectionGridSection(onSelect: { item in
                activeDetailContext = MusicDetailContext(
                    keyType: "collection",
                    name: item.name,
                    firstFilePath: "",
                    listId: nil,
                    seriesIndexId: nil,
                    collectionId: item.id
                )
            })
        }
    }
}

// MARK: - Detail Context (for navigation)

struct MusicDetailContext: Identifiable {
    let id = UUID()
    let keyType: String
    let name: String
    let firstFilePath: String
    let listId: Int?
    let seriesIndexId: Int?
    let collectionId: Int?
}
