package com.nascabos.tv.modules.video.detail

import android.app.Application
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.fragment.app.viewModels
import androidx.leanback.app.VerticalGridSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.BaseGridView
import androidx.leanback.widget.FocusHighlight
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.VerticalGridPresenter
import androidx.leanback.widget.VerticalGridView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.nascabos.tv.AppHostActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.modules.video_player.TvPlaylistItem
import com.nascabos.tv.modules.video_player.TvVideoPlayerActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class VideoEpisodeGridFragment : VerticalGridSupportFragment() {
    private val indexId: Int by lazy { arguments?.getInt(ARG_INDEX_ID) ?: 0 }
    private val overrideTitle: String by lazy { arguments?.getString(ARG_TITLE)?.trim().orEmpty() }
    private val discMode: Boolean by lazy { arguments?.getBoolean(ARG_DISC_MODE) == true }

    private val viewModel: VideoEpisodeGridViewModel by viewModels {
        Factory(requireActivity().application, indexId, discMode)
    }

    private val adapter by lazy { ArrayObjectAdapter(VideoEpisodeCardPresenter(requireContext())) }
    private var headerAdded: Boolean = false
    private var lastRenderedCount: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        title = overrideTitle.ifEmpty { getString(R.string.video_detail_select_episodes_title) }
        val columns = computeColumns()
        val gridPresenter =
            VerticalGridPresenter(FocusHighlight.ZOOM_FACTOR_MEDIUM, false).apply {
                numberOfColumns = columns
            }
        setGridPresenter(gridPresenter)
        setAdapter(adapter)

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                val ep = item as? VideoEpisodeItem ?: return@OnItemViewClickedListener
                playEpisode(ep)
            }

        setOnItemViewSelectedListener { _, item, _, _ ->
            val size = adapter.size()
            if (size <= 0) return@setOnItemViewSelectedListener
            val position = if (item == null) -1 else adapter.indexOf(item)
            if (position >= size - 8) viewModel.loadMore()
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        val grid = findVerticalGridView(view)
        if (grid != null) {
            val side = dpToPx(28f)
            val top = dpToPx(72f)
            val bottom = dpToPx(28f)
            grid.setPadding(side, top, side, bottom)
            grid.clipToPadding = false
            runCatching { grid.setItemSpacing(dpToPx(22f)) }
            grid.windowAlignment = BaseGridView.WINDOW_ALIGN_NO_EDGE
            grid.setWindowAlignmentOffsetPercent(0f)
            grid.setItemAlignmentOffsetPercent(0f)
            grid.layoutDirection = View.LAYOUT_DIRECTION_LTR
        }

        if (!headerAdded) {
            headerAdded = true
            val root = view as? ViewGroup
            if (root != null) {
                val header =
                    TextView(requireContext()).apply {
                        text = title
                        setTextColor(0xBFFFFFFF.toInt())
                        textSize = 20f
                        isFocusable = false
                        isFocusableInTouchMode = false
                    }
                val lp =
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        gravity = Gravity.START or Gravity.TOP
                        leftMargin = dpToPx(28f)
                        topMargin = dpToPx(24f)
                    }
                root.addView(header, lp)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // P2P 下提前预连 video 通道，减少点击集数播放时的等待
        if (ApiController.isP2pMode) {
            viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
                ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000)
            }
        }
    }

    override fun onActivityCreated(savedInstanceState: Bundle?) {
        super.onActivityCreated(savedInstanceState)
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.state.collectLatest { s ->
                render(s)
            }
        }
    }

    private fun render(state: VideoEpisodeGridUiState) {
        val items = state.items
        if (items.isEmpty()) {
            adapter.clear()
            lastRenderedCount = 0
            return
        }
        if (items.size < lastRenderedCount) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            return
        }
        if (items.size == lastRenderedCount) return
        for (i in lastRenderedCount until items.size) {
            adapter.add(items[i])
        }
        lastRenderedCount = items.size
    }

    private fun playEpisode(item: VideoEpisodeItem) {
        val p = item.fullPath.trim()
        if (p.isEmpty()) return
        viewLifecycleOwner.lifecycleScope.launch {
            if (ApiController.isP2pMode) {
                val ready = withContext(Dispatchers.IO) {
                    ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000)
                }
                if (!ready) {
                    (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_play_failed))
                    return@launch
                }
            }
            val (playlist, _) =
                if (discMode) {
                    val items = viewModel.state.value.items
                    val discPlaylist =
                        items.map {
                            TvPlaylistItem(
                                path = it.fullPath.trim(),
                                name = it.name,
                                internalPath = it.internalPath.trim(),
                            )
                        }.filter { it.path.isNotEmpty() }
                    discPlaylist to 0
                } else {
                    runCatching { VideoDetailApiService.getTvPlayInfo(indexId) }.getOrNull()
                        ?: (emptyList<TvPlaylistItem>() to 0)
                }
            val currentInternalPath = item.internalPath.trim()
            val idx =
                playlist.indexOfFirst {
                    it.path.trim() == p &&
                        (currentInternalPath.isEmpty() || it.internalPath.trim() == currentInternalPath)
                }.let { if (it >= 0) it else 0 }
            val intent =
                if (playlist.isNotEmpty()) {
                    TvVideoPlayerActivity.newIntent(
                        context = requireContext(),
                        playlist = playlist,
                        initialIndex = idx,
                        title = title?.toString().orEmpty(),
                        ignoreFindSub = 0,
                    )
                } else {
                    TvVideoPlayerActivity.newIntent(
                        context = requireContext(),
                        playlist = listOf(TvPlaylistItem(path = p, name = "")),
                        initialIndex = 0,
                        title = title?.toString().orEmpty(),
                        ignoreFindSub = 0,
                    )
                }
            runCatching { startActivity(intent) }.onFailure {
                (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_play_failed))
            }
        }
    }

    private fun computeColumns(): Int {
        val widthPx = resources.displayMetrics.widthPixels.coerceAtLeast(1)
        val cardW = dpToPx(220f)
        val spacing = dpToPx(22f)
        val side = dpToPx(28f)
        val available = (widthPx - side * 2).coerceAtLeast(cardW)
        val cols = (available + spacing) / (cardW + spacing)
        return cols.coerceIn(2, 6)
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private fun findVerticalGridView(root: View): VerticalGridView? {
        if (root is VerticalGridView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findVerticalGridView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    class Factory(
        private val app: Application,
        private val indexId: Int,
        private val discMode: Boolean,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(VideoEpisodeGridViewModel::class.java)) {
                return VideoEpisodeGridViewModel(app, indexId, discMode) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        private const val ARG_INDEX_ID = "index_id"
        private const val ARG_TITLE = "title"
        private const val ARG_DISC_MODE = "disc_mode"

        fun newInstance(
            indexId: Int,
            title: String,
            discMode: Boolean = false,
        ): VideoEpisodeGridFragment {
            return VideoEpisodeGridFragment().apply {
                arguments =
                    Bundle().apply {
                        putInt(ARG_INDEX_ID, indexId)
                        val t = title.trim()
                        if (t.isNotEmpty()) putString(ARG_TITLE, t)
                        putBoolean(ARG_DISC_MODE, discMode)
                    }
            }
        }
    }
}
