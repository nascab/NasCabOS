package com.nascabos.tv.modules.video

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

internal val Context.videoPrefsDataStore by preferencesDataStore(name = "video_prefs")

class VideoListPrefsStore(
    private val appContext: Context,
) {
    private fun sortByKey(mediaType: String, listType: String) =
        if (listType.trim().lowercase() == "favorite") {
            stringPreferencesKey("video_favorite_list_sort_by_${mediaType.trim().lowercase()}")
        } else {
            stringPreferencesKey("video_list_sort_by_${mediaType.trim().lowercase()}")
        }

    private fun sortOrderKey(mediaType: String, listType: String) =
        if (listType.trim().lowercase() == "favorite") {
            stringPreferencesKey("video_favorite_list_sort_order_${mediaType.trim().lowercase()}")
        } else {
            stringPreferencesKey("video_list_sort_order_${mediaType.trim().lowercase()}")
        }

    fun sortFlow(mediaType: String, listType: String, default: VideoListSortState): Flow<VideoListSortState> {
        val byKey = sortByKey(mediaType, listType)
        val orderKey = sortOrderKey(mediaType, listType)
        return appContext.videoPrefsDataStore.data.map { prefs ->
            val byRaw = prefs[byKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val by = runCatching { VideoListSortBy.valueOf(byRaw) }.getOrNull() ?: default.by
            val order = runCatching { VideoListSortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            VideoListSortState(by = by, order = order)
        }
    }

    suspend fun setSort(mediaType: String, listType: String, state: VideoListSortState) {
        val byKey = sortByKey(mediaType, listType)
        val orderKey = sortOrderKey(mediaType, listType)
        appContext.videoPrefsDataStore.edit { prefs ->
            prefs[byKey] = state.by.name
            prefs[orderKey] = state.order.name
        }
    }
}
