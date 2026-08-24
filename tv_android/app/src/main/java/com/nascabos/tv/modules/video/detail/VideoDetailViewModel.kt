package com.nascabos.tv.modules.video.detail

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.modules.video_player.TvPlaylistItem
import com.nascabos.tv.modules.video_player.TvVideoPlayerActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class VideoDetailUiState(
    val indexId: Int,
    val loading: Boolean = false,
    val data: VideoDetailData? = null,
)

class VideoDetailViewModel(
    app: Application,
    private val indexId: Int,
) : AndroidViewModel(app) {
    private val _state = MutableStateFlow(VideoDetailUiState(indexId = indexId, loading = false))
    val state: StateFlow<VideoDetailUiState> = _state.asStateFlow()

    private var refreshJob: Job? = null

    init {
        refresh(showLoading = true)
    }

    private fun isDiscStructure(mediaType: String): Boolean {
        val mt = mediaType.trim().lowercase()
        return mt == "bdmv" || mt == "video_ts"
    }

    fun refresh(showLoading: Boolean) {
        if (indexId <= 0) return
        refreshJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                _state.update { it.copy(loading = showLoading) }
                val detail =
                    withContext(Dispatchers.IO) {
                        runCatching { VideoDetailApiService.getDetail(indexId) }.getOrNull()
                            ?.let { data ->
                                if (!isDiscStructure(data.item.mediaType)) {
                                    data
                                } else {
                                    val discContents =
                                        runCatching { VideoDetailApiService.getDiscContents(indexId) }.getOrNull()
                                            ?: data.discContents
                                    data.copy(discContents = discContents)
                                }
                            }
                    }
                _state.update { it.copy(data = detail, loading = false) }
            }
    }

    fun toggleFavorite() {
        val item = _state.value.data?.item ?: return
        viewModelScope.launch {
            val ok =
                withContext(Dispatchers.IO) {
                    runCatching { VideoDetailApiService.setFavorite(item.id, favorite = !item.isFavorite) }.getOrNull() == true
                }
            if (ok) refresh(showLoading = false)
        }
    }

    fun scanChanges() {
        val item = _state.value.data?.item ?: return
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                runCatching { VideoDetailApiService.scanIndex(item.id) }.getOrNull()
            }
        }
    }

    fun deleteItem(onDone: (Boolean) -> Unit) {
        val item = _state.value.data?.item ?: return
        viewModelScope.launch {
            val ok =
                withContext(Dispatchers.IO) {
                    runCatching { VideoDetailApiService.deleteByPath(item.fullPath) }.getOrNull() == true
                }
            onDone(ok)
        }
    }

    fun buildPlayIntent(onReady: (Intent?) -> Unit) {
        val data = _state.value.data ?: return onReady(null)
        val item = data.item
        viewModelScope.launch {
            val (playlist, initialIndex) =
                if (isDiscStructure(item.mediaType)) {
                    val discPlaylist =
                        data.discContents.map {
                            TvPlaylistItem(
                                path = it.resolvedPath,
                                name = it.resolvedTitle,
                                internalPath = it.resolvedInternalPath,
                            )
                        }.filter { it.path.trim().isNotEmpty() }
                    if (discPlaylist.isNotEmpty()) {
                        discPlaylist to 0
                    } else {
                        val p = item.playFilePath.trim().ifEmpty { item.fullPath.trim() }
                        if (p.isEmpty()) emptyList<TvPlaylistItem>() to 0 else listOf(TvPlaylistItem(path = p, name = item.displayTitle)) to 0
                    }
                } else if (item.isFile) {
                    val p = item.fullPath.trim()
                    if (p.isEmpty()) {
                        emptyList<TvPlaylistItem>() to 0
                    } else {
                        listOf(TvPlaylistItem(path = p, name = item.filename.trim())) to 0
                    }
                } else {
                    withContext(Dispatchers.IO) {
                        runCatching { VideoDetailApiService.getTvPlayInfo(item.id) }.getOrNull()
                            ?: (emptyList<TvPlaylistItem>() to 0)
                    }
                }

            if (playlist.isEmpty()) {
                onReady(null)
                return@launch
            }

            if (ApiController.isP2pMode) {
                val ready = withContext(Dispatchers.IO) {
                    ApiController.ensureP2pPlaybackReady(timeoutMs = 15_000)
                }
                if (!ready) {
                    onReady(null)
                    return@launch
                }
            }

            val intent =
                TvVideoPlayerActivity.newIntent(
                    context = getApplication(),
                    playlist = playlist,
                    initialIndex = initialIndex.coerceIn(0, (playlist.size - 1).coerceAtLeast(0)),
                    title = item.displayTitle,
                    ignoreFindSub = 0,
                )
            Log.d("VideoDetailVM", "open internal player, items=${playlist.size}, idx=$initialIndex")
            onReady(intent)
        }
    }
}
