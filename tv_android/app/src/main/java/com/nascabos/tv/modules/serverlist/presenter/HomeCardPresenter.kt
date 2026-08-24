package com.nascabos.tv.modules.serverlist.presenter

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.content.ContextCompat
import androidx.leanback.widget.ImageCardView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R

sealed interface HomeCardItem

data class HomeEntryCard(
    val kind: HomeEntryKind,
    val subtitle: String = "",
) : HomeCardItem

enum class HomeEntryKind {
    VideoMovies,
    VideoTvSeries,
    VideoRecent,
    VideoFavorite,
    VideoCustomAlbums,
    VideoSmartAlbums,
    VideoCollections,

    PhotoTimeline,
    PhotoToday,
    PhotoFavorite,
    PhotoCustomAlbums,
    PhotoSmartAlbums,
    PhotoCollections,

    MusicTracks,
    MusicAlbums,
    MusicArtists,
    MusicPlaylists,
    MusicFavorite,
    MusicNowPlaying,

    FileBrowse,

    DevNetworkChannel,

    SettingsVideoPlayback,
    SettingsLanguage,
    SettingsLogout,
}

class HomeCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view = ImageCardView(parent.context).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            setMainImageDimensions(360, 200)
            setInfoAreaBackgroundColor(Color.parseColor("#1E1E1E"))
            mainImageView.scaleType = ImageView.ScaleType.CENTER_INSIDE
        }
        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val cardView = viewHolder.view as ImageCardView
        when (item) {
            is HomeEntryCard -> bindEntry(cardView, item)
        }
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {
        val cardView = viewHolder.view as ImageCardView
        cardView.mainImage = null
    }

    private fun bindEntry(cardView: ImageCardView, card: HomeEntryCard) {
        val (title, iconRes, isBanner) =
            when (card.kind) {
                HomeEntryKind.VideoMovies -> Triple(context.getString(R.string.home_video_movies), R.drawable.home_video_movie, true)
                HomeEntryKind.VideoTvSeries -> Triple(context.getString(R.string.home_video_tv_series), R.drawable.home_video_tv, true)
                HomeEntryKind.VideoRecent -> Triple(context.getString(R.string.home_video_recent), R.drawable.home_video_recent, true)
                HomeEntryKind.VideoFavorite -> Triple(context.getString(R.string.home_video_favorite), R.drawable.home_favorite, true)
                HomeEntryKind.VideoCustomAlbums -> Triple(context.getString(R.string.home_video_custom_albums), R.drawable.home_video_custom_album, true)
                HomeEntryKind.VideoSmartAlbums -> Triple(context.getString(R.string.home_video_smart_albums), R.drawable.home_movie_smart_album, true)
                HomeEntryKind.VideoCollections -> Triple(context.getString(R.string.home_video_collections), R.drawable.home_movie_collection, true)

                HomeEntryKind.PhotoTimeline -> Triple(context.getString(R.string.home_photo_timeline), R.drawable.home_photo_timeline, true)
                HomeEntryKind.PhotoToday -> Triple(context.getString(R.string.home_photo_today), R.drawable.home_photo_today, true)
                HomeEntryKind.PhotoFavorite -> Triple(context.getString(R.string.home_photo_favorite), R.drawable.home_photo_favorite, true)
                HomeEntryKind.PhotoCustomAlbums -> Triple(context.getString(R.string.home_photo_custom_albums), R.drawable.home_photo_album, true)
                HomeEntryKind.PhotoSmartAlbums -> Triple(context.getString(R.string.home_photo_smart_albums), R.drawable.home_photo_smart_album, true)
                HomeEntryKind.PhotoCollections -> Triple(context.getString(R.string.home_photo_collections), R.drawable.home_photo_collection, true)

                HomeEntryKind.MusicTracks -> Triple(context.getString(R.string.home_music_tracks), R.drawable.home_music, true)
                HomeEntryKind.MusicAlbums -> Triple(context.getString(R.string.home_music_albums), R.drawable.home_music_album, true)
                HomeEntryKind.MusicArtists -> Triple(context.getString(R.string.home_music_artists), R.drawable.home_music_artist, true)
                HomeEntryKind.MusicPlaylists -> Triple(context.getString(R.string.home_music_playlists), R.drawable.home_music_playlist, true)
                HomeEntryKind.MusicFavorite -> Triple(context.getString(R.string.home_music_favorite), R.drawable.home_music_favorite, true)
                HomeEntryKind.MusicNowPlaying -> Triple(context.getString(R.string.home_music_now_playing), R.drawable.home_music_playing, true)

                HomeEntryKind.FileBrowse -> Triple(context.getString(R.string.home_file_browse), R.drawable.home_folder, true)

                HomeEntryKind.DevNetworkChannel -> Triple(context.getString(R.string.dev_network_channel), R.drawable.ic_network, true)

                HomeEntryKind.SettingsVideoPlayback -> Triple(context.getString(R.string.home_video_playback_settings), R.drawable.video_setting, true)
                HomeEntryKind.SettingsLanguage -> Triple(context.getString(R.string.home_language_settings), R.drawable.home_language, true)
                HomeEntryKind.SettingsLogout -> Triple(context.getString(R.string.action_logout), R.drawable.home_logout, true)
            }

        cardView.titleText = title
        cardView.contentText = card.subtitle
        cardView.mainImageView.setBackgroundColor(Color.parseColor("#2C2C2C"))
        if (isBanner) {
            cardView.mainImageView.scaleType = ImageView.ScaleType.FIT_CENTER
            cardView.mainImageView.setPadding(54, 30, 54, 30)
        } else {
            cardView.mainImageView.scaleType = ImageView.ScaleType.CENTER
            val pad = (22f * context.resources.displayMetrics.density).toInt()
            cardView.mainImageView.setPadding(pad, pad, pad, pad)
        }
        cardView.mainImage = ContextCompat.getDrawable(context, iconRes)
    }
}
