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

class VideoLibrarySortDialogFragment : DialogFragment() {
    private val currentField: String by lazy { requireArguments().getString(ARG_SORT_FIELD).orEmpty() }
    private val currentOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

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

        val currentIdx = entries.indexOfFirst { it.field.name == currentField && it.order.name == currentOrder }.takeIf { it >= 0 } ?: 0
        listView.setItemChecked(currentIdx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val e = entries.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                VideoLibraryGridFragment.RESULT_KEY_SORT,
                bundleOf(
                    VideoLibraryGridFragment.RESULT_FIELD_SORT_FIELD to e.field.name,
                    VideoLibraryGridFragment.RESULT_FIELD_SORT_ORDER to e.order.name,
                ),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class SortEntry(
        val field: VideoLibrarySortField,
        val order: VideoLibrarySortOrder,
        val labelRes: Int,
    )

    private fun sortEntries(): List<SortEntry> {
        return listOf(
            SortEntry(VideoLibrarySortField.CreateTime, VideoLibrarySortOrder.Desc, R.string.video_library_sort_create_time_desc),
            SortEntry(VideoLibrarySortField.CreateTime, VideoLibrarySortOrder.Asc, R.string.video_library_sort_create_time_asc),
            SortEntry(VideoLibrarySortField.Name, VideoLibrarySortOrder.Asc, R.string.video_library_sort_name_asc),
            SortEntry(VideoLibrarySortField.Name, VideoLibrarySortOrder.Desc, R.string.video_library_sort_name_desc),
        )
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_SORT_FIELD = "sort_field"
        private const val ARG_SORT_ORDER = "sort_order"

        fun newInstance(currentSortField: String, currentSortOrder: String): VideoLibrarySortDialogFragment {
            return VideoLibrarySortDialogFragment().apply {
                arguments = bundleOf(ARG_SORT_FIELD to currentSortField, ARG_SORT_ORDER to currentSortOrder)
            }
        }
    }
}

