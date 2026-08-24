package com.nascabos.tv.core.api.p2p

import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Dns
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.net.Inet4Address
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.math.min

enum class P2pIcePreference { Auto, DirectOnly, RelayOnly }

enum class P2pTransportKind { Unknown, Direct, Relay }

class P2pManager(
    private val appContext: Context,
    private val gson: Gson = Gson(),
) {
    /** 中继连接成功后回调（用于触发升级检测等），由外部设置。 */
    var onRelayConnected: (() -> Unit)? = null
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val connectMutex = Mutex()

    private val unsafeClient: OkHttpClient by lazy { buildUnsafeClient() }
    private val httpClient: OkHttpClient by lazy { unsafeClient }

    private var ws: WebSocket? = null
    private var wsReady: CompletableDeferred<Unit>? = null
    private var heartbeatJob: Job? = null

    private var pairCode: String = ""
    private var sessionId: String = ""
    private var iceServers: List<Map<String, Any?>> = emptyList()
    private var rtc: P2pRtcClient? = null

    private val uploadLink = LinkState(label = "upload", channels = listOf(P2pRtcChannel.Upload))
    private val downloadLink = LinkState(label = "download", channels = listOf(P2pRtcChannel.Download))
    private val videoLink = LinkState(label = "video", channels = listOf(P2pRtcChannel.Video))

    @Volatile
    var isReady: Boolean = false
        private set

    @Volatile
    var lastConnectError: Throwable? = null
        private set

    @Volatile
    var icePreference: P2pIcePreference = P2pIcePreference.Auto
        private set

    @Volatile
    var activeIcePreference: P2pIcePreference = P2pIcePreference.Auto
        private set

    @Volatile
    var transportKind: P2pTransportKind = P2pTransportKind.Unknown
        private set

    @Volatile
    var relayAddress: String = ""
        private set

    private var reconnectAttempts: Int = 0
    private var allowReconnect: Boolean = false
    private var reconnectJob: Job? = null

    @Volatile
    private var lastPongAtMs: Long = 0L

    private var connectivityCallback: ConnectivityManager.NetworkCallback? = null
    private var autoSwitchInProgress: Boolean = false
    private var lastAutoSwitchAttemptAtMs: Long = 0
    private var lastAutoSwitchProbeAtMs: Long = 0
    private var autoSwitchDebounceJob: Job? = null

    suspend fun connectByPairCode(
        code: String,
        preference: P2pIcePreference = P2pIcePreference.Auto,
        resetReconnectAttempts: Boolean = true,
    ) {
        connectMutex.withLock {
            val trimmed = code.trim()
            if (trimmed.isEmpty()) throw IllegalArgumentException("pair_code_empty")

            if (resetReconnectAttempts) {
                reconnectAttempts = 0
                reconnectJob?.cancel()
                reconnectJob = null
            }

            icePreference = preference
            transportKind = when (preference) {
                P2pIcePreference.RelayOnly -> P2pTransportKind.Relay
                P2pIcePreference.DirectOnly -> P2pTransportKind.Direct
                else -> P2pTransportKind.Unknown
            }

            if (isReady && pairCode == trimmed && activeIcePreference == icePreference) return@withLock

            allowReconnect = true
            pairCode = trimmed

            cleanup(disableReconnect = false)

            val created = createSession(trimmed, linkLabel = null)
            val wsUrl = created.wsUrl
            val sid = created.sessionId
            if (wsUrl.isBlank() || sid.isBlank()) throw IllegalStateException("pair_session_invalid")

            sessionId = sid
            isReady = false
            wsReady = CompletableDeferred()

            openWs(wsUrl)
            startHeartbeat()

            try {
                wsReady?.let { kotlinx.coroutines.withTimeout(20_000) { it.await() } }
            } catch (e: Exception) {
                lastConnectError = e
                cleanup(disableReconnect = false)
                scheduleReconnect()
                throw e
            }

            val factory = P2pWebRtc.getFactory(appContext)
            val icePolicy = if (icePreference == P2pIcePreference.RelayOnly) "relay" else null
            val currentWs = ws ?: throw IllegalStateException("p2p_ws_closed")
            val client = P2pRtcClient(
                sessionId = sessionId,
                iceServers = iceServers,
                iceTransportPolicy = icePolicy,
                sendWsJson = { payload ->
                    runCatching {
                        P2pSignalingBinary.encodeSignaling(payload)?.let { currentWs.send(ByteString.of(*it)) }
                    }
                },
                factory = factory,
                gson = gson,
                onRtcConnectionLost = {
                    if (ApiController.isDebuggable()) {
                        Log.d("P2pManager", "onRtcConnectionLost: WebRTC FAILED/CLOSED/DISCONNECTED, scheduling reconnect")
                    }
                    cleanup(disableReconnect = false)
                    scheduleReconnect()
                },
            )
            rtc = client

            try {
                client.start(listOf(P2pRtcChannel.Api, P2pRtcChannel.File))
            } catch (e: Exception) {
                lastConnectError = e
                cleanup(disableReconnect = false)
                scheduleReconnect()
                throw IllegalStateException("p2p_rtc_init_failed_$e")
            }

            isReady = true
            activeIcePreference = icePreference
            lastConnectError = null
            startAutoSwitchMonitor()

            // 与 Flutter 对齐：约 800ms 后取 transport 类型；若为 relay 则立即触发升级探测并执行中继连上回调（如升级检测）
            scope.launch {
                delay(800)
                val currentRtc = rtc ?: return@launch
                runCatching {
                    val stats = currentRtc.getTransportStats()
                    val type = stats["type"]?.trim()?.lowercase().orEmpty()
                    when {
                        type == "relay" -> {
                            transportKind = P2pTransportKind.Relay
                            onRelayConnected?.let { cb ->
                                Handler(Looper.getMainLooper()).post { cb() }
                            }
                            runAutoSwitchProbe(ignoreThrottle = true)
                        }
                        type == "host" || type == "srflx" || type == "prflx" ->
                            transportKind = P2pTransportKind.Direct
                    }
                }
            }
        }
    }

    suspend fun ensureConnected(timeoutMs: Long = 15_000): Boolean {
        if (!isReady) {
            val code = pairCode.trim()
            if (code.isEmpty()) return false
            try {
                kotlinx.coroutines.withTimeout(timeoutMs) {
                    connectByPairCode(code, preference = P2pIcePreference.Auto, resetReconnectAttempts = false)
                }
            } catch (_: Exception) {}
        }
        return isReady
    }

    suspend fun forceReconnect(timeoutMs: Long = 15_000): Boolean {
        val code = pairCode.trim()
        if (code.isEmpty()) return false
        cleanup(disableReconnect = false)
        try {
            kotlinx.coroutines.withTimeout(timeoutMs) {
                connectByPairCode(code, preference = icePreference, resetReconnectAttempts = false)
            }
        } catch (_: Exception) {}
        return isReady
    }

    suspend fun disconnect() {
        connectMutex.withLock {
            cleanup(disableReconnect = true)
        }
    }

    /** 预连接 video 通道，供播放器在 P2P 模式下使用。在打开播放器前调用，避免首包超时。 */
    suspend fun ensureVideoLinkReady(timeoutMs: Long = 15_000): Boolean {
        if (!isReady) {
            val ok = ensureConnected(timeoutMs)
            if (!ok) return false
        }
        return try {
            ensureLinkConnected(videoLink)
            true
        } catch (_: Exception) {
            false
        }
    }

    suspend fun sendRequest(
        uri: android.net.Uri,
        method: String,
        headers: Map<String, String>,
        body: ByteArray,
        timeoutMs: Long = 5_000,
    ): P2pApiResponse {
        val ok = ensureConnected(timeoutMs = 15_000)
        if (!ok) throw IllegalStateException("p2p_not_connected")
        val resolved = P2pChannelUtil.resolve(uri)
        val channel = resolved.channel
        val path = resolved.path
        val client = when (channel) {
            P2pRtcChannel.Upload -> {
                ensureLinkConnected(uploadLink)
                uploadLink.rtc
            }
            P2pRtcChannel.Download -> {
                ensureLinkConnected(downloadLink)
                downloadLink.rtc
            }
            P2pRtcChannel.Video -> {
                ensureLinkConnected(videoLink)
                videoLink.rtc
            }
            else -> rtc
        } ?: throw IllegalStateException("p2p_not_connected")
        return client.sendRequest(channel, method, path, headers, body, timeoutMs = timeoutMs)
    }

    suspend fun sendRequestStream(
        uri: android.net.Uri,
        method: String,
        headers: Map<String, String>,
        body: ByteArray,
        timeoutMs: Long = 5 * 60_000L,
    ): P2pApiStreamResponse {
        val ok = ensureConnected(timeoutMs = 15_000)
        if (!ok) throw IllegalStateException("p2p_not_connected")
        val resolved = P2pChannelUtil.resolve(uri)
        val channel = resolved.channel
        val path = resolved.path
        val client = when (channel) {
            P2pRtcChannel.Upload -> {
                ensureLinkConnected(uploadLink)
                uploadLink.rtc
            }
            P2pRtcChannel.Download -> {
                ensureLinkConnected(downloadLink)
                downloadLink.rtc
            }
            P2pRtcChannel.Video -> {
                ensureLinkConnected(videoLink)
                videoLink.rtc
            }
            else -> rtc
        } ?: throw IllegalStateException("p2p_not_connected")
        return client.sendRequestStream(
            channel = channel,
            method = method,
            path = path,
            headers = headers,
            bodyBytes = body,
            timeoutMs = timeoutMs,
        )
    }

    fun openWebSocketTunnel(uri: android.net.Uri): P2pWsTunnel {
        val resolved = P2pChannelUtil.resolve(uri)
        val channel = resolved.channel
        val client = when (channel) {
            P2pRtcChannel.Upload -> uploadLink.rtc
            P2pRtcChannel.Download -> downloadLink.rtc
            P2pRtcChannel.Video -> videoLink.rtc
            else -> rtc
        } ?: throw IllegalStateException("p2p_not_connected")
        return client.openWebSocketChannel(channel = channel, path = resolved.path)
    }

    fun formatConnectError(e: Throwable): String {
        val s = e.toString()
        if (s.contains("pair_code_empty")) return "pair_code_empty"
        if (s.contains("pair_session_http_404")) return "pair_server_unreachable"
        if (s.contains("pair_session_http_")) return "pair_code_invalid"
        if (s.contains("pair_session_invalid")) return "p2p_session_invalid"
        if (s.contains("pair_ws_url_invalid")) return "p2p_ws_url_invalid"
        if (s.contains("p2p_relay_not_available")) return "p2p_relay_not_available"
        if (s.contains("p2p_ws_error") || s.contains("p2p_ws_closed")) return "p2p_channel_failed"
        return s
    }

    private fun scheduleReconnect() {
        if (!allowReconnect) return
        val code = pairCode.trim()
        if (code.isEmpty()) return
        if (reconnectJob != null) return

        val attempt = reconnectAttempts
        val exp = min(attempt, 5)
        val baseSeconds = 2 * (1 shl exp)
        val seconds = min(baseSeconds, 30)
        reconnectAttempts = attempt + 1

        reconnectJob = scope.launch {
            delay(seconds * 1000L)
            reconnectJob = null
            try {
                connectByPairCode(code, preference = icePreference, resetReconnectAttempts = false)
                reconnectAttempts = 0
            } catch (_: Exception) {
                scheduleReconnect()
            }
        }
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(15_000)
                val nowMs = System.currentTimeMillis()
                if (lastPongAtMs > 0L && nowMs - lastPongAtMs > 45_000L) {
                    if (ApiController.isDebuggable()) {
                        Log.d("P2pManager", "heartbeat: no pong for ${nowMs - lastPongAtMs}ms, scheduling reconnect")
                    }
                    cleanup(disableReconnect = false)
                    scheduleReconnect()
                    return@launch
                }
                val current = ws ?: continue
                val bytes = P2pSignalingBinary.encodeSignaling(mapOf("type" to "ping", "ts" to nowMs))
                runCatching { bytes?.let { current.send(ByteString.of(*it)) } }
            }
        }
    }

    private fun openWs(wsUrl: String) {
        val request =
            Request.Builder()
                .url(wsUrl)
                .header("Origin", ApiConfig.signalApiBaseUrl)
                .build()
        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (ApiController.isDebuggable()) {
                    Log.d("P2pManager", "ws: onOpen http=${response.code} msg='${response.message}'")
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleWsMessage(text.toByteArray(Charsets.UTF_8))
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                handleWsMessage(bytes.toByteArray())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (ApiController.isDebuggable()) {
                    Log.d("P2pManager", "ws: onFailure http=${response?.code} err='${t}'")
                }
                lastConnectError = t
                wsReady?.completeExceptionally(t)
                cleanup(disableReconnect = false)
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (ApiController.isDebuggable()) {
                    Log.d("P2pManager", "ws: onClosed code=$code reason='${reason.trim()}'")
                }
                lastConnectError = IllegalStateException("p2p_ws_closed")
                wsReady?.completeExceptionally(IllegalStateException("p2p_ws_closed"))
                cleanup(disableReconnect = false)
                scheduleReconnect()
            }
        }
        ws = httpClient.newWebSocket(request, listener)
    }

    private fun handleWsMessage(raw: ByteArray) {
        if (raw.isEmpty()) return
        val msg =
            P2pSignalingBinary.decodeSignaling(raw) ?: run {
                if (ApiController.isDebuggable()) {
                    val preview = String(raw, Charsets.UTF_8).trim().replace("\n", " ").take(240)
                    if (preview.isNotEmpty()) {
                        Log.d("P2pManager", "ws: onMessage decodeFailed preview='$preview'")
                    }
                }
                return
            }
        val type = msg["type"]?.toString().orEmpty()
        if (type == "pong") {
            lastPongAtMs = System.currentTimeMillis()
            Log.d("P2pManager", "heartbeat: pong ok")
            return
        }
        if (type.startsWith("webrtc:")) {
            rtc?.handleWsMessage(msg)
            return
        }
        if (ApiController.isDebuggable() && type.isNotEmpty()) {
            Log.d("P2pManager", "ws: onMessage type='$type' keys=${msg.keys.take(20)}")
        }
        if (type == "error") {
            val code = msg["code"]?.toString() ?: msg["errorCode"]?.toString() ?: "P2P_ERROR"
            lastConnectError = IllegalStateException("p2p_ws_error_$code")
            wsReady?.completeExceptionally(IllegalStateException("p2p_ws_error_$code"))
            cleanup(disableReconnect = false)
            scheduleReconnect()
            return
        }
        if (type == "session:ready") {
            lastPongAtMs = System.currentTimeMillis()
            val sid = msg["sessionId"]?.toString().orEmpty()
            if (sid.isNotEmpty()) sessionId = sid
            val iceRaw = msg["iceServers"]
            iceServers = applyIcePreference(parseIceServers(iceRaw), icePreference)
            relayAddress = extractTurnServerAddress(iceServers)
            wsReady?.complete(Unit)
            return
        }
        if (type == "session:closed") {
            cleanup(disableReconnect = false)
            scheduleReconnect()
            return
        }
    }

    private fun cleanup(disableReconnect: Boolean) {
        stopAutoSwitchMonitor()
        isReady = false
        lastPongAtMs = 0L
        sessionId = ""
        relayAddress = ""
        transportKind = P2pTransportKind.Unknown
        activeIcePreference = P2pIcePreference.Auto

        if (disableReconnect) {
            allowReconnect = false
            pairCode = ""
            reconnectAttempts = 0
            reconnectJob?.cancel()
            reconnectJob = null
        }

        heartbeatJob?.cancel()
        heartbeatJob = null

        wsReady?.cancel()
        wsReady = null

        val oldRtc = rtc
        rtc = null
        scope.launch { runCatching { oldRtc?.close() } }

        ws?.close(1000, "close")
        ws = null

        uploadLink.cleanup()
        downloadLink.cleanup()
        videoLink.cleanup()
    }

    private fun parseIceServers(raw: Any?): List<Map<String, Any?>> {
        if (raw !is List<*>) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        for (e in raw) {
            if (e is Map<*, *>) {
                @Suppress("UNCHECKED_CAST")
                out += e.entries.associate { it.key.toString() to it.value } as Map<String, Any?>
            }
        }
        return out
    }

    private fun applyIcePreference(
        servers: List<Map<String, Any?>>,
        pref: P2pIcePreference,
    ): List<Map<String, Any?>> {
        if (pref == P2pIcePreference.Auto) return servers
        val out = ArrayList<Map<String, Any?>>()
        for (s in servers) {
            val urlsAny = s["urls"]
            val urlList = when (urlsAny) {
                is String -> listOf(urlsAny.trim()).filter { it.isNotEmpty() }
                is List<*> -> urlsAny.mapNotNull { it?.toString()?.trim() }.filter { it.isNotEmpty() }
                else -> emptyList()
            }
            val hasTurn = urlList.any { isTurnUrl(it) }
            if (pref == P2pIcePreference.DirectOnly) {
                if (hasTurn) {
                    val nextUrls = urlList.filterNot { isTurnUrl(it) }
                    if (nextUrls.isEmpty()) continue
                    out += s.toMutableMap().also { it["urls"] = if (nextUrls.size == 1) nextUrls[0] else nextUrls }
                } else {
                    out += s
                }
            } else if (pref == P2pIcePreference.RelayOnly) {
                if (!hasTurn) continue
                val nextUrls = urlList.filter { isTurnUrl(it) }
                if (nextUrls.isEmpty()) continue
                out += s.toMutableMap().also { it["urls"] = if (nextUrls.size == 1) nextUrls[0] else nextUrls }
            }
        }
        if (pref == P2pIcePreference.RelayOnly) {
            val hasAnyTurn = out.any { s ->
                val urlsAny = s["urls"]
                val urls = when (urlsAny) {
                    is String -> listOf(urlsAny)
                    is List<*> -> urlsAny.mapNotNull { it?.toString() }
                    else -> emptyList()
                }
                urls.any { isTurnUrl(it) }
            }
            if (!hasAnyTurn) throw IllegalStateException("p2p_relay_not_available")
        }
        return if (out.isEmpty()) servers else out
    }

    private fun isTurnUrl(url: String): Boolean {
        val s = url.trim().lowercase()
        return s.startsWith("turn:") || s.startsWith("turns:")
    }

    private fun extractTurnServerAddress(servers: List<Map<String, Any?>>): String {
        for (s in servers) {
            val urlsAny = s["urls"]
            val urlList = when (urlsAny) {
                is String -> listOf(urlsAny.trim()).filter { it.isNotEmpty() }
                is List<*> -> urlsAny.mapNotNull { it?.toString()?.trim() }.filter { it.isNotEmpty() }
                else -> emptyList()
            }
            for (u in urlList) {
                if (!isTurnUrl(u)) continue
                val noScheme = u.replace(Regex("^turns?:", RegexOption.IGNORE_CASE), "")
                val atSplit = noScheme.split("@")
                val hostPart = (if (atSplit.size == 2) atSplit[1] else atSplit[0]).trim()
                val qIndex = hostPart.indexOf("?")
                return (if (qIndex >= 0) hostPart.substring(0, qIndex) else hostPart).trim()
            }
        }
        return ""
    }

    private data class CreatedSession(val wsUrl: String, val sessionId: String)

    private suspend fun createSession(pairCode: String, linkLabel: String?): CreatedSession {
        return kotlinx.coroutines.withContext(Dispatchers.IO) {
            val url = "${ApiConfig.signalApiBaseUrl}/api/p2p/pair/session/create"
            val bodyMap = mutableMapOf<String, Any?>("pairCode" to pairCode)
            val label = linkLabel?.trim().orEmpty()
            if (label.isNotEmpty()) bodyMap["link"] = label
            if (ApiController.isDebuggable()) {
                val masked = if (pairCode.length <= 2) "*".repeat(pairCode.length) else pairCode.take(1) + "***" + pairCode.takeLast(1)
                Log.d("P2pManager", "createSession: start url='$url' pairCode='$masked' link='${label}'")
            }
            val jsonBody = gson.toJson(bodyMap).toRequestBody("application/json".toMediaType())
            val req = Request.Builder().url(url).post(jsonBody).build()
            val res = httpClient.newCall(req).execute()
            res.use {
                if (it.code < 200 || it.code >= 300) throw IllegalStateException("pair_session_http_${it.code}")
                val raw = it.body?.string().orEmpty()
                val decoded = parseJsonMap(raw) ?: throw IllegalStateException("pair_session_invalid_response")
                val dataAny = decoded["data"]
                val data = if (dataAny is Map<*, *>) {
                    dataAny.entries.associate { e -> e.key.toString() to e.value }
                } else {
                    decoded
                }
                val wsUrl = data["wsUrl"]?.toString().orEmpty()
                val sessionId = data["sessionId"]?.toString().orEmpty()
                if (ApiController.isDebuggable()) {
                    Log.d(
                        "P2pManager",
                        "createSession: ok http=${it.code} link='${label}' wsUrlLen=${wsUrl.trim().length} sessionIdLen=${sessionId.trim().length} keys=${data.keys.take(20)}",
                    )
                }
                CreatedSession(wsUrl, sessionId)
            }
        }
    }

    private fun parseJsonMap(text: String): Map<String, Any?>? {
        return runCatching {
            val type = object : TypeToken<Map<String, Any?>>() {}.type
            gson.fromJson<Map<String, Any?>>(text, type)
        }.getOrNull()
    }

    private fun buildUnsafeClient(): OkHttpClient {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(trustAll), SecureRandom())
        val sslSocketFactory: SSLSocketFactory = sslContext.socketFactory
        val verifier = HostnameVerifier { _, _ -> true }
        val ipv4FirstDns =
            object : Dns {
                override fun lookup(hostname: String): List<java.net.InetAddress> {
                    val all = Dns.SYSTEM.lookup(hostname)
                    val v4 = all.filterIsInstance<Inet4Address>()
                    val rest = all.filterNot { it is Inet4Address }
                    return v4 + rest
                }
            }
        return OkHttpClient.Builder()
            .sslSocketFactory(sslSocketFactory, trustAll)
            .hostnameVerifier(verifier)
            .dns(ipv4FirstDns)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .writeTimeout(0, TimeUnit.MILLISECONDS)
            .build()
    }

    private fun startAutoSwitchMonitor() {
        if (connectivityCallback != null) return
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scheduleAutoSwitchDebounced()
            }

            override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                scheduleAutoSwitchDebounced()
            }
        }
        connectivityCallback = cb
        val req = NetworkRequest.Builder().build()
        runCatching { cm.registerNetworkCallback(req, cb) }
        scheduleAutoSwitchDebounced()
    }

    private fun stopAutoSwitchMonitor() {
        autoSwitchDebounceJob?.cancel()
        autoSwitchDebounceJob = null
        autoSwitchInProgress = false
        lastAutoSwitchAttemptAtMs = 0
        lastAutoSwitchProbeAtMs = 0

        val cb = connectivityCallback ?: return
        connectivityCallback = null
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching { cm.unregisterNetworkCallback(cb) }
    }

    private fun shouldAutoUpgradeRelayToDirect(): Boolean {
        if (!isReady) return false
        if (transportKind != P2pTransportKind.Relay) return false
        if (activeIcePreference != P2pIcePreference.Auto) return false
        if (icePreference != P2pIcePreference.Auto) return false
        if (uploadLink.rtc != null || downloadLink.rtc != null || videoLink.rtc != null) return false
        return true
    }

    private fun scheduleAutoSwitchDebounced() {
        if (!shouldAutoUpgradeRelayToDirect()) return
        autoSwitchDebounceJob?.cancel()
        autoSwitchDebounceJob = scope.launch {
            delay(800)
            runAutoSwitchProbe()
        }
    }

    /** @param ignoreThrottle 为 true 时跳过 10s 节流，用于中继连上后立即做一次升级探测（与 Flutter 一致） */
    private suspend fun runAutoSwitchProbe(ignoreThrottle: Boolean = false) {
        if (!shouldAutoUpgradeRelayToDirect()) return
        val nowMs = System.currentTimeMillis()
        if (!ignoreThrottle && nowMs - lastAutoSwitchProbeAtMs < 10_000) return
        lastAutoSwitchProbeAtMs = nowMs
        attemptUpgradeRelayToDirect()
    }

    private suspend fun attemptUpgradeRelayToDirect() {
        if (!shouldAutoUpgradeRelayToDirect()) return
        if (autoSwitchInProgress) return
        val nowMs = System.currentTimeMillis()
        if (nowMs - lastAutoSwitchAttemptAtMs < 20_000) return
        lastAutoSwitchAttemptAtMs = nowMs

        val code = pairCode.trim()
        if (code.isEmpty()) return

        autoSwitchInProgress = true
        val prev = icePreference
        try {
            connectByPairCode(code, preference = P2pIcePreference.DirectOnly, resetReconnectAttempts = false)
            delay(650)
            val stats = rtc?.getTransportStats().orEmpty()
            val type = stats["type"]?.trim()?.lowercase().orEmpty()
            if (type == "relay" || type.isEmpty()) throw IllegalStateException("p2p_direct_not_available")
            transportKind = P2pTransportKind.Direct
        } catch (_: Exception) {
            runCatching {
                connectByPairCode(code, preference = P2pIcePreference.Auto, resetReconnectAttempts = false)
            }
        } finally {
            if (prev == P2pIcePreference.Auto) {
                icePreference = P2pIcePreference.Auto
                activeIcePreference = P2pIcePreference.Auto
            }
            autoSwitchInProgress = false
        }
    }

    private suspend fun ensureLinkConnected(link: LinkState) {
        if (link.rtc != null) return
        val code = pairCode.trim()
        if (code.isEmpty()) throw IllegalStateException("p2p_not_connected")
        val ok = ensureConnected(timeoutMs = 15_000)
        if (!ok) throw IllegalStateException("p2p_not_connected")

        val created = createSession(code, linkLabel = link.label)
        if (created.wsUrl.isBlank() || created.sessionId.isBlank()) throw IllegalStateException("pair_session_invalid")

        link.sessionId = created.sessionId
        link.wsReady = CompletableDeferred()
        link.openWs(httpClient, created.wsUrl)
        link.startHeartbeat(gson)

        try {
            kotlinx.coroutines.withTimeout(10_000) { link.wsReady?.await() }
        } catch (e: Exception) {
            link.cleanup()
            throw e
        }

        val factory = P2pWebRtc.getFactory(appContext)
        val icePolicy = if (icePreference == P2pIcePreference.RelayOnly) "relay" else null
        val currentWs = link.ws ?: throw IllegalStateException("p2p_ws_closed")
        val client = P2pRtcClient(
            sessionId = link.sessionId,
            iceServers = link.iceServers,
            iceTransportPolicy = icePolicy,
            sendWsJson = { payload ->
                runCatching {
                    P2pSignalingBinary.encodeSignaling(payload)?.let { currentWs.send(ByteString.of(*it)) }
                }
            },
            factory = factory,
            gson = gson,
        )
        link.rtc = client
        client.start(link.channels)
    }

    private inner class LinkState(
        val label: String,
        val channels: List<P2pRtcChannel>,
    ) {
        var ws: WebSocket? = null
        var wsReady: CompletableDeferred<Unit>? = null
        var heartbeatJob: Job? = null
        var sessionId: String = ""
        var iceServers: List<Map<String, Any?>> = emptyList()
        var rtc: P2pRtcClient? = null

        fun openWs(client: OkHttpClient, wsUrl: String) {
            val request =
                Request.Builder()
                    .url(wsUrl)
                    .header("Origin", ApiConfig.signalApiBaseUrl)
                    .build()
            val listener = object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, text: String) {
                    handleWsMessage(text.toByteArray(Charsets.UTF_8))
                }

                override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                    handleWsMessage(bytes.toByteArray())
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    wsReady?.completeExceptionally(t)
                    cleanup()
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    wsReady?.completeExceptionally(IllegalStateException("p2p_ws_closed"))
                    cleanup()
                }
            }
            ws = client.newWebSocket(request, listener)
        }

        fun startHeartbeat(gson: Gson) {
            heartbeatJob?.cancel()
            heartbeatJob = scope.launch {
                while (isActive) {
                    delay(15_000)
                    val current = ws ?: continue
                    val bytes = P2pSignalingBinary.encodeSignaling(mapOf("type" to "ping", "ts" to System.currentTimeMillis()))
                    runCatching { bytes?.let { current.send(ByteString.of(*it)) } }
                }
            }
        }

        private fun handleWsMessage(raw: ByteArray) {
            if (raw.isEmpty()) return
            val msg = P2pSignalingBinary.decodeSignaling(raw) ?: return
            val type = msg["type"]?.toString().orEmpty()
            if (type == "pong") return
            if (type.startsWith("webrtc:")) {
                rtc?.handleWsMessage(msg)
                return
            }
            if (type == "error") {
                wsReady?.completeExceptionally(IllegalStateException("p2p_ws_error"))
                cleanup()
                return
            }
            if (type == "session:ready") {
                val sid = msg["sessionId"]?.toString().orEmpty()
                if (sid.isNotEmpty()) sessionId = sid
                val iceRaw = msg["iceServers"]
                iceServers = applyIcePreference(parseIceServers(iceRaw), icePreference)
                wsReady?.complete(Unit)
                return
            }
            if (type == "session:closed") {
                wsReady?.completeExceptionally(IllegalStateException("p2p_ws_closed"))
                cleanup()
            }
        }

        fun cleanup() {
            heartbeatJob?.cancel()
            heartbeatJob = null
            wsReady?.cancel()
            wsReady = null
            val old = rtc
            rtc = null
            scope.launch { runCatching { old?.close() } }
            ws?.close(1000, "close")
            ws = null
            sessionId = ""
            iceServers = emptyList()
        }
    }
}
