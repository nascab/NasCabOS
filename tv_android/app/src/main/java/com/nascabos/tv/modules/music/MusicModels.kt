package com.nascabos.tv.modules.music

data class MusicListItem(
    val id: Int,
    val path: String,
    val filename: String,
    val fileHash: String,
    val title: String,
    val artist: String,
    val album: String,
    val year: String,
    val genre: String,
    val duration: Int,
    val size: Long,
    val ext: String,
    val hasInnerCover: Int,
    val showType: String,
    val musicCount: Int,
    val isFavorite: Boolean,
    val isFromFile: Boolean,
    val ctime: String?,
    val mtime: String?,
    val birthtime: String?,
    val firstFilePath: String,
    val fullPath: String,
    val bitrate: Int?,
    val sampleRate: Int?,
    val bitDepth: Int?,
) {
    val isFolder: Boolean
        get() {
            val t = showType.trim().lowercase()
            return t == "folder" || t == "series"
        }

    val displayTitle: String
        get() {
            val n = filename.trim()
            return n.ifEmpty { title.trim() }
        }

    val displaySubtitle: String
        get() {
            val a = artist.trim()
            val al = album.trim()
            return when {
                a.isNotEmpty() && al.isNotEmpty() -> "$a · $al"
                a.isNotEmpty() -> a
                al.isNotEmpty() -> al
                else -> ""
            }
        }

    fun resolvePlayablePath(): String {
        val full = fullPath.trim()
        if (full.isNotEmpty()) return full
        val base = path.trim().trimEnd('/')
        val name = filename.trim()
        if (base.isNotEmpty() && name.isNotEmpty()) return "$base/$name"
        return base.ifEmpty { name }
    }
}

data class MusicListPathItem(
    val path: String,
    val valid: Boolean,
)

data class MusicListPagination(
    val total: Int,
    val page: Int,
    val limit: Int,
    val totalPages: Int,
    val hasNextPage: Boolean,
    val hasPrevPage: Boolean,
) {
    companion object {
        val empty =
            MusicListPagination(
                total = 0,
                page = 1,
                limit = 30,
                totalPages = 0,
                hasNextPage = false,
                hasPrevPage = false,
            )
    }
}

data class MusicListPagedResult(
    val items: List<MusicListItem>,
    val pagination: MusicListPagination,
    val validPaths: List<MusicListPathItem>,
) {
    companion object {
        val empty = MusicListPagedResult(items = emptyList(), pagination = MusicListPagination.empty, validPaths = emptyList())
    }
}

enum class MusicListSortBy(val apiValue: String) {
    Filename("filename"),
    Title("title"),
    Artist("artist"),
    Album("album"),
    Year("year"),
    Duration("duration"),
    Ctime("ctime"),
    Mtime("mtime"),
    FavoriteTime("favoriteTime"),
}

enum class MusicListSortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class MusicListSortState(
    val by: MusicListSortBy,
    val order: MusicListSortOrder,
)

data class MusicGroupItem(
    val keyType: String,
    val name: String,
    val firstFilePath: String,
    val indexCount: Int,
) {
    val isAlbum: Boolean get() = keyType.trim().lowercase() == "album"
    val isArtist: Boolean get() = keyType.trim().lowercase() == "artist"
}

data class MusicGroupPagedResult(
    val items: List<MusicGroupItem>,
    val pagination: MusicListPagination,
    val validPaths: List<MusicListPathItem>,
) {
    companion object {
        val empty = MusicGroupPagedResult(items = emptyList(), pagination = MusicListPagination.empty, validPaths = emptyList())
    }
}

enum class MusicGroupSortBy(val apiValue: String) {
    Count("count"),
    Name("name"),
}

enum class MusicGroupSortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class MusicGroupSortState(
    val by: MusicGroupSortBy,
    val order: MusicGroupSortOrder,
)

data class MusicPlaylistItem(
    val id: Int,
    val uid: Int,
    val name: String,
    val createTime: String,
    val previews: List<MusicListItem>,
)

data class MusicPlaylistPagedResult(
    val items: List<MusicPlaylistItem>,
    val pagination: MusicListPagination,
) {
    companion object {
        val empty = MusicPlaylistPagedResult(items = emptyList(), pagination = MusicListPagination.empty)
    }
}

enum class MusicPlaylistSortBy(val apiValue: String) {
    CreateTime("create_time"),
    Name("name"),
}

enum class MusicPlaylistSortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class MusicPlaylistSortState(
    val by: MusicPlaylistSortBy,
    val order: MusicPlaylistSortOrder,
)

