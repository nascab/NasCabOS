package com.nascabos.tv.modules.video.detail

import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.modules.video_player.TvPlaylistItem
import org.json.JSONArray
import org.json.JSONObject

object VideoDetailApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun getDetail(
        indexId: Int,
        timeoutSeconds: Long = 15,
    ): VideoDetailData? {
        val id = indexId.takeIf { it > 0 } ?: return null
        val raw =
            ApiController.requestJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/detail?index_id=$id",
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val itemMap = data["item"] as? Map<*, *> ?: return null
        val historyMap = data["history"] as? Map<*, *>
        val seasonListRaw = data["season_list"] as? List<*>
        val discContentsRaw = data["disc_contents"] as? List<*>
        val item = parseItem(itemMap) ?: return null
        val history = parseHistory(historyMap, fallbackDuration = item.durationSeconds)
        val seasons = parseSeasons(seasonListRaw)
        val discContents = parseDiscContents(discContentsRaw)
        return VideoDetailData(item = item, seasonList = seasons, discContents = discContents, history = history)
    }

    suspend fun getDiscContents(
        indexId: Int,
        timeoutSeconds: Long = 20,
    ): List<VideoDiscContentItem> {
        val id = indexId.takeIf { it > 0 } ?: return emptyList()
        val raw =
            ApiController.requestJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/discContents?index_id=$id",
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return emptyList()
        return parseDiscContents(data["items"] as? List<*>)
    }

    suspend fun getEpisodes(
        indexId: Int,
        page: Int = 1,
        pageSize: Int = 50,
        sortOrder: String = "asc",
        timeoutSeconds: Long = 20,
    ): VideoEpisodePagedResult {
        val id = indexId.takeIf { it > 0 } ?: return VideoEpisodePagedResult.empty
        val p = if (page > 0) page else 1
        val ps = pageSize.coerceIn(1, 200)
        val order = if (sortOrder.trim().lowercase() == "desc") "desc" else "asc"
        val raw =
            ApiController.requestJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/episodes?index_id=$id&page=$p&page_size=$ps&sort_order=$order",
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return VideoEpisodePagedResult.empty
        val list = data["items"] as? List<*> ?: emptyList<Any?>()
        val paginationMap = data["pagination"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val items = list.mapNotNull { (it as? Map<*, *>)?.let(::parseEpisodeItem) }
        val pagination = parseEpisodePagination(paginationMap)
        return VideoEpisodePagedResult(items = items, pagination = pagination)
    }

    suspend fun getTvPlayInfo(
        indexId: Int,
        timeoutSeconds: Long = 25,
    ): Pair<List<TvPlaylistItem>, Int> {
        val id = indexId.takeIf { it > 0 } ?: return emptyList<TvPlaylistItem>() to 0
        val raw =
            ApiController.requestJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/tvPlayInfo?index_id=$id",
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return emptyList<TvPlaylistItem>() to 0
        val list = data["playlist"] as? List<*> ?: emptyList<Any?>()
        val idx = parseInt(data["initialIndex"]).coerceAtLeast(0)
        val items =
            list.mapNotNull {
                val map = it as? Map<*, *> ?: return@mapNotNull null
                val p = parseString(map["path"])
                val name = parseString(map["name"])
                val internalPath = parseString(map["internalPath"]).ifEmpty { parseString(map["internal_path"]) }
                val safePath = p.ifEmpty { return@mapNotNull null }
                TvPlaylistItem(path = safePath, name = name, internalPath = internalPath)
            }
        return items to idx
    }

    fun buildDiscContentThumbApiPath(
        indexId: Int,
        internalPath: String,
        size: Int = 320,
    ): String {
        val id = indexId.takeIf { it > 0 } ?: return ""
        val internal = internalPath.trim()
        if (internal.isEmpty()) return ""
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append("/api/video/discContents/thumb")
        sb.append("?index_id=").append(id)
        sb.append("&internal_path=").append(enc(internal))
        if (size > 0) sb.append("&size=").append(size)
        if (token.isNotEmpty()) sb.append("&accessToken=").append(enc(token))
        return sb.toString()
    }

    suspend fun setFavorite(
        indexId: Int,
        favorite: Boolean,
        timeoutSeconds: Long = 12,
    ): Boolean {
        val id = indexId.takeIf { it > 0 } ?: return false
        val path = if (favorite) "/api/video/favorite/add" else "/api/video/favorite/remove"
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = path,
                body = mapOf("index_id" to id),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        return unwrapData(raw) != null
    }

    suspend fun scanIndex(
        indexId: Int,
        timeoutSeconds: Long = 12,
    ): Boolean {
        val id = indexId.takeIf { it > 0 } ?: return false
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/video/source/scan_index",
                body = mapOf("index_id" to id),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        return unwrapData(raw) != null
    }

    suspend fun deleteByPath(
        fullPath: String,
        deleteScrapeFiles: Boolean = true,
        timeoutSeconds: Long = 25,
    ): Boolean {
        val p = fullPath.trim()
        if (p.isEmpty()) return false
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/file/delete",
                body =
                    mapOf(
                        "paths" to listOf(p),
                        "recycle" to false,
                        "deleteScrapeFiles" to (if (deleteScrapeFiles) 1 else 0),
                    ),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        return unwrapData(raw) != null
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

    private fun parseString(v: Any?): String {
        return v?.toString()?.trim().orEmpty()
    }

    private fun enc(value: String): String = java.net.URLEncoder.encode(value, "UTF-8")

    private fun parseJsonPeople(v: Any?, role: String): List<VideoPerson> {
        val txt = v?.toString()?.trim().orEmpty()
        if (txt.isEmpty()) return emptyList()
        val arr =
            runCatching { JSONArray(txt) }.getOrNull()
                ?: runCatching {
                    val obj = JSONObject(txt)
                    obj.optJSONArray("items")
                }.getOrNull()
                ?: return emptyList()
        val out = ArrayList<VideoPerson>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val name = o.optString("name", "").trim()
            if (name.isEmpty()) continue
            val tmdbId = o.optString("tmdbId", "").trim()
            val thumb = o.optString("thumb", "").trim()
            out += VideoPerson(name = name, role = role, tmdbId = tmdbId, thumb = thumb)
        }
        return out
    }

    private fun parseItem(map: Map<*, *>): VideoDetailItem? {
        val id = parseInt(map["id"]).takeIf { it > 0 } ?: return null
        val mediaType = parseString(map["media_type"])
        val isFile = parseBool(map["is_file"])
        val path = parseString(map["path"])
        val filename = parseString(map["filename"])
        val fullPath = parseString(map["full_path"])
        val playFilePath = parseString(map["play_file_path"]).ifEmpty { parseString(map["playFilePath"]) }
        val firstFilePath = parseString(map["first_file_path"])
        val posterPath = parseString(map["poster_path"])
        val fanartPath = parseString(map["fanart_path"])
        val logoPath = parseString(map["logo_path"])
        val nfoName = parseString(map["nfo_name"])
        val nfoPlot = parseString(map["nfo_storyline"]).ifEmpty { parseString(map["nfo_plot"]) }
        val nfoYear = parseInt(map["nfo_year"])
        val nfoRegions = parseString(map["nfo_regions"])
        val nfoGenres = parseString(map["nfo_genres"])
        val duration = parseInt(map["duration"])
        val sizeBytes = parseLong(map["size"])
        val seasonCount = parseInt(map["season_count"])
        val episodeCount = parseInt(map["episod_count"]).takeIf { it > 0 } ?: parseInt(map["episode_count"])
        val isFavorite = parseBool(map["is_favorite"])
        val directors = parseJsonPeople(map["nfo_director_json"], role = "director")
        val actors = parseJsonPeople(map["nfo_actor_json"], role = "actor")
        return VideoDetailItem(
            id = id,
            mediaType = mediaType,
            isFile = isFile,
            path = path,
            filename = filename,
            fullPath = fullPath,
            playFilePath = playFilePath,
            firstFilePath = firstFilePath,
            posterPath = posterPath,
            fanartPath = fanartPath,
            logoPath = logoPath,
            nfoName = nfoName,
            nfoPlot = nfoPlot,
            nfoYear = nfoYear,
            nfoRegions = nfoRegions,
            nfoGenres = nfoGenres,
            durationSeconds = duration,
            sizeBytes = sizeBytes,
            seasonCount = seasonCount,
            episodeCount = episodeCount,
            isFavorite = isFavorite,
            directors = directors,
            actors = actors,
        )
    }

    private fun parseHistory(map: Map<*, *>?, fallbackDuration: Int): VideoHistory? {
        if (map == null) return null
        val pos = parseInt(map["playback_position"])
        val dur = parseInt(map["duration"]).takeIf { it > 0 } ?: fallbackDuration
        val last = map["last_watched_at"]?.toString()
        val ep = parseInt(map["episod_num"]).takeIf { it > 0 }
        if (pos <= 0 && dur <= 0 && (last == null || last.isBlank())) return null
        return VideoHistory(
            playbackPositionSeconds = pos.coerceAtLeast(0),
            durationSeconds = dur.coerceAtLeast(0),
            lastWatchedAt = last,
            episodeNum = ep,
        )
    }

    private fun parseSeasons(list: List<*>?): List<VideoSeasonItem> {
        val src = list ?: return emptyList()
        return src.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"]).takeIf { it > 0 } ?: return@mapNotNull null
            val name = parseString(map["nfo_name"]).ifEmpty { parseString(map["filename"]) }
            VideoSeasonItem(
                id = id,
                name = name,
                posterPath = parseString(map["poster_path"]),
                fanartPath = parseString(map["fanart_path"]),
                logoPath = parseString(map["logo_path"]),
                firstFilePath = parseString(map["first_file_path"]),
            )
        }
    }

    private fun parseEpisodeItem(map: Map<*, *>): VideoEpisodeItem? {
        val id = parseInt(map["id"]).takeIf { it > 0 } ?: return null
        val num = parseInt(map["episod_num"])
        val name = parseString(map["nfo_name"]).ifEmpty { parseString(map["filename"]) }
        val plot = parseString(map["nfo_storyline"]).ifEmpty { parseString(map["nfo_plot"]) }
        val full = parseString(map["full_path"])
        val durationSeconds = parseInt(map["duration"])
        val sizeBytes = parseLong(map["size"])
        return VideoEpisodeItem(
            id = id,
            displayIndex = num,
            episodeNum = num,
            name = name,
            plot = plot,
            fullPath = full,
            internalPath = "",
            apiThumbPath = "",
            posterPath = parseString(map["poster_path"]),
            fanartPath = parseString(map["fanart_path"]),
            logoPath = parseString(map["logo_path"]),
            durationSeconds = durationSeconds,
            sizeBytes = sizeBytes,
        )
    }

    private fun parseDiscContents(list: List<*>?): List<VideoDiscContentItem> {
        val src = list ?: return emptyList()
        return src.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val playlistRaw = map["playlist"] as? List<*>
            val playlist =
                playlistRaw.orEmpty().mapNotNull { item ->
                    val entry = item as? Map<*, *> ?: return@mapNotNull null
                    val path = parseString(entry["path"])
                    val internalPath = parseString(entry["internal_path"]).ifEmpty { parseString(entry["internalPath"]) }
                    if (path.isEmpty() && internalPath.isEmpty()) return@mapNotNull null
                    VideoDiscPlaylistItem(path = path, internalPath = internalPath)
                }
            val path = parseString(map["path"]).ifEmpty { playlist.firstOrNull()?.path.orEmpty() }
            val internalPath = parseString(map["internal_path"]).ifEmpty {
                parseString(map["internalPath"]).ifEmpty { playlist.firstOrNull()?.internalPath.orEmpty() }
            }
            if (path.isEmpty()) return@mapNotNull null
            VideoDiscContentItem(
                path = path,
                internalPath = internalPath,
                thumbnailPath = parseString(map["thumbnail_path"]).ifEmpty { parseString(map["thumbnailPath"]) },
                thumbnailInternalPath =
                    parseString(map["thumbnail_internal_path"]).ifEmpty {
                        parseString(map["thumbnailInternalPath"])
                    },
                title = parseString(map["title"]),
                displayName = parseString(map["display_name"]).ifEmpty { parseString(map["displayName"]) },
                durationSeconds = parseInt(map["duration"]),
                sizeBytes = parseLong(map["size"]),
                playlist = playlist,
            )
        }
    }

    private fun parseEpisodePagination(map: Map<*, *>): VideoEpisodePagination {
        val total = parseInt(map["total"])
        val page = parseInt(map["page"]).takeIf { it > 0 } ?: 1
        val limit = parseInt(map["limit"]).takeIf { it > 0 } ?: 50
        val totalPages = parseInt(map["totalPages"])
        val hasNext = parseBool(map["hasNextPage"])
        val hasPrev = parseBool(map["hasPrevPage"])
        return VideoEpisodePagination(
            total = total,
            page = page,
            limit = limit,
            totalPages = totalPages,
            hasNextPage = hasNext,
            hasPrevPage = hasPrev,
        )
    }
}
