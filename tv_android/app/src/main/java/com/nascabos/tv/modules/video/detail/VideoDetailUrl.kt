package com.nascabos.tv.modules.video.detail

import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.api.ApiConfig
import java.net.URLEncoder

object VideoDetailUrl {
    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    fun buildPersonImagePath(
        tmdbId: String,
        size: Int = 240,
        thumb: String? = null,
    ): String {
        val id = tmdbId.trim()
        if (id.isEmpty()) return ""
        val token = ApiController.accessToken.trim()
        val sb = StringBuilder()
        sb.append("/api/video/person/image")
        sb.append("?tmdb_id=").append(enc(id))
        if (size > 0) sb.append("&size=").append(enc(size.toString()))
        val t = thumb?.trim().orEmpty()
        if (t.isNotEmpty()) sb.append("&thumb=").append(enc(t))
        if (token.isNotEmpty()) sb.append("&accessToken=").append(enc(token))
        if (ApiController.baseUrl.trim() == ApiConfig.p2pBaseUrl) sb.append("&p2pChannel=video")
        return sb.toString()
    }

    fun buildRawFileUrl(filePath: String): String {
        val p = filePath.trim()
        if (p.isEmpty()) return ""
        val token = ApiController.accessToken.trim()
        val base = ApiController.baseUrl.trim()
        val sb = StringBuilder()
        sb.append(base.trimEnd('/'))
        sb.append("/api/file/rawFile")
        sb.append("?path=").append(enc(p))
        sb.append("&raw=1")
        if (token.isNotEmpty()) sb.append("&accessToken=").append(enc(token))
        if (base == ApiConfig.p2pBaseUrl) sb.append("&p2pChannel=file")
        return sb.toString()
    }
}

