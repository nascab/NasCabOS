package com.nascabos.tv.core.update

import android.content.Context
import android.content.pm.ApplicationInfo
import android.view.KeyEvent
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.nascabos.tv.R
import com.vector.update_app.HttpManager
import com.vector.update_app.UpdateAppBean
import com.vector.update_app.UpdateAppManager
import com.vector.update_app.UpdateCallback
import com.vector.update_app.service.DownloadService
import com.vector.update_app.utils.AppUpdateUtils
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.Serializable
import java.util.concurrent.TimeUnit

object TvAppUpdate {
    private const val UPDATE_URL = "https://nas.cab/config/updateInfo/android_tv.json"
    private const val PREFS_NAME = "tv_app_update"
    private const val KEY_LAST_CHECK_MS = "last_check_ms"
    private const val KEY_IGNORED_VERSION = "ignored_version"
    private const val DEFAULT_MIN_INTERVAL_MS = 24L * 60L * 60L * 1000L
    private const val VERSION_SUFFIX_SEPARATOR = "-"

    fun check(activity: FragmentActivity, minIntervalMs: Long = DEFAULT_MIN_INTERVAL_MS) {
        val isDebuggable =
            (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!isDebuggable) {
            val lastCheck = prefs.getLong(KEY_LAST_CHECK_MS, 0L)
            val now = System.currentTimeMillis()
            if (now - lastCheck < minIntervalMs) return
            prefs.edit().putLong(KEY_LAST_CHECK_MS, now).apply()
        }

        val downloadDir =
            activity.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.absolutePath
                ?: activity.externalCacheDir?.absolutePath
                ?: activity.cacheDir.absolutePath

        UpdateAppManager.Builder()
            .setActivity(activity)
            .setUpdateUrl(UPDATE_URL)
            .setHttpManager(TvUpdateHttpManager())
            .setTargetPath(downloadDir)
            .dismissNotificationProgress()
            .build()
            .checkNewApp(
                object : UpdateCallback() {
                    override fun parseJson(json: String): UpdateAppBean {
                        val obj = JSONObject(json)
                        val newVersion = obj.optString("new_version").trim()
                        val constraint = obj.optBoolean("constraint", false)

                        val localVersion = getLocalVersionName(activity)
                        val shouldUpdate = compareVersions(newVersion, localVersion) > 0
                        Log.d("nascab", "check: newVersion=$newVersion, localVersion=$localVersion, shouldUpdate=$shouldUpdate")
                        return UpdateAppBean()
                            .setUpdate(if (shouldUpdate) "Yes" else "No")
                            .setNewVersion(newVersion)
                            .setApkFileUrl(obj.optString("apk_file_url").trim())
                            .setUpdateLog(obj.optString("update_log").trim())
                            .setTargetSize(obj.optString("target_size").trim())
                            .setConstraint(constraint)
                            .setNewMd5(obj.optString("new_md5").trim())
                    }

                    override fun hasNewApp(updateApp: UpdateAppBean, updateAppManager: UpdateAppManager) {
                        val ignored =
                            if (!updateApp.isConstraint) {
                                prefs.getString(KEY_IGNORED_VERSION, null)?.trim().orEmpty()
                            } else {
                                ""
                            }
                        if (ignored.isNotEmpty()) {
                            val localVersion = getLocalVersionName(activity)
                            if (compareVersions(localVersion, ignored) >= 0) {
                                prefs.edit().remove(KEY_IGNORED_VERSION).apply()
                            } else if (ignored == updateApp.newVersion.trim()) {
                                return
                            }
                        }
                        val canIgnoreThisVersion = !updateApp.isConstraint
                        showSimpleUpdateDialog(
                            activity = activity,
                            updateApp = updateApp,
                            updateAppManager = updateAppManager,
                            canIgnoreThisVersion = canIgnoreThisVersion,
                        ) { version ->
                            prefs.edit().putString(KEY_IGNORED_VERSION, version.trim()).apply()
                        }
                    }

                    override fun noNewApp(error: String) {}
                },
            )
    }

    private fun getLocalVersionName(activity: FragmentActivity): String {
        val raw = AppUpdateUtils.getVersionName(activity).trim()
        val idx = raw.indexOf(VERSION_SUFFIX_SEPARATOR)
        return if (idx > 0) raw.substring(0, idx) else raw
    }

    private fun compareVersions(a: String, b: String): Int {
        val pa = a.trim().split('.', '-', '_').filter { it.isNotBlank() }
        val pb = b.trim().split('.', '-', '_').filter { it.isNotBlank() }
        val max = maxOf(pa.size, pb.size)
        for (i in 0 until max) {
            val sa = pa.getOrNull(i)
            val sb = pb.getOrNull(i)
            if (sa == null && sb == null) return 0
            if (sa == null) return -1
            if (sb == null) return 1
            val na = sa.toIntOrNull()
            val nb = sb.toIntOrNull()
            if (na != null || nb != null) {
                val va = na ?: 0
                val vb = nb ?: 0
                if (va != vb) return va.compareTo(vb)
            } else {
                if (sa != sb) return sa.compareTo(sb)
            }
        }
        return 0
    }

    private fun showSimpleUpdateDialog(
        activity: FragmentActivity,
        updateApp: UpdateAppBean,
        updateAppManager: UpdateAppManager,
        canIgnoreThisVersion: Boolean,
        onIgnoreThisVersion: (String) -> Unit,
    ) {
        val isConstraint = updateApp.isConstraint
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            val dp = activity.resources.displayMetrics.density
            val padding = (20f * dp).toInt()
            setPadding(padding, padding, padding, padding)
        }
        val statusView = TextView(activity).apply {
            text = activity.getString(R.string.update_status_ready)
            val dp = activity.resources.displayMetrics.density
            setPadding(0, 0, 0, (12f * dp).toInt())
        }
        val progressBar = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = false
            max = 100
            progress = 0
        }
        container.addView(
            statusView,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(
            progressBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val dialog =
            AlertDialog.Builder(activity)
                .setTitle(activity.getString(R.string.update_dialog_title_format, updateApp.newVersion))
                .setView(container)
                .setPositiveButton(R.string.update_action_upgrade, null)
                .apply {
                    if (!isConstraint) {
                        setNegativeButton(R.string.update_action_later) { d, _ -> d.dismiss() }
                    }
                    if (!isConstraint && canIgnoreThisVersion) {
                        setNeutralButton(R.string.update_action_ignore_this_version) { d, _ ->
                            onIgnoreThisVersion(updateApp.newVersion)
                            d.dismiss()
                        }
                    }
                }
                .setCancelable(!isConstraint)
                .create()

        dialog.setCanceledOnTouchOutside(false)

        if (isConstraint) {
            dialog.setOnKeyListener { _, keyCode, event ->
                if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    true
                } else {
                    false
                }
            }
        }

        dialog.setOnShowListener {
            val upgradeButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            val laterButton = dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
            upgradeButton.requestFocus()

            fun setDownloadingUi(percent: Int?) {
                progressBar.visibility = ProgressBar.VISIBLE
                if (percent == null) {
                    statusView.text = activity.getString(R.string.update_action_downloading)
                } else {
                    statusView.text =
                        activity.getString(R.string.update_status_downloading_percent_format, percent)
                    progressBar.progress = percent.coerceIn(0, 100)
                }
            }

            fun setErrorUi() {
                progressBar.progress = 0
                statusView.text = activity.getString(R.string.update_status_failed)
                upgradeButton.isEnabled = true
                upgradeButton.text = activity.getString(R.string.update_action_retry)
                if (!isConstraint) laterButton?.isEnabled = true
                upgradeButton.requestFocus()
            }

            upgradeButton.setOnClickListener {
                upgradeButton.isEnabled = false
                upgradeButton.text = activity.getString(R.string.update_action_downloading)
                if (!isConstraint) laterButton?.isEnabled = false
                setDownloadingUi(null)

                updateAppManager.download(
                    object : DownloadService.DownloadCallback {
                        override fun onStart() {
                            activity.runOnUiThread {
                                setDownloadingUi(0)
                            }
                        }

                        override fun onProgress(progress: Float, totalSize: Long) {
                            activity.runOnUiThread {
                                val percent = (progress * 100f).toInt()
                                setDownloadingUi(percent)
                            }
                        }

                        override fun setMax(totalSize: Long) {}

                        override fun onFinish(file: File): Boolean {
                            activity.runOnUiThread {
                                progressBar.progress = 100
                                statusView.text = activity.getString(R.string.update_status_ready_to_install)
                                AppUpdateUtils.installApp(activity, file)
                            }
                            return false
                        }

                        override fun onError(msg: String) {
                            activity.runOnUiThread {
                                setErrorUi()
                            }
                        }

                        override fun onInstallAppAndAppOnForeground(file: File): Boolean {
                            return false
                        }
                    },
                )
            }
        }

        dialog.show()
    }
}

class TvUpdateHttpManager : HttpManager, Serializable {
    @Transient
    private var client: OkHttpClient? = null

    private fun runOnMainThread(block: () -> Unit) {
        if (Looper.getMainLooper().thread == Thread.currentThread()) {
            block()
            return
        }
        Handler(Looper.getMainLooper()).post(block)
    }

    private fun getClient(): OkHttpClient {
        val existing = client
        if (existing != null) return existing
        val created =
            OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .followRedirects(true)
                .followSslRedirects(true)
                .build()
        client = created
        return created
    }

    override fun asyncGet(url: String, params: MutableMap<String, String>, callBack: HttpManager.Callback) {
        val base = url.toHttpUrlOrNull()
        if (base == null) {
            runOnMainThread { callBack.onError("invalid_url") }
            return
        }
        val u =
            base.newBuilder().apply {
                for ((k, v) in params) addQueryParameter(k, v)
            }.build()

        val req = Request.Builder().url(u).get().build()
        getClient().newCall(req).enqueue(
            object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: IOException) {
                    runOnMainThread { callBack.onError(e.message ?: "network_error") }
                }

                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    response.use {
                        val body = it.body?.string()
                        if (!it.isSuccessful || body == null) {
                            runOnMainThread { callBack.onError("http_${it.code}") }
                            return
                        }
                        runOnMainThread { callBack.onResponse(body) }
                    }
                }
            },
        )
    }

    override fun asyncPost(url: String, params: MutableMap<String, String>, callBack: HttpManager.Callback) {
        val form =
            FormBody.Builder().apply {
                for ((k, v) in params) add(k, v)
            }.build()
        val req = Request.Builder().url(url).post(form).build()
        getClient().newCall(req).enqueue(
            object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: IOException) {
                    runOnMainThread { callBack.onError(e.message ?: "network_error") }
                }

                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    response.use {
                        val body = it.body?.string()
                        if (!it.isSuccessful || body == null) {
                            runOnMainThread { callBack.onError("http_${it.code}") }
                            return
                        }
                        runOnMainThread { callBack.onResponse(body) }
                    }
                }
            },
        )
    }

    override fun download(
        url: String,
        path: String,
        fileName: String,
        callback: HttpManager.FileCallback,
    ) {
        runOnMainThread { callback.onBefore() }

        val dir = File(path)
        dir.mkdirs()

        val targetFile = File(dir, fileName)
        if (targetFile.exists()) {
            targetFile.delete()
        }

        val req = Request.Builder().url(url).get().build()
        getClient().newCall(req).enqueue(
            object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, e: IOException) {
                    runOnMainThread { callback.onError(e.message ?: "network_error") }
                }

                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    response.use {
                        if (!it.isSuccessful) {
                            runOnMainThread { callback.onError("http_${it.code}") }
                            return
                        }
                        val body = it.body ?: run {
                            runOnMainThread { callback.onError("empty_body") }
                            return
                        }
                        val total = body.contentLength().coerceAtLeast(0L)
                        try {
                            body.byteStream().use { input ->
                                FileOutputStream(targetFile).use { output ->
                                    val buf = ByteArray(DEFAULT_BUFFER_SIZE)
                                    var read: Int
                                    var written = 0L
                                    var lastProgressSentAt = 0L
                                    while (true) {
                                        read = input.read(buf)
                                        if (read <= 0) break
                                        output.write(buf, 0, read)
                                        written += read.toLong()
                                        if (total > 0) {
                                            val now = System.currentTimeMillis()
                                            if (now - lastProgressSentAt >= 150) {
                                                val progress = written.toFloat() / total.toFloat()
                                                runOnMainThread { callback.onProgress(progress, total) }
                                                lastProgressSentAt = now
                                            }
                                        }
                                    }
                                }
                            }
                            if (total > 0) runOnMainThread { callback.onProgress(1f, total) }
                            runOnMainThread { callback.onResponse(targetFile) }
                        } catch (e: Exception) {
                            targetFile.delete()
                            runOnMainThread { callback.onError(e.message ?: "write_file_error") }
                        }
                    }
                }
            },
        )
    }
}
