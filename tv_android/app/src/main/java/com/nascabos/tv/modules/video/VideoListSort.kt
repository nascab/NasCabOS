package com.nascabos.tv.modules.video

enum class VideoListSortBy(val apiValue: String) {
    ViewTime("view_time"),
    CreateTime("create_time"),
    Year("year"),
    Score("score"),
    Name("name"),
}

enum class VideoListSortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class VideoListSortState(
    val by: VideoListSortBy,
    val order: VideoListSortOrder,
)

