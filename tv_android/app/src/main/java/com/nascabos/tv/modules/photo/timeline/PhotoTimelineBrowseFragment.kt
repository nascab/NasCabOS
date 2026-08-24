package com.nascabos.tv.modules.photo.timeline

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.app.Application
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.core.os.bundleOf
import androidx.fragment.app.viewModels
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.Presenter
import androidx.leanback.widget.VerticalGridView
import androidx.leanback.widget.FocusHighlight
import androidx.leanback.widget.VerticalGridPresenter
import androidx.leanback.app.VerticalGridSupportFragment
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.util.Locale

class PhotoTimelineBrowseFragment : VerticalGridSupportFragment() {
    private val customTitle: String by lazy { arguments?.getString(ARG_TITLE)?.trim().orEmpty() }
    private val albumId: Int by lazy { arguments?.getInt(ARG_ALBUM_ID, 0) ?: 0 }
    private val collectionId: Int by lazy { arguments?.getInt(ARG_COLLECTION_ID, 0) ?: 0 }
    private val smartAlbumId: Int by lazy { arguments?.getInt(ARG_SMART_ALBUM_ID, 0) ?: 0 }
    private val listType: String by lazy { arguments?.getString(ARG_LIST_TYPE)?.trim().orEmpty() }
    private val loadTheDay: Boolean by lazy { arguments?.getBoolean(ARG_LOAD_THE_DAY, false) ?: false }

    private val viewModel: PhotoTimelineViewModel by viewModels {
        Factory(requireActivity().application, albumId, collectionId, smartAlbumId, listType, loadTheDay)
    }

    private val itemSizeDp: Float = 154f
    private val itemSpacingDp: Float = 16f

    private var rootView: View? = null
    private var headerTextView: TextView? = null
    private var focusTimeView: TextView? = null
    private var loadingView: ProgressBar? = null
    private var loadingMoreView: ProgressBar? = null
    private var emptyView: TextView? = null

    private val adapter by lazy { ArrayObjectAdapter(PhotoTimelineCardPresenter()) }
    private var lastRenderedCount: Int = 0
    private var lastItemsSignature: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = customTitle.ifEmpty { getString(R.string.home_photo_timeline) }
        val columns = computeColumns()
        val gridPresenter =
            VerticalGridPresenter(FocusHighlight.ZOOM_FACTOR_MEDIUM, false).apply {
                numberOfColumns = columns
            }
        setGridPresenter(gridPresenter)
        setAdapter(adapter)

        onItemViewClickedListener =
            OnItemViewClickedListener { _, item, _, _ ->
                val photo = item as? PhotoTimelinePhotoItem ?: return@OnItemViewClickedListener
                val idx = adapter.indexOf(photo).takeIf { it >= 0 } ?: 0
                openPreview(idx)
            }

        setOnItemViewSelectedListener { _, item, _, _ ->
            val photo = item as? PhotoTimelinePhotoItem
            updateFocusTime(photo)
            val size = adapter.size()
            if (size <= 0) return@setOnItemViewSelectedListener
            val position = if (item == null) -1 else adapter.indexOf(item)
            if (position >= size - 8) viewModel.loadMore()
        }

        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SORT, this) { _, bundle ->
            val raw = bundle.getString(RESULT_FIELD_SORT_ORDER).orEmpty()
            val order = runCatching { PhotoTimelineSortOrder.valueOf(raw) }.getOrNull() ?: return@setFragmentResultListener
            viewModel.setSortOrder(order)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_FILE_TYPE, this) { _, bundle ->
            val raw = bundle.getString(RESULT_FIELD_FILE_TYPE).orEmpty()
            val type = runCatching { PhotoTimelineFileType.valueOf(raw) }.getOrNull() ?: return@setFragmentResultListener
            viewModel.setFileType(type)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_SOURCES, this) { _, bundle ->
            val list = bundle.getStringArrayList(RESULT_FIELD_SOURCES) ?: arrayListOf()
            val set = list.map { it.trim() }.filter { it.isNotEmpty() }.toSet()
            viewModel.setSelectedPaths(set)
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_MONTH, this) { _, bundle ->
            val monthKey = bundle.getString(RESULT_FIELD_MONTH_KEY)?.trim().orEmpty()
            viewModel.setMonthKey(monthKey.ifEmpty { null })
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_CLEAR, this) { _, _ ->
            viewModel.clearFilters()
        }
        parentFragmentManager.setFragmentResultListener(RESULT_KEY_REFRESH, this) { _, _ ->
            viewModel.refresh(showLoading = true)
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        rootView = view
        val root = view as? ViewGroup ?: return

        val grid = findVerticalGridView(view)
        if (grid != null) {
            val side = dpToPx(28f)
            val top = dpToPx(86f)
            val bottom = dpToPx(28f)
            grid.setPadding(side, top, side, bottom)
            grid.clipToPadding = false
            runCatching { grid.setItemSpacing(dpToPx(itemSpacingDp)) }
        }

        val header =
            TextView(requireContext()).apply {
                text = customTitle.ifEmpty { getString(R.string.home_photo_timeline) }
                setTextColor(Color.parseColor("#E6FFFFFF"))
                textSize = 22f
                setTypeface(typeface, Typeface.BOLD)
                isFocusable = false
                isFocusableInTouchMode = false
            }
        val headerLp =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.START or Gravity.TOP
                leftMargin = dpToPx(28f)
                topMargin = dpToPx(20f)
            }
        root.addView(header, headerLp)
        headerTextView = header

        val focusTime =
            TextView(requireContext()).apply {
                setTextColor(Color.parseColor("#B3FFFFFF"))
                textSize = 14f
                isFocusable = false
                isFocusableInTouchMode = false
            }
        val focusTimeLp =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.START or Gravity.TOP
                leftMargin = dpToPx(28f)
                topMargin = dpToPx(48f)
            }
        root.addView(focusTime, focusTimeLp)
        focusTimeView = focusTime

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

        val more =
            ProgressBar(requireContext()).apply {
                isIndeterminate = true
                visibility = View.GONE
            }
        val moreLp =
            FrameLayout.LayoutParams(
                dpToPx(40f),
                dpToPx(40f),
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dpToPx(20f)
            }
        root.addView(more, moreLp)
        loadingMoreView = more

        val empty =
            TextView(requireContext()).apply {
                text = getString(R.string.common_no_data)
                setTextColor(Color.parseColor("#B3FFFFFF"))
                textSize = 18f
                visibility = View.GONE
                isFocusable = false
                isFocusableInTouchMode = false
            }
        val emptyLp =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.CENTER
            }
        root.addView(empty, emptyLp)
        emptyView = empty

        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.state.collectLatest { state ->
                loadingView?.visibility = if (state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
                loadingMoreView?.visibility = if (state.loadingMore) View.VISIBLE else View.GONE
                emptyView?.visibility = if (!state.loading && state.items.isEmpty()) View.VISIBLE else View.GONE
                renderItems(state.items)
            }
        }
    }

    fun openOptionsFromActivity() {
        openOptions()
    }

    private fun openOptions() {
        val s = viewModel.state.value
        val availablePaths = ArrayList(s.validPaths.map { it.path }.filter { it.isNotEmpty() })
        val selectedPaths = ArrayList(s.selectedPaths.toList())
        PhotoTimelineOptionsDialogFragment
            .newInstance(
                sortOrder = s.sortOrder.name,
                fileType = s.fileType.name,
                monthKey = s.monthKey.orEmpty(),
                monthOptions = ArrayList(s.monthOptions),
                availablePaths = availablePaths,
                selectedPaths = selectedPaths,
            )
            .show(parentFragmentManager, "photo_timeline_options")
    }

    private fun renderItems(items: List<PhotoTimelinePhotoItem>) {
        val sig = itemsSignature(items)
        if (sig == lastItemsSignature && adapter.size() == lastRenderedCount) return
        lastItemsSignature = sig
        if (items.isEmpty()) {
            adapter.clear()
            lastRenderedCount = 0
            updateFocusTime(null)
            return
        }
        if (items.size < lastRenderedCount || lastRenderedCount == 0) {
            adapter.clear()
            items.forEach { adapter.add(it) }
            lastRenderedCount = items.size
            return
        }
        for (i in lastRenderedCount until items.size) {
            adapter.add(items[i])
        }
        lastRenderedCount = items.size
    }

    private fun openPreview(initialIndex: Int) {
        val items = viewModel.state.value.items
        if (items.isEmpty()) return
        val idx = initialIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0))
        startActivity(PhotoPreviewActivity.newIntent(requireContext(), items, idx))
    }

    private fun itemsSignature(items: List<PhotoTimelinePhotoItem>): Long {
        var h = 1469598103934665603L
        for (i in 0 until items.size) {
            h = h xor items[i].id.toLong()
            h *= 1099511628211L
        }
        h = h xor items.size.toLong()
        h *= 1099511628211L
        return h
    }

    private fun openPlaceholder(photo: PhotoTimelinePhotoItem) {
        if (!isAdded) return
        val title = photo.filename.ifEmpty { photo.fullPath.ifEmpty { getString(R.string.home_photo_timeline) } }
        val message =
            buildString {
                val d = photo.originalDate.trim()
                val t = photo.originalTime.trim()
                if (d.isNotEmpty()) append(d)
                if (t.isNotEmpty()) {
                    if (isNotEmpty()) append(' ')
                    append(t)
                }
                val p = photo.fullPath.trim()
                if (p.isNotEmpty()) {
                    if (isNotEmpty()) append('\n')
                    append(p)
                }
            }.ifEmpty { photo.fullPath.ifEmpty { photo.path.ifEmpty { photo.filename } } }
        AlertDialog.Builder(requireContext(), R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(getString(R.string.action_ok), null)
            .show()
    }

    private fun dpToPx(dp: Float): Int = (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)

    private inner class PhotoTimelineCardPresenter : Presenter() {
        override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
            val ctx = parent.context
            val container =
                FrameLayout(ctx).apply {
                    isFocusable = true
                    isFocusableInTouchMode = true
                    val bg =
                        GradientDrawable().apply {
                            cornerRadius = dpToPx(12f).toFloat()
                            setColor(Color.parseColor("#1E1E1E"))
                        }
                    background = bg
                    clipToOutline = true
                    layoutParams =
                        ViewGroup.LayoutParams(
                            dpToPx(itemSizeDp),
                            dpToPx(itemSizeDp),
                        )
                }
            val iv =
                ImageView(ctx).apply {
                    scaleType = ImageView.ScaleType.CENTER_CROP
                    setBackgroundColor(Color.parseColor("#2C2C2C"))
                }
            container.addView(
                iv,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            val badge =
                TextView(ctx).apply {
                    setTextColor(Color.WHITE)
                    textSize = 11f
                    setPadding(dpToPx(6f), dpToPx(2f), dpToPx(6f), dpToPx(2f))
                    background =
                        GradientDrawable().apply {
                            cornerRadius = dpToPx(8f).toFloat()
                            setColor(Color.parseColor("#80000000"))
                        }
                    visibility = View.GONE
                    isFocusable = false
                }
            container.addView(
                badge,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    gravity = Gravity.END or Gravity.BOTTOM
                    rightMargin = dpToPx(6f)
                    bottomMargin = dpToPx(6f)
                },
            )
            return ViewHolder(container)
        }

        override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
            val data = item as? PhotoTimelinePhotoItem ?: return
            val root = viewHolder.view as FrameLayout
            val iv = root.getChildAt(0) as? ImageView ?: return
            val badge = root.getChildAt(1) as? TextView
            val p = data.fullPath.ifEmpty { data.path }
            TvImageLoader.loadTinyInto(
                imageView = iv,
                filePath = p,
                size = 480,
                placeholderResId = R.drawable.ic_photo,
                showPlaceholderWhileLoading = true,
                onDone = null,
            )
            val showBadge = data.duration > 0
            if (showBadge) {
                badge?.visibility = View.VISIBLE
                badge?.text = formatDuration(data.duration)
            } else {
                badge?.visibility = View.GONE
            }
        }

        override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
    }

    private fun formatDuration(seconds: Int): String {
        val s = seconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) {
            String.format(Locale.US, "%d:%02d:%02d", h, m, sec)
        } else {
            String.format(Locale.US, "%d:%02d", m, sec)
        }
    }

    private fun findVerticalGridView(view: View): VerticalGridView? {
        if (view is VerticalGridView) return view
        if (view !is ViewGroup) return null
        for (i in 0 until view.childCount) {
            val found = findVerticalGridView(view.getChildAt(i))
            if (found != null) return found
        }
        return null
    }

    private fun computeColumns(): Int {
        val wPx = resources.displayMetrics.widthPixels
        val side = dpToPx(28f) * 2
        val spacing = dpToPx(itemSpacingDp)
        val item = dpToPx(itemSizeDp)
        val available = (wPx - side).coerceAtLeast(item)
        val cols = (available + spacing) / (item + spacing)
        return cols.coerceIn(3, 8).coerceAtLeast(1)
    }

    private fun updateFocusTime(photo: PhotoTimelinePhotoItem?) {
        val d = photo?.originalDate?.trim().orEmpty()
        focusTimeView?.text =
            when {
                d.isNotEmpty() -> d
                else -> ""
            }
    }

    companion object {
        private const val ARG_TITLE = "title"
        private const val ARG_ALBUM_ID = "album_id"
        private const val ARG_COLLECTION_ID = "collection_id"
        private const val ARG_SMART_ALBUM_ID = "smart_album_id"
        private const val ARG_LIST_TYPE = "list_type"
        private const val ARG_LOAD_THE_DAY = "load_the_day"

        const val RESULT_KEY_SORT = "photo_timeline_sort"
        const val RESULT_FIELD_SORT_ORDER = "sort_order"

        const val RESULT_KEY_FILE_TYPE = "photo_timeline_file_type"
        const val RESULT_FIELD_FILE_TYPE = "file_type"

        const val RESULT_KEY_SOURCES = "photo_timeline_sources"
        const val RESULT_FIELD_SOURCES = "sources"

        const val RESULT_KEY_MONTH = "photo_timeline_month"
        const val RESULT_FIELD_MONTH_KEY = "month_key"

        const val RESULT_KEY_CLEAR = "photo_timeline_clear"
        const val RESULT_KEY_REFRESH = "photo_timeline_refresh"

        fun newInstance(
            title: String? = null,
            albumId: Int? = null,
            collectionId: Int? = null,
            smartAlbumId: Int? = null,
            listType: String? = null,
            loadTheDay: Boolean = false,
        ): PhotoTimelineBrowseFragment {
            return PhotoTimelineBrowseFragment().apply {
                arguments =
                    Bundle().apply {
                        val t = title?.trim().orEmpty()
                        if (t.isNotEmpty()) putString(ARG_TITLE, t)
                        val aid = albumId ?: 0
                        val cid = collectionId ?: 0
                        val sid = smartAlbumId ?: 0
                        if (aid > 0) putInt(ARG_ALBUM_ID, aid)
                        if (cid > 0) putInt(ARG_COLLECTION_ID, cid)
                        if (sid > 0) putInt(ARG_SMART_ALBUM_ID, sid)
                        val lt = listType?.trim().orEmpty()
                        if (lt.isNotEmpty()) putString(ARG_LIST_TYPE, lt)
                        if (loadTheDay) putBoolean(ARG_LOAD_THE_DAY, true)
                    }
            }
        }
    }

    class Factory(
        private val app: Application,
        private val albumId: Int,
        private val collectionId: Int,
        private val smartAlbumId: Int,
        private val listType: String,
        private val loadTheDay: Boolean,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(PhotoTimelineViewModel::class.java)) {
                return PhotoTimelineViewModel(
                    app = app,
                    albumId = albumId,
                    collectionId = collectionId,
                    smartAlbumId = smartAlbumId,
                    listType = listType.trim().ifEmpty { null },
                    loadTheDay = loadTheDay,
                ) as T
            }
            throw IllegalArgumentException("unknown_viewmodel")
        }
    }
}
