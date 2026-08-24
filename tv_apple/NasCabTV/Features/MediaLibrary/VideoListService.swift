import Foundation

@MainActor
enum TVVideoListService {
    private static let api = APIClient.shared

    static func loadPage(
        mediaType: String,
        page: Int,
        pageSize: Int = 30,
        listType: String = "",
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        search: String? = nil,
        sourceList: [String] = [],
        actors: [String] = [],
        directors: [String] = [],
        sortBy: String? = nil,
        sortOrder: String? = nil
    ) async -> APIResponse<TVVideoListResult> {
        var body: [String: Any] = [
            "page": page,
            "page_size": pageSize
        ]
        let mt = mediaType.trimmingCharacters(in: .whitespaces)
        if !mt.isEmpty {
            body["media_type"] = mt
        }
        let lt = listType.trimmingCharacters(in: .whitespaces)
        if !lt.isEmpty {
            body["listType"] = lt
        }

        if let albumId, albumId > 0 {
            body["album_id"] = albumId
        }
        if let collectionId, collectionId > 0 {
            body["collection_id"] = collectionId
        }
        if let smartAlbumId, smartAlbumId > 0 {
            body["smart_album_id"] = smartAlbumId
        }

        if let search {
            body["search"] = search
        }
        if !sourceList.isEmpty {
            body["sourceList"] = sourceList
        }
        if !actors.isEmpty {
            body["actors"] = actors
        }
        if !directors.isEmpty {
            body["directors"] = directors
        }
        if let sortBy, !sortBy.trimmingCharacters(in: .whitespaces).isEmpty {
            body["sort_by"] = sortBy.trimmingCharacters(in: .whitespaces)
        }
        if let sortOrder, !sortOrder.trimmingCharacters(in: .whitespaces).isEmpty {
            body["sort_order"] = sortOrder.trimmingCharacters(in: .whitespaces)
        }

        let response: APIResponse<TVVideoListResult> = await api.apiPost(
            "/api/video/list",
            body: body,
            dataParser: { data, _ in
                TVVideoListResult(json: data)
            }
        )
        return response
    }

    /// 最近播放列表（与 Flutter 一致：调用 /api/video/history/list，基于 video_play_preference）
    static func loadHistory() async -> APIResponse<TVVideoListResult> {
        let response: APIResponse<TVVideoListResult> = await api.apiPost(
            "/api/video/history/list",
            body: [:],
            dataParser: { data, _ in
                TVVideoListResult(json: data)
            }
        )
        return response
    }
}

