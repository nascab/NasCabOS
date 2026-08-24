import Foundation

// MARK: - Music API Service

@MainActor
enum MusicService {
    private static let api = APIClient.shared
    /// 对应 Flutter `Uri.encodeComponent` 的行为：仅保留 RFC 3986 unreserved 字符
    private static let componentAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return set
    }()

    private static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? value
    }

    // MARK: - Cover URL

    static func coverURL(filePath: String, size: Int = 500) -> URL? {
        let base = api.baseUrl.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        let p = filePath.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return nil }
        let encodedPath = encodeComponent(p)
        let encodedSize = encodeComponent(String(size))
        var urlString = "\(trimmed)/api/music/cover?file_path=\(encodedPath)&size=\(encodedSize)"
        if api.isP2pMode {
            urlString += "&p2pChannel=file"
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
           !token.isEmpty {
            urlString += "&accessToken=\(encodeComponent(token))"
        }
        // 与 Flutter 行为保持一致，这里不额外打印日志，避免刷屏
        return URL(string: urlString)
    }

    // MARK: - Raw File URL (direct stream, for VLC local decode)

    static func rawFileURL(filePath: String) -> URL? {
        let api = APIClient.shared
        var base = api.baseUrl.trimmingCharacters(in: .whitespaces)
        if base.isEmpty {
            print("[MusicService][rawFileURL] baseUrl is empty, filePath=\(filePath)")
            return nil
        }
        if base.hasSuffix("/") { base.removeLast() }
        if api.isP2pMode {
            if let proxyBase = LocalPlaybackProxy.shared.baseURL {
                base = proxyBase.hasSuffix("/") ? String(proxyBase.dropLast()) : proxyBase
            } else {
                print("[MusicService][rawFileURL] P2P mode but LocalPlaybackProxy.baseURL is nil, use api.baseUrl=\(base)")
            }
        }
        let trimmed = filePath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            print("[MusicService][rawFileURL] filePath is empty after trim")
            return nil
        }
        let encodedPath = encodeComponent(trimmed)
        var urlString = "\(base)/api/file/rawFile?path=\(encodedPath)&raw=1"
        if api.isP2pMode {
            let channel = encodeComponent("file")
            urlString += "&p2pChannel=\(channel)"
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
           !token.isEmpty {
            urlString += "&accessToken=\(encodeComponent(token))"
        }
        print("[MusicService][rawFileURL] url=\(urlString)")
        return URL(string: urlString)
    }

    // MARK: - Transcode URL (for AVPlayer, server-side transcode to MP3)

    static func transcodeURL(filePath: String) -> URL? {
        let base = api.baseUrl.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else {
            print("[MusicService][transcodeURL] baseUrl is empty, filePath=\(filePath)")
            return nil
        }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        let p = filePath.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else {
            print("[MusicService][transcodeURL] filePath is empty after trim")
            return nil
        }
        let encodedPath = encodeComponent(p)
        var urlString = "\(trimmed)/api/music/transcode?path=\(encodedPath)"
        if api.isP2pMode {
            let channel = encodeComponent("music")
            urlString += "&p2pChannel=\(channel)"
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty,
           !token.isEmpty {
            urlString += "&accessToken=\(encodeComponent(token))"
        }
        print("[MusicService][transcodeURL] url=\(urlString)")
        return URL(string: urlString)
    }

    // MARK: - List (songs)

    static func listSongs(
        page: Int = 1,
        pageSize: Int = 30,
        listType: String = "",
        listId: Int? = nil,
        seriesIndexId: Int? = nil,
        collectionId: Int? = nil,
        isFavorite: Bool = false,
        isHistory: Bool = false,
        search: String? = nil,
        artists: [String]? = nil,
        albums: [String]? = nil,
        sourceList: [String]? = nil,
        sortBy: String = "mtime",
        sortOrder: String = "desc"
    ) async -> APIResponse<MusicListResult> {
        var body: [String: Any] = [
            "page": page,
            "page_size": pageSize,
            "sort_by": sortBy,
            "sort_order": sortOrder,
        ]
        if !listType.isEmpty { body["listType"] = listType }
        if let lid = listId, lid > 0 { body["list_id"] = lid }
        if let sid = seriesIndexId, sid > 0 { body["series_index_id"] = sid }
        if let cid = collectionId, cid > 0 { body["collection_id"] = cid }
        if isFavorite { body["is_favorite"] = 1 }
        if isHistory { body["isHistory"] = 1 }
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { body["search"] = s }
        if let a = artists, !a.isEmpty { body["artists"] = a }
        if let a = albums, !a.isEmpty { body["albums"] = a }
        if let s = sourceList, !s.isEmpty { body["sourceList"] = s }

        return await api.apiPost(
            "/api/music/list",
            body: body,
            dataParser: { data, _ in MusicListResult(json: data) }
        )
    }

    // MARK: - Album List

    static func listAlbums(
        page: Int = 1,
        pageSize: Int = 30,
        search: String? = nil,
        sortBy: String = "count",
        sortOrder: String = "desc",
        sourceList: [String]? = nil
    ) async -> APIResponse<AlbumArtistListResult> {
        var body: [String: Any] = [
            "page": page,
            "page_size": pageSize,
            "sort_by": sortBy,
            "sort_order": sortOrder,
        ]
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { body["search"] = s }
        if let s = sourceList, !s.isEmpty { body["sourceList"] = s }

        return await api.apiPost(
            "/api/music/album/list",
            body: body,
            dataParser: { data, _ in AlbumArtistListResult(json: data) }
        )
    }

    // MARK: - Artist List

    static func listArtists(
        page: Int = 1,
        pageSize: Int = 30,
        search: String? = nil,
        sortBy: String = "count",
        sortOrder: String = "desc",
        sourceList: [String]? = nil
    ) async -> APIResponse<AlbumArtistListResult> {
        var body: [String: Any] = [
            "page": page,
            "page_size": pageSize,
            "sort_by": sortBy,
            "sort_order": sortOrder,
        ]
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { body["search"] = s }
        if let s = sourceList, !s.isEmpty { body["sourceList"] = s }

        return await api.apiPost(
            "/api/music/artist/list",
            body: body,
            dataParser: { data, _ in AlbumArtistListResult(json: data) }
        )
    }

    // MARK: - Playlist List

    static func listPlaylists(
        page: Int = 1,
        pageSize: Int = 30,
        search: String? = nil,
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<PlaylistListResult> {
        var body: [String: Any] = [
            "page": page,
            "page_size": pageSize,
            "sort_by": sortBy,
            "sort_order": sortOrder,
        ]
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty { body["search"] = s }

        return await api.apiPost(
            "/api/music/playlist/list",
            body: body,
            dataParser: { data, _ in PlaylistListResult(json: data) }
        )
    }

    // MARK: - Playlist Get (detail with items)

    static func getPlaylist(listId: Int) async -> APIResponse<PlaylistDetailResult> {
        return await api.apiPost(
            "/api/music/playlist/get",
            body: ["list_id": listId],
            dataParser: { data, _ in PlaylistDetailResult(json: data) }
        )
    }

    // MARK: - Collection List

    static func listCollections(
        page: Int = 1,
        pageSize: Int = 20,
        keyword: String? = nil,
        sortField: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<CollectionListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortField,
            "sortOrder": sortOrder,
        ]
        if let k = keyword?.trimmingCharacters(in: .whitespaces), !k.isEmpty { body["keyword"] = k }

        return await api.apiPost(
            "/api/music/collection/list",
            body: body,
            dataParser: { data, _ in CollectionListResult(json: data) }
        )
    }

    // MARK: - Collection Get (detail)

    static func getCollection(collectionId: Int) async -> APIResponse<CollectionDetailResult> {
        return await api.apiPost(
            "/api/music/collection/get",
            body: ["id": collectionId],
            dataParser: { data, _ in CollectionDetailResult(json: data) }
        )
    }

    // MARK: - Detail (single track with lyrics)

    static func getDetail(filePath: String) async -> APIResponse<MusicDetailResult> {
        return await api.apiPost(
            "/api/music/detail/get",
            body: ["file_path": filePath],
            dataParser: { data, _ in MusicDetailResult(json: data) }
        )
    }

    // MARK: - Lyric Search (API returns array directly as data)

    static func searchLyric(keyword: String) async -> APIResponse<[[String: Any]]> {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 100 else {
            return .failure(L10n.musicLyricSearchInvalid)
        }
        let response: APIResponse<[[String: Any]]> = await api.apiPost(
            "/api/music/lyric/search",
            body: ["keyword": trimmed],
            dataParser: nil
        )
        if response.success, let items = response.data {
            return .success(items)
        }
        return .failure(response.message ?? L10n.networkFailure)
    }

    // MARK: - Lyric Set (bind lrc to file)

    static func setLyric(musicPath: String, lrc: String) async -> APIResponse<[String: Any]> {
        let p = musicPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let lyric = lrc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !lyric.isEmpty else {
            return .failure(L10n.musicLyricSearchInvalid)
        }
        return await api.apiPost(
            "/api/music/lyric/set",
            body: ["music_path": p, "lrc": lyric],
            dataParser: { data, _ in data }
        )
    }

    // MARK: - Favorite

    static func addFavorite(indexId: Int) async -> APIResponse<[String: Any]> {
        return await api.apiPost(
            "/api/music/favorite/add",
            body: ["index_id": indexId],
            dataParser: { data, _ in data }
        )
    }

    static func removeFavorite(indexId: Int) async -> APIResponse<[String: Any]> {
        return await api.apiPost(
            "/api/music/favorite/remove",
            body: ["index_id": indexId],
            dataParser: { data, _ in data }
        )
    }

    // MARK: - Refresh History

    static func refreshHistory(indexId: Int? = nil, filePath: String? = nil) async -> APIResponse<[String: Any]> {
        var body: [String: Any] = [:]
        if let id = indexId, id > 0 { body["index_id"] = id }
        if let p = filePath?.trimmingCharacters(in: .whitespaces), !p.isEmpty { body["file_path"] = p }
        return await api.apiPost(
            "/api/music/history/refresh",
            body: body.isEmpty ? ["index_id": 0] : body,
            dataParser: { data, _ in data }
        )
    }
}

// MARK: - Result Types

struct MusicListResult {
    let items: [MusicItem]
    let pagination: MusicPagination
    let validPaths: [MusicSourcePathItem]

    init(json: [String: Any]) {
        let raw = json["items"] as? [[String: Any]] ?? []
        items = raw.map { MusicItem(json: $0) }.filter { $0.id > 0 }
        let pagRaw = json["pagination"] as? [String: Any] ?? [:]
        pagination = MusicPagination(json: pagRaw)
        let rawPaths = (json["validPaths"] ?? json["valid_paths"]) as? [Any] ?? []
        validPaths = rawPaths
            .map { MusicSourcePathItem(json: $0) }
            .filter { !$0.path.isEmpty }
    }
}

struct AlbumArtistListResult {
    let items: [AlbumArtistItem]
    let pagination: MusicPagination
    let validPaths: [MusicSourcePathItem]

    init(json: [String: Any]) {
        let raw = json["items"] as? [[String: Any]] ?? []
        items = raw.map { AlbumArtistItem(json: $0) }.filter { !$0.name.isEmpty }
        let pagRaw = json["pagination"] as? [String: Any] ?? [:]
        pagination = MusicPagination(json: pagRaw)
        let rawPaths = (json["validPaths"] ?? json["valid_paths"]) as? [Any] ?? []
        validPaths = rawPaths
            .map { MusicSourcePathItem(json: $0) }
            .filter { !$0.path.isEmpty }
    }
}

struct PlaylistListResult {
    let items: [MusicPlaylistItem]
    let pagination: MusicPagination

    init(json: [String: Any]) {
        let raw = json["items"] as? [[String: Any]] ?? []
        items = raw.map { MusicPlaylistItem(json: $0) }.filter { $0.id > 0 }
        let pagRaw = json["pagination"] as? [String: Any] ?? [:]
        pagination = MusicPagination(json: pagRaw)
    }
}

struct PlaylistDetailResult {
    let list: MusicPlaylistItem?
    let items: [MusicItem]

    init(json: [String: Any]) {
        if let listRaw = json["list"] as? [String: Any] {
            list = MusicPlaylistItem(json: listRaw)
        } else {
            list = nil
        }
        let raw = json["items"] as? [[String: Any]] ?? []
        items = raw.map { MusicItem(json: $0) }.filter { $0.id > 0 }
    }
}

struct CollectionListResult {
    let items: [MusicCollectionItem]
    let pagination: MusicPagination

    init(json: [String: Any]) {
        let raw = json["items"] as? [[String: Any]] ?? []
        items = raw.map { MusicCollectionItem(json: $0) }.filter { $0.id > 0 }
        let pagRaw = json["pagination"] as? [String: Any] ?? [:]
        pagination = MusicPagination(json: pagRaw)
    }
}

struct CollectionDetailResult {
    let id: Int
    let name: String
    let pathList: [String]

    init(json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        name = (json["name"] as? String) ?? ""
        let raw = json["path_list"] as? [Any] ?? []
        pathList = raw.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct MusicDetailResult {
    let item: MusicItem?
    let lyrics: String

    init(json: [String: Any]) {
        if let itemRaw = json["item"] as? [String: Any] {
            item = MusicItem(json: itemRaw)
        } else {
            item = nil
        }
        lyrics = (json["lyrics"] as? String) ?? ""
    }
}
