import Foundation

// MARK: - Photo Album / Smart Album / Collection Services

@MainActor
enum TVPhotoAlbumService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        type: String = "all",
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVPhotoAlbumListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder,
            "type": type,
        ]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVPhotoAlbumListResult> = await api.apiPost(
            "/api/photo/album/list",
            body: body,
            dataParser: { data, _ in TVPhotoAlbumListResult(json: data) }
        )
        return response
    }
}

@MainActor
enum TVPhotoSmartAlbumService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        type: String = "all",
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVPhotoSmartAlbumListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder,
        ]
        if !type.isEmpty, type != "all" {
            body["type"] = type
        }
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVPhotoSmartAlbumListResult> = await api.apiPost(
            "/api/photo/smart_album/list",
            body: body,
            dataParser: { data, _ in TVPhotoSmartAlbumListResult(json: data) }
        )
        return response
    }
}

@MainActor
enum TVPhotoCollectionService {
    private static let api = APIClient.shared

    static func loadPage(
        page: Int,
        pageSize: Int = 30,
        keyword: String? = nil,
        sortBy: String = "create_time",
        sortOrder: String = "desc"
    ) async -> APIResponse<TVPhotoCollectionListResult> {
        var body: [String: Any] = [
            "page": page,
            "pageSize": pageSize,
            "sortField": sortBy,
            "sortOrder": sortOrder,
        ]
        if let kw = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !kw.isEmpty {
            body["keyword"] = kw
        }

        let response: APIResponse<TVPhotoCollectionListResult> = await api.apiPost(
            "/api/photo/collection/list",
            body: body,
            dataParser: { data, _ in TVPhotoCollectionListResult(json: data) }
        )
        return response
    }
}
