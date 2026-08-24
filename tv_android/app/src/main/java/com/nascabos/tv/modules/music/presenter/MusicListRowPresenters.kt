package com.nascabos.tv.modules.music.presenter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.music.MusicFallbackCover
import com.nascabos.tv.modules.music.MusicGroupItem
import com.nascabos.tv.modules.music.MusicListItem
import com.nascabos.tv.modules.music.MusicPlaylistItem
import com.nascabos.tv.modules.music.MusicUrl

class MusicTrackRowPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.music_list_row_item, parent, false)
        view.isFocusable = true
        view.isFocusableInTouchMode = true
        view.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        val titleView = view.findViewById<TextView>(R.id.music_row_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }
        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val music = item as? MusicListItem ?: return

        val cover = view.findViewById<ImageView>(R.id.music_row_cover)
        val badge = view.findViewById<TextView>(R.id.music_row_badge)
        val title = view.findViewById<TextView>(R.id.music_row_title)
        val subtitle = view.findViewById<TextView>(R.id.music_row_subtitle)
        val meta = view.findViewById<TextView>(R.id.music_row_meta)

        val isFolder = music.isFolder
        title.text = music.displayTitle
        val rawSub = music.displaySubtitle
        val durationText = if (!isFolder) formatDurationLabel(music.duration) else ""
        val folderCountText =
            if (isFolder) {
                val c = music.musicCount.coerceAtLeast(0)
                if (c > 0) context.getString(R.string.music_item_folder_count, c) else ""
            } else {
                ""
            }
        val sub =
            if (isFolder) {
                listOf(folderCountText, rawSub).filter { it.isNotEmpty() }.joinToString(" · ")
            } else {
                listOf(durationText, rawSub).filter { it.isNotEmpty() }.joinToString(" · ")
            }
        subtitle.text = sub
        subtitle.visibility = if (sub.isNotEmpty()) View.VISIBLE else View.GONE

        if (music.isFavorite) {
            badge.text = "♥"
            badge.setTextColor(0xFFEF5350.toInt())
            badge.visibility = View.VISIBLE
        } else if (isFolder) {
            badge.text = context.getString(R.string.music_item_type_folder)
            badge.setTextColor(0xFFFFFFFF.toInt())
            badge.visibility = View.VISIBLE
        } else {
            badge.visibility = View.GONE
        }

        meta.text = ""

        val seed = music.id
        val customAsset = MusicFallbackCover.pickAssetPathForTrack(music.genre, seed)
        val shouldUseCustomCover = !isFolder && music.hasInnerCover <= 0
        if (shouldUseCustomCover) {
            MusicFallbackCover.loadInto(cover, customAsset, reqSize = 320)
            return
        }

        MusicFallbackCover.loadInto(cover, customAsset, reqSize = 320)
        val coverTarget =
            if (isFolder) {
                music.firstFilePath.trim().ifEmpty { music.resolvePlayablePath() }
            } else {
                music.resolvePlayablePath()
            }
        val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 320)
        TvImageLoader.loadApiPathInto(
            imageView = cover,
            apiPath = apiPath,
            cacheKeyPrefix = "music_cover_320",
            placeholderResId = 0,
            reqSize = 320,
            showPlaceholderWhileLoading = false,
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

class MusicGroupRowPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.music_list_row_item, parent, false)
        view.isFocusable = true
        view.isFocusableInTouchMode = true
        val titleView = view.findViewById<TextView>(R.id.music_row_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }
        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val group = item as? MusicGroupItem ?: return

        val cover = view.findViewById<ImageView>(R.id.music_row_cover)
        val badge = view.findViewById<TextView>(R.id.music_row_badge)
        val title = view.findViewById<TextView>(R.id.music_row_title)
        val subtitle = view.findViewById<TextView>(R.id.music_row_subtitle)
        val meta = view.findViewById<TextView>(R.id.music_row_meta)

        title.text = group.name
        val count = group.indexCount.coerceAtLeast(0)
        subtitle.text = if (count > 0) context.getString(R.string.music_group_count, count) else ""
        subtitle.visibility = if (subtitle.text.isNullOrEmpty()) View.GONE else View.VISIBLE
        meta.text = ""

        val kt = group.keyType.trim().lowercase()
        badge.text =
            if (kt == "artist") {
                context.getString(R.string.home_music_artists)
            } else {
                context.getString(R.string.home_music_albums)
            }
        badge.setTextColor(0xFFFFFFFF.toInt())
        badge.visibility = View.VISIBLE

        val fallbackAsset = MusicFallbackCover.pickAssetPathForName(group.name, seed = group.name.hashCode())
        MusicFallbackCover.loadInto(cover, fallbackAsset, reqSize = 320)

        val coverTarget = group.firstFilePath.trim()
        val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 320)
        TvImageLoader.loadApiPathInto(
            imageView = cover,
            apiPath = apiPath,
            cacheKeyPrefix = "music_group_cover_320",
            placeholderResId = 0,
            reqSize = 320,
            showPlaceholderWhileLoading = false,
        )
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
}

class MusicPlaylistRowPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.music_list_row_item, parent, false)
        view.isFocusable = true
        view.isFocusableInTouchMode = true
        val titleView = view.findViewById<TextView>(R.id.music_row_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }
        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val playlist = item as? MusicPlaylistItem ?: return

        val cover = view.findViewById<ImageView>(R.id.music_row_cover)
        val badge = view.findViewById<TextView>(R.id.music_row_badge)
        val title = view.findViewById<TextView>(R.id.music_row_title)
        val subtitle = view.findViewById<TextView>(R.id.music_row_subtitle)
        val meta = view.findViewById<TextView>(R.id.music_row_meta)

        title.text = playlist.name
        subtitle.text = playlist.createTime
        subtitle.visibility = if (playlist.createTime.trim().isEmpty()) View.GONE else View.VISIBLE
        meta.text = ""

        badge.text = context.getString(R.string.home_music_playlists)
        badge.setTextColor(0xFFFFFFFF.toInt())
        badge.visibility = View.VISIBLE

        val fallbackAsset = MusicFallbackCover.pickAssetPathForName(playlist.name, seed = playlist.id)
        MusicFallbackCover.loadInto(cover, fallbackAsset, reqSize = 320)

        val coverTarget = playlist.previews.firstOrNull()?.resolvePlayablePath()?.trim().orEmpty()
        val apiPath = MusicUrl.buildCoverApiPath(coverTarget, size = 320)
        TvImageLoader.loadApiPathInto(
            imageView = cover,
            apiPath = apiPath,
            cacheKeyPrefix = "music_playlist_cover_320",
            placeholderResId = 0,
            reqSize = 320,
            showPlaceholderWhileLoading = false,
        )
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
}
