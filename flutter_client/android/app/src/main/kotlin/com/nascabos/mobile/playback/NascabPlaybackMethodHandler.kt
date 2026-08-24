package com.nascabos.mobile.playback

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NascabPlaybackMethodHandler : MethodChannel.MethodCallHandler {
    private var appContext: Context? = null

    fun install(context: Context, channel: MethodChannel) {
        appContext = context.applicationContext
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("no_context", "Application context not ready", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val playerId = (args?.get("playerId") as? Number)?.toInt()
        if (playerId == null) {
            result.error("invalid_player", "playerId required", null)
            return
        }
        val session =
            Media3PlaybackHost.getSession(playerId)
                ?: Media3PlaybackHost.getOrCreateSession(ctx, playerId)

        when (call.method) {
            "create" -> {
                val url = args["url"]?.toString().orEmpty()
                if (url.isEmpty()) {
                    result.error("invalid_url", "url is empty", null)
                    return
                }
                val startMs = (args["startPositionMs"] as? Number)?.toLong() ?: 0L
                val headers = parseHeaders(args["headers"])
                val formatHint = args["formatHint"]?.toString()
                val externalSubtitleUrl = args["externalSubtitleUrl"]?.toString()
                val externalSubtitleSourcePath =
                    args["externalSubtitleSourcePath"]?.toString()
                val externalSubtitleLabel = args["externalSubtitleLabel"]?.toString()
                session.openUrl(
                    url,
                    startMs,
                    headers,
                    formatHint,
                    externalSubtitleUrl,
                    externalSubtitleSourcePath,
                    externalSubtitleLabel,
                )
                result.success(null)
            }
            "play" -> {
                session.player?.let { exo ->
                    exo.playWhenReady = true
                    exo.play()
                }
                result.success(null)
            }
            "pause" -> {
                session.player?.pause()
                result.success(null)
            }
            "seekTo" -> {
                val ms = (args["positionMs"] as? Number)?.toLong() ?: 0L
                session.player?.seekTo(ms)
                result.success(null)
            }
            "setVolume" -> {
                val vol = (args["volume"] as? Number)?.toFloat() ?: 1f
                session.player?.volume = vol.coerceIn(0f, 1f)
                result.success(null)
            }
            "setPlaybackSpeed" -> {
                val speed = (args["speed"] as? Number)?.toFloat() ?: 1f
                session.player?.setPlaybackSpeed(speed.coerceIn(0.5f, 2f))
                result.success(null)
            }
            "setLooping" -> {
                val looping = args["looping"] == true
                session.player?.repeatMode =
                    if (looping) {
                        androidx.media3.common.Player.REPEAT_MODE_ONE
                    } else {
                        androidx.media3.common.Player.REPEAT_MODE_OFF
                    }
                result.success(null)
            }
            "setAudioTracks" -> {
                val indices = (args["indices"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
                val mapIndex = indices?.firstOrNull() ?: 0
                session.applyAudioMapIndex(mapIndex)
                result.success(null)
            }
            "setSubtitleTracks" -> {
                val indices = (args["indices"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }
                if (indices.isNullOrEmpty()) {
                    session.disableSubtitles()
                } else {
                    session.applyInternalSubtitleMapIndex(indices.first())
                }
                result.success(null)
            }
            "setExternalSubtitle" -> {
                val url = args["url"]?.toString().orEmpty()
                if (url.isEmpty()) {
                    result.error("invalid_url", "subtitle url is empty", null)
                    return
                }
                val sourcePath = args["sourcePath"]?.toString()
                val label = args["label"]?.toString()
                session.applyExternalSubtitleUrl(url, sourcePath, label)
                result.success(null)
            }
            "dispose" -> {
                Media3PlaybackHost.releasePlayer(playerId)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun parseHeaders(raw: Any?): Map<String, String> {
        val map = raw as? Map<*, *> ?: return emptyMap()
        val out = LinkedHashMap<String, String>()
        for ((k, v) in map) {
            val key = k?.toString()?.trim().orEmpty()
            val value = v?.toString()?.trim().orEmpty()
            if (key.isNotEmpty() && value.isNotEmpty()) {
                out[key] = value
            }
        }
        return out
    }
}
