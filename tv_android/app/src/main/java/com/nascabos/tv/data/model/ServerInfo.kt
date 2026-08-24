package com.nascabos.tv.data.model

data class ServerInfo(
    val serverId: String = "",
    val serverUrl: String = "",
    val userInputUrl: String = "",
    val lanIpv4: String = "",
    val lanHttpPort: String = "",
    val lanHttpsPort: String = "",
    val serverName: String = "",
    val serverHost: String = "",
    val serverPortHttp: String = "",
    val serverPortHttps: String = "",
    val serverHostName: String = "",
    val serverPlatform: String = "unknown",
    /** 登录接口返回的 serverVersion，持久化供客户端功能门槛判断 */
    val serverVersion: String = "",
    val isAutoScanned: Boolean = false,
    val isLocalServer: Boolean = false,
    val isP2p: Boolean = false,
    val pairCode: String = "",
    val username: String = "",
    val password: String = "",
    val requirePasswordEveryLogin: Boolean = false,
    val accessToken: String = "",
    val refreshToken: String = "",
    /** 登录/刷新返回的 expiresIn（Unix 秒） */
    val accessTokenExpiresAtEpochSec: Long = 0L,
    val lastLoginTimeEpochMs: Long = 0L,
) {
    val hasPairCode: Boolean get() = pairCode.trim().isNotEmpty()
    val hasDirectUrl: Boolean get() = serverUrl.trim().isNotEmpty()
}
