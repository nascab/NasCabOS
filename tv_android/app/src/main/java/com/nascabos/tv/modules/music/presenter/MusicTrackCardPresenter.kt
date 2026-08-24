package com.nascabos.tv.modules.music.presenter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.modules.music.MusicListItem
import com.nascabos.tv.modules.music.MusicUrl
import com.nascabos.tv.core.ui.TvImageLoader

class MusicTrackCardPresenter(
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
        val music = item as? MusicListItem ?: return

        val typeText = view.findViewById<TextView>(R.id.video_card_type_text)
        val thumb = view.findViewById<ImageView>(R.id.video_card_thumb)
        val thumbLoading = view.findViewById<ProgressBar>(R.id.video_card_thumb_loading)
        val score = view.findViewById<TextView>(R.id.video_card_score)
        val title = view.findViewById<TextView>(R.id.video_card_title)
        val subtitle = view.findViewById<TextView>(R.id.video_card_subtitle)
        val genres = view.findViewById<TextView>(R.id.video_card_genres)

        val isFolder = music.isFolder
        typeText.text =
            if (isFolder) {
                context.getString(R.string.music_item_type_folder)
            } else {
                ""
            }
        typeText.visibility = if (isFolder) View.VISIBLE else View.INVISIBLE

        score.text = if (music.isFavorite) "♥" else ""
        score.setTextColor(0xFFEF5350.toInt())
        score.visibility = if (music.isFavorite) View.VISIBLE else View.INVISIBLE

        val displayTitle = music.displayTitle.ifEmpty { music.title.trim() }
        title.text = displayTitle

        val subtitleText = music.displaySubtitle
        subtitle.text = subtitleText
        subtitle.visibility = if (subtitleText.isEmpty()) View.GONE else View.VISIBLE

        val infoText =
            if (isFolder) {
                val c = music.musicCount.coerceAtLeast(0)
                if (c > 0) context.getString(R.string.music_item_folder_count, c) else ""
            } else {
                formatDurationLabel(music.duration)
            }
        genres.text = infoText
        genres.visibility = if (infoText.isEmpty()) View.GONE else View.VISIBLE

        val coverTarget =
            if (isFolder) {
                music.firstFilePath.trim().ifEmpty { music.resolvePlayablePath() }
            } else {
                music.resolvePlayablePath()
            }
        val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 480)
        thumbLoading.visibility = if (apiPath.isNotEmpty()) View.VISIBLE else View.GONE
        TvImageLoader.loadApiPathInto(
            imageView = thumb,
            apiPath = apiPath,
            cacheKeyPrefix = "music_cover_480",
            placeholderResId = if (isFolder) R.drawable.ic_folder else R.drawable.ic_music_note,
            reqSize = 480,
            showPlaceholderWhileLoading = false,
            onDone = { thumbLoading.visibility = View.GONE },
        )
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}

    private fun formatDurationLabel(seconds: Int): String {
        val s = seconds.coerceAtLeast(0)
        if (s <= 0) return ""
        val total = if (s > 24 * 60 * 60) s / 1000 else s
        val h = total / 3600
        val m = (total % 3600) / 60
        val sec = total % 60
        return if (h > 0) {
            String.format("%d:%02d:%02d", h, m, sec)
        } else {
            String.format("%d:%02d", m, sec)
        }
    }
}
