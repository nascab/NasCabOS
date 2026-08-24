import Foundation

// MARK: - Timeline Date Item

struct TVPhotoTimelineDateItem: Identifiable, Equatable {
    let id: String
    let originalDate: String  // YYYY-MM-DD
    let count: Int

    init(originalDate: String, count: Int) {
        self.id = originalDate
        self.originalDate = originalDate
        self.count = count
    }

    init?(json: [String: Any]) {
        guard let date = json["original_date"] as? String else { return nil }
        self.originalDate = date
        self.id = date
        if let c = json["date_photo_count"] as? Int {
            self.count = c
        } else if let c = json["date_photo_count"] as? Double {
            self.count = Int(c)
        } else {
            self.count = 0
        }
    }

    var year: Int {
        let parts = originalDate.split(separator: "-")
        return Int(parts.first ?? "0") ?? 0
    }

    var month: Int {
        let parts = originalDate.split(separator: "-")
        return parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
    }

    var monthYearKey: String {
        "\(year)-\(String(format: "%02d", month))"
    }
}

// MARK: - Timeline Photo Item

struct TVPhotoTimelinePhotoItem: Identifiable, Equatable {
    let id: Int
    let path: String
    let filename: String
    let fullpath: String
    let originalDate: String
    let originalTime: String
    let width: Int
    let height: Int
    let type: Int  // 2=video，其余为照片
    let duration: Int
    let fileHash: String
    let isFavorite: Bool
    let isLvp: Int  // 1=实况（Live Photo）

    init?(json: [String: Any]) {
        guard let idVal = json["id"] else { return nil }
        self.id = (idVal as? Int) ?? (idVal as? Double).map { Int($0) } ?? 0
        self.path = json["path"] as? String ?? ""
        self.filename = json["filename"] as? String ?? ""
        self.fullpath = json["fullpath"] as? String ?? ""
        self.originalDate = json["original_date"] as? String ?? ""
        self.originalTime = (json["original_time"] as? Int).map { String($0) } ?? (json["original_time"] as? String) ?? ""
        self.width = (json["width"] as? Int) ?? (json["width"] as? Double).map { Int($0) } ?? 0
        self.height = (json["height"] as? Int) ?? (json["height"] as? Double).map { Int($0) } ?? 0
        self.type = (json["type"] as? Int) ?? (json["type"] as? Double).map { Int($0) } ?? 0
        self.duration = (json["duration"] as? Int) ?? (json["duration"] as? Double).map { Int($0) } ?? 0
        self.fileHash = json["file_hash"] as? String ?? ""
        self.isFavorite = ((json["is_favorite"] as? Int) ?? (json["is_favorite"] as? Double).map { Int($0) } ?? 0) == 1
        self.isLvp = (json["is_lvp"] as? Int) ?? (json["is_lvp"] as? Double).map { Int($0) } ?? 0
    }

    /// type=2 为视频
    var isVideo: Bool { type == 2 }
    /// is_lvp=1 为实况（Live Photo）
    var isLivePhoto: Bool { isLvp == 1 }
}

// MARK: - Timeline Path Item

struct TVPhotoTimelinePathItem: Identifiable, Equatable {
    let id: String
    let path: String
    let valid: Bool

    init(path: String, valid: Bool = true) {
        self.path = path
        self.id = path
        self.valid = valid
    }

    init?(json: [String: Any]) {
        guard let p = json["path"] as? String else { return nil }
        self.path = p
        self.id = p
        self.valid = json["valid"] as? Bool ?? true
    }
}

// MARK: - Timeline Year Item

struct TVPhotoTimelineYearItem: Identifiable, Equatable {
    let id: Int
    let year: Int
    let count: Int
    let cover: TVPhotoTimelinePhotoItem?

    init?(json: [String: Any]) {
        guard let y = json["year"] as? Int ?? (json["year"] as? Double).map({ Int($0) }) else { return nil }
        self.year = y
        self.id = y
        self.count = (json["count"] as? Int) ?? (json["count"] as? Double).map { Int($0) } ?? 0
        if let coverJson = json["cover"] as? [String: Any] {
            self.cover = TVPhotoTimelinePhotoItem(json: coverJson)
        } else {
            self.cover = nil
        }
    }
}

// MARK: - API Results

struct TVPhotoTimelineDateListResult {
    let items: [TVPhotoTimelineDateItem]
    let validPaths: [TVPhotoTimelinePathItem]

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [[String: Any]] ?? []
        self.items = rawItems.compactMap { TVPhotoTimelineDateItem(json: $0) }
        let rawPaths = json["validPaths"] as? [Any] ?? []
        self.validPaths = rawPaths.compactMap { item -> TVPhotoTimelinePathItem? in
            if let s = item as? String {
                return TVPhotoTimelinePathItem(path: s, valid: true)
            }
            if let m = item as? [String: Any] {
                return TVPhotoTimelinePathItem(json: m)
            }
            return nil
        }
    }
}

struct TVPhotoTimelinePhotoListResult {
    let photoList: [TVPhotoTimelinePhotoItem]
    let dateInfoList: [TVPhotoTimelineDateInfo]

    init(json: [String: Any]) {
        let rawPhotos = json["photoList"] as? [[String: Any]] ?? []
        self.photoList = rawPhotos.compactMap { TVPhotoTimelinePhotoItem(json: $0) }
        let rawDates = json["dateInfoList"] as? [[String: Any]] ?? []
        self.dateInfoList = rawDates.compactMap { TVPhotoTimelineDateInfo(json: $0) }
    }
}

struct TVPhotoTimelineDateInfo {
    let originalDate: String
    let geo: String
    let camera: String

    init?(json: [String: Any]) {
        self.originalDate = json["original_date"] as? String ?? ""
        self.geo = json["geo"] as? String ?? ""
        self.camera = json["camera"] as? String ?? ""
    }
}

struct TVPhotoTimelineYearListResult {
    let items: [TVPhotoTimelineYearItem]

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [[String: Any]] ?? []
        self.items = rawItems.compactMap { TVPhotoTimelineYearItem(json: $0) }
    }
}
