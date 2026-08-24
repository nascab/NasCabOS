package com.nascabos.tv.modules.video.detail

import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.leanback.widget.HorizontalGridView
import androidx.leanback.widget.ListRowPresenter
import androidx.leanback.widget.RowPresenter

class VideoDetailListRowPresenter : ListRowPresenter() {
    /** 与详情页上部一致的半透明黑背景 */
    private val rowBackgroundColor = Color.argb(217, 0, 0, 0)

    init {
        shadowEnabled = false
        selectEffectEnabled = true
        setHeaderPresenter(WhiteRowHeaderPresenter())
    }

    override fun createRowViewHolder(parent: ViewGroup): RowPresenter.ViewHolder {
        val vh = super.createRowViewHolder(parent)
        vh.view.setBackgroundColor(rowBackgroundColor)
        applyRowHorizontalPadding(vh.view)
        return vh
    }

    override fun onBindRowViewHolder(vh: RowPresenter.ViewHolder, item: Any) {
        super.onBindRowViewHolder(vh, item)
        vh.view.setBackgroundColor(rowBackgroundColor)
        applyRowHorizontalPadding(vh.view)
        applyTextColor(vh.view as? ViewGroup)
        applyHorizontalSpacing(vh.view as? ViewGroup)
    }

    /** 整行左右留白，避免列表贴边 */
    private fun applyRowHorizontalPadding(rowView: View) {
        val h = dp(rowView, 32f)
        rowView.setPadding(h, rowView.paddingTop, h, rowView.paddingBottom)
    }

    private fun applyTextColor(root: ViewGroup?) {
        if (root == null) return
        val stack = ArrayList<android.view.View>()
        stack.add(root)
        while (stack.isNotEmpty()) {
            val v = stack.removeAt(stack.size - 1)
            when (v) {
                is TextView -> v.setTextColor(Color.WHITE)
                is ViewGroup -> {
                    for (i in 0 until v.childCount) {
                        stack.add(v.getChildAt(i))
                    }
                }
            }
        }
    }

    private fun applyHorizontalSpacing(root: ViewGroup?) {
        if (root == null) return
        val spacing = dp(root, 10f)
        val sidePadding = dp(root, 16f)
        val stack = ArrayList<View>()
        stack.add(root)
        while (stack.isNotEmpty()) {
            val v = stack.removeAt(stack.size - 1)
            when (v) {
                is HorizontalGridView -> {
                    runCatching { v.setItemSpacing(spacing) }
                    v.setPadding(sidePadding, v.paddingTop, sidePadding, v.paddingBottom)
                    v.clipToPadding = false
                }
                is ViewGroup -> {
                    for (i in 0 until v.childCount) {
                        stack.add(v.getChildAt(i))
                    }
                }
            }
        }
    }

    private fun dp(view: View, dp: Float): Int {
        return (dp * view.resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }
}
