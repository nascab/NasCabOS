package com.nascabos.tv.modules.photo.timeline

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

class PhotoTimelineMonthDialogFragment : DialogFragment() {
    private val currentMonthKey: String by lazy { requireArguments().getString(ARG_CURRENT_MONTH_KEY).orEmpty() }
    private val monthOptions: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_MONTH_OPTIONS) ?: arrayListOf() }

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

        val entries = entries()
        val adapter =
            object : ArrayAdapter<Entry>(ctx, android.R.layout.simple_list_item_single_choice, android.R.id.text1, entries) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.text = getItem(position)?.label.orEmpty()
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

        val cur = currentMonthKey.trim()
        val idx = entries.indexOfFirst { it.value == cur }.takeIf { it >= 0 } ?: 0
        listView.setItemChecked(idx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val e = entries.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                PhotoTimelineBrowseFragment.RESULT_KEY_MONTH,
                bundleOf(PhotoTimelineBrowseFragment.RESULT_FIELD_MONTH_KEY to e.value),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class Entry(
        val value: String,
        val label: String,
    )

    private fun entries(): List<Entry> {
        val list = mutableListOf<Entry>()
        list += Entry(value = "", label = getString(R.string.photo_timeline_month_all))
        monthOptions.map { it.trim() }.filter { it.isNotEmpty() }.distinct().forEach { mk ->
            list += Entry(value = mk, label = mk)
        }
        return list
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_CURRENT_MONTH_KEY = "current_month_key"
        private const val ARG_MONTH_OPTIONS = "month_options"

        fun newInstance(currentMonthKey: String, monthOptions: ArrayList<String>): PhotoTimelineMonthDialogFragment {
            return PhotoTimelineMonthDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_CURRENT_MONTH_KEY to currentMonthKey,
                        ARG_MONTH_OPTIONS to monthOptions,
                    )
            }
        }
    }
}

