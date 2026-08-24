package com.nascabos.tv.modules.music

import com.nascabos.tv.core.api.ApiController

object MusicListApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun listPaged(
        page: Int,
        pageSize: Int,
        isFavorite: Boolean,
        search: String?,
        sourceList: List<String>?,
        sort: MusicListSortState,
        listType: String? = null,
        listId: Int? = null,
        seriesIndexId: Int? = null,
        artists: List<String>? = null,
        albums: List<String>? = null,
        timeoutSeconds: Long = 15,
    ): MusicListPagedResult {
        val effectivePage = if (page > 0) page else 1
        val effectivePageSize = if (pageSize > 0) pageSize else 30

        val body =
            mutableMapOf<String, Any?>(
                "page" to effectivePage,
                "page_size" to effectivePageSize,
                "sort_by" to sort.by.apiValue,
                "sort_order" to sort.order.apiValue,
            )

        val q = search?.trim().orEmpty()
        if (q.isNotEmpty()) body["search"] = q
        if (isFavorite) body["is_favorite"] = 1
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList
        val lt = listType?.trim().orEmpty()
        if (lt.isNotEmpty()) body["listType"] = lt
        val lid = listId ?: 0
        if (lid > 0) body["list_id"] = lid
        val sid = seriesIndexId ?: 0
        if (sid > 0) body["series_index_id"] = sid
        if (!artists.isNullOrEmpty()) body["artists"] = artists
        if (!albums.isNullOrEmpty()) body["albums"] = albums

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/music/list",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return MusicListPagedResult.empty
        val items = parseMusicItems(data["items"])
        val pagination = parsePagination(data["pagination"])
        val validPaths = parseValidPaths(data["validPaths"] ?: data["valid_paths"])
        return MusicListPagedResult(items = items, pagination = pagination, validPaths = validPaths)
    }

    suspend fun getDetail(
        filePath: String,
        timeoutSeconds: Long = 15,
    ): MusicDetailResult? {
        val p = filePath.trim()
        if (p.isEmpty()) return null
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/music/detail/get",
                body = mapOf("file_path" to p),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val itemMap = data["item"] as? Map<*, *>
        val lyrics = data["lyrics"]?.toString()?.trim().orEmpty()
        val lyricsGetState = parseInt(itemMap?.get("lyrics_get_state") ?: itemMap?.get("lyricsGetState"))
        val item = itemMap?.let { parseMusicItem(it) }
        return MusicDetailResult(item = item, lyrics = lyrics, lyricsGetState = lyricsGetState)
    }

    data class MusicDetailResult(
        val item: MusicListItem?,
        val lyrics: String,
        val lyricsGetState: Int,
    )

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

    private fun parseLong(v: Any?): Long {
        return when (v) {
            null -> 0L
            is Number -> v.toLong()
            else -> v.toString().trim().removeSuffix(".0").toLongOrNull() ?: 0L
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

    private fun parseMusicItems(v: Any?): List<MusicListItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            parseMusicItem(map)
        }.filter { it.id > 0 }
    }

    private fun parseMusicItem(map: Map<*, *>): MusicListItem? {
        val id = parseInt(map["id"])
        if (id <= 0) return null

        fun parseNullableInt(v: Any?): Int? {
            val n = parseInt(v)
            return if (n == 0) null else n
        }

        val isFavorite = parseBool(map["is_favorite"] ?: map["isFavorite"])
        val isFromFile = parseBool(map["is_from_file"] ?: map["isFromFile"])

        return MusicListItem(
            id = id,
            path = parseString(map["path"]),
            filename = parseString(map["filename"]),
            fileHash = parseString(map["file_hash"] ?: map["fileHash"]),
            title = parseString(map["title"]),
            artist = parseString(map["artist"]),
            album = parseString(map["album"]),
            year = parseString(map["year"]),
            genre = parseString(map["genre"]),
            duration = parseInt(map["duration"]),
            size = parseLong(map["size"]),
            ext = parseString(map["ext"]),
            hasInnerCover = parseInt(map["has_inner_cover"] ?: map["hasInnerCover"]),
            showType = parseString(map["show_type"] ?: map["showType"]),
            musicCount = parseInt(map["music_count"] ?: map["musicCount"]),
            isFavorite = isFavorite,
            isFromFile = isFromFile,
            ctime = map["ctime"]?.toString(),
            mtime = map["mtime"]?.toString(),
            birthtime = map["birthtime"]?.toString(),
            firstFilePath = parseString(map["first_file_path"] ?: map["firstFilePath"]),
            fullPath = parseString(map["full_path"] ?: map["fullPath"]),
            bitrate = parseNullableInt(map["bitrate"]),
            sampleRate = parseNullableInt(map["sample_rate"] ?: map["sampleRate"]),
            bitDepth = parseNullableInt(map["bit_depth"] ?: map["bitDepth"]),
        )
    }

    private fun parsePagination(v: Any?): MusicListPagination {
        val map = v as? Map<*, *> ?: return MusicListPagination.empty
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val limit = parseInt(map["limit"]).takeIf { it > 0 } ?: 30
        val totalPages = parseInt(map["totalPages"])
        val hasNextPage = (map["hasNextPage"] as? Boolean) ?: parseBool(map["hasNextPage"])
        val hasPrevPage = (map["hasPrevPage"] as? Boolean) ?: parseBool(map["hasPrevPage"])
        return MusicListPagination(
            total = total,
            page = page,
            limit = limit,
            totalPages = totalPages,
            hasNextPage = hasNextPage,
            hasPrevPage = hasPrevPage,
        )
    }

    private fun parseValidPaths(v: Any?): List<MusicListPathItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            when (raw) {
                is String -> {
                    val p = raw.trim()
                    if (p.isEmpty()) null else MusicListPathItem(path = p, valid = true)
                }
                is Map<*, *> -> {
                    val path = raw["path"]?.toString()?.trim().orEmpty()
                    if (path.isEmpty()) return@mapNotNull null
                    val valid = raw["valid"] as? Boolean ?: parseBool(raw["valid"])
                    MusicListPathItem(path = path, valid = valid)
                }
                else -> null
            }
        }
    }
}

object MusicGroupApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun listAlbumOrArtistPaged(
        keyType: String,
        page: Int,
        pageSize: Int,
        search: String?,
        sourceList: List<String>?,
        sort: MusicGroupSortState,
        timeoutSeconds: Long = 15,
    ): MusicGroupPagedResult {
        val kt = keyType.trim().lowercase()
        val endpoint =
            if (kt == "artist") {
                "/api/music/artist/list"
            } else {
                "/api/music/album/list"
            }
        val effectivePage = if (page > 0) page else 1
        val effectivePageSize = if (pageSize > 0) pageSize else 30
        val body =
            mutableMapOf<String, Any?>(
                "page" to effectivePage,
                "page_size" to effectivePageSize,
                "sort_by" to sort.by.apiValue,
                "sort_order" to sort.order.apiValue,
            )
        val q = search?.trim().orEmpty()
        if (q.isNotEmpty()) body["search"] = q
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = endpoint,
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return MusicGroupPagedResult.empty
        val items = parseItems(kt, data["items"])
        val pagination = parsePagination(data["pagination"])
        val validPaths = parseValidPaths(data["validPaths"] ?: data["valid_paths"])
        return MusicGroupPagedResult(items = items, pagination = pagination, validPaths = validPaths)
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

    private fun parsePagination(v: Any?): MusicListPagination {
        val map = v as? Map<*, *> ?: return MusicListPagination.empty
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val limit = parseInt(map["limit"]).takeIf { it > 0 } ?: 30
        val totalPages = parseInt(map["totalPages"])
        val hasNextPage = (map["hasNextPage"] as? Boolean) ?: parseBool(map["hasNextPage"])
        val hasPrevPage = (map["hasPrevPage"] as? Boolean) ?: parseBool(map["hasPrevPage"])
        return MusicListPagination(
            total = total,
            page = page,
            limit = limit,
            totalPages = totalPages,
            hasNextPage = hasNextPage,
            hasPrevPage = hasPrevPage,
        )
    }

    private fun parseValidPaths(v: Any?): List<MusicListPathItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            when (raw) {
                is String -> {
                    val p = raw.trim()
                    if (p.isEmpty()) null else MusicListPathItem(path = p, valid = true)
                }
                is Map<*, *> -> {
                    val path = raw["path"]?.toString()?.trim().orEmpty()
                    if (path.isEmpty()) return@mapNotNull null
                    val valid = raw["valid"] as? Boolean ?: parseBool(raw["valid"])
                    MusicListPathItem(path = path, valid = valid)
                }
                else -> null
            }
        }
    }

    private fun parseItems(keyType: String, v: Any?): List<MusicGroupItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val name = map["name"]?.toString()?.trim().orEmpty()
            if (name.isEmpty()) return@mapNotNull null
            val firstFilePath = (map["first_file_path"] ?: map["firstFilePath"])?.toString()?.trim().orEmpty()
            val indexCount = parseInt(map["index_count"])
            MusicGroupItem(
                keyType = keyType,
                name = name,
                firstFilePath = firstFilePath,
                indexCount = indexCount,
            )
        }
    }
}

object MusicPlaylistApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun listPlaylistsPaged(
        page: Int,
        pageSize: Int,
        search: String?,
        sort: MusicPlaylistSortState,
        timeoutSeconds: Long = 15,
    ): MusicPlaylistPagedResult {
        val effectivePage = if (page > 0) page else 1
        val effectivePageSize = if (pageSize > 0) pageSize else 30
        val body =
            mutableMapOf<String, Any?>(
                "page" to effectivePage,
                "page_size" to effectivePageSize,
                "sort_by" to sort.by.apiValue,
                "sort_order" to sort.order.apiValue,
            )
        val q = search?.trim().orEmpty()
        if (q.isNotEmpty()) body["search"] = q

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/music/playlist/list",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return MusicPlaylistPagedResult.empty
        val items = parsePlaylists(data["items"])
        val pagination = parsePagination(data["pagination"])
        return MusicPlaylistPagedResult(items = items, pagination = pagination)
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

    private fun parsePagination(v: Any?): MusicListPagination {
        val map = v as? Map<*, *> ?: return MusicListPagination.empty
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val limit = parseInt(map["limit"]).takeIf { it > 0 } ?: 30
        val totalPages = parseInt(map["totalPages"])
        val hasNextPage = (map["hasNextPage"] as? Boolean) ?: parseBool(map["hasNextPage"])
        val hasPrevPage = (map["hasPrevPage"] as? Boolean) ?: parseBool(map["hasPrevPage"])
        return MusicListPagination(
            total = total,
            page = page,
            limit = limit,
            totalPages = totalPages,
            hasNextPage = hasNextPage,
            hasPrevPage = hasPrevPage,
        )
    }

    private fun parsePlaylists(v: Any?): List<MusicPlaylistItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"])
            if (id <= 0) return@mapNotNull null
            val uid = parseInt(map["uid"])
            val name = map["name"]?.toString()?.trim().orEmpty()
            val createTime = (map["create_time"] ?: map["createTime"])?.toString()?.trim().orEmpty()
            val previewsRaw = map["previews"] as? List<*> ?: emptyList<Any?>()
            val previews =
                previewsRaw.mapNotNull { p ->
                    val m = p as? Map<*, *> ?: return@mapNotNull null
                    parsePreviewMusicItem(m)
                }
            MusicPlaylistItem(id = id, uid = uid, name = name, createTime = createTime, previews = previews)
        }
    }

    private fun parsePreviewMusicItem(map: Map<*, *>): MusicListItem? {
        val id = parseInt(map["id"])
        if (id <= 0) return null

        fun parseNullableInt(v: Any?): Int? {
            val n = parseInt(v)
            return if (n == 0) null else n
        }

        val isFavorite = parseBool(map["is_favorite"] ?: map["isFavorite"])
        val isFromFile = parseBool(map["is_from_file"] ?: map["isFromFile"])

        fun parseLong(v: Any?): Long {
            return when (v) {
                null -> 0L
                is Number -> v.toLong()
                else -> v.toString().trim().removeSuffix(".0").toLongOrNull() ?: 0L
            }
        }

        fun parseString(v: Any?): String = v?.toString()?.trim().orEmpty()

        return MusicListItem(
            id = id,
            path = parseString(map["path"]),
            filename = parseString(map["filename"]),
            fileHash = parseString(map["file_hash"] ?: map["fileHash"]),
            title = parseString(map["title"]),
            artist = parseString(map["artist"]),
            album = parseString(map["album"]),
            year = parseString(map["year"]),
            genre = parseString(map["genre"]),
            duration = parseInt(map["duration"]),
            size = parseLong(map["size"]),
            ext = parseString(map["ext"]),
            hasInnerCover = parseInt(map["has_inner_cover"] ?: map["hasInnerCover"]),
            showType = parseString(map["show_type"] ?: map["showType"]),
            musicCount = parseInt(map["music_count"] ?: map["musicCount"]),
            isFavorite = isFavorite,
            isFromFile = isFromFile,
            ctime = map["ctime"]?.toString(),
            mtime = map["mtime"]?.toString(),
            birthtime = map["birthtime"]?.toString(),
            firstFilePath = parseString(map["first_file_path"] ?: map["firstFilePath"]),
            fullPath = parseString(map["full_path"] ?: map["fullPath"]),
            bitrate = parseNullableInt(map["bitrate"]),
            sampleRate = parseNullableInt(map["sample_rate"] ?: map["sampleRate"]),
            bitDepth = parseNullableInt(map["bit_depth"] ?: map["bitDepth"]),
        )
    }
}

object MusicLyricApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    data class LyricSearchItem(
        val id: String,
        val source: String,
        val title: String,
        val album: String,
        val artist: String,
        val durationMs: Int,
        val preview: String,
        val lrc: String,
    )

    suspend fun search(
        keyword: String,
        timeoutSeconds: Long = 15,
    ): List<LyricSearchItem> {
        val q = keyword.trim()
        if (q.isEmpty()) return emptyList()
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/music/lyric/search",
                body = mapOf("keyword" to q),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val dataAny = unwrapDataAny(raw) ?: return emptyList()
        val list = dataAny as? List<*> ?: return emptyList()
        return list.mapNotNull { it as? Map<*, *> }.map { m ->
            LyricSearchItem(
                id = m["id"]?.toString()?.trim().orEmpty(),
                source = m["source"]?.toString()?.trim().orEmpty(),
                title = m["title"]?.toString()?.trim().orEmpty(),
                album = m["album"]?.toString()?.trim().orEmpty(),
                artist = m["artist"]?.toString()?.trim().orEmpty(),
                durationMs = parseInt(m["duration"]),
                preview = m["preview"]?.toString()?.trim().orEmpty(),
                lrc = m["lrc"]?.toString()?.trim().orEmpty(),
            )
        }
    }

    suspend fun setLyric(
        musicPath: String,
        lrc: String,
        timeoutSeconds: Long = 15,
    ): Boolean {
        val p = musicPath.trim()
        val lyric = lrc
        if (p.isEmpty()) return false
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/music/lyric/set",
                body = mapOf("music_path" to p, "lrc" to lyric),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val success = raw["success"] as? Boolean
        if (success != null) return success == true
        return true
    }

    private fun unwrapDataAny(raw: Map<String, Any?>): Any? {
        val success = raw["success"] as? Boolean
        if (success != null) {
            if (success != true) return null
            return raw["data"]
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
}

object MusicFavoriteApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun setFavorite(
        indexId: Int,
        favorite: Boolean,
        timeoutSeconds: Long = 12,
    ): Boolean {
        val id = indexId.takeIf { it > 0 } ?: return false
        val path = if (favorite) "/api/music/favorite/add" else "/api/music/favorite/remove"
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = path,
                body = mapOf("index_id" to id),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val success = raw["success"] as? Boolean
        if (success != null) return success == true
        return true
    }
}
