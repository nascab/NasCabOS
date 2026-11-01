package com.nascabos.mobile.storage

import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * 把下载完成的文件写入 Android 公共 Download 目录。
 * Android 10+（分区存储）走 MediaStore，无需存储权限；Android 9 及以下直接写公共目录。
 */
object PublicDownloadsHandler : MethodChannel.MethodCallHandler {
    private const val DEFAULT_RELATIVE_DIR = "Download/NasCabOS"

    private var appContext: Context? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun install(context: Context, channel: MethodChannel) {
        appContext = context.applicationContext
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveToDownloads" -> {
                val ctx = appContext
                if (ctx == null) {
                    result.error("no_context", "Application context not ready", null)
                    return
                }
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")
                if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                    result.error("invalid_args", "sourcePath/fileName required", null)
                    return
                }
                val relativeDir =
                    call.argument<String>("relativeDir")?.takeIf { it.isNotBlank() }
                        ?: DEFAULT_RELATIVE_DIR
                // 大文件拷贝放到后台线程，避免阻塞主线程导致界面卡顿。
                executor.execute {
                    val savedPath =
                        try {
                            saveToDownloads(ctx, sourcePath, relativeDir, fileName)
                        } catch (_: Exception) {
                            null
                        }
                    mainHandler.post {
                        if (savedPath == null) {
                            result.error("save_failed", "Failed to save into public Downloads", null)
                        } else {
                            result.success(savedPath)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun saveToDownloads(
        context: Context,
        sourcePath: String,
        relativeDir: String,
        fileName: String,
    ): String? {
        val src = File(sourcePath)
        if (!src.exists() || src.isDirectory) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, src, relativeDir, fileName)
        } else {
            saveToLegacyPublicDir(src, relativeDir, fileName)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(
        context: Context,
        src: File,
        relativeDir: String,
        fileName: String,
    ): String? {
        val resolver = context.contentResolver
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeOf(fileName))
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativeDir)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        val uri =
            resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return null
        try {
            resolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("openOutputStream returned null")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        val pending = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        resolver.update(uri, pending, null, null)
        return resolveFilePath(resolver, uri, relativeDir) ?: uri.toString()
    }

    /** 查询 MediaStore 返回的真实文件路径，供应用内打开/分享/展示。 */
    @Suppress("DEPRECATION")
    private fun resolveFilePath(
        resolver: ContentResolver,
        uri: Uri,
        relativeDir: String,
    ): String? {
        try {
            val projection =
                arrayOf(
                    MediaStore.MediaColumns.DATA,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                )
            resolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use
                val dataIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                if (dataIndex >= 0) {
                    val path = cursor.getString(dataIndex)
                    if (!path.isNullOrBlank()) return path
                }
                // DATA 列不可用时，用 DisplayName + 公共目录拼接
                val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    val name = cursor.getString(nameIndex)
                    if (!name.isNullOrBlank()) {
                        val subDir =
                            relativeDir.removePrefix(Environment.DIRECTORY_DOWNLOADS + "/")
                        val dir =
                            if (subDir.isBlank()) {
                                publicDownloadRoot()
                            } else {
                                File(publicDownloadRoot(), subDir)
                            }
                        val candidate = File(dir, name)
                        if (candidate.exists()) return candidate.absolutePath
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun publicDownloadRoot(): File =
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    @Suppress("DEPRECATION")
    private fun saveToLegacyPublicDir(
        src: File,
        relativeDir: String,
        fileName: String,
    ): String? {
        val publicRoot = publicDownloadRoot()
        val subDir =
            relativeDir
                .removePrefix(Environment.DIRECTORY_DOWNLOADS + "/")
                .removePrefix(Environment.DIRECTORY_DOWNLOADS)
        val dir = if (subDir.isBlank()) publicRoot else File(publicRoot, subDir)
        if (!dir.exists() && !dir.mkdirs()) return null
        var dest = File(dir, fileName)
        var index = 1
        val base = dest.nameWithoutExtension
        val ext = dest.extension
        while (dest.exists()) {
            val name = if (ext.isEmpty()) "$base($index)" else "$base($index).$ext"
            dest = File(dir, name)
            index++
        }
        src.copyTo(dest, overwrite = false)
        return dest.absolutePath
    }

    private fun mimeTypeOf(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }
}
