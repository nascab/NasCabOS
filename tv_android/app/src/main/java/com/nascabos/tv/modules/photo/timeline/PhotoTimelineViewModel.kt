package com.nascabos.tv.modules.photo.timeline

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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

enum class PhotoTimelineSortOrder {
    Asc,
    Desc,
}

enum class PhotoTimelineFileType {
    All,
    Image,
    Video,
}

data class PhotoTimelineUiState(
    val items: List<PhotoTimelinePhotoItem> = emptyList(),
    val validPaths: List<PhotoTimelinePathItem> = emptyList(),
    val selectedPaths: Set<String> = emptySet(),
    val sortOrder: PhotoTimelineSortOrder = PhotoTimelineSortOrder.Desc,
    val fileType: PhotoTimelineFileType = PhotoTimelineFileType.All,
    val monthKey: String? = null,
    val monthOptions: List<String> = emptyList(),
    val loading: Boolean = false,
    val loadingMore: Boolean = false,
    val hasMore: Boolean = false,
)

class PhotoTimelineViewModel(
    app: Application,
    private val albumId: Int = 0,
    private val collectionId: Int = 0,
    private val smartAlbumId: Int = 0,
    private val listType: String? = null,
    private val loadTheDay: Boolean = false,
) : AndroidViewModel(app) {
    private val _state = MutableStateFlow(PhotoTimelineUiState())
    val state: StateFlow<PhotoTimelineUiState> = _state.asStateFlow()

    private var refreshJob: Job? = null
    private var loadMoreJob: Job? = null

    private var dateList: List<PhotoTimelineDateItem> = emptyList()
    private var loadedEndIndex: Int = -1
    private val loadedIds: MutableSet<Int> = mutableSetOf()

    init {
        refresh(showLoading = true)
    }

    fun refresh(showLoading: Boolean) {
        refreshJob?.cancel()
        loadMoreJob?.cancel()
        refreshJob =
            viewModelScope.launch {
                val s = _state.value
                _state.update {
                    it.copy(
                        loading = showLoading,
                        loadingMore = false,
                        items = emptyList(),
                        hasMore = false,
                    )
                }

                loadedIds.clear()
                loadedEndIndex = -1
                dateList = emptyList()

                val sort = if (s.sortOrder == PhotoTimelineSortOrder.Asc) "asc" else "desc"
                val ft =
                    when (s.fileType) {
                        PhotoTimelineFileType.All -> null
                        PhotoTimelineFileType.Image -> "image"
                        PhotoTimelineFileType.Video -> "video"
                    }
                val sources = s.selectedPaths.toList().ifEmpty { null }

                val res =
                    runCatching {
                        withContext(Dispatchers.IO) {
                            PhotoTimelineApiService.getTimelineDateList(
                                sort = sort,
                                fileType = ft,
                                sourceList = sources,
                                albumId = albumId.takeIf { it > 0 },
                                collectionId = collectionId.takeIf { it > 0 },
                                smartAlbumId = smartAlbumId.takeIf { it > 0 },
                                listType = listType?.trim()?.takeIf { it.isNotEmpty() },
                                loadTheDay = loadTheDay.takeIf { it },
                            )
                        }
                    }.getOrNull()

                if (res == null) {
                    _state.update { it.copy(loading = false, loadingMore = false, hasMore = false) }
                    Toast.makeText(getApplication(), R.string.error_network_failed, Toast.LENGTH_SHORT).show()
                    return@launch
                }

                val monthOptions = computeMonthKeys(res.items)
                val monthKey =
                    s.monthKey?.trim()?.takeIf { it.isNotEmpty() && monthOptions.contains(it) }
                val filteredDates =
                    if (monthKey != null) {
                        res.items.filter { it.originalDate.startsWith(monthKey) }
                    } else {
                        res.items
                    }

                _state.update {
                    it.copy(
                        validPaths = res.validPaths,
                        monthOptions = monthOptions,
                        monthKey = monthKey,
                    )
                }

                dateList = filteredDates
                if (dateList.isEmpty()) {
                    _state.update { it.copy(loading = false, loadingMore = false, items = emptyList(), hasMore = false) }
                    return@launch
                }

                val range = buildFetchRange(fromIndex = 0, minCount = MIN_FETCH_COUNT) ?: run {
                    _state.update { it.copy(loading = false, loadingMore = false, items = emptyList(), hasMore = false) }
                    return@launch
                }

                val photos =
                    runCatching {
                        withContext(Dispatchers.IO) {
                            PhotoTimelineApiService.getTimelinePhotoList(
                                sort = sort,
                                fileType = ft,
                                startTime = range.startTime,
                                endTime = range.endTime,
                                sourceList = sources,
                                albumId = albumId.takeIf { it > 0 },
                                collectionId = collectionId.takeIf { it > 0 },
                                smartAlbumId = smartAlbumId.takeIf { it > 0 },
                                listType = listType?.trim()?.takeIf { it.isNotEmpty() },
                                loadTheDay = loadTheDay.takeIf { it },
                            )
                        }
                    }.getOrNull()

                val list = photos?.photoList.orEmpty().filter { loadedIds.add(it.id) }
                loadedEndIndex = range.endIndex
                val hasMore = loadedEndIndex < dateList.size - 1
                _state.update { it.copy(items = list, loading = false, loadingMore = false, hasMore = hasMore) }
            }
    }

    fun setSortOrder(order: PhotoTimelineSortOrder) {
        if (_state.value.sortOrder == order) return
        _state.update { it.copy(sortOrder = order) }
        refresh(showLoading = true)
    }

    fun setFileType(type: PhotoTimelineFileType) {
        if (_state.value.fileType == type) return
        _state.update { it.copy(fileType = type) }
        refresh(showLoading = true)
    }

    fun setSelectedPaths(paths: Set<String>) {
        if (_state.value.selectedPaths == paths) return
        _state.update { it.copy(selectedPaths = paths) }
        refresh(showLoading = true)
    }

    fun setMonthKey(monthKey: String?) {
        val mk = monthKey?.trim()?.takeIf { it.isNotEmpty() }
        if (_state.value.monthKey == mk) return
        _state.update { it.copy(monthKey = mk) }
        refresh(showLoading = true)
    }

    fun clearFilters() {
        val reset =
            _state.value.copy(
                selectedPaths = emptySet(),
                sortOrder = PhotoTimelineSortOrder.Desc,
                fileType = PhotoTimelineFileType.All,
                monthKey = null,
            )
        _state.value = reset
        refresh(showLoading = true)
    }

    fun loadMore() {
        val s = _state.value
        if (s.loading || s.loadingMore) return
        if (!s.hasMore) return
        if (loadMoreJob?.isActive == true) return
        loadMoreJob =
            viewModelScope.launch {
                val from = loadedEndIndex + 1
                if (from < 0 || from >= dateList.size) {
                    _state.update { it.copy(hasMore = false, loadingMore = false) }
                    return@launch
                }
                _state.update { it.copy(loadingMore = true) }

                val sort = if (_state.value.sortOrder == PhotoTimelineSortOrder.Asc) "asc" else "desc"
                val ft =
                    when (_state.value.fileType) {
                        PhotoTimelineFileType.All -> null
                        PhotoTimelineFileType.Image -> "image"
                        PhotoTimelineFileType.Video -> "video"
                    }
                val sources = _state.value.selectedPaths.toList().ifEmpty { null }

                val range = buildFetchRange(fromIndex = from, minCount = MIN_FETCH_COUNT)
                if (range == null) {
                    _state.update { it.copy(hasMore = false, loadingMore = false) }
                    return@launch
                }

                val photos =
                    runCatching {
                        withContext(Dispatchers.IO) {
                            PhotoTimelineApiService.getTimelinePhotoList(
                                sort = sort,
                                fileType = ft,
                                startTime = range.startTime,
                                endTime = range.endTime,
                                sourceList = sources,
                                albumId = albumId.takeIf { it > 0 },
                                collectionId = collectionId.takeIf { it > 0 },
                                smartAlbumId = smartAlbumId.takeIf { it > 0 },
                                listType = listType?.trim()?.takeIf { it.isNotEmpty() },
                                loadTheDay = loadTheDay.takeIf { it },
                            )
                        }
                    }.getOrNull()

                val incoming = photos?.photoList.orEmpty()
                val added = incoming.filter { loadedIds.add(it.id) }
                loadedEndIndex = range.endIndex
                val hasMore = loadedEndIndex < dateList.size - 1
                _state.update {
                    it.copy(
                        items = it.items + added,
                        hasMore = hasMore,
                        loadingMore = false,
                    )
                }
            }
    }

    private data class FetchRange(
        val startTime: Long,
        val endTime: Long,
        val endIndex: Int,
    )

    private fun buildFetchRange(fromIndex: Int, minCount: Int): FetchRange? {
        if (fromIndex < 0 || fromIndex >= dateList.size) return null
        var total = 0
        var end = fromIndex
        for (i in fromIndex until dateList.size) {
            total += dateList[i].count
            end = i
            if (total >= minCount) break
        }
        val startDate = dateList[fromIndex].originalDate.trim()
        val endDate = dateList[end].originalDate.trim()
        if (startDate.isEmpty() || endDate.isEmpty()) return null
        val minDate = if (startDate <= endDate) startDate else endDate
        val maxDate = if (startDate >= endDate) startDate else endDate
        val startTime = startOfDayMs(minDate)
        val endTime = endOfDayMs(maxDate)
        return FetchRange(startTime = startTime, endTime = endTime, endIndex = end)
    }

    private fun computeMonthKeys(items: List<PhotoTimelineDateItem>): List<String> {
        val set = linkedSetOf<String>()
        for (i in items.indices) {
            val d = items[i].originalDate.trim()
            if (d.length >= 7) {
                val mk = d.substring(0, 7)
                if (mk.length == 7) set.add(mk)
            }
        }
        return set.toList()
    }

    private fun startOfDayMs(date: String): Long {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.timeZone = TimeZone.getDefault()
        val parsed = runCatching { sdf.parse(date) }.getOrNull() ?: return 0L
        val cal = Calendar.getInstance()
        cal.time = parsed
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun endOfDayMs(date: String): Long {
        val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        sdf.timeZone = TimeZone.getDefault()
        val parsed = runCatching { sdf.parse(date) }.getOrNull() ?: return 0L
        val cal = Calendar.getInstance()
        cal.time = parsed
        cal.set(Calendar.HOUR_OF_DAY, 23)
        cal.set(Calendar.MINUTE, 59)
        cal.set(Calendar.SECOND, 59)
        cal.set(Calendar.MILLISECOND, 999)
        return cal.timeInMillis
    }

    companion object {
        private const val MIN_FETCH_COUNT = 300
    }
}
