package com.nascabos.tv.modules.photo.library

enum class PhotoLibraryKind {
    Album,
    SmartAlbum,
    Collection,
}

data class PhotoLibraryPreviewItem(
    val fullPath: String,
    val type: Int,
    val duration: Int,
)

data class PhotoLibraryListItem(
    val id: Int,
    val kind: PhotoLibraryKind,
    val name: String,
    val type: String,
    val createTime: String?,
    val isOwner: Boolean? = null,
    val isPublic: Boolean? = null,
    val previews: List<PhotoLibraryPreviewItem> = emptyList(),
)

data class PhotoLibraryPagination(
    val total: Int,
    val page: Int,
    val pageSize: Int,
) {
    val hasNextPage: Boolean get() = total > 0 && page > 0 && pageSize > 0 && (page * pageSize) < total
}

data class PhotoLibraryPagedResult(
    val items: List<PhotoLibraryListItem>,
    val pagination: PhotoLibraryPagination,
) {
    companion object {
        val empty: PhotoLibraryPagedResult =
            PhotoLibraryPagedResult(
                items = emptyList(),
                pagination = PhotoLibraryPagination(total = 0, page = 1, pageSize = 20),
            )
    }
}

