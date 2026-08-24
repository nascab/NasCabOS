package com.nascabos.tv.modules.video_player

object TvSubtitleBitmapUtil {
    fun isBitmapCodecName(codecName: String?): Boolean {
        val v = codecName?.trim()?.lowercase().orEmpty()
        return v == "pgssub" ||
            v == "hdmv_pgs_subtitle" ||
            v == "vobsub" ||
            v == "dvd_subtitle" ||
            v == "dvdsub" ||
            v == "dvb_subtitle" ||
            v == "xsub"
    }

    fun isBitmapExternalExtension(ext: String): Boolean {
        val v = ext.trim().lowercase()
        return v == ".sup" || v == ".sub" || v == ".idx"
    }
}
