package com.nascabos.tv.modules.photo.timeline

import com.nascabos.tv.core.api.ApiController

object PhotoTimelineApiService {
    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun getTimelineDateList(
        sort: String,
        fileType: String?,
        sourceList: List<String>?,
        albumId: Int? = null,
        collectionId: Int? = null,
        smartAlbumId: Int? = null,
        listType: String? = null,
        loadTheDay: Boolean? = null,
        timeoutSeconds: Long = 15,
    ): PhotoTimelineDateListResult? {
        val body = mutableMapOf<String, Any?>(
            "sort" to sort.trim().ifEmpty { "desc" },
        )
        val ft = fileType?.trim().orEmpty()
        if (ft.isNotEmpty()) body["fileType"] = ft
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList
        val aid = albumId ?: 0
        val cid = collectionId ?: 0
        val sid = smartAlbumId ?: 0
        if (aid > 0) body["album_id"] = aid
        if (cid > 0) body["collection_id"] = cid
        if (sid > 0) body["smart_album_id"] = sid
        val lt = listType?.trim().orEmpty()
        if (lt.isNotEmpty()) body["list_type"] = lt
        if (loadTheDay == true) body["loadTheDay"] = true

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/timeline/dates",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val items = parseDateItems(data["items"])
        val validPaths = parseValidPaths(data["validPaths"] ?: data["valid_paths"])
        return PhotoTimelineDateListResult(items = items, validPaths = validPaths)
    }

    suspend fun getTimelinePhotoList(
        sort: String,
        fileType: String?,
        startTime: Long,
        endTime: Long,
        sourceList: List<String>?,
        albumId: Int? = null,
        collectionId: Int? = null,
        smartAlbumId: Int? = null,
        listType: String? = null,
        loadTheDay: Boolean? = null,
        timeoutSeconds: Long = 30,
    ): PhotoTimelinePhotoListResult? {
        val body = mutableMapOf<String, Any?>(
            "sort" to sort.trim().ifEmpty { "desc" },
            "startTime" to startTime,
            "endTime" to endTime,
        )
        val ft = fileType?.trim().orEmpty()
        if (ft.isNotEmpty()) body["fileType"] = ft
        if (!sourceList.isNullOrEmpty()) body["sourceList"] = sourceList
        val aid = albumId ?: 0
        val cid = collectionId ?: 0
        val sid = smartAlbumId ?: 0
        if (aid > 0) body["album_id"] = aid
        if (cid > 0) body["collection_id"] = cid
        if (sid > 0) body["smart_album_id"] = sid
        val lt = listType?.trim().orEmpty()
        if (lt.isNotEmpty()) body["list_type"] = lt
        if (loadTheDay == true) body["loadTheDay"] = true

        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/timeline/photos",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val photoList = parsePhotoItems(data["photoList"])
        val dateInfoList = parseDateInfoItems(data["dateInfoList"])
        return PhotoTimelinePhotoListResult(photoList = photoList, dateInfoList = dateInfoList)
    }

    suspend fun getTimelineYearList(
        timeoutSeconds: Long = 15,
    ): PhotoTimelineYearListResult? {
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/timeline/years",
                body = emptyMap<String, Any?>(),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val items = parseYearItems(data["items"])
        return PhotoTimelineYearListResult(items = items)
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

    private fun parseDateItems(v: Any?): List<PhotoTimelineDateItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val date = parseString(map["original_date"])
            if (date.isEmpty()) return@mapNotNull null
            val count = parseInt(map["date_photo_count"])
            PhotoTimelineDateItem(originalDate = date, count = count)
        }
    }

    private fun parseValidPaths(v: Any?): List<PhotoTimelinePathItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            when (raw) {
                is String -> {
                    val p = raw.trim()
                    if (p.isEmpty()) null else PhotoTimelinePathItem(path = p, valid = true)
                }
                is Map<*, *> -> {
                    val p = parseString(raw["path"])
                    if (p.isEmpty()) return@mapNotNull null
                    val valid = (raw["valid"] as? Boolean) ?: parseBool(raw["valid"])
                    PhotoTimelinePathItem(path = p, valid = valid)
                }
                else -> null
            }
        }
    }

    private fun parsePhotoItems(v: Any?): List<PhotoTimelinePhotoItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val id = parseInt(map["id"])
            if (id <= 0) return@mapNotNull null

            val originalDate = parseString(map["original_date"])
            val path = parseString(map["path"])
            val filename = parseString(map["filename"])
            val size = parseInt(map["size"] ?: map["file_size"])
            val isLvp = parseInt(map["is_lvp"])
            val type = parseInt(map["type"])
            val width = parseInt(map["width"])
            val height = parseInt(map["height"])
            val originalTime = parseString(map["original_time"])
            val fullPath = parseString(map["fullpath"] ?: map["full_path"])
            val duration = parseInt(map["duration"])
            val fileHash = parseString(map["file_hash"])
            val isFavorite = parseInt(map["is_favorite"]) == 1 || parseBool(map["is_favorite"])
            val liveFilename = parseString(map["live_filename"])
            val rawFilename = parseString(map["raw_filename"])
            val rawShowExt = parseString(map["raw_show_ext"])

            PhotoTimelinePhotoItem(
                id = id,
                path = path,
                filename = filename,
                size = size,
                isLvp = isLvp,
                type = type,
                width = width,
                height = height,
                originalDate = originalDate,
                originalTime = originalTime,
                fullPath = fullPath,
                duration = duration,
                fileHash = fileHash,
                isFavorite = isFavorite,
                liveFilename = liveFilename,
                rawFilename = rawFilename,
                rawShowExt = rawShowExt,
            )
        }
    }

    private fun parseDateInfoItems(v: Any?): List<PhotoTimelineDateInfo> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val date = parseString(map["original_date"])
            if (date.isEmpty()) return@mapNotNull null
            val geo = parseString(map["geo"])
            val camera = parseString(map["camera"])
            PhotoTimelineDateInfo(originalDate = date, geo = geo, camera = camera)
        }
    }

    private fun parseYearItems(v: Any?): List<PhotoTimelineYearItem> {
        val list = v as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            val year = parseInt(map["year"])
            if (year <= 0) return@mapNotNull null
            val count = parseInt(map["count"])
            val coverMap = map["cover"] as? Map<*, *> ?: emptyMap<String, Any?>()
            val cover = parsePhotoItems(listOf(coverMap)).firstOrNull()
            if (cover == null) return@mapNotNull null
            PhotoTimelineYearItem(year = year, count = count, cover = cover)
        }
    }

    /** 切换单张收藏状态，返回新的 is_favorite 或 null（失败） */
    suspend fun toggleFavorite(fileHash: String, timeoutSeconds: Long = 10): Boolean? {
        if (fileHash.isBlank()) return null
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/favorite/toggle",
                body = mapOf("file_hash" to fileHash.trim()),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        return parseBool(data["is_favorite"])
    }

    /** 批量设置收藏状态 */
    suspend fun batchFavorite(fileHashes: List<String>, isFavorite: Boolean, timeoutSeconds: Long = 15): Boolean {
        if (fileHashes.isEmpty()) return true
        val hashes = fileHashes.map { it.trim() }.filter { it.isNotEmpty() }
        if (hashes.isEmpty()) return true
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/favorite/batch",
                body = mapOf("file_hashes" to hashes, "is_favorite" to isFavorite),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        return raw["success"] == true
    }

    /** 批量放入回收站（服务端返回 success: true, data: null 时也视为成功） */
    suspend fun batchTrash(ids: List<Int>, timeoutSeconds: Long = 15): Boolean {
        if (ids.isEmpty()) return true
        val validIds = ids.filter { it > 0 }
        if (validIds.isEmpty()) return true
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/photo/trash/add",
                body = mapOf("ids" to validIds),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        return raw["success"] == true
    }
}
