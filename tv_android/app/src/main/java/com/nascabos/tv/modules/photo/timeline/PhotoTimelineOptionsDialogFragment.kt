package com.nascabos.tv.modules.photo.timeline

import android.app.Dialog
import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.TextView
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import com.nascabos.tv.R

class PhotoTimelineOptionsDialogFragment : DialogFragment() {
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val fileType: String by lazy { requireArguments().getString(ARG_FILE_TYPE).orEmpty() }
    private val monthKey: String by lazy { requireArguments().getString(ARG_MONTH_KEY).orEmpty() }
    private val monthOptions: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_MONTH_OPTIONS) ?: arrayListOf() }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }

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
                ID_FILE_TYPE -> {
                    dismissAllowingStateLoss()
                    PhotoTimelineFileTypeDialogFragment
                        .newInstance(currentFileType = fileType)
                        .show(parentFragmentManager, "photo_timeline_file_type")
                }
                ID_MONTH -> {
                    dismissAllowingStateLoss()
                    PhotoTimelineMonthDialogFragment
                        .newInstance(currentMonthKey = monthKey, monthOptions = monthOptions)
                        .show(parentFragmentManager, "photo_timeline_month")
                }
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    PhotoTimelineSortDialogFragment
                        .newInstance(currentSortOrder = sortOrder)
                        .show(parentFragmentManager, "photo_timeline_sort")
                }
                ID_SOURCES -> {
                    dismissAllowingStateLoss()
                    PhotoTimelineSourceDialogFragment
                        .newInstance(
                            availablePaths = availablePaths,
                            selectedPaths = selectedPaths,
                        )
                        .show(parentFragmentManager, "photo_timeline_sources")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(PhotoTimelineBrowseFragment.RESULT_KEY_CLEAR, bundleOf())
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun buildRows(): List<Row> {
        val sortLabel = sortLabel(sortOrder)
        val typeLabel = fileTypeLabel(fileType)
        val monthLabel = monthLabel(monthKey)
        val sourcesLabel =
            if (selectedPaths.isEmpty()) {
                getString(R.string.photo_timeline_sources_all)
            } else {
                getString(R.string.photo_timeline_sources_selected_count, selectedPaths.size)
            }

        val hasFilters =
            selectedPaths.isNotEmpty() ||
                monthKey.trim().isNotEmpty() ||
                runCatching { PhotoTimelineFileType.valueOf(fileType) }.getOrNull() != PhotoTimelineFileType.All ||
                runCatching { PhotoTimelineSortOrder.valueOf(sortOrder) }.getOrNull() != PhotoTimelineSortOrder.Desc

        val list = mutableListOf<Row>()
        list += Row(ID_FILE_TYPE, getString(R.string.photo_timeline_action_type), typeLabel)
        list += Row(ID_MONTH, getString(R.string.photo_timeline_action_month), monthLabel)
        list += Row(ID_SORT, getString(R.string.photo_timeline_action_sort), sortLabel)
        list += Row(ID_SOURCES, getString(R.string.photo_timeline_action_sources), sourcesLabel)
        if (hasFilters) {
            list += Row(ID_CLEAR, getString(R.string.photo_timeline_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun sortLabel(orderRaw: String): String {
        val order = runCatching { PhotoTimelineSortOrder.valueOf(orderRaw) }.getOrNull() ?: PhotoTimelineSortOrder.Desc
        return when (order) {
            PhotoTimelineSortOrder.Asc -> getString(R.string.photo_timeline_sort_asc)
            PhotoTimelineSortOrder.Desc -> getString(R.string.photo_timeline_sort_desc)
        }
    }

    private fun fileTypeLabel(typeRaw: String): String {
        val type = runCatching { PhotoTimelineFileType.valueOf(typeRaw) }.getOrNull() ?: PhotoTimelineFileType.All
        return when (type) {
            PhotoTimelineFileType.All -> getString(R.string.photo_timeline_file_type_all)
            PhotoTimelineFileType.Image -> getString(R.string.photo_timeline_file_type_image)
            PhotoTimelineFileType.Video -> getString(R.string.photo_timeline_file_type_video)
        }
    }

    private fun monthLabel(monthKey: String): String {
        val mk = monthKey.trim()
        if (mk.isEmpty()) return getString(R.string.photo_timeline_month_all)
        return mk
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_FILE_TYPE = "file_type"
        private const val ARG_MONTH_KEY = "month_key"
        private const val ARG_MONTH_OPTIONS = "month_options"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        private const val ID_FILE_TYPE = 1
        private const val ID_MONTH = 2
        private const val ID_SORT = 3
        private const val ID_SOURCES = 4
        private const val ID_CLEAR = 5
        private const val ID_CLOSE = 6

        fun newInstance(
            sortOrder: String,
            fileType: String,
            monthKey: String,
            monthOptions: ArrayList<String>,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
        ): PhotoTimelineOptionsDialogFragment {
            return PhotoTimelineOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_SORT_ORDER to sortOrder,
                        ARG_FILE_TYPE to fileType,
                        ARG_MONTH_KEY to monthKey,
                        ARG_MONTH_OPTIONS to monthOptions,
                        ARG_AVAILABLE_PATHS to availablePaths,
                        ARG_SELECTED_PATHS to selectedPaths,
                    )
            }
        }
    }
}

