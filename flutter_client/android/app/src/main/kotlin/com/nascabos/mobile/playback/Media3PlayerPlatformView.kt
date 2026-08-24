package com.nascabos.mobile.playback

import android.content.Context
import android.view.View
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.platform.PlatformView

class Media3PlayerPlatformView(
    context: Context,
    private val viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView {
    private val playerView: PlayerView = PlayerView(context)

    init {
        EventChannel(messenger, "com.nascabos/playback_events/$viewId")
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        Media3PlaybackHost.registerEventSink(viewId, events)
                    }

                    override fun onCancel(arguments: Any?) {
                        Media3PlaybackHost.registerEventSink(viewId, null)
                    }
                },
            )
        val session = Media3PlaybackHost.getOrCreateSession(context, viewId)
        session.attachPlayerView(playerView)
        Media3PlaybackHost.startProgressTicker(viewId)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        Media3PlaybackHost.releasePlayer(viewId)
    }
}
