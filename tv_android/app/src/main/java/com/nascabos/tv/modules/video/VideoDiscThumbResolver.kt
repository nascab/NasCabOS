package com.nascabos.tv.modules.video

import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.video.detail.VideoDetailApiService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

object VideoDiscThumbResolver {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val cache = LinkedHashMap<Int, String>(64, 0.75f, true)
    private val pending = LinkedHashMap<Int, MutableList<(String) -> Unit>>()

    fun resolveThumbApiPath(
        indexId: Int,
        size: Int = 640,
        onResolved: (String) -> Unit,
    ) {
        val id = indexId.takeIf { it > 0 } ?: run {
            onResolved("")
            return
        }
        synchronized(this) {
            cache[id]?.let {
                onResolved(it)
                return
            }
            val callbacks = pending[id]
            if (callbacks != null) {
                callbacks += onResolved
                return
            }
            pending[id] = mutableListOf(onResolved)
        }
        scope.launch {
            val apiPath =
                withContext(Dispatchers.IO) {
                    val item =
                        runCatching { VideoDetailApiService.getDiscContents(id) }.getOrNull()
                            .orEmpty()
                            .firstOrNull {
                                it.resolvedThumbnailPath.isNotEmpty() ||
                                    it.resolvedThumbnailInternalPath.isNotEmpty()
                            }
                    if (item == null) {
                        ""
                    } else if (item.resolvedThumbnailPath.isNotEmpty()) {
                        TvImageLoader.buildTinyApiPath(item.resolvedThumbnailPath, size = size)
                    } else {
                        VideoDetailApiService.buildDiscContentThumbApiPath(
                            indexId = id,
                            internalPath = item.resolvedThumbnailInternalPath,
                            size = size,
                        )
                    }
                }
            val callbacks =
                synchronized(this@VideoDiscThumbResolver) {
                    cache[id] = apiPath
                    if (cache.size > 120) {
                        val firstKey = cache.entries.firstOrNull()?.key
                        if (firstKey != null) cache.remove(firstKey)
                    }
                    pending.remove(id).orEmpty()
                }
            callbacks.forEach { it(apiPath) }
        }
    }
}
