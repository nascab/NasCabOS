package com.nascabos.tv.modules.video_player

data class TvPlaylistItem(
    val path: String,
    val name: String,
    val internalPath: String = "",
)

data class TvAudioTrack(
    val label: String,
    val mapIndex: Int,
)

data class TvSubtitleTrack(
    val label: String,
    val mapIndex: Int?,
    val isExternal: Boolean,
    val externalPath: String?,
    val codecName: String? = null,
)

data class TvSubtitleSearchItem(
    val sname: String,
    val displayName: String,
    val language: String,
    val ext: String,
    val surl: String,
)

data class TvDownloadedSubtitle(
    val path: String,
    val filename: String,
)

data class TvPlayerPreference(
    val playbackPositionSeconds: Int,
    val audioLabel: String?,
    val subtitleLabel: String?,
)

data class TvOpenSkip(
    val startSec: Int,
    val endSec: Int,
)

data class TvVideoPlayerInfo(
    val durationSeconds: Int?,
    val audioTracks: List<TvAudioTrack>,
    val subtitleTracks: List<TvSubtitleTrack>,
    val preference: TvPlayerPreference?,
    val openSkip: TvOpenSkip?,
    val isDolbyVision: Boolean,
)
