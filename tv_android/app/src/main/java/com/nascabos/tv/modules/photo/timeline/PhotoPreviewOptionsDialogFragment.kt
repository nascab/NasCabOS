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

class PhotoPreviewOptionsDialogFragment : DialogFragment() {
    private val autoPlayEnabled: Boolean by lazy { requireArguments().getBoolean(ARG_AUTO_PLAY_ENABLED, false) }
    private val intervalSeconds: Int by lazy { requireArguments().getInt(ARG_INTERVAL_SECONDS, 5).coerceIn(2, 60) }
    private val currentItemIsFavorite: Boolean by lazy { requireArguments().getBoolean(ARG_CURRENT_ITEM_FAVORITE, false) }

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
        root.addView(
            panel,
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply { gravity = Gravity.END },
        )

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
                ID_AUTO_PLAY -> {
                    parentFragmentManager.setFragmentResult(
                        RESULT_KEY_AUTO_PLAY,
                        bundleOf(RESULT_FIELD_AUTO_PLAY_ENABLED to !autoPlayEnabled),
                    )
                    dismissAllowingStateLoss()
                }
                ID_INTERVAL -> {
                    dismissAllowingStateLoss()
                    PhotoPreviewIntervalDialogFragment
                        .newInstance(currentSeconds = intervalSeconds)
                        .show(parentFragmentManager, "photo_preview_interval")
                }
                ID_FAVORITE_TOGGLE -> {
                    parentFragmentManager.setFragmentResult(RESULT_KEY_FAVORITE_TOGGLE, bundleOf())
                    dismissAllowingStateLoss()
                }
                ID_TRASH -> {
                    parentFragmentManager.setFragmentResult(RESULT_KEY_TRASH, bundleOf())
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun buildRows(): List<Row> {
        val list = mutableListOf<Row>()
        val autoPlayDesc = if (autoPlayEnabled) getString(R.string.common_on) else getString(R.string.common_off)
        list += Row(ID_AUTO_PLAY, getString(R.string.photo_preview_auto_play), autoPlayDesc)
        list += Row(ID_INTERVAL, getString(R.string.photo_preview_auto_play_interval), getString(R.string.photo_preview_seconds_format, intervalSeconds))
        list += Row(
            ID_FAVORITE_TOGGLE,
            if (currentItemIsFavorite) getString(R.string.photo_preview_action_unfavorite) else getString(R.string.photo_preview_action_favorite),
            "",
        )
        list += Row(ID_TRASH, getString(R.string.photo_preview_action_trash), "")
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_AUTO_PLAY_ENABLED = "auto_play_enabled"
        private const val ARG_INTERVAL_SECONDS = "interval_seconds"
        private const val ARG_CURRENT_ITEM_FAVORITE = "current_item_is_favorite"

        internal const val RESULT_KEY_AUTO_PLAY = "photo_preview_auto_play"
        internal const val RESULT_FIELD_AUTO_PLAY_ENABLED = "auto_play_enabled"
        internal const val RESULT_KEY_FAVORITE_TOGGLE = "photo_preview_favorite_toggle"
        internal const val RESULT_KEY_TRASH = "photo_preview_trash"

        private const val ID_AUTO_PLAY = 1
        private const val ID_INTERVAL = 2
        private const val ID_FAVORITE_TOGGLE = 3
        private const val ID_TRASH = 4
        private const val ID_CLOSE = 5

        fun newInstance(
            autoPlayEnabled: Boolean,
            intervalSeconds: Int,
            currentItemIsFavorite: Boolean = false,
        ): PhotoPreviewOptionsDialogFragment {
            return PhotoPreviewOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_AUTO_PLAY_ENABLED to autoPlayEnabled,
                        ARG_INTERVAL_SECONDS to intervalSeconds,
                        ARG_CURRENT_ITEM_FAVORITE to currentItemIsFavorite,
                    )
            }
        }
    }
}
