package com.nascabos.tv.modules.video_player

import com.nascabos.tv.core.api.ApiController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object TvVideoPlayerApiService {
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private fun authHeaders(): Map<String, String> {
        val token = ApiController.accessToken.trim()
        if (token.isEmpty()) return emptyMap()
        return mapOf("Authorization" to "Bearer $token")
    }

    suspend fun searchSubtitles(
        filePath: String,
        searchType: String,
        keyword: String? = null,
        timeoutSeconds: Long = 25,
    ): List<TvSubtitleSearchItem> {
        val p = filePath.trim()
        if (p.isEmpty()) return emptyList()
        val body =
            buildMap<String, Any> {
                put("filePath", p)
                put("searchType", searchType.trim())
                val kw = keyword?.trim().orEmpty()
                if (kw.isNotEmpty()) put("keyword", kw)
            }
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/videoPlayer/searchSubtitle",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return emptyList()
        val itemsAny = data["items"]
        val items = (itemsAny as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
        return items.mapNotNull { m ->
            val surl = m["surl"]?.toString()?.trim().orEmpty()
            if (surl.isEmpty()) return@mapNotNull null
            TvSubtitleSearchItem(
                sname = m["sname"]?.toString()?.trim().orEmpty(),
                displayName = m["displayName"]?.toString()?.trim().orEmpty(),
                language = m["language"]?.toString()?.trim().orEmpty(),
                ext = m["ext"]?.toString()?.trim().orEmpty(),
                surl = surl,
            )
        }
    }

    suspend fun downloadSearchedSubtitle(
        filePath: String,
        surl: String,
        sname: String? = null,
        language: String? = null,
        timeoutSeconds: Long = 60,
    ): TvDownloadedSubtitle? {
        val p = filePath.trim()
        val url = surl.trim()
        if (p.isEmpty() || url.isEmpty()) return null
        val body =
            buildMap<String, Any> {
                put("filePath", p)
                put("surl", url)
                val name = sname?.trim().orEmpty()
                if (name.isNotEmpty()) put("sname", name)
                val lang = language?.trim().orEmpty()
                if (lang.isNotEmpty()) put("language", lang)
            }
        val raw =
            ApiController.postJsonMap(
                baseUrl = ApiController.baseUrl,
                path = "/api/videoPlayer/downloadSearchedSubtitle",
                body = body,
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val savedPath = data["path"]?.toString()?.trim().orEmpty()
        val filename = data["filename"]?.toString()?.trim().orEmpty()
        if (savedPath.isEmpty() || filename.isEmpty()) return null
        return TvDownloadedSubtitle(path = savedPath, filename = filename)
    }

    suspend fun getInfo(
        filePath: String,
        ignoreFindSub: Int = 1,
        timeoutSeconds: Long = 25,
    ): TvVideoPlayerInfo? {
        val p = filePath.trim()
        if (p.isEmpty()) return null
        val ignore = if (ignoreFindSub == 0) 0 else 1
        val raw =
            ApiController.requestJsonMap(
                baseUrl = ApiController.baseUrl,
                path =
                    "/api/videoPlayer/info?filePath=${java.net.URLEncoder.encode(p, "UTF-8")}&ignoreFindSub=$ignore",
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        val data = unwrapData(raw) ?: return null
        val durationSeconds = parseInt(data["duration"]).takeIf { it > 0 }
        val openSkipMap = data["openSkip"] as? Map<*, *>
        val openSkip =
            if (openSkipMap == null) {
                null
            } else {
                val startSec = parseInt(openSkipMap["startSec"] ?: openSkipMap["start_sec"]).coerceAtLeast(0)
                val endSec = parseInt(openSkipMap["endSec"] ?: openSkipMap["end_sec"]).coerceAtLeast(0)
                if (startSec <= 0 && endSec <= 0) null else TvOpenSkip(startSec = startSec, endSec = endSec)
            }

        val streamsAny = data["streams"]
        val streams = (streamsAny as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
        val localDetected = streams.any { isDolbyVisionVideoStream(it) }
        val serverDetected = parseBoolean(data["isDolbyVision"]) == true
        val isDolbyVision = localDetected || serverDetected
        android.util.Log.d(
            "TvVideoPlayer",
            "dolbyVision detect: local=$localDetected server=$serverDetected final=$isDolbyVision path=${p.takeLast(80)}",
        )

        val audioTracks = ArrayList<TvAudioTrack>()
        val subtitleTracks = ArrayList<TvSubtitleTrack>()

        var audioOrder = 0
        var subtitleOrder = 0
        for (s in streams) {
            val codec = s["codec_type"]?.toString()?.trim()?.lowercase().orEmpty()
            if (codec == "audio") {
                val tags = s["tags"] as? Map<*, *>
                val lang = tags?.get("language")?.toString()?.ifBlank { "und" } ?: "und"
                val title =
                    tags?.get("title")?.toString()?.trim()?.ifEmpty { null }
                        ?: s["codec_name"]?.toString()?.trim().orEmpty().ifEmpty { "audio" }
                val idx = parseInt(s["index"])
                val label = "Audio $idx ($lang) - $title"
                audioTracks += TvAudioTrack(label = label, mapIndex = audioOrder)
                audioOrder++
            } else if (codec == "subtitle") {
                val tags = s["tags"] as? Map<*, *>
                val lang = tags?.get("language")?.toString()?.ifBlank { "und" } ?: "und"
                val title =
                    tags?.get("title")?.toString()?.trim()?.ifEmpty { null }
                        ?: s["codec_name"]?.toString()?.trim().orEmpty().ifEmpty { "sub" }
                val label = "($lang) $title"
                val codecName = s["codec_name"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                subtitleTracks +=
                    TvSubtitleTrack(
                        label = label,
                        mapIndex = subtitleOrder,
                        isExternal = false,
                        externalPath = null,
                        codecName = codecName,
                    )
                subtitleOrder++
            }
        }

        val extAny = data["externalSubtitles"]
        val extSubs = (extAny as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
        val extTracks =
            extSubs.mapNotNull { m ->
                val path = m["path"]?.toString()?.trim().orEmpty()
                if (path.isEmpty()) return@mapNotNull null
                val filename = m["filename"]?.toString()?.trim().orEmpty().ifEmpty { path }
                TvSubtitleTrack(label = filename, mapIndex = null, isExternal = true, externalPath = path)
            }

        val prefMap = data["preference"] as? Map<*, *>
        val pref =
            if (prefMap == null) {
                null
            } else {
                val pos = parseInt(prefMap["playback_position"]).coerceAtLeast(0)
                val audioLabel = prefMap["audio_label"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                val subtitleLabel = prefMap["subtitle_label"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                if (pos <= 0 && audioLabel == null && subtitleLabel == null) null else TvPlayerPreference(pos, audioLabel, subtitleLabel)
            }

        return TvVideoPlayerInfo(
            durationSeconds = durationSeconds,
            audioTracks = audioTracks,
            subtitleTracks = extTracks + subtitleTracks,
            preference = pref,
            openSkip = openSkip,
            isDolbyVision = isDolbyVision,
        )
    }

    suspend fun savePreference(
        filePath: String,
        playbackPositionSeconds: Int,
        audioLabel: String?,
        subtitleLabel: String?,
        timeoutSeconds: Long = 15,
    ) {
        val p = filePath.trim()
        if (p.isEmpty()) return
        ApiController.postJsonMap(
            baseUrl = ApiController.baseUrl,
            path = "/api/videoPlayer/preference",
            body =
                mapOf(
                    "filePath" to p,
                    "playback_position" to playbackPositionSeconds.toString(),
                    "subtitle_label" to (subtitleLabel ?: ""),
                    "audio_label" to (audioLabel ?: ""),
                ),
            timeoutSeconds = timeoutSeconds,
            headers = authHeaders(),
        )
    }

    suspend fun stopTranscoding(
        playId: String,
        timeoutSeconds: Long = 10,
    ) {
        val id = playId.trim()
        if (id.isEmpty()) return
        ApiController.postJsonMap(
            baseUrl = ApiController.baseUrl,
            path = "/api/videoPlayer/stop",
            body = mapOf("playId" to id),
            timeoutSeconds = timeoutSeconds,
            headers = authHeaders(),
        )
    }

    fun stopTranscodingAsync(
        playId: String,
        timeoutSeconds: Long = 10,
    ) {
        val id = playId.trim()
        if (id.isEmpty()) return
        scope.launch {
            runCatching { stopTranscoding(id, timeoutSeconds = timeoutSeconds) }
        }
    }

    suspend fun fetchSubtitleVtt(
        filePath: String,
        subtitleIndex: Int?,
        subtitlePath: String?,
        timeoutSeconds: Long = 30,
    ): String? {
        val sb = StringBuilder("/api/videoPlayer/subtitle-vtt?")
        val extPath = subtitlePath?.trim().orEmpty()
        val idx = subtitleIndex ?: 0
        sb.append("subtitleIndex=").append(idx)
        if (extPath.isNotEmpty()) {
            sb.append("&subtitlePath=").append(java.net.URLEncoder.encode(extPath, "UTF-8"))
        } else {
            val p = filePath.trim()
            if (p.isNotEmpty()) {
                sb.append("&filePath=").append(java.net.URLEncoder.encode(p, "UTF-8"))
            }
        }
        val token = ApiController.accessToken.trim()
        if (token.isNotEmpty()) {
            sb.append("&accessToken=").append(java.net.URLEncoder.encode(token, "UTF-8"))
        }
        val bytes =
            ApiController.requestBytes(
                baseUrl = ApiController.baseUrl,
                path = sb.toString(),
                timeoutSeconds = timeoutSeconds,
                headers = authHeaders(),
            )
        if (bytes.isEmpty()) return null
        return bytes.toString(Charsets.UTF_8).trim().takeIf { it.isNotEmpty() }
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
        if (v == null) return 0
        return when (v) {
            is Int -> v
            is Long -> v.toInt()
            is Double -> v.toInt()
            is Float -> v.toInt()
            is Number -> v.toInt()
            else -> v.toString().trim().toIntOrNull() ?: 0
        }
    }

    private fun parseBoolean(v: Any?): Boolean? {
        return when (v) {
            null -> null
            is Boolean -> v
            is Number -> v.toInt() != 0
            else -> {
                when (v.toString().trim().lowercase()) {
                    "true", "1", "yes" -> true
                    "false", "0", "no" -> false
                    else -> null
                }
            }
        }
    }

    private fun isDolbyVisionVideoStream(stream: Map<*, *>): Boolean {
        val codecType = stream["codec_type"]?.toString()?.trim()?.lowercase().orEmpty()
        if (codecType != "video") return false
        val codecTag = stream["codec_tag_string"]?.toString()?.trim()?.lowercase().orEmpty()
        if (codecTag == "dvhe" || codecTag == "dvh1") return true
        val tags = stream["tags"] as? Map<*, *>
        val encoder = tags?.get("encoder")?.toString().orEmpty()
        if (encoder.contains("dovi", ignoreCase = true)) return true
        val sideDataType = stream["side_data_type"]?.toString()?.trim()?.lowercase().orEmpty()
        if (sideDataType.contains("dovi") || sideDataType.contains("dolby")) return true
        if (parseInt(stream["dv_profile"]) > 0) return true
        if (parseInt(stream["rpu_present_flag"]) == 1) return true
        val codecName = stream["codec_name"]?.toString()?.trim()?.lowercase().orEmpty()
        if (codecName.contains("dolby") || codecName.contains("dovi")) return true
        val profile = stream["profile"]?.toString()?.trim()?.lowercase().orEmpty()
        if (profile.contains("dolby vision")) return true
        if (codecTag.contains("dvh1") || codecTag.contains("dvhe")) return true
        val codecTagHex = stream["codec_tag"]?.toString()?.trim()?.lowercase().orEmpty()
        if (codecTagHex.contains("dvh1") || codecTagHex.contains("dvhe")) return true
        val sideData =
            (stream["side_data_list"] as? List<*>)?.mapNotNull { it as? Map<*, *> }.orEmpty()
        return sideData.any { side ->
            val type = side["side_data_type"]?.toString()?.trim()?.lowercase().orEmpty()
            type.contains("dovi") || type.contains("dolby") ||
                parseInt(side["dv_profile"]) > 0 ||
                parseInt(side["rpu_present_flag"]) == 1
        }
    }
}
