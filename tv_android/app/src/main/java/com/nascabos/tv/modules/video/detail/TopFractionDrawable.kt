package com.nascabos.tv.modules.video.detail

import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable

/**
 * 只绘制内层 drawable 在垂直方向上方 [topFraction] 比例区域内（约 0.6 = 上 60%），
 * 用于详情页背景只显示在屏幕上方一段。
 */
class TopFractionDrawable(
    private val inner: Drawable,
    private val topFraction: Float,
) : Drawable() {

    init {
        require(topFraction in 0.01f..1f) { "topFraction must be in (0, 1]" }
    }

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.isEmpty) return
        val clipBottom = b.top + (b.height() * topFraction).toInt().coerceIn(1, b.height())
        canvas.save()
        canvas.clipRect(b.left, b.top, b.right, clipBottom)
        val iw = inner.intrinsicWidth
        val ih = inner.intrinsicHeight
        if (iw > 0 && ih > 0) {
            val bw = b.width().toFloat()
            val bh = b.height().toFloat()
            val scale = maxOf(bw / iw.toFloat(), bh / ih.toFloat())
            val sw = iw * scale
            val sh = ih * scale
            val left = b.left + ((bw - sw) / 2f).toInt()
            val top = b.top + ((bh - sh) / 2f).toInt()
            inner.setBounds(left, top, left + sw.toInt(), top + sh.toInt())
        } else {
            inner.setBounds(b.left, b.top, b.right, b.bottom)
        }
        inner.draw(canvas)
        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {
        inner.alpha = alpha
    }

    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
        inner.colorFilter = colorFilter
    }

    @Suppress("DEPRECATION")
    override fun getOpacity(): Int = inner.opacity
}
