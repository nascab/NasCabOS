package com.nascabos.tv.modules.music

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import android.widget.ImageView

object MusicFallbackCover {
    private val cache =
        object : LruCache<String, Bitmap>((Runtime.getRuntime().maxMemory() / 10L).toInt().coerceAtLeast(8 * 1024 * 1024)) {
            override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
        }

    private val genreKeys =
        setOf(
            "blues",
            "classical",
            "country",
            "gospel",
            "hiphop",
            "pop",
            "rock",
        )

    fun pickAssetPathForTrack(
        genre: String,
        seed: Int,
    ): String {
        val normalized = normalizeGenreKey(genre)
        if (normalized.isNotEmpty() && genreKeys.contains(normalized)) {
            val idx = (stablePositive(seed) % 6) + 1
            return "musicCover/${normalized}${idx}.jpg"
        }
        val idx = (stablePositive(seed) % 20) + 1
        return "musicCover/other${idx}.jpg"
    }

    fun pickAssetPathForName(name: String, seed: Int = name.hashCode()): String {
        val idx = (stablePositive(seed) % 20) + 1
        return "musicCover/other${idx}.jpg"
    }

    fun loadInto(
        imageView: ImageView,
        assetPath: String,
        reqSize: Int = 320,
    ) {
        val p = assetPath.trim()
        if (p.isEmpty()) return
        val key = "asset:$reqSize:$p"
        val cached = cache.get(key)
        if (cached != null && !cached.isRecycled) {
            imageView.setImageBitmap(cached)
            return
        }
        val bmp = decodeAsset(imageView.context, p, reqSize) ?: return
        cache.put(key, bmp)
        imageView.setImageBitmap(bmp)
    }

    private fun decodeAsset(context: Context, assetPath: String, reqSize: Int): Bitmap? {
        val safeReq = reqSize.coerceAtLeast(120)
        val bytes =
            runCatching {
                context.assets.open(assetPath).use { it.readBytes() }
            }.getOrNull() ?: return decodeDefault(context, safeReq)

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return decodeDefault(context, safeReq)

        var sample = 1
        var halfW = w / 2
        var halfH = h / 2
        while (halfW / sample >= safeReq && halfH / sample >= safeReq) {
            sample *= 2
        }
        val opts =
            BitmapFactory.Options().apply {
                inSampleSize = sample.coerceAtLeast(1)
                inPreferredConfig = Bitmap.Config.RGB_565
            }
        return runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) }.getOrNull()
    }

    private fun decodeDefault(context: Context, reqSize: Int): Bitmap? {
        val key = "asset:$reqSize:musicCover/default.jpg"
        val cached = cache.get(key)
        if (cached != null && !cached.isRecycled) return cached
        val bmp =
            runCatching {
                context.assets.open("musicCover/default.jpg").use { stream ->
                    val bytes = stream.readBytes()
                    val opts =
                        BitmapFactory.Options().apply {
                            inPreferredConfig = Bitmap.Config.RGB_565
                        }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                }
            }.getOrNull()
        if (bmp != null) cache.put(key, bmp)
        return bmp
    }

    private fun normalizeGenreKey(genre: String): String {
        val raw = genre.trim().lowercase()
        if (raw.isEmpty()) return ""
        val head =
            raw.split(Regex("[/\\\\,;|]"))
                .map { it.trim() }
                .firstOrNull()
                .orEmpty()
        if (head.isEmpty()) return ""
        return head.replace(Regex("[^a-z0-9]"), "")
    }

    private fun stablePositive(seed: Int): Int {
        val x = seed xor (seed ushr 16)
        return x and Int.MAX_VALUE
    }
}
