package com.nascabos.tv.modules.video.detail

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class VideoEpisodeGridUiState(
    val indexId: Int,
    val items: List<VideoEpisodeItem> = emptyList(),
    val pagination: VideoEpisodePagination = VideoEpisodePagedResult.empty.pagination,
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
)

class VideoEpisodeGridViewModel(
    app: Application,
    private val indexId: Int,
    private val discMode: Boolean,
) : AndroidViewModel(app) {
    private val _state = MutableStateFlow(VideoEpisodeGridUiState(indexId = indexId))
    val state: StateFlow<VideoEpisodeGridUiState> = _state.asStateFlow()

    private var page: Int = 1
    private val pageSize: Int = 60
    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null

    init {
        refresh(showLoading = true)
    }

    fun refresh(showLoading: Boolean) {
        if (indexId <= 0) return
        refreshJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                _state.update { it.copy(loading = showLoading, loadingMore = false) }
                page = 1
                val res =
                    withContext(Dispatchers.IO) {
                        if (discMode) {
                            val discItems =
                                runCatching { VideoDetailApiService.getDiscContents(indexId) }.getOrNull().orEmpty()
                            VideoEpisodePagedResult(
                                items =
                                    discItems.mapIndexed { idx, item ->
                                        VideoEpisodeItem(
                                            id = -(idx + 1),
                                            displayIndex = idx + 1,
                                            episodeNum = idx + 1,
                                            name = item.resolvedTitle.ifEmpty { item.resolvedInternalPath.ifEmpty { item.resolvedPath } },
                                            plot = "",
                                            fullPath = item.resolvedPath,
                                            internalPath = item.resolvedInternalPath,
                                            apiThumbPath =
                                                VideoDetailApiService.buildDiscContentThumbApiPath(
                                                    indexId = indexId,
                                                    internalPath = item.resolvedInternalPath,
                                                    size = 640,
                                                ),
                                            posterPath = "",
                                            fanartPath = "",
                                            logoPath = "",
                                            durationSeconds = item.durationSeconds,
                                            sizeBytes = item.sizeBytes,
                                        )
                                    },
                                pagination =
                                    VideoEpisodePagination(
                                        total = discItems.size,
                                        page = 1,
                                        limit = discItems.size.coerceAtLeast(1),
                                        totalPages = if (discItems.isEmpty()) 0 else 1,
                                        hasNextPage = false,
                                        hasPrevPage = false,
                                    ),
                            )
                        } else {
                            runCatching { VideoDetailApiService.getEpisodes(indexId = indexId, page = 1, pageSize = pageSize, sortOrder = "asc") }
                                .getOrNull()
                                ?: VideoEpisodePagedResult.empty
                        }
                    }
                val indexed =
                    res.items.mapIndexed { idx, e ->
                        e.copy(displayIndex = idx + 1)
                    }
                _state.update {
                    it.copy(
                        items = indexed,
                        pagination = res.pagination,
                        loading = false,
                        loadingMore = false,
                    )
                }
            }
    }

    fun loadMore() {
        val s = _state.value
        if (s.loading || s.loadingMore) return
        if (discMode) return
        if (!s.pagination.hasNextPage) return
        if (loadMoreJob?.isActive == true) return
        loadMoreJob =
            viewModelScope.launch {
                _state.update { it.copy(loadingMore = true) }
                val next = page + 1
                val res =
                    withContext(Dispatchers.IO) {
                        runCatching { VideoDetailApiService.getEpisodes(indexId = indexId, page = next, pageSize = pageSize, sortOrder = "asc") }
                            .getOrNull()
                            ?: VideoEpisodePagedResult.empty
                    }
                page = next
                val start = s.items.size
                val indexed =
                    res.items.mapIndexed { idx, e ->
                        e.copy(displayIndex = start + idx + 1)
                    }
                _state.update {
                    it.copy(
                        items = it.items + indexed,
                        pagination = res.pagination,
                        loadingMore = false,
                        loading = false,
                    )
                }
            }
    }
}
