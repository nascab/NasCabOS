import Foundation

// MARK: - Music Item (single track)

struct MusicItem: Identifiable, Equatable {
    let id: Int
    let path: String
    let filename: String
    let fileHash: String
    let title: String
    let artist: String
    let album: String
    let year: String
    let genre: String
    let duration: Int
    let size: Int
    let ext: String
    let hasInnerCover: Int
    let showType: String
    let musicCount: Int
    let isFavorite: Bool
    let fullPath: String
    let firstFilePath: String
    let bitrate: Int?
    let sampleRate: Int?
    let bitDepth: Int?

    /// 文件夹类型，不可直接播放，需进入二级列表
    var isSeries: Bool { showType.trimmingCharacters(in: .whitespaces).lowercased() == "series" }

    var displayTitle: String { filename.trimmingCharacters(in: .whitespaces) }
    var displaySubtitle: String {
        // 文件夹类型：显示「X 首」
        if isSeries, musicCount > 0 {
            return L10n.musicItemCount(musicCount)
        }
        var parts: [String] = []
        if !artist.isEmpty { parts.append(artist) }
        if !album.isEmpty { parts.append(album) }
        return parts.joined(separator: " · ")
    }

    init(json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        path = (json["path"] as? String) ?? ""
        filename = (json["filename"] as? String) ?? ""
        fileHash = (json["file_hash"] as? String ?? json["fileHash"] as? String) ?? ""
        title = (json["title"] as? String) ?? ""
        artist = (json["artist"] as? String) ?? ""
        album = (json["album"] as? String) ?? ""
        year = (json["year"] as? String) ?? ""
        genre = (json["genre"] as? String) ?? ""
        duration = (json["duration"] as? NSNumber)?.intValue ?? 0
        size = (json["size"] as? NSNumber)?.intValue ?? 0
        ext = (json["ext"] as? String) ?? ""
        hasInnerCover = (json["has_inner_cover"] as? NSNumber)?.intValue ?? 0
        showType = (json["show_type"] as? String) ?? ""
        musicCount = (json["music_count"] as? NSNumber)?.intValue ?? 0
        let fav = json["is_favorite"] ?? json["isFavorite"]
        isFavorite = (fav as? Bool) == true || (fav as? NSNumber)?.intValue == 1
        fullPath = (json["full_path"] as? String ?? json["fullPath"] as? String) ?? ""
        firstFilePath = (json["first_file_path"] as? String ?? json["firstFilePath"] as? String) ?? ""
        bitrate = (json["bitrate"] as? NSNumber)?.intValue
        sampleRate = (json["sample_rate"] as? NSNumber)?.intValue ?? (json["sampleRate"] as? NSNumber)?.intValue
        bitDepth = (json["bit_depth"] as? NSNumber)?.intValue ?? (json["bitDepth"] as? NSNumber)?.intValue
    }
}

// MARK: - Album / Artist Group Item

struct AlbumArtistItem: Identifiable, Equatable {
    let keyType: String
    let name: String
    let firstFilePath: String
    let indexCount: Int

    var id: String { "\(keyType)_\(name)" }
    var isAlbum: Bool { keyType.lowercased() == "album" }
    var isArtist: Bool { keyType.lowercased() == "artist" }

    init(json: [String: Any]) {
        keyType = (json["key_type"] as? String ?? json["keyType"] as? String) ?? ""
        name = ((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        firstFilePath = (json["first_file_path"] as? String ?? json["firstFilePath"] as? String) ?? ""
        indexCount = (json["index_count"] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: - Source Path Item (for source filter)

struct MusicSourcePathItem: Identifiable, Equatable {
    let path: String
    let valid: Bool

    var id: String { path }

    init(path: String, valid: Bool) {
        self.path = path
        self.valid = valid
    }

    init(json: Any) {
        if let s = json as? String {
            let p = s.trimmingCharacters(in: .whitespacesAndNewlines)
            self.path = p
            self.valid = !p.isEmpty
            return
        }

        guard let dict = json as? [String: Any] else {
            self.path = ""
            self.valid = false
            return
        }

        let rawPath = (dict["path"] as? String) ?? ""
        self.path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.valid = (dict["valid"] as? Bool) ?? false
    }
}

// MARK: - Playlist Item

struct MusicPlaylistItem: Identifiable, Equatable {
    let id: Int
    let uid: Int
    let name: String
    let createTime: String
    let previews: [MusicItem]

    init(json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        uid = (json["uid"] as? NSNumber)?.intValue ?? 0
        name = ((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        createTime = (json["create_time"] as? String ?? json["createTime"] as? String) ?? ""
        let raw = json["previews"] as? [[String: Any]] ?? []
        previews = raw.map { MusicItem(json: $0) }.filter { $0.id > 0 }
    }
}

// MARK: - Collection Preview Item

struct MusicCollectionPreviewItem: Equatable {
    let id: Int
    let path: String
    let filename: String
    let showType: String
    let firstFilePath: String

    var fullPath: String {
        let p = path.trimmingCharacters(in: .whitespaces)
        let f = filename.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return "" }
        if f.isEmpty { return p }
        return p.hasSuffix("/") ? "\(p)\(f)" : "\(p)/\(f)"
    }

    init(json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        path = (json["path"] as? String) ?? ""
        filename = (json["filename"] as? String) ?? ""
        showType = (json["show_type"] as? String) ?? ""
        firstFilePath = (json["first_file_path"] as? String ?? json["firstFilePath"] as? String) ?? ""
    }
}

// MARK: - Collection Item

struct MusicCollectionItem: Identifiable, Equatable {
    let id: Int
    let ownerId: Int
    let name: String
    let pathList: [String]
    let previews: [MusicCollectionPreviewItem]

    init(json: [String: Any]) {
        id = (json["id"] as? NSNumber)?.intValue ?? 0
        ownerId = (json["uid"] as? NSNumber)?.intValue ?? 0
        name = ((json["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let rawPaths = json["path_list"] as? [Any] ?? []
        pathList = rawPaths.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let rawPreviews = json["previews"] as? [[String: Any]] ?? []
        previews = rawPreviews.map { MusicCollectionPreviewItem(json: $0) }.filter { $0.id > 0 }
    }
}

// MARK: - Pagination

struct MusicPagination {
    let total: Int
    let page: Int
    let limit: Int
    let totalPages: Int
    let hasNextPage: Bool
    let hasPrevPage: Bool

    init(json: [String: Any]) {
        total = (json["total"] as? NSNumber)?.intValue ?? 0
        page = (json["page"] as? NSNumber)?.intValue ?? 1
        limit = (json["limit"] as? NSNumber)?.intValue ?? 30
        totalPages = (json["totalPages"] as? NSNumber)?.intValue ?? 0
        hasNextPage = (json["hasNextPage"] as? Bool) ?? false
        hasPrevPage = (json["hasPrevPage"] as? Bool) ?? false
    }
}

// MARK: - Lyric Line

struct LyricLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}
