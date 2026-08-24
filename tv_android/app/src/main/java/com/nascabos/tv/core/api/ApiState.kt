package com.nascabos.tv.core.api

data class ApiState(
    val serverId: String = "",
    val baseUrl: String = "",
    val accessToken: String = "",
    val refreshToken: String = "",
    /** accessToken 过期时间（Unix 秒），与 Flutter ApiController expiresIn 一致；无则仅依赖 401 刷新 */
    val accessTokenExpiresAtEpochSec: Long? = null,
    /** 服务端版本（登录/刷新接口返回），用于功能门槛判断 */
    val serverVersion: String = "",
)
