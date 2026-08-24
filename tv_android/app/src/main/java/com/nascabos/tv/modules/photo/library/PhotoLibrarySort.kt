package com.nascabos.tv.modules.photo.library

enum class PhotoLibrarySortField(val apiValue: String) {
    CreateTime("create_time"),
    Name("name"),
}

enum class PhotoLibrarySortOrder(val apiValue: String) {
    Asc("asc"),
    Desc("desc"),
}

data class PhotoLibrarySortState(
    val field: PhotoLibrarySortField,
    val order: PhotoLibrarySortOrder,
)

