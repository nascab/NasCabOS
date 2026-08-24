package com.nascabos.tv.modules.video

import android.app.Dialog
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import com.nascabos.tv.R

class VideoOptionsDialogFragment : DialogFragment() {
    private val mediaType: String by lazy { requireArguments().getString(ARG_MEDIA_TYPE).orEmpty() }
    private val listType: String by lazy { requireArguments().getString(ARG_LIST_TYPE).orEmpty() }
    private val currentSearch: String by lazy { requireArguments().getString(ARG_CURRENT_SEARCH).orEmpty() }
    private val sortBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }
    private val enableMediaTypeFilter: Boolean by lazy { requireArguments().getBoolean(ARG_ENABLE_MEDIA_TYPE_FILTER, false) }
    private val currentMediaTypeFilter: String by lazy { requireArguments().getString(ARG_CURRENT_MEDIA_TYPE_FILTER).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(420f)
        val panel =
            FrameLayout(ctx).apply {
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val listView =
            ListView(ctx).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                dividerHeight = 0
                selector = resources.getDrawable(R.drawable.video_dialog_selector, ctx.theme)
            }
        panel.addView(listView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val rows = buildRows()
        val adapter =
            object : ArrayAdapter<Row>(ctx, android.R.layout.simple_list_item_2, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t1 = v.findViewById<TextView>(android.R.id.text1)
                    val t2 = v.findViewById<TextView>(android.R.id.text2)
                    val row = getItem(position)
                    t1.text = row?.title.orEmpty()
                    t2.text = row?.desc.orEmpty()
                    t2.visibility = if (row?.desc?.isNotBlank() == true) View.VISIBLE else View.GONE
                    t1.setTextColor(0xFFFFFFFF.toInt())
                    t2.setTextColor(0xB3FFFFFF.toInt())
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)
        listView.setOnItemClickListener { _, _, position, _ ->
            when (rows.getOrNull(position)?.id) {
                ID_SEARCH -> openSearchInput()
                ID_MEDIA_TYPE -> {
                    dismissAllowingStateLoss()
                    VideoMediaTypeDialogFragment
                        .newInstance(currentMediaTypeFilter)
                        .show(parentFragmentManager, "video_media_type")
                }
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    VideoSortDialogFragment.newInstance(sortBy, sortOrder, listType = listType).show(parentFragmentManager, "video_sort")
                }
                ID_SOURCES -> {
                    dismissAllowingStateLoss()
                    VideoSourceDialogFragment
                        .newInstance(
                            availablePaths = availablePaths,
                            selectedPaths = selectedPaths,
                        )
                        .show(parentFragmentManager, "video_sources")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(VideoGridFragment.RESULT_KEY_SEARCH, bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to ""))
                    parentFragmentManager.setFragmentResult(VideoGridFragment.RESULT_KEY_SOURCES, bundleOf(VideoGridFragment.RESULT_FIELD_SOURCES to arrayListOf<String>()))
                    if (enableMediaTypeFilter) {
                        parentFragmentManager.setFragmentResult(
                            VideoGridFragment.RESULT_KEY_MEDIA_TYPE_FILTER,
                            bundleOf(VideoGridFragment.RESULT_FIELD_MEDIA_TYPE_FILTER to "all"),
                        )
                    }
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun openSearchInput() {
        val ctx = requireContext()
        val input =
            EditText(ctx).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setText(currentSearch)
                setSelection(text?.length ?: 0)
                setTextColor(0xFFFFFFFF.toInt())
                setHintTextColor(0x99FFFFFF.toInt())
                setBackgroundColor(0xFF2A2A2A.toInt())
                setPadding(dpToPx(12f), dpToPx(10f), dpToPx(12f), dpToPx(10f))
            }
        AlertDialog.Builder(ctx, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.video_list_action_search))
            .setView(input)
            .setPositiveButton(getString(R.string.video_list_action_apply)) { _, _ ->
                val q = input.text?.toString()?.trim().orEmpty()
                parentFragmentManager.setFragmentResult(
                    VideoGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to q),
                )
                dismissAllowingStateLoss()
            }
            .setNeutralButton(getString(R.string.video_list_action_clear_search)) { _, _ ->
                parentFragmentManager.setFragmentResult(
                    VideoGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to ""),
                )
                dismissAllowingStateLoss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun buildRows(): List<Row> {
        val sortLabel = sortLabel(sortBy, sortOrder)
        val sourcesLabel =
            if (selectedPaths.isEmpty()) {
                getString(R.string.video_list_sources_all)
            } else {
                getString(R.string.video_list_sources_selected_count, selectedPaths.size)
            }
        val list = mutableListOf<Row>()
        list += Row(ID_SEARCH, getString(R.string.video_list_action_search), currentSearch.ifEmpty { getString(R.string.video_list_search_empty) })
        if (enableMediaTypeFilter) {
            list += Row(ID_MEDIA_TYPE, getString(R.string.video_list_action_media_type), mediaTypeLabel(currentMediaTypeFilter))
        }
        list += Row(ID_SORT, getString(R.string.video_list_action_sort), sortLabel)
        list += Row(ID_SOURCES, getString(R.string.video_list_action_sources), sourcesLabel)
        if (currentSearch.isNotBlank() || selectedPaths.isNotEmpty() || (enableMediaTypeFilter && currentMediaTypeFilter.trim().lowercase() != "all")) {
            list += Row(ID_CLEAR, getString(R.string.video_list_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun sortLabel(byRaw: String, orderRaw: String): String {
        val by = runCatching { VideoListSortBy.valueOf(byRaw) }.getOrNull() ?: VideoListSortBy.ViewTime
        val order = runCatching { VideoListSortOrder.valueOf(orderRaw) }.getOrNull() ?: VideoListSortOrder.Desc
        return when (by) {
            VideoListSortBy.ViewTime ->
                if (order == VideoListSortOrder.Desc) getString(R.string.video_list_sort_view_time_desc) else getString(R.string.video_list_sort_view_time_asc)
            VideoListSortBy.CreateTime ->
                if (listType.trim().lowercase() == "favorite") {
                    if (order == VideoListSortOrder.Desc) getString(R.string.video_list_sort_favorite_time_desc) else getString(R.string.video_list_sort_favorite_time_asc)
                } else {
                    if (order == VideoListSortOrder.Desc) getString(R.string.video_list_sort_create_time_desc) else getString(R.string.video_list_sort_create_time_asc)
                }
            VideoListSortBy.Year ->
                if (order == VideoListSortOrder.Desc) getString(R.string.video_list_sort_year_desc) else getString(R.string.video_list_sort_year_asc)
            VideoListSortBy.Score ->
                if (order == VideoListSortOrder.Desc) getString(R.string.video_list_sort_score_desc) else getString(R.string.video_list_sort_score_asc)
            VideoListSortBy.Name ->
                if (order == VideoListSortOrder.Asc) getString(R.string.video_list_sort_name_asc) else getString(R.string.video_list_sort_name_desc)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private fun mediaTypeLabel(value: String): String {
        return when (value.trim().lowercase()) {
            "movie" -> getString(R.string.video_list_media_type_movie)
            "tv" -> getString(R.string.video_list_media_type_tv)
            else -> getString(R.string.video_list_media_type_all)
        }
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_MEDIA_TYPE = "media_type"
        private const val ARG_LIST_TYPE = "list_type"
        private const val ARG_CURRENT_SEARCH = "current_search"
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"
        private const val ARG_ENABLE_MEDIA_TYPE_FILTER = "enable_media_type_filter"
        private const val ARG_CURRENT_MEDIA_TYPE_FILTER = "current_media_type_filter"

        private const val ID_SEARCH = 1
        private const val ID_MEDIA_TYPE = 2
        private const val ID_SORT = 3
        private const val ID_SOURCES = 4
        private const val ID_CLEAR = 5
        private const val ID_CLOSE = 6

        fun newInstance(
            mediaType: String,
            listType: String,
            currentSearch: String,
            sortBy: String,
            sortOrder: String,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
            currentMediaTypeFilter: String,
            enableMediaTypeFilter: Boolean,
        ): VideoOptionsDialogFragment {
            return VideoOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_MEDIA_TYPE to mediaType,
                        ARG_LIST_TYPE to listType,
                        ARG_CURRENT_SEARCH to currentSearch,
                        ARG_SORT_BY to sortBy,
                        ARG_SORT_ORDER to sortOrder,
                        ARG_AVAILABLE_PATHS to availablePaths,
                        ARG_SELECTED_PATHS to selectedPaths,
                        ARG_CURRENT_MEDIA_TYPE_FILTER to currentMediaTypeFilter,
                        ARG_ENABLE_MEDIA_TYPE_FILTER to enableMediaTypeFilter,
                    )
            }
        }
    }
}
