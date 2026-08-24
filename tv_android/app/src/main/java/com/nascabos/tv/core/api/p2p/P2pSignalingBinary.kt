package com.nascabos.tv.core.api.p2p

import org.json.JSONArray
import java.nio.charset.StandardCharsets

/**
 * P2P 信令紧凑二进制协议（与服务端 signalingBinary.js / quickshare 一致）
 */
object P2pSignalingBinary {
    private val MAGIC = byteArrayOf(0x4e, 0x50, 0x53, 0x01)

    private const val TYPE_PING: Int = 0x01
    private const val TYPE_PONG: Int = 0x02
    private const val TYPE_SESSION_READY: Int = 0x10
    private const val TYPE_SESSION_CLOSED: Int = 0x11
    private const val TYPE_WEBRTC_OFFER: Int = 0x20
    private const val TYPE_WEBRTC_ANSWER: Int = 0x21
    private const val TYPE_WEBRTC_CANDIDATE: Int = 0x22
    private const val TYPE_ERROR: Int = 0x23
    private const val TYPE_DEVICE_READY: Int = 0x30
    private const val TYPE_DEVICE_PAIR_CODE: Int = 0x31
    private const val TYPE_SESSION_CLIENT_CONNECTED: Int = 0x32
    private const val TYPE_WEBRTC_DEVICE_READY: Int = 0x33

    fun isSignalingBinary(data: ByteArray): Boolean {
        if (data.size < 5) return false
        return data[0] == MAGIC[0] && data[1] == MAGIC[1] && data[2] == MAGIC[2] && data[3] == MAGIC[3]
    }

    fun encodeSignaling(msg: Map<String, Any?>): ByteArray? {
        val type = msg["type"]?.toString() ?: return null
        val mt = when (type) {
            "ping" -> TYPE_PING
            "pong" -> TYPE_PONG
            "session:ready" -> TYPE_SESSION_READY
            "session:closed" -> TYPE_SESSION_CLOSED
            "webrtc:offer" -> TYPE_WEBRTC_OFFER
            "webrtc:answer" -> TYPE_WEBRTC_ANSWER
            "webrtc:candidate" -> TYPE_WEBRTC_CANDIDATE
            "error" -> TYPE_ERROR
            "device:ready" -> TYPE_DEVICE_READY
            "device:pairCode" -> TYPE_DEVICE_PAIR_CODE
            "session:client_connected" -> TYPE_SESSION_CLIENT_CONNECTED
            "webrtc:device_ready" -> TYPE_WEBRTC_DEVICE_READY
            else -> return null
        }
        val out = mutableListOf<Byte>()
        out.addAll(MAGIC.toList())
        out.add(mt.toByte())

        when (mt) {
            TYPE_PING, TYPE_PONG -> {
                val ts = (msg["ts"] as? Number)?.toLong()?.toInt() ?: 0
                out.addAll(encodeVarint(ts).toList())
            }
            TYPE_SESSION_READY -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                val ice = msg["iceServers"]
                val iceJson = if (ice is List<*>) JSONArray(ice).toString() else "[]"
                out.addAll(encodeString(iceJson).toList())
            }
            TYPE_SESSION_CLOSED -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                out.addAll(encodeString(msg["reason"]?.toString() ?: "").toList())
            }
            TYPE_WEBRTC_OFFER -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                @Suppress("UNCHECKED_CAST")
                val offer = msg["offer"] as? Map<String, Any?> ?: emptyMap()
                out.addAll(encodeString(offer["type"]?.toString() ?: "").toList())
                out.addAll(encodeString(offer["sdp"]?.toString() ?: "").toList())
            }
            TYPE_WEBRTC_ANSWER -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                @Suppress("UNCHECKED_CAST")
                val answer = msg["answer"] as? Map<String, Any?> ?: emptyMap()
                out.addAll(encodeString(answer["type"]?.toString() ?: "").toList())
                out.addAll(encodeString(answer["sdp"]?.toString() ?: "").toList())
            }
            TYPE_WEBRTC_CANDIDATE -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                @Suppress("UNCHECKED_CAST")
                val c = msg["candidate"] as? Map<String, Any?> ?: emptyMap()
                out.addAll(encodeString(c["candidate"]?.toString() ?: "").toList())
                out.addAll(encodeString(c["sdpMid"]?.toString() ?: "").toList())
                val idx = (c["sdpMLineIndex"] as? Number)?.toInt() ?: 0
                out.addAll(encodeVarint(idx).toList())
            }
            TYPE_ERROR -> out.addAll(encodeString(msg["code"]?.toString() ?: "").toList())
            TYPE_DEVICE_READY, TYPE_DEVICE_PAIR_CODE -> {
                out.addAll(encodeString(msg["deviceId"]?.toString() ?: "").toList())
                out.addAll(encodeString(msg["serverId"]?.toString() ?: "").toList())
                out.addAll(encodeString(msg["pairCode"]?.toString() ?: "").toList())
            }
            TYPE_SESSION_CLIENT_CONNECTED -> {
                out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
                val ice = msg["iceServers"]
                val iceJson = if (ice is List<*>) JSONArray(ice).toString() else "[]"
                out.addAll(encodeString(iceJson).toList())
            }
            TYPE_WEBRTC_DEVICE_READY -> out.addAll(encodeString(msg["sessionId"]?.toString() ?: "").toList())
            else -> return null
        }
        return out.toByteArray()
    }

    fun decodeSignaling(data: ByteArray): Map<String, Any?>? {
        if (data.size < 5 || !isSignalingBinary(data)) return null
        val mt = data[4].toInt() and 0xff
        var offset = 5

        fun readStr(): String? {
            val r = decodeString(data, offset) ?: return null
            offset = r.second
            return r.first
        }
        fun readVar(): Int? {
            val r = decodeVarint(data, offset) ?: return null
            offset = r.second
            return r.first
        }

        return when (mt) {
            TYPE_PING -> readVar()?.let { mapOf("type" to "ping", "ts" to it) }
            TYPE_PONG -> readVar()?.let { mapOf("type" to "pong", "ts" to it) }
            TYPE_SESSION_READY -> {
                val sessionId = readStr() ?: return null
                val iceJson = readStr() ?: return null
                val iceServers = parseJsonArray(iceJson)
                mapOf("type" to "session:ready", "sessionId" to sessionId, "iceServers" to iceServers)
            }
            TYPE_SESSION_CLOSED -> {
                val sessionId = readStr() ?: return null
                val reason = readStr()
                mutableMapOf<String, Any?>("type" to "session:closed", "sessionId" to sessionId).apply {
                    if (!reason.isNullOrEmpty()) put("reason", reason)
                }
            }
            TYPE_WEBRTC_OFFER -> {
                val sessionId = readStr() ?: return null
                val type = readStr() ?: return null
                val sdp = readStr() ?: return null
                mapOf("type" to "webrtc:offer", "sessionId" to sessionId, "offer" to mapOf("type" to type, "sdp" to sdp))
            }
            TYPE_WEBRTC_ANSWER -> {
                val sessionId = readStr()
                val type = readStr() ?: return null
                val sdp = readStr() ?: return null
                mutableMapOf<String, Any?>("type" to "webrtc:answer", "answer" to mapOf("type" to type, "sdp" to sdp)).apply {
                    if (!sessionId.isNullOrEmpty()) put("sessionId", sessionId)
                }
            }
            TYPE_WEBRTC_CANDIDATE -> {
                val sessionId = readStr() ?: return null
                val candidate = readStr() ?: return null
                val sdpMid = readStr() ?: ""
                val sdpMLineIndex = readVar() ?: 0
                mapOf(
                    "type" to "webrtc:candidate",
                    "sessionId" to sessionId,
                    "candidate" to mapOf("candidate" to candidate, "sdpMid" to sdpMid, "sdpMLineIndex" to sdpMLineIndex),
                )
            }
            TYPE_ERROR -> readStr()?.let { mapOf("type" to "error", "code" to it) }
            TYPE_DEVICE_READY -> {
                val deviceId = readStr() ?: return null
                val serverId = readStr() ?: return null
                val pairCode = readStr() ?: return null
                mapOf("type" to "device:ready", "deviceId" to deviceId, "serverId" to serverId, "pairCode" to pairCode)
            }
            TYPE_DEVICE_PAIR_CODE -> {
                val deviceId = readStr() ?: return null
                val serverId = readStr() ?: return null
                val pairCode = readStr() ?: return null
                mapOf("type" to "device:pairCode", "deviceId" to deviceId, "serverId" to serverId, "pairCode" to pairCode)
            }
            TYPE_SESSION_CLIENT_CONNECTED -> {
                val sessionId = readStr() ?: return null
                val iceJson = readStr() ?: return null
                val iceServers = parseJsonArray(iceJson)
                mapOf("type" to "session:client_connected", "sessionId" to sessionId, "iceServers" to iceServers)
            }
            TYPE_WEBRTC_DEVICE_READY -> readStr()?.let { mapOf("type" to "webrtc:device_ready", "sessionId" to it) }
            else -> null
        }
    }

    private fun encodeVarint(n: Int): ByteArray {
        var v = n and 0x7fffffff
        if (v < 0) v = 0
        val out = mutableListOf<Byte>()
        var x = v.toLong() and 0xffffffffL
        while (x >= 0x80) {
            out.add(((x and 0x7f) or 0x80).toInt().toByte())
            x = x shr 7
        }
        out.add(x.toInt().toByte())
        return out.toByteArray()
    }

    private fun decodeVarint(data: ByteArray, offset0: Int): Pair<Int, Int>? {
        var offset = offset0
        var shift = 0
        var result = 0L
        while (offset < data.size) {
            val b = data[offset].toInt() and 0xff
            offset++
            result = result or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) return Pair(result.coerceIn(0, Int.MAX_VALUE.toLong()).toInt(), offset)
            shift += 7
            if (shift > 35) return null
        }
        return null
    }

    private fun encodeString(s: String): ByteArray {
        val b = s.toByteArray(StandardCharsets.UTF_8)
        return encodeVarint(b.size) + b
    }

    private fun decodeString(data: ByteArray, offset0: Int): Pair<String, Int>? {
        val v = decodeVarint(data, offset0) ?: return null
        val len = v.first
        var offset = v.second
        if (offset + len > data.size) return null
        val str = if (len == 0) "" else String(data, offset, len, StandardCharsets.UTF_8)
        offset += len
        return Pair(str, offset)
    }

    private fun parseJsonArray(json: String): List<Map<String, Any?>> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val obj = arr.optJSONObject(i) ?: return@map emptyMap<String, Any?>()
                obj.keys().asSequence().associateWith { key -> jsonValueToAny(obj.get(key)) }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun jsonValueToAny(v: Any?): Any? {
        if (v == null || v == org.json.JSONObject.NULL) return null
        return when (v) {
            is JSONArray -> (0 until v.length()).map { jsonValueToAny(v.get(it)) }
            is org.json.JSONObject -> v.keys().asSequence().associateWith { key -> jsonValueToAny(v.get(key)) }
            else -> v
        }
    }
}
