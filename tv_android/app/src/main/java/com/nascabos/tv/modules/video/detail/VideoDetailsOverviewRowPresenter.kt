package com.nascabos.tv.modules.video.detail

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.leanback.widget.FullWidthDetailsOverviewRowPresenter
import androidx.leanback.widget.HorizontalGridView
import androidx.leanback.widget.Presenter
import androidx.leanback.widget.RowPresenter
import androidx.leanback.widget.Row
import androidx.recyclerview.widget.RecyclerView
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader

class VideoDetailsOverviewRowPresenter(
    descriptionPresenter: Presenter,
) : FullWidthDetailsOverviewRowPresenter(descriptionPresenter) {
    private var onActionClicked: ((Long) -> Unit)? = null

    init {
        //设置顶部信息区的背景色
        val alpha = 217
        val semiTransparentBlack = Color.argb(alpha, 0, 0, 0)
        setBackgroundColor(semiTransparentBlack)
        setActionsBackgroundColor(Color.TRANSPARENT)
    }

    fun setOnActionClickedListener(listener: (Long) -> Unit) {
        onActionClicked = listener
        super.setOnActionClickedListener { action ->
            val id = action?.id ?: return@setOnActionClickedListener
            onActionClicked?.invoke(id)
        }
    }

    override fun createRowViewHolder(parent: ViewGroup): RowPresenter.ViewHolder {
        val vh = super.createRowViewHolder(parent)
        val root = vh.view as? ViewGroup
        if (root != null) {
            val actions = root.findViewById<HorizontalGridView?>(androidx.leanback.R.id.details_overview_actions)
            if (actions != null) {
                val h = dp(actions.context, 10f)
                val v = dp(actions.context, 10f)
                val selector = ContextCompat.getDrawable(actions.context, R.drawable.tv_button_bg_color)
                // 在子 View 附着后再设置文字颜色，确保在 Leanback Adapter bind 之后生效
                (actions as? RecyclerView)?.addOnChildAttachStateChangeListener(object : RecyclerView.OnChildAttachStateChangeListener {
                    override fun onChildViewAttachedToWindow(view: View) {
                        view.post {
                            if (selector != null) {
                                val bg = selector.constantState?.newDrawable()?.mutate()
                                if (bg != null) view.background = bg
                            }
                            if (view.paddingLeft != h || view.paddingTop != v || view.paddingRight != h || view.paddingBottom != v) {
                                view.setPadding(h, v, h, v)
                            }
                            applyTextColorToView(view)
                            applyActionItemVerticalCenter(view)
                        }
                    }
                    override fun onChildViewDetachedFromWindow(view: View) {}
                })
            }
            val logo =
                ImageView(parent.context).apply {
                    visibility = View.GONE
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setBackgroundColor(Color.TRANSPARENT)
                }
            val lp =
                FrameLayout.LayoutParams(
                    dp(parent.context, 220f),
                    dp(parent.context, 96f),
                ).apply {
                    gravity = Gravity.TOP or Gravity.END
                    rightMargin = dp(parent.context, 24f)
                    topMargin = dp(parent.context, 18f)
                }
            root.addView(logo, lp)
            logo.bringToFront()
            vh.view.tag = logo
        }
        return vh
    }

    override fun onBindRowViewHolder(vh: RowPresenter.ViewHolder, item: Any) {
        super.onBindRowViewHolder(vh, item)
        applyTextColor(vh.view as? ViewGroup)
        applyPosterScale(vh.view as? ViewGroup)
        applyActionsStyle(vh.view as? ViewGroup)
        applyDescriptionFillRemainingSpace(vh.view as? ViewGroup)
        val data = item as? androidx.leanback.widget.DetailsOverviewRow ?: return
        val payload = data.item as? VideoDetailRowData ?: return
        val logo = vh.view.tag as? ImageView ?: return
        val p = payload.item.logoPath.trim()
        if (p.isEmpty()) {
            logo.visibility = View.GONE
            return
        }
        logo.visibility = View.VISIBLE
        TvImageLoader.loadTinyInto(logo, p, size = 480)
    }

    private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)

    private fun applyTextColor(root: ViewGroup?) {
        if (root == null) return
        applyTextColorToView(root)
    }

    /** 对单个 View 及其子 View 中所有 TextView 设置白色，用于 action 子项（在 attach 后调用以确保覆盖 Leanback 的 bind） */
    private fun applyTextColorToView(view: View) {
        when (view) {
            is TextView -> {
                val txt = view.text?.toString().orEmpty()
                val max = if (txt.contains('\n')) 2 else 1
                if (view.maxLines != max) view.maxLines = max
                if (view.ellipsize != android.text.TextUtils.TruncateAt.END) {
                    view.ellipsize = android.text.TextUtils.TruncateAt.END
                }
                view.setTextColor(Color.WHITE)
            }
            is ViewGroup -> {
                for (i in 0 until view.childCount) {
                    applyTextColorToView(view.getChildAt(i))
                }
            }
        }
    }

    /** 使 action 按钮内文字垂直居中：容器与 TextView 均设置 CENTER 重力 */
    private fun applyActionItemVerticalCenter(view: View) {
        when (view) {
            is TextView -> if (view.gravity != Gravity.CENTER) view.gravity = Gravity.CENTER
            is LinearLayout -> view.gravity = Gravity.CENTER
            is ViewGroup -> {
                for (i in 0 until view.childCount) {
                    applyActionItemVerticalCenter(view.getChildAt(i))
                }
            }
        }
    }

    /** 详情页左上角海报统一尺寸（剧/季一致），避免季详情海报被压小 */
    private fun applyPosterScale(root: ViewGroup?) {
        if (root == null) return
        val poster = root.findViewById<ImageView?>(androidx.leanback.R.id.details_overview_image) ?: return
        poster.scaleType = ImageView.ScaleType.CENTER_CROP
        poster.adjustViewBounds = false
    }

    /** 使海报右侧文字区域填满剩余空间，右侧留一点 padding */
    private fun applyDescriptionFillRemainingSpace(root: ViewGroup?) {
        if (root == null) return
        val descContainer = root.findViewById<View>(androidx.leanback.R.id.details_overview_description) ?: return
        val rightPaddingPx = dp(root.context, 24f)
        descContainer.setPadding(descContainer.paddingLeft, descContainer.paddingTop, rightPaddingPx, descContainer.paddingBottom)
        if (descContainer is ViewGroup && descContainer.childCount > 0) {
            val content = descContainer.getChildAt(0)
            val lp = content.layoutParams
            if (lp != null) {
                lp.width = ViewGroup.LayoutParams.MATCH_PARENT
                content.layoutParams = lp
            }
        }
    }

    private fun applyActionsStyle(root: ViewGroup?) {
        if (root == null) return
        val actions = root.findViewById<HorizontalGridView?>(androidx.leanback.R.id.details_overview_actions) ?: return
        actions.post { styleActionsChildren(actions) }
    }

    private fun styleActionsChildren(actions: HorizontalGridView) {
        val selector = ContextCompat.getDrawable(actions.context, R.drawable.tv_button_bg_color) ?: return
        val h = dp(actions.context, 10f)
        val v = dp(actions.context, 10f)
        for (i in 0 until actions.childCount) {
            val child = actions.getChildAt(i)
            val bg = selector.constantState?.newDrawable()?.mutate()
            if (bg != null) child.background = bg
            if (child.paddingLeft != h || child.paddingTop != v || child.paddingRight != h || child.paddingBottom != v) {
                child.setPadding(h, v, h, v)
            }
            applyTextColorToView(child)
        }
        // 延迟再应用一次，防止 RecyclerView 首次 layout 时子 View 尚未 bind
        actions.post { applyTextColorToView(actions) }
    }
}
