package com.nascabos.tv.modules.video_player

import android.content.Context
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import androidx.media3.common.MimeTypes

object DolbyVisionHardwareUtil {
    @Volatile
    private var cachedSupported: Boolean? = null

    fun isHardwareSupported(context: Context): Boolean {
        cachedSupported?.let { return it }
        val result = detectHardwareSupported(context)
        cachedSupported = result
        return result
    }

    private fun detectHardwareSupported(context: Context): Boolean {
        if (hasDolbyVisionMediaCodec()) return true
        if (hasDolbyVisionDisplay(context)) return true
        return false
    }

    private fun hasDolbyVisionDisplay(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val display = context.display ?: return false
        val caps = display.hdrCapabilities ?: return false
        return caps.supportedHdrTypes.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)
    }

    private fun hasDolbyVisionMediaCodec(): Boolean {
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        for (codecInfo in codecList.codecInfos) {
            if (codecInfo.isEncoder) continue
            for (type in codecInfo.supportedTypes) {
                if (type.equals("video/dolby-vision", ignoreCase = true)) return true
            }
            val name = codecInfo.name.lowercase()
            if (!name.contains("dolby") && !name.contains("dovi")) continue
            for (type in codecInfo.supportedTypes) {
                if (type.equals(MimeTypes.VIDEO_H265, ignoreCase = true) ||
                    type.equals("video/hevc", ignoreCase = true)
                ) {
                    return true
                }
            }
        }
        return false
    }
}
