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

data class MusicTrackListUiState(
    val title: String,
    val isFavorite: Boolean,
    val items: List<MusicListItem> = emptyList(),
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val hasMore: Boolean = true,
    val searchText: String = "",
    val sort: MusicListSortState,
    val availablePaths: List<MusicListPathItem> = emptyList(),
    val selectedPaths: Set<String> = emptySet(),
)

class MusicTrackListViewModel(
    app: Application,
    private val titleText: String,
    private val isFavoriteList: Boolean,
    private val listType: String? = null,
    private val listId: Int? = null,
    private val seriesIndexId: Int? = null,
    private val artists: List<String>? = null,
    private val albums: List<String>? = null,
) : AndroidViewModel(app) {
    private val prefsStore = MusicPrefsStore(app.applicationContext)
    private val sortScope: String =
        when {
            isFavoriteList -> "favorite"
            !listType.isNullOrBlank() -> "sub_${listType.trim().lowercase()}"
            listId != null && listId > 0 -> "sub_list"
            seriesIndexId != null && seriesIndexId > 0 -> "sub_series"
            !artists.isNullOrEmpty() -> "sub_artist"
            !albums.isNullOrEmpty() -> "sub_album"
            else -> "library"
        }

    private val defaultSort =
        if (isFavoriteList) {
            MusicListSortState(MusicListSortBy.FavoriteTime, MusicListSortOrder.Desc)
        } else {
            MusicListSortState(MusicListSortBy.Filename, MusicListSortOrder.Asc)
        }

    private val _state =
        MutableStateFlow(
            MusicTrackListUiState(
                title = titleText,
                isFavorite = isFavoriteList,
                sort = defaultSort,
            ),
        )
    val state: StateFlow<MusicTrackListUiState> = _state.asStateFlow()

    private var page: Int = 1
    private val pageSize: Int = 30
    private var sortLoadedOnce: Boolean = false
    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null

    init {
        viewModelScope.launch {
            prefsStore.trackSortFlow(sortScope, default = _state.value.sort).collectLatest { sort ->
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

    fun setSort(state: MusicListSortState) {
        viewModelScope.launch { prefsStore.setTrackSort(sortScope, state) }
    }

    fun setSourcePaths(paths: Set<String>) {
        val normalized = paths.map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        if (_state.value.selectedPaths == normalized) return
        _state.update { it.copy(selectedPaths = normalized) }
        refresh(showLoading = true)
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
                            MusicListApiService.listPaged(
                                page = page,
                                pageSize = pageSize,
                                isFavorite = isFavoriteList,
                                search = _state.value.searchText,
                                sourceList = _state.value.selectedPaths.toList().ifEmpty { null },
                                sort = _state.value.sort,
                                listType = listType,
                                listId = listId,
                                seriesIndexId = seriesIndexId,
                                artists = artists,
                                albums = albums,
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
                        availablePaths = res.validPaths,
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
                            MusicListApiService.listPaged(
                                page = nextPage,
                                pageSize = pageSize,
                                isFavorite = isFavoriteList,
                                search = _state.value.searchText,
                                sourceList = _state.value.selectedPaths.toList().ifEmpty { null },
                                sort = _state.value.sort,
                                listType = listType,
                                listId = listId,
                                seriesIndexId = seriesIndexId,
                                artists = artists,
                                albums = albums,
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
                        availablePaths = res.validPaths.ifEmpty { it.availablePaths },
                        loadingMore = false,
                    )
                }
            }
    }
}

