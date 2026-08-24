package com.nascabos.tv.modules.video

data class VideoListItem(
    val id: Int,
    val mediaType: String,
    val path: String,
    val filename: String,
    val firstFilePath: String,
    val nfoName: String,
    val nfoYear: Int,
    val nfoScore: Double,
    val nfoRegions: String,
    val nfoGenres: String,
    val posterPath: String,
    val fanartPath: String,
    val logoPath: String,
    val progress: Double,
    val isFavorite: Boolean,
    val viewTime: String?,
    val createTime: String?,
    val fullPath: String,
)

data class VideoListPagination(
    val total: Int,
    val page: Int,
    val limit: Int,
    val totalPages: Int,
    val hasNextPage: Boolean,
    val hasPrevPage: Boolean,
) {
    companion object {
        val empty: VideoListPagination =
            VideoListPagination(
                total = 0,
                page = 1,
                limit = 30,
                totalPages = 0,
                hasNextPage = false,
                hasPrevPage = false,
            )
    }
}

data class VideoListPathItem(
    val path: String,
    val valid: Boolean,
)

data class VideoListPagedResult(
    val items: List<VideoListItem>,
    val pagination: VideoListPagination,
    val validPaths: List<VideoListPathItem>,
) {
    companion object {
        val empty: VideoListPagedResult =
            VideoListPagedResult(
                items = emptyList(),
                pagination = VideoListPagination.empty,
                validPaths = emptyList(),
            )
    }
}

data class VideoIndexCountResult(
    val movie: Int,
    val tv: Int,
    val total: Int,
)

enum class VideoLibraryKind {
    Album,
    SmartAlbum,
    Collection,
}

data class VideoLibraryPreviewItem(
    val fullPath: String,
    val firstFilePath: String,
    val mediaType: String,
)

data class VideoLibraryListItem(
    val id: Int,
    val kind: VideoLibraryKind,
    val name: String,
    val type: String,
    val createTime: String?,
    val previews: List<VideoLibraryPreviewItem> = emptyList(),
)

data class VideoLibraryPagination(
    val total: Int,
    val page: Int,
    val pageSize: Int,
) {
    val hasNextPage: Boolean get() = total > 0 && page > 0 && pageSize > 0 && (page * pageSize) < total
}

data class VideoLibraryPagedResult(
    val items: List<VideoLibraryListItem>,
    val pagination: VideoLibraryPagination,
) {
    companion object {
        val empty: VideoLibraryPagedResult =
            VideoLibraryPagedResult(
                items = emptyList(),
                pagination = VideoLibraryPagination(total = 0, page = 1, pageSize = 20),
            )
    }
}
