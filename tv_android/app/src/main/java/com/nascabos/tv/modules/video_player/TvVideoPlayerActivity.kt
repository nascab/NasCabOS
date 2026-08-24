package com.nascabos.tv.modules.video_player

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.text.Layout
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatSeekBar
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.gson.Gson
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.ui.JwtSessionExpiredUi
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.p2p.P2pIcePreference
import com.nascabos.tv.core.i18n.LocaleManager
import com.nascabos.tv.data.storage.ServerStore
import com.nascabos.tv.modules.music.player.MusicPlaybackService
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.first
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IMedia
import org.videolan.libvlc.util.VLCUtil
import org.videolan.libvlc.util.VLCVideoLayout
import java.util.UUID
import kotlin.math.roundToInt

class TvVideoPlayerActivity : AppCompatActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var playerView: PlayerView
    private lateinit var vlcVideoLayout: VLCVideoLayout
    private lateinit var loading: ProgressBar
    private lateinit var controlsContainer: View
    private lateinit var titleView: TextView
    private lateinit var extraInfoView: TextView
    private lateinit var timeView: TextView
    private lateinit var seekPreviewView: TextView
    /** VLC 转码文本字幕叠层（Exo 转码仍走 PlayerView 内嵌 SubtitleView）。 */
    private lateinit var clientSubtitleView: SubtitleView
    private lateinit var hintView: TextView
    private lateinit var stateView: TextView
    private lateinit var seekBar: AppCompatSeekBar
    private lateinit var panelScrim: View
    private lateinit var panelContainer: View
    private lateinit var panelTitle: TextView
    private lateinit var panelList: RecyclerView
    private lateinit var playerRoot: View

    private val panelAdapter = TvPlayerPanelAdapter { pos -> onPanelItemClick(pos) }

    private var trackSelector: DefaultTrackSelector? = null
    private var player: ExoPlayer? = null
    private var libVlc: LibVLC? = null
    private var vlcPlayer: MediaPlayer? = null
    private var currentAudioTrackRefs: List<Tracks.Group> = emptyList()
    private var currentSubtitleTrackRefs: List<Tracks.Group> = emptyList()
    private var lastExternalSubtitleUrl: String? = null
    private var currentPlaybackUrl: String? = null
    private var currentPlaybackMimeType: String? = null

    private var playlist: List<TvPlaylistItem> = emptyList()
    private var currentIndex: Int = 0
    /** 1: skip scanning same-dir subtitle files; 0: allow scanning (video module only) */
    private var ignoreFindSub: Int = 1

    private var sourceDurationSeconds: Int? = null
    private var currentQuality: String = QUALITY_ORIGINAL
    private var playbackSpeed: Float = 1.0f
    private var isDolbyVisionSource: Boolean = false
    private var pendingOriginalStreamSeekSeconds: Int? = null

    private var audioTracks: List<TvAudioTrack> = emptyList()
    private var subtitleTracks: List<TvSubtitleTrack> = emptyList()
    private var currentAudioLabel: String = ""
    private var currentSubtitleLabel: String = ""
    private var currentSubtitleTextSizeSp: Float = DEFAULT_SUBTITLE_TEXT_SIZE_SP
    private var clientSubtitleCues: List<TvSubtitleCue> = emptyList()
    private var clientSubtitleCacheKey: String = ""
    private var clientSubtitleLoading: Boolean = false
    private var decoderPreference: String = DECODER_PREF_VLC
    /** 用户在本条视频上手动切换过解码器时，不再被自动策略覆盖。 */
    private var decoderManuallyOverridden: Boolean = false

    private var currentSubtitleSearchMode: String = "feature"
    private var currentSubtitleSearchKeyword: String = ""
    private var currentSubtitleSearchResults: List<TvSubtitleSearchItem> = emptyList()

    private var playId: String? = null
    private var transcodeBaseSeconds: Int = 0
    private var pendingTranscodeSeekSeconds: Int? = null

    private var controlsVisible: Boolean = false
    private var panelMode: PanelMode? = null

    private var autoHideJob: Job? = null
    private var autoSaveJob: Job? = null
    private var uiJob: Job? = null
    private var isClosingPlayer: Boolean = false
    private var seekPreviewJob: Job? = null
    private var playRetryCount: Int = 0
    private var lastKnownPositionSeconds: Int = 0
    private var lastKnownDurationSeconds: Int? = null
    private var openSkipStartSeconds: Int = 0
    private var openSkipEndSeconds: Int = 0
    private var didApplyResumeForCurrentSource: Boolean = false
    private var skipIntroConsumed: Boolean = false
    private var skipOutroConsumed: Boolean = false
    private var skipOutroSuppressedByResume: Boolean = false

    private var noAudioMode: Boolean = false
    private var triedNoAudioFallback: Boolean = false
    private var autoSwitchedToTranscode: Boolean = false

    private var seekKeyHeld: Boolean = false
    private var seekHeldKeyCode: Int = 0
    private var seekAdjustTargetSeconds: Int? = null

    /** 转码快进时延迟执行 stop+换源，避免 VLC AudioTrack 原生线程未 Detach 导致进程崩溃 */
    private var pendingDelayedStopAndPlay: Runnable? = null
    /** 上次转码重启完成时间，用于冷却期内不再立即触发重启 */
    private var lastTranscodeRestartDoneUptimeMs: Long = 0L
    /** 转码快进完成后在此时间前不响应左右方向键，避免连续触发崩溃 */
    private var transcodeSeekKeyBlockedUntilUptimeMs: Long = 0L

    /** 继续播放提示对话框的 5 秒自动消失任务 */
    private var resumeDialogAutoDismissRunnable: Runnable? = null
    /** 最近一次 seek 目标，用于卡在 loading 时自动补一次恢复 seek/重建播放 */
    private var pendingSeekRecoverySeconds: Int? = null
    private var seekRecoveryAttemptCount: Int = 0
    private var bufferingRecoveryRunnable: Runnable? = null
    private var systemSeekResumeRunnable: Runnable? = null
    private var vlcLoadingWatchdogRunnable: Runnable? = null
    private var pendingVlcSeekMs: Long? = null

    private val startContinuousSeekRunnable =
        Runnable {
            if (!seekKeyHeld) return@Runnable
            mainHandler.removeCallbacks(continuousSeekTickRunnable)
            mainHandler.post(continuousSeekTickRunnable)
        }

    private val continuousSeekTickRunnable =
        object : Runnable {
            override fun run() {
                if (!seekKeyHeld) return
                applySeekStep(seekHeldKeyCode)
                mainHandler.postDelayed(this, 220L)
            }
        }

    private val commitSeekRunnable =
        Runnable {
            val target = seekAdjustTargetSeconds ?: return@Runnable
            seekAdjustTargetSeconds = null
            commitSeekTargetSeconds(target)
        }

    private enum class PanelMode {
        Options,
        Quality,
        Speed,
        Audio,
        Subtitle,
        SubtitleSearch,
        SubtitleSize,
        Decoder,
        Playlist,
    }

    private enum class OptionAction {
        Previous,
        Next,
        Quality,
        Speed,
        Audio,
        Subtitle,
        SubtitleSize,
        Decoder,
        Playlist,
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocaleManager.init(applicationContext)
        LocaleManager.restoreSavedLanguage()
        MusicPlaybackService.sendStop(this)
        ApiController.init(applicationContext)
        setContentView(R.layout.activity_tv_video_player)

        playerView = findViewById(R.id.player_view)
        vlcVideoLayout = findViewById(R.id.vlc_video)
        loading = findViewById(R.id.loading)
        controlsContainer = findViewById(R.id.controls_container)
        titleView = findViewById(R.id.title)
        extraInfoView = findViewById(R.id.extra_info)
        timeView = findViewById(R.id.time)
        hintView = findViewById(R.id.hint)
        stateView = findViewById(R.id.state)
        seekPreviewView = findViewById(R.id.seek_preview)
        clientSubtitleView = findViewById(R.id.client_subtitle_view)
        seekBar = findViewById(R.id.seek)
        panelScrim = findViewById(R.id.panel_scrim)
        panelContainer = findViewById(R.id.panel_container)
        panelTitle = findViewById(R.id.panel_title)
        panelList = findViewById(R.id.panel_list)
        playerRoot = findViewById(R.id.player_root)
        playerRoot.isFocusable = true
        playerRoot.isFocusableInTouchMode = true

        panelList.layoutManager = LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        panelList.adapter = panelAdapter

        hintView.text = getString(R.string.player_hint_controls)

        parseIntent()
        loadPlayerPrefs()
        initPlayer()
        updateHeader()
        bindBackPressed()
        bindSeekBar()

        if (playlist.isNotEmpty()) {
            lifecycleScope.launch {
                ensureApiReadyForPlayback()
                prepareAndPlay(keepPositionSeconds = null, showResumeDialog = true)
            }
        } else {
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        JwtSessionExpiredUi.attachResumedActivity(this)
        updateKeepScreenOn()
        startUiLoop()
        startAutoSave()
    }

    override fun onPause() {
        cancelPendingSeekAdjust()
        runCatching { pausePlayback() }
        updateKeepScreenOn()
        stopAutoSave()
        stopUiLoop()
        super.onPause()
    }

    override fun onStop() {
        runCatching { pausePlayback() }
        if (isFinishing) {
            runCatching { stopTranscodingIfNeeded() }
            runCatching { stopPlayback() }
            runCatching { releasePlayer() }
        } else {
            // 观看过程中按首页键等切到后台时直接退出并销毁播放器，避免返回时黑屏
            finish()
        }
        super.onStop()
    }

    override fun onDestroy() {
        JwtSessionExpiredUi.detachIfSame(this)
        cancelPendingSeekAdjust()
        runCatching { stopTranscodingIfNeeded() }
        stopAutoSave()
        stopUiLoop()
        hidePanel()
        hideControls()
        releasePlayer()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (panelMode != null) {
            if (event.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_BACK) {
                when (panelMode) {
                    PanelMode.Quality,
                    PanelMode.Speed,
                    PanelMode.Audio,
                    PanelMode.Subtitle,
                    PanelMode.SubtitleSearch,
                    PanelMode.SubtitleSize,
                    PanelMode.Decoder,
                    -> showPanel(PanelMode.Options)
                    PanelMode.Options, PanelMode.Playlist -> hidePanel()
                    null -> {}
                }
                return true
            }
        } else {
            if (handleSeekKeyEvent(event.keyCode, event)) return true
            if (event.action == KeyEvent.ACTION_DOWN) {
                showControls(autoHide = true)
                when (event.keyCode) {
                    KeyEvent.KEYCODE_DPAD_CENTER,
                    KeyEvent.KEYCODE_ENTER,
                    KeyEvent.KEYCODE_NUMPAD_ENTER,
                    -> {
                        togglePlay()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_UP,
                    KeyEvent.KEYCODE_MENU,
                    -> {
                        showPanel(PanelMode.Options)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> {
                        showPanel(PanelMode.Playlist)
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun parseIntent() {
        val paths = intent.getStringArrayListExtra(EXTRA_PATHS).orEmpty()
        val names = intent.getStringArrayListExtra(EXTRA_NAMES).orEmpty()
        val internalPaths = intent.getStringArrayListExtra(EXTRA_INTERNAL_PATHS).orEmpty()
        val list = ArrayList<TvPlaylistItem>()
        for (i in paths.indices) {
            val p = paths[i].trim()
            if (p.isEmpty()) continue
            val n = names.getOrNull(i)?.trim().orEmpty()
            val internalPath = internalPaths.getOrNull(i)?.trim().orEmpty()
            list += TvPlaylistItem(path = p, name = n, internalPath = internalPath)
        }
        playlist = list
        currentIndex = intent.getIntExtra(EXTRA_INITIAL_INDEX, 0).coerceIn(0, (playlist.size - 1).coerceAtLeast(0))
        ignoreFindSub = intent.getIntExtra(EXTRA_IGNORE_FIND_SUB, 1).let { if (it == 0) 0 else 1 }
    }

    private fun initPlayer() {
        if (isUsingVlcBackend()) {
            if (libVlc != null && vlcPlayer != null) return
            buildAndAttachVlcPlayer()
        } else {
            if (player != null) return
            buildAndAttachSystemPlayer()
        }
    }

    private fun applyAutoDecoderForSource() {
        if (decoderManuallyOverridden) return
        val hwSupported = DolbyVisionHardwareUtil.isHardwareSupported(this)
        val targetDecoder =
            when {
                !isDolbyVisionSource -> DECODER_PREF_VLC
                hwSupported -> DECODER_PREF_SYSTEM
                else -> DECODER_PREF_VLC
            }
        if (decoderPreference != targetDecoder) {
            android.util.Log.d(
                "TvVideoPlayer",
                "auto decoder: isDolbyVision=$isDolbyVisionSource hwDv=$hwSupported -> $targetDecoder",
            )
            decoderPreference = targetDecoder
        }
    }

    private fun enforceQualityConstraints(path: String, internalPath: String) {
        if (isDolbyVisionSource &&
            isUsingVlcBackend() &&
            currentQuality == QUALITY_ORIGINAL &&
            !decoderManuallyOverridden
        ) {
            android.util.Log.d(
                "TvVideoPlayer",
                "auto quality: DV on auto-VLC backend, force transcode",
            )
            currentQuality = defaultTranscodeQuality()
            return
        }
        if (currentQuality == QUALITY_ORIGINAL && shouldForceTranscodeForSource(path, internalPath)) {
            android.util.Log.d(
                "TvVideoPlayer",
                "auto quality: force transcode for source isDolbyVision=$isDolbyVisionSource " +
                    "hwDv=${DolbyVisionHardwareUtil.isHardwareSupported(this)}",
            )
            currentQuality = defaultTranscodeQuality()
        }
    }

    private fun applyPlaybackStrategy(path: String, internalPath: String) {
        applyAutoDecoderForSource()
        enforceQualityConstraints(path, internalPath)
        ensurePlayerBackendMatchesDecoder()
    }

    private fun ensurePlayerBackendMatchesDecoder() {
        val needsVlc = isUsingVlcBackend()
        val vlcReady = libVlc != null && vlcPlayer != null
        val systemReady = player != null
        val backendMatches =
            if (needsVlc) vlcReady && !systemReady else systemReady && !vlcReady
        if (backendMatches) return
        android.util.Log.d(
            "TvVideoPlayer",
            "rebuild player backend: needsVlc=$needsVlc vlcReady=$vlcReady systemReady=$systemReady",
        )
        runCatching { stopPlayback() }
        releasePlayer()
        initPlayer()
    }

    private fun isUsingVlcBackend(): Boolean = decoderPreference == DECODER_PREF_VLC

    private fun isPlaybackPlaying(): Boolean {
        return if (isUsingVlcBackend()) vlcPlayer?.isPlaying == true else player?.isPlaying == true
    }

    private fun pausePlayback() {
        if (isUsingVlcBackend()) {
            vlcPlayer?.pause()
        } else {
            player?.pause()
        }
    }

    private fun resumePlayback() {
        if (isUsingVlcBackend()) {
            vlcPlayer?.play()
        } else {
            player?.play()
        }
    }

    private fun stopPlayback() {
        if (isUsingVlcBackend()) {
            vlcPlayer?.stop()
        } else {
            player?.stop()
        }
    }

    private fun applyPlaybackSpeed() {
        val speed = playbackSpeed.coerceIn(0.5f, 2.0f)
        if (isUsingVlcBackend()) {
            val mp = vlcPlayer ?: return
            runCatching { mp.setRate(speed) }
            // 某些设备/流在 play 或切回 1.0x 后会把速率重置，延迟再补一次。
            mainHandler.postDelayed(
                {
                    if (isUsingVlcBackend()) {
                        runCatching { vlcPlayer?.setRate(speed) }
                    }
                },
                120L,
            )
        } else {
            val mp = player ?: return
            runCatching { mp.playbackParameters = PlaybackParameters(speed) }
        }
    }

    private fun buildAndAttachSystemPlayer() {
        val selector = DefaultTrackSelector(this)
        val renderersFactory =
            DefaultRenderersFactory(this)
                .setEnableDecoderFallback(true)
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                .setEnableAudioTrackPlaybackParams(false)
        val mediaSourceFactory = buildMediaSourceFactory()
        val mp =
            ExoPlayer.Builder(this)
                .setRenderersFactory(renderersFactory)
                .setMediaSourceFactory(mediaSourceFactory)
                .setTrackSelector(selector)
                .setSeekForwardIncrementMs(30_000L)
                .setSeekBackIncrementMs(10_000L)
                .build()
        mp.repeatMode = Player.REPEAT_MODE_OFF
        mp.trackSelectionParameters =
            mp.trackSelectionParameters
                .buildUpon()
                .setAudioOffloadPreferences(
                    TrackSelectionParameters.AudioOffloadPreferences.Builder()
                        .setAudioOffloadMode(TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED)
                        .setIsSpeedChangeSupportRequired(true)
                        .build(),
                )
                .build()
        mp.addListener(
            object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    onPlayerStateChanged(playbackState)
                }

                override fun onPlayerError(error: PlaybackException) {
                    this@TvVideoPlayerActivity.onPlayerError(error)
                }

                override fun onTracksChanged(tracks: Tracks) {
                    updateCurrentTrackRefs(tracks)
                    maybeSelectExternalSidecarTextTrack()
                }

                override fun onCues(cueGroup: CueGroup) {
                    if (useClientSubtitleOverlay() && !isUsingVlcBackend()) {
                        mainHandler.post { updateClientSubtitleCue() }
                    }
                }

                override fun onPositionDiscontinuity(
                    oldPosition: Player.PositionInfo,
                    newPosition: Player.PositionInfo,
                    reason: Int,
                ) {
                    if (reason == Player.DISCONTINUITY_REASON_SEEK && shouldUseSeekRecovery()) {
                        scheduleBufferingRecoveryCheck()
                    }
                }
            },
        )
        playerView.visibility = View.VISIBLE
        vlcVideoLayout.visibility = View.GONE
        playerView.player = mp
        configureSubtitleView()
        trackSelector = selector
        player = mp
    }

    private fun buildAndAttachVlcPlayer() {
        val options =
            arrayListOf(
                "--no-drop-late-frames",
                "--no-skip-frames",
                "--network-caching=600",
                "--file-caching=600",
                "--codec=all",
                "--avcodec-fast",
                "--audio-time-stretch",
            )
        val lv = LibVLC(this, options)
        val mp = MediaPlayer(lv)
        mp.attachViews(vlcVideoLayout, null, true, false)
        mp.setEventListener { event -> onVlcEvent(event) }
        playerView.player = null
        playerView.visibility = View.GONE
        vlcVideoLayout.visibility = View.VISIBLE
        libVlc = lv
        vlcPlayer = mp
    }

    private fun buildMediaSourceFactory(): DefaultMediaSourceFactory {
        val httpFactory =
            DefaultHttpDataSource.Factory()
                .setConnectTimeoutMs(30_000)
                .setReadTimeoutMs(60_000)
                .setAllowCrossProtocolRedirects(true)
        val token = ApiController.accessToken.trim()
        if (token.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(
                mapOf(
                    "Authorization" to "Bearer $token",
                ),
            )
        }
        val dataSourceFactory =
            DefaultDataSource.Factory(
                this,
                httpFactory,
            )
        return DefaultMediaSourceFactory(dataSourceFactory)
    }

    private fun configureSubtitleView() {
        val bottomMarginPx = resources.getDimension(R.dimen.player_subtitle_bottom_margin)
        val screenH = resources.displayMetrics.heightPixels.toFloat().coerceAtLeast(1f)
        val bottomPaddingFraction = (bottomMarginPx / screenH).coerceIn(0.02f, 0.12f)
        playerView.subtitleView?.let { applyExoSubtitleViewStyle(it, bottomPaddingFraction) }
        applyVlcClientSubtitleViewStyle(bottomPaddingFraction)
    }

    private fun applyExoSubtitleViewStyle(
        subtitleView: SubtitleView,
        bottomPaddingFraction: Float,
    ) {
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
        subtitleView.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, currentSubtitleTextSizeSp)
        subtitleView.setBottomPaddingFraction(bottomPaddingFraction)
    }

    /**
     * VLC 转码叠层：无描边/阴影（避免连成黑块），仅白字透明底。
     * 原画 VLC 仍走原生 SPU，样式由播放器自己处理。
     */
    private fun applyVlcClientSubtitleViewStyle(bottomPaddingFraction: Float) {
        clientSubtitleView.setApplyEmbeddedFontSizes(false)
        clientSubtitleView.setApplyEmbeddedStyles(false)
        clientSubtitleView.setBackgroundColor(Color.TRANSPARENT)
        clientSubtitleView.setStyle(
            CaptionStyleCompat(
                Color.WHITE,
                Color.TRANSPARENT,
                Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_NONE,
                Color.TRANSPARENT,
                null,
            ),
        )
        clientSubtitleView.setViewType(SubtitleView.VIEW_TYPE_CANVAS)
        clientSubtitleView.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, currentSubtitleTextSizeSp)
        clientSubtitleView.setBottomPaddingFraction(bottomPaddingFraction)
    }

    /** Exo 走 PlayerView 内嵌 SubtitleView；VLC 转码文本字幕走独立 SubtitleView。 */
    private fun subtitleRenderView(): SubtitleView? {
        if (!useClientSubtitleOverlay()) return null
        return if (isUsingVlcBackend()) clientSubtitleView else playerView.subtitleView
    }

    private fun buildClientSubtitleCue(text: String): Cue {
        // 不设 line/position，与原画原生字幕一致，仅由 SubtitleView.bottomPaddingFraction 控制底边距。
        return Cue.Builder()
            .setText(text)
            .setTextAlignment(Layout.Alignment.ALIGN_CENTER)
            .build()
    }

    private fun releasePlayer() {
        pendingDelayedStopAndPlay?.let { mainHandler.removeCallbacks(it) }
        pendingDelayedStopAndPlay = null
        clearSeekRecovery()
        cancelVlcLoadingWatchdog()
        val exo = player
        player = null
        trackSelector = null
        currentAudioTrackRefs = emptyList()
        currentSubtitleTrackRefs = emptyList()
        lastExternalSubtitleUrl = null
        runCatching { playerView.player = null }
        runCatching { exo?.stop() }
        runCatching { exo?.release() }
        val vlc = vlcPlayer
        vlcPlayer = null
        runCatching { vlc?.setEventListener(null) }
        runCatching { vlc?.detachViews() }
        runCatching { vlc?.stop() }
        runCatching { vlc?.release() }
        val lv = libVlc
        libVlc = null
        runCatching { lv?.release() }
    }

    private fun updateHeader() {
        titleView.text = currentItemDisplayName()
    }

    private suspend fun prepareAndPlay(
        keepPositionSeconds: Int?,
        showResumeDialog: Boolean,
    ) {
        val item = playlist.getOrNull(currentIndex) ?: return
        val filePath = item.path
        loading.visibility = View.VISIBLE
        val info =
            runCatching { TvVideoPlayerApiService.getInfo(filePath, ignoreFindSub = ignoreFindSub) }.getOrNull()
        sourceDurationSeconds = info?.durationSeconds
        isDolbyVisionSource = info?.isDolbyVision == true
        android.util.Log.d(
            "TvVideoPlayer",
            "dolbyVision playback: isDolbyVision=$isDolbyVisionSource " +
                "hwSupported=${DolbyVisionHardwareUtil.isHardwareSupported(this)} " +
                "file=${filePath.takeLast(80)}",
        )
        applyOpenSkipData(info?.openSkip)
        audioTracks = info?.audioTracks.orEmpty()
        subtitleTracks = info?.subtitleTracks.orEmpty()
        resetPlaybackFallbackState()
        if (keepPositionSeconds == null) {
            currentQuality = VideoPlaybackSettingsStore.getDefaultQuality(this)
            decoderManuallyOverridden = false
        }
        val strategyPath = item.path
        val strategyInternalPath = item.internalPath
        applyPlaybackStrategy(strategyPath, strategyInternalPath)

        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        currentSubtitleLabel = noSubtitleLabel
        currentAudioLabel = audioTracks.firstOrNull()?.label.orEmpty()

        val pref = info?.preference
        pref?.audioLabel?.takeIf { it.isNotEmpty() }?.let { saved ->
            if (audioTracks.any { it.label == saved }) currentAudioLabel = saved
        }
        pref?.subtitleLabel?.takeIf { it.isNotEmpty() }?.let { saved ->
            if (saved == noSubtitleLabel) {
                currentSubtitleLabel = noSubtitleLabel
            } else if (subtitleTracks.any { it.label == saved }) {
                currentSubtitleLabel = saved
            }
        }

        val resumeFrom: Int
        val showResumeOverlayAfterPlay: Int?
        if (keepPositionSeconds != null) {
            resumeFrom = keepPositionSeconds
            showResumeOverlayAfterPlay = null
        } else if (showResumeDialog && pref != null && pref.playbackPositionSeconds > 10) {
            // 直接从上次位置开始播放，稍后在播放器内弹出与退出确认同款的对话框提示
            resumeFrom = pref.playbackPositionSeconds
            showResumeOverlayAfterPlay = pref.playbackPositionSeconds
        } else {
            resumeFrom = 0
            showResumeOverlayAfterPlay = null
        }

        if (showResumeOverlayAfterPlay != null) {
            markResumeApplied(resumeFrom)
        }
        playCurrent(startSeconds = resumeFrom)

        if (showResumeOverlayAfterPlay != null) {
            mainHandler.postDelayed(
                { showResumeConfirmOverlay(showResumeOverlayAfterPlay) },
                RESUME_DIALOG_SHOW_DELAY_MS
            )
        }
    }

    private fun playCurrent(startSeconds: Int) {
        pendingDelayedStopAndPlay?.let { mainHandler.removeCallbacks(it) }
        pendingDelayedStopAndPlay = null

        val item = playlist.getOrNull(currentIndex) ?: return
        updateHeader()
        val path = item.path
        val internalPath = item.internalPath
        applyPlaybackStrategy(path, internalPath)
        val forceTranscode = shouldForceTranscodeForSource(path, internalPath)
        android.util.Log.d(
            "TvVideoPlayer",
            "playCurrent: isDolbyVision=$isDolbyVisionSource " +
                "hwDv=${DolbyVisionHardwareUtil.isHardwareSupported(this)} " +
                "decoder=$decoderPreference manualDecoder=$decoderManuallyOverridden " +
                "quality=$currentQuality forceTranscode=$forceTranscode",
        )
        updateStateText()
        val prevPlayId = playId
        if (prevPlayId != null) {
            playId = null
            transcodeBaseSeconds = 0
            pendingTranscodeSeekSeconds = null
            lifecycleScope.launch { runCatching { TvVideoPlayerApiService.stopTranscoding(prevPlayId) } }
        }
        val url =
            if (currentQuality == QUALITY_ORIGINAL) {
                buildOriginalUrl(path, internalPath)
            } else {
                buildTranscodeUrl(path, seekSeconds = startSeconds)
            }
        val proxied = P2pLocalHttpProxy.proxyUrlIfNeeded(url)
        android.util.Log.d("TvVideoPlayer", "playCurrent: url=${url.take(80)}... proxied=${proxied.take(80)}...")
        pendingOriginalStreamSeekSeconds = null
        loading.visibility = View.VISIBLE
        currentPlaybackUrl = proxied
        if (isUsingVlcBackend()) {
            playCurrentWithVlc(proxied, path, internalPath, startSeconds)
        } else {
            playCurrentWithSystemPlayer(proxied, path, internalPath, startSeconds)
        }
        if (startSeconds > 0 && shouldUseSeekRecovery()) {
            armSeekRecovery(startSeconds)
            scheduleBufferingRecoveryCheck()
        } else {
            clearSeekRecovery()
        }
        updateKeepScreenOn()

        lifecycleScope.launch {
            if (useClientSubtitleOverlay()) {
                loadClientSubtitleIfNeeded(force = true)
            } else {
                clearClientSubtitle()
            }
        }

        if (currentQuality != QUALITY_ORIGINAL) {
            transcodeSeekKeyBlockedUntilUptimeMs = SystemClock.uptimeMillis() + TRANSCODE_SEEK_KEY_BLOCK_MS
            lastTranscodeRestartDoneUptimeMs = SystemClock.uptimeMillis()
        }
        showControls(autoHide = true)
        updateExtraInfo()
        updateSeekBar()
        playerRoot.requestFocus()
    }

    private suspend fun rebuildPlayerForDecoderPreference(resumeSeconds: Int) {
        loading.post { loading.visibility = View.VISIBLE }
        runCatching { stopPlayback() }
        releasePlayer()
        playCurrent(startSeconds = resumeSeconds)
    }

    private fun playCurrentWithSystemPlayer(
        proxied: String,
        path: String,
        internalPath: String,
        startSeconds: Int,
    ) {
        val mp = player ?: return
        runCatching { mp.stop() }
        runCatching { mp.clearMediaItems() }
        val mediaItemBuilder =
            MediaItem.Builder()
                .setUri(Uri.parse(proxied))
                .applyPlaybackMimeType(path = path, internalPath = internalPath, isTranscode = currentQuality != QUALITY_ORIGINAL)
        val externalSubtitleConfig = selectedExternalSubtitleConfig()
        if (externalSubtitleConfig != null) {
            lastExternalSubtitleUrl = externalSubtitleConfig.first
            mediaItemBuilder.setSubtitleConfigurations(listOf(externalSubtitleConfig.second))
        } else {
            lastExternalSubtitleUrl = null
        }
        val mediaItem = mediaItemBuilder.build()
        currentPlaybackMimeType = mediaItem.localConfiguration?.mimeType
        val mediaStartPositionMs =
            if (currentQuality == QUALITY_ORIGINAL) {
                startSeconds.coerceAtLeast(0) * 1000L
            } else {
                0L
            }
        mp.setMediaItem(mediaItem, mediaStartPositionMs)
        mp.prepare()
        applyPlaybackSpeed()
        mp.play()
    }

    private fun playCurrentWithVlc(
        proxied: String,
        path: String,
        internalPath: String,
        startSeconds: Int,
    ) {
        val lv = libVlc ?: return
        val mp = vlcPlayer ?: return
        runCatching { mp.stop() }
        currentPlaybackMimeType = playbackContainerMimeType(path, internalPath)
        val media = Media(lv, Uri.parse(proxied))
        media.addOption(":network-caching=600")
        media.addOption(":file-caching=600")
        media.addOption(":http-reconnect")
        media.setHWDecoderEnabled(true, false)
        if (noAudioMode) media.addOption(":no-audio")
        val subtitleUrl = selectedExternalSubtitleUrl()
        if (subtitleUrl != null) {
            lastExternalSubtitleUrl = subtitleUrl
            // Media.addSlave 须在 parse/play 之前调用；在 mp.media 赋值前对 Media 挂 slave（先于 mp.addSlave 且无 media 时无效）
            runCatching {
                val mrl = VLCUtil.encodeVLCUri(Uri.parse(subtitleUrl))
                media.addSlave(IMedia.Slave(IMedia.Slave.Type.Subtitle, 4, mrl))
            }
        } else {
            lastExternalSubtitleUrl = null
        }
        mp.media = media
        media.release()
        disableVlcNativeSubtitleForClientOverlay()
        applyPlaybackSpeed()
        pendingVlcSeekMs =
            if (currentQuality == QUALITY_ORIGINAL && startSeconds > 0) {
                startSeconds.coerceAtLeast(0).toLong() * 1000L
            } else {
                null
            }
        mp.play()
        pendingVlcSeekMs?.let { seekMs ->
            runCatching { mp.time = seekMs }
        }
        scheduleVlcLoadingWatchdog()
    }

    private fun selectedExternalSubtitleUrl(): String? {
        if (currentQuality != QUALITY_ORIGINAL) return null
        val selected = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel && it.isExternal } ?: return null
        val ext = selected.externalPath?.trim().orEmpty()
        if (ext.isEmpty()) return null
        val subUrl = P2pLocalHttpProxy.proxyUrlIfNeeded(buildSubtitleUrl(ext))
        return subUrl.takeIf { it.isNotEmpty() }
    }

    private fun defaultKeywordForCurrentItem(): String {
        val item = playlist.getOrNull(currentIndex)
        val name = item?.name?.trim().orEmpty().ifEmpty { item?.path?.substringAfterLast('/')?.trim().orEmpty() }
        if (name.isEmpty()) return ""
        val base = name.substringBeforeLast('.', name)
        return base.trim()
    }

    private suspend fun runSubtitleSearchFlow(initialMode: String) {
        if (panelMode != PanelMode.SubtitleSearch) return
        val item = playlist.getOrNull(currentIndex) ?: return
        val filePath = item.path
        if (filePath.trim().isEmpty()) return
        if (currentSubtitleSearchKeyword.isBlank()) currentSubtitleSearchKeyword = defaultKeywordForCurrentItem()
        currentSubtitleSearchMode = initialMode

        panelAdapter.submit(buildSubtitleSearchRows(loading = true))

        val results =
            runCatching {
                if (initialMode == "feature") {
                    val feature = TvVideoPlayerApiService.searchSubtitles(filePath = filePath, searchType = "feature")
                    if (feature.isNotEmpty()) {
                        currentSubtitleSearchMode = "feature"
                        feature
                    } else {
                        currentSubtitleSearchMode = "keyword"
                        TvVideoPlayerApiService.searchSubtitles(
                            filePath = filePath,
                            searchType = "keyword",
                            keyword = currentSubtitleSearchKeyword.trim(),
                        )
                    }
                } else {
                    currentSubtitleSearchMode = "keyword"
                    TvVideoPlayerApiService.searchSubtitles(
                        filePath = filePath,
                        searchType = "keyword",
                        keyword = currentSubtitleSearchKeyword.trim(),
                    )
                }
            }.getOrElse { emptyList() }

        currentSubtitleSearchResults = results
        panelAdapter.submit(buildSubtitleSearchRows(loading = false))

        if (results.isEmpty()) {
            Toast.makeText(this, R.string.player_subtitle_search_no_results, Toast.LENGTH_SHORT).show()
        }
        panelList.post {
            panelList.scrollToPosition(0)
            panelList.requestFocus()
            panelList.post { panelList.findViewHolderForAdapterPosition(0)?.itemView?.requestFocus() }
        }
    }

    private fun buildSubtitleSearchRows(loading: Boolean): List<TvPanelRow> {
        val out = ArrayList<TvPanelRow>()
        val featureMark = if (currentSubtitleSearchMode == "feature") "✓" else ""
        val keywordMark = if (currentSubtitleSearchMode == "keyword") "✓" else ""
        out += TvPanelRow("${getString(R.string.player_subtitle_search_feature)} $featureMark".trim(), "")
        out += TvPanelRow("${getString(R.string.player_subtitle_search_keyword)} $keywordMark".trim(), "")
        val kw = currentSubtitleSearchKeyword.trim().ifEmpty { "-" }
        out += TvPanelRow(getString(R.string.player_subtitle_search_keyword_hint), kw)

        if (loading) {
            out += TvPanelRow(getString(R.string.player_subtitle_searching), "")
            return out
        }
        if (currentSubtitleSearchResults.isEmpty()) {
            out += TvPanelRow(getString(R.string.player_subtitle_search_no_results), "")
            return out
        }
        for (it in currentSubtitleSearchResults) {
            val title = it.displayName.ifEmpty { it.sname.ifEmpty { "subtitle" } }
            val lang = it.language.ifEmpty { "und" }
            val ext = it.ext.ifEmpty { "-" }
            out += TvPanelRow(title, "$lang · $ext")
        }
        return out
    }

    private fun showKeywordInputDialog() {
        val input = EditText(this).apply {
            setText(currentSubtitleSearchKeyword)
            setSelection(text.length)
            hint = getString(R.string.player_subtitle_search_keyword_hint)
        }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (16 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
            addView(input)
        }
        AlertDialog.Builder(this, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.player_subtitle_search_keyword))
            .setView(container)
            .setPositiveButton(getString(R.string.action_ok)) { _, _ ->
                currentSubtitleSearchKeyword = input.text?.toString().orEmpty().trim()
                lifecycleScope.launch { runSubtitleSearchFlow(initialMode = "keyword") }
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private suspend fun downloadAndApplySearchedSubtitle(it: TvSubtitleSearchItem) {
        val item = playlist.getOrNull(currentIndex) ?: return
        val filePath = item.path
        if (filePath.trim().isEmpty()) return
        loading.post { loading.visibility = View.VISIBLE }
        val downloaded =
            runCatching {
                TvVideoPlayerApiService.downloadSearchedSubtitle(
                    filePath = filePath,
                    surl = it.surl,
                    sname = it.sname,
                    language = it.language,
                )
            }.getOrNull()
        loading.post { loading.visibility = View.GONE }
        if (downloaded == null) {
            Toast.makeText(this, R.string.player_subtitle_download_failed, Toast.LENGTH_SHORT).show()
            return
        }

        val savedPath = downloaded.path.trim()
        val filename = downloaded.filename.trim()
        if (savedPath.isEmpty() || filename.isEmpty()) {
            Toast.makeText(this, R.string.player_subtitle_download_failed, Toast.LENGTH_SHORT).show()
            return
        }

        val exists = subtitleTracks.any { t -> t.isExternal && t.externalPath?.trim() == savedPath }
        if (!exists) {
            subtitleTracks =
                listOf(TvSubtitleTrack(label = filename, mapIndex = null, isExternal = true, externalPath = savedPath)) +
                    subtitleTracks
        }
        val prevSubtitleLabel = currentSubtitleLabel
        currentSubtitleLabel = filename
        updateStateText()

        if (currentQuality == QUALITY_ORIGINAL) {
            applySubtitleChangeForOriginalQuality()
        } else {
            applySubtitleTrackWhileTranscoding(prevLabel = prevSubtitleLabel)
        }
        saveProgress()
        Toast.makeText(this, R.string.player_subtitle_download_success, Toast.LENGTH_SHORT).show()
        showPanel(PanelMode.Subtitle)
    }

    /** 转码文本字幕走 client 叠层时，关闭 VLC 原生 SPU，避免黑底字幕与叠层重复。 */
    private fun disableVlcNativeSubtitleForClientOverlay() {
        if (!isUsingVlcBackend()) return
        if (currentQuality == QUALITY_ORIGINAL) return
        if (!useClientSubtitleOverlay()) return
        runCatching { vlcPlayer?.spuTrack = -1 }
    }

    private fun onVlcEvent(event: MediaPlayer.Event) {
        when (event.type) {
            MediaPlayer.Event.Playing -> {
                playRetryCount = 0
                applyPlaybackSpeed()
                applyPendingVlcSeekIfNeeded()
                disableVlcNativeSubtitleForClientOverlay()
                lifecycleScope.launch {
                    if (currentQuality == QUALITY_ORIGINAL) {
                        applyAudioSelection()
                        applySubtitleSelection()
                    }
                }
                if (currentQuality == QUALITY_ORIGINAL) {
                    scheduleVlcExternalSidecarSubtitleSelectRetries()
                }
                cancelVlcLoadingWatchdog()
                loading.post { loading.visibility = View.GONE }
                mainHandler.post { updateKeepScreenOn() }
            }
            MediaPlayer.Event.Buffering -> {
                if (event.buffering >= 100f) {
                    applyPlaybackSpeed()
                    applyPendingVlcSeekIfNeeded()
                    disableVlcNativeSubtitleForClientOverlay()
                    lifecycleScope.launch {
                        if (currentQuality == QUALITY_ORIGINAL) {
                            applyAudioSelection()
                            applySubtitleSelection()
                        }
                    }
                    if (currentQuality == QUALITY_ORIGINAL) {
                        scheduleVlcExternalSidecarSubtitleSelectRetries()
                    }
                    cancelVlcLoadingWatchdog()
                    loading.post { loading.visibility = View.GONE }
                } else if (!isPlaybackPlaying()) {
                    loading.post { loading.visibility = View.VISIBLE }
                }
            }
            MediaPlayer.Event.EndReached -> {
                cancelVlcLoadingWatchdog()
                lifecycleScope.launch { handlePlaybackEnded() }
            }
            MediaPlayer.Event.EncounteredError -> {
                cancelVlcLoadingWatchdog()
                lifecycleScope.launch {
                    if (playRetryCount < 3) {
                        playRetryCount++
                        loading.post { loading.visibility = View.VISIBLE }
                        delay(1_500)
                        prepareAndPlay(keepPositionSeconds = lastKnownPositionSeconds, showResumeDialog = false)
                    } else {
                        loading.post { loading.visibility = View.GONE }
                        showReconnectDialog(lastKnownPositionSeconds)
                    }
                }
            }
        }
    }

    private fun scheduleVlcLoadingWatchdog() {
        cancelVlcLoadingWatchdog()
        if (!isUsingVlcBackend()) return
        var attempts = 0
        val runnable =
            object : Runnable {
                override fun run() {
                    val mp = vlcPlayer ?: return
                    if (mp.isPlaying || mp.time > 0L || mp.position > 0f) {
                        loading.visibility = View.GONE
                        vlcLoadingWatchdogRunnable = null
                        return
                    }
                    attempts++
                    if (attempts >= 30) {
                        vlcLoadingWatchdogRunnable = null
                        return
                    }
                    mainHandler.postDelayed(this, 300L)
                }
            }
        vlcLoadingWatchdogRunnable = runnable
        mainHandler.postDelayed(runnable, 300L)
    }

    private fun cancelVlcLoadingWatchdog() {
        vlcLoadingWatchdogRunnable?.let { mainHandler.removeCallbacks(it) }
        vlcLoadingWatchdogRunnable = null
    }

    private fun applyPendingVlcSeekIfNeeded() {
        val mp = vlcPlayer ?: return
        val seekMs = pendingVlcSeekMs ?: return
        pendingVlcSeekMs = null
        runCatching { mp.time = seekMs }
    }

    private fun MediaItem.Builder.applyPlaybackMimeType(
        path: String,
        internalPath: String,
        isTranscode: Boolean,
    ): MediaItem.Builder {
        if (isTranscode) {
            setMimeType(MimeTypes.APPLICATION_M3U8)
            return this
        }
        playbackContainerMimeType(path, internalPath)?.let { setMimeType(it) }
        return this
    }

    private fun playbackContainerMimeType(path: String, internalPath: String): String? {
        return when (playbackSourceExtension(path, internalPath)) {
            "m2ts", "mts", "m2t", "ts" -> MimeTypes.VIDEO_MP2T
            "mp4", "m4v", "mov" -> MimeTypes.VIDEO_MP4
            "mkv" -> MimeTypes.VIDEO_MATROSKA
            "webm" -> MimeTypes.VIDEO_WEBM
            else -> null
        }
    }

    private fun shouldForceTranscodeForSource(path: String, internalPath: String): Boolean {
        if (playbackSourceExtension(path, internalPath) in FORCE_TRANSCODE_EXTENSIONS) return true
        if (isDolbyVisionSource && !DolbyVisionHardwareUtil.isHardwareSupported(this)) return true
        return false
    }

    private fun playbackSourceExtension(path: String, internalPath: String): String {
        val candidate =
            internalPath.trim().takeIf { it.isNotEmpty() }
                ?: path.trim()
        return candidate.substringAfterLast('.', "").lowercase()
    }

    private fun armSeekRecovery(targetSeconds: Int) {
        pendingSeekRecoverySeconds = targetSeconds.coerceAtLeast(0)
        seekRecoveryAttemptCount = 0
        bufferingRecoveryRunnable?.let { mainHandler.removeCallbacks(it) }
        bufferingRecoveryRunnable = null
    }

    private fun clearSeekRecovery() {
        pendingSeekRecoverySeconds = null
        seekRecoveryAttemptCount = 0
        bufferingRecoveryRunnable?.let { mainHandler.removeCallbacks(it) }
        bufferingRecoveryRunnable = null
        systemSeekResumeRunnable?.let { mainHandler.removeCallbacks(it) }
        systemSeekResumeRunnable = null
    }

    private fun shouldUseSeekRecovery(): Boolean {
        return isDirectOriginalFilePlayback()
    }

    private fun isDirectOriginalFilePlayback(): Boolean {
        if (currentQuality != QUALITY_ORIGINAL) return false
        if (playId != null) return false
        if (shouldRestartOriginalSeek()) return false
        return true
    }

    private fun scheduleBufferingRecoveryCheck() {
        val target = pendingSeekRecoverySeconds ?: return
        bufferingRecoveryRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable =
            object : Runnable {
                override fun run() {
                    val mp = player ?: return
                    val stillSeeking = pendingSeekRecoverySeconds != null
                    val buffering = mp.playbackState == Player.STATE_BUFFERING
                    if (!stillSeeking || !buffering) return
                    if (seekRecoveryAttemptCount >= MAX_SEEK_RECOVERY_ATTEMPTS) return
                    seekRecoveryAttemptCount++
                    val duration = currentDurationSeconds() ?: 0
                    val retryTarget =
                        if (duration > 1) {
                            (target + 1).coerceIn(0, duration - 1)
                        } else {
                            target
                        }
                    if (currentQuality == QUALITY_ORIGINAL && !shouldRestartOriginalSeek()) {
                        runCatching {
                            mp.seekTo(retryTarget.toLong() * 1000L)
                            mp.playWhenReady = true
                            mp.play()
                        }
                        scheduleSystemSeekResumeCheck(retryTarget)
                        mainHandler.postDelayed(this, SEEK_BUFFERING_RECOVERY_TIMEOUT_MS)
                    } else {
                        lifecycleScope.launch {
                            if (currentQuality != QUALITY_ORIGINAL) {
                                stopTranscodingIfNeeded()
                            }
                            playCurrent(startSeconds = retryTarget)
                        }
                    }
                }
            }
        bufferingRecoveryRunnable = runnable
        mainHandler.postDelayed(runnable, SEEK_BUFFERING_RECOVERY_TIMEOUT_MS)
    }

    private fun scheduleSystemSeekResumeCheck(targetSeconds: Int) {
        systemSeekResumeRunnable?.let { mainHandler.removeCallbacks(it) }
        if (isUsingVlcBackend() || !isDirectOriginalFilePlayback()) return
        val runnable =
            Runnable {
                val mp = player ?: return@Runnable
                if (isUsingVlcBackend() || !isDirectOriginalFilePlayback()) return@Runnable
                if (mp.playbackState == Player.STATE_ENDED) return@Runnable
                val currentSeconds = (mp.currentPosition / 1000L).toInt().coerceAtLeast(0)
                val nearTarget = kotlin.math.abs(currentSeconds - targetSeconds) <= 3
                if (nearTarget && !mp.isPlaying) {
                    mp.playWhenReady = true
                    mp.play()
                }
            }
        systemSeekResumeRunnable = runnable
        mainHandler.postDelayed(runnable, SYSTEM_SEEK_RESUME_DELAY_MS)
    }

    private fun selectedExternalSubtitleConfig(): Pair<String, MediaItem.SubtitleConfiguration>? {
        if (currentQuality != QUALITY_ORIGINAL) return null
        val selected = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel && it.isExternal } ?: return null
        val ext = selected.externalPath?.trim().orEmpty()
        if (ext.isEmpty()) return null
        val subUrl = P2pLocalHttpProxy.proxyUrlIfNeeded(buildSubtitleUrl(ext))
        if (subUrl.isEmpty()) return null
        val config =
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(subUrl))
                .setMimeType(subtitleMimeType(ext))
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .setLabel(selected.label)
                .build()
        return subUrl to config
    }

    private fun subtitleMimeType(path: String): String {
        return when (path.substringAfterLast('.', "").lowercase()) {
            "srt" -> MimeTypes.APPLICATION_SUBRIP
            "vtt" -> MimeTypes.TEXT_VTT
            "ass", "ssa" -> MimeTypes.TEXT_SSA
            else -> MimeTypes.APPLICATION_SUBRIP
        }
    }

    private fun togglePlay() {
        if (isPlaybackPlaying()) {
            pausePlayback()
        } else {
            resumePlayback()
        }
        updateKeepScreenOn()
        scheduleAutoHide()
    }

    private fun showSeekPreview(targetSeconds: Int, totalSeconds: Int?) {
        val txt =
            if (totalSeconds != null) {
                "${formatTime(targetSeconds)} / ${formatTime(totalSeconds)}"
            } else {
                formatTime(targetSeconds)
            }
        seekPreviewView.text = txt
        seekPreviewView.visibility = View.VISIBLE
        seekPreviewJob?.cancel()
        seekPreviewJob =
            lifecycleScope.launch {
                delay(1_500)
                seekPreviewView.visibility = View.GONE
                updateSeekBar()
            }
        updateSeekBar()
    }

    private fun seekToSeconds(seconds: Int) {
        if (currentQuality != QUALITY_ORIGINAL) {
            clearSeekRecovery()
            pendingTranscodeSeekSeconds = seconds
            updateSeekBar()
            scheduleTranscodeRestart()
            scheduleAutoHide()
            return
        }
        if (shouldUseSeekRecovery()) {
            armSeekRecovery(seconds)
        } else {
            clearSeekRecovery()
        }
        if (shouldRestartOriginalSeek()) {
            pendingOriginalStreamSeekSeconds = seconds
            updateSeekBar()
            scheduleOriginalRemuxRestart()
            scheduleAutoHide()
            return
        }
        if (isUsingVlcBackend()) {
            val mp = vlcPlayer ?: return
            mp.time = seconds.toLong() * 1000L
            mp.play()
        } else {
            val mp = player ?: return
            mp.seekTo(seconds.toLong() * 1000L)
            mp.playWhenReady = true
            mp.play()
            scheduleSystemSeekResumeCheck(seconds)
        }
        loading.visibility = View.VISIBLE
        if (shouldUseSeekRecovery()) {
            scheduleBufferingRecoveryCheck()
        }
        scheduleAutoHide()
        updateSeekBar()
    }

    private fun scheduleOriginalRemuxRestart() {
        mainHandler.removeCallbacks(restartOriginalRemuxRunnable)
        mainHandler.postDelayed(restartOriginalRemuxRunnable, ORIGINAL_REMUX_SEEK_DEBOUNCE_MS)
    }

    private val restartOriginalRemuxRunnable =
        Runnable {
            val seek = pendingOriginalStreamSeekSeconds ?: return@Runnable
            pendingOriginalStreamSeekSeconds = null
            lifecycleScope.launch {
                playCurrent(startSeconds = seek)
            }
        }

    private fun scheduleTranscodeRestart() {
        mainHandler.removeCallbacks(restartTranscodeRunnable)
        val now = SystemClock.uptimeMillis()
        val elapsedSinceRestart = now - lastTranscodeRestartDoneUptimeMs
        val delayMs = if (elapsedSinceRestart < TRANSCODE_RESTART_COOLDOWN_MS) {
            (TRANSCODE_RESTART_COOLDOWN_MS - elapsedSinceRestart).coerceAtLeast(TRANSCODE_SEEK_DEBOUNCE_MS)
        } else {
            TRANSCODE_SEEK_DEBOUNCE_MS
        }
        mainHandler.postDelayed(restartTranscodeRunnable, delayMs)
    }

    private val restartTranscodeRunnable =
        Runnable {
            val seek = pendingTranscodeSeekSeconds ?: return@Runnable
            pendingTranscodeSeekSeconds = null
            lifecycleScope.launch {
                stopTranscodingIfNeeded()
                playCurrent(startSeconds = seek)
            }
        }

    private fun currentDurationSeconds(): Int? {
        return if (currentQuality == QUALITY_ORIGINAL) {
            val len =
                if (isUsingVlcBackend()) {
                    vlcPlayer?.length ?: 0L
                } else {
                    player?.duration ?: 0L
                }
            if (len > 0) (len / 1000L).toInt() else sourceDurationSeconds
        } else {
            sourceDurationSeconds
        }
    }

    private fun currentPositionSeconds(): Int {
        pendingOriginalStreamSeekSeconds?.let {
            if (currentQuality == QUALITY_ORIGINAL && shouldRestartOriginalSeek()) return it.coerceAtLeast(0)
        }
        val posMs =
            if (isUsingVlcBackend()) {
                vlcPlayer?.time ?: 0L
            } else {
                player?.currentPosition ?: 0L
            }
        val pos = (posMs / 1000L).toInt().coerceAtLeast(0)
        return if (currentQuality == QUALITY_ORIGINAL) {
            pos
        } else {
            (transcodeBaseSeconds + pos).coerceAtLeast(0)
        }
    }

    private fun shouldRestartOriginalSeek(): Boolean {
        if (currentQuality != QUALITY_ORIGINAL) return false
        val item = playlist.getOrNull(currentIndex) ?: return false
        return item.internalPath.trim().isNotEmpty()
    }

    private fun updateSeekBar() {
        val dur = currentDurationSeconds()
        val actualPos = currentPositionSeconds()
        val previewPos =
            seekAdjustTargetSeconds
                ?: pendingTranscodeSeekSeconds
                ?: pendingOriginalStreamSeekSeconds
        val pos = previewPos ?: actualPos
        if (isPlaybackPlaying()) {
            lastKnownPositionSeconds = actualPos
            lastKnownDurationSeconds = dur
            maybeHandleAutoSkip(actualPos, dur)
        }
        val d = dur ?: 0
        val safeD = d.coerceAtLeast(1)
        seekBar.progress = ((pos.toDouble() / safeD.toDouble()) * 1000.0).roundToInt().coerceIn(0, 1000)
        val timeText = if (dur != null) "${formatTime(pos)} / ${formatTime(dur)}" else formatTime(pos)
        timeView.text = timeText
        updateStateText()
        updateClientSubtitleCue()
    }

    /** 始终保持屏幕常亮，避免暂停时触发系统休眠 */
    private fun updateKeepScreenOn() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun updateStateText() {
        val playing = isPlaybackPlaying()
        val q = qualityLabel(currentQuality)
        val sp = "${playbackSpeed}x"
        val a = if (noAudioMode) "-" else currentAudioLabel.ifEmpty { "-" }
        val s = currentSubtitleLabel.ifEmpty { "-" }
        val decoder = decoderPreferenceLabel()
        val dv =
            if (isDolbyVisionSource) {
                val hw = if (DolbyVisionHardwareUtil.isHardwareSupported(this)) "硬解" else "转码"
                "DV:$hw"
            } else {
                "DV:否"
            }
        val status = if (playing) "播放中" else "已暂停"
        stateView.text = "$status  $q  $sp  $decoder  $dv  $a  $s"
    }

    private fun updateExtraInfo() {
        extraInfoView.text = qualityLabel(currentQuality)
    }

    private fun applyOpenSkipData(openSkip: TvOpenSkip?) {
        openSkipStartSeconds = openSkip?.startSec?.coerceAtLeast(0) ?: 0
        openSkipEndSeconds = openSkip?.endSec?.coerceAtLeast(0) ?: 0
        didApplyResumeForCurrentSource = false
        skipIntroConsumed = false
        skipOutroConsumed = false
        skipOutroSuppressedByResume = false
    }

    private fun markResumeApplied(targetSeconds: Int) {
        didApplyResumeForCurrentSource = true
        skipIntroConsumed = true
        val total = currentDurationSeconds() ?: sourceDurationSeconds ?: return
        if (openSkipEndSeconds <= 0 || total <= 0) return
        val outroStart = total - openSkipEndSeconds
        if (outroStart <= 0) return
        if (targetSeconds >= outroStart) {
            skipOutroSuppressedByResume = true
            skipOutroConsumed = true
        }
    }

    private fun maybeHandleAutoSkip(positionSeconds: Int, durationSeconds: Int?) {
        if (isClosingPlayer) return
        if (!isPlaybackPlaying()) return
        val total = durationSeconds ?: return
        if (total <= 0) return

        if (!skipIntroConsumed && !didApplyResumeForCurrentSource) {
            val startSec = openSkipStartSeconds
            if (startSec > 0) {
                if (startSec >= total) {
                    skipIntroConsumed = true
                } else if (positionSeconds < startSec) {
                    skipIntroConsumed = true
                    triggerIntroAutoSkip(startSec)
                    return
                } else {
                    skipIntroConsumed = true
                }
            }
        }

        if (skipOutroConsumed || skipOutroSuppressedByResume) return
        val endSec = openSkipEndSeconds
        if (endSec <= 0) return
        val outroStart = total - endSec
        if (outroStart <= 0) return
        if (positionSeconds >= outroStart) {
            skipOutroConsumed = true
            triggerOutroAutoSkip()
        }
    }

    private fun triggerIntroAutoSkip(targetSeconds: Int) {
        val current = currentPositionSeconds()
        if (targetSeconds <= current + 1) return
        Toast.makeText(this, R.string.player_skip_opening, Toast.LENGTH_SHORT).show()
        seekToSeconds(targetSeconds)
    }

    private fun triggerOutroAutoSkip() {
        Toast.makeText(this, R.string.player_skip_ending, Toast.LENGTH_SHORT).show()
        runCatching { pausePlayback() }
        lifecycleScope.launch {
            saveProgress(forceZero = true)
            mainHandler.post { updateKeepScreenOn() }
            playNextOrExit()
        }
    }

    private fun showControls(autoHide: Boolean) {
        controlsVisible = true
        controlsContainer.visibility = View.VISIBLE
        updateSeekBar()
        if (autoHide) scheduleAutoHide() else cancelAutoHide()
    }

    private fun hideControls() {
        controlsVisible = false
        controlsContainer.visibility = View.GONE
        cancelAutoHide()
        playerRoot.requestFocus()
    }

    private fun scheduleAutoHide() {
        cancelAutoHide()
        autoHideJob =
            lifecycleScope.launch {
                delay(3_000)
                if (panelMode != null) return@launch
                if (seekKeyHeld) {
                    scheduleAutoHide()
                    return@launch
                }
                hideControls()
            }
    }

    private fun cancelAutoHide() {
        autoHideJob?.cancel()
        autoHideJob = null
    }

    private fun showPanel(mode: PanelMode) {
        panelMode = mode
        panelScrim.visibility = View.VISIBLE
        panelContainer.visibility = View.VISIBLE
        controlsContainer.visibility = View.VISIBLE
        controlsVisible = true
        cancelAutoHide()

        when (mode) {
            PanelMode.Options -> {
                panelTitle.text = getString(R.string.player_options_title)
                panelAdapter.submit(buildOptionsRows())
            }
            PanelMode.Quality -> {
                panelTitle.text = getString(R.string.player_setting_quality)
                panelAdapter.submit(buildQualityRows())
            }
            PanelMode.Speed -> {
                panelTitle.text = getString(R.string.player_setting_speed)
                panelAdapter.submit(buildSpeedRows())
            }
            PanelMode.Audio -> {
                panelTitle.text = getString(R.string.player_setting_audio_track)
                panelAdapter.submit(buildAudioRows())
            }
            PanelMode.Subtitle -> {
                panelTitle.text = getString(R.string.player_setting_subtitle_track)
                panelAdapter.submit(buildSubtitleRows())
            }
            PanelMode.SubtitleSearch -> {
                panelTitle.text = getString(R.string.player_subtitle_search_title)
                panelAdapter.submit(listOf(TvPanelRow(getString(R.string.player_subtitle_searching), "")))
                panelList.post { panelList.scrollToPosition(0) }
                lifecycleScope.launch { runSubtitleSearchFlow(initialMode = "feature") }
            }
            PanelMode.SubtitleSize -> {
                panelTitle.text = getString(R.string.player_setting_subtitle_size)
                panelAdapter.submit(buildSubtitleSizeRows())
            }
            PanelMode.Decoder -> {
                panelTitle.text = getString(R.string.player_setting_decoder)
                panelAdapter.submit(buildDecoderRows())
            }
            PanelMode.Playlist -> {
                panelTitle.text = getString(R.string.player_playlist_title)
                panelAdapter.submit(buildPlaylistRows())
            }
        }
        panelList.post {
            val focusPosition =
                if (mode == PanelMode.Playlist) {
                    currentIndex.coerceIn(0, (panelAdapter.itemCount - 1).coerceAtLeast(0))
                } else {
                    0
                }
            panelList.scrollToPosition(focusPosition)
            panelList.requestFocus()
            panelList.post {
                panelList.findViewHolderForAdapterPosition(focusPosition)?.itemView?.requestFocus()
            }
        }
    }

    private fun hidePanel() {
        panelMode = null
        panelScrim.visibility = View.GONE
        panelContainer.visibility = View.GONE
        playerRoot.requestFocus()
        scheduleAutoHide()
    }

    private fun onPanelItemClick(position: Int) {
        when (panelMode) {
            PanelMode.Options -> {
                when (buildVisibleOptionActions().getOrNull(position)) {
                    OptionAction.Previous -> {
                        if (playAdjacent(offset = -1)) hidePanel()
                    }
                    OptionAction.Next -> {
                        if (playAdjacent(offset = 1)) hidePanel()
                    }
                    OptionAction.Quality -> showPanel(PanelMode.Quality)
                    OptionAction.Speed -> showPanel(PanelMode.Speed)
                    OptionAction.Audio -> showPanel(PanelMode.Audio)
                    OptionAction.Subtitle -> showPanel(PanelMode.Subtitle)
                    OptionAction.SubtitleSize -> showPanel(PanelMode.SubtitleSize)
                    OptionAction.Decoder -> showPanel(PanelMode.Decoder)
                    OptionAction.Playlist -> showPanel(PanelMode.Playlist)
                    null -> return
                }
            }
            PanelMode.Quality -> {
                val q = QUALITY_OPTIONS.getOrNull(position) ?: return
                if (q == currentQuality) return
                val keep = currentPositionSeconds()
                lifecycleScope.launch {
                    if (q == QUALITY_ORIGINAL) {
                        stopTranscodingIfNeeded()
                    }
                    currentQuality = q
                    resetPlaybackFallbackState()
                    playCurrent(startSeconds = keep)
                    hidePanel()
                }
            }
            PanelMode.Speed -> {
                val sp = SPEED_OPTIONS.getOrNull(position) ?: return
                playbackSpeed = sp
                applyPlaybackSpeed()
                updateStateText()
                hidePanel()
            }
            PanelMode.Audio -> {
                val sel = audioTracks.getOrNull(position) ?: return
                if (sel.label == currentAudioLabel) return
                currentAudioLabel = sel.label
                lifecycleScope.launch {
                    if (currentQuality == QUALITY_ORIGINAL) {
                        if (noAudioMode) {
                            val keep = currentPositionSeconds()
                            noAudioMode = false
                            triedNoAudioFallback = false
                            playCurrent(startSeconds = keep)
                        } else {
                            applyAudioSelection()
                        }
                    } else {
                        val keep = currentPositionSeconds()
                        stopTranscodingIfNeeded()
                        playCurrent(startSeconds = keep)
                    }
                    saveProgress()
                }
                updateStateText()
                hidePanel()
            }
            PanelMode.Subtitle -> {
                val noSubtitleLabel = getString(R.string.player_no_subtitle)
                if (position == 0) {
                    if (currentSubtitleLabel == noSubtitleLabel) return
                    val prev = currentSubtitleLabel
                    currentSubtitleLabel = noSubtitleLabel
                    lifecycleScope.launch {
                        if (currentQuality == QUALITY_ORIGINAL) {
                            applySubtitleChangeForOriginalQuality()
                        } else {
                            applySubtitleTrackWhileTranscoding(prevLabel = prev)
                        }
                        saveProgress()
                    }
                    updateStateText()
                    hidePanel()
                    return
                }
                if (position == 1) {
                    openSubtitleSearchIfServerSupported()
                    return
                }
                val sel = subtitleTracks.getOrNull(position - 2) ?: return
                if (sel.label == currentSubtitleLabel) return
                val prev = currentSubtitleLabel
                currentSubtitleLabel = sel.label
                lifecycleScope.launch {
                    if (currentQuality == QUALITY_ORIGINAL) {
                        applySubtitleChangeForOriginalQuality()
                    } else {
                        applySubtitleTrackWhileTranscoding(prevLabel = prev)
                    }
                    saveProgress()
                }
                updateStateText()
                hidePanel()
            }
            PanelMode.SubtitleSearch -> {
                // Rows: 0 feature, 1 keyword, 2 keyword input, 3... results
                when (position) {
                    0 -> lifecycleScope.launch { runSubtitleSearchFlow(initialMode = "feature") }
                    1 -> lifecycleScope.launch { runSubtitleSearchFlow(initialMode = "keyword") }
                    2 -> showKeywordInputDialog()
                    else -> {
                        val idx = position - 3
                        val it = currentSubtitleSearchResults.getOrNull(idx) ?: return
                        lifecycleScope.launch { downloadAndApplySearchedSubtitle(it) }
                    }
                }
            }
            PanelMode.SubtitleSize -> {
                val size = SUBTITLE_TEXT_SIZE_OPTIONS_SP.getOrNull(position) ?: return
                if (size == currentSubtitleTextSizeSp) return
                currentSubtitleTextSizeSp = size
                applySubtitleTextSize()
                savePlayerPrefs()
                hidePanel()
            }
            PanelMode.Decoder -> {
                val pref = DECODER_OPTIONS.getOrNull(position) ?: return
                if (pref == decoderPreference) return
                val keep = currentPositionSeconds()
                decoderManuallyOverridden = true
                decoderPreference = pref
                savePlayerPrefs()
                lifecycleScope.launch {
                    rebuildPlayerForDecoderPreference(keep)
                    hidePanel()
                }
            }
            PanelMode.Playlist -> {
                val idx = position.coerceIn(0, (playlist.size - 1).coerceAtLeast(0))
                if (idx == currentIndex) return
                currentIndex = idx
                lifecycleScope.launch { prepareAndPlay(keepPositionSeconds = null, showResumeDialog = true) }
                hidePanel()
            }
            null -> {}
        }
    }

    private fun buildOptionsRows(): List<TvPanelRow> {
        val audio = if (noAudioMode) "-" else currentAudioLabel.ifEmpty { "-" }
        val sub = currentSubtitleLabel.ifEmpty { "-" }
        return buildVisibleOptionActions().map { action ->
            when (action) {
                OptionAction.Previous -> TvPanelRow(getString(R.string.player_action_previous), currentItemDisplayName(currentIndex - 1))
                OptionAction.Next -> TvPanelRow(getString(R.string.player_action_next), currentItemDisplayName(currentIndex + 1))
                OptionAction.Quality -> TvPanelRow(getString(R.string.player_setting_quality), qualityLabel(currentQuality))
                OptionAction.Speed -> TvPanelRow(getString(R.string.player_setting_speed), "${playbackSpeed}x")
                OptionAction.Audio -> TvPanelRow(getString(R.string.player_setting_audio_track), audio)
                OptionAction.Subtitle -> TvPanelRow(getString(R.string.player_setting_subtitle_track), sub)
                OptionAction.SubtitleSize -> TvPanelRow(getString(R.string.player_setting_subtitle_size), subtitleTextSizeLabel(currentSubtitleTextSizeSp))
                OptionAction.Decoder -> TvPanelRow(getString(R.string.player_setting_decoder), decoderPreferenceLabel())
                OptionAction.Playlist -> TvPanelRow(getString(R.string.player_setting_show_playlist), playlistRowSummary())
            }
        }
    }

    private fun buildVisibleOptionActions(): List<OptionAction> {
        val out = ArrayList<OptionAction>(9)
        if (currentIndex > 0) out += OptionAction.Previous
        if (currentIndex < playlist.lastIndex) out += OptionAction.Next
        out += OptionAction.Quality
        out += OptionAction.Speed
        out += OptionAction.Audio
        out += OptionAction.Subtitle
        if (!isUsingVlcBackend()) {
            out += OptionAction.SubtitleSize
        }
        out += OptionAction.Decoder
        out += OptionAction.Playlist
        return out
    }

    private fun buildQualityRows(): List<TvPanelRow> {
        return QUALITY_OPTIONS.map { q ->
            val mark = if (q == currentQuality) "✓" else ""
            TvPanelRow(title = "${qualityLabel(q)} $mark".trim(), subtitle = q)
        }
    }

    private fun buildSpeedRows(): List<TvPanelRow> {
        return SPEED_OPTIONS.map { sp ->
            val mark = if (sp == playbackSpeed) "✓" else ""
            TvPanelRow(title = "${sp}x $mark".trim(), subtitle = "")
        }
    }

    private fun buildAudioRows(): List<TvPanelRow> {
        if (audioTracks.isEmpty()) return listOf(TvPanelRow("-", ""))
        return audioTracks.map { t ->
            val mark = if (t.label == currentAudioLabel) "✓" else ""
            TvPanelRow(title = "${t.label} $mark".trim(), subtitle = "")
        }
    }

    private fun buildSubtitleRows(): List<TvPanelRow> {
        val no = getString(R.string.player_no_subtitle)
        val out = ArrayList<TvPanelRow>()
        val mark0 = if (currentSubtitleLabel == no) "✓" else ""
        out += TvPanelRow(title = "$no $mark0".trim(), subtitle = "")
        out += TvPanelRow(title = getString(R.string.player_setting_subtitle_search), subtitle = "")
        for (t in subtitleTracks) {
            val mark = if (t.label == currentSubtitleLabel) "✓" else ""
            out +=
                TvPanelRow(
                    title = "${t.label} $mark".trim(),
                    subtitle = if (t.isExternal) getString(R.string.player_subtitle_external) else "",
                )
        }
        return out
    }

    private fun buildSubtitleSizeRows(): List<TvPanelRow> {
        return SUBTITLE_TEXT_SIZE_OPTIONS_SP.map { size ->
            val mark = if (size == currentSubtitleTextSizeSp) "✓" else ""
            TvPanelRow("${subtitleTextSizeLabel(size)} $mark".trim(), "${size.toInt()}sp")
        }
    }

    private fun buildDecoderRows(): List<TvPanelRow> {
        return DECODER_OPTIONS.map { pref ->
            val mark = if (pref == decoderPreference) "✓" else ""
            TvPanelRow("${decoderPreferenceLabel(pref)} $mark".trim(), "")
        }
    }

    private fun buildPlaylistRows(): List<TvPanelRow> {
        return playlist.mapIndexed { idx, it ->
            val name = it.name.ifEmpty { it.path.substringAfterLast('/') }
            val mark = if (idx == currentIndex) "▶" else ""
            TvPanelRow(title = "$mark $name".trim(), subtitle = it.path)
        }
    }

    private fun playlistRowSummary(): String {
        val total = playlist.size
        val idx = (currentIndex + 1).coerceIn(1, total.coerceAtLeast(1))
        return "$idx / $total"
    }

    private fun currentItemDisplayName(index: Int = currentIndex): String {
        val item = playlist.getOrNull(index) ?: return ""
        return item.name.ifEmpty { item.path.substringAfterLast('/') }
    }

    private fun subtitleTextSizeLabel(sizeSp: Float): String {
        return when (sizeSp) {
            18f -> getString(R.string.player_subtitle_size_small)
            22f -> getString(R.string.player_subtitle_size_medium)
            26f -> getString(R.string.player_subtitle_size_large)
            30f -> getString(R.string.player_subtitle_size_xlarge)
            36f -> "36sp"
            42f -> "42sp"
            50f -> "50sp"
            else -> "${sizeSp.toInt()}sp"
        }
    }

    private fun decoderPreferenceLabel(pref: String = decoderPreference): String {
        return when (pref) {
            DECODER_PREF_SYSTEM -> getString(R.string.player_decoder_system)
            DECODER_PREF_VLC -> getString(R.string.player_decoder_vlc)
            else -> getString(R.string.player_decoder_system)
        }
    }

    private fun loadPlayerPrefs() {
        val prefs = getSharedPreferences(PREFS_PLAYER_UI, Context.MODE_PRIVATE)
        val saved = prefs.getFloat(KEY_SUBTITLE_TEXT_SIZE_SP, DEFAULT_SUBTITLE_TEXT_SIZE_SP)
        currentSubtitleTextSizeSp =
            SUBTITLE_TEXT_SIZE_OPTIONS_SP.firstOrNull { it == saved }
                ?: DEFAULT_SUBTITLE_TEXT_SIZE_SP
        decoderPreference =
            prefs.getString(KEY_DECODER_PREFERENCE, DECODER_PREF_VLC)
                ?.takeIf { it in DECODER_OPTIONS }
                ?: DECODER_PREF_VLC
        currentQuality = VideoPlaybackSettingsStore.getDefaultQuality(this)
    }

    private fun savePlayerPrefs() {
        getSharedPreferences(PREFS_PLAYER_UI, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_SUBTITLE_TEXT_SIZE_SP, currentSubtitleTextSizeSp)
            .putString(KEY_DECODER_PREFERENCE, decoderPreference)
            .apply()
    }

    private fun applySubtitleTextSize() {
        configureSubtitleView()
    }

    private fun playAdjacent(offset: Int): Boolean {
        val targetIndex = currentIndex + offset
        if (targetIndex !in playlist.indices) return false
        currentIndex = targetIndex
        lifecycleScope.launch {
            prepareAndPlay(keepPositionSeconds = null, showResumeDialog = true)
        }
        return true
    }

    private fun resetPlaybackFallbackState() {
        noAudioMode = currentQuality == QUALITY_ORIGINAL && audioTracks.isEmpty()
        triedNoAudioFallback = false
        autoSwitchedToTranscode = false
    }

    private fun defaultTranscodeQuality(): String {
        return QUALITY_OPTIONS.firstOrNull { it == "1080p_5m" }
            ?: QUALITY_OPTIONS.firstOrNull { it == "720p_2m" }
            ?: QUALITY_OPTIONS.firstOrNull { it != QUALITY_ORIGINAL }
            ?: QUALITY_ORIGINAL
    }

    private suspend fun applyAudioSelection() {
        if (currentQuality != QUALITY_ORIGINAL) return
        if (isUsingVlcBackend()) {
            val mp = vlcPlayer ?: return
            if (noAudioMode) {
                runCatching { mp.audioTrack = -1 }
                return
            }
            val selectedTrack = audioTracks.firstOrNull { it.label == currentAudioLabel }
            val audioTrackId = resolveVlcAudioTrackId(selectedTrack?.mapIndex)
            if (audioTrackId != null) {
                runCatching { mp.audioTrack = audioTrackId }
            }
            return
        }
        val selector = trackSelector ?: return
        val builder = selector.parameters.buildUpon()
        if (noAudioMode) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
        } else {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            builder.clearOverridesOfType(C.TRACK_TYPE_AUDIO)
            val selected = audioTracks.indexOfFirst { it.label == currentAudioLabel }
            val trackRef = currentAudioTrackRefs.getOrNull(selected) ?: currentAudioTrackRefs.firstOrNull()
            if (trackRef != null) {
                builder.setOverrideForType(TrackSelectionOverride(trackRef.mediaTrackGroup, 0))
            }
        }
        selector.setParameters(builder)
    }

    private suspend fun applySubtitleChangeForOriginalQuality() {
        applySubtitleSelection()
    }

    private suspend fun applySubtitleSelection() {
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        if (currentQuality != QUALITY_ORIGINAL) return
        if (isUsingVlcBackend()) {
            val mp = vlcPlayer ?: return
            if (currentSubtitleLabel == noSubtitleLabel) {
                clearClientSubtitle()
                runCatching { mp.spuTrack = -1 }
                lastExternalSubtitleUrl = null
                return
            }
            val selected = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel } ?: return
            if (selected.isExternal) {
                val ext = selected.externalPath?.trim().orEmpty()
                if (ext.isEmpty()) return
                val subUrl = P2pLocalHttpProxy.proxyUrlIfNeeded(buildSubtitleUrl(ext))
                if (subUrl.isEmpty()) return
                clearClientSubtitle()
                if (lastExternalSubtitleUrl == subUrl) {
                    applySelectVlcExternalSidecarSpuTrack()
                    scheduleVlcExternalSidecarSubtitleSelectRetries()
                    return
                }
                lastExternalSubtitleUrl = subUrl
                hotSwapVlcExternalSubtitle(subUrl)
                return
            }
            clearClientSubtitle()
            lastExternalSubtitleUrl = null
            val subtitleTrackId = resolveVlcSubtitleTrackId(selected.mapIndex)
            if (subtitleTrackId != null) {
                runCatching { mp.spuTrack = subtitleTrackId }
            }
            return
        }
        val selector = trackSelector ?: return
        if (currentSubtitleLabel == noSubtitleLabel) {
            clearClientSubtitle()
            selector.setParameters(
                selector.parameters
                    .buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT),
            )
            lastExternalSubtitleUrl = null
            return
        }
        val selected = subtitleTracks.indexOfFirst { it.label == currentSubtitleLabel }
        if (selected < 0) return
        val t = subtitleTracks[selected]
        if (t.isExternal) {
            val ext = t.externalPath?.trim().orEmpty()
            if (ext.isEmpty()) return
            val subUrl = P2pLocalHttpProxy.proxyUrlIfNeeded(buildSubtitleUrl(ext))
            if (subUrl.isEmpty()) return
            clearClientSubtitle()
            if (lastExternalSubtitleUrl == subUrl) {
                maybeSelectExternalSidecarTextTrack()
                return
            }
            lastExternalSubtitleUrl = subUrl
            hotSwapExoExternalSubtitle(subUrl, ext, t.label)
            return
        }
        clearClientSubtitle()
        lastExternalSubtitleUrl = null
        val internalIndex = subtitleTracks.take(selected + 1).count { !it.isExternal } - 1
        val trackRef = currentSubtitleTrackRefs.getOrNull(internalIndex) ?: return
        selector.setParameters(
            selector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setOverrideForType(TrackSelectionOverride(trackRef.mediaTrackGroup, 0)),
        )
    }

    private fun hotSwapExoExternalSubtitle(
        subUrl: String,
        extPath: String,
        label: String,
    ) {
        val mp = player ?: return
        val item = playlist.getOrNull(currentIndex) ?: return
        val proxied = currentPlaybackUrl?.trim().orEmpty()
        if (proxied.isEmpty()) return
        val posMs = mp.currentPosition.coerceAtLeast(0)
        val wasPlaying = mp.isPlaying
        val config =
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(subUrl))
                .setMimeType(subtitleMimeType(extPath))
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .setLabel(label)
                .build()
        val mediaItem =
            MediaItem.Builder()
                .setUri(Uri.parse(proxied))
                .applyPlaybackMimeType(path = item.path, internalPath = item.internalPath, isTranscode = false)
                .setSubtitleConfigurations(listOf(config))
                .build()
        mp.setMediaItem(mediaItem, posMs)
        mp.prepare()
        if (wasPlaying) {
            mp.playWhenReady = true
            mp.play()
        }
        maybeSelectExternalSidecarTextTrack()
    }

    private fun hotSwapVlcExternalSubtitle(subUrl: String) {
        val mp = vlcPlayer ?: return
        runCatching { mp.spuTrack = -1 }
        val mrl = VLCUtil.encodeVLCUri(Uri.parse(subUrl))
        val added = runCatching { mp.addSlave(IMedia.Slave.Type.Subtitle, mrl, true) }.getOrDefault(false)
        if (!added) {
            val keep = currentPositionSeconds()
            playCurrent(startSeconds = keep)
            return
        }
        applySelectVlcExternalSidecarSpuTrack()
        scheduleVlcExternalSidecarSubtitleSelectRetries()
    }

    private fun resolveVlcAudioTrackId(mapIndex: Int?): Int? {
        val tracks = vlcPlayer?.audioTracks?.filter { it.id != -1 }.orEmpty()
        if (tracks.isEmpty()) return null
        val index = mapIndex ?: 0
        return tracks.getOrNull(index)?.id ?: tracks.firstOrNull()?.id
    }

    private fun resolveVlcSubtitleTrackId(mapIndex: Int?): Int? {
        val tracks = vlcPlayer?.spuTracks?.filter { it.id != -1 }.orEmpty()
        if (tracks.isEmpty()) return null
        val index = mapIndex ?: 0
        return tracks.getOrNull(index)?.id ?: tracks.firstOrNull()?.id
    }

    private fun bindBackPressed() {
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (panelMode != null) {
                        hidePanel()
                        return
                    }
                    showExitConfirm()
                }
            },
        )
    }

    private fun showExitConfirm() {
        val wasPlaying = isPlaybackPlaying()
        if (wasPlaying) runCatching { pausePlayback() }
        val dialog = AlertDialog.Builder(this)
            .setTitle(getString(R.string.player_exit_title))
            .setMessage(getString(R.string.player_exit_message))
            .setPositiveButton(getString(R.string.action_ok)) { _, _ ->
                closeAndFinish()
            }
            .setNegativeButton(getString(R.string.action_cancel)) { _, _ ->
                if (wasPlaying) runCatching { resumePlayback() }
            }
            .setOnCancelListener {
                if (wasPlaying) runCatching { resumePlayback() }
            }
            .create()
        dialog.show()
        dialog.getButton(AlertDialog.BUTTON_POSITIVE)?.requestFocus()
    }

    /**
     * 在播放器内显示「是否继续播放」提示，样式与退出确认对话框一致；不操作时 5 秒后自动消失。
     * 标题后显示自动关闭倒计时；焦点默认在「继续播放」。
     * 当前已从 resumePositionSeconds 开始播放，用户可选择「从开头播放」跳转到 0。
     */
    private fun showResumeConfirmOverlay(resumePositionSeconds: Int) {
        resumeDialogAutoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        resumeDialogAutoDismissRunnable = null
        val msg = getString(R.string.player_resume_message, formatTime(resumePositionSeconds))
        var dialogRef: AlertDialog? = null
        val dismissRunnable = Runnable {
            dialogRef?.dismiss()
            resumeDialogAutoDismissRunnable = null
        }
        resumeDialogAutoDismissRunnable = dismissRunnable
        val resumeTitle = getString(R.string.player_resume_title)
        val titleView = TextView(this).apply {
            text = resumeTitle + getString(R.string.player_resume_auto_close, 5)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            val padPx = (24 * resources.displayMetrics.density).toInt()
            setPadding(padPx, padPx, padPx, 0)
        }
        var countdownRunnable: Runnable? = null
        countdownRunnable = object : Runnable {
            var count = 5
            override fun run() {
                count--
                if (count > 0 && dialogRef?.isShowing == true) {
                    titleView.text = resumeTitle + getString(R.string.player_resume_auto_close, count)
                    countdownRunnable?.let { mainHandler.postDelayed(it, 1000L) }
                }
            }
        }
        dialogRef = AlertDialog.Builder(this)
            .setCustomTitle(titleView)
            .setMessage(msg)
            .setPositiveButton(getString(R.string.player_resume_title)) { _, _ ->
                countdownRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable = null
                dialogRef?.dismiss()
            }
            .setNegativeButton(getString(R.string.player_resume_from_start)) { _, _ ->
                countdownRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable = null
                dialogRef?.dismiss()
                seekToSeconds(0)
            }
            .setOnCancelListener {
                countdownRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
                resumeDialogAutoDismissRunnable = null
            }
            .create()
        dialogRef?.setOnDismissListener {
            countdownRunnable?.let { mainHandler.removeCallbacks(it) }
        }
        dialogRef?.show()
        mainHandler.postDelayed(countdownRunnable, 1000L)
        mainHandler.postDelayed(dismissRunnable, RESUME_DIALOG_AUTO_DISMISS_MS)
        dialogRef?.getButton(AlertDialog.BUTTON_POSITIVE)?.requestFocus()
    }

    private fun closeAndFinish() {
        if (isClosingPlayer) return
        isClosingPlayer = true
        runCatching { stopTranscodingIfNeeded() }
        runCatching { stopAutoSave() }
        runCatching { stopUiLoop() }
        runCatching { hidePanel() }
        runCatching { hideControls() }
        runCatching { stopPlayback() }
        runCatching { releasePlayer() }
        finish()
    }

    private fun bindSeekBar() {
        seekBar.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                controlsVisible = true
                controlsContainer.visibility = View.VISIBLE
            }
            scheduleAutoHide()
        }
        seekBar.setOnKeyListener { _, keyCode, event ->
            handleSeekKeyEvent(keyCode, event)
        }
    }

    private fun handleSeekKeyEvent(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode != KeyEvent.KEYCODE_DPAD_LEFT && keyCode != KeyEvent.KEYCODE_DPAD_RIGHT) return false
        if (panelMode != null) return false

        if (currentQuality != QUALITY_ORIGINAL) {
            // 转码模式：仅正常播放时响应快进；加载中或快进完成后 2 秒内不响应方向键，避免连续触发崩溃
            val now = SystemClock.uptimeMillis()
            if (now < transcodeSeekKeyBlockedUntilUptimeMs) return true
            if (loading.visibility == View.VISIBLE) return true
            if (!isPlaybackPlaying()) return true
        }

        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                showControls(autoHide = true)
                if (event.repeatCount == 0) {
                    if (seekKeyHeld) {
                        mainHandler.removeCallbacks(startContinuousSeekRunnable)
                        mainHandler.removeCallbacks(continuousSeekTickRunnable)
                    }
                    seekKeyHeld = true
                    seekHeldKeyCode = keyCode
                    mainHandler.removeCallbacks(commitSeekRunnable)
                    applySeekStep(keyCode)
                    mainHandler.removeCallbacks(startContinuousSeekRunnable)
                    mainHandler.postDelayed(startContinuousSeekRunnable, 350L)
                } else if (currentQuality == QUALITY_ORIGINAL) {
                    // 某些设备长按不会触发我们的定时器，但会持续派发 repeat 事件。
                    applySeekStep(keyCode)
                }
                return true
            }
            KeyEvent.ACTION_UP -> {
                if (!seekKeyHeld) return true
                if (seekHeldKeyCode != keyCode) return true
                seekKeyHeld = false
                mainHandler.removeCallbacks(startContinuousSeekRunnable)
                mainHandler.removeCallbacks(continuousSeekTickRunnable)
                mainHandler.removeCallbacks(commitSeekRunnable)
                mainHandler.postDelayed(commitSeekRunnable, 300L)
                return true
            }
            else -> return true
        }
    }

    private fun applySeekStep(keyCode: Int) {
        val dur = currentDurationSeconds() ?: return
        val base = seekAdjustTargetSeconds ?: currentPositionSeconds()
        val delta = if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) 30 else -10
        val next = (base + delta).coerceIn(0, dur)
        seekAdjustTargetSeconds = next
        showSeekPreview(targetSeconds = next, totalSeconds = dur)
    }

    private fun commitSeekTargetSeconds(seconds: Int) {
        if (currentQuality == QUALITY_ORIGINAL) {
            seekToSeconds(seconds)
            return
        }
        pendingTranscodeSeekSeconds = seconds
        updateSeekBar()
        mainHandler.removeCallbacks(restartTranscodeRunnable)
        mainHandler.post(restartTranscodeRunnable)
        scheduleAutoHide()
    }

    private fun cancelPendingSeekAdjust() {
        seekKeyHeld = false
        seekHeldKeyCode = 0
        seekAdjustTargetSeconds = null
        mainHandler.removeCallbacks(startContinuousSeekRunnable)
        mainHandler.removeCallbacks(continuousSeekTickRunnable)
        mainHandler.removeCallbacks(commitSeekRunnable)
        mainHandler.removeCallbacks(restartOriginalRemuxRunnable)
    }

    private suspend fun ensureApiReadyForPlayback() {
        if (ApiController.baseUrl.trim().isNotEmpty()) return
        val store = ServerStore(applicationContext, Gson())
        val last = runCatching { store.lastSelectedFlow.first() }.getOrNull() ?: return
        ApiController.setTokens(
            last.accessToken,
            last.refreshToken,
            last.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
            last.serverVersion.trim().takeIf { it.isNotEmpty() },
        )

        val direct = last.serverUrl.trim()
        if (direct.isNotEmpty()) {
            ApiController.setBaseUrl(direct)
            return
        }

        val code = last.pairCode.trim()
        if (code.isEmpty()) return
        val pref =
            when (ApiController.getDevConnectMode()) {
                ApiController.DevConnectMode.P2pDirect -> P2pIcePreference.DirectOnly
                ApiController.DevConnectMode.P2pRelay -> P2pIcePreference.RelayOnly
                else -> P2pIcePreference.Auto
            }
        runCatching { ApiController.connectP2pByPairCode(code, icePreference = pref) }
        if (ApiController.baseUrl.trim().isEmpty()) {
            ApiController.setBaseUrl(ApiConfig.p2pBaseUrl)
        }
    }

    private fun updateCurrentTrackRefs(tracks: Tracks) {
        currentAudioTrackRefs =
            tracks.groups.filter { group ->
                group.type == C.TRACK_TYPE_AUDIO && group.length > 0
            }
        currentSubtitleTrackRefs =
            tracks.groups.filter { group ->
                group.type == C.TRACK_TYPE_TEXT && group.length > 0
            }
    }

    /**
     * 原画非 remux：侧挂字幕与主片合并后，需显式启用 TEXT 并选中轨道；否则常出现「URL 已带上字幕但画面无字」。
     */
    private fun maybeSelectExternalSidecarTextTrack() {
        if (currentQuality != QUALITY_ORIGINAL || isUsingVlcBackend()) return
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        if (currentSubtitleLabel == noSubtitleLabel) return
        val sel = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel } ?: return
        if (!sel.isExternal) return
        if (sel.externalPath?.trim().orEmpty().isEmpty()) return
        val selector = trackSelector ?: return
        val refs = currentSubtitleTrackRefs
        if (refs.isEmpty()) return
        val group =
            when {
                refs.size == 1 -> refs.first()
                else -> refs.last()
            }
        if (group.length <= 0) return
        selector.setParameters(
            selector.parameters
                .buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
                .build(),
        )
    }

    /** VLC 外挂字幕轨略晚于首包，与「首启 URL 已匹配」分支配合 */
    private fun scheduleVlcExternalSidecarSubtitleSelectRetries() {
        if (!isUsingVlcBackend()) return
        if (currentQuality != QUALITY_ORIGINAL) return
        val no = getString(R.string.player_no_subtitle)
        if (currentSubtitleLabel == no) return
        val selected = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel } ?: return
        if (!selected.isExternal) return
        val runnable =
            Runnable {
                if (!isUsingVlcBackend()) return@Runnable
                if (currentSubtitleLabel == getString(R.string.player_no_subtitle)) return@Runnable
                applySelectVlcExternalSidecarSpuTrack()
            }
        mainHandler.postDelayed(runnable, 120L)
        mainHandler.postDelayed(runnable, 450L)
        mainHandler.postDelayed(runnable, 1200L)
    }

    /** 原画外挂：slave 轨常在片内嵌轨之后，单轨时取首条即可 */
    private fun selectVlcExternalSidecarSpuTrackId(): Int? {
        val spu = vlcPlayer?.spuTracks?.filter { it.id != -1 }.orEmpty()
        return when {
            spu.isEmpty() -> null
            spu.size == 1 -> spu.first().id
            else -> spu.last().id
        }
    }

    private fun applySelectVlcExternalSidecarSpuTrack() {
        val id = selectVlcExternalSidecarSpuTrackId() ?: return
        runCatching { vlcPlayer?.spuTrack = id }
    }

    private fun onPlayerStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_READY -> {
                clearSeekRecovery()
                playRetryCount = 0
                applyPlaybackSpeed()
                loading.post { loading.visibility = View.GONE }
                mainHandler.post { updateKeepScreenOn() }
                lifecycleScope.launch {
                    if (currentQuality == QUALITY_ORIGINAL) {
                        applyAudioSelection()
                        applySubtitleSelection()
                        maybeSelectExternalSidecarTextTrack()
                    }
                }
            }
            Player.STATE_BUFFERING -> {
                loading.post { loading.visibility = View.VISIBLE }
                scheduleBufferingRecoveryCheck()
            }
            Player.STATE_ENDED -> {
                clearSeekRecovery()
                lifecycleScope.launch { handlePlaybackEnded() }
            }
        }
    }

    private fun onPlayerError(error: PlaybackException) {
        clearSeekRecovery()
        val resumePos = lastKnownPositionSeconds
        val cause = error.cause
        android.util.Log.e(
            "TvVideoPlayer",
            "Player error code=${error.errorCode} codeName=${error.errorCodeName} " +
                "message=${error.message.orEmpty()} retryCount=$playRetryCount resumePos=$resumePos " +
                "quality=$currentQuality mime=${currentPlaybackMimeType.orEmpty()} " +
                "url=${currentPlaybackUrl.orEmpty().take(200)} " +
                "cause=${cause?.javaClass?.simpleName}:${cause?.message.orEmpty()}",
            error,
        )
        lifecycleScope.launch {
            if (currentQuality == QUALITY_ORIGINAL) {
                if (!noAudioMode && !triedNoAudioFallback) {
                    triedNoAudioFallback = true
                    noAudioMode = true
                    loading.post { loading.visibility = View.VISIBLE }
                    delay(300)
                    playCurrent(startSeconds = resumePos)
                    return@launch
                }
                if (!autoSwitchedToTranscode) {
                    val fallbackQ = defaultTranscodeQuality()
                    if (fallbackQ != QUALITY_ORIGINAL) {
                        autoSwitchedToTranscode = true
                        noAudioMode = false
                        triedNoAudioFallback = false
                        currentQuality = fallbackQ
                        loading.post { loading.visibility = View.VISIBLE }
                        delay(300)
                        playCurrent(startSeconds = resumePos)
                        return@launch
                    }
                }
            }
            if (playRetryCount < 3) {
                playRetryCount++
                loading.post { loading.visibility = View.VISIBLE }
                delay(1_500)
                if (ApiController.isP2pMode) {
                    runCatching { ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000) }
                }
                prepareAndPlay(keepPositionSeconds = resumePos, showResumeDialog = false)
            } else {
                loading.post { loading.visibility = View.GONE }
                showReconnectDialog(resumePos)
            }
        }
    }

    private suspend fun handlePlaybackEnded() {
        clearSeekRecovery()
        val dur = lastKnownDurationSeconds
        val pos = lastKnownPositionSeconds
        val isPrematureEnd = dur != null && dur > 0 && pos + 5 < dur
        if (isPrematureEnd) {
            if (playRetryCount < 3) {
                playRetryCount++
                loading.post { loading.visibility = View.VISIBLE }
                delay(1_500)
                if (ApiController.isP2pMode) {
                    runCatching { ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000) }
                }
                prepareAndPlay(keepPositionSeconds = pos, showResumeDialog = false)
                return
            }
            loading.post { loading.visibility = View.GONE }
            showReconnectDialog(pos)
            return
        }
        saveProgress(forceZero = true)
        mainHandler.post { updateKeepScreenOn() }
        playNextOrExit()
    }

    private suspend fun showPlayFailedDialog() {
        AlertDialog.Builder(this@TvVideoPlayerActivity)
            .setTitle(getString(R.string.error_title))
            .setMessage(getString(R.string.player_play_failed))
            .setPositiveButton(getString(R.string.action_ok), null)
            .show()
    }

    private fun showReconnectDialog(resumePos: Int) {
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.player_reconnect_title))
            .setMessage(getString(R.string.player_reconnect_message))
            .setPositiveButton(getString(R.string.player_reconnect_retry)) { _, _ ->
                playRetryCount = 0
                loading.visibility = View.VISIBLE
                lifecycleScope.launch {
                    delay(500)
                    if (ApiController.isP2pMode) {
                        runCatching { ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000) }
                    }
                    prepareAndPlay(keepPositionSeconds = resumePos, showResumeDialog = false)
                }
            }
            .setNegativeButton(getString(R.string.player_reconnect_exit)) { _, _ ->
                finish()
            }
            .setCancelable(false)
            .show()
    }

    private suspend fun playNextOrExit() {
        if (playlist.isEmpty()) {
            finish()
            return
        }
        val next = currentIndex + 1
        if (next >= playlist.size) {
            finish()
            return
        }
        currentIndex = next
        prepareAndPlay(keepPositionSeconds = null, showResumeDialog = true)
    }

    private fun startUiLoop() {
        if (uiJob != null) return
        uiJob =
            lifecycleScope.launch {
                while (isActive) {
                    delay(500)
                    updateSeekBar()
                }
            }
    }

    private fun stopUiLoop() {
        uiJob?.cancel()
        uiJob = null
    }

    private fun startAutoSave() {
        if (autoSaveJob != null) return
        autoSaveJob =
            lifecycleScope.launch {
                while (isActive) {
                    delay(30_000)
                    if (!isPlaybackPlaying()) continue
                    saveProgress()
                }
            }
    }

    private fun stopAutoSave() {
        autoSaveJob?.cancel()
        autoSaveJob = null
    }

    private suspend fun saveProgress(forceZero: Boolean = false) {
        val item = playlist.getOrNull(currentIndex) ?: return
        val pos = if (forceZero) 0 else currentPositionSeconds()
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        val subtitle = if (currentSubtitleLabel == noSubtitleLabel) noSubtitleLabel else currentSubtitleLabel
        runCatching {
            TvVideoPlayerApiService.savePreference(
                filePath = item.path,
                playbackPositionSeconds = pos,
                audioLabel = currentAudioLabel,
                subtitleLabel = subtitle,
            )
        }
    }

    private fun stopTranscodingIfNeeded() {
        val id = playId ?: return
        playId = null
        transcodeBaseSeconds = 0
        pendingTranscodeSeekSeconds = null
        pendingOriginalStreamSeekSeconds = null
        TvVideoPlayerApiService.stopTranscodingAsync(id)
    }

    /** 转码文本字幕：subtitle-vtt + SubtitleView；原画/位图仍走原生 sidecar 或转码烧录。 */
    private fun useClientSubtitleOverlay(): Boolean {
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        if (currentSubtitleLabel.isEmpty() || currentSubtitleLabel == noSubtitleLabel) return false
        if (currentQuality == QUALITY_ORIGINAL) return false
        return !subtitleLabelNeedsTranscodeBurn(currentSubtitleLabel)
    }

    private fun subtitleLabelNeedsTranscodeBurn(label: String): Boolean {
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        if (label.isEmpty() || label == noSubtitleLabel) return false
        val track = subtitleTracks.firstOrNull { it.label == label } ?: return false
        if (track.isExternal) {
            val path = track.externalPath?.trim().orEmpty()
            val dot = path.lastIndexOf('.')
            val ext = if (dot >= 0) path.substring(dot).lowercase() else ""
            return TvSubtitleBitmapUtil.isBitmapExternalExtension(ext)
        }
        return TvSubtitleBitmapUtil.isBitmapCodecName(track.codecName)
    }

    private fun clearClientSubtitle() {
        val hadClientOverlay = clientSubtitleCues.isNotEmpty() || clientSubtitleCacheKey.isNotEmpty()
        clientSubtitleCues = emptyList()
        clientSubtitleCacheKey = ""
        clientSubtitleView.setCues(emptyList())
        clientSubtitleView.visibility = View.GONE
        if (hadClientOverlay && !isUsingVlcBackend()) {
            playerView.subtitleView?.setCues(emptyList())
        }
    }

    private fun updateClientSubtitleCue() {
        if (!useClientSubtitleOverlay()) {
            clearClientSubtitle()
            return
        }
        val renderView = subtitleRenderView()
        val posMs = currentPositionSeconds().coerceAtLeast(0).toLong() * 1000L
        val cue = TvWebVttParser.findActiveCue(clientSubtitleCues, posMs)
        val text = cue?.text?.trim().orEmpty()
        if (text.isEmpty() || renderView == null) {
            renderView?.setCues(emptyList())
            clientSubtitleView.visibility = View.GONE
            return
        }
        renderView.setCues(listOf(buildClientSubtitleCue(text)))
        if (isUsingVlcBackend()) {
            clientSubtitleView.visibility = View.VISIBLE
            clientSubtitleView.bringToFront()
        } else {
            clientSubtitleView.visibility = View.GONE
        }
    }

    private suspend fun loadClientSubtitleIfNeeded(force: Boolean = false) {
        if (!useClientSubtitleOverlay()) {
            clearClientSubtitle()
            return
        }
        val item = playlist.getOrNull(currentIndex) ?: run {
            clearClientSubtitle()
            return
        }
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        val track = subtitleTracks.firstOrNull { it.label == currentSubtitleLabel } ?: run {
            clearClientSubtitle()
            return
        }
        val isExternal = track.isExternal
        val idx = track.mapIndex ?: 0
        val subPath = track.externalPath?.trim().orEmpty()
        val key =
            if (isExternal) {
                "ext:$subPath#$idx"
            } else {
                "emb:${item.path.trim()}#$idx"
            }
        if (!force && key == clientSubtitleCacheKey && clientSubtitleCues.isNotEmpty()) {
            updateClientSubtitleCue()
            return
        }
        if (clientSubtitleLoading) return
        clientSubtitleLoading = true
        clientSubtitleCacheKey = key
        try {
            val vtt =
                TvVideoPlayerApiService.fetchSubtitleVtt(
                    filePath = item.path,
                    subtitleIndex = if (isExternal) null else idx,
                    subtitlePath = if (isExternal) subPath.takeIf { it.isNotEmpty() } else null,
                )
            if (vtt.isNullOrBlank()) {
                clearClientSubtitle()
                return
            }
            clientSubtitleCues = TvWebVttParser.parseWebVtt(vtt)
            updateClientSubtitleCue()
        } catch (_: Throwable) {
            clearClientSubtitle()
        } finally {
            clientSubtitleLoading = false
        }
    }

    /** 转码中切换字幕：文本仅刷新 VTT；位图或从位图切走时才重启转码（对齐 Flutter）。 */
    private suspend fun applySubtitleTrackWhileTranscoding(prevLabel: String) {
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        val prevWasBitmapBurn = subtitleLabelNeedsTranscodeBurn(prevLabel)
        val nextNeedsBitmapBurn = subtitleLabelNeedsTranscodeBurn(currentSubtitleLabel)

        if (prevWasBitmapBurn && !nextNeedsBitmapBurn) {
            val keep = currentPositionSeconds()
            stopTranscodingIfNeeded()
            playCurrent(startSeconds = keep)
            loadClientSubtitleIfNeeded(force = true)
            return
        }

        if (currentSubtitleLabel != noSubtitleLabel && nextNeedsBitmapBurn) {
            val keep = currentPositionSeconds()
            stopTranscodingIfNeeded()
            playCurrent(startSeconds = keep)
            return
        }

        if (currentSubtitleLabel == noSubtitleLabel) {
            clearClientSubtitle()
            return
        }

        loadClientSubtitleIfNeeded(force = true)
    }

    private fun buildOriginalUrl(
        filePath: String,
        internalPath: String,
    ): String {
        val p = filePath.trim()
        if (p.startsWith("http://") || p.startsWith("https://")) return p
        val internal = internalPath.trim()
        val baseUrl = ApiController.baseUrl.trim().trimEnd('/')
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append(baseUrl)
        sb.append("/api/videoPlayer/rawFile?raw=1&path=").append(Uri.encode(p))
        if (internal.isNotEmpty()) sb.append("&internalPath=").append(Uri.encode(internal))
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        return sb.toString()
    }

    private fun buildSubtitleUrl(filePath: String): String {
        val p = filePath.trim()
        val baseUrl = ApiController.baseUrl.trim().trimEnd('/')
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append(baseUrl)
        sb.append("/api/file/rawFile?raw=1&path=").append(Uri.encode(p))
        sb.append("&p2pChannel=file")
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        return sb.toString()
    }

    private fun buildTranscodeUrl(
        filePath: String,
        seekSeconds: Int,
    ): String {
        val p = filePath.trim()
        val baseUrl = ApiController.baseUrl.trim().trimEnd('/')
        val token = ApiController.accessToken.trim()
        val id = UUID.randomUUID().toString()
        playId = id
        transcodeBaseSeconds = seekSeconds.coerceAtLeast(0)

        var width: Int? = null
        var bitrate: String? = null
        val q = currentQuality.trim()
        val parts = q.split('_')
        if (parts.size >= 2) {
            val res = parts[0].trim().lowercase()
            val br = parts[1].trim().lowercase()
            width =
                when (res) {
                    "4k" -> 3840
                    "1080p" -> 1920
                    "720p" -> 1280
                    "480p" -> 854
                    else -> null
                }
            val m = Regex("^(\\d+)(m|k)$").find(br)
            if (m != null) {
                val n = m.groupValues.getOrNull(1)?.toIntOrNull()
                val unit = m.groupValues.getOrNull(2)
                if (n != null && n > 0) {
                    bitrate = if (unit == "m") "${n * 1000}k" else "${n}k"
                }
            }
        }

        var audioIndex: Int? = null
        val a = currentAudioLabel.trim()
        if (a.isNotEmpty()) {
            audioIndex = audioTracks.firstOrNull { it.label == a }?.mapIndex
        }

        var subtitleIndex: Int? = null
        var subtitlePath: String? = null
        var burn = false
        val noSubtitleLabel = getString(R.string.player_no_subtitle)
        val s = currentSubtitleLabel.trim()
        if (s.isNotEmpty() && s != noSubtitleLabel && subtitleLabelNeedsTranscodeBurn(s)) {
            val track = subtitleTracks.firstOrNull { it.label == s }
            if (track != null) {
                if (track.isExternal) {
                    val extPath = track.externalPath?.trim().orEmpty()
                    if (extPath.isNotEmpty()) {
                        subtitlePath = extPath
                        burn = true
                    }
                } else {
                    subtitleIndex = track.mapIndex
                    burn = true
                }
            }
        }

        val sb = StringBuilder()
        sb.append(baseUrl)
        sb.append("/api/videoPlayer/transcode?playId=").append(Uri.encode(id))
        sb.append("&filePath=").append(Uri.encode(p))
        sb.append("&seek=").append(seekSeconds.coerceAtLeast(0))
        val deviceId = ApiController.getOrCreateVideoDeviceId()
        if (deviceId.isNotEmpty()) sb.append("&device_id=").append(Uri.encode(deviceId))
        if (width != null) sb.append("&width=").append(width)
        if (bitrate != null) sb.append("&bitrate=").append(Uri.encode(bitrate))
        if (audioIndex != null) sb.append("&audioIndex=").append(audioIndex)
        if (subtitleIndex != null) sb.append("&subtitleIndex=").append(subtitleIndex)
        if (subtitlePath != null) sb.append("&subtitlePath=").append(Uri.encode(subtitlePath))
        if (burn) sb.append("&subtitleBurn=true")
        sb.append("&p2pChannel=video")
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        return sb.toString()
    }

    private fun qualityLabel(q: String): String {
        return if (q == QUALITY_ORIGINAL) getString(R.string.player_quality_original) else q.replace('_', ' ').uppercase()
    }

    private fun formatTime(totalSeconds: Int): String {
        val s = totalSeconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%02d:%02d", m, sec)
    }

    /** 与 Flutter `DialogUtil.showInfoDialog` + `server_version_too_low` 一致（字幕搜索需服务端主版本 ≥ 6） */
    private fun showServerVersionTooLowForSubtitleSearch() {
        AlertDialog.Builder(this, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.tip))
            .setMessage(getString(R.string.server_version_too_low))
            .setPositiveButton(getString(R.string.action_ok), null)
            .show()
    }

    private fun openSubtitleSearchIfServerSupported() {
        if (!ApiController.isServerVersionAtLeast(6)) {
            showServerVersionTooLowForSubtitleSearch()
            return
        }
        showPanel(PanelMode.SubtitleSearch)
    }

    private suspend fun showConfirmDialog(title: String, message: String): Boolean? {
        val deferred = CompletableDeferred<Boolean?>()
        runOnUiThread {
            AlertDialog.Builder(this, R.style.Theme_NasCabTv_AlertDialog)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(getString(R.string.action_ok)) { _, _ -> deferred.complete(true) }
                .setNegativeButton(getString(R.string.action_cancel)) { _, _ -> deferred.complete(false) }
                .setOnCancelListener { deferred.complete(false) }
                .show()
        }
        return runCatching { deferred.await() }.getOrNull()
    }

    companion object {
        private const val EXTRA_PATHS = "paths"
        private const val EXTRA_NAMES = "names"
        private const val EXTRA_INTERNAL_PATHS = "internal_paths"
        private const val EXTRA_INITIAL_INDEX = "initialIndex"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_IGNORE_FIND_SUB = "ignoreFindSub"

        /** 转码快进时 pause 后等待再 stop，避免 VLC AudioTrack 原生线程未 Detach 崩溃 */
        private const val DELAY_BEFORE_STOP_MS = 1000L
        /** stop() 后再等一段时间再 setMedia+play，给 native 线程收尾 */
        private const val DELAY_AFTER_STOP_MS = 500L
        /** 转码重启完成后一段时间内不再立即响应新的快进重启，避免频繁 stop/play 崩溃 */
        private const val TRANSCODE_RESTART_COOLDOWN_MS = 2000L
        /** 转码快进防抖：按下后延迟多久再执行重启 */
        private const val TRANSCODE_SEEK_DEBOUNCE_MS = 500L
        /** 原画 remux-mp4 快进防抖，避免连续重建流 */
        private const val ORIGINAL_REMUX_SEEK_DEBOUNCE_MS = 300L
        /** 转码快进完成后不响应左右方向键的时长（毫秒），避免连续触发崩溃 */
        private const val TRANSCODE_SEEK_KEY_BLOCK_MS = 3000L
        /** 开始播放后延迟多久再显示「继续播放」提示对话框（毫秒） */
        private const val RESUME_DIALOG_SHOW_DELAY_MS = 600L
        /** 「继续播放」提示对话框无操作时自动消失时间（毫秒） */
        private const val RESUME_DIALOG_AUTO_DISMISS_MS = 5000L
        /** seek 后若持续 buffering，则自动补一次恢复 seek/重建播放 */
        private const val SEEK_BUFFERING_RECOVERY_TIMEOUT_MS = 2500L
        /** 系统内核 seek 后若停在已就绪但未播放，延迟补一次 play() */
        private const val SYSTEM_SEEK_RESUME_DELAY_MS = 900L
        private const val MAX_SEEK_RECOVERY_ATTEMPTS = 2
        private const val PREFS_PLAYER_UI = "video_player_ui_prefs"
        private const val KEY_SUBTITLE_TEXT_SIZE_SP = "subtitle_text_size_sp"
        private const val KEY_DECODER_PREFERENCE = "decoder_preference"
        private const val DEFAULT_SUBTITLE_TEXT_SIZE_SP = 22f

        private const val QUALITY_ORIGINAL = "original"
        private const val DECODER_PREF_SYSTEM = "system"
        private const val DECODER_PREF_VLC = "vlc"
        private val FORCE_TRANSCODE_EXTENSIONS =
            setOf(
                "m2ts",
                "mts",
                "m2t",
                "ts",
                "vob",
            )
        private val SUBTITLE_TEXT_SIZE_OPTIONS_SP =
            listOf(
                18f,
                22f,
                26f,
                30f,
                36f,
                42f,
                50f,
            )
        private val DECODER_OPTIONS =
            listOf(
                DECODER_PREF_SYSTEM,
                DECODER_PREF_VLC,
            )
        private val QUALITY_OPTIONS =
            listOf(
                "original",
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

        private val SPEED_OPTIONS =
            listOf(
                0.5f,
                0.75f,
                1.0f,
                1.25f,
                1.5f,
                2.0f,
            )

        fun newIntent(
            context: Context,
            playlist: List<TvPlaylistItem>,
            initialIndex: Int,
            title: String,
            ignoreFindSub: Int = 1,
        ): Intent {
            val paths = ArrayList<String>()
            val names = ArrayList<String>()
            val internalPaths = ArrayList<String>()
            for (p in playlist) {
                val path = p.path.trim()
                if (path.isEmpty()) continue
                paths += path
                names += p.name
                internalPaths += p.internalPath
            }
            return Intent(context, TvVideoPlayerActivity::class.java).apply {
                putStringArrayListExtra(EXTRA_PATHS, paths)
                putStringArrayListExtra(EXTRA_NAMES, names)
                putStringArrayListExtra(EXTRA_INTERNAL_PATHS, internalPaths)
                putExtra(EXTRA_INITIAL_INDEX, initialIndex)
                val t = title.trim()
                if (t.isNotEmpty()) putExtra(EXTRA_TITLE, t)
                putExtra(EXTRA_IGNORE_FIND_SUB, if (ignoreFindSub == 0) 0 else 1)
            }
        }
    }
}
