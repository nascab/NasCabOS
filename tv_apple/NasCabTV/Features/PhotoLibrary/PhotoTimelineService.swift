import Foundation

@MainActor
enum TVPhotoTimelineService {
    private static let api = APIClient.shared

    static func getTimelineDateList(
        sort: String = "desc",
        fileType: String? = nil,
        search: String? = nil,
        sourceList: [String]? = nil,
        year: Int? = nil,
        loadTheDay: Bool = false,
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        listType: String? = nil
    ) async -> APIResponse<TVPhotoTimelineDateListResult> {
        var body: [String: Any] = [
            "sort": sort,
        ]
        if let ft = fileType, !ft.isEmpty, ft != "all" {
            body["fileType"] = ft
        }
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            body["search"] = s
        }
        if let sl = sourceList, !sl.isEmpty {
            body["sourceList"] = sl
        }
        if let y = year {
            body["year"] = y
        }
        if loadTheDay {
            body["loadTheDay"] = 1
        }
        if let aid = albumId, aid > 0 {
            body["album_id"] = aid
        }
        if let cid = collectionId, cid > 0 {
            body["collection_id"] = cid
        }
        if let sid = smartAlbumId, sid > 0 {
            body["smart_album_id"] = sid
        }
        if let lt = listType, !lt.trimmingCharacters(in: .whitespaces).isEmpty {
            body["list_type"] = lt.trimmingCharacters(in: .whitespaces)
        }

        print("[PhotoTimeline] getTimelineDateList request body: \(body)")
        let response: APIResponse<TVPhotoTimelineDateListResult> = await api.apiPost(
            "/api/photo/timeline/dates",
            body: body,
            dataParser: { data, _ in
                let result = TVPhotoTimelineDateListResult(json: data)
                print("[PhotoTimeline] getTimelineDateList parsed: items=\(result.items.count), validPaths=\(result.validPaths.count)")
                return result
            }
        )
        print("[PhotoTimeline] getTimelineDateList response: success=\(response.success), message=\(response.message ?? "nil")")
        return response
    }

    static func getTimelinePhotoList(
        sort: String = "desc",
        fileType: String? = nil,
        startTime: Int,
        endTime: Int,
        search: String? = nil,
        sourceList: [String]? = nil,
        year: Int? = nil,
        loadTheDay: Bool = false,
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        listType: String? = nil
    ) async -> APIResponse<TVPhotoTimelinePhotoListResult> {
        var body: [String: Any] = [
            "sort": sort,
            "startTime": startTime,
            "endTime": endTime,
        ]
        if let ft = fileType, !ft.isEmpty, ft != "all" {
            body["fileType"] = ft
        }
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            body["search"] = s
        }
        if let sl = sourceList, !sl.isEmpty {
            body["sourceList"] = sl
        }
        if let y = year {
            body["year"] = y
        }
        if loadTheDay {
            body["loadTheDay"] = 1
        }
        if let aid = albumId, aid > 0 {
            body["album_id"] = aid
        }
        if let cid = collectionId, cid > 0 {
            body["collection_id"] = cid
        }
        if let sid = smartAlbumId, sid > 0 {
            body["smart_album_id"] = sid
        }
        if let lt = listType, !lt.trimmingCharacters(in: .whitespaces).isEmpty {
            body["list_type"] = lt.trimmingCharacters(in: .whitespaces)
        }

        print("[PhotoTimeline] getTimelinePhotoList request: startTime=\(startTime), endTime=\(endTime)")
        let response: APIResponse<TVPhotoTimelinePhotoListResult> = await api.apiPost(
            "/api/photo/timeline/photos",
            body: body,
            dataParser: { data, _ in
                let result = TVPhotoTimelinePhotoListResult(json: data)
                print("[PhotoTimeline] getTimelinePhotoList parsed: photoList=\(result.photoList.count)")
                return result
            }
        )
        print("[PhotoTimeline] getTimelinePhotoList response: success=\(response.success), message=\(response.message ?? "nil")")
        return response
    }

    static func getTimelineYearList() async -> APIResponse<TVPhotoTimelineYearListResult> {
        let response: APIResponse<TVPhotoTimelineYearListResult> = await api.apiPost(
            "/api/photo/timeline/years",
            body: [:],
            dataParser: { data, _ in
                TVPhotoTimelineYearListResult(json: data)
            }
        )
        return response
    }
}
