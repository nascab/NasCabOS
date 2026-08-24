package com.nascabos.tv.modules.music

import android.app.Application
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

data class MusicPlaylistUiState(
    val title: String,
    val items: List<MusicPlaylistItem> = emptyList(),
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val hasMore: Boolean = true,
    val searchText: String = "",
    val sort: MusicPlaylistSortState,
)

class MusicPlaylistListViewModel(
    app: Application,
    private val titleText: String,
) : AndroidViewModel(app) {
    private val prefsStore = MusicPrefsStore(app.applicationContext)
    private val defaultSort = MusicPlaylistSortState(MusicPlaylistSortBy.CreateTime, MusicPlaylistSortOrder.Desc)

    private val _state =
        MutableStateFlow(
            MusicPlaylistUiState(
                title = titleText,
                sort = defaultSort,
            ),
        )
    val state: StateFlow<MusicPlaylistUiState> = _state.asStateFlow()

    private var page: Int = 1
    private val pageSize: Int = 30
    private var sortLoadedOnce: Boolean = false
    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null

    init {
        viewModelScope.launch {
            prefsStore.playlistSortFlow(default = _state.value.sort).collectLatest { sort ->
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

    fun setSearch(text: String) {
        val q = text.trim()
        if (_state.value.searchText == q) return
        _state.update { it.copy(searchText = q) }
        refresh(showLoading = true)
    }

    fun clearSearch() {
        if (_state.value.searchText.isEmpty()) return
        _state.update { it.copy(searchText = "") }
        refresh(showLoading = true)
    }

    fun setSort(state: MusicPlaylistSortState) {
        viewModelScope.launch { prefsStore.setPlaylistSort(state) }
    }

    fun refresh(showLoading: Boolean) {
        refreshJob?.cancel()
        loadMoreJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                if (showLoading) _state.update { it.copy(loading = true, loadingMore = false) }
                page = 1
                val res =
                    runCatching {
                        withContext(Dispatchers.IO) {
                            MusicPlaylistApiService.listPlaylistsPaged(
                                page = page,
                                pageSize = pageSize,
                                search = _state.value.searchText,
                                sort = _state.value.sort,
                            )
                        }
                    }.getOrNull()

                if (res == null) {
                    _state.update { it.copy(loading = false, loadingMore = false) }
                    Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                    return@launch
                }

                _state.update {
                    it.copy(
                        items = res.items,
                        hasMore = res.pagination.hasNextPage,
                        loading = false,
                        loadingMore = false,
                    )
                }
            }
    }

    fun loadMore() {
        if (_state.value.loading || _state.value.loadingMore) return
        if (!_state.value.hasMore) return
        loadMoreJob?.cancel()
        loadMoreJob =
            viewModelScope.launch {
                _state.update { it.copy(loadingMore = true) }
                val nextPage = page + 1
                val res =
                    runCatching {
                        withContext(Dispatchers.IO) {
                            MusicPlaylistApiService.listPlaylistsPaged(
                                page = nextPage,
                                pageSize = pageSize,
                                search = _state.value.searchText,
                                sort = _state.value.sort,
                            )
                        }
                    }.getOrNull()

                if (res == null) {
                    _state.update { it.copy(loadingMore = false) }
                    return@launch
                }
                page = nextPage
                _state.update {
                    it.copy(
                        items = it.items + res.items,
                        hasMore = res.pagination.hasNextPage,
                        loadingMore = false,
                    )
                }
            }
    }
}

