import Foundation

// MARK: - Detail Models

struct TVVideoDetailHistory {
    let playbackSeconds: Int
    let durationSeconds: Int
    let episodeNumber: Int?

    init(playbackSeconds: Int, durationSeconds: Int, episodeNumber: Int?) {
        self.playbackSeconds = playbackSeconds
        self.durationSeconds = durationSeconds
        self.episodeNumber = episodeNumber
    }

    init(json: [String: Any]) {
        let playback = (json["playback_position"] as? NSNumber)?.intValue
            ?? Int(json["playback_position"] as? String ?? "")
            ?? 0
        let duration = (json["duration"] as? NSNumber)?.intValue
            ?? Int(json["duration"] as? String ?? "")
            ?? 0
        let epNum = (json["episod_num"] as? NSNumber)?.intValue
            ?? Int(json["episod_num"] as? String ?? "")

        self.playbackSeconds = max(0, playback)
        self.durationSeconds = max(0, duration)
        self.episodeNumber = (epNum ?? 0) > 0 ? epNum : nil
    }
}

struct TVVideoDetailResponse {
    let item: TVVideoItem
    let seasons: [TVVideoItem]
    let history: TVVideoDetailHistory?

    init(item: TVVideoItem, seasons: [TVVideoItem], history: TVVideoDetailHistory?) {
        self.item = item
        self.seasons = seasons
        self.history = history
    }

    init(json: [String: Any]) {
        let itemJson = (json["item"] as? [String: Any]) ?? [:]
        self.item = TVVideoItem(json: itemJson)

        let seasonRaw = json["season_list"] as? [Any] ?? []
        self.seasons = seasonRaw
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoItem(json: $0) }

        if let historyJson = json["history"] as? [String: Any] {
            self.history = TVVideoDetailHistory(json: historyJson)
        } else {
            self.history = nil
        }
    }
}

struct TVVideoEpisodeItem: Identifiable, Equatable {
    let id: Int
    let name: String
    let storyline: String
    let fullPath: String
    let episodNumber: Int
    let posterPath: String
    /// 时长（秒），来自 video_index.duration
    let durationSeconds: Int
    /// 文件大小（字节），来自 video_index.size
    let fileSizeBytes: Int

    init(json: [String: Any]) {
        func int(_ key: String) -> Int {
            if let n = json[key] as? NSNumber { return n.intValue }
            if let s = json[key] as? String, let v = Int(s) { return v }
            return 0
        }

        func string(_ key: String) -> String {
            (json[key] as? String) ?? ""
        }

        self.id = int("id")
        let nfoName = string("nfo_name").trimmingCharacters(in: .whitespaces)
        let filename = string("filename")
        self.name = nfoName.isEmpty ? filename : nfoName
        self.storyline = string("nfo_storyline")
        self.fullPath = (json["full_path"] as? String) ?? ""
        self.episodNumber = int("episod_num")
        self.posterPath = string("poster_path")
        self.durationSeconds = int("duration")
        self.fileSizeBytes = int("size")
    }
}

struct TVVideoEpisodePage {
    let items: [TVVideoEpisodeItem]
    let total: Int
    let page: Int
    let pageSize: Int

    init(items: [TVVideoEpisodeItem], total: Int, page: Int, pageSize: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }

    init(json: [String: Any]) {
        let rawItems = json["items"] as? [Any] ?? []
        self.items = rawItems
            .compactMap { $0 as? [String: Any] }
            .map { TVVideoEpisodeItem(json: $0) }
            .filter { $0.id > 0 }

        let p = json["pagination"] as? [String: Any] ?? [:]
        func int(_ key: String, default def: Int) -> Int {
            if let n = p[key] as? NSNumber { return n.intValue }
            if let s = p[key] as? String, let v = Int(s) { return v }
            return def
        }
        self.total = int("total", default: 0)
        self.page = int("page", default: 1)
        self.pageSize = int("limit", default: 50)
    }
}

struct TVVideoTvPlayInfo {
    let playlist: [[String: String]]
    let initialIndex: Int

    init(json: [String: Any]) {
        let rawList = json["playlist"] as? [Any] ?? []
        self.playlist = rawList
            .compactMap { $0 as? [String: Any] }
            .map { dict in
                [
                    "path": (dict["path"] as? String) ?? "",
                    "name": (dict["name"] as? String) ?? ""
                ]
            }
            .filter { !($0["path"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

        if let n = json["initialIndex"] as? NSNumber {
            self.initialIndex = n.intValue
        } else if let s = json["initialIndex"] as? String, let v = Int(s) {
            self.initialIndex = v
        } else {
            self.initialIndex = 0
        }
    }
}

// MARK: - Service

@MainActor
enum TVVideoDetailService {
    private static let api = APIClient.shared

    static func getDetail(indexId: Int) async -> APIResponse<TVVideoDetailResponse> {
        await api.apiGet(
            "/api/video/detail",
            queryParams: ["index_id": "\(indexId)"],
            dataParser: { data, _ in
                TVVideoDetailResponse(json: data)
            }
        )
    }

    static func getEpisodes(
        indexId: Int,
        page: Int,
        pageSize: Int,
        sortAsc: Bool
    ) async -> APIResponse<TVVideoEpisodePage> {
        let sortOrder = sortAsc ? "asc" : "desc"
        return await api.apiGet(
            "/api/video/episodes",
            queryParams: [
                "index_id": "\(indexId)",
                "page": "\(page)",
                "page_size": "\(pageSize)",
                "sort_order": sortOrder
            ],
            dataParser: { data, _ in
                TVVideoEpisodePage(json: data)
            }
        )
    }

    static func getTvPlayInfo(indexId: Int) async -> APIResponse<TVVideoTvPlayInfo> {
        await api.apiGet(
            "/api/video/tvPlayInfo",
            queryParams: ["index_id": "\(indexId)"],
            dataParser: { data, _ in
                TVVideoTvPlayInfo(json: data)
            }
        )
    }

    static func setFavorite(indexId: Int, to isFavorite: Bool) async -> Bool {
        let endpoint = isFavorite ? "/api/video/favorite/add" : "/api/video/favorite/remove"
        let body: [String: Any] = ["index_id": indexId]
        let response: APIResponse<[String: Any]> = await api.apiPost(
            endpoint,
            body: body,
            dataParser: { data, _ in data }
        )
        return response.success
    }

    static func scanChanges(indexId: Int) async -> APIResponse<[String: Any]> {
        let body: [String: Any] = ["index_id": indexId]
        return await api.apiPost(
            "/api/video/source/scan_index",
            body: body,
            dataParser: { data, _ in data }
        )
    }

    static func deleteItem(atPath path: String) async -> APIResponse<[String: Any]> {
        let body: [String: Any] = [
            "paths": [path],
            "recycle": false
        ]
        return await api.apiPost(
            "/api/file/delete",
            body: body,
            dataParser: { data, _ in data }
        )
    }
}

