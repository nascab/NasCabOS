package com.nascabos.tv.core.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.view.View
import android.widget.ImageView
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URLEncoder
import java.util.WeakHashMap

object TvImageLoader {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val cache =
        object : LruCache<String, Bitmap>((Runtime.getRuntime().maxMemory() / 8L).toInt().coerceAtLeast(8 * 1024 * 1024)) {
            override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
        }

    private val inFlightJobs = WeakHashMap<ImageView, Job>()
    private val attachListeners = WeakHashMap<ImageView, View.OnAttachStateChangeListener>()

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    fun buildTinyApiPath(filePath: String, size: Int = 640): String {
        val p = filePath.trim()
        if (p.isEmpty()) return ""
        val token = ApiController.accessToken.trim()

        val sb = StringBuilder()
        sb.append("/api/file/tiny")
        sb.append("?path=").append(enc(p))
        if (size > 0) sb.append("&size=").append(enc(size.toString()))
        if (token.isNotEmpty()) sb.append("&accessToken=").append(enc(token))
        if (ApiController.baseUrl.trim() == ApiConfig.p2pBaseUrl) sb.append("&p2pChannel=file")
        return sb.toString()
    }

    private fun ensureCancelOnDetach(imageView: ImageView) {
        if (attachListeners.containsKey(imageView)) return
        val listener =
            object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {}

                override fun onViewDetachedFromWindow(v: View) {
                    cancelInFlight(imageView)
                }
            }
        attachListeners[imageView] = listener
        imageView.addOnAttachStateChangeListener(listener)
    }

    private fun cancelInFlight(imageView: ImageView) {
        inFlightJobs.remove(imageView)?.cancel()
    }

    fun loadTinyInto(
        imageView: ImageView,
        filePath: String?,
        size: Int = 480,
    ) {
        loadTinyInto(
            imageView = imageView,
            filePath = filePath,
            size = size,
            placeholderResId = R.drawable.ic_video,
            showPlaceholderWhileLoading = true,
            errorResId = R.drawable.img_404,
            onDone = null,
        )
    }

    fun loadTinyInto(
        imageView: ImageView,
        filePath: String?,
        size: Int = 640,
        placeholderResId: Int = R.drawable.ic_video,
        showPlaceholderWhileLoading: Boolean = true,
        errorResId: Int = R.drawable.img_404,
        onDone: ((Boolean) -> Unit)? = null,
    ) {
        val p = filePath?.trim().orEmpty()
        if (p.isEmpty()) {
            cancelInFlight(imageView)
            imageView.tag = null
            if (placeholderResId != 0) imageView.setImageResource(placeholderResId) else imageView.setImageDrawable(null)
            onDone?.invoke(false)
            return
        }

        val pathWithQuery = buildTinyApiPath(p, size = size)
        if (pathWithQuery.isEmpty()) {
            cancelInFlight(imageView)
            imageView.tag = null
            if (placeholderResId != 0) imageView.setImageResource(placeholderResId) else imageView.setImageDrawable(null)
            onDone?.invoke(false)
            return
        }

        ensureCancelOnDetach(imageView)
        cancelInFlight(imageView)

        val cacheKey = "tiny:$size:$p"
        imageView.tag = cacheKey

        val cached = cache.get(cacheKey)
        if (cached != null && !cached.isRecycled) {
            imageView.setImageBitmap(cached)
            onDone?.invoke(true)
            return
        }

        if (showPlaceholderWhileLoading) {
            if (placeholderResId != 0) imageView.setImageResource(placeholderResId) else imageView.setImageDrawable(null)
        } else if (placeholderResId != 0) {
            imageView.setImageDrawable(null)
        }

        val job =
            scope.launch {
                val bmp = loadTinyBitmap(filePath = p, size = size, reqSize = size, timeoutSeconds = 12)
                if (imageView.tag != cacheKey) return@launch
                if (bmp == null) {
                    if (errorResId != 0) imageView.setImageResource(errorResId) else imageView.setImageDrawable(null)
                    onDone?.invoke(false)
                    return@launch
                }
                imageView.setImageBitmap(bmp)
                onDone?.invoke(true)
            }
        inFlightJobs[imageView] = job
        job.invokeOnCompletion {
            if (inFlightJobs[imageView] == job) inFlightJobs.remove(imageView)
        }
    }

    fun loadApiPathInto(
        imageView: ImageView,
        apiPath: String?,
        cacheKeyPrefix: String,
        placeholderResId: Int,
        timeoutSeconds: Long = 12,
    ) {
        loadApiPathInto(
            imageView = imageView,
            apiPath = apiPath,
            cacheKeyPrefix = cacheKeyPrefix,
            placeholderResId = placeholderResId,
            reqSize = 240,
            showPlaceholderWhileLoading = true,
            errorResId = R.drawable.img_404,
            timeoutSeconds = timeoutSeconds,
            onDone = null,
        )
    }

    fun loadApiPathInto(
        imageView: ImageView,
        apiPath: String?,
        cacheKeyPrefix: String,
        placeholderResId: Int,
        reqSize: Int,
        showPlaceholderWhileLoading: Boolean = true,
        errorResId: Int = R.drawable.img_404,
        timeoutSeconds: Long = 12,
        onDone: ((Boolean) -> Unit)? = null,
    ) {
        val p = apiPath?.trim().orEmpty()
        if (p.isEmpty()) {
            cancelInFlight(imageView)
            imageView.tag = null
            if (placeholderResId != 0) imageView.setImageResource(placeholderResId) else imageView.setImageDrawable(null)
            onDone?.invoke(false)
            return
        }

        ensureCancelOnDetach(imageView)
        cancelInFlight(imageView)

        val cacheKey = "${cacheKeyPrefix}:${p}"
        imageView.tag = cacheKey

        val cached = cache.get(cacheKey)
        if (cached != null && !cached.isRecycled) {
            imageView.setImageBitmap(cached)
            onDone?.invoke(true)
            return
        }

        if (showPlaceholderWhileLoading) {
            if (placeholderResId != 0) imageView.setImageResource(placeholderResId) else imageView.setImageDrawable(null)
        } else {
            imageView.setImageDrawable(null)
        }

        val job =
            scope.launch {
                val bmp = loadApiPathBitmap(apiPath = p, cacheKeyPrefix = cacheKeyPrefix, reqSize = reqSize, timeoutSeconds = timeoutSeconds)
                if (imageView.tag != cacheKey) return@launch
                if (bmp == null) {
                    if (errorResId != 0) imageView.setImageResource(errorResId) else imageView.setImageDrawable(null)
                    onDone?.invoke(false)
                    return@launch
                }
                imageView.setImageBitmap(bmp)
                onDone?.invoke(true)
            }
        inFlightJobs[imageView] = job
        job.invokeOnCompletion {
            if (inFlightJobs[imageView] == job) inFlightJobs.remove(imageView)
        }
    }

    suspend fun loadTinyBitmap(
        filePath: String?,
        size: Int,
        reqSize: Int,
        timeoutSeconds: Long = 12,
    ): Bitmap? {
        val p = filePath?.trim().orEmpty()
        if (p.isEmpty()) return null

        val pathWithQuery = buildTinyApiPath(p, size = size)
        if (pathWithQuery.isEmpty()) return null

        val cacheKey = "tiny:$size:$p"
        val cached = cache.get(cacheKey)
        if (cached != null && !cached.isRecycled) return cached

        val bytes =
            withContext(Dispatchers.IO) {
                try {
                    ApiController.requestBytes(
                        baseUrl = ApiController.baseUrl,
                        path = pathWithQuery,
                        timeoutSeconds = timeoutSeconds,
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    ByteArray(0)
                }
            }
        if (bytes.isEmpty()) return null

        val bmp =
            withContext(Dispatchers.Default) {
                currentCoroutineContext().ensureActive()
                decodeSampledBitmap(bytes, reqSize = reqSize.coerceAtLeast(100))
            } ?: return null

        cache.put(cacheKey, bmp)
        return bmp
    }

    suspend fun loadApiPathBitmap(
        apiPath: String?,
        cacheKeyPrefix: String,
        reqSize: Int,
        timeoutSeconds: Long = 12,
    ): Bitmap? {
        val p = apiPath?.trim().orEmpty()
        if (p.isEmpty()) return null

        val cacheKey = "${cacheKeyPrefix}:${p}"
        val cached = cache.get(cacheKey)
        if (cached != null && !cached.isRecycled) return cached

        val bytes =
            withContext(Dispatchers.IO) {
                try {
                    ApiController.requestBytes(
                        baseUrl = ApiController.baseUrl,
                        path = p,
                        timeoutSeconds = timeoutSeconds,
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    ByteArray(0)
                }
            }
        if (bytes.isEmpty()) return null

        val bmp =
            withContext(Dispatchers.Default) {
                currentCoroutineContext().ensureActive()
                decodeSampledBitmap(bytes, reqSize = reqSize.coerceAtLeast(120))
            } ?: return null

        cache.put(cacheKey, bmp)
        return bmp
    }

    private fun decodeSampledBitmap(bytes: ByteArray, reqSize: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return null

        var sample = 1
        var halfW = w / 2
        var halfH = h / 2
        while (halfW / sample >= reqSize && halfH / sample >= reqSize) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample.coerceAtLeast(1)
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) }.getOrNull()
    }
}
