package com.nascabos.tv.core.api.p2p

import android.net.Uri

object P2pChannelUtil {
    fun parseMark(raw: String?): P2pRtcChannel? {
        val s = raw?.trim()?.lowercase().orEmpty()
        return when (s) {
            "api" -> P2pRtcChannel.Api
            "file" -> P2pRtcChannel.File
            "upload" -> P2pRtcChannel.Upload
            "download" -> P2pRtcChannel.Download
            "video" -> P2pRtcChannel.Video
            else -> null
        }
    }

    fun fallbackForPath(path: String): P2pRtcChannel {
        val p = path.trim()
        return when {
            p.startsWith("/api/file/upload") -> P2pRtcChannel.Upload
            p.startsWith("/api/file/download") -> P2pRtcChannel.Download
            p.startsWith("/api/videoPlayer/") -> P2pRtcChannel.Video
            p.startsWith("/api/file/rawFile") -> P2pRtcChannel.File
            p.startsWith("/api/file") || p.startsWith("/api/static") -> P2pRtcChannel.File
            else -> P2pRtcChannel.Api
        }
    }

    fun stripP2pChannelFromPath(path: String): String {
        return stripQueryKey(path, "p2pChannel")
    }

    fun stripQueryKey(path: String, key: String): String {
        val idx = path.indexOf('?')
        if (idx < 0) return path
        val base = path.substring(0, idx)
        val query = path.substring(idx + 1)
        if (query.trim().isEmpty()) return base
        val parts = query.split('&')
        val kept = mutableListOf<String>()
        for (part in parts) {
            val p = part.trim()
            if (p.isEmpty()) continue
            val eq = p.indexOf('=')
            val k = (if (eq >= 0) p.substring(0, eq) else p).trim()
            if (k == key) continue
            kept += p
        }
        return if (kept.isEmpty()) base else "$base?${kept.joinToString("&")}"
    }

    data class Resolved(val channel: P2pRtcChannel, val path: String)

    /**
     * 使用 encodedPath/encodedQuery 保留百分号编码，避免文件名含空格、中文等特殊字符时
     * 在 P2P 服务端 new URL(path, base) 报 invalid_url（直连时浏览器/客户端会发已编码 URL，P2P 需原样传递）。
     */
    fun resolve(
        uri: Uri,
        fallbackChannel: P2pRtcChannel? = null,
    ): Resolved {
        val encodedPath = uri.encodedPath?.takeIf { it.isNotEmpty() } ?: ""
        val encodedQuery = uri.encodedQuery
        val rawPath = if (encodedQuery != null && encodedQuery.isNotEmpty()) "$encodedPath?$encodedQuery" else encodedPath
        val stripped = stripP2pChannelFromPath(rawPath)
        val mark = parseMark(uri.getQueryParameter("p2pChannel"))
        val fallback = fallbackChannel ?: fallbackForPath(uri.path ?: "")
        return Resolved(channel = mark ?: fallback, path = stripped)
    }
}
