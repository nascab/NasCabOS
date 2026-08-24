package com.nascabos.tv.modules.photo.library

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

internal val Context.photoPrefsDataStore by preferencesDataStore(name = "photo_prefs")

class PhotoLibraryPrefsStore(
    private val appContext: Context,
) {
    private fun sortFieldKey(kind: PhotoLibraryKind) = stringPreferencesKey("photo_library_sort_field_${kind.name.lowercase()}")
    private fun sortOrderKey(kind: PhotoLibraryKind) = stringPreferencesKey("photo_library_sort_order_${kind.name.lowercase()}")

    fun sortFlow(kind: PhotoLibraryKind, default: PhotoLibrarySortState): Flow<PhotoLibrarySortState> {
        val fieldKey = sortFieldKey(kind)
        val orderKey = sortOrderKey(kind)
        return appContext.photoPrefsDataStore.data.map { prefs ->
            val fieldRaw = prefs[fieldKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val field = runCatching { PhotoLibrarySortField.valueOf(fieldRaw) }.getOrNull() ?: default.field
            val order = runCatching { PhotoLibrarySortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            PhotoLibrarySortState(field = field, order = order)
        }
    }

    suspend fun setSort(kind: PhotoLibraryKind, state: PhotoLibrarySortState) {
        val fieldKey = sortFieldKey(kind)
        val orderKey = sortOrderKey(kind)
        appContext.photoPrefsDataStore.edit { prefs ->
            prefs[fieldKey] = state.field.name
            prefs[orderKey] = state.order.name
        }
    }
}

