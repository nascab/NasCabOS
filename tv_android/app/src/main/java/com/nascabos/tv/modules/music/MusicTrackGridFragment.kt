package com.nascabos.tv.modules.music

import android.app.Application
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.os.bundleOf
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
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.modules.music.player.MusicNowPlayingActivity
import com.nascabos.tv.modules.music.player.MusicPlaybackService
import com.nascabos.tv.modules.music.presenter.MusicTrackRowPresenter
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MusicTrackGridFragment : VerticalGridSupportFragment() {
    private val titleArg: String by lazy { arguments?.getString(ARG_TITLE)?.trim().orEmpty() }
    private val isFavorite: Boolean by lazy { arguments?.getBoolean(ARG_IS_FAVORITE, false) ?: false }
    private val seriesIndexId: Int by lazy { arguments?.getInt(ARG_SERIES_INDEX_ID) ?: 0 }
    private val listType: String by lazy { arguments?.getString(ARG_LIST_TYPE)?.trim().orEmpty() }
    private val listId: Int by lazy { arguments?.getInt(ARG_LIST_ID) ?: 0 }
    private val artists: ArrayList<String> by lazy { arguments?.getStringArrayList(ARG_ARTISTS) ?: arrayListOf() }
    private val albums: ArrayList<String> by lazy { arguments?.getStringArrayList(ARG_ALBUMS) ?: arrayListOf() }

    private val viewModel: MusicTrackListViewModel by viewModels {
        Factory(
            requireActivity().application,
            titleArg,
            isFavorite = isFavorite,
            listType = listType.ifEmpty { null },
            listId = listId.takeIf { it > 0 },
            seriesIndexId = seriesIndexId.takeIf { it > 0 },
            artists = artists.map { it.trim() }.filter { it.isNotEmpty() }.ifEmpty { null },
            albums = albums.map { it.trim() }.filter { it.isNotEmpty() }.ifEmpty { null },
        )
    }

    private val adapter by lazy { ArrayObjectAdapter(MusicTrackRowPresenter(requireContext())) }
    private var lastRenderedCount: Int = 0
    private var lastRenderKey: RenderKey? = null
    private var lastFirstId: Long = 0L
    private var lastLastId: Long = 0L
    private var headerAdded: Boolean = false
    private var loadingView: ProgressBar? = null
    private var lastState: MusicTrackListUiState? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SEARCH, this) { _, bundle ->
            val q = bundle.getString(RESULT_FIELD_QUERY)?.trim().orEmpty()
            if (q.isEmpty()) viewModel.clearSearch() else viewModel.setSearch(q)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SORT, this) { _, bundle ->
            val byRaw = bundle.getString(RESULT_FIELD_SORT_BY)?.trim().orEmpty()
            val orderRaw = bundle.getString(RESULT_FIELD_SORT_ORDER)?.trim().orEmpty()
            val by = runCatching { MusicListSortBy.valueOf(byRaw) }.getOrNull()
            val order = runCatching { MusicListSortOrder.valueOf(orderRaw) }.getOrNull()
            if (by != null && order != null) {
                viewModel.setSort(MusicListSortState(by = by, order = order))
            }
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SOURCES, this) { _, bundle ->
            val list = bundle.getStringArrayList(RESULT_FIELD_SOURCES) ?: arrayListOf()
            viewModel.setSourcePaths(list.toSet())
        }

        title = titleArg

        val columns = 1
        val gridPresenter =
            VerticalGridPresenter(FocusHighlight.ZOOM_FACTOR_MEDIUM, false).apply {
                numberOfColumns = columns
            }
        setGridPresenter(gridPresenter)
        setAdapter(adapter)

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                val music = item as? MusicListItem ?: return@OnItemViewClickedListener
                if (music.isFolder) {
                    openFolder(music)
                } else {
                    startPlaybackFromCurrentList(music)
                }
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
            runCatching { grid.setItemSpacing(dpToPx(10f)) }
            runCatching { grid.setItemAlignmentOffsetPercent(0f) }
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

    private fun renderState(state: MusicTrackListUiState) {
        loadingView?.visibility = if (state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
        val items = state.items
        val key =
            RenderKey(
                search = state.searchText,
                sort = state.sort,
                sources = state.selectedPaths,
            )
        val firstId = items.firstOrNull()?.id?.toLong() ?: 0L
        val lastId = items.lastOrNull()?.id?.toLong() ?: 0L
        if (lastRenderKey != key) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            lastRenderKey = key
            lastFirstId = firstId
            lastLastId = lastId
            return
        }
        if (items.isEmpty()) {
            adapter.clear()
            lastRenderedCount = 0
            lastFirstId = 0L
            lastLastId = 0L
            return
        }
        if (items.size < lastRenderedCount) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            lastFirstId = firstId
            lastLastId = lastId
            return
        }
        if (items.size == lastRenderedCount) {
            if (firstId != lastFirstId || lastId != lastLastId) {
                adapter.clear()
                items.forEach { adapter.add(it) }
                lastRenderedCount = items.size
                lastFirstId = firstId
                lastLastId = lastId
            }
            return
        }
        for (i in lastRenderedCount until items.size) {
            adapter.add(items[i])
        }
        lastRenderedCount = items.size
        lastFirstId = firstId
        lastLastId = lastId
    }

    fun openOptionsFromActivity() {
        val s = lastState ?: return
        val activity = activity ?: return
        val paths = s.availablePaths.map { it.path }.filter { it.isNotBlank() }
        MusicOptionsDialogFragment
            .newInstance(
                currentSearch = s.searchText,
                sortBy = s.sort.by.name,
                sortOrder = s.sort.order.name,
                availablePaths = ArrayList(paths),
                selectedPaths = ArrayList(s.selectedPaths.toList()),
            )
            .show(activity.supportFragmentManager, "music_options")
    }

    private fun openFolder(item: MusicListItem) {
        val id = item.id
        if (id <= 0) return
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.beginTransaction()
            .replace(
                R.id.main_container,
                newInstance(
                    title = item.displayTitle.ifEmpty { getString(R.string.music_item_type_folder) },
                    seriesIndexId = id,
                ),
            )
            .addToBackStack(null)
            .commit()
    }

    private fun startPlaybackFromCurrentList(startItem: MusicListItem) {
        val state = lastState ?: return
        val playable = state.items.filterNot { it.isFolder }
        if (playable.isEmpty()) return
        val startIndex = playable.indexOfFirst { it.id == startItem.id }.coerceAtLeast(0)
        val ctx = context ?: return
        MusicPlaybackService.startPlaylist(
            context = ctx,
            playlist = playable,
            startIndex = startIndex,
        )
        startActivity(MusicNowPlayingActivity.newIntent(ctx))
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
        val sort: MusicListSortState,
        val sources: Set<String>,
    )

    class Factory(
        private val app: Application,
        private val title: String,
        private val isFavorite: Boolean,
        private val listType: String? = null,
        private val listId: Int? = null,
        private val seriesIndexId: Int? = null,
        private val artists: List<String>? = null,
        private val albums: List<String>? = null,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(MusicTrackListViewModel::class.java)) {
                return MusicTrackListViewModel(
                    app,
                    titleText = title,
                    isFavoriteList = isFavorite,
                    listType = listType,
                    listId = listId,
                    seriesIndexId = seriesIndexId,
                    artists = artists,
                    albums = albums,
                ) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        private const val ARG_TITLE = "title"
        private const val ARG_IS_FAVORITE = "is_favorite"
        private const val ARG_SERIES_INDEX_ID = "series_index_id"
        private const val ARG_LIST_TYPE = "list_type"
        private const val ARG_LIST_ID = "list_id"
        private const val ARG_ARTISTS = "artists"
        private const val ARG_ALBUMS = "albums"

        const val RESULT_KEY_SEARCH = "music_list_result_search"
        const val RESULT_KEY_SORT = "music_list_result_sort"
        const val RESULT_KEY_SOURCES = "music_list_result_sources"
        const val RESULT_FIELD_QUERY = "query"
        const val RESULT_FIELD_SORT_BY = "sort_by"
        const val RESULT_FIELD_SORT_ORDER = "sort_order"
        const val RESULT_FIELD_SOURCES = "sources"

        fun newInstance(
            title: String,
            isFavorite: Boolean = false,
            seriesIndexId: Int? = null,
            listType: String? = null,
            listId: Int? = null,
            artists: List<String>? = null,
            albums: List<String>? = null,
        ): MusicTrackGridFragment {
            return MusicTrackGridFragment().apply {
                arguments =
                    bundleOf(
                        ARG_TITLE to title.trim(),
                        ARG_IS_FAVORITE to isFavorite,
                        ARG_SERIES_INDEX_ID to (seriesIndexId ?: 0),
                        ARG_LIST_TYPE to (listType?.trim().orEmpty()),
                        ARG_LIST_ID to (listId ?: 0),
                        ARG_ARTISTS to ArrayList(artists.orEmpty()),
                        ARG_ALBUMS to ArrayList(albums.orEmpty()),
                    )
            }
        }
    }
}
