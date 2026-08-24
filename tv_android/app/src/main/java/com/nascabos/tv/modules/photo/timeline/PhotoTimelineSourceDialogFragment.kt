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
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import com.nascabos.tv.R

class PhotoTimelineSourceDialogFragment : DialogFragment() {
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

        val panelWidth = dpToPx(560f)
        val panel =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val title =
            TextView(ctx).apply {
                text = getString(R.string.photo_timeline_action_sources)
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 18f
                setPadding(dpToPx(18f), dpToPx(16f), dpToPx(18f), dpToPx(8f))
            }
        panel.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val listView =
            ListView(ctx).apply {
                choiceMode = ListView.CHOICE_MODE_MULTIPLE
                dividerHeight = 0
                selector = ctx.getDrawable(R.drawable.video_dialog_selector)
            }
        val listLp =
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0).apply {
                weight = 1f
            }
        panel.addView(listView, listLp)

        val allLabel = getString(R.string.music_list_sources_all_sources)
        val paths = availablePaths.map { it.trim() }.filter { it.isNotEmpty() }
        val selectedSet = selectedPaths.map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet()
        val rows = ArrayList<String>(paths.size + 1).apply {
            add(allLabel)
            addAll(paths)
        }

        val adapter =
            object : ArrayAdapter<String>(ctx, android.R.layout.simple_list_item_multiple_choice, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
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

        if (selectedSet.isEmpty()) {
            listView.setItemChecked(0, true)
        } else {
            listView.setItemChecked(0, false)
        }
        for (i in paths.indices) {
            listView.setItemChecked(i + 1, selectedSet.contains(paths[i]))
        }

        fun emitSelection() {
            val picked =
                if (selectedSet.isEmpty()) {
                    arrayListOf<String>()
                } else {
                    ArrayList(selectedSet.toList())
                }
            parentFragmentManager.setFragmentResult(
                PhotoTimelineBrowseFragment.RESULT_KEY_SOURCES,
                bundleOf(PhotoTimelineBrowseFragment.RESULT_FIELD_SOURCES to picked),
            )
        }
        emitSelection()

        listView.setOnItemClickListener { _, _, position, _ ->
            if (position == 0) {
                listView.setItemChecked(0, true)
                selectedSet.clear()
                for (i in paths.indices) {
                    listView.setItemChecked(i + 1, false)
                }
                emitSelection()
                return@setOnItemClickListener
            }
            val p = paths.getOrNull(position - 1).orEmpty()
            if (p.isEmpty()) return@setOnItemClickListener
            if (selectedSet.contains(p)) selectedSet.remove(p) else selectedSet.add(p)
            if (selectedSet.isEmpty()) {
                listView.setItemChecked(0, true)
                for (i in paths.indices) listView.setItemChecked(i + 1, false)
            } else {
                listView.setItemChecked(0, false)
            }
            emitSelection()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        fun newInstance(availablePaths: ArrayList<String>, selectedPaths: ArrayList<String>): PhotoTimelineSourceDialogFragment {
            return PhotoTimelineSourceDialogFragment().apply {
                arguments = bundleOf(ARG_AVAILABLE_PATHS to availablePaths, ARG_SELECTED_PATHS to selectedPaths)
            }
        }
    }
}

