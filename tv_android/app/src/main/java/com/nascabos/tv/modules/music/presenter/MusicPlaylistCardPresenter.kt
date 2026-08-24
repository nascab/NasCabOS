package com.nascabos.tv.modules.music.presenter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.modules.music.MusicFallbackCover
import com.nascabos.tv.modules.music.MusicPlaylistItem
import com.nascabos.tv.modules.music.MusicUrl
import com.nascabos.tv.core.ui.TvImageLoader

class MusicPlaylistCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view =
            LayoutInflater.from(parent.context).inflate(R.layout.music_library_grid_card_small, parent, false).apply {
                isFocusable = true
                isFocusableInTouchMode = true
            }

        val titleView = view.findViewById<TextView>(R.id.video_library_card_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }

        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val playlist = item as? MusicPlaylistItem ?: return

        val row = view.findViewById<LinearLayout>(R.id.video_library_thumb_row)
        val single = view.findViewById<ImageView>(R.id.video_library_thumb_single)
        val title = view.findViewById<TextView>(R.id.video_library_card_title)
        val subtitle = view.findViewById<TextView>(R.id.video_library_card_subtitle)
        val tag = view.findViewById<TextView>(R.id.video_library_card_tag)

        row.visibility = View.GONE
        single.visibility = View.VISIBLE

        title.text = playlist.name
        subtitle.text = playlist.createTime
        subtitle.visibility = if (playlist.createTime.trim().isEmpty()) View.GONE else View.VISIBLE

        tag.text = context.getString(R.string.home_music_playlists)
        tag.visibility = View.VISIBLE

        val coverTarget =
            playlist.previews.firstOrNull()?.resolvePlayablePath()?.trim().orEmpty()
        val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 360)
        MusicFallbackCover.loadInto(single, "icons/default_cover.jpg", reqSize = 360)
        if (apiPath.isNotEmpty()) {
            TvImageLoader.loadApiPathInto(
                imageView = single,
                apiPath = apiPath,
                cacheKeyPrefix = "music_playlist_cover_360",
                reqSize = 360,
                placeholderResId = 0,
                showPlaceholderWhileLoading = false,
            )
        }
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
}
