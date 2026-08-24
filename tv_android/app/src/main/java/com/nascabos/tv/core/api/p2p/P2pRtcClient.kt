package com.nascabos.tv.core.api.p2p

import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.webrtc.DataChannel
import org.webrtc.IceCandidate
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RTCStatsReport
import org.webrtc.SessionDescription
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.util.Random
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.min

class P2pRtcClient(
    private val sessionId: String,
    private val iceServers: List<Map<String, Any?>>,
    private val iceTransportPolicy: String?,
    private val sendWsJson: (Map<String, Any?>) -> Unit,
    private val factory: PeerConnectionFactory,
    private val gson: Gson = Gson(),
    private val onRtcConnectionLost: (() -> Unit)? = null,
) {
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private var pc: PeerConnection? = null
    private val channels: MutableMap<P2pRtcChannel, ChannelState> = ConcurrentHashMap()
    private var heartbeatJob: Job? = null

    suspend fun start(wantedChannels: List<P2pRtcChannel>) {
        val sid = sessionId.trim()
        if (sid.isEmpty()) throw IllegalArgumentException("p2p_session_invalid")

        val rtcIceServers = iceServers.mapNotNull { raw ->
            val urlsAny = raw["urls"]
            val urls: List<String> =
                when (urlsAny) {
                    is String -> listOf(urlsAny)
                    is List<*> -> urlsAny.mapNotNull { it?.toString() }
                    else -> emptyList()
                }.map { it.trim() }.filter { it.isNotEmpty() }
            if (urls.isEmpty()) return@mapNotNull null
            val builder = PeerConnection.IceServer.builder(urls)
            val username = raw["username"]?.toString()?.trim().orEmpty()
            val credential = raw["credential"]?.toString()?.trim().orEmpty()
            if (username.isNotEmpty()) builder.setUsername(username)
            if (credential.isNotEmpty()) builder.setPassword(credential)
            builder.createIceServer()
        }

        val config = PeerConnection.RTCConfiguration(rtcIceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            if (!iceTransportPolicy.isNullOrBlank()) {
                this.iceTransportsType =
                    if (iceTransportPolicy.trim().lowercase() == "relay") {
                        PeerConnection.IceTransportsType.RELAY
                    } else {
                        PeerConnection.IceTransportsType.ALL
                    }
            }
        }

        val observer = object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                val c = candidate.sdp
                if (c.isNullOrBlank()) return
                sendWsJson(
                    mapOf(
                        "type" to "webrtc:candidate",
                        "sessionId" to sid,
                        "candidate" to mapOf(
                            "candidate" to c,
                            "sdpMid" to candidate.sdpMid,
                            "sdpMLineIndex" to candidate.sdpMLineIndex,
                        ),
                    ),
                )
            }

            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
                if (newState == PeerConnection.PeerConnectionState.FAILED ||
                    newState == PeerConnection.PeerConnectionState.CLOSED ||
                    newState == PeerConnection.PeerConnectionState.DISCONNECTED
                ) {
                    scope.launch {
                        runCatching { onRtcConnectionLost?.invoke() }
                        close()
                    }
                }
            }

            override fun onSignalingChange(newState: PeerConnection.SignalingState) {}
            override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(newState: PeerConnection.IceGatheringState) {}
            override fun onIceCandidatesRemoved(candidates: Array<IceCandidate>) {}
            override fun onAddStream(stream: org.webrtc.MediaStream) {}
            override fun onRemoveStream(stream: org.webrtc.MediaStream) {}
            override fun onDataChannel(dc: DataChannel) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: org.webrtc.RtpReceiver, mediaStreams: Array<org.webrtc.MediaStream>) {}
        }

        val peerConnection = factory.createPeerConnection(config, observer)
            ?: throw IllegalStateException("p2p_pc_create_failed")
        pc = peerConnection

        suspend fun attachChannel(c: P2pRtcChannel) {
            val prefix = prefixForChannel(c)
            val init = DataChannel.Init()
            val dc = peerConnection.createDataChannel(prefix, init)
                ?: throw IllegalStateException("p2p_dc_create_failed")
            val ready = CompletableDeferred<Unit>()
            val st = ChannelState(channel = c, prefix = prefix, dc = dc, ready = ready)
            channels[c] = st
            dc.registerObserver(object : DataChannel.Observer {
                override fun onBufferedAmountChange(previousAmount: Long) {}
                override fun onStateChange() {
                    if (dc.state() == DataChannel.State.CLOSED) {
                        if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException("p2p_dc_closed"))
                        st.failAll(IllegalStateException("p2p_dc_closed"))
                    }
                }

                override fun onMessage(buffer: DataChannel.Buffer) {
                    val nowMs = System.currentTimeMillis()
                    st.rxPackets++
                    st.lastRxAtMs = nowMs
                    if (buffer.binary) {
                        val data = ByteArray(buffer.data.remaining())
                        buffer.data.get(data)
                        st.rxBytes += data.size.toLong()
                        st.rxBinaryPackets++
                        st.rxBinaryBytes += data.size.toLong()
                        if (P2pControlBinary.isControl(data)) {
                            P2pControlBinary.decodeControl(data, st.prefix)?.let { onChannelMessage(st, it) }
                            return
                        }
                        if (data.isNotEmpty() && data[0] == 0x01.toByte()) {
                            handleBinaryChunk(st, data)
                            return
                        }
                        val text = runCatching { String(data, Charsets.UTF_8) }.getOrNull().orEmpty()
                        if (text.isEmpty()) return
                        parseJsonMap(text)?.let { onChannelMessage(st, it) }
                        return
                    } else {
                        val data = ByteArray(buffer.data.remaining())
                        buffer.data.get(data)
                        val text = runCatching { String(data, Charsets.UTF_8) }.getOrNull().orEmpty()
                        if (text.isEmpty()) return
                        st.rxBytes += text.length.toLong()
                        st.rxTextPackets++
                        st.rxTextBytes += text.length.toLong()
                        parseJsonMap(text)?.let { onChannelMessage(st, it) }
                    }
                }
            })
        }

        for (c in wantedChannels) {
            attachChannel(c)
        }

        val offer = withContext(Dispatchers.Default) {
            val deferred = CompletableDeferred<SessionDescription>()
            peerConnection.createOffer(object : org.webrtc.SdpObserver {
                override fun onCreateSuccess(desc: SessionDescription) {
                    deferred.complete(desc)
                }

                override fun onCreateFailure(error: String) {
                    deferred.completeExceptionally(IllegalStateException(error))
                }

                override fun onSetSuccess() {}
                override fun onSetFailure(error: String) {}
            }, org.webrtc.MediaConstraints())
            deferred.await()
        }

        withContext(Dispatchers.Default) {
            val deferred = CompletableDeferred<Unit>()
            peerConnection.setLocalDescription(object : org.webrtc.SdpObserver {
                override fun onSetSuccess() {
                    deferred.complete(Unit)
                }

                override fun onSetFailure(error: String) {
                    deferred.completeExceptionally(IllegalStateException(error))
                }

                override fun onCreateSuccess(desc: SessionDescription) {}
                override fun onCreateFailure(error: String) {}
            }, offer)
            deferred.await()
        }

        sendWsJson(
            mapOf(
                "type" to "webrtc:offer",
                "sessionId" to sid,
                "offer" to mapOf("type" to offer.type.canonicalForm(), "sdp" to offer.description),
            ),
        )

        channels.values.map { it.ready }.forEach { it.await() }

        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(15_000)
                val now = System.currentTimeMillis()
                val current = channels.values.toList()
                for (st in current) {
                    val dc = st.dc
                    if (dc.state() != DataChannel.State.OPEN) continue
                    runCatching {
                        sendControl(st, P2pControlBinary.ControlType.PING, mapOf("ts" to now))
                    }
                }
            }
        }
    }

    fun handleWsMessage(msg: Map<String, Any?>) {
        val peerConnection = pc ?: return
        val type = msg["type"]?.toString().orEmpty()
        val sid = msg["sessionId"]?.toString().orEmpty()
        if (sid.isNotEmpty() && sid != sessionId) return

        if (type == "webrtc:answer") {
            val a = msg["answer"]
            if (a is Map<*, *>) {
                val t = a["type"]?.toString().orEmpty()
                val sdp = a["sdp"]?.toString().orEmpty()
                if (t.isNotEmpty() && sdp.isNotEmpty()) {
                    val desc = SessionDescription(SessionDescription.Type.fromCanonicalForm(t), sdp)
                    peerConnection.setRemoteDescription(object : org.webrtc.SdpObserver {
                        override fun onSetSuccess() {}
                        override fun onSetFailure(error: String) {}
                        override fun onCreateSuccess(desc: SessionDescription) {}
                        override fun onCreateFailure(error: String) {}
                    }, desc)
                }
            }
            return
        }

        if (type == "webrtc:candidate") {
            val c = msg["candidate"]
            if (c is Map<*, *>) {
                val candidate = c["candidate"]?.toString().orEmpty()
                if (candidate.isEmpty()) return
                val sdpMid = c["sdpMid"]?.toString()
                val lineIndex = c["sdpMLineIndex"]?.toString()?.toIntOrNull() ?: -1
                peerConnection.addIceCandidate(IceCandidate(sdpMid, lineIndex, candidate))
            }
        }
    }

    suspend fun getTransportStats(): Map<String, String> {
        val peerConnection = pc ?: return emptyMap()
        return withContext(Dispatchers.Default) {
            runCatching {
                val report = getStatsReport(peerConnection)
                val out = mutableMapOf<String, String>()
                val nowMs = System.currentTimeMillis()
                val statsMap = report.statsMap
                val candidatePair = statsMap.values.firstOrNull { it.type == "candidate-pair" && it.members["state"] == "succeeded" }
                if (candidatePair != null) {
                    val localId = candidatePair.members["localCandidateId"]?.toString().orEmpty()
                    val local = statsMap[localId]
                    if (local != null) {
                        out["protocol"] = local.members["protocol"]?.toString().orEmpty()
                        out["type"] = local.members["candidateType"]?.toString().orEmpty()
                    }
                    val rtt = candidatePair.members["currentRoundTripTime"]?.toString()?.toDoubleOrNull()
                    if (rtt != null) out["rttMs"] = (rtt * 1000).toInt().toString()
                    candidatePair.members["bytesSent"]?.toString()?.let { out["bytesSent"] = it }
                    candidatePair.members["bytesReceived"]?.toString()?.let { out["bytesReceived"] = it }
                    candidatePair.members["packetsSent"]?.toString()?.let { out["packetsSent"] = it }
                    candidatePair.members["packetsReceived"]?.toString()?.let { out["packetsReceived"] = it }
                    candidatePair.members["availableOutgoingBitrate"]?.toString()?.let { out["availableOutgoingBitrate"] = it }
                    candidatePair.members["availableIncomingBitrate"]?.toString()?.let { out["availableIncomingBitrate"] = it }

                    fun fill(prefix: String, st: ChannelState?) {
                        if (st == null) return
                        out["${prefix}DcBuffered"] = st.dc.bufferedAmount().toString()
                        out["${prefix}TxPackets"] = st.txPackets.toString()
                        out["${prefix}TxBytes"] = st.txBytes.toString()
                        out["${prefix}RxPackets"] = st.rxPackets.toString()
                        out["${prefix}RxBytes"] = st.rxBytes.toString()
                        out["${prefix}RxBinaryPackets"] = st.rxBinaryPackets.toString()
                        out["${prefix}RxTextPackets"] = st.rxTextPackets.toString()
                        out["${prefix}TxBinaryPackets"] = st.txBinaryPackets.toString()
                        out["${prefix}TxTextPackets"] = st.txTextPackets.toString()
                        if (st.lastRxAtMs > 0) out["${prefix}RxIdleMs"] = (nowMs - st.lastRxAtMs).toString()
                        if (st.lastTxAtMs > 0) out["${prefix}TxIdleMs"] = (nowMs - st.lastTxAtMs).toString()
                    }

                    fill("api", channels[P2pRtcChannel.Api])
                    fill("file", channels[P2pRtcChannel.File])
                    fill("upload", channels[P2pRtcChannel.Upload])
                    fill("download", channels[P2pRtcChannel.Download])
                    fill("video", channels[P2pRtcChannel.Video])
                }
                out
            }.getOrDefault(emptyMap())
        }
    }

    fun openWebSocketChannel(
        channel: P2pRtcChannel,
        path: String,
        headers: Map<String, String> = emptyMap(),
    ): P2pWsTunnel {
        val st = requireChannel(channel)
        val id = "${System.nanoTime()}_${Random().nextInt(1 shl 30)}"
        val outgoingHeaders = headers.mapKeys { it.key.trim() }.filterKeys { it.isNotEmpty() }
        val ws = P2pWsTunnel(
            id = id,
            prefix = st.prefix,
            sendJson = { payload ->
                if (st.dc.state() != DataChannel.State.OPEN) throw IllegalStateException("p2p_dc_not_open")
                sendText(st, gson.toJson(payload))
            },
            onClose = { st.wsTunnels.remove(id) },
        )
        st.wsTunnels[id] = ws

        scope.launch {
            try {
                st.ready.await()
                if (st.dc.state() != DataChannel.State.OPEN) throw IllegalStateException("p2p_dc_not_open")
                val safePath = path.trim()
                if (safePath.isEmpty() || !safePath.startsWith("/")) {
                    st.wsTunnels.remove(id)
                    ws.handleOpenError("invalid_path")
                    return@launch
                }
                ws.sendOpen(safePath, outgoingHeaders)
            } catch (e: Exception) {
                st.wsTunnels.remove(id)
                ws.handleOpenError(e.toString())
            }
        }

        return ws
    }

    suspend fun sendRequest(
        channel: P2pRtcChannel,
        method: String,
        path: String,
        headers: Map<String, String>,
        bodyBytes: ByteArray,
        timeoutMs: Long = 5 * 60_000L,
        cancelSignal: CompletableDeferred<Unit>? = null,
    ): P2pApiResponse {
        val st = requireChannel(channel)
        st.ready.await()
        if (st.dc.state() != DataChannel.State.OPEN) throw IllegalStateException("p2p_dc_not_open")

        fun drainLimitBytes(): Long {
            return when (channel) {
                P2pRtcChannel.Api -> 512L * 1024
                P2pRtcChannel.Video -> 4L * 1024 * 1024
                else -> 2L * 1024 * 1024
            }
        }

        suspend fun waitDrain() {
            val limit = drainLimitBytes()
            val startedAt = System.currentTimeMillis()
            while (st.dc.bufferedAmount() > limit) {
                if (cancelSignal?.isCompleted == true) throw IllegalStateException("p2p_canceled")
                if (System.currentTimeMillis() - startedAt > 30_000L) return
                delay(5)
            }
        }

        val id = "${System.nanoTime()}_${Random().nextInt(1 shl 30)}"
        val completer = CompletableDeferred<P2pApiResponse>()
        st.pending[id] = completer

        fun abortLocal(error: Throwable) {
            st.pending.remove(id)
            st.pendingChunks.remove(id)
            if (!completer.isCompleted) completer.completeExceptionally(error)
        }

        cancelSignal?.invokeOnCompletion {
            abortLocal(IllegalStateException("p2p_canceled"))
        }

        val safeHeaders = headers.mapKeys { it.key.trim() }
            .filterKeys { it.isNotEmpty() }
            .filterKeys { k -> k.lowercase() != "host" && k.lowercase() != "content-length" }

        try {
            val rawBody = bodyBytes

            if (rawBody.isNotEmpty()) {
                if (cancelSignal?.isCompleted == true) throw IllegalStateException("p2p_canceled")
                waitDrain()

                val beginPayload = mutableMapOf<String, Any?>(
                    "id" to id,
                    "method" to method,
                    "path" to path,
                    "headers" to safeHeaders,
                    "length" to rawBody.size,
                )
                sendControl(st, P2pControlBinary.ControlType.REQ_BEGIN, beginPayload)

                val idBuf = id.toByteArray(Charset.forName("ISO-8859-1"))
                if (idBuf.size > 255) throw IllegalStateException("p2p_req_id_too_long")
                val idLen = idBuf.size

                val chunkSize = 64 * 1024
                val header = ByteArray(2 + idLen)
                header[0] = 0x01
                header[1] = idLen.toByte()
                System.arraycopy(idBuf, 0, header, 2, idLen)

                var offset = 0
                while (offset < rawBody.size) {
                    if (cancelSignal?.isCompleted == true) throw IllegalStateException("p2p_canceled")
                    val end = min(offset + chunkSize, rawBody.size)
                    val piece = rawBody.copyOfRange(offset, end)
                    waitDrain()
                    val packet = ByteArray(header.size + piece.size)
                    System.arraycopy(header, 0, packet, 0, header.size)
                    System.arraycopy(piece, 0, packet, header.size, piece.size)
                    sendBinary(st, packet)
                    offset = end
                }

                if (cancelSignal?.isCompleted == true) throw IllegalStateException("p2p_canceled")
                waitDrain()
                sendControl(st, P2pControlBinary.ControlType.REQ_END, mapOf("id" to id))
            } else {
                if (cancelSignal?.isCompleted == true) throw IllegalStateException("p2p_canceled")
                waitDrain()
                val reqPayload = mutableMapOf<String, Any?>(
                    "id" to id,
                    "method" to method,
                    "path" to path,
                    "headers" to safeHeaders,
                )
                sendControl(st, P2pControlBinary.ControlType.REQ, reqPayload)
            }
        } catch (e: Exception) {
            abortLocal(e)
            throw e
        }

        return withContext(Dispatchers.Default) {
            try {
                kotlinx.coroutines.withTimeout(timeoutMs) { completer.await() }
            } finally {
                st.pending.remove(id)
            }
        }
    }

    suspend fun sendRequestStream(
        channel: P2pRtcChannel,
        method: String,
        path: String,
        headers: Map<String, String>,
        bodyBytes: ByteArray,
        timeoutMs: Long = 5 * 60_000L,
    ): P2pApiStreamResponse {
        val st = requireChannel(channel)
        st.ready.await()
        if (st.dc.state() != DataChannel.State.OPEN) throw IllegalStateException("p2p_dc_not_open")

        suspend fun waitDrain() {
            val limit = 16L * 1024 * 1024
            val startedAt = System.currentTimeMillis()
            while (st.dc.bufferedAmount() > limit) {
                if (System.currentTimeMillis() - startedAt > 30_000L) return
                delay(5)
            }
        }

        val id = "${System.nanoTime()}_${Random().nextInt(1 shl 30)}"
        val streamChannel = Channel<ByteArray>(capacity = 256)
        val start = CompletableDeferred<StreamStart>()
        val pendingStream = PendingStream(channel = streamChannel, start = start)
        st.pendingStreams[id] = pendingStream

        val safeHeaders = headers.mapKeys { it.key.trim() }
            .filterKeys { it.isNotEmpty() }
            .filterKeys { k -> k.lowercase() != "host" && k.lowercase() != "content-length" }

        fun cancelInternal() {
            val pst = st.pendingStreams.remove(id) ?: return
            Log.d("P2pRtc", "cancelInternal: channel=${st.prefix} id=$id")
            runCatching {
                if (st.dc.state() == DataChannel.State.OPEN) {
                    sendControl(st, P2pControlBinary.ControlType.CANCEL, mapOf("id" to id))
                }
            }
            if (!pst.start.isCompleted) pst.start.completeExceptionally(IllegalStateException("p2p_canceled"))
            pst.channel.close(IllegalStateException("p2p_canceled"))
        }

        try {
            val rawBody = bodyBytes

            if (rawBody.isNotEmpty()) {
                waitDrain()
                val beginPayload = mutableMapOf<String, Any?>(
                    "id" to id,
                    "method" to method,
                    "path" to path,
                    "headers" to safeHeaders,
                    "length" to rawBody.size,
                )
                sendControl(st, P2pControlBinary.ControlType.REQ_BEGIN, beginPayload)

                val idBuf = id.toByteArray(Charset.forName("ISO-8859-1"))
                if (idBuf.size > 255) throw IllegalStateException("p2p_req_id_too_long")
                val idLen = idBuf.size
                val chunkSize = 64 * 1024

                val header = ByteArray(2 + idLen)
                header[0] = 0x01
                header[1] = idLen.toByte()
                System.arraycopy(idBuf, 0, header, 2, idLen)

                var offset = 0
                while (offset < rawBody.size) {
                    val end = min(offset + chunkSize, rawBody.size)
                    val piece = rawBody.copyOfRange(offset, end)
                    waitDrain()
                    val packet = ByteArray(header.size + piece.size)
                    System.arraycopy(header, 0, packet, 0, header.size)
                    System.arraycopy(piece, 0, packet, header.size, piece.size)
                    sendBinary(st, packet)
                    offset = end
                }
                waitDrain()
                sendControl(st, P2pControlBinary.ControlType.REQ_END, mapOf("id" to id))
            } else {
                waitDrain()
                val reqPayload = mutableMapOf<String, Any?>(
                    "id" to id,
                    "method" to method,
                    "path" to path,
                    "headers" to safeHeaders,
                )
                sendControl(st, P2pControlBinary.ControlType.REQ, reqPayload)
            }
        } catch (e: Exception) {
            st.pendingStreams.remove(id)
            streamChannel.close(e)
            throw e
        }

        val startTimeoutMs = min(timeoutMs, 15_000L)
        val started = try {
            kotlinx.coroutines.withTimeout(startTimeoutMs) { start.await() }
        } catch (e: Exception) {
            cancelInternal()
            throw IllegalStateException("p2p_dc_error_start_timeout")
        }

        return P2pApiStreamResponse(
            status = started.status,
            headers = started.headers,
            stream = streamChannel.receiveAsFlow(),
            cancel = ::cancelInternal,
        )
    }

    suspend fun close() {
        heartbeatJob?.cancel()
        heartbeatJob = null

        val peerConnection = pc
        pc = null

        val snapshot = channels.toMap()
        channels.clear()
        for (st in snapshot.values) {
            runCatching { st.dc.close() }
            if (!st.ready.isCompleted) st.ready.completeExceptionally(IllegalStateException("p2p_closed"))
            st.failAll(IllegalStateException("p2p_closed"))
        }

        if (peerConnection != null) {
            runCatching { peerConnection.close() }
            runCatching { peerConnection.dispose() }
        }
        scope.coroutineContext[Job]?.cancel()
    }

    private fun requireChannel(channel: P2pRtcChannel): ChannelState {
        return channels[channel] ?: throw IllegalStateException("p2p_not_connected")
    }

    private fun prefixForChannel(c: P2pRtcChannel): String =
        when (c) {
            P2pRtcChannel.Api -> "api"
            P2pRtcChannel.File -> "file"
            P2pRtcChannel.Upload -> "upload"
            P2pRtcChannel.Download -> "download"
            P2pRtcChannel.Video -> "video"
        }

    private fun sendText(st: ChannelState, text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        st.txPackets++
        st.txBytes += text.length.toLong()
        st.txTextPackets++
        st.txTextBytes += text.length.toLong()
        st.lastTxAtMs = System.currentTimeMillis()
        st.dc.send(DataChannel.Buffer(ByteBuffer.wrap(bytes), false))
    }

    private fun sendFlow(st: ChannelState, id: String, action: String) {
        if (st.dc.state() != DataChannel.State.OPEN) return
        Log.d("P2pRtc", "sendFlow: channel=${st.prefix} id=$id action=$action")
        runCatching {
            sendControl(st, P2pControlBinary.ControlType.FLOW, mapOf("id" to id, "action" to action))
        }
    }

    private fun sendControl(st: ChannelState, type: P2pControlBinary.ControlType, payload: Map<String, Any?>) {
        val bytes = P2pControlBinary.encodeControl(st.prefix, type, payload) ?: return
        sendBinary(st, bytes)
    }

    private fun sendBinary(st: ChannelState, bytes: ByteArray) {
        st.txPackets++
        st.txBytes += bytes.size.toLong()
        st.txBinaryPackets++
        st.txBinaryBytes += bytes.size.toLong()
        st.lastTxAtMs = System.currentTimeMillis()
        st.dc.send(DataChannel.Buffer(ByteBuffer.wrap(bytes), true))
    }

    private fun parseJsonMap(text: String): Map<String, Any?>? {
        return runCatching {
            val type = object : TypeToken<Map<String, Any?>>() {}.type
            gson.fromJson<Map<String, Any?>>(text, type)
        }.getOrNull()
    }

    /** Gson 将 JSON 数字解析为 Double，toString() 得到 "200.0"，toIntOrNull() 为 null。需先处理 Number。 */
    private fun parseIntFromJson(value: Any?, default: Int): Int {
        return when (value) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: default
        }
    }

    private fun handleBinaryChunk(st: ChannelState, bytes: ByteArray) {
        if (bytes.size < 2) return
        val ver = bytes[0].toInt() and 0xff
        if (ver != 0x01) return
        var offset = 1
        val idLen = bytes[offset].toInt() and 0xff
        offset++
        if (offset + idLen > bytes.size) return

        val idBytes = bytes.copyOfRange(offset, offset + idLen)
        val id = String(idBytes, Charset.forName("ISO-8859-1"))
        if (id.isEmpty()) return
        offset += idLen

        val payload = bytes.copyOfRange(offset, bytes.size)

        val pendingStream = st.pendingStreams[id]
        if (pendingStream != null) {
            val encodedLen = payload.size
            if (encodedLen > 0) {
                val out = payload
                val offered = runCatching { pendingStream.channel.trySend(out) }.getOrNull()
                if (offered != null && offered.isSuccess) {
                    if (pendingStream.flowPaused) {
                        pendingStream.flowPaused = false
                        sendFlow(st, id, "resume")
                    }
                    scheduleStreamAck(st, id, encodedLen, pendingStream)
                    return
                }
                if (pendingStream.channel.isClosedForSend) {
                    cancelPendingStream(st, id, "p2p_stream_controller_error")
                    return
                }
                if (!pendingStream.flowPaused) {
                    pendingStream.flowPaused = true
                    sendFlow(st, id, "pause")
                }
                runCatching {
                    runBlocking {
                        pendingStream.channel.send(out)
                    }
                }.onFailure {
                    cancelPendingStream(st, id, "p2p_stream_controller_error")
                    return
                }
                pendingStream.flowPaused = false
                sendFlow(st, id, "resume")
                scheduleStreamAck(st, id, encodedLen, pendingStream)
            }
            return
        }

        val pendingChunk = st.pendingChunks[id]
        if (pendingChunk != null) {
            pendingChunk.builder.write(payload)
        }
    }

    private fun onChannelMessage(st: ChannelState, m: Map<String, Any?>) {
        val prefix = st.prefix
        val type = m["type"]?.toString().orEmpty()

        if (type == "$prefix:ready") {
            if (!st.ready.isCompleted) st.ready.complete(Unit)
            return
        }

        if (type == "$prefix:ping") {
            if (st.dc.state() != DataChannel.State.OPEN) return
            runCatching {
                sendControl(st, P2pControlBinary.ControlType.PONG, mapOf("ts" to System.currentTimeMillis()))
            }
            return
        }

        if (type == "$prefix:pong") return

        if (type == "$prefix:ws:open:ok") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return
            st.wsTunnels[id]?.handleOpenOk()
            return
        }

        if (type == "$prefix:ws:open:error") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return
            val err = m["error"]?.toString().orEmpty().ifEmpty { "open_failed" }
            st.wsTunnels.remove(id)?.handleOpenError(err)
            return
        }

        if (type == "$prefix:ws:message") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return
            val data = m["data"]?.toString().orEmpty()
            st.wsTunnels[id]?.handleMessage(data)
            return
        }

        if (type == "$prefix:ws:error") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return
            val err = m["error"]?.toString().orEmpty().ifEmpty { "ws_error" }
            st.wsTunnels.remove(id)?.handleRemoteError(err)
            return
        }

        if (type == "$prefix:ws:close") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return
            val parsed = m["code"]?.let { parseIntFromJson(it, -1) }
            val code = if (parsed != null && parsed >= 0) parsed else null
            val reason = m["reason"]?.toString()
            st.wsTunnels.remove(id)?.handleRemoteClose(code, reason)
            return
        }

        if (type == "$prefix:res:begin") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return

            val pendingStream = st.pendingStreams[id]
            if (pendingStream != null) {
                val status = parseIntFromJson(m["status"], 500)
                val headers = parseHeadersLowercase(m["headers"])
                if (!pendingStream.start.isCompleted) pendingStream.start.complete(StreamStart(status, headers))
                return
            }

            val c = st.pending[id] ?: return
            if (c.isCompleted) return
            val status = parseIntFromJson(m["status"], 500)
            val headers = parseHeadersLowercase(m["headers"])
            val length = parseIntFromJson(m["length"], 0)
            st.pendingChunks[id] = PendingChunk(
                completer = c,
                status = status,
                headers = headers,
                builder = ByteArrayOutputStream(maxOf(length, 0)),
            )
            return
        }

        if (type == "$prefix:res:end") {
            val id = m["id"]?.toString().orEmpty()
            if (id.isEmpty()) return

            val pendingStream = st.pendingStreams.remove(id)
            if (pendingStream != null) {
                flushStreamAck(st, id, pendingStream)
                if (!pendingStream.start.isCompleted) {
                    pendingStream.start.complete(StreamStart(200, emptyMap()))
                }
                pendingStream.channel.close()
                return
            }

            val pendingChunk = st.pendingChunks.remove(id) ?: return
            st.pending.remove(id)
            if (pendingChunk.completer.isCompleted) return
            val encoded = pendingChunk.builder.toByteArray()
            scope.launch {
                pendingChunk.completer.complete(P2pApiResponse(pendingChunk.status, pendingChunk.headers, encoded))
            }
            return
        }
    }

    private fun parseHeadersLowercase(raw: Any?): Map<String, String> {
        if (raw !is Map<*, *>) return emptyMap()
        val out = mutableMapOf<String, String>()
        raw.forEach { (k, v) ->
            val key = k?.toString()?.trim().orEmpty()
            if (key.isEmpty()) return@forEach
            out[key.lowercase()] = v?.toString().orEmpty()
        }
        return out
    }

    private fun sendStreamAckDelta(st: ChannelState, id: String, delta: Int) {
        if (delta <= 0) return
        if (st.dc.state() != DataChannel.State.OPEN) return
        runCatching { sendControl(st, P2pControlBinary.ControlType.ACK, mapOf("id" to id, "delta" to delta)) }
    }

    private fun flushStreamAck(st: ChannelState, id: String, sst: PendingStream) {
        val delta = sst.ackPendingBytes
        if (delta <= 0) return
        sst.ackPendingBytes = 0
        sendStreamAckDelta(st, id, delta)
    }

    private fun cancelPendingStream(st: ChannelState, id: String, error: String) {
        val pst = st.pendingStreams.remove(id) ?: return
        Log.w("P2pRtc", "cancelPendingStream: channel=${st.prefix} id=$id error=$error")
        runCatching {
            if (st.dc.state() == DataChannel.State.OPEN) {
                sendControl(st, P2pControlBinary.ControlType.CANCEL, mapOf("id" to id))
            }
        }
        if (!pst.start.isCompleted) pst.start.completeExceptionally(IllegalStateException(error))
        pst.channel.close(IllegalStateException(error))
    }

    private fun scheduleStreamAck(st: ChannelState, id: String, delta: Int, sst: PendingStream) {
        if (delta <= 0) return
        sst.ackPendingBytes += delta
        if (sst.ackScheduled) return
        sst.ackScheduled = true
        val immediateThreshold =
            if (st.channel == P2pRtcChannel.Api) 256 * 1024
            else if (st.channel == P2pRtcChannel.Download) 128 * 1024
            else 1024 * 1024
        val delayMs =
            if (st.channel == P2pRtcChannel.Api) 50L
            else if (st.channel == P2pRtcChannel.Download) 50L
            else 200L
        val immediate = sst.ackPendingBytes >= immediateThreshold
        scope.launch {
            if (!immediate) delay(delayMs)
            val cur = st.pendingStreams[id] ?: return@launch
            try {
                flushStreamAck(st, id, cur)
            } finally {
                // IMPORTANT:
                // 仅在 flush 结束后解锁，避免并发窗口导致 ack 定时任务重复叠加。
                cur.ackScheduled = false
                if (cur.ackPendingBytes > 0 && st.pendingStreams.containsKey(id)) {
                    // flush 期间新增了字节，补排一次即可。
                    scheduleStreamAck(st, id, 0, cur)
                }
            }
        }
    }

    private suspend fun getStatsReport(pc: PeerConnection): RTCStatsReport {
        val deferred = CompletableDeferred<RTCStatsReport>()
        pc.getStats { report ->
            deferred.complete(report)
        }
        return deferred.await()
    }

    private data class StreamStart(val status: Int, val headers: Map<String, String>)

    private data class PendingChunk(
        val completer: CompletableDeferred<P2pApiResponse>,
        val status: Int,
        val headers: Map<String, String>,
        val builder: ByteArrayOutputStream,
    )

    private class PendingStream(
        val channel: Channel<ByteArray>,
        val start: CompletableDeferred<StreamStart>,
    ) {
        var ackPendingBytes: Int = 0
        var ackScheduled: Boolean = false
        @Volatile var flowPaused: Boolean = false
    }

    private class ChannelState(
        val channel: P2pRtcChannel,
        val prefix: String,
        val dc: DataChannel,
        val ready: CompletableDeferred<Unit>,
    ) {
        val pending: MutableMap<String, CompletableDeferred<P2pApiResponse>> = ConcurrentHashMap()
        val pendingChunks: MutableMap<String, PendingChunk> = ConcurrentHashMap()
        val pendingStreams: MutableMap<String, PendingStream> = ConcurrentHashMap()
        val wsTunnels: MutableMap<String, P2pWsTunnel> = ConcurrentHashMap()

        var txPackets: Long = 0
        var txBytes: Long = 0
        var rxPackets: Long = 0
        var rxBytes: Long = 0
        var txBinaryPackets: Long = 0
        var txBinaryBytes: Long = 0
        var txTextPackets: Long = 0
        var txTextBytes: Long = 0
        var rxBinaryPackets: Long = 0
        var rxBinaryBytes: Long = 0
        var rxTextPackets: Long = 0
        var rxTextBytes: Long = 0
        var lastTxAtMs: Long = 0
        var lastRxAtMs: Long = 0

        fun failAll(error: Throwable) {
            pending.values.forEach { if (!it.isCompleted) it.completeExceptionally(error) }
            pending.clear()
            pendingChunks.clear()
            pendingStreams.values.forEach { pst ->
                if (!pst.start.isCompleted) pst.start.completeExceptionally(error)
                pst.channel.close(error)
            }
            pendingStreams.clear()
            wsTunnels.values.forEach { it.handleRemoteClose(1001, "p2p_closed") }
            wsTunnels.clear()
        }
    }
}
