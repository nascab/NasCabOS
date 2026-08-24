package com.nascabos.tv.core.api.p2p

import kotlinx.coroutines.flow.Flow

data class P2pApiResponse(
    val status: Int,
    val headers: Map<String, String>,
    val bodyBytes: ByteArray,
)

data class P2pApiStreamResponse(
    val status: Int,
    val headers: Map<String, String>,
    val stream: Flow<ByteArray>,
    val cancel: () -> Unit,
)

enum class P2pRtcChannel {
    Api,
    File,
    Upload,
    Download,
    Video,
}
