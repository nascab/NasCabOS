package com.nascabos.mobile.playback

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.util.TypedValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView

/**
 * 单路 Media3 播放会话：直连服务端 URL（不经 Flutter 本地代理），音轨/字幕逻辑对齐 TV 端。
 */
class Media3PlayerSession(
    context: Context,
    val playerId: Int,
) {
    private val appContext = context.applicationContext
    private var trackSelector: DefaultTrackSelector = DefaultTrackSelector(appContext)
    var player: ExoPlayer? = null
        private set

    private var playerViewRef: PlayerView? = null
    private var requestHeaders: Map<String, String> = emptyMap()

    private var mainUrl: String? = null
    private var lastFormatHint: String? = null
    private var lastExternalSubtitleUrl: String? = null
    private var lastExternalSubtitleSourcePath: String? = null
    private var lastExternalSubtitleLabel: String? = null
    private var audioTrackRefs: List<Tracks.Group> = emptyList()
    private var subtitleTrackRefs: List<Tracks.Group> = emptyList()
    private var pendingAudioMapIndex: Int? = null
    private var pendingInternalSubtitleIndex: Int? = null
    private var pendingDisableSubtitles: Boolean = false
    private var extensionRendererMode: Int =
        DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
    private var triedSoftwareDecodeFallback: Boolean = false
    /** 硬解已失败：后续 openUrl 同 URL 直接走 FFmpeg 软解，避免 Flutter 重试又重置为硬解。 */
    private var videoSoftwareDecodeOnly: Boolean = false

    private fun buildRenderersFactory(
        rendererMode: Int,
        softwareVideoOnly: Boolean,
    ): DefaultRenderersFactory {
        val factory = DefaultRenderersFactory(appContext)
        if (softwareVideoOnly) {
            factory
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                .setEnableDecoderFallback(false)
                .setMediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
                    if (mimeType.startsWith("video/")) {
                        emptyList()
                    } else {
                        MediaCodecSelector.DEFAULT.getDecoderInfos(
                            mimeType,
                            requiresSecureDecoder,
                            requiresTunnelingDecoder,
                        )
                    }
                }
        } else {
            factory
                .setExtensionRendererMode(rendererMode)
                .setEnableDecoderFallback(true)
                .setMediaCodecSelector(MediaCodecSelector.DEFAULT)
        }
        return factory
    }

    private fun createExoPlayer(
        headers: Map<String, String>,
        rendererMode: Int,
        softwareVideoOnly: Boolean,
    ): ExoPlayer {
        val httpFactory =
            DefaultHttpDataSource.Factory()
                .setConnectTimeoutMs(30_000)
                .setReadTimeoutMs(60_000)
                .setAllowCrossProtocolRedirects(true)
        if (headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }
        val dataSourceFactory = DefaultDataSource.Factory(appContext, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
        val exo =
            ExoPlayer.Builder(appContext)
                .setRenderersFactory(buildRenderersFactory(rendererMode, softwareVideoOnly))
                .setTrackSelector(trackSelector)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()
        exo.trackSelectionParameters =
            exo.trackSelectionParameters
                .buildUpon()
                .setAudioOffloadPreferences(
                    TrackSelectionParameters.AudioOffloadPreferences.Builder()
                        .setAudioOffloadMode(
                            TrackSelectionParameters.AudioOffloadPreferences
                                .AUDIO_OFFLOAD_MODE_DISABLED,
                        )
                        .setIsSpeedChangeSupportRequired(true)
                        .build(),
                )
                .build()
        exo.addListener(
            object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    updateTrackRefs(tracks)
                    flushPendingTrackSelection()
                    maybeSelectExternalSidecarTextTrack()
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    Media3PlaybackHost.emitState(playerId, exo)
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    Media3PlaybackHost.emitState(playerId, exo)
                }

                override fun onPlayerError(error: PlaybackException) {
                    handlePlaybackError(error)
                }
            },
        )
        return exo
    }

    private fun ensurePlayer(
        headers: Map<String, String>,
        rendererMode: Int = extensionRendererMode,
        softwareVideoOnly: Boolean = videoSoftwareDecodeOnly,
    ): ExoPlayer {
        if (player != null &&
            headers == requestHeaders &&
            rendererMode == extensionRendererMode &&
            softwareVideoOnly == videoSoftwareDecodeOnly
        ) {
            return player!!
        }
        playerViewRef?.player = null
        player?.stop()
        player?.release()
        player = null
        requestHeaders = headers
        extensionRendererMode = rendererMode
        videoSoftwareDecodeOnly = softwareVideoOnly
        trackSelector = DefaultTrackSelector(appContext)
        val exo = createExoPlayer(headers, rendererMode, softwareVideoOnly)
        player = exo
        playerViewRef?.player = exo
        return exo
    }

    private fun isHlsOrTranscodeUrl(url: String): Boolean {
        return resolvePlaybackMimeType(url, lastFormatHint) == MimeTypes.APPLICATION_M3U8
    }

    private fun isDecoderRelatedError(error: PlaybackException): Boolean {
        when (error.errorCode) {
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            -> return true
        }
        var cause: Throwable? = error.cause
        while (cause != null) {
            val name = cause.javaClass.name
            if (name.contains("MediaCodec", ignoreCase = true) ||
                name.contains("Decoder", ignoreCase = true)
            ) {
                return true
            }
            cause = cause.cause
        }
        return false
    }

    /** 硬解失败后重建播放器，视频轨仅走 FFmpeg 扩展解码器。 */
    private fun trySoftwareDecodeFallback(): Boolean {
        if (triedSoftwareDecodeFallback) return false
        val url = mainUrl ?: return false
        if (isHlsOrTranscodeUrl(url)) return false

        triedSoftwareDecodeFallback = true
        videoSoftwareDecodeOnly = true
        val oldExo = player
        val positionMs = oldExo?.currentPosition?.coerceAtLeast(0L) ?: 0L
        val wasPlaying = oldExo?.isPlaying == true || oldExo?.playWhenReady == true
        val headers = requestHeaders
        val formatHint = lastFormatHint
        val subUrl = lastExternalSubtitleUrl

        playerViewRef?.player = null
        oldExo?.stop()
        oldExo?.release()
        player = null

        requestHeaders = headers
        extensionRendererMode = DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
        trackSelector = DefaultTrackSelector(appContext)
        val newExo =
            createExoPlayer(
                headers,
                extensionRendererMode,
                softwareVideoOnly = true,
            )
        player = newExo
        playerViewRef?.player = newExo

        val mediaItem =
            buildMediaItem(
                url,
                subUrl,
                formatHint,
                lastExternalSubtitleSourcePath,
                lastExternalSubtitleLabel,
            )
        newExo.setMediaItem(mediaItem, positionMs)
        newExo.prepare()
        newExo.playWhenReady = wasPlaying
        Media3PlaybackHost.emitState(playerId, newExo)
        return true
    }

    private fun handlePlaybackError(error: PlaybackException) {
        if (isDecoderRelatedError(error) && trySoftwareDecodeFallback()) {
            return
        }
        Media3PlaybackHost.emitError(
            playerId,
            error.message ?: "playback_error",
        )
    }

    fun attachPlayerView(playerView: PlayerView) {
        playerViewRef = playerView
        playerView.useController = false
        configureSubtitleView(playerView)
        player?.let { playerView.player = it }
    }

    private fun configureSubtitleView(playerView: PlayerView) {
        val subtitleView = playerView.subtitleView ?: return
        // 与转码 WebSubtitleOverlay 一致：忽略字幕文件内嵌字号（ASS 竖屏易过大），用统一字号。
        subtitleView.setApplyEmbeddedFontSizes(false)
        subtitleView.setApplyEmbeddedStyles(false)
        subtitleView.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW,
                Color.BLACK,
                null,
            ),
        )
        subtitleView.setViewType(SubtitleView.VIEW_TYPE_CANVAS)
        subtitleView.setFixedTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            resolveSubtitleTextSizeSp(),
        )
    }

    /** 对齐 Flutter WebSubtitleOverlay: (shortestSide / 28).clamp(14, 28) */
    private fun resolveSubtitleTextSizeSp(): Float {
        val dm = appContext.resources.displayMetrics
        val shortestSideDp = minOf(dm.widthPixels, dm.heightPixels) / dm.density
        return (shortestSideDp / 28f).coerceIn(14f, 28f)
    }

    fun openUrl(
        url: String,
        startPositionMs: Long = 0L,
        headers: Map<String, String> = emptyMap(),
        formatHint: String? = null,
        externalSubtitleUrl: String? = null,
        externalSubtitleSourcePath: String? = null,
        externalSubtitleLabel: String? = null,
    ) {
        val urlChanged = mainUrl != null && mainUrl != url
        if (urlChanged) {
            triedSoftwareDecodeFallback = false
            videoSoftwareDecodeOnly = false
        }
        mainUrl = url
        lastFormatHint = formatHint
        lastExternalSubtitleUrl = externalSubtitleUrl?.trim()?.takeIf { it.isNotEmpty() }
        lastExternalSubtitleSourcePath =
            externalSubtitleSourcePath?.trim()?.takeIf { it.isNotEmpty() }
        lastExternalSubtitleLabel = externalSubtitleLabel?.trim()?.takeIf { it.isNotEmpty() }

        val softwareVideo = videoSoftwareDecodeOnly
        val rendererMode =
            if (softwareVideo) {
                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
            } else {
                triedSoftwareDecodeFallback = false
                DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
            }
        val exo = ensurePlayer(headers, rendererMode, softwareVideo)
        val mediaItem =
            buildMediaItem(
                url,
                lastExternalSubtitleUrl,
                formatHint = formatHint,
                externalSubtitleSourcePath = lastExternalSubtitleSourcePath,
                externalSubtitleLabel = lastExternalSubtitleLabel,
            )
        exo.stop()
        exo.clearMediaItems()
        exo.setMediaItem(mediaItem, startPositionMs.coerceAtLeast(0L))
        exo.prepare()
        exo.playWhenReady = true
        Media3PlaybackHost.emitState(playerId, exo)
    }

    fun reloadKeepingPosition(
        externalSubtitleUrl: String?,
        externalSubtitleSourcePath: String? = null,
        externalSubtitleLabel: String? = null,
    ) {
        val url = mainUrl ?: return
        val exo = player ?: return
        val positionMs = exo.currentPosition.coerceAtLeast(0L)
        val wasPlaying = exo.isPlaying || exo.playWhenReady
        lastExternalSubtitleUrl = externalSubtitleUrl?.trim()?.takeIf { it.isNotEmpty() }
        lastExternalSubtitleSourcePath =
            externalSubtitleSourcePath?.trim()?.takeIf { it.isNotEmpty() }
                ?: lastExternalSubtitleSourcePath
        lastExternalSubtitleLabel =
            externalSubtitleLabel?.trim()?.takeIf { it.isNotEmpty() }
                ?: lastExternalSubtitleLabel
        val mediaItem =
            buildMediaItem(
                url,
                lastExternalSubtitleUrl,
                formatHint = lastFormatHint,
                externalSubtitleSourcePath = lastExternalSubtitleSourcePath,
                externalSubtitleLabel = lastExternalSubtitleLabel,
            )
        exo.stop()
        exo.clearMediaItems()
        exo.setMediaItem(mediaItem, positionMs)
        exo.prepare()
        exo.playWhenReady = wasPlaying
        Media3PlaybackHost.emitState(playerId, exo)
    }

    private fun buildMediaItem(
        url: String,
        externalSubtitleUrl: String?,
        formatHint: String? = null,
        externalSubtitleSourcePath: String? = null,
        externalSubtitleLabel: String? = null,
    ): MediaItem {
        val builder = MediaItem.Builder().setUri(Uri.parse(url))
        resolvePlaybackMimeType(url, formatHint)?.let { builder.setMimeType(it) }
        if (!externalSubtitleUrl.isNullOrBlank()) {
            val mime =
                resolveSubtitleMimeType(
                    externalSubtitleUrl,
                    externalSubtitleSourcePath ?: lastExternalSubtitleSourcePath,
                )
            val subBuilder =
                MediaItem.SubtitleConfiguration.Builder(Uri.parse(externalSubtitleUrl))
                    .setMimeType(mime)
                    .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            val label =
                externalSubtitleLabel?.trim()?.takeIf { it.isNotEmpty() }
                    ?: lastExternalSubtitleLabel
            if (!label.isNullOrBlank()) {
                subBuilder.setLabel(label)
            }
            builder.setSubtitleConfigurations(listOf(subBuilder.build()))
        }
        return builder.build()
    }

    private fun resolveSubtitleMimeType(url: String, sourcePath: String?): String {
        val ext =
            when {
                !sourcePath.isNullOrBlank() ->
                    sourcePath.substringAfterLast('.', "").lowercase()
                else -> {
                    val uri = Uri.parse(url)
                    val pathParam = uri.getQueryParameter("path")?.trim().orEmpty()
                    when {
                        pathParam.isNotEmpty() ->
                            pathParam.substringAfterLast('.', "").lowercase()
                        else -> uri.path.orEmpty().substringAfterLast('.', "").lowercase()
                    }
                }
            }
        return subtitleMimeTypeFromExtension(ext)
    }

    private fun subtitleMimeTypeFromExtension(ext: String): String =
        when (ext) {
            "srt" -> MimeTypes.APPLICATION_SUBRIP
            "vtt" -> MimeTypes.TEXT_VTT
            "ass", "ssa" -> MimeTypes.TEXT_SSA
            else -> MimeTypes.APPLICATION_SUBRIP
        }

    private fun playbackSourceExtension(url: String): String {
        val uri = Uri.parse(url)
        val internal = uri.getQueryParameter("internalPath")?.trim().orEmpty()
        val filePath = uri.getQueryParameter("path")?.trim().orEmpty()
        val candidate =
            when {
                internal.isNotEmpty() -> internal
                filePath.isNotEmpty() -> filePath
                else -> uri.path.orEmpty()
            }
        return candidate.substringAfterLast('.', "").lowercase()
    }

    /** 转码/HLS 必须声明 m3u8；原画按容器声明 MIME，避免嗅探失败误报不可播放。 */
    private fun resolvePlaybackMimeType(url: String, formatHint: String?): String? {
        when (formatHint?.lowercase()?.trim()) {
            "hls" -> return MimeTypes.APPLICATION_M3U8
        }
        val lower = url.lowercase()
        if (lower.contains("/api/videoplayer/transcode") ||
            lower.contains("/api/videoplayer/hls/") ||
            lower.contains(".m3u8")
        ) {
            return MimeTypes.APPLICATION_M3U8
        }
        return when (playbackSourceExtension(url)) {
            "m2ts", "mts", "m2t", "ts" -> MimeTypes.VIDEO_MP2T
            "mp4", "m4v", "mov" -> MimeTypes.VIDEO_MP4
            "mkv" -> MimeTypes.VIDEO_MATROSKA
            "webm" -> MimeTypes.VIDEO_WEBM
            else -> null
        }
    }

    private fun updateTrackRefs(tracks: Tracks) {
        audioTrackRefs =
            tracks.groups.filter { group ->
                group.type == C.TRACK_TYPE_AUDIO && group.length > 0
            }
        subtitleTrackRefs =
            tracks.groups.filter { group ->
                group.type == C.TRACK_TYPE_TEXT && group.length > 0
            }
    }

    private fun flushPendingTrackSelection() {
        if (pendingDisableSubtitles) {
            pendingDisableSubtitles = false
            disableSubtitles()
        }
        pendingAudioMapIndex?.let {
            pendingAudioMapIndex = null
            applyAudioMapIndex(it)
        }
        pendingInternalSubtitleIndex?.let {
            pendingInternalSubtitleIndex = null
            applyInternalSubtitleMapIndex(it)
        }
    }

    fun applyAudioMapIndex(mapIndex: Int) {
        if (audioTrackRefs.isEmpty()) {
            pendingAudioMapIndex = mapIndex
            return
        }
        val builder = trackSelector.parameters.buildUpon()
        builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
        builder.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
        val trackRef = audioTrackRefs.getOrNull(mapIndex.coerceAtLeast(0))
            ?: audioTrackRefs.firstOrNull()
        if (trackRef != null) {
            builder.setOverrideForType(TrackSelectionOverride(trackRef.mediaTrackGroup, 0))
        }
        trackSelector.setParameters(builder)
    }

    fun disableSubtitles() {
        if (subtitleTrackRefs.isEmpty() && lastExternalSubtitleUrl == null) {
            pendingDisableSubtitles = true
            pendingInternalSubtitleIndex = null
            return
        }
        lastExternalSubtitleUrl = null
        lastExternalSubtitleSourcePath = null
        lastExternalSubtitleLabel = null
        trackSelector.setParameters(
            trackSelector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .build(),
        )
    }

    fun applyInternalSubtitleMapIndex(internalIndex: Int) {
        if (subtitleTrackRefs.isEmpty()) {
            pendingInternalSubtitleIndex = internalIndex
            pendingDisableSubtitles = false
            return
        }
        lastExternalSubtitleUrl = null
        lastExternalSubtitleSourcePath = null
        lastExternalSubtitleLabel = null
        pendingDisableSubtitles = false
        val idx = internalIndex.coerceAtLeast(0)
        val trackRef = subtitleTrackRefs.getOrNull(idx) ?: return
        trackSelector.setParameters(
            trackSelector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setOverrideForType(TrackSelectionOverride(trackRef.mediaTrackGroup, 0))
                .build(),
        )
    }

    fun applyExternalSubtitleUrl(
        subUrl: String,
        sourcePath: String? = null,
        label: String? = null,
    ) {
        if (subUrl.isBlank()) return
        val normalized = subUrl.trim()
        val normalizedPath = sourcePath?.trim()?.takeIf { it.isNotEmpty() }
        val normalizedLabel = label?.trim()?.takeIf { it.isNotEmpty() }
        if (lastExternalSubtitleUrl != normalized ||
            lastExternalSubtitleSourcePath != normalizedPath ||
            lastExternalSubtitleLabel != normalizedLabel
        ) {
            reloadKeepingPosition(normalized, normalizedPath, normalizedLabel)
            return
        }
        maybeSelectExternalSidecarTextTrack()
    }

    private fun maybeSelectExternalSidecarTextTrack() {
        val subUrl = lastExternalSubtitleUrl ?: return
        if (subUrl.isBlank()) return
        if (subtitleTrackRefs.isEmpty()) return
        val group =
            when {
                subtitleTrackRefs.size == 1 -> subtitleTrackRefs.first()
                lastExternalSubtitleUrl != null -> subtitleTrackRefs.last()
                else -> subtitleTrackRefs.first()
            }
        if (group.length <= 0) return
        trackSelector.setParameters(
            trackSelector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
                .build(),
        )
    }

    fun release() {
        playerViewRef?.player = null
        player?.stop()
        player?.release()
        player = null
        playerViewRef = null
        triedSoftwareDecodeFallback = false
        videoSoftwareDecodeOnly = false
        mainUrl = null
    }
}
