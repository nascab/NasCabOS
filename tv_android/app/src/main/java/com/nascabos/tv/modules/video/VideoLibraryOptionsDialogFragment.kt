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

class VideoLibraryOptionsDialogFragment : DialogFragment() {
    private val kind: String by lazy { requireArguments().getString(ARG_KIND).orEmpty() }
    private val currentKeyword: String by lazy { requireArguments().getString(ARG_CURRENT_KEYWORD).orEmpty() }
    private val sortField: String by lazy { requireArguments().getString(ARG_SORT_FIELD).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

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
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    VideoLibrarySortDialogFragment.newInstance(sortField, sortOrder).show(parentFragmentManager, "video_library_sort")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(VideoLibraryGridFragment.RESULT_KEY_SEARCH, bundleOf(VideoLibraryGridFragment.RESULT_FIELD_QUERY to ""))
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
                setText(currentKeyword)
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
                    VideoLibraryGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoLibraryGridFragment.RESULT_FIELD_QUERY to q),
                )
                dismissAllowingStateLoss()
            }
            .setNeutralButton(getString(R.string.video_list_action_clear_search)) { _, _ ->
                parentFragmentManager.setFragmentResult(
                    VideoLibraryGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoLibraryGridFragment.RESULT_FIELD_QUERY to ""),
                )
                dismissAllowingStateLoss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun buildRows(): List<Row> {
        val sortLabel = sortLabel(sortField, sortOrder)
        val list = mutableListOf<Row>()
        list += Row(ID_SEARCH, getString(R.string.video_list_action_search), currentKeyword.ifEmpty { getString(R.string.video_list_search_empty) })
        list += Row(ID_SORT, getString(R.string.video_list_action_sort), sortLabel)
        if (currentKeyword.isNotBlank()) {
            list += Row(ID_CLEAR, getString(R.string.video_list_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun sortLabel(fieldRaw: String, orderRaw: String): String {
        val field = runCatching { VideoLibrarySortField.valueOf(fieldRaw) }.getOrNull() ?: VideoLibrarySortField.CreateTime
        val order = runCatching { VideoLibrarySortOrder.valueOf(orderRaw) }.getOrNull() ?: VideoLibrarySortOrder.Desc
        return when (field) {
            VideoLibrarySortField.CreateTime ->
                if (order == VideoLibrarySortOrder.Desc) getString(R.string.video_library_sort_create_time_desc) else getString(R.string.video_library_sort_create_time_asc)
            VideoLibrarySortField.Name ->
                if (order == VideoLibrarySortOrder.Asc) getString(R.string.video_library_sort_name_asc) else getString(R.string.video_library_sort_name_desc)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_KIND = "kind"
        private const val ARG_CURRENT_KEYWORD = "current_keyword"
        private const val ARG_SORT_FIELD = "sort_field"
        private const val ARG_SORT_ORDER = "sort_order"

        private const val ID_SEARCH = 1
        private const val ID_SORT = 2
        private const val ID_CLEAR = 3
        private const val ID_CLOSE = 4

        fun newInstance(
            kind: String,
            currentKeyword: String,
            sortField: String,
            sortOrder: String,
        ): VideoLibraryOptionsDialogFragment {
            return VideoLibraryOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_KIND to kind,
                        ARG_CURRENT_KEYWORD to currentKeyword,
                        ARG_SORT_FIELD to sortField,
                        ARG_SORT_ORDER to sortOrder,
                    )
            }
        }
    }
}

