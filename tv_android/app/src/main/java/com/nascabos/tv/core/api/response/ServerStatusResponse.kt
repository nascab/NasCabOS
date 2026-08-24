package com.nascabos.tv.core.api.response

data class ServerStatusResponse(
    val success: Boolean,
    val isNasCabServer: Boolean,
    val message: String? = null,
    val serverData: Map<String, Any?>? = null,
)
