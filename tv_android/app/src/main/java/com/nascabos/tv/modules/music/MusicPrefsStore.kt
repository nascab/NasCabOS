package com.nascabos.tv.modules.music

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

internal val Context.musicPrefsDataStore by preferencesDataStore(name = "music_prefs")

class MusicPrefsStore(
    private val appContext: Context,
) {
    private fun trackSortByKey(scope: String) = stringPreferencesKey("music_track_sort_by_${scope.lowercase()}")
    private fun trackSortOrderKey(scope: String) = stringPreferencesKey("music_track_sort_order_${scope.lowercase()}")
    private fun groupSortByKey(scope: String) = stringPreferencesKey("music_group_sort_by_${scope.lowercase()}")
    private fun groupSortOrderKey(scope: String) = stringPreferencesKey("music_group_sort_order_${scope.lowercase()}")
    private fun playlistSortByKey() = stringPreferencesKey("music_playlist_sort_by")
    private fun playlistSortOrderKey() = stringPreferencesKey("music_playlist_sort_order")

    fun trackSortFlow(scope: String, default: MusicListSortState): Flow<MusicListSortState> {
        val byKey = trackSortByKey(scope)
        val orderKey = trackSortOrderKey(scope)
        return appContext.musicPrefsDataStore.data.map { prefs ->
            val byRaw = prefs[byKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val by = runCatching { MusicListSortBy.valueOf(byRaw) }.getOrNull() ?: default.by
            val order = runCatching { MusicListSortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            MusicListSortState(by = by, order = order)
        }
    }

    suspend fun setTrackSort(scope: String, state: MusicListSortState) {
        val byKey = trackSortByKey(scope)
        val orderKey = trackSortOrderKey(scope)
        appContext.musicPrefsDataStore.edit { prefs ->
            prefs[byKey] = state.by.name
            prefs[orderKey] = state.order.name
        }
    }

    fun groupSortFlow(scope: String, default: MusicGroupSortState): Flow<MusicGroupSortState> {
        val byKey = groupSortByKey(scope)
        val orderKey = groupSortOrderKey(scope)
        return appContext.musicPrefsDataStore.data.map { prefs ->
            val byRaw = prefs[byKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val by = runCatching { MusicGroupSortBy.valueOf(byRaw) }.getOrNull() ?: default.by
            val order = runCatching { MusicGroupSortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            MusicGroupSortState(by = by, order = order)
        }
    }

    suspend fun setGroupSort(scope: String, state: MusicGroupSortState) {
        val byKey = groupSortByKey(scope)
        val orderKey = groupSortOrderKey(scope)
        appContext.musicPrefsDataStore.edit { prefs ->
            prefs[byKey] = state.by.name
            prefs[orderKey] = state.order.name
        }
    }

    fun playlistSortFlow(default: MusicPlaylistSortState): Flow<MusicPlaylistSortState> {
        val byKey = playlistSortByKey()
        val orderKey = playlistSortOrderKey()
        return appContext.musicPrefsDataStore.data.map { prefs ->
            val byRaw = prefs[byKey]?.trim().orEmpty()
            val orderRaw = prefs[orderKey]?.trim().orEmpty()
            val by = runCatching { MusicPlaylistSortBy.valueOf(byRaw) }.getOrNull() ?: default.by
            val order = runCatching { MusicPlaylistSortOrder.valueOf(orderRaw) }.getOrNull() ?: default.order
            MusicPlaylistSortState(by = by, order = order)
        }
    }

    suspend fun setPlaylistSort(state: MusicPlaylistSortState) {
        val byKey = playlistSortByKey()
        val orderKey = playlistSortOrderKey()
        appContext.musicPrefsDataStore.edit { prefs ->
            prefs[byKey] = state.by.name
            prefs[orderKey] = state.order.name
        }
    }
}

