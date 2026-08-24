package com.nascabos.tv.modules.video.detail

data class VideoHistory(
    val playbackPositionSeconds: Int,
    val durationSeconds: Int,
    val lastWatchedAt: String?,
    val episodeNum: Int?,
) {
    val hasProgress: Boolean get() = playbackPositionSeconds > 0 && durationSeconds > 0
}

data class VideoPerson(
    val name: String,
    val role: String,
    val tmdbId: String,
    val thumb: String,
)

data class VideoDetailItem(
    val id: Int,
    val mediaType: String,
    val isFile: Boolean,
    val path: String,
    val filename: String,
    val fullPath: String,
    val playFilePath: String,
    val firstFilePath: String,
    val posterPath: String,
    val fanartPath: String,
    val logoPath: String,
    val nfoName: String,
    val nfoPlot: String,
    val nfoYear: Int,
    val nfoRegions: String,
    val nfoGenres: String,
    val durationSeconds: Int,
    val sizeBytes: Long,
    val seasonCount: Int,
    val episodeCount: Int,
    val isFavorite: Boolean,
    val directors: List<VideoPerson>,
    val actors: List<VideoPerson>,
) {
    val displayTitle: String get() = nfoName.trim().ifEmpty { filename.trim() }
}

data class VideoDetailData(
    val item: VideoDetailItem,
    val seasonList: List<VideoSeasonItem>,
    val discContents: List<VideoDiscContentItem>,
    val history: VideoHistory?,
)

data class VideoSeasonItem(
    val id: Int,
    val name: String,
    val posterPath: String,
    val fanartPath: String,
    val logoPath: String,
    val firstFilePath: String,
)

data class VideoEpisodeItem(
    val id: Int,
    val displayIndex: Int,
    val episodeNum: Int,
    val name: String,
    val plot: String,
    val fullPath: String,
    val internalPath: String,
    val apiThumbPath: String,
    val posterPath: String,
    val fanartPath: String,
    val logoPath: String,
    val durationSeconds: Int,
    val sizeBytes: Long,
)

data class VideoDiscPlaylistItem(
    val path: String,
    val internalPath: String,
)

data class VideoDiscContentItem(
    val path: String,
    val internalPath: String,
    val thumbnailPath: String,
    val thumbnailInternalPath: String,
    val title: String,
    val displayName: String,
    val durationSeconds: Int,
    val sizeBytes: Long,
    val playlist: List<VideoDiscPlaylistItem>,
) {
    val resolvedPath: String
        get() = path.trim().ifEmpty { playlist.firstOrNull()?.path.orEmpty() }

    val resolvedInternalPath: String
        get() = internalPath.trim().ifEmpty { playlist.firstOrNull()?.internalPath.orEmpty() }

    val resolvedThumbnailPath: String
        get() = thumbnailPath.trim()

    val resolvedThumbnailInternalPath: String
        get() = thumbnailInternalPath.trim().ifEmpty { resolvedInternalPath }

    val resolvedTitle: String
        get() = title.trim().ifEmpty { displayName.trim() }
}

data class VideoEpisodePagination(
    val total: Int,
    val page: Int,
    val limit: Int,
    val totalPages: Int,
    val hasNextPage: Boolean,
    val hasPrevPage: Boolean,
)

data class VideoEpisodePagedResult(
    val items: List<VideoEpisodeItem>,
    val pagination: VideoEpisodePagination,
) {
    companion object {
        val empty: VideoEpisodePagedResult =
            VideoEpisodePagedResult(
                items = emptyList(),
                pagination =
                    VideoEpisodePagination(
                        total = 0,
                        page = 1,
                        limit = 50,
                        totalPages = 0,
                        hasNextPage = false,
                        hasPrevPage = false,
                    ),
            )
    }
}
