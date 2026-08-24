package com.nascabos.tv.modules.video

import com.nascabos.tv.core.api.ApiController

object VideoListApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun getIndexCounts(
        sourceList: List<String>? = null,
        timeoutSeconds: Long = 10,
    ): VideoIndexCountResult? {
        val body = mutableMapOf<String, Any?>()
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/list/count",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val movie = parseInt(data["movie"])
        val tv = parseInt(data["tv"])
        val total = parseInt(data["total"]).takeIf { it > 0 } ?: (movie + tv)
        return VideoIndexCountResult(movie = movie, tv = tv, total = total)
    }

    suspend fun listPaged(
        page: Int,
        pageSize: Int,
        mediaType: String,
        search: String?,
        sourceList: List<String>?,
        sort: VideoListSortState,
        listType: String? = null,
        albumId: Int? = null,
        collectionId: Int? = null,
        smartAlbumId: Int? = null,
        timeoutSeconds: Long = 15,
    ): VideoListPagedResult {
        val effectivePage = if (page > 0) page else 1
        val effectivePageSize = if (pageSize > 0) pageSize else 30
        val mt = mediaType.trim().lowercase()
        val body =
            mutableMapOf<String, Any?>(
                "page" to effectivePage,
                "page_size" to effectivePageSize,
                "sort_by" to sort.by.apiValue,
                "sort_order" to sort.order.apiValue,
            )
        if (mt == "movie" || mt == "tv" || mt == "season") {
            body["media_type"] = mt
        }
        val q = search?.trim().orEmpty()
        if (q.isNotEmpty()) body["search"] = q
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList
        val lt = listType?.trim().orEmpty()
        if (lt.isNotEmpty()) body["listType"] = lt
        val aid = albumId ?: 0
        if (aid > 0) body["album_id"] = aid
        val cid = collectionId ?: 0
        if (cid > 0) body["collection_id"] = cid
        val sid = smartAlbumId ?: 0
        if (sid > 0) body["smart_album_id"] = sid

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/list",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return VideoListPagedResult.empty

        val items = parseItems(data["items"])
        val pagination = parsePagination(data["pagination"])
        val validPaths = parseValidPaths(data["validPaths"] ?: data["valid_paths"])
        return VideoListPagedResult(items = items, pagination = pagination, validPaths = validPaths)
    }

    suspend fun listHistory(
        timeoutSeconds: Long = 20,
    ): List<VideoListItem> {
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/history/list",
                body = emptyMap<String, Any?>(),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return emptyList()
        return parseItems(data["items"])
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

    private fun parseDouble(v: Any?): Double {
        return when (v) {
            null -> 0.0
            is Number -> v.toDouble()
            else -> v.toString().trim().toDoubleOrNull() ?: 0.0
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

    private fun parseItems(v: Any?): List<VideoListItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"])
            if (id <= 0) return@mapNotNull null
            val mediaType = map["media_type"]?.toString().orEmpty()
            val path = map["path"]?.toString().orEmpty()
            val filename = map["filename"]?.toString().orEmpty()
            val firstFilePath = (map["first_file_path"] ?: map["firstFilePath"])?.toString().orEmpty()
            val nfoName = map["nfo_name"]?.toString().orEmpty()
            val nfoYear = parseInt(map["nfo_year"])
            val nfoScore = parseDouble(map["nfo_score"])
            val nfoRegions = map["nfo_regions"]?.toString().orEmpty()
            val nfoGenres = map["nfo_genres"]?.toString().orEmpty()
            val posterPath = map["poster_path"]?.toString().orEmpty()
            val fanartPath = map["fanart_path"]?.toString().orEmpty()
            val logoPath = map["logo_path"]?.toString().orEmpty()
            val progress = parseDouble(map["progress"])
            val isFavorite = parseBool(map["is_favorite"])
            val viewTime = map["view_time"]?.toString()
            val createTime = map["create_time"]?.toString()
            val fullPath = map["full_path"]?.toString().orEmpty()
            VideoListItem(
                id = id,
                mediaType = mediaType,
                path = path,
                filename = filename,
                firstFilePath = firstFilePath,
                nfoName = nfoName,
                nfoYear = nfoYear,
                nfoScore = nfoScore,
                nfoRegions = nfoRegions,
                nfoGenres = nfoGenres,
                posterPath = posterPath,
                fanartPath = fanartPath,
                logoPath = logoPath,
                progress = progress,
                isFavorite = isFavorite,
                viewTime = viewTime,
                createTime = createTime,
                fullPath = fullPath,
            )
        }
    }

    private fun parsePagination(v: Any?): VideoListPagination {
        val map = v as? Map<*, *> ?: return VideoListPagination.empty
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val limit = parseInt(map["limit"]).takeIf { it > 0 } ?: 30
        val totalPages = parseInt(map["totalPages"])
        val hasNextPage = (map["hasNextPage"] as? Boolean) ?: parseBool(map["hasNextPage"])
        val hasPrevPage = (map["hasPrevPage"] as? Boolean) ?: parseBool(map["hasPrevPage"])
        return VideoListPagination(
            total = total,
            page = page,
            limit = limit,
            totalPages = totalPages,
            hasNextPage = hasNextPage,
            hasPrevPage = hasPrevPage,
        )
    }

    private fun parseValidPaths(v: Any?): List<VideoListPathItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            when (raw) {
                is String -> {
                    val p = raw.trim()
                    if (p.isEmpty()) null else VideoListPathItem(path = p, valid = true)
                }
                is Map<*, *> -> {
                    val path = raw["path"]?.toString()?.trim().orEmpty()
                    if (path.isEmpty()) return@mapNotNull null
                    val valid = raw["valid"] as? Boolean ?: parseBool(raw["valid"])
                    VideoListPathItem(path = path, valid = valid)
                }
                else -> null
            }
        }
    }
}
