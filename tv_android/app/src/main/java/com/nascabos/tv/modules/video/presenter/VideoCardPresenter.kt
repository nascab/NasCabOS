package com.nascabos.tv.modules.video.presenter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import android.widget.ProgressBar
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.video.VideoDiscThumbResolver
import com.nascabos.tv.modules.video.VideoListItem

class VideoCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view =
            LayoutInflater.from(parent.context).inflate(R.layout.video_grid_card, parent, false).apply {
                isFocusable = true
                isFocusableInTouchMode = true
            }

        val titleView = view.findViewById<TextView>(R.id.video_card_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }

        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val video = item as? VideoListItem ?: return

        val typeText = view.findViewById<TextView>(R.id.video_card_type_text)
        val thumb = view.findViewById<ImageView>(R.id.video_card_thumb)
        val thumbLoading = view.findViewById<ProgressBar>(R.id.video_card_thumb_loading)
        val score = view.findViewById<TextView>(R.id.video_card_score)
        val title = view.findViewById<TextView>(R.id.video_card_title)
        val subtitle = view.findViewById<TextView>(R.id.video_card_subtitle)
        val genres = view.findViewById<TextView>(R.id.video_card_genres)

        val mt = video.mediaType.trim().lowercase()
        typeText.text =
            when (mt) {
                "tv" -> context.getString(R.string.video_media_type_tv)
                else -> context.getString(R.string.video_media_type_movie)
            }

        val scoreValue = video.nfoScore
        val scoreText = if (scoreValue > 0.0) String.format("%.1f", scoreValue) else ""
        score.text = scoreText
        score.setTextColor(0xFFFFA726.toInt())
        score.visibility = if (scoreText.isEmpty()) View.INVISIBLE else View.VISIBLE

        val displayTitle = video.nfoName.trim().ifEmpty { video.filename.trim() }
        title.text = displayTitle

        val year = video.nfoYear.takeIf { it > 0 }?.toString().orEmpty()
        val region = video.nfoRegions.trim()
        val subtitleText =
            when {
                year.isNotEmpty() && region.isNotEmpty() -> "$year · $region"
                year.isNotEmpty() -> year
                region.isNotEmpty() -> region
                else -> ""
            }
        subtitle.text = subtitleText
        subtitle.visibility = if (subtitleText.isEmpty()) View.GONE else View.VISIBLE

        val genresText = video.nfoGenres.trim()
        genres.text = genresText
        genres.visibility = if (genresText.isEmpty()) View.GONE else View.VISIBLE

        val poster = video.posterPath.trim()
        val firstFile = video.firstFilePath.trim()
        val fullPath = video.fullPath.trim()
        val isDiscType = mt == "bdmv" || mt == "video_ts"
        // 先设占位图，避免出现白块
        thumb.setImageResource(R.drawable.ic_video)
        // 有 poster 时用 poster；无 poster 时：tv/season 用 first_file_path 取缩略图，否则用 full_path 取 tiny 缩略图
        val primaryPath = if (poster.isNotEmpty()) poster else ""
        val fallbackForThumb: String = when {
            primaryPath.isNotEmpty() -> ""
            isDiscType -> ""
            mt == "tv" || mt == "season" -> firstFile
            else -> fullPath
        }
        val useVideoThumbnail = fallbackForThumb.isNotEmpty()
        val thumbSize = 640

        fun loadDiscThumb() {
            thumbLoading.visibility = View.VISIBLE
            thumb.setTag(R.id.video_card_thumb, video.id)
            VideoDiscThumbResolver.resolveThumbApiPath(indexId = video.id, size = thumbSize) { apiPath ->
                if (thumb.getTag(R.id.video_card_thumb) != video.id) return@resolveThumbApiPath
                if (apiPath.isEmpty()) {
                    thumbLoading.visibility = View.GONE
                    return@resolveThumbApiPath
                }
                TvImageLoader.loadApiPathInto(
                    imageView = thumb,
                    apiPath = apiPath,
                    cacheKeyPrefix = "video-disc-thumb",
                    placeholderResId = R.drawable.ic_video,
                    reqSize = thumbSize,
                    showPlaceholderWhileLoading = true,
                    errorResId = R.drawable.img_404,
                    onDone = { success ->
                        thumbLoading.visibility = View.GONE
                    },
                )
            }
        }

        fun loadThumb(path: String) {
            thumbLoading.visibility = View.VISIBLE
            TvImageLoader.loadTinyInto(
                imageView = thumb,
                filePath = path,
                size = thumbSize,
                placeholderResId = R.drawable.ic_video,
                showPlaceholderWhileLoading = true,
                errorResId = R.drawable.img_404,
                onDone = { success ->
                    thumbLoading.visibility = View.GONE
                    if (!success && isDiscType && path == primaryPath) {
                        loadDiscThumb()
                    } else if (!success && path != fallbackForThumb && fallbackForThumb.isNotEmpty()) {
                        thumbLoading.visibility = View.VISIBLE
                        TvImageLoader.loadTinyInto(
                            imageView = thumb,
                            filePath = fallbackForThumb,
                            size = thumbSize,
                            placeholderResId = R.drawable.ic_video,
                            showPlaceholderWhileLoading = true,
                            errorResId = R.drawable.img_404,
                            onDone = { thumbLoading.visibility = View.GONE },
                        )
                    }
                },
            )
        }

        when {
            isDiscType && primaryPath.isNotEmpty() -> loadThumb(primaryPath)
            isDiscType -> loadDiscThumb()
            useVideoThumbnail -> loadThumb(fallbackForThumb)
            primaryPath.isNotEmpty() -> loadThumb(primaryPath)
            else -> {
                thumbLoading.visibility = View.GONE
                // 无任何图时保持占位图（已在上面 setImageResource）
            }
        }
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
}
