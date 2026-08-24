package com.nascabos.tv.modules.music.player

import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.graphics.BitmapFactory
import android.graphics.Outline
import android.graphics.Typeface
import android.os.Bundle
import android.os.IBinder
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.ArrayAdapter
import android.widget.CheckedTextView
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.graphics.drawable.DrawableCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.DividerItemDecoration
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.nascabos.tv.R
import com.nascabos.tv.modules.music.MusicFallbackCover
import com.nascabos.tv.modules.music.MusicListApiService
import com.nascabos.tv.modules.music.MusicFavoriteApiService
import com.nascabos.tv.modules.music.MusicLyricApiService
import com.nascabos.tv.modules.music.MusicListItem
import com.nascabos.tv.modules.music.MusicUrl
import com.nascabos.tv.core.i18n.LocaleManager
import com.nascabos.tv.core.ui.TvImageLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import kotlin.math.abs

class MusicNowPlayingActivity : AppCompatActivity() {
    private var service: MusicPlaybackService? = null
    private var bound = false

    private lateinit var discImage: ImageView
    private lateinit var coverImage: ImageView
    private lateinit var titleView: TextView
    private lateinit var subtitleView: TextView
    private lateinit var timeView: TextView
    private lateinit var btnFavorite: ImageButton
    private lateinit var btnRepeat: ImageButton
    private lateinit var btnPrev: ImageButton
    private lateinit var btnPlay: ImageButton
    private lateinit var btnNext: ImageButton
    private lateinit var btnPlaylist: ImageButton
    private lateinit var btnLyricSearch: ImageButton
    private lateinit var lyricsList: RecyclerView
    private lateinit var lyricsEmptyPlaceholder: TextView

    private val lyricsAdapter = LyricsAdapter()
    private var lyricsJob: Job? = null
    private var lastLyricsKey: String = ""
    private var discAnimator: ObjectAnimator? = null
    private var lastCenteredLyricIndex: Int = -1

    private val connection =
        object : ServiceConnection {
            override fun onServiceConnected(name: android.content.ComponentName?, binder: IBinder?) {
                val b = binder as? MusicPlaybackService.LocalBinder ?: return
                service = b.service()
                bound = true
                startCollecting()
            }

            override fun onServiceDisconnected(name: android.content.ComponentName?) {
                bound = false
                service = null
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocaleManager.init(applicationContext)
        LocaleManager.restoreSavedLanguage()
        setContentView(R.layout.activity_music_now_playing)

        discImage = findViewById(R.id.disc_image)
        coverImage = findViewById(R.id.cover_image)
        titleView = findViewById(R.id.title)
        subtitleView = findViewById(R.id.subtitle)
        timeView = findViewById(R.id.time)
        btnFavorite = findViewById(R.id.btn_favorite)
        btnRepeat = findViewById(R.id.btn_repeat)
        btnPrev = findViewById(R.id.btn_prev)
        btnPlay = findViewById(R.id.btn_play)
        btnNext = findViewById(R.id.btn_next)
        btnPlaylist = findViewById(R.id.btn_playlist)
        btnLyricSearch = findViewById(R.id.btn_lyric_search)
        lyricsList = findViewById(R.id.lyrics_list)
        lyricsEmptyPlaceholder = findViewById(R.id.lyrics_empty_placeholder)

        lyricsList.layoutManager = LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        lyricsList.adapter = lyricsAdapter

        loadDiscAsset()
        setupCoverCircleClip()
        setupControls()
    }

    override fun onStart() {
        super.onStart()
        bindToService()
    }

    override fun onStop() {
        super.onStop()
        if (bound) {
            unbindService(connection)
            bound = false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        discAnimator?.cancel()
        discAnimator = null
        lyricsJob?.cancel()
        lyricsJob = null
    }

    private fun bindToService() {
        val intent = Intent(this, MusicPlaybackService::class.java)
        bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    private fun startCollecting() {
        val s = service ?: return
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                s.state.collectLatest { st ->
                    renderState(st)
                }
            }
        }
    }

    private fun renderState(st: MusicPlaybackState) {
        val current = st.current
        val title = current?.filename?.trim().orEmpty().ifEmpty { current?.title?.trim().orEmpty() }
        val artist = current?.artist?.trim().orEmpty()
        val album = current?.album?.trim().orEmpty()

        titleView.text = title.ifEmpty { getString(R.string.music_now_playing_empty) }
        subtitleView.text =
            listOf(artist, album).filter { it.isNotBlank() }.joinToString(" · ")

        val pos = st.positionMs.coerceAtLeast(0L)
        val dur = st.durationMs.coerceAtLeast(0L)
        timeView.text = "${formatTime(pos)} / ${formatTime(dur)}"

        btnPlay.setImageResource(if (st.isPlaying) R.drawable.ic_pause else R.drawable.ic_play)
        btnRepeat.setImageResource(
            when (st.repeatMode) {
                RepeatMode.Off -> R.drawable.ic_repeat_off
                RepeatMode.All -> R.drawable.ic_repeat_all
                RepeatMode.One -> R.drawable.ic_repeat_one
                RepeatMode.Shuffle -> R.drawable.ic_shuffle
            },
        )
        val fav = current?.isFavorite == true
        btnFavorite.setImageResource(if (fav) R.drawable.ic_favorite else R.drawable.ic_favorite_border)
        btnFavorite.contentDescription = getString(if (fav) R.string.music_unfavorite else R.string.music_favorite)
        updateDiscAnimation(st.isPlaying)

        val coverTarget = current?.resolvePlayablePath()?.trim().orEmpty()
        val coverKey = coverTarget
        val seed = current?.id ?: 0
        val fallbackAsset =
            if (current != null) {
                MusicFallbackCover.pickAssetPathForTrack(current.genre, seed)
            } else {
                "musicCover/default.jpg"
            }
        MusicFallbackCover.loadInto(coverImage, fallbackAsset, reqSize = 500)
        val canUseApiCover = current != null && current.hasInnerCover > 0 && coverKey.isNotEmpty()
        if (canUseApiCover) {
            val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 500)
            TvImageLoader.loadApiPathInto(
                imageView = coverImage,
                apiPath = apiPath,
                cacheKeyPrefix = "music_cover_500",
                placeholderResId = 0,
                reqSize = 500,
                showPlaceholderWhileLoading = false,
            )
        }

        if (coverKey.isNotEmpty() && lastLyricsKey != coverKey) {
            lastLyricsKey = coverKey
            fetchLyricsFor(coverKey, current, dur)
        }

        lyricsAdapter.setPlaybackPosition(pos)
        val curIdx = lyricsAdapter.currentIndex()
        if (curIdx >= 0) {
            val lm = lyricsList.layoutManager as? LinearLayoutManager
            if (lm != null) {
                centerLyricIfNeeded(lm, curIdx)
            }
        }
    }

    private fun fetchLyricsFor(filePath: String, item: MusicListItem?, durationMs: Long) {
        lyricsJob?.cancel()
        lyricsEmptyPlaceholder.visibility = View.GONE
        lyricsJob =
            lifecycleScope.launch {
                val openedPath = filePath.trim()
                val res =
                    withContext(Dispatchers.IO) {
                        runCatching { MusicListApiService.getDetail(openedPath) }.getOrNull()
                    }
                val lyricText = res?.lyrics.orEmpty()
                val lyricGetState = res?.lyricsGetState ?: 0
                val lines = LrcParser.parse(lyricText)
                lyricsAdapter.setLines(lines)
                lyricsEmptyPlaceholder.visibility = if (lines.isEmpty()) View.VISIBLE else View.GONE
                if (lines.isEmpty()) {
                    if (lyricGetState == 2) return@launch
                    maybeAutoSetLyricIfNoLyric(
                        filePath = openedPath,
                        item = item,
                        durationMsFromPlayer = durationMs,
                    )
                }
            }
    }

    private fun maybeAutoSetLyricIfNoLyric(
        filePath: String,
        item: MusicListItem?,
        durationMsFromPlayer: Long,
    ) {
        val p = filePath.trim()
        if (p.isEmpty()) return
        val it = item ?: return
        val expectedMs =
            durationMsFromPlayer
                .coerceAtLeast(0L)
                .takeIf { value -> value > 0L }
                ?.toInt()
                ?: coerceDurationMs(it.duration)
        if (expectedMs <= 0) return

        val keyword = buildLyricSearchKeyword(it, filePath = p)
        if (keyword.isEmpty()) return

        lifecycleScope.launch {
            val results =
                withContext(Dispatchers.IO) {
                    runCatching { MusicLyricApiService.search(keyword) }.getOrNull().orEmpty()
                }
            if (results.isEmpty()) {
                withContext(Dispatchers.IO) {
                    runCatching { MusicLyricApiService.setLyric(musicPath = p, lrc = "") }.getOrNull()
                }
                return@launch
            }

            val stemNorm = normalizeForContains(fileStem(p))
            val chosen =
                results.firstOrNull { candidate ->
                    isHighMatch(
                        candidate = candidate,
                        fileStemNormalized = stemNorm,
                        expectedDurationMs = expectedMs,
                    )
                }
            if (chosen == null) {
                withContext(Dispatchers.IO) {
                    runCatching { MusicLyricApiService.setLyric(musicPath = p, lrc = "") }.getOrNull()
                }
                return@launch
            }

            val lrc = chosen.lrc.trim()
            if (lrc.isEmpty()) {
                withContext(Dispatchers.IO) {
                    runCatching { MusicLyricApiService.setLyric(musicPath = p, lrc = "") }.getOrNull()
                }
                return@launch
            }

            val ok =
                withContext(Dispatchers.IO) {
                    runCatching { MusicLyricApiService.setLyric(musicPath = p, lrc = lrc) }.getOrNull() == true
                }
            if (!ok) return@launch

            val currentPath = service?.state?.value?.current?.resolvePlayablePath()?.trim().orEmpty()
            if (currentPath != p) return@launch

            applyLyricToUi(lrc)
        }
    }

    private fun setupControls() {
        btnFavorite.setOnClickListener { toggleFavorite() }
        btnRepeat.setOnClickListener { service?.cycleRepeatMode() }
        btnPrev.setOnClickListener { service?.prev() }
        btnPlay.setOnClickListener { service?.toggle() }
        btnNext.setOnClickListener { service?.next() }
        btnPlaylist.setOnClickListener { openPlaylistDialog() }
        btnLyricSearch.setOnClickListener { openLyricSearchForCurrent() }
    }

    private fun toggleFavorite() {
        val s = service ?: return
        val current = s.state.value.current ?: return
        val id = current.id
        if (id <= 0) return
        val next = !current.isFavorite
        lifecycleScope.launch {
            val ok =
                withContext(Dispatchers.IO) {
                    runCatching { MusicFavoriteApiService.setFavorite(indexId = id, favorite = next) }.getOrNull() == true
                }
            if (!ok) {
                Toast.makeText(this@MusicNowPlayingActivity, R.string.operation_failed, Toast.LENGTH_SHORT).show()
                return@launch
            }
            s.setFavorite(id, next)
            Toast.makeText(this@MusicNowPlayingActivity, R.string.operation_success, Toast.LENGTH_SHORT).show()
        }
    }

    private fun openPlaylistDialog() {
        val s = service ?: return
        val st = s.state.value
        val list = st.playlist
        if (list.isEmpty()) return

        val items =
            list.map { it.displayTitle.ifEmpty { it.title.trim() }.ifEmpty { it.filename.trim() } }
                .mapIndexed { i, t ->
                    val artist = list[i].artist.trim()
                    if (artist.isNotEmpty()) "$t · $artist" else t
                }
                .toTypedArray()

        val currentIndex = st.index.coerceIn(0, list.size - 1)
        val adapter =
            object : ArrayAdapter<String>(this, android.R.layout.simple_list_item_single_choice, android.R.id.text1, items) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val tv = v.findViewById<TextView>(android.R.id.text1)
                    tv.setTextColor(0xFFFFFFFF.toInt())
                    if (tv is CheckedTextView) {
                        val d = tv.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            tv.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }

        AlertDialog.Builder(this, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.home_music_now_playing))
            .setSingleChoiceItems(adapter, currentIndex) { dialog, which ->
                s.playAt(which)
                dialog.dismiss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun openLyricSearchForCurrent() {
        val current = service?.state?.value?.current ?: return
        val p = current.resolvePlayablePath().trim()
        if (p.isEmpty()) return
        val expected = service?.state?.value?.durationMs ?: 0L
        showLyricSearchDialog(filePath = p, item = current, expectedDurationMs = expected.coerceAtLeast(0L).toInt())
    }

    private fun showLyricSearchDialog(
        filePath: String,
        item: MusicListItem,
        expectedDurationMs: Int,
    ) {
        val p = filePath.trim()
        if (p.isEmpty()) return

        val input =
            EditText(this).apply {
                setText(buildLyricSearchKeyword(item, filePath = p))
                setSingleLine(true)
                setSelectAllOnFocus(true)
                setTextColor(0xFFFFFFFF.toInt())
                setHintTextColor(0x99FFFFFF.toInt())
                setBackgroundResource(R.drawable.bg_music_search_input)
                setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
            }

        val searchBtn =
            ImageButton(this).apply {
                setImageResource(R.drawable.ic_search)
                contentDescription = getString(R.string.action_search)
                setBackgroundResource(R.drawable.video_dialog_selector)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setPadding(dp(10f), dp(10f), dp(10f), dp(10f))
            }

        val loading =
            ProgressBar(this).apply {
                visibility = View.GONE
            }

        val headerRow =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(
                    input,
                    LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { rightMargin = dp(10f) },
                )
                addView(
                    searchBtn,
                    LinearLayout.LayoutParams(dp(48f), dp(48f)).apply { rightMargin = dp(10f) },
                )
                addView(
                    loading,
                    LinearLayout.LayoutParams(dp(20f), dp(20f)),
                )
            }

        val rv =
            RecyclerView(this).apply {
                layoutManager = LinearLayoutManager(this@MusicNowPlayingActivity, LinearLayoutManager.VERTICAL, false)
                addItemDecoration(DividerItemDecoration(context, DividerItemDecoration.VERTICAL))
            }

        var dialog: AlertDialog? = null
        val adapter =
            LyricSearchAdapter(
                ctx = this,
                filePath = p,
                expectedDurationMs = expectedDurationMs,
                onSelect = { chosen ->
                    val openedPath = p
                    lifecycleScope.launch {
                        val ok =
                            withContext(Dispatchers.IO) {
                                runCatching { MusicLyricApiService.setLyric(musicPath = openedPath, lrc = chosen.lrc) }.getOrNull() == true
                            }
                        if (!ok) {
                            Toast.makeText(this@MusicNowPlayingActivity, R.string.operation_failed, Toast.LENGTH_SHORT).show()
                            return@launch
                        }

                        val curPath = service?.state?.value?.current?.resolvePlayablePath()?.trim().orEmpty()
                        if (curPath == openedPath) {
                            applyLyricToUi(chosen.lrc)
                        }
                        Toast.makeText(this@MusicNowPlayingActivity, R.string.operation_success, Toast.LENGTH_SHORT).show()
                        dialog?.dismiss()
                    }
                },
            )
        rv.adapter = adapter

        val content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18f), dp(12f), dp(18f), dp(12f))
                addView(headerRow)
                addView(
                    rv,
                    LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(320f)).apply { topMargin = dp(10f) },
                )
            }

        dialog =
            AlertDialog.Builder(this, R.style.Theme_NasCabTv_AlertDialog)
                .setTitle(getString(R.string.music_search_lyric))
                .setView(content)
                .setNegativeButton(getString(R.string.action_cancel), null)
                .create()

        fun doSearch() {
            val q = input.text?.toString()?.trim().orEmpty()
            if (q.isEmpty()) return
            loading.visibility = View.VISIBLE
            searchBtn.isEnabled = false
            searchBtn.alpha = 0.6f
            lifecycleScope.launch {
                val list =
                    withContext(Dispatchers.IO) {
                        runCatching { MusicLyricApiService.search(q) }.getOrNull().orEmpty()
                    }
                adapter.submit(list)
                loading.visibility = View.GONE
                searchBtn.isEnabled = true
                searchBtn.alpha = 1f
                if (list.isEmpty()) Toast.makeText(this@MusicNowPlayingActivity, R.string.no_data, Toast.LENGTH_SHORT).show()
            }
        }

        searchBtn.setOnClickListener { doSearch() }
        dialog?.show()
        dialog?.window?.setLayout(dp(980f), ViewGroup.LayoutParams.WRAP_CONTENT)
        input.post { input.requestFocus() }
        doSearch()
    }

    private fun applyLyricToUi(lrc: String) {
        val lines = LrcParser.parse(lrc)
        lyricsAdapter.setLines(lines)
        lyricsEmptyPlaceholder.visibility = if (lines.isEmpty()) View.VISIBLE else View.GONE
    }

    private fun buildLyricSearchKeyword(item: MusicListItem, filePath: String): String {
        val rawTitle = item.title.trim()
        val rawArtist = item.artist.trim()
        val fallbackTitle = fileStem(item.filename.trim().ifEmpty { filePath })
        val title = (if (rawTitle.isNotEmpty()) rawTitle else fallbackTitle).trim()
        if (title.isEmpty()) return ""
        return if (rawArtist.isNotEmpty()) "$title $rawArtist" else title
    }

    private fun coerceDurationMs(value: Int): Int {
        val v = value.coerceAtLeast(0)
        if (v <= 0) return 0
        if (v < 24 * 60 * 60) return v * 1000
        return v
    }

    private fun fileStem(pathOrFile: String): String {
        val input = pathOrFile.trim()
        if (input.isEmpty()) return ""
        val slash = input.lastIndexOf('/')
        val backSlash = input.lastIndexOf('\\')
        val sep = if (slash > backSlash) slash else backSlash
        val name = if (sep >= 0) input.substring(sep + 1) else input
        val dot = name.lastIndexOf('.')
        if (dot <= 0) return name
        return name.substring(0, dot)
    }

    private fun normalizeForContains(input: String): String {
        val s = input.trim().lowercase()
        if (s.isEmpty()) return ""
        return s.replace(Regex("[^a-z0-9\\u4e00-\\u9fff]+"), "")
    }

    private fun isHighMatch(
        candidate: MusicLyricApiService.LyricSearchItem,
        fileStemNormalized: String,
        expectedDurationMs: Int,
    ): Boolean {
        val titleNorm = normalizeForContains(candidate.title)
        if (titleNorm.isEmpty()) return false
        val durationMatch = candidate.durationMs > 0 && abs(candidate.durationMs - expectedDurationMs) <= 5000
        val nameMatch = fileStemNormalized.isNotEmpty() && fileStemNormalized.contains(titleNorm)
        return durationMatch && nameMatch
    }

    private fun dp(dp: Float): Int = (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)

    private fun centerLyricIfNeeded(lm: LinearLayoutManager, index: Int) {
        if (index == lastCenteredLyricIndex) return
        lastCenteredLyricIndex = index

        lyricsList.post {
            if (lyricsList.height <= 0) {
                lm.scrollToPositionWithOffset(index, 0)
                return@post
            }
            val v = lm.findViewByPosition(index)
            if (v != null) {
                val targetTop = (lyricsList.height / 2) - (v.height / 2)
                val dy = v.top - targetTop
                if (kotlin.math.abs(dy) > 4) lyricsList.smoothScrollBy(0, dy)
            } else {
                lm.scrollToPositionWithOffset(index, lyricsList.height / 2)
            }
        }
    }

    private fun loadDiscAsset() {
        val bmp =
            runCatching {
                assets.open("icons/player_disc.png").use { BitmapFactory.decodeStream(it) }
            }.getOrNull()
        if (bmp != null) {
            discImage.setImageBitmap(bmp)
            return
        }
        val fallback =
            runCatching {
                assets.open("icons/player_disc.png").use { BitmapFactory.decodeStream(it) }
            }.getOrNull()
        if (fallback != null) discImage.setImageBitmap(fallback)
    }

    private fun setupCoverCircleClip() {
        coverImage.outlineProvider =
            object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    val w = view.width
                    val h = view.height
                    val d = minOf(w, h)
                    val left = (w - d) / 2
                    val top = (h - d) / 2
                    outline.setOval(left, top, left + d, top + d)
                }
            }
        coverImage.clipToOutline = true
    }

    private fun updateDiscAnimation(isPlaying: Boolean) {
        if (discAnimator == null) {
            discAnimator =
                ObjectAnimator.ofFloat(discImage, View.ROTATION, 0f, 360f).apply {
                    duration = 12_000
                    repeatCount = ValueAnimator.INFINITE
                    repeatMode = ValueAnimator.RESTART
                }
        }
        val anim = discAnimator ?: return
        if (isPlaying) {
            if (!anim.isStarted) anim.start() else anim.resume()
        } else {
            if (anim.isStarted) anim.pause()
        }
    }

    private fun formatTime(ms: Long): String {
        val total = (ms.coerceAtLeast(0L) / 1000L).toInt()
        val h = total / 3600
        val m = (total % 3600) / 60
        val s = total % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, s) else String.format("%d:%02d", m, s)
    }

    companion object {
        fun newIntent(context: Context): Intent {
            return Intent(context, MusicNowPlayingActivity::class.java)
        }
    }
}

private data class LyricSearchUiItem(
    val raw: MusicLyricApiService.LyricSearchItem,
    val highMatch: Boolean,
    val matchScore: Int,
    val meta: String,
    val previewLine: String,
)

private class LyricSearchAdapter(
    private val ctx: Context,
    private val filePath: String,
    private val expectedDurationMs: Int,
    private val onSelect: (MusicLyricApiService.LyricSearchItem) -> Unit,
) : RecyclerView.Adapter<LyricSearchAdapter.VH>() {
    private var items: List<LyricSearchUiItem> = emptyList()
    private var selectingId: String = ""

    fun submit(list: List<MusicLyricApiService.LyricSearchItem>) {
        val stemNorm = normalizeForContains(fileStem(filePath))
        items =
            list.map { it ->
                val durationMatch = it.durationMs > 0 && abs(it.durationMs - expectedDurationMs) <= 5000
                val titleNorm = normalizeForContains(it.title)
                val nameMatch = titleNorm.isNotEmpty() && stemNorm.isNotEmpty() && stemNorm.contains(titleNorm)
                val highMatch = durationMatch && nameMatch
                val score =
                    when {
                        highMatch -> 100
                        durationMatch && nameMatch -> 100
                        durationMatch || nameMatch -> 50
                        else -> 0
                    }
                val metaParts = ArrayList<String>(4)
                if (it.artist.isNotEmpty()) metaParts += it.artist
                if (it.album.isNotEmpty()) metaParts += it.album
                if (it.durationMs > 0) metaParts += formatTime(it.durationMs.toLong())
                metaParts += ctx.getString(R.string.music_match_score, score)
                LyricSearchUiItem(
                    raw = it,
                    highMatch = highMatch,
                    matchScore = score,
                    meta = metaParts.joinToString(" · "),
                    previewLine = firstLyricLineFromLrc(it.lrc),
                )
            }
        selectingId = ""
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val c = parent.context
        val root =
            LinearLayout(c).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(c, 10f), dp(c, 10f), dp(c, 10f), dp(c, 10f))
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            }

        val left =
            LinearLayout(c).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }

        val titleRow =
            LinearLayout(c).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            }

        val tagView =
            TextView(c).apply {
                text = c.getString(R.string.music_match_high)
                setTextColor(0xCCFFFFFF.toInt())
                textSize = 12f
                setPadding(dp(c, 6f), dp(c, 2f), dp(c, 6f), dp(c, 2f))
                visibility = View.GONE
            }

        val titleView =
            TextView(c).apply {
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 16f
                maxLines = 1
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { leftMargin = dp(c, 8f) }
            }

        titleRow.addView(tagView)
        titleRow.addView(titleView)

        val metaView =
            TextView(c).apply {
                setTextColor(0x99FFFFFF.toInt())
                textSize = 13f
                maxLines = 1
            }

        val previewView =
            TextView(c).apply {
                setTextColor(0x99FFFFFF.toInt())
                textSize = 13f
                maxLines = 1
            }

        left.addView(titleRow)
        left.addView(metaView)
        left.addView(previewView)

        val selectBtn =
            ImageButton(c).apply {
                setImageResource(R.drawable.ic_add)
                contentDescription = c.getString(R.string.action_select)
                setBackgroundResource(R.drawable.video_dialog_selector)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
                setPadding(dp(c, 10f), dp(c, 10f), dp(c, 10f), dp(c, 10f))
                layoutParams = LinearLayout.LayoutParams(dp(c, 48f), dp(c, 48f)).apply { leftMargin = dp(c, 10f) }
            }

        root.addView(left)
        root.addView(selectBtn)

        return VH(root, tagView, titleView, metaView, previewView, selectBtn)
    }

    override fun getItemCount(): Int = items.size

    override fun onBindViewHolder(holder: VH, position: Int) {
        val ui = items.getOrNull(position) ?: return
        holder.tagView.visibility = if (ui.highMatch) View.VISIBLE else View.GONE
        holder.titleView.text = ui.raw.title.ifEmpty { ui.raw.id }
        holder.metaView.text = ui.meta
        holder.previewView.text = ui.previewLine.ifEmpty { "\u00A0" }

        val selecting = selectingId == ui.raw.id
        holder.selectBtn.isEnabled = !selecting && ui.raw.lrc.isNotEmpty()
        holder.selectBtn.alpha = if (holder.selectBtn.isEnabled) 1f else 0.6f
        holder.selectBtn.setOnClickListener {
            if (selectingId.isNotEmpty()) return@setOnClickListener
            selectingId = ui.raw.id
            notifyDataSetChanged()
            onSelect(ui.raw)
        }
    }

    class VH(
        view: View,
        val tagView: TextView,
        val titleView: TextView,
        val metaView: TextView,
        val previewView: TextView,
        val selectBtn: ImageButton,
    ) : RecyclerView.ViewHolder(view)
}

private fun firstLyricLineFromLrc(lrc: String): String {
    val text = lrc.trim()
    if (text.isEmpty()) return ""
    val lines = text.split(Regex("\\r?\\n"))
    for (raw in lines) {
        val line = raw.trim()
        if (line.isEmpty()) continue
        if (line.startsWith('[') && line.contains(']')) {
            val idx = line.lastIndexOf(']')
            val after = if (idx >= 0) line.substring(idx + 1).trim() else ""
            if (after.isNotEmpty()) return after
            continue
        }
        return line
    }
    return ""
}

private fun fileStem(pathOrFile: String): String {
    val input = pathOrFile.trim()
    if (input.isEmpty()) return ""
    val slash = input.lastIndexOf('/')
    val backSlash = input.lastIndexOf('\\')
    val sep = if (slash > backSlash) slash else backSlash
    val name = if (sep >= 0) input.substring(sep + 1) else input
    val dot = name.lastIndexOf('.')
    if (dot <= 0) return name
    return name.substring(0, dot)
}

private fun normalizeForContains(input: String): String {
    val s = input.trim().lowercase()
    if (s.isEmpty()) return ""
    return s.replace(Regex("[^a-z0-9\\u4e00-\\u9fff]+"), "")
}

private fun formatTime(ms: Long): String {
    val total = (ms.coerceAtLeast(0L) / 1000L).toInt()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, s) else String.format("%d:%02d", m, s)
}

private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)

data class LyricLine(
    val timeMs: Long,
    val text: String,
)

object LrcParser {
    private val timeRegex = Regex("\\[(\\d{1,2}):(\\d{1,2})(?:\\.(\\d{1,3}))?\\]")

    fun parse(lrc: String): List<LyricLine> {
        val text = lrc.trim()
        if (text.isEmpty()) return emptyList()
        val out = ArrayList<LyricLine>()
        val lines = text.split(Regex("\\r?\\n"))
        for (raw in lines) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val matches = timeRegex.findAll(line).toList()
            if (matches.isEmpty()) continue
            val last = matches.last()
            val content = line.substring(last.range.last + 1).trim()
            for (m in matches) {
                val min = m.groupValues.getOrNull(1)?.toIntOrNull() ?: 0
                val sec = m.groupValues.getOrNull(2)?.toIntOrNull() ?: 0
                val msPart = m.groupValues.getOrNull(3).orEmpty()
                val ms = when (msPart.length) {
                    0 -> 0
                    1 -> msPart.toIntOrNull()?.times(100) ?: 0
                    2 -> msPart.toIntOrNull()?.times(10) ?: 0
                    else -> msPart.take(3).toIntOrNull() ?: 0
                }
                val t = (min * 60_000L) + (sec * 1000L) + ms
                out.add(LyricLine(timeMs = t.coerceAtLeast(0L), text = content))
            }
        }
        out.sortWith(compareBy({ it.timeMs }, { it.text }))
        return out
    }
}

private class LyricsAdapter : RecyclerView.Adapter<LyricsAdapter.VH>() {
    private var lines: List<LyricLine> = emptyList()
    private var playbackMs: Long = 0L
    private var curIndex: Int = -1

    fun setLines(next: List<LyricLine>) {
        lines = next
        curIndex = -1
        notifyDataSetChanged()
    }

    fun setPlaybackPosition(ms: Long) {
        playbackMs = ms.coerceAtLeast(0L)
        val next = findCurrentIndex()
        if (next != curIndex) {
            val prev = curIndex
            curIndex = next
            if (prev >= 0) notifyItemChanged(prev)
            if (curIndex >= 0) notifyItemChanged(curIndex)
        }
    }

    fun currentIndex(): Int = curIndex

    private fun findCurrentIndex(): Int {
        if (lines.isEmpty()) return -1
        var lo = 0
        var hi = lines.size - 1
        var ans = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val t = lines[mid].timeMs
            if (t <= playbackMs) {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val tv =
            TextView(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                setPadding(dp(parent.context, 10f), dp(parent.context, 10f), dp(parent.context, 10f), dp(parent.context, 10f))
                setTextColor(0xB3FFFFFF.toInt())
                textSize = 16f
                isFocusable = false
                isFocusableInTouchMode = false
            }
        return VH(tv)
    }

    override fun getItemCount(): Int = lines.size.coerceAtLeast(0)

    override fun onBindViewHolder(holder: VH, position: Int) {
        val line = lines.getOrNull(position)
        val tv = holder.itemView as TextView
        tv.text = line?.text.orEmpty()
        if (position == curIndex) {
            tv.setTextColor(0xFFFFFFFF.toInt())
            tv.setTypeface(null, Typeface.BOLD)
            tv.textSize = 22f
        } else {
            tv.setTextColor(0x99FFFFFF.toInt())
            tv.setTypeface(null, Typeface.NORMAL)
            tv.textSize = 16f
        }
    }

    class VH(view: View) : RecyclerView.ViewHolder(view)

    private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)
}
