package com.nascabos.tv.modules.video

import android.app.Dialog
import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.CheckedTextView
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.TextView
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import com.nascabos.tv.R

class VideoSortDialogFragment : DialogFragment() {
    private val currentBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val currentOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val listType: String by lazy { requireArguments().getString(ARG_LIST_TYPE).orEmpty() }

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
                choiceMode = ListView.CHOICE_MODE_SINGLE
                dividerHeight = 0
                selector = resources.getDrawable(R.drawable.video_dialog_selector, ctx.theme)
            }
        panel.addView(listView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val entries = sortEntries()
        val adapter =
            object : ArrayAdapter<SortEntry>(ctx, android.R.layout.simple_list_item_single_choice, android.R.id.text1, entries) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.text = getString(getItem(position)?.labelRes ?: R.string.video_list_action_sort)
                    t.setTextColor(0xFFFFFFFF.toInt())
                    if (t is CheckedTextView) {
                        val d = t.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            t.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)

        val currentIdx = entries.indexOfFirst { it.by.name == currentBy && it.order.name == currentOrder }.takeIf { it >= 0 } ?: 0
        listView.setItemChecked(currentIdx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val e = entries.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                VideoGridFragment.RESULT_KEY_SORT,
                bundleOf(
                    VideoGridFragment.RESULT_FIELD_SORT_BY to e.by.name,
                    VideoGridFragment.RESULT_FIELD_SORT_ORDER to e.order.name,
                ),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class SortEntry(
        val by: VideoListSortBy,
        val order: VideoListSortOrder,
        val labelRes: Int,
    )

    private fun sortEntries(): List<SortEntry> {
        val createTimeResDesc =
            if (listType.trim().lowercase() == "favorite") {
                R.string.video_list_sort_favorite_time_desc
            } else {
                R.string.video_list_sort_create_time_desc
            }
        val createTimeResAsc =
            if (listType.trim().lowercase() == "favorite") {
                R.string.video_list_sort_favorite_time_asc
            } else {
                R.string.video_list_sort_create_time_asc
            }
        return listOf(
            SortEntry(VideoListSortBy.ViewTime, VideoListSortOrder.Desc, R.string.video_list_sort_view_time_desc),
            SortEntry(VideoListSortBy.ViewTime, VideoListSortOrder.Asc, R.string.video_list_sort_view_time_asc),
            SortEntry(VideoListSortBy.CreateTime, VideoListSortOrder.Desc, createTimeResDesc),
            SortEntry(VideoListSortBy.CreateTime, VideoListSortOrder.Asc, createTimeResAsc),
            SortEntry(VideoListSortBy.Year, VideoListSortOrder.Desc, R.string.video_list_sort_year_desc),
            SortEntry(VideoListSortBy.Year, VideoListSortOrder.Asc, R.string.video_list_sort_year_asc),
            SortEntry(VideoListSortBy.Score, VideoListSortOrder.Desc, R.string.video_list_sort_score_desc),
            SortEntry(VideoListSortBy.Score, VideoListSortOrder.Asc, R.string.video_list_sort_score_asc),
            SortEntry(VideoListSortBy.Name, VideoListSortOrder.Asc, R.string.video_list_sort_name_asc),
            SortEntry(VideoListSortBy.Name, VideoListSortOrder.Desc, R.string.video_list_sort_name_desc),
        )
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_LIST_TYPE = "list_type"

        fun newInstance(currentSortBy: String, currentSortOrder: String, listType: String = ""): VideoSortDialogFragment {
            return VideoSortDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_SORT_BY to currentSortBy,
                        ARG_SORT_ORDER to currentSortOrder,
                        ARG_LIST_TYPE to listType,
                    )
            }
        }
    }
}
