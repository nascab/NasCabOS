package com.nascabos.tv.modules.photo.timeline

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.i18n.LocaleManager
import com.nascabos.tv.core.ui.JwtSessionExpiredUi
import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.video_player.TvPlaylistItem
import com.nascabos.tv.modules.video_player.TvVideoPlayerActivity
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

class PhotoPreviewActivity : AppCompatActivity() {
    private val gson = Gson()

    private var items: List<PreviewItem> = emptyList()
    private var index: Int = 0

    private lateinit var imageView: ImageView
    private lateinit var playIconView: ImageView
    private lateinit var progressView: ProgressBar
    private lateinit var bottomBar: FrameLayout
    private lateinit var filenameView: TextView

    private val prefs by lazy { PhotoPreviewPrefsStore(applicationContext) }
    private var autoPlayEnabled: Boolean = false
    private var autoPlayIntervalSeconds: Int = 5
    private var autoPlayJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocaleManager.init(applicationContext)
        LocaleManager.restoreSavedLanguage()

        items = parseItems(intent)
        index = intent.getIntExtra(EXTRA_INDEX, 0).coerceIn(0, (items.size - 1).coerceAtLeast(0))

        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        setContentView(root)

        imageView =
            ImageView(this).apply {
                setBackgroundColor(Color.BLACK)
                scaleType = ImageView.ScaleType.FIT_CENTER
                isFocusable = true
                isFocusableInTouchMode = true
            }
        root.addView(
            imageView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )

        playIconView =
            ImageView(this).apply {
                setImageResource(android.R.drawable.ic_media_play)
                setColorFilter(Color.argb(180, 255, 255, 255)) // 半透明白色
                visibility = View.GONE
                isFocusable = false
            }
        root.addView(
            playIconView,
            FrameLayout.LayoutParams(dpToPx(96f), dpToPx(96f)).apply {
                gravity = Gravity.CENTER
            },
        )

        progressView =
            ProgressBar(this).apply {
                isIndeterminate = true
                visibility = View.GONE
            }
        root.addView(
            progressView,
            FrameLayout.LayoutParams(dpToPx(56f), dpToPx(56f)).apply {
                gravity = Gravity.CENTER
            },
        )

        bottomBar =
            FrameLayout(this).apply {
                setBackgroundColor(0x66000000)
                isFocusable = false
            }
        root.addView(
            bottomBar,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
            },
        )

        filenameView =
            TextView(this).apply {
                setTextColor(Color.WHITE)
                // 字体稍微缩小一点
                textSize = 14f
                // 文字上下各留约 15 像素，左右保持 20 像素
                setPadding(dpToPx(20f), dpToPx(6f), dpToPx(20f), dpToPx(6f))
                gravity = Gravity.CENTER
                isSingleLine = true
                ellipsize = android.text.TextUtils.TruncateAt.MARQUEE
                marqueeRepeatLimit = -1
                isSelected = true
            }
        bottomBar.addView(
            filenameView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.CENTER
            },
        )

        supportFragmentManager.setFragmentResultListener(PhotoPreviewOptionsDialogFragment.RESULT_KEY_AUTO_PLAY, this) { _, bundle ->
            autoPlayEnabled =
                bundle.getBoolean(
                    PhotoPreviewOptionsDialogFragment.RESULT_FIELD_AUTO_PLAY_ENABLED,
                    false,
                )
            restartAutoPlay()
        }
        supportFragmentManager.setFragmentResultListener(PhotoPreviewOptionsDialogFragment.RESULT_KEY_FAVORITE_TOGGLE, this) { _, _ ->
            onFavoriteToggleRequested()
        }
        supportFragmentManager.setFragmentResultListener(PhotoPreviewOptionsDialogFragment.RESULT_KEY_TRASH, this) { _, _ ->
            onTrashRequested()
        }

        lifecycleScope.launch {
            prefs.stateFlow.collectLatest { s ->
                autoPlayIntervalSeconds = s.autoPlayIntervalSeconds
                restartAutoPlay()
            }
        }

        showCurrent()
        imageView.requestFocus()
    }

    override fun onStop() {
        super.onStop()
        autoPlayJob?.cancel()
        autoPlayJob = null
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_UP) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    finish()
                    return true
                }
                KeyEvent.KEYCODE_MENU -> {
                    openOptions()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_UP,
                -> {
                    prev()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_DOWN,
                -> {
                    next()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                -> {
                    onOkPressed()
                    return true
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun prev() {
        if (items.isEmpty()) return
        if (index <= 0) return
        index -= 1
        showCurrent()
        restartAutoPlay()
    }

    private fun next() {
        if (items.isEmpty()) return
        if (index >= items.size - 1) return
        index += 1
        showCurrent()
        restartAutoPlay()
    }

    private fun nextWrap() {
        if (items.isEmpty()) return
        index = if (index >= items.size - 1) 0 else index + 1
        showCurrent()
    }

    private fun onOkPressed() {
        val cur = items.getOrNull(index) ?: return
        // 视频类型：确认键直接播放，不切换底部条显隐
        if (cur.isVideo) {
            playCurrentVideo(cur)
            return
        }
        // 图片类型：确认键切换底部条显隐
        if (bottomBar.visibility == View.VISIBLE) {
            bottomBar.visibility = View.GONE
        } else {
            bottomBar.visibility = View.VISIBLE
        }
    }

    private fun openOptions() {
        val cur = items.getOrNull(index)
        PhotoPreviewOptionsDialogFragment
            .newInstance(
                autoPlayEnabled = autoPlayEnabled,
                intervalSeconds = autoPlayIntervalSeconds,
                currentItemIsFavorite = cur?.isFavorite == true,
            )
            .show(supportFragmentManager, "photo_preview_options")
    }

    private fun onFavoriteToggleRequested() {
        val cur = items.getOrNull(index) ?: return
        if (cur.fileHash.isBlank()) return
        lifecycleScope.launch {
            val newFavorite =
                withContext(Dispatchers.IO) {
                    PhotoTimelineApiService.toggleFavorite(cur.fileHash)
                }
            if (newFavorite != null) {
                items =
                    items.mapIndexed { i, it ->
                        if (i == index) it.copy(isFavorite = newFavorite) else it
                    }
                showCurrent()
            }
        }
    }

    private fun onTrashRequested() {
        val cur = items.getOrNull(index) ?: return
        if (cur.id <= 0) return
        lifecycleScope.launch {
            val ok =
                withContext(Dispatchers.IO) {
                    PhotoTimelineApiService.batchTrash(listOf(cur.id))
                }
            if (ok) {
                runOnUiThread {
                    Toast.makeText(this@PhotoPreviewActivity, R.string.photo_preview_toast_moved_to_trash, Toast.LENGTH_SHORT).show()
                    items = items.filterIndexed { i, _ -> i != index }
                    index = index.coerceAtMost((items.size - 1).coerceAtLeast(0))
                    if (items.isEmpty()) {
                        finish()
                        return@runOnUiThread
                    }
                    showCurrent()
                    restartAutoPlay()
                }
            }
        }
    }

    private fun restartAutoPlay() {
        autoPlayJob?.cancel()
        if (!autoPlayEnabled) return
        if (items.isEmpty()) return
        val intervalMs = (autoPlayIntervalSeconds.coerceIn(2, 60) * 1000L)
        autoPlayJob =
            lifecycleScope.launch {
                while (true) {
                    delay(intervalMs)
                    nextWrap()
                }
            }
    }

    private fun showCurrent() {
        val item = items.getOrNull(index) ?: return
        filenameView.text = item.filename.ifEmpty { item.path }
        val path = item.path.trim()
        val isVideo = item.isVideo
        playIconView.visibility = if (isVideo) View.VISIBLE else View.GONE
        progressView.visibility = View.GONE

        if (path.isEmpty()) {
            imageView.setImageResource(R.drawable.ic_photo)
            return
        }

        if (isVideo) {
            TvImageLoader.loadTinyInto(
                imageView = imageView,
                filePath = path,
                size = 1280,
                placeholderResId = R.drawable.ic_video,
                showPlaceholderWhileLoading = true,
                onDone = null,
            )
            return
        }

        // 图片大图加载时不再显示占位图片图标，只保留纯色背景 + loading
        imageView.setImageDrawable(null)
        imageView.setBackgroundColor(Color.BLACK)
        val apiPath = PhotoPreviewUrl.buildRawFileApiPath(filePath = path, size = 4000)
        val reqSize = maxOf(resources.displayMetrics.widthPixels, resources.displayMetrics.heightPixels).coerceAtMost(2400)
        progressView.visibility = View.VISIBLE
        TvImageLoader.loadApiPathInto(
            imageView = imageView,
            apiPath = apiPath,
            cacheKeyPrefix = "photo_raw_4000",
            placeholderResId = 0,
            reqSize = reqSize,
            showPlaceholderWhileLoading = false,
            timeoutSeconds = 20,
            onDone = { done ->
                progressView.visibility = View.GONE
            },
        )
    }

    private fun playCurrentVideo(cur: PreviewItem) {
        val p = cur.path.trim()
        if (p.isEmpty()) return
        lifecycleScope.launch {
            if (ApiController.isP2pMode) {
                val ok = ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000)
                if (!ok) return@launch
            }
            val videoItems = items.filter { it.isVideo }
            val startIndex =
                videoItems.indexOfFirst { it.path.trim() == p }.takeIf { it >= 0 } ?: 0
            val playlist =
                ArrayList(
                    videoItems.map {
                        val vp = it.path.trim()
                        TvPlaylistItem(path = vp, name = it.filename.ifEmpty { vp })
                    },
                )
            if (playlist.isEmpty()) return@launch
            val title = cur.filename.ifEmpty { getString(R.string.home_photo_timeline) }
            startActivity(
                TvVideoPlayerActivity.newIntent(
                    this@PhotoPreviewActivity,
                    playlist,
                    startIndex,
                    title,
                    ignoreFindSub = 1,
                ),
            )
        }
    }

    private fun parseItems(intent: Intent): List<PreviewItem> {
        val json = intent.getStringExtra(EXTRA_ITEMS_JSON).orEmpty()
        if (json.isEmpty()) return emptyList()
        val type = object : TypeToken<List<PreviewItem>>() {}.type
        return runCatching { gson.fromJson<List<PreviewItem>>(json, type) }.getOrDefault(emptyList())
    }

    private fun dpToPx(dp: Float): Int = (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)

    override fun onResume() {
        super.onResume()
        JwtSessionExpiredUi.attachResumedActivity(this)
    }

    override fun onDestroy() {
        JwtSessionExpiredUi.detachIfSame(this)
        super.onDestroy()
    }

    data class PreviewItem(
        val path: String,
        val filename: String,
        val duration: Int,
        val id: Int = 0,
        val fileHash: String = "",
        val isFavorite: Boolean = false,
    ) {
        val isVideo: Boolean get() = duration > 0
    }

    companion object {
        private const val EXTRA_ITEMS_JSON = "items_json"
        private const val EXTRA_INDEX = "index"

        fun newIntent(context: Context, items: List<PhotoTimelinePhotoItem>, index: Int): Intent {
            val payload =
                items.map {
                    PreviewItem(
                        path = it.fullPath.ifEmpty { it.path },
                        filename = it.filename,
                        duration = it.duration,
                        id = it.id,
                        fileHash = it.fileHash,
                        isFavorite = it.isFavorite,
                    )
                }
            val json = Gson().toJson(payload)
            return Intent(context, PhotoPreviewActivity::class.java).apply {
                putExtra(EXTRA_ITEMS_JSON, json)
                putExtra(EXTRA_INDEX, index)
            }
        }
    }
}
