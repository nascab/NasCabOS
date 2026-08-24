import Foundation

// MARK: - Photo Album Models (自建相册)

struct TVPhotoAlbumPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String

    init(fullPath: String) {
        self.fullPath = fullPath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
    }
}

struct TVPhotoAlbumItem: Identifiable, Equatable {
    let id: Int
    let ownerId: Int
    let name: String
    let isPublic: Bool
    let isOwner: Bool
    let previews: [TVPhotoAlbumPreviewItem]

    init(
        id: Int,
        ownerId: Int,
        name: String,
        isPublic: Bool,
        isOwner: Bool,
        previews: [TVPhotoAlbumPreviewItem]
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
            .map { TVPhotoAlbumPreviewItem(json: $0) }
            .filter { !$0.fullPath.isEmpty }

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

struct TVPhotoAlbumListPagination {
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
            if let n = json[key] as? NSNumber { return n.intValue }
            if let s = json[key] as? String, let v = Int(s) { return v }
            return defaultValue
        }
        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.pageSize = int("pageSize", default: 20)
    }
}

struct TVPhotoAlbumListResult {
    let items: [TVPhotoAlbumItem]
    let pagination: TVPhotoAlbumListPagination

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVPhotoAlbumItem(json: $0) }
            .filter { $0.id > 0 }
        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        self.items = parsedItems
        self.pagination = TVPhotoAlbumListPagination(json: paginationRaw)
    }
}

// MARK: - Photo Smart Album Models (智能相册)

struct TVPhotoSmartAlbumPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String

    init(fullPath: String) {
        self.fullPath = fullPath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
    }
}

struct TVPhotoSmartAlbumItem: Identifiable {
    let id: Int
    let uid: Int
    let name: String
    let type: String
    let filterContent: [String: Any]
    let previews: [TVPhotoSmartAlbumPreviewItem]

    init(
        id: Int,
        uid: Int,
        name: String,
        type: String,
        filterContent: [String: Any],
        previews: [TVPhotoSmartAlbumPreviewItem]
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
            .map { TVPhotoSmartAlbumPreviewItem(json: $0) }
            .filter { !$0.fullPath.isEmpty }

        self.id = (json["id"] as? NSNumber)?.intValue ?? Int(json["id"] as? String ?? "") ?? 0
        self.uid = (json["uid"] as? NSNumber)?.intValue ?? Int(json["uid"] as? String ?? "") ?? 0
        self.name = (json["name"] as? String) ?? ""
        self.type = (json["type"] as? String) ?? "condition"
        self.filterContent = (json["filter_content"] as? [String: Any]) ?? [:]
        self.previews = previews
    }
}

struct TVPhotoSmartAlbumListResult {
    let items: [TVPhotoSmartAlbumItem]
    let pagination: TVPhotoAlbumListPagination

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVPhotoSmartAlbumItem(json: $0) }
            .filter { $0.id > 0 }
        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        self.items = parsedItems
        self.pagination = TVPhotoAlbumListPagination(json: paginationRaw)
    }
}

// MARK: - Photo Collection Models (照片合集)

struct TVPhotoCollectionPreviewItem: Identifiable, Equatable {
    let id = UUID()
    let fullPath: String

    init(fullPath: String) {
        self.fullPath = fullPath
    }

    init(json: [String: Any]) {
        self.fullPath = (json["fullpath"] as? String) ?? ""
    }
}

struct TVPhotoCollectionItem: Identifiable, Equatable {
    let id: Int
    let ownerId: Int
    let name: String
    let pathList: [String]
    let createTime: String?
    let previews: [TVPhotoCollectionPreviewItem]

    init(
        id: Int,
        ownerId: Int,
        name: String,
        pathList: [String],
        createTime: String?,
        previews: [TVPhotoCollectionPreviewItem]
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
            .map { TVPhotoCollectionPreviewItem(json: $0) }
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

struct TVPhotoCollectionListResult {
    let items: [TVPhotoCollectionItem]
    let pagination: TVPhotoAlbumListPagination

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        let parsedItems = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVPhotoCollectionItem(json: $0) }
            .filter { $0.id > 0 }
        let paginationRaw = json["pagination"] as? [String: Any] ?? [:]
        self.items = parsedItems
        self.pagination = TVPhotoAlbumListPagination(json: paginationRaw)
    }
}
