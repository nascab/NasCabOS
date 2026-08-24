package com.nascabos.tv.modules.photo.timeline

data class PhotoTimelineDateItem(
    val originalDate: String,
    val count: Int,
)

data class PhotoTimelinePhotoItem(
    val id: Int,
    val path: String,
    val filename: String,
    val size: Int,
    val isLvp: Int,
    val type: Int,
    val width: Int,
    val height: Int,
    val originalDate: String,
    val originalTime: String,
    val fullPath: String,
    val duration: Int,
    val fileHash: String,
    val isFavorite: Boolean,
    val liveFilename: String,
    val rawFilename: String,
    val rawShowExt: String,
)

data class PhotoTimelineDateInfo(
    val originalDate: String,
    val geo: String,
    val camera: String,
)

data class PhotoTimelineYearItem(
    val year: Int,
    val count: Int,
    val cover: PhotoTimelinePhotoItem,
)

data class PhotoTimelinePathItem(
    val path: String,
    val valid: Boolean,
)

data class PhotoTimelineDateListResult(
    val items: List<PhotoTimelineDateItem>,
    val validPaths: List<PhotoTimelinePathItem>,
)

data class PhotoTimelinePhotoListResult(
    val photoList: List<PhotoTimelinePhotoItem>,
    val dateInfoList: List<PhotoTimelineDateInfo>,
)

data class PhotoTimelineYearListResult(
    val items: List<PhotoTimelineYearItem>,
)

