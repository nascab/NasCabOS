package com.nascabos.tv.modules.video.detail

import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.leanback.widget.Presenter
import androidx.leanback.widget.RowHeaderPresenter

/**
 * 详情页行标题（如「季」「演职人员」）使用白色文字。
 * 在 onBindViewHolder 中显式设置，避免被主题或默认样式覆盖。
 */
class WhiteRowHeaderPresenter : RowHeaderPresenter() {

    override fun onBindViewHolder(viewHolder: Presenter.ViewHolder, item: Any) {
        super.onBindViewHolder(viewHolder, item)
        setTextColorWhite(viewHolder.view)
    }

    override fun onViewAttachedToWindow(viewHolder: Presenter.ViewHolder) {
        super.onViewAttachedToWindow(viewHolder)
        setTextColorWhite(viewHolder.view)
    }

    private fun setTextColorWhite(view: View) {
        when (view) {
            is TextView -> view.setTextColor(Color.WHITE)
            is ViewGroup -> {
                for (i in 0 until view.childCount) {
                    setTextColorWhite(view.getChildAt(i))
                }
            }
        }
    }
}
