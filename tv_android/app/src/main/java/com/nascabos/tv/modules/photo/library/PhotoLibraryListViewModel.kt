package com.nascabos.tv.modules.photo.library

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

data class PhotoLibraryUiState(
    val kind: PhotoLibraryKind,
    val items: List<PhotoLibraryListItem> = emptyList(),
    val pagination: PhotoLibraryPagination = PhotoLibraryPagination(total = 0, page = 1, pageSize = 20),
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val keyword: String = "",
    val sort: PhotoLibrarySortState = PhotoLibrarySortState(PhotoLibrarySortField.CreateTime, PhotoLibrarySortOrder.Desc),
)

class PhotoLibraryListViewModel(
    app: Application,
    private val kind: PhotoLibraryKind,
) : AndroidViewModel(app) {
    private val prefsStore = PhotoLibraryPrefsStore(app.applicationContext)

    private val _state =
        MutableStateFlow(
            PhotoLibraryUiState(
                kind = kind,
                sort = PhotoLibrarySortState(PhotoLibrarySortField.CreateTime, PhotoLibrarySortOrder.Desc),
            ),
        )
    val state: StateFlow<PhotoLibraryUiState> = _state.asStateFlow()

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
        loadMoreJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                val s = _state.value
                Log.d("PhotoLibraryListVM", "refresh kind=${kind.name} loading=$showLoading keyword='${s.keyword}' sort=${s.sort.field}/${s.sort.order}")
                _state.update { it.copy(loading = showLoading, loadingMore = false) }
                page = 1
                try {
                    val res =
                        withContext(Dispatchers.IO) {
                            PhotoLibraryApiService.listPaged(
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
                    Log.e("PhotoLibraryListVM", "refresh failed", e)
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
                            PhotoLibraryApiService.listPaged(
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
                    Log.e("PhotoLibraryListVM", "loadMore failed", e)
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

    fun setSort(sort: PhotoLibrarySortState) {
        if (_state.value.sort == sort) return
        _state.update { it.copy(sort = sort) }
        refresh(showLoading = true)
        viewModelScope.launch { prefsStore.setSort(kind, sort) }
    }
}

