package com.nascabos.tv.modules.music

import android.net.Uri
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController

object MusicUrl {
    fun buildCoverApiPath(
        filePath: String,
        size: Int = 640,
    ): String {
        val p = filePath.trim()
        if (p.isEmpty()) return ""
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append("/api/music/cover")
        sb.append("?file_path=").append(Uri.encode(p))
        if (size > 0) sb.append("&size=").append(size)
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        if (ApiController.baseUrl.trim() == ApiConfig.p2pBaseUrl) sb.append("&p2pChannel=file")
        return sb.toString()
    }

    fun buildRawFileUrl(
        filePath: String,
        p2pChannel: String = "video",
    ): String {
        val p = filePath.trim()
        if (p.isEmpty()) return ""
        if (p.startsWith("http://") || p.startsWith("https://")) return p
        val baseUrl = ApiController.baseUrl.trim().trimEnd('/')
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append(baseUrl)
        sb.append("/api/file/rawFile?raw=1&path=").append(Uri.encode(p))
        if (p2pChannel.isNotEmpty()) sb.append("&p2pChannel=").append(Uri.encode(p2pChannel))
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        return sb.toString()
    }
}

