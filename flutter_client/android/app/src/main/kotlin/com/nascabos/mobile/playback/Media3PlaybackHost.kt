package com.nascabos.mobile.playback

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.EventChannel

object Media3PlaybackHost {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<Int, Media3PlayerSession>()
    private val eventSinks = mutableMapOf<Int, EventChannel.EventSink?>()

    fun registerEventSink(playerId: Int, sink: EventChannel.EventSink?) {
        eventSinks[playerId] = sink
        if (sink != null) {
            sessions[playerId]?.player?.let { emitState(playerId, it) }
        }
    }

    fun getOrCreateSession(context: Context, playerId: Int): Media3PlayerSession {
        return sessions.getOrPut(playerId) {
            Media3PlayerSession(context, playerId)
        }
    }

    fun getSession(playerId: Int): Media3PlayerSession? = sessions[playerId]

    fun releasePlayer(playerId: Int) {
        sessions.remove(playerId)?.release()
        eventSinks.remove(playerId)
    }

    fun emitState(playerId: Int, player: ExoPlayer) {
        val sink = eventSinks[playerId] ?: return
        val duration = player.duration.coerceAtLeast(0L)
        val position = player.currentPosition.coerceAtLeast(0L)
        val buffered = player.bufferedPosition.coerceAtLeast(0L)
        mainHandler.post {
            sink.success(
                mapOf(
                    "isInitialized" to
                        (duration > 0 || player.playbackState == Player.STATE_READY),
                    "isPlaying" to player.isPlaying,
                    "positionMs" to position,
                    "durationMs" to duration,
                    "bufferedPositionMs" to buffered,
                ),
            )
        }
    }

    fun emitError(playerId: Int, message: String) {
        val sink = eventSinks[playerId] ?: return
        mainHandler.post {
            sink.success(mapOf("error" to message))
        }
    }

    fun startProgressTicker(playerId: Int) {
        mainHandler.post(
            object : Runnable {
                override fun run() {
                    val exo = sessions[playerId]?.player
                    if (exo != null) {
                        emitState(playerId, exo)
                    }
                    mainHandler.postDelayed(this, 500L)
                }
            },
        )
    }
}
