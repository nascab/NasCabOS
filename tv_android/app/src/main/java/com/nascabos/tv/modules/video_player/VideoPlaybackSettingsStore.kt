package com.nascabos.tv.modules.video_player

import android.content.Context
import com.nascabos.tv.R

object VideoPlaybackSettingsStore {
    const val PREFS_NAME = "video_playback_settings"
    const val KEY_DEFAULT_QUALITY = "default_quality"
    const val QUALITY_ORIGINAL = "original"

    val QUALITY_OPTIONS: List<String> =
        listOf(
            QUALITY_ORIGINAL,
            "4k_20m",
            "4k_15m",
            "4k_10m",
            "1080p_8m",
            "1080p_5m",
            "1080p_3m",
            "1080p_2m",
            "720p_3m",
            "720p_2m",
            "720p_1m",
            "480p_1m",
        )

    fun getDefaultQuality(context: Context): String {
        val saved =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_DEFAULT_QUALITY, QUALITY_ORIGINAL)
                ?.trim()
                .orEmpty()
        return saved.takeIf { it in QUALITY_OPTIONS } ?: QUALITY_ORIGINAL
    }

    fun setDefaultQuality(context: Context, quality: String) {
        val q = quality.trim().takeIf { it in QUALITY_OPTIONS } ?: return
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DEFAULT_QUALITY, q)
            .apply()
    }

    fun qualityLabel(context: Context, quality: String): String {
        return if (quality == QUALITY_ORIGINAL) {
            context.getString(R.string.player_quality_original)
        } else {
            quality.replace('_', ' ').uppercase()
        }
    }
}
