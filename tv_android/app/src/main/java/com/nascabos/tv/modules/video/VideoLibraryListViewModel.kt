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

data class VideoLibraryUiState(
    val kind: VideoLibraryKind,
    val items: List<VideoLibraryListItem> = emptyList(),
    val pagination: VideoLibraryPagination = VideoLibraryPagination(total = 0, page = 1, pageSize = 20),
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val keyword: String = "",
    val sort: VideoLibrarySortState = VideoLibrarySortState(VideoLibrarySortField.CreateTime, VideoLibrarySortOrder.Desc),
)

class VideoLibraryListViewModel(
    app: Application,
    private val kind: VideoLibraryKind,
) : AndroidViewModel(app) {
    private val prefsStore = VideoLibraryPrefsStore(app.applicationContext)

    private val _state =
        MutableStateFlow(
            VideoLibraryUiState(
                kind = kind,
                sort = VideoLibrarySortState(VideoLibrarySortField.CreateTime, VideoLibrarySortOrder.Desc),
            ),
        )
    val state: StateFlow<VideoLibraryUiState> = _state.asStateFlow()

    private var page: Int = 1
    private val pageSize: Int = 20
    private var sortLoadedOnce: Boolean = false
    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null

    init {
        viewModelScope.launch {
            prefsStore.sortFlow(kind, default = _state.value.sort).collectLatest { sort ->
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

    fun refresh(showLoading: Boolean) {
        refreshJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                val s = _state.value
                Log.d("VideoLibraryListVM", "refresh kind=${kind.name} loading=$showLoading keyword='${s.keyword}' sort=${s.sort.field}/${s.sort.order}")
                _state.update { it.copy(loading = showLoading, loadingMore = false) }
                page = 1
                try {
                    val res =
                        withContext(Dispatchers.IO) {
                            VideoLibraryApiService.listPaged(
                                kind = kind,
                                page = page,
                                pageSize = pageSize,
                                keyword = _state.value.keyword,
                                sortField = _state.value.sort.field,
                                sortOrder = _state.value.sort.order,
                            )
                        }
                    _state.update {
                        it.copy(
                            items = res.items,
                            pagination = res.pagination,
                            loading = false,
                            loadingMore = false,
                        )
                    }
                } catch (e: Exception) {
                    Log.e("VideoLibraryListVM", "refresh failed", e)
                    _state.update { it.copy(loading = false, loadingMore = false) }
                    Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                }
            }
    }

    fun loadMore() {
        val s = _state.value
        if (s.loading || s.loadingMore) return
        if (!s.pagination.hasNextPage) return
        if (loadMoreJob?.isActive == true) return
        loadMoreJob =
            viewModelScope.launch {
                _state.update { it.copy(loadingMore = true) }
                val next = page + 1
                try {
                    val res =
                        withContext(Dispatchers.IO) {
                            VideoLibraryApiService.listPaged(
                                kind = kind,
                                page = next,
                                pageSize = pageSize,
                                keyword = _state.value.keyword,
                                sortField = _state.value.sort.field,
                                sortOrder = _state.value.sort.order,
                            )
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
                } catch (e: Exception) {
                    Log.e("VideoLibraryListVM", "loadMore failed", e)
                    _state.update { it.copy(loadingMore = false, loading = false) }
                    Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                }
            }
    }

    fun setKeyword(text: String) {
        val normalized = text.trim()
        if (_state.value.keyword == normalized) return
        _state.update { it.copy(keyword = normalized) }
        refresh(showLoading = true)
    }

    fun clearKeyword() {
        if (_state.value.keyword.isNotEmpty()) {
            _state.update { it.copy(keyword = "") }
        }
        refresh(showLoading = true)
    }

    fun setSort(sort: VideoLibrarySortState) {
        if (_state.value.sort == sort) return
        _state.update { it.copy(sort = sort) }
        refresh(showLoading = true)
        viewModelScope.launch { prefsStore.setSort(kind, sort) }
    }
}

