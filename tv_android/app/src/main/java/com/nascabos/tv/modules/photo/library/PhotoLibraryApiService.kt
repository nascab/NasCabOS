package com.nascabos.tv.modules.photo.library

import com.nascabos.tv.core.api.ApiController

object PhotoLibraryApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun listPaged(
        kind: PhotoLibraryKind,
        page: Int,
        pageSize: Int,
        keyword: String?,
        sortField: PhotoLibrarySortField,
        sortOrder: PhotoLibrarySortOrder,
        previewLimit: Int = 4,
        timeoutSeconds: Long = 15,
    ): PhotoLibraryPagedResult {
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
        if (kind == PhotoLibraryKind.Album) body["type"] = "all"

        val path =
            when (kind) {
                PhotoLibraryKind.Album -> "/api/photo/album/list"
                PhotoLibraryKind.SmartAlbum -> "/api/photo/smart_album/list"
                PhotoLibraryKind.Collection -> "/api/photo/collection/list"
            }

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = path,
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )

        val data = unwrapData(raw) ?: return PhotoLibraryPagedResult.empty
        val items = parseItems(kind, data["items"])
        val pagination = parsePagination(data["pagination"], defaultPageSize = ps)
        return PhotoLibraryPagedResult(items = items, pagination = pagination)
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

    private fun parseBool(v: Any?): Boolean {
        return when (v) {
            true -> true
            false -> false
            is Number -> v.toInt() != 0
            else -> v?.toString()?.trim() == "1"
        }
    }

    private fun parseString(v: Any?): String = v?.toString()?.trim().orEmpty()

    private fun parseItems(kind: PhotoLibraryKind, v: Any?): List<PhotoLibraryListItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"])
            if (id <= 0) return@mapNotNull null
            val name = parseString(map["name"])
            val type = parseString(map["type"])
            val createTime = map["create_time"]?.toString()

            val isOwner =
                when (kind) {
                    PhotoLibraryKind.Album -> (map["is_owner"] as? Boolean) ?: parseBool(map["is_owner"])
                    else -> null
                }
            val isPublic =
                when (kind) {
                    PhotoLibraryKind.Album -> {
                        val v2 = map["is_public"]
                        if (v2 == null) null else (v2 as? Boolean) ?: parseBool(v2)
                    }
                    else -> null
                }

            val previews = parsePreviews(map["previews"])

            PhotoLibraryListItem(
                id = id,
                kind = kind,
                name = name,
                type = type,
                createTime = createTime,
                isOwner = isOwner,
                isPublic = isPublic,
                previews = previews,
            )
        }
    }

    private fun parsePreviews(v: Any?): List<PhotoLibraryPreviewItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val fullPath = parseString(map["fullpath"] ?: map["full_path"])
            if (fullPath.isEmpty()) return@mapNotNull null
            val type = parseInt(map["type"])
            val duration = parseInt(map["duration"])
            PhotoLibraryPreviewItem(fullPath = fullPath, type = type, duration = duration)
        }
    }

    private fun parsePagination(v: Any?, defaultPageSize: Int): PhotoLibraryPagination {
        val map = v as? Map<*, *> ?: return PhotoLibraryPagination(total = 0, page = 1, pageSize = defaultPageSize)
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val pageSize = parseInt(map["pageSize"] ?: map["page_size"]).takeIf { it > 0 } ?: defaultPageSize
        return PhotoLibraryPagination(total = total, page = page, pageSize = pageSize)
    }
}

