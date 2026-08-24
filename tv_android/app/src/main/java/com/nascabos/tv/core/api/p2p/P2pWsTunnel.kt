package com.nascabos.tv.core.api.p2p

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow

class P2pWsTunnel(
    val id: String,
    private val prefix: String,
    private val sendJson: (Map<String, Any?>) -> Unit,
    private val onClose: () -> Unit,
) {
    private val ready = CompletableDeferred<Unit>()
    private val incoming = Channel<String>(capacity = Channel.BUFFERED)
    private val pendingOutgoing = ArrayList<String>()
    private var closed = false

    val stream: Flow<String> = incoming.receiveAsFlow()

    suspend fun awaitReady() {
        ready.await()
    }

    fun send(text: String) {
        if (closed) return
        if (!ready.isCompleted) {
            pendingOutgoing += text
            return
        }
        runCatching {
            sendJson(mapOf("type" to "$prefix:ws:send", "id" to id, "data" to text))
        }
    }

    fun close(code: Int? = null, reason: String? = null) {
        if (closed) return
        closed = true
        runCatching { sendJson(mapOf("type" to "$prefix:ws:close", "id" to id, "code" to code, "reason" to reason)) }
        onClose()
        incoming.close()
    }

    internal fun sendOpen(path: String, headers: Map<String, String>) {
        if (closed) return
        sendJson(mapOf("type" to "$prefix:ws:open", "id" to id, "path" to path, "headers" to headers))
    }

    internal fun handleOpenOk() {
        if (closed) return
        if (!ready.isCompleted) ready.complete(Unit)
        flushPending()
    }

    internal fun handleOpenError(error: String) {
        if (closed) return
        if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException(error))
        close(1011, error)
    }

    internal fun handleMessage(data: String) {
        if (closed) return
        incoming.trySend(data)
    }

    internal fun handleRemoteError(error: String) {
        if (closed) return
        if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException(error))
        close(1011, error)
    }

    internal fun handleRemoteClose(code: Int?, reason: String?) {
        if (closed) return
        closed = true
        onClose()
        incoming.close()
    }

    private fun flushPending() {
        if (closed) return
        if (!ready.isCompleted) return
        if (pendingOutgoing.isEmpty()) return
        val list = pendingOutgoing.toList()
        pendingOutgoing.clear()
        for (m in list) send(m)
    }
}
