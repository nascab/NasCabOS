package com.nascabos.tv.modules.photo.timeline

import android.net.Uri
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController

object PhotoPreviewUrl {
    fun buildRawFileApiPath(
        filePath: String,
        size: Int = 4000,
    ): String {
        val p = filePath.trim()
        if (p.isEmpty()) return ""

        val token = ApiController.accessToken.trim()

        val sb = StringBuilder()
        sb.append("/api/file/rawFile")
        sb.append("?path=").append(Uri.encode(p))
        if (size > 0) sb.append("&size=").append(size)
        if (token.isNotEmpty()) sb.append("&accessToken=").append(Uri.encode(token))
        if (ApiController.baseUrl.trim() == ApiConfig.p2pBaseUrl) sb.append("&p2pChannel=file")
        return sb.toString()
    }
}
