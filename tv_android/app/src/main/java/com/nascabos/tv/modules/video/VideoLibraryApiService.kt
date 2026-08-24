package com.nascabos.tv.modules.video

import com.nascabos.tv.core.api.ApiController

object VideoLibraryApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun listPaged(
        kind: VideoLibraryKind,
        page: Int,
        pageSize: Int,
        keyword: String?,
        sortField: VideoLibrarySortField,
        sortOrder: VideoLibrarySortOrder,
        previewLimit: Int = 4,
        timeoutSeconds: Long = 15,
    ): VideoLibraryPagedResult {
        val p = if (page > 0) page else 1
        val ps = if (pageSize > 0) pageSize else 20
        val limit = previewLimit.coerceIn(1, 20)

        val body =
            mutableMapOf<String, Any?>(
                "page" to p,
                "pageSize" to ps,
                "sortField" to sortField.apiValue,
                "sortOrder" to sortOrder.apiValue,
                "previewLimit" to limit,
            )
        val q = keyword?.trim().orEmpty()
        if (q.isNotEmpty()) body["keyword"] = q

        val path =
            when (kind) {
                VideoLibraryKind.Album -> "/api/video/album/list"
                VideoLibraryKind.SmartAlbum -> "/api/video/smart_album/list"
                VideoLibraryKind.Collection -> "/api/video/collection/list"
            }

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = path,
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )

        val data = unwrapData(raw) ?: return VideoLibraryPagedResult.empty
        val items = parseItems(kind, data["items"])
        val pagination = parsePagination(data["pagination"], defaultPageSize = ps)
        return VideoLibraryPagedResult(items = items, pagination = pagination)
    }

    private fun unwrapData(raw: Map<String, Any?>): Map<String, Any?>? {
        val success = raw["success"] as? Boolean
        if (success != null) {
            if (success != true) return null
            val data = raw["data"] as? Map<*, *>
            @Suppress("UNCHECKED_CAST")
            return data?.entries?.associate { it.key?.toString().orEmpty() to it.value } as? Map<String, Any?>
        }
        return raw
    }

    private fun parseInt(v: Any?): Int {
        return when (v) {
            null -> 0
            is Number -> v.toInt()
            else -> v.toString().trim().removeSuffix(".0").toIntOrNull() ?: 0
        }
    }

    private fun parseString(v: Any?): String {
        return v?.toString()?.trim().orEmpty()
    }

    private fun parseItems(kind: VideoLibraryKind, v: Any?): List<VideoLibraryListItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"])
            if (id <= 0) return@mapNotNull null
            val name = parseString(map["name"])
            val type = parseString(map["type"])
            val createTime = map["create_time"]?.toString()
            val previews = parsePreviews(map["previews"])
            VideoLibraryListItem(
                id = id,
                kind = kind,
                name = name,
                type = type,
                createTime = createTime,
                previews = previews,
            )
        }
    }

    private fun parsePreviews(v: Any?): List<VideoLibraryPreviewItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val fullPath = parseString(map["fullpath"] ?: map["full_path"])
            val firstFilePath = parseString(map["first_file_path"] ?: map["firstFilePath"])
            val mediaType = parseString(map["media_type"] ?: map["mediaType"])
            if (fullPath.isEmpty() && firstFilePath.isEmpty()) return@mapNotNull null
            VideoLibraryPreviewItem(fullPath = fullPath, firstFilePath = firstFilePath, mediaType = mediaType)
        }
    }

    private fun parsePagination(v: Any?, defaultPageSize: Int): VideoLibraryPagination {
        val map = v as? Map<*, *> ?: return VideoLibraryPagination(total = 0, page = 1, pageSize = defaultPageSize)
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val pageSize = parseInt(map["pageSize"] ?: map["page_size"]).takeIf { it > 0 } ?: defaultPageSize
        return VideoLibraryPagination(total = total, page = page, pageSize = pageSize)
    }
}

