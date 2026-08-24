package com.nascabos.mobile

import com.nascabos.mobile.playback.Media3PlayerViewFactory
import com.nascabos.mobile.playback.NascabPlaybackMethodHandler
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nascab_media3_player",
            Media3PlayerViewFactory(messenger),
        )
        NascabPlaybackMethodHandler.install(
            this,
            MethodChannel(messenger, "com.nascabos/playback"),
        )
    }
}
