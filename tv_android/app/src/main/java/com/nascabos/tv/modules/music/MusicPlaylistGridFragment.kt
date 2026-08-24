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
import com.nascabos.tv.R
import com.nascabos.tv.modules.music.presenter.MusicPlaylistCardPresenter
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MusicPlaylistGridFragment : VerticalGridSupportFragment() {
    private val viewModel: MusicPlaylistListViewModel by viewModels {
        Factory(
            requireActivity().application,
            title = getString(R.string.home_music_playlists),
        )
    }

    private val adapter by lazy { ArrayObjectAdapter(MusicPlaylistCardPresenter(requireContext())) }
    private var lastRenderedCount: Int = 0
    private var lastRenderKey: RenderKey? = null
    private var lastFirstId: Long = 0L
    private var lastLastId: Long = 0L
    private var headerAdded: Boolean = false
    private var loadingView: ProgressBar? = null
    private var lastState: MusicPlaylistUiState? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SEARCH, this) { _, bundle ->
            val q = bundle.getString(RESULT_FIELD_QUERY)?.trim().orEmpty()
            if (q.isEmpty()) viewModel.clearSearch() else viewModel.setSearch(q)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SORT, this) { _, bundle ->
            val byRaw = bundle.getString(RESULT_FIELD_SORT_BY)?.trim().orEmpty()
            val orderRaw = bundle.getString(RESULT_FIELD_SORT_ORDER)?.trim().orEmpty()
            val by = runCatching { MusicPlaylistSortBy.valueOf(byRaw) }.getOrNull()
            val order = runCatching { MusicPlaylistSortOrder.valueOf(orderRaw) }.getOrNull()
            if (by != null && order != null) {
                viewModel.setSort(MusicPlaylistSortState(by = by, order = order))
            }
        }

        title = getString(R.string.home_music_playlists)

        val columns = computeColumns()
        val gridPresenter =
            VerticalGridPresenter(FocusHighlight.ZOOM_FACTOR_MEDIUM, false).apply {
                numberOfColumns = columns
            }
        setGridPresenter(gridPresenter)
        setAdapter(adapter)

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                val playlist = item as? MusicPlaylistItem ?: return@OnItemViewClickedListener
                openPlaylist(playlist)
            }

        setOnItemViewSelectedListener { _, item, _, _ ->
            val size = adapter.size()
            if (size <= 0) return@setOnItemViewSelectedListener
            val position = if (item == null) -1 else adapter.indexOf(item)
            if (position >= size - 6) viewModel.loadMore()
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
            runCatching { grid.setItemSpacing(dpToPx(16f)) }
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

    private fun renderState(state: MusicPlaylistUiState) {
        loadingView?.visibility = if (state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
        val items = state.items
        val key = RenderKey(search = state.searchText, sort = state.sort)
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
        MusicPlaylistOptionsDialogFragment
            .newInstance(
                currentSearch = s.searchText,
                sortBy = s.sort.by.name,
                sortOrder = s.sort.order.name,
            )
            .show(activity.supportFragmentManager, "music_playlist_options")
    }

    private fun openPlaylist(playlist: MusicPlaylistItem) {
        val id = playlist.id
        if (id <= 0) return
        val name = playlist.name.trim().ifEmpty { getString(R.string.home_music_playlists) }
        activity?.supportFragmentManager
            ?.beginTransaction()
            ?.replace(
                R.id.main_container,
                MusicTrackGridFragment.newInstance(
                    title = name,
                    listType = "playlist",
                    listId = id,
                ),
            )
            ?.addToBackStack(null)
            ?.commit()
    }

    private fun computeColumns(): Int {
        val widthPx = resources.displayMetrics.widthPixels.coerceAtLeast(1)
        val cardW = dpToPx(200f)
        val spacing = dpToPx(16f)
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
        val sort: MusicPlaylistSortState,
    )

    class Factory(
        private val app: Application,
        private val title: String,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(MusicPlaylistListViewModel::class.java)) {
                return MusicPlaylistListViewModel(
                    app,
                    titleText = title,
                ) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }

    companion object {
        const val RESULT_KEY_SEARCH = "music_playlist_result_search"
        const val RESULT_KEY_SORT = "music_playlist_result_sort"
        const val RESULT_FIELD_QUERY = "query"
        const val RESULT_FIELD_SORT_BY = "sort_by"
        const val RESULT_FIELD_SORT_ORDER = "sort_order"

        fun newInstance(): MusicPlaylistGridFragment {
            return MusicPlaylistGridFragment().apply { arguments = bundleOf() }
        }
    }
}
