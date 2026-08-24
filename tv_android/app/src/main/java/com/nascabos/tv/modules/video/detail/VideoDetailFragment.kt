package com.nascabos.tv.modules.video.detail

import android.app.Application
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.core.content.ContextCompat
import androidx.fragment.app.viewModels
import androidx.leanback.app.BackgroundManager
import androidx.leanback.app.DetailsSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.ClassPresenterSelector
import androidx.leanback.widget.DetailsOverviewRow
import androidx.leanback.widget.HeaderItem
import androidx.leanback.widget.ListRow
import androidx.leanback.widget.ListRowPresenter
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.SparseArrayObjectAdapter
import androidx.leanback.widget.VerticalGridView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.nascabos.tv.AppHostActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.video_player.TvPlaylistItem
import com.nascabos.tv.modules.video_player.TvVideoPlayerActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class VideoDetailFragment : DetailsSupportFragment() {
    private val indexId: Int by lazy { arguments?.getInt(ARG_INDEX_ID) ?: 0 }

    private val viewModel: VideoDetailViewModel by viewModels {
        Factory(requireActivity().application, indexId)
    }

    private val backgroundManager by lazy { BackgroundManager.getInstance(requireActivity()) }
    private var previousBackground: Drawable? = null
    private val classPresenterSelector by lazy { ClassPresenterSelector() }
    private val rowsAdapter by lazy { ArrayObjectAdapter(classPresenterSelector) }
    private var detailsPresenter: VideoDetailsOverviewRowPresenter? = null
    private var loadingView: ProgressBar? = null

    private var lastDataKey: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (detailsPresenter == null) {
            val dp =
                VideoDetailsOverviewRowPresenter(
                    VideoDetailsDescriptionPresenter(requireContext()),
                ).apply {
                    setOnActionClickedListener { id ->
                        handleAction(id)
                    }
                }
            detailsPresenter = dp
            classPresenterSelector.addClassPresenter(DetailsOverviewRow::class.java, dp)
            classPresenterSelector.addClassPresenter(ListRow::class.java, VideoDetailListRowPresenter())
        }
        adapter = rowsAdapter
        if (!backgroundManager.isAttached) backgroundManager.attach(requireActivity().window)
        if (previousBackground == null) previousBackground = backgroundManager.drawable

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                when (item) {
                    is VideoSeasonItem -> openSeason(item.id)
                }
            }
    }

    override fun onViewCreated(view: android.view.View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        applyDetailsListBackground(view)

        val root = view as? ViewGroup
        if (root != null && loadingView == null) {
            val progress =
                ProgressBar(requireContext()).apply {
                    isIndeterminate = true
                    visibility = View.GONE
                }
            val w = dpToPx(48f)
            val h = dpToPx(48f)
            val progressLp =
                if (root is FrameLayout) {
                    FrameLayout.LayoutParams(w, h).apply { gravity = Gravity.CENTER }
                } else {
                    ViewGroup.LayoutParams(w, h)
                }
            root.addView(progress, progressLp)
            loadingView = progress
        }
    }

    override fun onResume() {
        super.onResume()
        viewModel.state.value.data?.let { setFanartBackground(it.item) }
        // P2P 下提前预连 video 通道，减少点击播放时的等待（5–10s → 约 1s）
        if (ApiController.isP2pMode) {
            viewLifecycleOwner.lifecycleScope.launch(Dispatchers.IO) {
                ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000)
            }
        }
    }

    override fun onDestroyView() {
        if (!requireActivity().isFinishing) {
            try {
                backgroundManager.drawable = previousBackground
            } catch (_: Exception) {
                // BackgroundManager 在 Activity 销毁过程中可能已释放内部服务，忽略
            }
        }
        super.onDestroyView()
    }

    /** 与详情页上部一致的半透明黑，用于列表整体容器 */
    private val detailsListBackgroundColor = Color.argb(217, 0, 0, 0)

    private fun applyDetailsListBackground(root: View) {
        val grid = findVerticalGridView(root) ?: return
        grid.setBackgroundColor(detailsListBackgroundColor)
        (grid.parent as? ViewGroup)?.setBackgroundColor(detailsListBackgroundColor)
    }

    private fun findVerticalGridView(v: View): VerticalGridView? {
        if (v is VerticalGridView) return v
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) {
                findVerticalGridView(v.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    override fun onActivityCreated(savedInstanceState: Bundle?) {
        super.onActivityCreated(savedInstanceState)
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.state.collectLatest { s ->
                render(s)
            }
        }
    }

    private fun handleAction(id: Long) {
        when (id) {
            ACTION_PLAY -> playMain()
            ACTION_FAVORITE -> viewModel.toggleFavorite()
            ACTION_SCAN -> {
                viewModel.scanChanges()
                (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_scan_queued))
            }
            ACTION_DELETE -> confirmDelete()
            ACTION_SELECT_EPISODES -> openEpisodePage()
            ACTION_SELECT_SEASON -> scrollToSeasonRow()
        }
    }

    private fun render(state: VideoDetailUiState) {
        loadingView?.visibility = if (state.loading && state.data == null) View.VISIBLE else View.GONE

        val detail = state.data ?: return
        val key = detail.item.id.toLong() xor (detail.item.isFavorite.hashCode().toLong() shl 1)
        if (key == lastDataKey && rowsAdapter.size() > 0) return
        lastDataKey = key

        rowsAdapter.clear()
        title = detail.item.displayTitle
        addDetailsRow(detail)
        addSeasonRowIfNeeded(detail)
        addPeopleRowIfNeeded(detail)
        setFanartBackground(detail.item)
    }

    private fun confirmDelete() {
        val item = viewModel.state.value.data?.item ?: return
        val ctx = activity ?: return
        androidx.appcompat.app.AlertDialog.Builder(ctx)
            .setTitle(getString(R.string.video_detail_delete_title))
            .setMessage(getString(R.string.video_detail_delete_message, item.displayTitle))
            .setPositiveButton(getString(R.string.action_delete)) { _, _ ->
                viewModel.deleteItem { ok ->
                    if (!ok) {
                        (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_delete_failed))
                        return@deleteItem
                    }
                    if (activity is VideoDetailActivity) {
                        (activity as? VideoDetailActivity)?.finish()
                    } else {
                        activity?.supportFragmentManager?.popBackStack()
                    }
                }
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun playEpisode(fullPath: String) {
        val p = fullPath.trim()
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
            val intent =
                TvVideoPlayerActivity.newIntent(
                    context = requireContext(),
                    playlist = listOf(TvPlaylistItem(path = p, name = "")),
                    initialIndex = 0,
                    title = title?.toString().orEmpty(),
                    ignoreFindSub = 0,
                )
            runCatching { startActivity(intent) }.onFailure {
                (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_play_failed))
            }
        }
    }

    private fun playMain() {
        viewModel.buildPlayIntent { intent ->
            if (intent == null) {
                (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_play_failed))
                return@buildPlayIntent
            }
            runCatching { startActivity(intent) }.onFailure {
                (activity as? AppHostActivity)?.showError(getString(R.string.video_detail_play_failed))
            }
        }
    }

    private fun openSeason(seasonId: Int) {
        if (seasonId <= 0) return
        activity?.supportFragmentManager?.beginTransaction()
            ?.replace(R.id.main_container, newInstance(seasonId))
            ?.addToBackStack(null)
            ?.commit()
    }

    /** 详情页往上滚，滚动到季列表区块（选季 action 调用） */
    private fun scrollToSeasonRow() {
        val root = view ?: return
        val grid = findVerticalGridView(root) ?: return
        val targetPosition = 1
        if (targetPosition < rowsAdapter.size()) {
            grid.post { grid.setSelectedPosition(targetPosition) }
        }
    }

    private fun openEpisodePage() {
        val data = viewModel.state.value.data ?: return
        val t = data.item.mediaType.trim().lowercase()
        val hasSeasons = t == "tv" && data.seasonList.isNotEmpty()
        val need =
            when (t) {
                "season" -> true
                "tv" -> !hasSeasons && data.item.seasonCount <= 1
                "bdmv", "video_ts" -> true
                else -> false
            }
        if (!need) return
        activity?.supportFragmentManager?.beginTransaction()
            ?.replace(
                R.id.main_container,
                VideoEpisodeGridFragment.newInstance(
                    indexId = data.item.id,
                    title = data.item.displayTitle,
                    discMode = t == "bdmv" || t == "video_ts",
                ),
            )
            ?.addToBackStack(null)
            ?.commit()
    }

    private fun addDetailsRow(detail: VideoDetailData) {
        val payload = VideoDetailRowData(item = detail.item, history = detail.history)
        val row = DetailsOverviewRow(payload)
        row.actionsAdapter = buildActions(detail)

        rowsAdapter.add(row)
        loadPosterIntoRow(row, detail.item)
    }

    private fun buildActions(detail: VideoDetailData): SparseArrayObjectAdapter {
        val adapter = SparseArrayObjectAdapter()
        val playIcon = ContextCompat.getDrawable(requireContext(), R.drawable.ic_play)
        val canResume = detail.history?.hasProgress == true
        val playLabel = if (canResume) getString(R.string.video_detail_action_continue_play) else getString(R.string.video_detail_action_play)
        val playAction = androidx.leanback.widget.Action(ACTION_PLAY, playLabel)
        if (playIcon != null) {
            runCatching {
                val m = playAction.javaClass.getMethod("setIcon", android.graphics.drawable.Drawable::class.java)
                m.invoke(playAction, playIcon)
            }
        }
        adapter.set(ACTION_PLAY.toInt(), playAction)
        val t = detail.item.mediaType.trim().lowercase()
        val hasSeasons = t == "tv" && detail.seasonList.isNotEmpty()
        if (hasSeasons) {
            adapter.set(ACTION_SELECT_SEASON.toInt(), androidx.leanback.widget.Action(ACTION_SELECT_SEASON, getString(R.string.video_detail_action_select_season)))
        }
        val showSelectEpisodes =
            when (t) {
                "season" -> true
                "tv" -> !hasSeasons && detail.item.seasonCount <= 1
                "bdmv", "video_ts" -> true
                else -> false
            }
        if (showSelectEpisodes) {
            adapter.set(ACTION_SELECT_EPISODES.toInt(), androidx.leanback.widget.Action(ACTION_SELECT_EPISODES, getString(R.string.video_detail_action_select_episodes)))
        }
        val favTitle =
            if (detail.item.isFavorite) getString(R.string.video_detail_action_unfavorite) else getString(R.string.video_detail_action_favorite)
        adapter.set(ACTION_FAVORITE.toInt(), androidx.leanback.widget.Action(ACTION_FAVORITE, favTitle))
        adapter.set(ACTION_SCAN.toInt(), androidx.leanback.widget.Action(ACTION_SCAN, getString(R.string.video_detail_action_scan)))
//        adapter.set(ACTION_DELETE.toInt(), androidx.leanback.widget.Action(ACTION_DELETE, getString(R.string.video_detail_action_delete)))
        return adapter
    }

    private fun addSeasonRowIfNeeded(detail: VideoDetailData) {
        if (detail.item.mediaType.trim().lowercase() != "tv") return
        if (detail.seasonList.isEmpty()) return
        val seasonAdapter = ArrayObjectAdapter(VideoSeasonCardPresenter(requireContext()))
        detail.seasonList.forEach { seasonAdapter.add(it) }
        rowsAdapter.add(ListRow(HeaderItem(ROW_SEASONS, getString(R.string.video_detail_seasons)), seasonAdapter))
    }

    private fun addPeopleRowIfNeeded(detail: VideoDetailData) {
        val people = ArrayList<VideoPerson>()
        people.addAll(detail.item.directors)
        people.addAll(detail.item.actors)
        if (people.isEmpty()) return
        val adapter = ArrayObjectAdapter(VideoPersonCardPresenter(requireContext()))
        people.forEach { adapter.add(it) }
        rowsAdapter.add(ListRow(HeaderItem(ROW_PEOPLE, getString(R.string.video_detail_people)), adapter))
    }

    /** 背景只占屏幕上方此比例（约 60%） */
    private val backgroundTopFraction = 1f

    private fun setFanartBackground(item: VideoDetailItem) {
        val discPick = detailDiscThumbApiPath(item = item, size = 1280)
        val fallback =
            item.fanartPath.trim().ifEmpty {
                item.posterPath.trim().ifEmpty {
                    item.firstFilePath.trim().ifEmpty { item.fullPath.trim() }
                }
            }.trim()
        val pick = if (fallback.isNotEmpty()) "" else discPick
        if (pick.isEmpty()) {
            if (fallback.isEmpty()) {
                backgroundManager.drawable = ContextCompat.getDrawable(requireContext(), R.drawable.video_detail_bg)
                return
            }
            viewLifecycleOwner.lifecycleScope.launch {
                val bmp = TvImageLoader.loadTinyBitmap(filePath = fallback, size = 1280, reqSize = 1280, timeoutSeconds = 12)
                if (bmp == null) {
                    backgroundManager.drawable = ContextCompat.getDrawable(requireContext(), R.drawable.video_detail_bg)
                    return@launch
                }
                backgroundManager.drawable = TopFractionDrawable(BitmapDrawable(resources, bmp), backgroundTopFraction)
            }
            return
        }
        viewLifecycleOwner.lifecycleScope.launch {
            val bmp = TvImageLoader.loadApiPathBitmap(apiPath = pick, cacheKeyPrefix = "video-disc-bg", reqSize = 1280, timeoutSeconds = 12)
            if (bmp == null) {
                backgroundManager.drawable = ContextCompat.getDrawable(requireContext(), R.drawable.video_detail_bg)
                return@launch
            }
            backgroundManager.drawable = TopFractionDrawable(BitmapDrawable(resources, bmp), backgroundTopFraction)
        }
    }

    private fun detailDiscThumbApiPath(
        item: VideoDetailItem,
        size: Int = 1280,
    ): String {
        val detail = viewModel.state.value.data ?: return ""
        val mt = item.mediaType.trim().lowercase()
        if (mt != "bdmv" && mt != "video_ts") return ""
        val discItem =
            detail.discContents.firstOrNull {
                it.resolvedThumbnailPath.isNotEmpty() ||
                    it.resolvedThumbnailInternalPath.isNotEmpty()
            } ?: return ""
        if (discItem.resolvedThumbnailPath.isNotEmpty()) {
            return TvImageLoader.buildTinyApiPath(discItem.resolvedThumbnailPath, size = size)
        }
        val internalPath = discItem.resolvedThumbnailInternalPath
        if (internalPath.isEmpty()) return ""
        return VideoDetailApiService.buildDiscContentThumbApiPath(indexId = item.id, internalPath = internalPath, size = size)
    }

    private fun loadPosterIntoRow(row: DetailsOverviewRow, item: VideoDetailItem) {
        val poster = item.posterPath.trim()
        val firstFile = item.firstFilePath.trim()
        val fullPath = item.fullPath.trim()
        val mt = item.mediaType.trim().lowercase()
        val discApiPath = detailDiscThumbApiPath(item = item, size = 640)
        val pick = when {
            poster.isNotEmpty() -> poster
            discApiPath.isNotEmpty() -> ""
            mt == "tv" || mt == "season" -> firstFile
            else -> fullPath
        }.trim()

        fun showDiscPosterOr404() {
            if (discApiPath.isEmpty()) {
                row.imageDrawable = ContextCompat.getDrawable(requireContext(), R.drawable.img_404)
                rowsAdapter.notifyArrayItemRangeChanged(0, 1)
                return
            }
            viewLifecycleOwner.lifecycleScope.launch {
                val bmp =
                    TvImageLoader.loadApiPathBitmap(
                        apiPath = discApiPath,
                        cacheKeyPrefix = "video-disc-poster",
                        reqSize = 640,
                        timeoutSeconds = 12,
                    )
                row.imageDrawable =
                    if (bmp != null) {
                        BitmapDrawable(resources, bmp)
                    } else {
                        ContextCompat.getDrawable(requireContext(), R.drawable.img_404)
                    }
                rowsAdapter.notifyArrayItemRangeChanged(0, 1)
            }
        }

        if (pick.isEmpty()) {
            showDiscPosterOr404()
            return
        }
        viewLifecycleOwner.lifecycleScope.launch {
            val bmp = TvImageLoader.loadTinyBitmap(filePath = pick, size = 640, reqSize = 640, timeoutSeconds = 12)
            if (bmp == null) {
                if (poster.isNotEmpty() && discApiPath.isNotEmpty()) {
                    showDiscPosterOr404()
                    return@launch
                }
                row.imageDrawable = ContextCompat.getDrawable(requireContext(), R.drawable.img_404)
            } else {
                row.imageDrawable = BitmapDrawable(resources, bmp)
            }
            rowsAdapter.notifyArrayItemRangeChanged(0, 1)
        }
    }

    class Factory(
        private val app: Application,
        private val indexId: Int,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(VideoDetailViewModel::class.java)) {
                return VideoDetailViewModel(app, indexId) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        private const val ARG_INDEX_ID = "index_id"

        private const val ACTION_PLAY = 1L
        private const val ACTION_SELECT_SEASON = 2L
        private const val ACTION_SELECT_EPISODES = 3L
        private const val ACTION_FAVORITE = 4L
        private const val ACTION_SCAN = 5L
        private const val ACTION_DELETE = 6L

        private const val ROW_SEASONS = 10L
        private const val ROW_PEOPLE = 12L

        fun newInstance(indexId: Int): VideoDetailFragment {
            return VideoDetailFragment().apply {
                arguments = Bundle().apply { putInt(ARG_INDEX_ID, indexId) }
            }
        }
    }
}
