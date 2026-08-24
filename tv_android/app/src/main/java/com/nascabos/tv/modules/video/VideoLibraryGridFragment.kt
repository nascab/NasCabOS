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
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.viewModels
import androidx.leanback.app.VerticalGridSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.FocusHighlight
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.VerticalGridPresenter
import androidx.leanback.widget.VerticalGridView
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.nascabos.tv.R
import com.nascabos.tv.modules.video.presenter.VideoLibraryCardPresenter
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class VideoLibraryGridFragment : VerticalGridSupportFragment() {
    private val kind: VideoLibraryKind by lazy {
        val raw = arguments?.getString(ARG_KIND)?.trim().orEmpty()
        runCatching { VideoLibraryKind.valueOf(raw) }.getOrNull() ?: VideoLibraryKind.Album
    }

    private val viewModel: VideoLibraryListViewModel by viewModels {
        Factory(requireActivity().application, kind)
    }

    private val adapter by lazy { ArrayObjectAdapter(VideoLibraryCardPresenter(requireContext(), kind)) }
    private var headerAdded: Boolean = false
    private var loadingView: ProgressBar? = null
    private var emptyContainer: FrameLayout? = null
    private var lastRenderedCount: Int = 0
    private var lastRenderKey: RenderKey? = null
    private var lastItemsSignature: Long = 0L
    private var lastState: VideoLibraryUiState? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SEARCH, this) { _, bundle ->
            val q = bundle.getString(RESULT_FIELD_QUERY)?.trim().orEmpty()
            Log.d("VideoLibraryGrid", "result_search q='$q'")
            if (q.isEmpty()) viewModel.clearKeyword() else viewModel.setKeyword(q)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SORT, this) { _, bundle ->
            val fieldRaw = bundle.getString(RESULT_FIELD_SORT_FIELD)?.trim().orEmpty()
            val orderRaw = bundle.getString(RESULT_FIELD_SORT_ORDER)?.trim().orEmpty()
            val field = runCatching { VideoLibrarySortField.valueOf(fieldRaw) }.getOrNull()
            val order = runCatching { VideoLibrarySortOrder.valueOf(orderRaw) }.getOrNull()
            if (field != null && order != null) {
                viewModel.setSort(VideoLibrarySortState(field = field, order = order))
            }
        }

        title =
            when (kind) {
                VideoLibraryKind.Album -> getString(R.string.home_video_custom_albums)
                VideoLibraryKind.SmartAlbum -> getString(R.string.home_video_smart_albums)
                VideoLibraryKind.Collection -> getString(R.string.home_video_collections)
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
                val data = item as? VideoLibraryListItem ?: return@OnItemViewClickedListener
                openLibraryItem(data)
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
                val emptyIcon =
                    ImageView(requireContext()).apply {
                        setImageResource(R.drawable.ic_video)
                        setColorFilter(0x66FFFFFF.toInt())
                        scaleType = ImageView.ScaleType.FIT_CENTER
                    }
                val emptyIconLp =
                    FrameLayout.LayoutParams(
                        dpToPx(88f),
                        dpToPx(88f),
                    ).apply {
                        gravity = Gravity.CENTER
                    }
                empty.addView(emptyIcon, emptyIconLp)

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

    private fun renderState(state: VideoLibraryUiState) {
        loadingView?.visibility = if (state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
        emptyContainer?.visibility = if (!state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE

        val items = state.items
        val key = RenderKey(keyword = state.keyword, sort = state.sort)
        val sig = itemsSignature(items)
        if (lastRenderKey != key || lastItemsSignature != sig) {
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
        lastItemsSignature = sig
    }

    fun openOptionsFromActivity() {
        val s = lastState ?: return
        val activity = activity ?: return
        VideoLibraryOptionsDialogFragment
            .newInstance(
                kind = kind.name,
                currentKeyword = s.keyword,
                sortField = s.sort.field.name,
                sortOrder = s.sort.order.name,
            )
            .show(activity.supportFragmentManager, "video_library_options")
    }

    private fun openLibraryItem(item: VideoLibraryListItem) {
        val activity = activity ?: return
        val aid = if (item.kind == VideoLibraryKind.Album) item.id else null
        val cid = if (item.kind == VideoLibraryKind.Collection) item.id else null
        val sid = if (item.kind == VideoLibraryKind.SmartAlbum) item.id else null
        val prefix =
            when (item.kind) {
                VideoLibraryKind.Album -> getString(R.string.video_library_prefix_album)
                VideoLibraryKind.SmartAlbum -> getString(R.string.video_library_prefix_smart_album)
                VideoLibraryKind.Collection -> getString(R.string.video_library_prefix_collection)
            }.trim()
        val name = item.name.trim()
        val title = if (name.isNotEmpty()) "${prefix}-${name}" else prefix
        activity.supportFragmentManager.beginTransaction()
            .replace(
                R.id.main_container,
                VideoGridFragment.newInstance(
                    mediaType = "all",
                    title = title,
                    albumId = aid,
                    collectionId = cid,
                    smartAlbumId = sid,
                ),
            )
            .addToBackStack(null)
            .commit()
    }

    private fun computeColumns(): Int {
        val widthPx = resources.displayMetrics.widthPixels.coerceAtLeast(1)
        val cardW = dpToPx(300f)
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
        val keyword: String,
        val sort: VideoLibrarySortState,
    )

    private fun itemsSignature(items: List<VideoLibraryListItem>): Long {
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
        private val kind: VideoLibraryKind,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(VideoLibraryListViewModel::class.java)) {
                return VideoLibraryListViewModel(app, kind) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        private const val ARG_KIND = "kind"
        const val RESULT_KEY_SEARCH = "video_library_result_search"
        const val RESULT_KEY_SORT = "video_library_result_sort"
        const val RESULT_FIELD_QUERY = "query"
        const val RESULT_FIELD_SORT_FIELD = "sort_field"
        const val RESULT_FIELD_SORT_ORDER = "sort_order"

        fun newInstance(kind: VideoLibraryKind): VideoLibraryGridFragment {
            return VideoLibraryGridFragment().apply {
                arguments = Bundle().apply { putString(ARG_KIND, kind.name) }
            }
        }
    }
}
