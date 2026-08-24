import Foundation

// MARK: - 基础模型

struct TVVideoItem: Identifiable, Equatable {
    let id: Int
    let mediaType: String
    let path: String
    let filename: String
    let firstFilePath: String
    let nfoName: String
    let nfoYear: Int
    let nfoScore: Double
    let nfoRegions: String
    let nfoGenres: String
    let posterPath: String
    let fanartPath: String
    let logoPath: String
    let progress: Double
    let isFavorite: Bool
    let viewTime: String?
    let createTime: String?
    let fullPath: String
    let nfoStoryline: String
    let seasonCount: Int
    let episodeCount: Int
    let width: Int
    let height: Int
    /// 视频时长（秒），来自 video_index.duration
    let durationSeconds: Int
    /// 文件大小（字节），来自 video_index.size
    let fileSizeBytes: Int
    let rawDirectorJson: String
    let rawActorJson: String

    init(
        id: Int,
        mediaType: String,
        path: String,
        filename: String,
        firstFilePath: String,
        nfoName: String,
        nfoYear: Int,
        nfoScore: Double,
        nfoRegions: String,
        nfoGenres: String,
        posterPath: String,
        fanartPath: String,
        logoPath: String,
        progress: Double,
        isFavorite: Bool,
        viewTime: String?,
        createTime: String?,
        fullPath: String,
        nfoStoryline: String = "",
        seasonCount: Int = 0,
        episodeCount: Int = 0,
        width: Int = 0,
        height: Int = 0,
        durationSeconds: Int = 0,
        fileSizeBytes: Int = 0,
        rawDirectorJson: String = "",
        rawActorJson: String = ""
    ) {
        self.id = id
        self.mediaType = mediaType
        self.path = path
        self.filename = filename
        self.firstFilePath = firstFilePath
        self.nfoName = nfoName
        self.nfoYear = nfoYear
        self.nfoScore = nfoScore
        self.nfoRegions = nfoRegions
        self.nfoGenres = nfoGenres
        self.posterPath = posterPath
        self.fanartPath = fanartPath
        self.logoPath = logoPath
        self.progress = progress
        self.isFavorite = isFavorite
        self.viewTime = viewTime
        self.createTime = createTime
        self.fullPath = fullPath
        self.nfoStoryline = nfoStoryline
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.rawDirectorJson = rawDirectorJson
        self.rawActorJson = rawActorJson
    }

    init(json: [String: Any]) {
        let rawFav = json["is_favorite"]
        let isFav = (rawFav as? Bool) == true
            || (rawFav as? Int) == 1
            || (rawFav as? String) == "1"

        func string(_ key: String) -> String {
            (json[key] as? String) ?? ""
        }

        func double(_ key: String) -> Double {
            if let n = json[key] as? NSNumber {
                return n.doubleValue
            }
            if let s = json[key] as? String, let v = Double(s) {
                return v
            }
            return 0
        }

        func int(_ key: String) -> Int {
            if let n = json[key] as? NSNumber {
                return n.intValue
            }
            if let s = json[key] as? String, let v = Int(s) {
                return v
            }
            return 0
        }

        self.id = int("id")
        self.mediaType = string("media_type")
        self.path = string("path")
        self.filename = string("filename")
        self.firstFilePath = (json["first_file_path"] ?? json["firstFilePath"]) as? String ?? ""
        self.fullPath = (json["full_path"] ?? json["fullPath"]) as? String ?? ""
        self.nfoName = string("nfo_name")
        self.nfoYear = int("nfo_year")
        self.nfoScore = double("nfo_score")
        self.nfoRegions = string("nfo_regions")
        self.nfoGenres = string("nfo_genres")
        self.posterPath = string("poster_path")
        self.fanartPath = string("fanart_path")
        self.logoPath = string("logo_path")
        self.progress = double("progress")
        self.isFavorite = isFav
        self.viewTime = json["view_time"] as? String ?? json["viewTime"] as? String
        self.createTime = json["create_time"] as? String ?? json["createTime"] as? String
        self.nfoStoryline = string("nfo_storyline")
        self.seasonCount = int("season_count")
        self.episodeCount = int("episode_count")
        self.width = int("width")
        self.height = int("height")
        self.durationSeconds = int("duration")
        self.fileSizeBytes = int("size")
        self.rawDirectorJson = string("nfo_director_json")
        self.rawActorJson = string("nfo_actor_json")
    }
}

struct TVVideoPathItem: Identifiable, Equatable {
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

struct TVVideoListPagination {
    let total: Int
    let page: Int
    let limit: Int
    let totalPages: Int
    let hasNextPage: Bool
    let hasPrevPage: Bool

    static let empty = TVVideoListPagination(
        total: 0,
        page: 1,
        limit: 30,
        totalPages: 0,
        hasNextPage: false,
        hasPrevPage: false
    )

    init(
        total: Int,
        page: Int,
        limit: Int,
        totalPages: Int,
        hasNextPage: Bool,
        hasPrevPage: Bool
    ) {
        self.total = total
        self.page = page
        self.limit = limit
        self.totalPages = totalPages
        self.hasNextPage = hasNextPage
        self.hasPrevPage = hasPrevPage
    }

    init(json: [String: Any]) {
        func int(_ key: String, default defaultValue: Int) -> Int {
            if let n = json[key] as? NSNumber {
                return n.intValue
            }
            if let s = json[key] as? String, let v = Int(s) {
                return v
            }
            return defaultValue
        }

        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.limit = int("limit", default: 30)
        self.totalPages = int("totalPages", default: 0)
        self.hasNextPage = (json["hasNextPage"] as? Bool) ?? false
        self.hasPrevPage = (json["hasPrevPage"] as? Bool) ?? false
    }
}

struct TVVideoListResult {
    let items: [TVVideoItem]
    let pagination: TVVideoListPagination
    let validPaths: [TVVideoPathItem]

    static let empty = TVVideoListResult(items: [], pagination: .empty, validPaths: [])

    init(items: [TVVideoItem], pagination: TVVideoListPagination, validPaths: [TVVideoPathItem]) {
        self.items = items
        self.pagination = pagination
        self.validPaths = validPaths
    }

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoItem(json: $0) }
            .filter { $0.id > 0 }

        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        let pagination = TVVideoListPagination(json: paginationRaw)

        let validPathsRaw = (json["validPaths"] ?? json["valid_paths"]) as? [Any] ?? []
        let parsedPaths = validPathsRaw
            .map { TVVideoPathItem(json: $0) }
            .filter { !$0.path.isEmpty }

        self.items = parsedItems
        self.pagination = pagination
        self.validPaths = parsedPaths
    }
}

// MARK: - 工具函数（类型文本 / 元信息）

enum TVVideoMetaUtils {
    static func mediaTypeText(_ mediaType: String) -> String {
        let t = mediaType.lowercased()
        if t == "tv" || t == "episod" || t == "season" {
            return L10n.videoTabTv
        }
        if t == "movie" {
            return L10n.videoTabMovie
        }
        return mediaType
    }

    static func buildMetaSubtitle(for item: TVVideoItem) -> String {
        func pickFirst(_ s: String) -> String {
            let parts = s
                .split(whereSeparator: { ",，/|、".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return parts.first ?? ""
        }

        let country = pickFirst(item.nfoRegions)
        let genre = pickFirst(item.nfoGenres)
        switch (country.isEmpty, genre.isEmpty) {
        case (true, true):
            return ""
        case (true, false):
            return genre
        case (false, true):
            return country
        case (false, false):
            return "\(country) · \(genre)"
        }
    }
}

// MARK: - Album / Collection / Smart Album Models

struct TVVideoAlbumPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String
    let firstFilePath: String

    init(fullPath: String, firstFilePath: String) {
        self.fullPath = fullPath
        self.firstFilePath = firstFilePath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
        self.firstFilePath = (json["first_file_path"] as? String) ?? ""
    }
}

struct TVVideoAlbumItem: Identifiable, Equatable {
    let id: Int
    let ownerId: Int
    let name: String
    let isPublic: Bool
    let isOwner: Bool
    let previews: [TVVideoAlbumPreviewItem]

    init(
        id: Int,
        ownerId: Int,
        name: String,
        isPublic: Bool,
        isOwner: Bool,
        previews: [TVVideoAlbumPreviewItem]
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.isPublic = isPublic
        self.isOwner = isOwner
        self.previews = previews
    }

    init(json: [String: Any]) {
        let rawPreviews = json["previews"] as? [Any] ?? []
        let previews = rawPreviews
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoAlbumPreviewItem(json: $0) }
            .filter { !$0.fullPath.isEmpty || !$0.firstFilePath.isEmpty }

        let rawIsPublic = json["is_public"]
        let isPublic = (rawIsPublic as? Bool) == true
            || (rawIsPublic as? Int) == 1
            || (rawIsPublic as? String) == "1"

        self.id = (json["id"] as? NSNumber)?.intValue ?? Int(json["id"] as? String ?? "") ?? 0
        self.ownerId = (json["owner_id"] as? NSNumber)?.intValue ?? Int(json["owner_id"] as? String ?? "") ?? 0
        self.name = (json["name"] as? String) ?? ""
        self.isPublic = isPublic
        self.isOwner = (json["is_owner"] as? Bool) ?? false
        self.previews = previews
    }
}

struct TVVideoAlbumListPagination {
    let total: Int
    let page: Int
    let pageSize: Int

    init(total: Int, page: Int, pageSize: Int) {
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    init(json: [String: Any]) {
        func int(_ key: String, default defaultValue: Int) -> Int {
            if let n = json[key] as? NSNumber {
                return n.intValue
            }
            if let s = json[key] as? String, let v = Int(s) {
                return v
            }
            return defaultValue
        }

        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.pageSize = int("pageSize", default: 20)
    }
}

struct TVVideoAlbumListResult {
    let items: [TVVideoAlbumItem]
    let pagination: TVVideoAlbumListPagination

    init(items: [TVVideoAlbumItem], pagination: TVVideoAlbumListPagination) {
        self.items = items
        self.pagination = pagination
    }

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoAlbumItem(json: $0) }
            .filter { $0.id > 0 }

        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        let pagination = TVVideoAlbumListPagination(json: paginationRaw)

        self.items = parsedItems
        self.pagination = pagination
    }
}

struct TVVideoCollectionPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String
    let firstFilePath: String

    init(fullPath: String, firstFilePath: String) {
        self.fullPath = fullPath
        self.firstFilePath = firstFilePath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
        self.firstFilePath = (json["first_file_path"] as? String) ?? ""
    }
}

struct TVVideoCollectionItem: Identifiable, Equatable {
    let id: Int
    let ownerId: Int
    let name: String
    let pathList: [String]
    let createTime: String?
    let previews: [TVVideoCollectionPreviewItem]

    init(
        id: Int,
        ownerId: Int,
        name: String,
        pathList: [String],
        createTime: String?,
        previews: [TVVideoCollectionPreviewItem]
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.pathList = pathList
        self.createTime = createTime
        self.previews = previews
    }

    init(json: [String: Any]) {
        let rawPreviews = json["previews"] as? [Any] ?? []
        let previews = rawPreviews
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoCollectionPreviewItem(json: $0) }
            .filter { !$0.fullPath.isEmpty }

        let rawPathList = json["path_list"] as? [Any] ?? []
        let paths = rawPathList.map { String(describing: $0) }

        self.id = (json["id"] as? NSNumber)?.intValue ?? Int(json["id"] as? String ?? "") ?? 0
        self.ownerId = (json["uid"] as? NSNumber)?.intValue ?? Int(json["uid"] as? String ?? "") ?? 0
        self.name = (json["name"] as? String) ?? ""
        self.pathList = paths
        self.createTime = json["create_time"] as? String
        self.previews = previews
    }
}

struct TVVideoCollectionListPagination {
    let total: Int
    let page: Int
    let pageSize: Int

    init(total: Int, page: Int, pageSize: Int) {
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    init(json: [String: Any]) {
        func int(_ key: String, default defaultValue: Int) -> Int {
            if let n = json[key] as? NSNumber {
                return n.intValue
            }
            if let s = json[key] as? String, let v = Int(s) {
                return v
            }
            return defaultValue
        }

        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.pageSize = int("pageSize", default: 20)
    }
}

struct TVVideoCollectionListResult {
    let items: [TVVideoCollectionItem]
    let pagination: TVVideoCollectionListPagination

    init(items: [TVVideoCollectionItem], pagination: TVVideoCollectionListPagination) {
        self.items = items
        self.pagination = pagination
    }

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoCollectionItem(json: $0) }
            .filter { $0.id > 0 }

        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        let pagination = TVVideoCollectionListPagination(json: paginationRaw)

        self.items = parsedItems
        self.pagination = pagination
    }
}

struct TVVideoSmartAlbumPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String
    let firstFilePath: String

    init(fullPath: String, firstFilePath: String) {
        self.fullPath = fullPath
        self.firstFilePath = firstFilePath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
        self.firstFilePath = (json["first_file_path"] as? String) ?? ""
    }
}

struct TVVideoSmartAlbumItem: Identifiable, Equatable {
    let id: Int
    let uid: Int
    let name: String
    let type: String
    let filterContent: [String: Any]
    let previews: [TVVideoSmartAlbumPreviewItem]

    init(
        id: Int,
        uid: Int,
        name: String,
        type: String,
        filterContent: [String: Any],
        previews: [TVVideoSmartAlbumPreviewItem]
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.type = type
        self.filterContent = filterContent
        self.previews = previews
    }

    init(json: [String: Any]) {
        let rawPreviews = json["previews"] as? [Any] ?? []
        let previews = rawPreviews
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoSmartAlbumPreviewItem(json: $0) }
            .filter { !$0.fullPath.isEmpty || !$0.firstFilePath.isEmpty }

        self.id = (json["id"] as? NSNumber)?.intValue ?? Int(json["id"] as? String ?? "") ?? 0
        self.uid = (json["uid"] as? NSNumber)?.intValue ?? Int(json["uid"] as? String ?? "") ?? 0
        self.name = (json["name"] as? String) ?? ""
        self.type = (json["type"] as? String) ?? "condition"
        self.filterContent = (json["filter_content"] as? [String: Any]) ?? [:]
        self.previews = previews
    }
}

extension TVVideoSmartAlbumItem {
    static func == (lhs: TVVideoSmartAlbumItem, rhs: TVVideoSmartAlbumItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.uid == rhs.uid &&
        lhs.name == rhs.name &&
        lhs.type == rhs.type
    }
}

struct TVVideoSmartAlbumListPagination {
    let total: Int
    let page: Int
    let pageSize: Int

    init(total: Int, page: Int, pageSize: Int) {
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    init(json: [String: Any]) {
        func int(_ key: String, default defaultValue: Int) -> Int {
            if let n = json[key] as? NSNumber {
                return n.intValue
            }
            if let s = json[key] as? String, let v = Int(s) {
                return v
            }
            return defaultValue
        }

        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.pageSize = int("pageSize", default: 20)
    }
}

struct TVVideoSmartAlbumListResult {
    let items: [TVVideoSmartAlbumItem]
    let pagination: TVVideoSmartAlbumListPagination

    init(items: [TVVideoSmartAlbumItem], pagination: TVVideoSmartAlbumListPagination) {
        self.items = items
        self.pagination = pagination
    }

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoSmartAlbumItem(json: $0) }
            .filter { $0.id > 0 }

        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        let pagination = TVVideoSmartAlbumListPagination(json: paginationRaw)

        self.items = parsedItems
        self.pagination = pagination
    }
}


