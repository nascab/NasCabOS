package com.nascabos.tv.modules.music.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import com.google.gson.Gson
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.modules.music.MusicListItem
import com.nascabos.tv.modules.music.MusicUrl
import com.nascabos.tv.modules.video_player.P2pLocalHttpProxy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import java.util.ArrayDeque
import java.util.Random

data class MusicPlaybackState(
    val playlist: List<MusicListItem> = emptyList(),
    val index: Int = 0,
    val repeatMode: RepeatMode = RepeatMode.Off,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
) {
    val current: MusicListItem? get() = playlist.getOrNull(index)
}

enum class RepeatMode {
    Off,
    One,
    All,
    Shuffle,
}

class MusicPlaybackService : Service() {
    private val binder = LocalBinder()
    private val gson = Gson()

    private val serviceJob: Job = SupervisorJob()
    private val scope = CoroutineScope(serviceJob + Dispatchers.Main.immediate)

    private var libVlc: LibVLC? = null
    private var player: MediaPlayer? = null
    private var stateJob: Job? = null

    private val _state = MutableStateFlow(MusicPlaybackState())
    val state: StateFlow<MusicPlaybackState> = _state.asStateFlow()

    private var mediaSession: MediaSession? = null
    private var audioManager: AudioManager? = null
    private val shuffleHistory = ArrayDeque<Int>()
    private val rng = Random()

    inner class LocalBinder : Binder() {
        fun service(): MusicPlaybackService = this@MusicPlaybackService
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        initMediaSession()
        initPlayer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action?.trim().orEmpty()
        when (action) {
            ACTION_START_PLAYLIST -> {
                val json = intent?.getStringExtra(EXTRA_PLAYLIST_JSON).orEmpty()
                val startIndex = intent?.getIntExtra(EXTRA_START_INDEX, 0) ?: 0
                val list =
                    runCatching {
                        gson.fromJson(json, Array<MusicListItem>::class.java)?.toList().orEmpty()
                    }.getOrNull().orEmpty()
                if (list.isNotEmpty()) {
                    setPlaylistAndPlay(list, startIndex)
                }
            }
            ACTION_TOGGLE -> toggle()
            ACTION_NEXT -> next()
            ACTION_PREV -> prev()
            ACTION_STOP -> stopAndExit()
            ACTION_PAUSE -> pause()
            ACTION_PLAY -> play()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stateJob?.cancel()
        releasePlayer()
        runCatching { mediaSession?.release() }
        mediaSession = null
        serviceJob.cancel()
    }

    fun setPlaylistAndPlay(items: List<MusicListItem>, startIndex: Int) {
        val safe = items.filter { it.resolvePlayablePath().trim().isNotEmpty() }
        if (safe.isEmpty()) return
        val idx = startIndex.coerceIn(0, (safe.size - 1).coerceAtLeast(0))
        shuffleHistory.clear()
        _state.update { it.copy(playlist = safe, index = idx) }
        updateNotification()
        updateMediaSession()
        playCurrent(resetPosition = true)
    }

    fun toggle() {
        val mp = player ?: return
        if (mp.isPlaying) pause() else play()
    }

    fun play() {
        val mp = player ?: return
        if (_state.value.playlist.isEmpty()) return
        if (!mp.isPlaying) {
            mp.play()
            _state.update { it.copy(isPlaying = true) }
            updateNotification()
            updateMediaSession()
        }
    }

    fun pause() {
        val mp = player ?: return
        if (mp.isPlaying) {
            mp.pause()
            _state.update { it.copy(isPlaying = false) }
            updateNotification()
            updateMediaSession()
        }
    }

    fun next() {
        val s = _state.value
        if (s.playlist.isEmpty()) return
        if (s.repeatMode == RepeatMode.Shuffle) {
            playShuffleNext()
            return
        }
        val next =
            if (s.index + 1 >= s.playlist.size) {
                if (s.repeatMode == RepeatMode.All) 0 else s.playlist.size - 1
            } else {
                s.index + 1
            }
        if (next == s.index) return
        _state.update { it.copy(index = next) }
        playCurrent(resetPosition = true)
    }

    fun prev() {
        val s = _state.value
        if (s.playlist.isEmpty()) return
        if (s.repeatMode == RepeatMode.Shuffle) {
            val prev = shuffleHistory.pollLast() ?: return
            _state.update { it.copy(index = prev, positionMs = 0L, durationMs = 0L) }
            playCurrent(resetPosition = true)
            return
        }
        val prev =
            if (s.index - 1 < 0) {
                if (s.repeatMode == RepeatMode.All) s.playlist.size - 1 else 0
            } else {
                s.index - 1
            }
        if (prev == s.index) return
        _state.update { it.copy(index = prev) }
        playCurrent(resetPosition = true)
    }

    fun playAt(index: Int) {
        val s = _state.value
        if (s.playlist.isEmpty()) return
        val next = index.coerceIn(0, s.playlist.size - 1)
        if (next == s.index) {
            playCurrent(resetPosition = false)
            return
        }
        if (s.repeatMode == RepeatMode.Shuffle) {
            shuffleHistory.clear()
            shuffleHistory.addLast(s.index)
        }
        _state.update { it.copy(index = next, positionMs = 0L, durationMs = 0L) }
        playCurrent(resetPosition = true)
    }

    fun cycleRepeatMode() {
        val next =
            when (_state.value.repeatMode) {
                RepeatMode.Off -> RepeatMode.All
                RepeatMode.All -> RepeatMode.One
                RepeatMode.One -> RepeatMode.Shuffle
                RepeatMode.Shuffle -> RepeatMode.Off
            }
        _state.update { it.copy(repeatMode = next) }
        if (next != RepeatMode.Shuffle) {
            shuffleHistory.clear()
        } else {
            shuffleHistory.clear()
        }
        updateNotification()
        updateMediaSession()
    }

    fun setFavorite(indexId: Int, favorite: Boolean) {
        val id = indexId.takeIf { it > 0 } ?: return
        _state.update { st ->
            if (st.playlist.isEmpty()) return@update st
            var changed = false
            val next =
                st.playlist.map { item ->
                    if (item.id == id && item.isFavorite != favorite) {
                        changed = true
                        item.copy(isFavorite = favorite)
                    } else {
                        item
                    }
                }
            if (changed) st.copy(playlist = next) else st
        }
    }

    fun seekTo(ms: Long) {
        val mp = player ?: return
        val target = ms.coerceAtLeast(0)
        runCatching { mp.time = target }
    }

    private fun playShuffleNext() {
        val s = _state.value
        val size = s.playlist.size
        if (size <= 0) return
        val current = s.index.coerceIn(0, size - 1)
        val next = pickRandomIndex(size, current)
        if (next == current) return
        shuffleHistory.addLast(current)
        while (shuffleHistory.size > 100) shuffleHistory.removeFirst()
        _state.update { it.copy(index = next, positionMs = 0L, durationMs = 0L) }
        playCurrent(resetPosition = true)
    }

    private fun pickRandomIndex(size: Int, current: Int): Int {
        if (size <= 1) return current
        var cand = current
        var tries = 0
        while (tries < 6 && cand == current) {
            cand = rng.nextInt(size)
            tries++
        }
        return if (cand == current) (current + 1) % size else cand
    }

    private fun initPlayer() {
        if (libVlc != null && player != null) return
        val options =
            arrayListOf(
                "--no-drop-late-frames",
                "--no-skip-frames",
                "--network-caching=800",
                "--file-caching=800",
                "--codec=all",
                "--avcodec-fast",
                "--aout=opensles",
                "--audio-time-stretch",
                "--no-video",
            )
        val lv = LibVLC(this, options)
        val mp = MediaPlayer(lv)
        mp.setEventListener { e -> onVlcEvent(e) }
        libVlc = lv
        player = mp

        startStateLoop()
    }

    private fun releasePlayer() {
        val mp = player
        player = null
        runCatching { mp?.stop() }
        runCatching { mp?.release() }
        val lv = libVlc
        libVlc = null
        runCatching { lv?.release() }
    }

    private fun playCurrent(resetPosition: Boolean) {
        val item = _state.value.current ?: return
        val lv = libVlc ?: return
        val mp = player ?: return

        scope.launch {
            if (ApiController.isP2pMode) {
                runCatching { ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000) }
            }

            val filePath = item.resolvePlayablePath()
            val url = MusicUrl.buildRawFileUrl(filePath, p2pChannel = "video")
            val proxied = P2pLocalHttpProxy.proxyUrlIfNeeded(url)

            mp.stop()
            val media = Media(lv, Uri.parse(proxied))
            media.addOption(":network-caching=800")
            media.addOption(":file-caching=800")
            media.addOption(":http-reconnect")
            media.setHWDecoderEnabled(true, false)
            mp.media = media
            media.release()
            mp.play()
            if (!resetPosition) {
                val pos = _state.value.positionMs
                if (pos > 0) runCatching { mp.time = pos }
            } else {
                _state.update { it.copy(positionMs = 0L, durationMs = 0L) }
            }
            _state.update { it.copy(isPlaying = true) }
            updateNotification()
            updateMediaSession()
        }
    }

    private fun onVlcEvent(e: MediaPlayer.Event) {
        when (e.type) {
            MediaPlayer.Event.Playing -> {
                _state.update { it.copy(isPlaying = true) }
                updateNotification()
                updateMediaSession()
            }
            MediaPlayer.Event.Paused -> {
                _state.update { it.copy(isPlaying = false) }
                updateNotification()
                updateMediaSession()
            }
            MediaPlayer.Event.EndReached -> {
                scope.launch {
                    val s = _state.value
                    when (s.repeatMode) {
                        RepeatMode.One -> {
                            _state.update { it.copy(positionMs = 0L, durationMs = 0L) }
                            playCurrent(resetPosition = true)
                        }
                        RepeatMode.Shuffle -> {
                            playShuffleNext()
                        }
                        RepeatMode.All -> {
                            val next = if (s.index + 1 >= s.playlist.size) 0 else s.index + 1
                            _state.update { it.copy(index = next, positionMs = 0L, durationMs = 0L) }
                            playCurrent(resetPosition = true)
                        }
                        RepeatMode.Off -> {
                            val next = s.index + 1
                            if (next >= s.playlist.size) {
                                pause()
                                seekTo(0L)
                            } else {
                                _state.update { it.copy(index = next, positionMs = 0L, durationMs = 0L) }
                                playCurrent(resetPosition = true)
                            }
                        }
                    }
                }
            }
            MediaPlayer.Event.EncounteredError -> {
                pause()
            }
        }
    }

    private fun startStateLoop() {
        stateJob?.cancel()
        stateJob =
            scope.launch {
                while (true) {
                    delay(500)
                    val mp = player ?: continue
                    val pos = runCatching { mp.time }.getOrNull() ?: 0L
                    val dur = runCatching { mp.length }.getOrNull() ?: 0L
                    _state.update {
                        it.copy(
                            positionMs = pos.coerceAtLeast(0L),
                            durationMs = dur.coerceAtLeast(0L),
                            isPlaying = mp.isPlaying,
                        )
                    }
                    updateMediaSession()
                }
            }
    }

    private fun initMediaSession() {
        if (mediaSession != null) return
        val session = MediaSession(this, "MusicPlayback")
        session.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() = play()
                override fun onPause() = pause()
                override fun onSkipToNext() = next()
                override fun onSkipToPrevious() = prev()
                override fun onSeekTo(pos: Long) = seekTo(pos)
                override fun onStop() = stopAndExit()
            },
        )
        session.isActive = true
        mediaSession = session
        updateMediaSession()
    }

    private fun updateMediaSession() {
        val session = mediaSession ?: return
        val s = _state.value
        val current = s.current
        val title = current?.title?.trim().orEmpty().ifEmpty { current?.filename?.trim().orEmpty() }
        val artist = current?.artist?.trim().orEmpty()

        val meta =
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, s.durationMs.coerceAtLeast(0L))
                .build()
        session.setMetadata(meta)

        val actions =
            PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or
                PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                PlaybackState.ACTION_SEEK_TO or
                PlaybackState.ACTION_STOP

        val st =
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (s.isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    s.positionMs.coerceAtLeast(0L),
                    1.0f,
                ).build()
        session.setPlaybackState(st)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val existing = mgr.getNotificationChannel(NOTIFY_CHANNEL_ID)
        if (existing != null) return
        val ch =
            NotificationChannel(
                NOTIFY_CHANNEL_ID,
                getString(R.string.music_notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.music_notification_channel_desc)
            }
        mgr.createNotificationChannel(ch)
    }

    private fun updateNotification() {
        val current = _state.value.current
        if (current == null) {
            @Suppress("DEPRECATION")
            stopForeground(true)
            return
        }
        ensureNotificationChannel()
        val session = mediaSession
        val title = current.title.trim().ifEmpty { current.filename.trim() }.ifEmpty { getString(R.string.home_music_tracks) }
        val artist = current.artist.trim()

        val openIntent =
            PendingIntent.getActivity(
                this,
                0,
                MusicNowPlayingActivity.newIntent(this).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                pendingIntentFlags(),
            )

        val playPause =
            PendingIntent.getService(
                this,
                1,
                Intent(this, MusicPlaybackService::class.java).setAction(ACTION_TOGGLE),
                pendingIntentFlags(),
            )
        val next =
            PendingIntent.getService(
                this,
                2,
                Intent(this, MusicPlaybackService::class.java).setAction(ACTION_NEXT),
                pendingIntentFlags(),
            )
        val prev =
            PendingIntent.getService(
                this,
                3,
                Intent(this, MusicPlaybackService::class.java).setAction(ACTION_PREV),
                pendingIntentFlags(),
            )
        val stop =
            PendingIntent.getService(
                this,
                4,
                Intent(this, MusicPlaybackService::class.java).setAction(ACTION_STOP),
                pendingIntentFlags(),
            )

        val builder =
            if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, NOTIFY_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
                .setSmallIcon(R.drawable.ic_music_note)
                .setContentTitle(title)
                .setContentText(artist)
                .setContentIntent(openIntent)
                .setOngoing(_state.value.isPlaying)
                .setShowWhen(false)
                .addAction(Notification.Action.Builder(0, getString(R.string.music_action_prev), prev).build())
                .addAction(
                    Notification.Action.Builder(
                        0,
                        if (_state.value.isPlaying) getString(R.string.music_action_pause) else getString(R.string.music_action_play),
                        playPause,
                    ).build(),
                )
                .addAction(Notification.Action.Builder(0, getString(R.string.music_action_next), next).build())
                .addAction(Notification.Action.Builder(0, getString(R.string.music_action_stop), stop).build())

        if (session != null) {
            val style =
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            builder.setStyle(style)
        }

        val n = builder.build()
        startForeground(NOTIFY_ID, n)
    }

    private fun pendingIntentFlags(): Int {
        val base = PendingIntent.FLAG_UPDATE_CURRENT
        return if (Build.VERSION.SDK_INT >= 23) base or PendingIntent.FLAG_IMMUTABLE else base
    }

    private fun stopAndExit() {
        pause()
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    companion object {
        private const val NOTIFY_CHANNEL_ID = "music_playback"
        private const val NOTIFY_ID = 3001

        private const val ACTION_START_PLAYLIST = "com.nascabos.tv.action.MUSIC_START_PLAYLIST"
        private const val ACTION_TOGGLE = "com.nascabos.tv.action.MUSIC_TOGGLE"
        private const val ACTION_NEXT = "com.nascabos.tv.action.MUSIC_NEXT"
        private const val ACTION_PREV = "com.nascabos.tv.action.MUSIC_PREV"
        private const val ACTION_STOP = "com.nascabos.tv.action.MUSIC_STOP"
        private const val ACTION_PAUSE = "com.nascabos.tv.action.MUSIC_PAUSE"
        private const val ACTION_PLAY = "com.nascabos.tv.action.MUSIC_PLAY"

        private const val EXTRA_PLAYLIST_JSON = "extra_playlist_json"
        private const val EXTRA_START_INDEX = "extra_start_index"

        fun startPlaylist(
            context: Context,
            playlist: List<MusicListItem>,
            startIndex: Int,
        ) {
            val safe = playlist.filter { it.resolvePlayablePath().trim().isNotEmpty() }
            if (safe.isEmpty()) return
            val json = Gson().toJson(safe)
            val intent =
                Intent(context, MusicPlaybackService::class.java).apply {
                    action = ACTION_START_PLAYLIST
                    putExtra(EXTRA_PLAYLIST_JSON, json)
                    putExtra(EXTRA_START_INDEX, startIndex.coerceAtLeast(0))
                }
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun sendToggle(context: Context) {
            context.startService(Intent(context, MusicPlaybackService::class.java).setAction(ACTION_TOGGLE))
        }

        fun sendNext(context: Context) {
            context.startService(Intent(context, MusicPlaybackService::class.java).setAction(ACTION_NEXT))
        }

        fun sendPrev(context: Context) {
            context.startService(Intent(context, MusicPlaybackService::class.java).setAction(ACTION_PREV))
        }

        fun sendStop(context: Context) {
            context.startService(Intent(context, MusicPlaybackService::class.java).setAction(ACTION_STOP))
        }
    }
}
