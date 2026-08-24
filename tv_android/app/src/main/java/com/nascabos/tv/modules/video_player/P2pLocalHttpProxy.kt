package com.nascabos.tv.modules.video_player

import android.net.Uri
import android.util.Log
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket

object P2pLocalHttpProxy {
    private const val TAG = "P2pProxy"

    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var serverSocket: ServerSocket? = null
    private var acceptJob: Job? = null
    private var stopDelayJob: Job? = null
    @Volatile
    private var port: Int = -1

    @Volatile
    private var p2pActive: Boolean = false

    /** 与 P2P 连接生命周期同步：P2P 连接时启动，切回直连时停止。由 ApiController.setBaseUrl 调用。 */
    fun setP2pActive(active: Boolean) {
        if (p2pActive == active) return
        p2pActive = active
        stopDelayJob?.cancel()
        stopDelayJob = null
        if (active) {
            Log.d(TAG, "p2p active -> ensure start")
            ensureStarted()
        } else {
            Log.d(TAG, "p2p inactive -> schedule stop")
            stopDelayJob = scope.launch {
                delay(800)
                stopDelayJob = null
                if (!p2pActive) stop()
            }
        }
    }

    fun proxyUrlIfNeeded(url: String): String {
        val raw = url.trim()
        if (raw.isEmpty()) return raw
        val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return raw
        val host = uri.host?.trim().orEmpty()
        val needsProxy = host == "p2p.local" || ApiController.baseUrl.trim() == ApiConfig.p2pBaseUrl
        if (!needsProxy || !p2pActive) return raw
        val p = ensureStarted()
        if (p <= 0) return raw
        return uri.buildUpon().encodedAuthority("127.0.0.1:$p").build().toString()
    }

    fun stop() {
        stopDelayJob?.cancel()
        stopDelayJob = null
        acceptJob?.cancel()
        acceptJob = null
        runCatching { serverSocket?.close() }
        serverSocket = null
        port = -1
    }

    private fun ensureStarted(): Int {
        if (!p2pActive) return -1
        if (port > 0 && serverSocket != null) return port
        synchronized(this) {
            if (port > 0 && serverSocket != null) return port
            val ss =
                runCatching { ServerSocket(0, 50, InetAddress.getByName("127.0.0.1")) }.getOrNull()
                    ?: return -1
            serverSocket = ss
            port = ss.localPort
            acceptJob?.cancel()
            acceptJob =
                scope.launch {
                    while (isActive) {
                        val s = runCatching { ss.accept() }.getOrNull() ?: break
                        launch { handleSocket(s) }
                    }
                }
            return port
        }
    }

    private suspend fun handleSocket(socket: Socket) {
        socket.soTimeout = 15_000
        socket.tcpNoDelay = true
        val output = BufferedOutputStream(socket.getOutputStream())
        var respCancel: (() -> Unit)? = null
        var headersSent = false
        var exitedByException = false
        Log.d(TAG, "handleSocket: start")
        try {
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.ISO_8859_1))
            val requestLine = reader.readLine()?.trim().orEmpty()
            if (requestLine.isEmpty()) {
                writeHttp(output, 400, "Bad Request", emptyMap(), ByteArray(0))
                return
            }
            val parts = requestLine.split(' ')
            val method = parts.getOrNull(0)?.trim()?.uppercase().orEmpty()
            val rawTarget = parts.getOrNull(1)?.trim().orEmpty()
            if (method.isEmpty() || rawTarget.isEmpty()) {
                writeHttp(output, 400, "Bad Request", emptyMap(), ByteArray(0))
                return
            }
            val targetPath =
                if (rawTarget.startsWith("http://") || rawTarget.startsWith("https://")) {
                    val u = runCatching { Uri.parse(rawTarget) }.getOrNull()
                    val p = u?.encodedPath.orEmpty()
                    val q = u?.encodedQuery.orEmpty()
                    if (q.isNotEmpty()) "$p?$q" else p
                } else {
                    rawTarget
                }
            if (targetPath.isEmpty() || targetPath == "*") {
                writeHttp(output, 400, "Bad Request", emptyMap(), ByteArray(0))
                return
            }
            if (!targetPath.startsWith("/")) {
                writeHttp(output, 400, "Bad Request", emptyMap(), ByteArray(0))
                return
            }

            val headers = LinkedHashMap<String, String>()
            while (true) {
                val line = reader.readLine() ?: break
                val l = line.trimEnd()
                if (l.isEmpty()) break
                val idx = l.indexOf(':')
                if (idx <= 0) continue
                val k = l.substring(0, idx).trim()
                val v = l.substring(idx + 1).trim()
                if (k.isNotEmpty()) headers[k] = v
            }

            val targetUri = Uri.parse("${ApiConfig.p2pBaseUrl}$targetPath")
            val passthroughHeaders = LinkedHashMap<String, String>()
            headers.entries.firstOrNull { it.key.equals("Range", ignoreCase = true) }?.let { passthroughHeaders["Range"] = it.value }
            headers.entries.firstOrNull { it.key.equals("If-Range", ignoreCase = true) }?.let { passthroughHeaders["If-Range"] = it.value }
            if (passthroughHeaders.none { it.key.equals("Authorization", ignoreCase = true) } &&
                !targetPath.contains("accessToken=")
            ) {
                val token = ApiController.accessToken.trim()
                if (token.isNotEmpty()) {
                    passthroughHeaders["Authorization"] = "Bearer $token"
                }
            }

            Log.d(TAG, "request: method=$method pathLen=${targetPath.length} pathPreview=${targetPath.take(120)}... range=${passthroughHeaders["Range"].orEmpty()} hasAuth=${passthroughHeaders.containsKey("Authorization")}")

            val resp =
                ApiController.requestP2pStream(
                    uri = targetUri,
                    method = if (method == "HEAD") "GET" else method,
                    headers = passthroughHeaders,
                    body = ByteArray(0),
                    timeoutMs = 5 * 60_000L,
                )
            respCancel = resp.cancel
            Log.d(TAG, "requestP2pStream done: status=${resp.status}")
            if (resp.status >= 400) {
                Log.e(TAG, "P2P request failed: status=${resp.status} - check server logs for details")
            }

            val normalizedHeaders = normalizeResponseHeaders(resp.status, resp.headers).toMutableMap()
            val hasContentLength = normalizedHeaders.entries.any { it.key.equals("Content-Length", ignoreCase = true) }
            val useChunked = !hasContentLength && method != "HEAD"
            if (useChunked) {
                normalizedHeaders.entries.removeAll { it.key.equals("Content-Length", ignoreCase = true) }
                normalizedHeaders.entries.removeAll { it.key.equals("Transfer-Encoding", ignoreCase = true) }
                normalizedHeaders["Transfer-Encoding"] = "chunked"
            }
            Log.d(TAG, "response: status=${resp.status} contentType=${normalizedHeaders["Content-Type"].orEmpty()} useChunked=$useChunked")

            writeHttpHeaders(output, resp.status, reasonPhrase(resp.status), normalizedHeaders)
            headersSent = true

            if (method != "HEAD") {
                var pendingFlushBytes = 0
                var chunkCount = 0
                var totalBytes = 0L
                resp.stream.collect { chunk ->
                    if (chunk.isEmpty()) return@collect
                    chunkCount++
                    totalBytes += chunk.size
                    if (chunkCount == 1) {
                        Log.d(TAG, "firstChunk: size=${chunk.size}")
                        if (resp.status >= 400) {
                            val bodyPreview = chunk.toString(Charsets.UTF_8).take(500)
                            Log.e(TAG, "error body preview (status=${resp.status}): $bodyPreview")
                        }
                    }
                    if (chunkCount % 20 == 0 || chunkCount <= 3) {
                        Log.d(TAG, "stream progress: chunks=$chunkCount totalBytes=$totalBytes")
                    }
                    try {
                        if (useChunked) {
                            val header = Integer.toHexString(chunk.size) + "\r\n"
                            output.write(header.toByteArray(Charsets.ISO_8859_1))
                            output.write(chunk)
                            output.write("\r\n".toByteArray(Charsets.ISO_8859_1))
                        } else {
                            output.write(chunk)
                        }
                        pendingFlushBytes += chunk.size
                        if (chunkCount <= 2 || pendingFlushBytes >= 256 * 1024) {
                            output.flush()
                            pendingFlushBytes = 0
                        }
                    } catch (e: Exception) {
                        val msg = e.message.orEmpty()
                        val isClientAbort =
                            msg.contains("Broken pipe", ignoreCase = true) ||
                                msg.contains("Connection reset", ignoreCase = true) ||
                                msg.contains("socket closed", ignoreCase = true)
                        if (isClientAbort) {
                            Log.d(TAG, "client abort during write: $msg")
                            runCatching { respCancel?.invoke() }
                        }
                        throw e
                    }
                }
                if (useChunked) {
                    output.write("0\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
                }
                output.flush()
                Log.d(TAG, "stream complete: all chunks written")
            }
        } catch (e: Exception) {
            exitedByException = true
            val msg = e.message.orEmpty()
            val isClientAbort =
                msg.contains("Broken pipe", ignoreCase = true) ||
                    msg.contains("Connection reset", ignoreCase = true) ||
                    msg.contains("socket closed", ignoreCase = true)
            if (isClientAbort) {
                Log.d(TAG, "handleSocket client abort: $msg")
            } else {
                Log.w(TAG, "handleSocket exception: ${e.javaClass.simpleName} msg='$msg'", e)
            }
            if (!headersSent && !isClientAbort) {
                runCatching { writeHttp(output, 500, "Internal Server Error", emptyMap(), ByteArray(0)) }
            }
        } finally {
            Log.d(TAG, "finally: calling respCancel exitedByException=$exitedByException headersSent=$headersSent")
            runCatching { respCancel?.invoke() }
            runCatching { socket.close() }
        }
    }

    private fun normalizeResponseHeaders(
        status: Int,
        raw: Map<String, String>,
    ): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        for ((k, v) in raw) {
            out[k] = v
        }
        if (out.entries.none { it.key.equals("Content-Type", ignoreCase = true) }) {
            out["Content-Type"] = "application/octet-stream"
        }
        val hasContentLength = out.entries.any { it.key.equals("Content-Length", ignoreCase = true) }
        if (!hasContentLength) {
            val cr = out.entries.firstOrNull { it.key.equals("Content-Range", ignoreCase = true) }?.value?.trim().orEmpty()
            if (status == 206 && cr.startsWith("bytes", ignoreCase = true)) {
                val bytesPart = cr.substringAfter("bytes", "").trim()
                val rangePart = bytesPart.substringBefore('/').trim()
                val dash = rangePart.indexOf('-')
                if (dash > 0) {
                    val start = rangePart.substring(0, dash).trim().toLongOrNull()
                    val end = rangePart.substring(dash + 1).trim().toLongOrNull()
                    if (start != null && end != null && end >= start) {
                        out["Content-Length"] = (end - start + 1).toString()
                    }
                }
            }
        }
        return out
    }

    private fun writeHttpHeaders(
        out: BufferedOutputStream,
        status: Int,
        reason: String,
        headers: Map<String, String>,
    ) {
        val statusLine = "HTTP/1.1 $status $reason\r\n"
        out.write(statusLine.toByteArray(Charsets.ISO_8859_1))
        for ((k, v) in headers) {
            val lk = k.trim().lowercase()
            if (lk == "connection") continue
            out.write("$k: $v\r\n".toByteArray(Charsets.ISO_8859_1))
        }
        out.write("Connection: close\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
        out.flush()
    }

    private fun writeHttp(
        out: BufferedOutputStream,
        status: Int,
        reason: String,
        headers: Map<String, String>,
        body: ByteArray,
    ) {
        val hdrs = LinkedHashMap(headers)
        hdrs["Content-Length"] = body.size.toString()
        writeHttpHeaders(out, status, reason, hdrs)
        if (body.isNotEmpty()) {
            out.write(body)
            out.flush()
        }
    }

    private fun reasonPhrase(status: Int): String {
        return when (status) {
            200 -> "OK"
            206 -> "Partial Content"
            301 -> "Moved Permanently"
            302 -> "Found"
            304 -> "Not Modified"
            400 -> "Bad Request"
            401 -> "Unauthorized"
            403 -> "Forbidden"
            404 -> "Not Found"
            416 -> "Range Not Satisfiable"
            500 -> "Internal Server Error"
            503 -> "Service Unavailable"
            else -> "OK"
        }
    }
}
