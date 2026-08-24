package com.nascabos.tv.modules.video.detail

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.TextUtils
import android.util.TypedValue
import android.view.ViewGroup
import android.widget.TextView
import androidx.leanback.widget.AbstractDetailsDescriptionPresenter
import androidx.leanback.widget.ImageCardView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader

class VideoDetailsDescriptionPresenter(
    private val context: Context,
) : AbstractDetailsDescriptionPresenter() {
    override fun onBindDescription(
        vh: ViewHolder,
        item: Any,
    ) {
        val data = item as? VideoDetailRowData ?: return
        val title = data.item.displayTitle
        vh.title.text = title
        vh.title.setTextColor(Color.WHITE)
        vh.title.setTypeface(vh.title.typeface ?: Typeface.DEFAULT, Typeface.BOLD)
        vh.title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)

        ensureExtraRows(vh)
        @Suppress("UNCHECKED_CAST")
        val extras = vh.view.tag as? Array<TextView>
        if (extras != null && extras.size >= 2) {
            val filenameLine = data.item.filename.trim()
            extras[0].text = filenameLine
            extras[0].visibility = if (filenameLine.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
            val metaLine = formatMetaLine(data.item)
            extras[1].text = metaLine
            extras[1].visibility = if (metaLine.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
        }

        val year = data.item.nfoYear.takeIf { it > 0 }?.toString().orEmpty()
        val region = data.item.nfoRegions.trim()
        val genres = data.item.nfoGenres.trim()
        val subtitle =
            when {
                year.isNotEmpty() && region.isNotEmpty() -> "$year · $region"
                year.isNotEmpty() -> year
                region.isNotEmpty() -> region
                else -> ""
            }
        val sub2 =
            when {
                subtitle.isNotEmpty() && genres.isNotEmpty() -> "$subtitle · $genres"
                subtitle.isNotEmpty() -> subtitle
                genres.isNotEmpty() -> genres
                else -> ""
            }
        vh.subtitle.text = sub2
        vh.subtitle.setTextColor(0xB3FFFFFF.toInt())

        val plot = data.item.nfoPlot.trim()
        vh.body.text = plot
        vh.body.setTextColor(0xE6FFFFFF.toInt())
    }

    private fun ensureExtraRows(vh: ViewHolder) {
        if (vh.view.tag != null) return
        val parent = vh.view as? ViewGroup ?: return
        val titleIndex = parent.indexOfChild(vh.title)
        if (titleIndex < 0) return
        val insertIndex = titleIndex + 1
        val filenameView = TextView(context).apply {
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
        val durationSizeView = TextView(context).apply {
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
        parent.addView(filenameView, insertIndex)
        parent.addView(durationSizeView, insertIndex + 1)
        vh.view.tag = arrayOf(filenameView, durationSizeView)
    }

    /** 电影：时长+大小；TV：共xx季；season：共xx集 */
    private fun formatMetaLine(item: VideoDetailItem): String {
        val t = item.mediaType.trim().lowercase()
        return when (t) {
            "tv" -> if (item.seasonCount > 0) context.getString(R.string.video_detail_meta_seasons_count, item.seasonCount) else ""
            "season" -> if (item.episodeCount > 0) context.getString(R.string.video_detail_meta_episodes_count, item.episodeCount) else ""
            else -> formatDurationAndSize(item.durationSeconds, item.sizeBytes)
        }
    }

    private fun formatDurationAndSize(durationSeconds: Int, sizeBytes: Long): String {
        val parts = mutableListOf<String>()
        if (durationSeconds > 0) parts.add(formatDuration(durationSeconds))
        if (sizeBytes > 0) parts.add(formatFileSize(sizeBytes))
        return parts.joinToString(" · ")
    }

    private fun formatDuration(totalSeconds: Int): String {
        val s = totalSeconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%02d:%02d", m, sec)
    }

    private fun formatFileSize(bytes: Long): String {
        if (bytes <= 0) return ""
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var unitIndex = 0
        var value = bytes.toDouble()
        while (value >= 1024 && unitIndex < units.size - 1) {
            value /= 1024
            unitIndex++
        }
        return if (unitIndex == 0) "${value.toLong()} ${units[0]}" else String.format("%.1f %s", value, units[unitIndex])
    }
}

class VideoSeasonCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val card =
            ImageCardView(parent.context).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                setBackgroundColor(Color.parseColor("#1E1E1E"))
                setInfoAreaBackgroundColor(Color.parseColor("#1E1E1E"))
                setMainImageDimensions(dp(parent.context, 150f), dp(parent.context, 200f))
                mainImageView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                setCardTextColors()
            }
        return ViewHolder(card)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val card = viewHolder.view as ImageCardView
        val data = item as? VideoSeasonItem ?: return
        card.titleText = data.name
        card.contentText = context.getString(R.string.video_detail_season_label)
        val pick =
            data.posterPath.trim().ifEmpty {
                data.fanartPath.trim().ifEmpty {
                    data.logoPath.trim().ifEmpty { data.firstFilePath.trim() }
                }
            }
        TvImageLoader.loadTinyInto(card.mainImageView, pick, size = 480)
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}

    private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)
}

class VideoEpisodeCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val card =
            ImageCardView(parent.context).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                setBackgroundColor(Color.parseColor("#1E1E1E"))
                setInfoAreaBackgroundColor(Color.parseColor("#1E1E1E"))
                setMainImageDimensions(dp(parent.context, 210f), dp(parent.context, 118f))
                mainImageView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
                setCardTextColors()
            }
        runCatching {
            val titleView = card.findViewById<TextView>(androidx.leanback.R.id.title_text)
            titleView.maxLines = 1
            titleView.ellipsize = TextUtils.TruncateAt.END
            val content = card.findViewById<TextView>(androidx.leanback.R.id.content_text)
            content.maxLines = 3
            content.minLines = 3
            content.ellipsize = TextUtils.TruncateAt.END
        }
        return ViewHolder(card)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val card = viewHolder.view as ImageCardView
        val data = item as? VideoEpisodeItem ?: return
        val idx = data.displayIndex.takeIf { it > 0 } ?: (data.episodeNum.takeIf { it > 0 } ?: 0)
        card.titleText = if (idx > 0) "${idx}.${data.name}" else data.name
        val plot = data.plot.trim()
        val durationSizeStr = formatEpisodeDurationAndSize(data.durationSeconds, data.sizeBytes)
        card.contentText = when {
            plot.isEmpty() && durationSizeStr.isEmpty() -> ""
            plot.isEmpty() -> durationSizeStr
            durationSizeStr.isEmpty() -> plot
            else -> "$durationSizeStr\n$plot"
        }
        val pick =
            data.posterPath.trim().ifEmpty {
                data.fanartPath.trim().ifEmpty {
                    data.logoPath.trim().ifEmpty { data.fullPath.trim() }
                }
            }
        if (data.apiThumbPath.trim().isNotEmpty()) {
            TvImageLoader.loadApiPathInto(
                imageView = card.mainImageView,
                apiPath = data.apiThumbPath,
                cacheKeyPrefix = "video-disc-episode",
                placeholderResId = R.drawable.ic_video,
                reqSize = 640,
                showPlaceholderWhileLoading = true,
                errorResId = R.drawable.img_404,
                onDone = { success ->
                    if (!success) {
                        TvImageLoader.loadTinyInto(card.mainImageView, pick, size = 640)
                    }
                },
            )
        } else {
            TvImageLoader.loadTinyInto(card.mainImageView, pick, size = 640)
        }
        card.mainImageView.setBackgroundColor(Color.parseColor("#121212"))
    }

    private fun formatEpisodeDurationAndSize(durationSeconds: Int, sizeBytes: Long): String {
        val parts = mutableListOf<String>()
        if (durationSeconds > 0) parts.add(formatEpisodeDuration(durationSeconds))
        if (sizeBytes > 0) parts.add(formatEpisodeFileSize(sizeBytes))
        return parts.joinToString(" · ")
    }

    private fun formatEpisodeDuration(totalSeconds: Int): String {
        val s = totalSeconds.coerceAtLeast(0)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%02d:%02d", m, sec)
    }

    private fun formatEpisodeFileSize(bytes: Long): String {
        if (bytes <= 0) return ""
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var unitIndex = 0
        var value = bytes.toDouble()
        while (value >= 1024 && unitIndex < units.size - 1) {
            value /= 1024
            unitIndex++
        }
        return if (unitIndex == 0) "${value.toLong()} ${units[0]}" else String.format("%.1f %s", value, units[unitIndex])
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}

    private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)
}

class VideoPersonCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val card =
            ImageCardView(parent.context).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                setBackgroundColor(Color.parseColor("#1E1E1E"))
                setInfoAreaBackgroundColor(Color.parseColor("#1E1E1E"))
                setMainImageDimensions(dp(parent.context, 120f), dp(parent.context, 160f))
                setCardTextColors()
            }
        return ViewHolder(card)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val card = viewHolder.view as ImageCardView
        val data = item as? VideoPerson ?: return
        card.titleText = data.name
        card.contentText =
            when (data.role) {
                "director" -> context.getString(R.string.video_detail_directors)
                "actor" -> context.getString(R.string.video_detail_actors)
                else -> data.role
            }
        val apiPath = VideoDetailUrl.buildPersonImagePath(tmdbId = data.tmdbId, size = 240, thumb = data.thumb.ifEmpty { null })
        TvImageLoader.loadApiPathInto(
            imageView = card.mainImageView,
            apiPath = apiPath,
            cacheKeyPrefix = "person",
            placeholderResId = R.drawable.ic_person,
        )
        card.mainImageView.setBackgroundColor(Color.parseColor("#121212"))
        card.mainImageView.scaleType = android.widget.ImageView.ScaleType.CENTER_CROP
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}

    private fun dp(ctx: Context, dp: Float): Int = (dp * ctx.resources.displayMetrics.density).toInt().coerceAtLeast(0)
}

data class VideoDetailRowData(
    val item: VideoDetailItem,
    val history: VideoHistory?,
)

private fun ImageCardView.setCardTextColors() {
    val cls = ImageCardView::class.java
    runCatching {
        val m = cls.getMethod("setTitleTextColor", Int::class.javaPrimitiveType)
        m.invoke(this, Color.WHITE)
    }
    runCatching {
        val m = cls.getMethod("setContentTextColor", Int::class.javaPrimitiveType)
        m.invoke(this, 0xB3FFFFFF.toInt())
    }
}
