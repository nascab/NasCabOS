package com.nascabos.tv.modules.photo.timeline

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

internal val Context.photoPreviewPrefsDataStore by preferencesDataStore(name = "photo_preview_prefs")

data class PhotoPreviewPrefsState(
    val autoPlayIntervalSeconds: Int,
)

class PhotoPreviewPrefsStore(
    private val appContext: Context,
) {
    private val keyAutoPlayInterval = intPreferencesKey("photo_preview_auto_play_interval_seconds")

    val stateFlow: Flow<PhotoPreviewPrefsState> =
        appContext.photoPreviewPrefsDataStore.data.map { prefs ->
            PhotoPreviewPrefsState(
                autoPlayIntervalSeconds = (prefs[keyAutoPlayInterval] ?: 5).coerceIn(2, 60),
            )
        }

    suspend fun setAutoPlayIntervalSeconds(seconds: Int) {
        appContext.photoPreviewPrefsDataStore.edit { prefs ->
            prefs[keyAutoPlayInterval] = seconds.coerceIn(2, 60)
        }
    }
}
