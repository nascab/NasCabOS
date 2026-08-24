package com.nascabos.tv.modules.video

import android.app.Application
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.viewModels
import androidx.leanback.app.VerticalGridSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.VerticalGridView
import androidx.leanback.widget.FocusHighlight
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.VerticalGridPresenter
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.nascabos.tv.R
import com.nascabos.tv.modules.video.detail.VideoDetailActivity
import com.nascabos.tv.modules.video.presenter.VideoCardPresenter
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class VideoGridFragment : VerticalGridSupportFragment() {
    private val mediaType: String by lazy { arguments?.getString(ARG_MEDIA_TYPE)?.trim().orEmpty() }
    private val albumId: Int by lazy { arguments?.getInt(ARG_ALBUM_ID) ?: 0 }
    private val collectionId: Int by lazy { arguments?.getInt(ARG_COLLECTION_ID) ?: 0 }
    private val smartAlbumId: Int by lazy { arguments?.getInt(ARG_SMART_ALBUM_ID) ?: 0 }
    private val overrideTitle: String by lazy { arguments?.getString(ARG_TITLE)?.trim().orEmpty() }
    private val listType: String by lazy { arguments?.getString(ARG_LIST_TYPE)?.trim().orEmpty() }

    private val viewModel: VideoListViewModel by viewModels {
        Factory(
            requireActivity().application,
            mediaType,
            listType = listType,
            albumId = albumId.takeIf { it > 0 },
            collectionId = collectionId.takeIf { it > 0 },
            smartAlbumId = smartAlbumId.takeIf { it > 0 },
        )
    }

    private val adapter by lazy { ArrayObjectAdapter(VideoCardPresenter(requireContext())) }
    private var lastRenderedCount: Int = 0
    private var lastState: VideoListUiState? = null
    private var headerAdded: Boolean = false
    private var loadingView: ProgressBar? = null
    private var emptyContainer: View? = null
    private var lastRenderKey: RenderKey? = null
    private var lastItemsSignature: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SEARCH, this) { _, bundle ->
            val q = bundle.getString(RESULT_FIELD_QUERY)?.trim().orEmpty()
            Log.d("VideoGridFragment", "result_search q='$q'")
            if (q.isEmpty()) viewModel.clearSearch() else viewModel.setSearch(q)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SORT, this) { _, bundle ->
            val byRaw = bundle.getString(RESULT_FIELD_SORT_BY)?.trim().orEmpty()
            val orderRaw = bundle.getString(RESULT_FIELD_SORT_ORDER)?.trim().orEmpty()
            Log.d("VideoGridFragment", "result_sort by='$byRaw' order='$orderRaw'")
            val by = runCatching { VideoListSortBy.valueOf(byRaw) }.getOrNull()
            val order = runCatching { VideoListSortOrder.valueOf(orderRaw) }.getOrNull()
            if (by != null && order != null) {
                viewModel.setSort(VideoListSortState(by = by, order = order))
            }
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SOURCES, this) { _, bundle ->
            val list = bundle.getStringArrayList(RESULT_FIELD_SOURCES) ?: arrayListOf()
            viewModel.setSourcePaths(list.toSet())
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_MEDIA_TYPE_FILTER, this) { _, bundle ->
            val mt = bundle.getString(RESULT_FIELD_MEDIA_TYPE_FILTER)?.trim().orEmpty()
            viewModel.setMediaTypeFilter(mt)
        }

        title =
            overrideTitle.ifEmpty {
                when (mediaType.trim().lowercase()) {
                    "tv" -> getString(R.string.home_video_tv_series)
                    else -> getString(R.string.home_video_movies)
                }
            }

        val columns = computeColumns()
        val gridPresenter =
            VerticalGridPresenter(FocusHighlight.ZOOM_FACTOR_MEDIUM, false).apply {
                numberOfColumns = columns
            }
        setGridPresenter(gridPresenter)
        setAdapter(adapter)

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                val video = item as? VideoListItem ?: return@OnItemViewClickedListener
                openPlaceholder(video)
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
        }

        if (!headerAdded) {
            headerAdded = true
            val root = view as? ViewGroup
            if (root != null) {
                val header =
                    TextView(requireContext()).apply {
                        text = title
                        setTextColor(Color.parseColor("#BFFFFFFF"))
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

                val progress =
                    ProgressBar(requireContext()).apply {
                        isIndeterminate = true
                        visibility = View.GONE
                    }
                val progressLp =
                    FrameLayout.LayoutParams(
                        dpToPx(48f),
                        dpToPx(48f),
                    ).apply {
                        gravity = Gravity.CENTER
                    }
                root.addView(progress, progressLp)
                loadingView = progress

                val empty =
                    FrameLayout(requireContext()).apply {
                        setBackgroundColor(Color.parseColor("#121212"))
                        visibility = View.GONE
                        isClickable = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                    }

                val emptyContent =
                    LinearLayout(requireContext()).apply {
                        orientation = LinearLayout.VERTICAL
                        gravity = Gravity.CENTER
                        isClickable = false
                        isFocusable = false
                        isFocusableInTouchMode = false
                    }

                val emptyImage =
                    ImageView(requireContext()).apply {
                        setImageResource(R.drawable.no_data)
                        scaleType = ImageView.ScaleType.FIT_CENTER
                    }
                emptyContent.addView(
                    emptyImage,
                    LinearLayout.LayoutParams(
                        dpToPx(220f),
                        dpToPx(140f),
                    ),
                )

                val emptyText =
                    TextView(requireContext()).apply {
                        text = getString(R.string.common_no_data)
                        setTextColor(0x99FFFFFF.toInt())
                        textSize = 16f
                        isFocusable = false
                        isFocusableInTouchMode = false
                    }
                emptyContent.addView(
                    emptyText,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { topMargin = dpToPx(14f) },
                )

                empty.addView(
                    emptyContent,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { gravity = Gravity.CENTER },
                )

                val emptyLp =
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    )
                root.addView(empty, emptyLp)
                emptyContainer = empty
            }
        }
    }

    override fun onActivityCreated(savedInstanceState: Bundle?) {
        super.onActivityCreated(savedInstanceState)
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.state.collectLatest { s ->
                lastState = s
                renderState(s)
            }
        }
    }

    private fun renderState(state: VideoListUiState) {
        loadingView?.visibility = if (state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
        emptyContainer?.visibility = if (!state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE

        val items = state.items
        val key =
            RenderKey(
                search = state.searchText,
                sort = state.sort,
                sources = state.selectedPaths,
                mediaTypeFilter = state.mediaTypeFilter,
            )
        val sig = itemsSignature(items)

        // 筛选/排序/搜索等条件变化 → 全量刷新
        if (lastRenderKey != key) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            lastRenderKey = key
            lastItemsSignature = sig
            return
        }
        if (items.isEmpty()) {
            adapter.clear()
            lastRenderedCount = 0
            return
        }
        // 列表被替换或截断（如 refresh）→ 全量刷新
        if (items.size < lastRenderedCount) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            lastItemsSignature = sig
            return
        }
        if (items.size == lastRenderedCount) return
        // 首次有数据 → 全量填充
        if (lastRenderedCount == 0) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            lastItemsSignature = sig
            return
        }
        // 仅追加新项（加载下一页），不 clear，避免滚动位置跳回顶部
        for (i in lastRenderedCount until items.size) {
            adapter.add(items[i])
        }
        lastRenderedCount = items.size
        lastItemsSignature = sig
    }

    private fun openPlaceholder(video: VideoListItem) {
        val id = video.id
        if (id <= 0) return
        val ctx = context ?: return
        startActivity(VideoDetailActivity.createIntent(ctx, id))
    }

    fun openOptionsFromActivity() {
        if (listType.trim().lowercase() == "history") return
        val s = lastState ?: return
        val activity = activity ?: return
        val paths = s.availablePaths.map { it.path }.filter { it.isNotBlank() }
        VideoOptionsDialogFragment
            .newInstance(
                mediaType = s.mediaType,
                listType = listType,
                currentSearch = s.searchText,
                sortBy = s.sort.by.name,
                sortOrder = s.sort.order.name,
                availablePaths = ArrayList(paths),
                selectedPaths = ArrayList(s.selectedPaths.toList()),
                currentMediaTypeFilter = s.mediaTypeFilter,
                enableMediaTypeFilter = (albumId > 0 || collectionId > 0 || smartAlbumId > 0),
            )
            .show(activity.supportFragmentManager, "video_options")
    }

    private fun computeColumns(): Int {
        val widthPx = resources.displayMetrics.widthPixels.coerceAtLeast(1)
        val cardW = dpToPx(136f)
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

    private data class RenderKey(
        val search: String,
        val sort: VideoListSortState,
        val sources: Set<String>,
        val mediaTypeFilter: String,
    )

    private fun itemsSignature(items: List<VideoListItem>): Long {
        var h = 1469598103934665603L
        for (i in 0 until items.size) {
            h = h xor items[i].id.toLong()
            h *= 1099511628211L
        }
        h = h xor items.size.toLong()
        h *= 1099511628211L
        return h
    }

    class Factory(
        private val app: Application,
        private val mediaType: String,
        private val listType: String,
        private val albumId: Int? = null,
        private val collectionId: Int? = null,
        private val smartAlbumId: Int? = null,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(VideoListViewModel::class.java)) {
                return VideoListViewModel(
                    app,
                    mediaType,
                    listType = listType,
                    albumId = albumId,
                    collectionId = collectionId,
                    smartAlbumId = smartAlbumId,
                ) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        private const val ARG_MEDIA_TYPE = "media_type"
        private const val ARG_ALBUM_ID = "album_id"
        private const val ARG_COLLECTION_ID = "collection_id"
        private const val ARG_SMART_ALBUM_ID = "smart_album_id"
        private const val ARG_TITLE = "title"
        private const val ARG_LIST_TYPE = "list_type"
        const val RESULT_KEY_SEARCH = "video_list_result_search"
        const val RESULT_KEY_SORT = "video_list_result_sort"
        const val RESULT_KEY_SOURCES = "video_list_result_sources"
        const val RESULT_KEY_MEDIA_TYPE_FILTER = "video_list_result_media_type_filter"
        const val RESULT_FIELD_QUERY = "query"
        const val RESULT_FIELD_SORT_BY = "sort_by"
        const val RESULT_FIELD_SORT_ORDER = "sort_order"
        const val RESULT_FIELD_SOURCES = "sources"
        const val RESULT_FIELD_MEDIA_TYPE_FILTER = "media_type_filter"

        fun newInstance(
            mediaType: String,
            title: String? = null,
            listType: String? = null,
            albumId: Int? = null,
            collectionId: Int? = null,
            smartAlbumId: Int? = null,
        ): VideoGridFragment {
            return VideoGridFragment().apply {
                arguments =
                    Bundle().apply {
                        putString(ARG_MEDIA_TYPE, mediaType)
                        val t = title?.trim().orEmpty()
                        if (t.isNotEmpty()) putString(ARG_TITLE, t)
                        val lt = listType?.trim().orEmpty()
                        if (lt.isNotEmpty()) putString(ARG_LIST_TYPE, lt)
                        val aid = albumId ?: 0
                        if (aid > 0) putInt(ARG_ALBUM_ID, aid)
                        val cid = collectionId ?: 0
                        if (cid > 0) putInt(ARG_COLLECTION_ID, cid)
                        val sid = smartAlbumId ?: 0
                        if (sid > 0) putInt(ARG_SMART_ALBUM_ID, sid)
                    }
            }
        }
    }
}
