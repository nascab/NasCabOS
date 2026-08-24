package com.nascabos.tv.core.api

import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import com.google.gson.Gson
import com.nascabos.tv.core.api.http.ApiHttp
import com.nascabos.tv.core.api.p2p.P2pIcePreference
import com.nascabos.tv.core.api.p2p.P2pTransportKind
import com.nascabos.tv.core.api.p2p.P2pManager
import com.nascabos.tv.core.api.p2p.P2pApiStreamResponse
import com.nascabos.tv.data.storage.ServerStore
import com.nascabos.tv.core.util.ServerVersionUtil
import com.nascabos.tv.modules.video_player.P2pLocalHttpProxy
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.io.ByteArrayOutputStream
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

object ApiController {
    private var state: ApiState = ApiState(baseUrl = "")
    private var appContext: Context? = null
    private var p2pManager: P2pManager? = null
    private val gson: Gson = Gson()

    private val _connectChannelRevision = MutableStateFlow(0)
    val connectChannelRevision: StateFlow<Int> = _connectChannelRevision.asStateFlow()

    val baseUrl: String get() = state.baseUrl
    val accessToken: String get() = state.accessToken
    val refreshToken: String get() = state.refreshToken
    /** 服务端版本字符串（登录/刷新返回），与 Flutter ApiController.serverVersion 一致 */
    val serverVersion: String get() = state.serverVersion
    val isP2pMode: Boolean get() = baseUrl.trim() == ApiConfig.p2pBaseUrl
    val p2pTransportKind: P2pTransportKind get() = p2pManager?.transportKind ?: P2pTransportKind.Unknown
    val p2pRelayAddress: String get() = p2pManager?.relayAddress ?: ""

    val connectChannelDisplayValue: String
        get() {
            val isRelay =
                isP2pMode &&
                    (getDevConnectMode() == DevConnectMode.P2pRelay ||
                        p2pTransportKind == P2pTransportKind.Relay)
            val relay = p2pRelayAddress.trim()
            return if (isP2pMode) {
                if (isRelay) {
                    if (relay.isNotEmpty()) "P2P $relay" else "P2P "
                } else {
                    "P2P"
                }
            } else {
                baseUrl
            }
        }

    enum class DevConnectMode {
        Auto,
        Direct,
        P2pDirect,
        P2pRelay,
    }

    private const val PREFS_DEV = "dev_settings"
    private const val KEY_DEV_CONNECT_MODE = "dev_connect_mode"
    private const val PREFS_VIDEO_PLAYER = "video_player"
    private const val KEY_VIDEO_DEVICE_ID = "device_id"

    private val okHttpClient: OkHttpClient by lazy {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}

            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}

            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        val sslSocketFactory: SSLSocketFactory = sslContext.socketFactory
        val verifier = HostnameVerifier { _, _ -> true }

        val logger = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        OkHttpClient.Builder()
            .sslSocketFactory(sslSocketFactory, trustAll)
            .hostnameVerifier(verifier)
            .addInterceptor(logger)
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    val http: ApiHttp by lazy { ApiHttp(okHttpClient) }

    /** refreshJwt 失败或刷新接口 401 时回调（由当前 Activity 在 onResume 注册，见 JwtSessionExpiredUi） */
    var onJwtSessionExpired: (() -> Unit)? = null

    private val jwtRefreshMutex = Mutex()
    private val sessionExpiredNotified = AtomicBoolean(false)
    private val authScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var proactiveRefreshJob: Job? = null

    fun init(appContext: Context) {
        if (this.appContext != null) return
        this.appContext = appContext.applicationContext
        this.p2pManager = P2pManager(this.appContext!!)
        P2pLocalHttpProxy.setP2pActive(baseUrl.trim() == ApiConfig.p2pBaseUrl)
    }

    private var p2pRelayConnectedCallback: (() -> Unit)? = null

    /** 设置 P2P 中继连上后的回调（如升级检测）。应在 init 之后、首次 P2P 连接前调用。 */
    fun setP2pRelayConnectedCallback(callback: (() -> Unit)?) {
        p2pRelayConnectedCallback = callback
        p2pManager?.onRelayConnected = callback
    }

    fun getOrCreateVideoDeviceId(appContext: Context? = null): String {
        val ctx = appContext ?: this.appContext ?: return ""
        val prefs = ctx.getSharedPreferences(PREFS_VIDEO_PLAYER, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_VIDEO_DEVICE_ID, null)?.trim().orEmpty()
        if (existing.isNotEmpty()) return existing
        val id = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_VIDEO_DEVICE_ID, id).apply()
        return id
    }

    fun isDebuggable(): Boolean {
        val ctx = appContext ?: return false
        val flags = ctx.applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    fun getDevConnectMode(): DevConnectMode {
        val ctx = appContext ?: return DevConnectMode.Auto
        val raw = ctx.getSharedPreferences(PREFS_DEV, Context.MODE_PRIVATE)
            .getString(KEY_DEV_CONNECT_MODE, null)
            ?.trim()
            .orEmpty()
        return runCatching { DevConnectMode.valueOf(raw) }.getOrNull() ?: DevConnectMode.Auto
    }

    fun setDevConnectMode(mode: DevConnectMode) {
        val ctx = appContext ?: return
        ctx.getSharedPreferences(PREFS_DEV, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_DEV_CONNECT_MODE, mode.name)
            .apply()
        _connectChannelRevision.value = _connectChannelRevision.value + 1
    }

    private fun requireP2p(): P2pManager {
        val p = p2pManager
        require(p != null) { "ApiController.init(context) not called" }
        return p
    }

    fun setBaseUrl(baseUrl: String) {
        state = state.copy(baseUrl = baseUrl.trim())
        _connectChannelRevision.value = _connectChannelRevision.value + 1
        P2pLocalHttpProxy.setP2pActive(baseUrl.trim() == ApiConfig.p2pBaseUrl)
    }

    /**
     * 与 Flutter [ApiController.isServerVersionAtLeast] 一致：未知版本时默认视为满足（避免误拦老会话）。
     */
    fun isServerVersionAtLeast(
        majorVersion: Int,
        unknownAsSupported: Boolean = true,
    ): Boolean =
        ServerVersionUtil.isAtLeast(
            serverVersion.trim().takeIf { it.isNotEmpty() },
            majorVersion,
            unknownAsSupported = unknownAsSupported,
        )

    fun setTokens(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAtEpochSec: Long? = null,
        serverVersion: String? = null,
    ) {
        proactiveRefreshJob?.cancel()
        sessionExpiredNotified.set(false)
        val cleared = accessToken.isEmpty() && refreshToken.isEmpty()
        val expires =
            when {
                cleared -> null
                accessTokenExpiresAtEpochSec != null && accessTokenExpiresAtEpochSec > 0L ->
                    accessTokenExpiresAtEpochSec
                else -> null
            }
        state =
            state.copy(
                accessToken = accessToken,
                refreshToken = refreshToken,
                accessTokenExpiresAtEpochSec = expires,
                serverVersion =
                    when {
                        cleared -> ""
                        serverVersion != null -> serverVersion.trim()
                        else -> state.serverVersion
                    },
            )
        restartProactiveJwtRefreshIfNeeded()
    }

    fun validatePairCodeText(value: String?): PairCodeError? {
        val s = value?.trim().orEmpty()
        if (s.isEmpty()) return PairCodeError.Empty
        if (s.length < 4) return PairCodeError.Invalid
        if (s.length > 32) return PairCodeError.Invalid
        return null
    }

    suspend fun connectP2pByPairCode(
        pairCode: String,
        icePreference: P2pIcePreference = P2pIcePreference.Auto,
    ) {
        withContext(Dispatchers.IO) {
            requireP2p().connectByPairCode(pairCode, preference = icePreference)
        }
        setBaseUrl(ApiConfig.p2pBaseUrl)
    }

    suspend fun disconnectP2p() {
        withContext(Dispatchers.IO) {
            requireP2p().disconnect()
        }
    }

    suspend fun ensureP2pConnected(timeoutMs: Long = 15_000): Boolean {
        return withContext(Dispatchers.IO) {
            requireP2p().ensureConnected(timeoutMs = timeoutMs)
        }
    }

    /** P2P 模式下预连接 video 通道，供播放器使用。在打开播放器前调用，避免首包超时（与 Apple TV LocalPlaybackProxy 预启动行为一致）。 */
    suspend fun ensureP2pPlaybackReady(timeoutMs: Long = 15_000): Boolean {
        if (!isP2pMode) return true
        return withContext(Dispatchers.IO) {
            val ok = ensureP2pConnected(timeoutMs)
            if (!ok) return@withContext false
            requireP2p().ensureVideoLinkReady(timeoutMs = timeoutMs)
        }
    }

    fun formatP2pConnectError(e: Throwable): String {
        return runCatching { requireP2p().formatConnectError(e) }.getOrElse { e.toString() }
    }

    suspend fun requestJsonMap(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long,
        headers: Map<String, String> = emptyMap(),
    ): Map<String, Any?> {
        return executeJsonMapWithJwtRetry(
            isGet = true,
            baseUrl = baseUrl,
            path = path,
            body = null,
            timeoutSeconds = timeoutSeconds,
            headers = headers,
        )
    }

    suspend fun postJsonMap(
        baseUrl: String,
        path: String,
        body: Any?,
        timeoutSeconds: Long,
        headers: Map<String, String> = emptyMap(),
    ): Map<String, Any?> {
        return executeJsonMapWithJwtRetry(
            isGet = false,
            baseUrl = baseUrl,
            path = path,
            body = body,
            timeoutSeconds = timeoutSeconds,
            headers = headers,
        )
    }

    suspend fun requestBytes(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long = 8,
        headers: Map<String, String> = emptyMap(),
    ): ByteArray {
        val trimmed = baseUrl.trim()
        val effectiveHeaders = mergeDefaultBearerHeaders(headers)
        val normPath = if (path.startsWith("/")) path else "/$path"
        if (trimmed == ApiConfig.p2pBaseUrl) {
            return withContext(Dispatchers.IO) {
                val ok = ensureP2pConnected(timeoutMs = 15_000)
                if (!ok) throw IllegalStateException("p2p_not_connected")
                val uri = Uri.parse("${ApiConfig.p2pBaseUrl}$normPath")
                val timeoutMs = (timeoutSeconds.coerceAtLeast(3) * 1000L)
                suspend fun loadOnce(h: Map<String, String>): Pair<Int, ByteArray> {
                    val res =
                        requireP2p().sendRequestStream(
                            uri = uri,
                            method = "GET",
                            headers = h,
                            body = ByteArray(0),
                            timeoutMs = timeoutMs,
                        )
                    val code = res.status
                    if (code == 401) {
                        runCatching { res.cancel() }
                        return code to ByteArray(0)
                    }
                    return code to readP2pStreamFully(res, timeoutMs)
                }
                var (code, bytes) = loadOnce(effectiveHeaders)
                if (code == 401 && !isRefreshJwtPath(normPath) && hasRefreshToken()) {
                    val refreshed = jwtRefreshMutex.withLock { refreshJwtUnsafe() }
                    if (refreshed) {
                        val second = loadOnce(mergeBearerFromState(effectiveHeaders))
                        code = second.first
                        bytes = second.second
                    }
                }
                if (code == 401 && isRefreshJwtPath(normPath)) {
                    notifyJwtSessionExpiredOnce()
                }
                bytes
            }
        }
        var (code, bytes) = http.getBytesWithHttpCode(trimmed, normPath, timeoutSeconds, effectiveHeaders)
        if (code == 401 && !isRefreshJwtPath(normPath) && hasRefreshToken()) {
            val refreshed = jwtRefreshMutex.withLock { refreshJwtUnsafe() }
            if (refreshed) {
                val second = http.getBytesWithHttpCode(trimmed, normPath, timeoutSeconds, mergeBearerFromState(effectiveHeaders))
                code = second.first
                bytes = second.second
            }
        }
        if (code == 401 && isRefreshJwtPath(normPath)) {
            notifyJwtSessionExpiredOnce()
        }
        return bytes
    }

    private fun restartProactiveJwtRefreshIfNeeded() {
        proactiveRefreshJob?.cancel()
        val exp = state.accessTokenExpiresAtEpochSec
        if (state.accessToken.isBlank() || state.refreshToken.isBlank() || exp == null || exp <= 0L) {
            return
        }
        proactiveRefreshJob =
            authScope.launch {
                while (isActive) {
                    delay(60_000L)
                    val e = state.accessTokenExpiresAtEpochSec ?: break
                    val now = System.currentTimeMillis() / 1000L
                    if (e - now <= 300L) {
                        jwtRefreshMutex.withLock { refreshJwtUnsafe() }
                    }
                }
            }
    }

    private fun notifyJwtSessionExpiredOnce() {
        if (!sessionExpiredNotified.compareAndSet(false, true)) return
        val cb = onJwtSessionExpired ?: return
        cb.invoke()
    }

    private fun hasRefreshToken() = state.refreshToken.isNotBlank()

    private fun isRefreshJwtPath(path: String): Boolean = path.contains("/api/auth/refreshJwt")

    private fun isTwofaRequiredBody(map: Map<String, Any?>): Boolean =
        map["code"]?.toString() == "twofa.TWO_FACTOR_REQUIRED"

    private fun mergeBearerFromState(headers: Map<String, String>): Map<String, String> {
        val t = state.accessToken.trim()
        if (t.isEmpty()) return headers
        val out = headers.toMutableMap()
        out["Authorization"] = "Bearer $t"
        return out
    }

    /** 缩略图等请求未显式带 Authorization 时自动补 Bearer，与移动端一致 */
    private fun mergeDefaultBearerHeaders(headers: Map<String, String>): Map<String, String> {
        if (headers.keys.any { it.equals("Authorization", ignoreCase = true) }) return headers
        val t = state.accessToken.trim()
        if (t.isEmpty()) return headers
        return headers + ("Authorization" to "Bearer $t")
    }

    private fun normalizeJsonBusinessCodes(map: Map<String, Any?>): Map<String, Any?> {
        val code = map["code"]?.toString() ?: return map
        if (code != "service.NASCAB_SESSION_EXPIRED") return map
        val ctx = appContext ?: return map
        val msg =
            runCatching {
                ctx.getString(com.nascabos.tv.R.string.service_nascab_session_expired)
            }.getOrNull() ?: return map
        val out = map.toMutableMap()
        out["message"] = msg
        return out
    }

    private suspend fun executeJsonMapWithJwtRetry(
        isGet: Boolean,
        baseUrl: String,
        path: String,
        body: Any?,
        timeoutSeconds: Long,
        headers: Map<String, String>,
    ): Map<String, Any?> {
        val trimmed = baseUrl.trim()
        val normPath = if (path.startsWith("/")) path else "/$path"

        suspend fun directOnce(h: Map<String, String>): Pair<Int, Map<String, Any?>> {
            return if (trimmed == ApiConfig.p2pBaseUrl) {
                if (isGet) {
                    p2pGetJsonWithHttpCode(normPath, timeoutSeconds, h)
                } else {
                    p2pPostJsonWithHttpCode(normPath, body ?: emptyMap<String, Any?>(), timeoutSeconds, h)
                }
            } else {
                if (isGet) {
                    http.getJsonMapWithHttpCode(trimmed, normPath, timeoutSeconds, h)
                } else {
                    http.postJsonMapWithHttpCode(trimmed, normPath, body, timeoutSeconds, h)
                }
            }
        }

        var (code, map) = directOnce(headers)
        map = normalizeJsonBusinessCodes(map)
        if (code == 401 && !isRefreshJwtPath(normPath) && !isTwofaRequiredBody(map) && hasRefreshToken()) {
            val refreshed = jwtRefreshMutex.withLock { refreshJwtUnsafe() }
            if (refreshed) {
                val second = directOnce(mergeBearerFromState(headers))
                code = second.first
                map = normalizeJsonBusinessCodes(second.second)
            }
        }
        if (code == 401 && isRefreshJwtPath(normPath)) {
            notifyJwtSessionExpiredOnce()
        }
        return map
    }

    private suspend fun p2pGetJsonWithHttpCode(
        path: String,
        timeoutSeconds: Long,
        headers: Map<String, String>,
    ): Pair<Int, Map<String, Any?>> {
        return withContext(Dispatchers.IO) {
            val ok = ensureP2pConnected(timeoutMs = 15_000)
            if (!ok) throw IllegalStateException("p2p_not_connected")
            val uri = Uri.parse("${ApiConfig.p2pBaseUrl}$path")
            val res =
                requireP2p().sendRequest(
                    uri = uri,
                    method = "GET",
                    headers = headers,
                    body = ByteArray(0),
                    timeoutMs = timeoutSeconds * 1000L,
                )
            val bodyText = String(res.bodyBytes, Charsets.UTF_8)
            @Suppress("UNCHECKED_CAST")
            val parsed = gson.fromJson(bodyText, Map::class.java) as? Map<String, Any?> ?: emptyMap()
            res.status to parsed
        }
    }

    private suspend fun p2pPostJsonWithHttpCode(
        path: String,
        body: Any?,
        timeoutSeconds: Long,
        headers: Map<String, String>,
    ): Pair<Int, Map<String, Any?>> {
        return withContext(Dispatchers.IO) {
            val ok = ensureP2pConnected(timeoutMs = 15_000)
            if (!ok) throw IllegalStateException("p2p_not_connected")
            val uri = Uri.parse("${ApiConfig.p2pBaseUrl}$path")
            val payload = gson.toJson(body)
            val res =
                requireP2p().sendRequest(
                    uri = uri,
                    method = "POST",
                    headers = headers + mapOf("Content-Type" to "application/json"),
                    body = payload.toByteArray(Charsets.UTF_8),
                    timeoutMs = timeoutSeconds * 1000L,
                )
            val respBody = String(res.bodyBytes, Charsets.UTF_8)
            @Suppress("UNCHECKED_CAST")
            val parsed = gson.fromJson(respBody, Map::class.java) as? Map<String, Any?> ?: emptyMap()
            res.status to parsed
        }
    }

    /**
     * 使用 refreshToken 刷新 JWT；调用方需持有 [jwtRefreshMutex]（或由 [jwtRefreshMutex.withLock] 包裹）。
     * 不走 [postJsonMap]，避免 401 递归。
     */
    private suspend fun refreshJwtUnsafe(): Boolean {
        val rt = state.refreshToken.trim()
        if (rt.isEmpty()) return false
        val prevAccess = state.accessToken
        val base = state.baseUrl.trim()
        val path = "/api/auth/refreshJwt"
        val payload = mapOf("refreshToken" to rt)
        val (code, rawMap) =
            if (base == ApiConfig.p2pBaseUrl) {
                p2pPostJsonWithHttpCode(path, payload, timeoutSeconds = 15, headers = emptyMap())
            } else {
                http.postJsonMapWithHttpCode(base, path, payload, timeoutSeconds = 15, headers = emptyMap())
            }
        val map = normalizeJsonBusinessCodes(rawMap)
        if (code == 401) {
            notifyJwtSessionExpiredOnce()
            return false
        }
        val lr = AuthApiService.parseLoginResponse(map)
        val newAccess = lr.accessToken?.trim().orEmpty()
        val newRefresh = lr.refreshToken?.trim().orEmpty()
        if (!lr.success || newAccess.isEmpty() || newRefresh.isEmpty()) {
            return false
        }
        val newServerVersion = lr.serverVersion?.trim().orEmpty()
        state =
            state.copy(
                accessToken = newAccess,
                refreshToken = newRefresh,
                accessTokenExpiresAtEpochSec = lr.expiresIn?.takeIf { it > 0L },
                serverVersion = if (newServerVersion.isNotEmpty()) newServerVersion else state.serverVersion,
            )
        sessionExpiredNotified.set(false)
        persistRefreshedTokens(prevAccess, lr)
        restartProactiveJwtRefreshIfNeeded()
        return true
    }

    private suspend fun persistRefreshedTokens(
        oldAccessToken: String,
        lr: LoginResponse,
    ) {
        val ctx = appContext ?: return
        val store = ServerStore(ctx, gson)
        val last = runCatching { store.lastSelectedFlow.first() }.getOrNull() ?: return
        if (last.accessToken != oldAccessToken) return
        val exp = lr.expiresIn?.takeIf { it > 0L } ?: 0L
        val v = lr.serverVersion?.trim().orEmpty()
        val updated =
            last.copy(
                accessToken = lr.accessToken.orEmpty(),
                refreshToken = lr.refreshToken.orEmpty(),
                accessTokenExpiresAtEpochSec = exp,
                serverVersion = if (v.isNotEmpty()) v else last.serverVersion,
            )
        store.setLastSelected(updated)
        store.upsert(updated)
    }

    suspend fun requestP2pStream(
        uri: Uri,
        method: String,
        headers: Map<String, String>,
        body: ByteArray,
        timeoutMs: Long = 5 * 60_000L,
    ): P2pApiStreamResponse {
        return withContext(Dispatchers.IO) {
            val ok = ensureP2pConnected(timeoutMs = 15_000)
            if (!ok) throw IllegalStateException("p2p_not_connected")
            requireP2p().sendRequestStream(uri = uri, method = method, headers = headers, body = body, timeoutMs = timeoutMs)
        }
    }

    private suspend fun readP2pStreamFully(
        res: P2pApiStreamResponse,
        timeoutMs: Long,
    ): ByteArray {
        val maxBytes = 60L * 1024 * 1024
        val bos = ByteArrayOutputStream()
        var total = 0L
        try {
            withTimeout(timeoutMs) {
                res.stream.collect { chunk ->
                    if (chunk.isEmpty()) return@collect
                    total += chunk.size.toLong()
                    if (total > maxBytes) throw IllegalStateException("p2p_body_too_large")
                    bos.write(chunk)
                }
            }
        } finally {
            runCatching { res.cancel() }
        }
        return bos.toByteArray()
    }
}

enum class PairCodeError { Empty, Invalid }
