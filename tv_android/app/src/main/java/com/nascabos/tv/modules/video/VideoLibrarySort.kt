package com.nascabos.tv.modules.video

enum class VideoLibrarySortField(val apiValue: String) {
    CreateTime("create_time"),
    Name("name"),
}

enum class VideoLibrarySortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class VideoLibrarySortState(
    val field: VideoLibrarySortField,
    val order: VideoLibrarySortOrder,
)

