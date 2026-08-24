package com.nascabos.tv.core.api.p2p

import java.nio.charset.StandardCharsets

/**
 * 与服务端 p2pConnectWorker/dataChannelProxy 一致的紧凑二进制控制消息协议。
 * 信令从 JSON 改为二进制后，Data Channel 上的控制消息使用此格式。
 */
object P2pControlBinary {
    private val MAGIC = byteArrayOf(0x4e, 0x50, 0x43, 0x01)

    enum class ControlType(val code: Int) {
        READY(0x01),
        PING(0x02),
        PONG(0x03),
        REQ(0x10),
        REQ_BEGIN(0x11),
        REQ_END(0x12),
        REQ_CANCEL(0x13),
        CANCEL(0x14),
        RES_BEGIN(0x20),
        RES_END(0x21),
        FLOW(0x22),
        ACK(0x30),
        WS_OPEN(0x40),
        WS_SEND(0x41),
        WS_CLOSE(0x42),
        WS_OPEN_OK(0x43),
        WS_OPEN_ERROR(0x44),
        WS_MESSAGE(0x45),
        WS_ERROR(0x46),
    }

    fun isControl(data: ByteArray): Boolean {
        if (data.size < 5) return false
        return data[0] == MAGIC[0] && data[1] == MAGIC[1] && data[2] == MAGIC[2] && data[3] == MAGIC[3]
    }

    // Varint (unsigned LEB128)
    fun encodeVarint(n: Int): ByteArray {
        var v = n.toLong() and 0x7fffffffL
        if (v < 0) v = 0
        val out = mutableListOf<Byte>()
        while (v >= 0x80) {
            out.add(((v and 0x7f) or 0x80).toByte())
            v = v shr 7
        }
        out.add(v.toByte())
        return out.toByteArray()
    }

    /** @return Pair(value, nextOffset) or null */
    fun decodeVarint(data: ByteArray, offset: Int): Pair<Int, Int>? {
        var pos = offset
        var shift = 0
        var result = 0L
        while (pos < data.size) {
            val b = data[pos].toInt() and 0xff
            pos++
            result = result or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) {
                val value = if (result <= Int.MAX_VALUE) result.toInt() else Int.MAX_VALUE
                return Pair(value, pos)
            }
            shift += 7
            if (shift > 63) return null
        }
        return null
    }

    fun encodeString(s: String): ByteArray {
        val utf8 = s.toByteArray(StandardCharsets.UTF_8)
        if (utf8.isEmpty()) return byteArrayOf(0)
        return encodeVarint(utf8.size) + utf8
    }

    /** @return Pair(value, nextOffset) or null */
    fun decodeString(data: ByteArray, offset: Int): Pair<String, Int>? {
        val v = decodeVarint(data, offset) ?: return null
        val len = v.first
        val start = v.second
        if (start + len > data.size) return null
        val str = if (len == 0) "" else String(data, start, len, StandardCharsets.UTF_8)
        return Pair(str, start + len)
    }

    fun encodeMapStrStr(map: Map<String, String>): ByteArray {
        val entries = map.entries.filter { it.key.isNotEmpty() }
        var out = encodeVarint(entries.size)
        for ((k, v) in entries) {
            out = out + encodeString(k) + encodeString(v)
        }
        return out
    }

    /** @return Pair(map, nextOffset) or null */
    fun decodeMapStrStr(data: ByteArray, offset: Int): Pair<Map<String, String>, Int>? {
        val v = decodeVarint(data, offset) ?: return null
        var pos = v.second
        val out = mutableMapOf<String, String>()
        repeat(v.first) {
            val k = decodeString(data, pos) ?: return null
            pos = k.second
            val v2 = decodeString(data, pos) ?: return null
            pos = v2.second
            if (k.first.isNotEmpty()) out[k.first] = v2.first
        }
        return Pair(out, pos)
    }

    fun encodeStringList(list: List<String>): ByteArray {
        var out = encodeVarint(list.size)
        for (s in list) out = out + encodeString(s)
        return out
    }

    /** @return Pair(list, nextOffset) or null */
    fun decodeStringList(data: ByteArray, offset: Int): Pair<List<String>, Int>? {
        val v = decodeVarint(data, offset) ?: return null
        var pos = v.second
        val out = mutableListOf<String>()
        repeat(v.first) {
            val s = decodeString(data, pos) ?: return null
            pos = s.second
            out.add(s.first)
        }
        return Pair(out, pos)
    }

    /**
     * 解码控制消息为 Map，供现有 onChannelMessage 使用。
     */
    fun decodeControl(data: ByteArray, prefix: String): Map<String, Any?>? {
        if (!isControl(data) || data.size < 5) return null
        val mt = data[4].toInt() and 0xff
        var offset = 5

        fun readVar(): Int? {
            val p = decodeVarint(data, offset) ?: return null
            offset = p.second
            return p.first
        }
        fun readStr(): String? {
            val p = decodeString(data, offset) ?: return null
            offset = p.second
            return p.first
        }
        fun readMap(): Map<String, String>? {
            val p = decodeMapStrStr(data, offset) ?: return null
            offset = p.second
            return p.first
        }
        fun readList(): List<String>? {
            val p = decodeStringList(data, offset) ?: return null
            offset = p.second
            return p.first
        }

        return when (mt) {
            ControlType.PING.code, ControlType.PONG.code -> {
                val ts = readVar() ?: return null
                val suffix = if (mt == ControlType.PING.code) "ping" else "pong"
                mapOf("type" to "$prefix:$suffix", "ts" to ts)
            }
            ControlType.READY.code -> {
                val chunkBinaryV2 = readVar() ?: return null
                // 服务端 READY 仅写 chunkBinaryV2，无 chunkEncoding 列表（见 dataChannelProxy encodeControlBinary）
                val chunkEncoding =
                    if (offset >= data.size) {
                        emptyList()
                    } else {
                        readList() ?: return null
                    }
                mapOf(
                    "type" to "$prefix:ready",
                    "features" to mapOf(
                        "chunkBinaryV2" to (chunkBinaryV2 != 0),
                        "chunkEncoding" to chunkEncoding,
                    ),
                )
            }
            ControlType.REQ_END.code, ControlType.REQ_CANCEL.code, ControlType.CANCEL.code, ControlType.RES_END.code -> {
                val id = readStr() ?: return null
                val suffix = when (mt) {
                    ControlType.REQ_END.code -> "req:end"
                    ControlType.REQ_CANCEL.code -> "req:cancel"
                    ControlType.CANCEL.code -> "cancel"
                    ControlType.RES_END.code -> "res:end"
                    else -> ""
                }
                mapOf("type" to "$prefix:$suffix", "id" to id)
            }
            ControlType.ACK.code -> {
                val id = readStr() ?: return null
                val delta = readVar() ?: return null
                mapOf("type" to "$prefix:ack", "id" to id, "delta" to delta)
            }
            ControlType.FLOW.code -> {
                val id = readStr() ?: return null
                val action = readStr() ?: return null
                mapOf("type" to "$prefix:flow", "id" to id, "action" to action)
            }
            ControlType.REQ.code, ControlType.REQ_BEGIN.code -> {
                val id = readStr() ?: return null
                val method = readStr() ?: return null
                val path = readStr() ?: return null
                val headers = readMap() ?: return null
                if (mt == ControlType.REQ_BEGIN.code) {
                    val length = readVar() ?: return null
                    val acceptEncoding = readStr() ?: return null
                    val acceptChunkEncoding = readStr() ?: return null
                    val encoding = readStr() ?: return null
                    val encodedLength = readVar() ?: return null
                    val out = mutableMapOf<String, Any?>(
                        "type" to "$prefix:req:begin",
                        "id" to id,
                        "method" to method,
                        "path" to path,
                        "headers" to headers,
                        "length" to length,
                    )
                    if (acceptEncoding.isNotEmpty()) out["acceptEncoding"] = acceptEncoding
                    if (acceptChunkEncoding.isNotEmpty()) out["acceptChunkEncoding"] = acceptChunkEncoding
                    if (encoding.isNotEmpty()) {
                        out["encoding"] = encoding
                        out["encodedLength"] = encodedLength
                    }
                    out
                } else {
                    val acceptEncoding = readStr() ?: return null
                    val acceptChunkEncoding = readStr() ?: return null
                    val out = mutableMapOf<String, Any?>(
                        "type" to "$prefix:req",
                        "id" to id,
                        "method" to method,
                        "path" to path,
                        "headers" to headers,
                    )
                    if (acceptEncoding.isNotEmpty()) out["acceptEncoding"] = acceptEncoding
                    if (acceptChunkEncoding.isNotEmpty()) out["acceptChunkEncoding"] = acceptChunkEncoding
                    out
                }
            }
            ControlType.RES_BEGIN.code -> {
                val id = readStr() ?: return null
                val status = readVar() ?: return null
                val headers = readMap() ?: return null
                val length = readVar() ?: return null
                val headersAny = headers.mapValues { it.value as Any }
                val out = mutableMapOf<String, Any?>(
                    "type" to "$prefix:res:begin",
                    "id" to id,
                    "status" to status,
                    "headers" to headersAny,
                    "length" to length,
                )
                // 服务端 dataChannelProxy 仅发到 length；若将来有扩展尾字段再解析
                if (offset < data.size) {
                    val saved = offset
                    val enc = readStr()
                    val el = readVar()
                    if (enc != null && enc.isNotEmpty() && el != null) {
                        out["encoding"] = enc
                        out["encodedLength"] = el
                    } else {
                        offset = saved
                    }
                }
                out
            }
            ControlType.WS_OPEN_OK.code -> {
                val id = readStr() ?: return null
                mapOf("type" to "$prefix:ws:open:ok", "id" to id)
            }
            ControlType.WS_OPEN_ERROR.code -> {
                val id = readStr() ?: return null
                val error = readStr() ?: return null
                mapOf("type" to "$prefix:ws:open:error", "id" to id, "error" to error)
            }
            ControlType.WS_MESSAGE.code -> {
                val id = readStr() ?: return null
                val data = readStr() ?: return null
                mapOf("type" to "$prefix:ws:message", "id" to id, "data" to data)
            }
            ControlType.WS_ERROR.code -> {
                val id = readStr() ?: return null
                val error = readStr() ?: return null
                mapOf("type" to "$prefix:ws:error", "id" to id, "error" to error)
            }
            ControlType.WS_CLOSE.code -> {
                val id = readStr() ?: return null
                val code = readVar() ?: return null
                val reason = readStr() ?: return null
                mapOf("type" to "$prefix:ws:close", "id" to id, "code" to code, "reason" to reason)
            }
            else -> null
        }
    }

    /**
     * 编码控制消息（客户端 -> 服务端）。
     */
    fun encodeControl(prefix: String, type: ControlType, payload: Map<String, Any?>): ByteArray? {
        val header = MAGIC + byteArrayOf(type.code.toByte())

        return when (type) {
            ControlType.PING, ControlType.PONG -> {
                val ts = (payload["ts"] as? Number)?.toInt() ?: return null
                header + encodeVarint(ts)
            }
            ControlType.REQ_END, ControlType.REQ_CANCEL, ControlType.CANCEL, ControlType.RES_END -> {
                val id = payload["id"]?.toString() ?: return null
                header + encodeString(id)
            }
            ControlType.ACK -> {
                val id = payload["id"]?.toString() ?: return null
                val delta = (payload["delta"] as? Number)?.toInt() ?: return null
                header + encodeString(id) + encodeVarint(delta)
            }
            ControlType.FLOW -> {
                val id = payload["id"]?.toString() ?: return null
                val action = payload["action"]?.toString() ?: return null
                header + encodeString(id) + encodeString(action)
            }
            ControlType.REQ -> {
                val id = payload["id"]?.toString() ?: return null
                val method = payload["method"]?.toString() ?: return null
                val path = payload["path"]?.toString() ?: return null
                @Suppress("UNCHECKED_CAST")
                val headers = payload["headers"] as? Map<String, String> ?: emptyMap()
                val acceptEncoding = payload["acceptEncoding"]?.toString() ?: ""
                val acceptChunkEncoding = payload["acceptChunkEncoding"]?.toString() ?: ""
                header + encodeString(id) + encodeString(method) + encodeString(path) +
                    encodeMapStrStr(headers) + encodeString(acceptEncoding) + encodeString(acceptChunkEncoding)
            }
            ControlType.REQ_BEGIN -> {
                val id = payload["id"]?.toString() ?: return null
                val method = payload["method"]?.toString() ?: return null
                val path = payload["path"]?.toString() ?: return null
                @Suppress("UNCHECKED_CAST")
                val headers = payload["headers"] as? Map<String, String> ?: emptyMap()
                val length = (payload["length"] as? Number)?.toInt() ?: return null
                val acceptEncoding = payload["acceptEncoding"]?.toString() ?: ""
                val acceptChunkEncoding = payload["acceptChunkEncoding"]?.toString() ?: ""
                val encoding = payload["encoding"]?.toString() ?: ""
                val encodedLength = (payload["encodedLength"] as? Number)?.toInt() ?: 0
                header + encodeString(id) + encodeString(method) + encodeString(path) +
                    encodeMapStrStr(headers) + encodeVarint(length) +
                    encodeString(acceptEncoding) + encodeString(acceptChunkEncoding) +
                    encodeString(encoding) + encodeVarint(encodedLength)
            }
            else -> null
        }
    }
}
