package com.nascabos.tv.modules.video

import android.app.Application
import android.util.Log
import android.widget.Toast
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nascabos.tv.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class VideoListUiState(
    val mediaType: String,
    val mediaTypeFilter: String = "all",
    val items: List<VideoListItem> = emptyList(),
    val pagination: VideoListPagination = VideoListPagination.empty,
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val searchText: String = "",
    val sort: VideoListSortState = VideoListSortState(VideoListSortBy.ViewTime, VideoListSortOrder.Desc),
    val availablePaths: List<VideoListPathItem> = emptyList(),
    val selectedPaths: Set<String> = emptySet(),
)

class VideoListViewModel(
    app: Application,
    private val initialMediaType: String,
    listType: String = "",
    private val albumId: Int? = null,
    private val collectionId: Int? = null,
    private val smartAlbumId: Int? = null,
) : AndroidViewModel(app) {
    private val prefsStore = VideoListPrefsStore(app.applicationContext)
    private val mediaType = initialMediaType.trim().lowercase()
    private val listTypeNormalized = listType.trim().lowercase()
    private val isHistoryList: Boolean = listTypeNormalized == "history"
    private val defaultSort: VideoListSortState =
        when {
            isHistoryList -> VideoListSortState(VideoListSortBy.ViewTime, VideoListSortOrder.Desc)
            listTypeNormalized == "favorite" -> VideoListSortState(VideoListSortBy.CreateTime, VideoListSortOrder.Desc)
            else -> VideoListSortState(VideoListSortBy.ViewTime, VideoListSortOrder.Desc)
        }
    private val fixedMediaType: String? =
        when (mediaType) {
            "movie",
            "tv",
            -> mediaType
            else -> null
        }

    private val _state =
        MutableStateFlow(
            VideoListUiState(
                mediaType = mediaType,
                mediaTypeFilter = fixedMediaType ?: "all",
                sort = defaultSort,
            ),
        )
    val state: StateFlow<VideoListUiState> = _state.asStateFlow()

    private var page: Int = 1
    private val pageSize: Int = 30
    private var sortLoadedOnce: Boolean = false
    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null
    private var historyItems: List<VideoListItem> = emptyList()

    init {
        if (isHistoryList) {
            refresh(showLoading = true)
        } else {
            viewModelScope.launch {
                prefsStore.sortFlow(mediaType, listTypeNormalized, default = _state.value.sort).collectLatest { sort ->
                    val prev = _state.value.sort
                    _state.update { it.copy(sort = sort) }
                    val wasLoaded = sortLoadedOnce
                    sortLoadedOnce = true
                    if (!wasLoaded) {
                        refresh(showLoading = true)
                    } else if (prev != sort) {
                        refresh(showLoading = true)
                    }
                }
            }
        }
    }

    fun refresh(showLoading: Boolean) {
        refreshJob?.cancel()
        refreshJob =
            viewModelScope.launch {
            val s = _state.value
            val effectiveMediaType = fixedMediaType ?: s.mediaTypeFilter
            Log.d(
                "VideoListViewModel",
                "refresh mt=$effectiveMediaType loading=$showLoading search='${s.searchText}' sort=${s.sort.by}/${s.sort.order} sources=${s.selectedPaths.size}",
            )
            _state.update { it.copy(loading = showLoading, loadingMore = false) }
            page = 1
            if (isHistoryList) {
                if (historyItems.isEmpty()) {
                    historyItems =
                        withContext(Dispatchers.IO) {
                            VideoListApiService.listHistory()
                        }
                }
                val filtered = applyHistoryFilters(historyItems, _state.value)
                _state.update {
                    it.copy(
                        items = filtered,
                        pagination =
                            VideoListPagination(
                                total = filtered.size,
                                page = 1,
                                limit = filtered.size.coerceAtLeast(1),
                                totalPages = if (filtered.isEmpty()) 0 else 1,
                                hasNextPage = false,
                                hasPrevPage = false,
                            ),
                        loading = false,
                        loadingMore = false,
                    )
                }
                Log.d("VideoListViewModel", "refresh done (history) items=${filtered.size}")
                return@launch
            }

            val res =
                runCatching {
                    withContext(Dispatchers.IO) {
                        VideoListApiService.listPaged(
                            page = page,
                            pageSize = pageSize,
                            mediaType = effectiveMediaType,
                            search = _state.value.searchText,
                            sourceList = _state.value.selectedPaths.toList().ifEmpty { null },
                            sort = _state.value.sort,
                            listType = listTypeNormalized.ifEmpty { null },
                            albumId = albumId,
                            collectionId = collectionId,
                            smartAlbumId = smartAlbumId,
                        )
                    }
                }.getOrNull()
            if (res == null) {
                _state.update { it.copy(loading = false, loadingMore = false) }
                Log.d("VideoListViewModel", "refresh failed")
                Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                return@launch
            }
            _state.update {
                it.copy(
                    items = res.items,
                    pagination = res.pagination,
                    availablePaths = if (res.validPaths.isNotEmpty()) res.validPaths else it.availablePaths,
                    loading = false,
                    loadingMore = false,
                )
            }
            Log.d("VideoListViewModel", "refresh done items=${res.items.size} hasNext=${res.pagination.hasNextPage}")
            }
    }

    fun loadMore() {
        if (isHistoryList) return
        val s = _state.value
        if (s.loading || s.loadingMore) return
        if (!s.pagination.hasNextPage) return
        if (loadMoreJob?.isActive == true) return
        loadMoreJob =
            viewModelScope.launch {
            val effectiveMediaType = fixedMediaType ?: _state.value.mediaTypeFilter
            _state.update { it.copy(loadingMore = true) }
            val next = page + 1
            val res =
                runCatching {
                    withContext(Dispatchers.IO) {
                        VideoListApiService.listPaged(
                            page = next,
                            pageSize = pageSize,
                            mediaType = effectiveMediaType,
                            search = _state.value.searchText,
                            sourceList = _state.value.selectedPaths.toList().ifEmpty { null },
                            sort = _state.value.sort,
                            listType = listTypeNormalized.ifEmpty { null },
                            albumId = albumId,
                            collectionId = collectionId,
                            smartAlbumId = smartAlbumId,
                        )
                    }
                }.getOrNull()
            if (res == null) {
                _state.update { it.copy(loadingMore = false, loading = false) }
                Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                return@launch
            }
            page = next
            _state.update {
                it.copy(
                    items = it.items + res.items,
                    pagination = res.pagination,
                    loadingMore = false,
                    loading = false,
                )
            }
            }
    }

    private fun applyHistoryFilters(items: List<VideoListItem>, state: VideoListUiState): List<VideoListItem> {
        return items.sortedByDescending { it.viewTime.orEmpty() }
    }

    private fun historyPathMatches(itemPath: String, selectedPath: String): Boolean {
        val base = selectedPath.trim().trimEnd('/', '\\')
        if (base.isEmpty()) return false
        if (itemPath == base) return true
        return itemPath.startsWith("$base/") || itemPath.startsWith("$base\\")
    }

    fun setSearch(text: String) {
        if (isHistoryList) return
        val normalized = text.trim()
        if (_state.value.searchText == normalized) return
        Log.d("VideoListViewModel", "setSearch '$normalized'")
        _state.update { it.copy(searchText = normalized) }
        refresh(showLoading = true)
    }

    fun clearSearch() {
        if (isHistoryList) return
        if (_state.value.searchText.isNotEmpty()) {
            Log.d("VideoListViewModel", "clearSearch")
            _state.update { it.copy(searchText = "") }
        }
        refresh(showLoading = true)
    }

    fun setSort(sort: VideoListSortState) {
        if (isHistoryList) return
        if (_state.value.sort == sort) return
        Log.d("VideoListViewModel", "setSort ${sort.by}/${sort.order}")
        _state.update { it.copy(sort = sort) }
        refresh(showLoading = true)
        viewModelScope.launch { prefsStore.setSort(mediaType, listTypeNormalized, sort) }
    }

    fun toggleSourcePath(path: String) {
        if (isHistoryList) return
        val p = path.trim()
        if (p.isEmpty()) return
        _state.update { s ->
            val set = s.selectedPaths.toMutableSet()
            if (set.contains(p)) set.remove(p) else set.add(p)
            s.copy(selectedPaths = set)
        }
        refresh(showLoading = true)
    }

    fun clearSourcePaths() {
        if (isHistoryList) return
        if (_state.value.selectedPaths.isEmpty()) return
        _state.update { it.copy(selectedPaths = emptySet()) }
        refresh(showLoading = true)
    }

    fun setSourcePaths(paths: Set<String>) {
        if (isHistoryList) return
        val normalized =
            paths
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .toSet()
        if (_state.value.selectedPaths == normalized) return
        _state.update { it.copy(selectedPaths = normalized) }
        refresh(showLoading = true)
    }

    fun setMediaTypeFilter(filter: String) {
        if (isHistoryList) return
        if (fixedMediaType != null) return
        val normalized =
            when (filter.trim().lowercase()) {
                "movie" -> "movie"
                "tv" -> "tv"
                else -> "all"
            }
        if (_state.value.mediaTypeFilter == normalized) return
        _state.update { it.copy(mediaTypeFilter = normalized) }
        refresh(showLoading = true)
    }
}
