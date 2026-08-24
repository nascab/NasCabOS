package com.nascabos.tv.modules.video

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class VideoLibraryPrefsStore(
    private val appContext: Context,
) {
    private fun sortFieldKey(kind: VideoLibraryKind) = stringPreferencesKey("video_library_sort_field_${kind.name.lowercase()}")
    private fun sortOrderKey(kind: VideoLibraryKind) = stringPreferencesKey("video_library_sort_order_${kind.name.lowercase()}")

    fun sortFlow(kind: VideoLibraryKind, default: VideoLibrarySortState): Flow<VideoLibrarySortState> {
        val fieldKey = sortFieldKey(kind)
        val orderKey = sortOrderKey(kind)
        return appContext.videoPrefsDataStore.data.map { prefs ->
            val fieldRaw = prefs[fieldKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val field = runCatching { VideoLibrarySortField.valueOf(fieldRaw) }.getOrNull() ?: default.field
            val order = runCatching { VideoLibrarySortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            VideoLibrarySortState(field = field, order = order)
        }
    }

    suspend fun setSort(kind: VideoLibraryKind, state: VideoLibrarySortState) {
        val fieldKey = sortFieldKey(kind)
        val orderKey = sortOrderKey(kind)
        appContext.videoPrefsDataStore.edit { prefs ->
            prefs[fieldKey] = state.field.name
            prefs[orderKey] = state.order.name
        }
    }
}

