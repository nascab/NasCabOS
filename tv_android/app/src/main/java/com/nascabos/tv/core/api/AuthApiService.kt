package com.nascabos.tv.core.api

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Base64
import android.util.Log
import com.nascabos.tv.core.api.response.ServerStatusResponse
import com.nascabos.tv.data.model.ServerInfo
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

object AuthApiService {
    suspend fun checkServerStatus(
        baseUrl: String,
        timeoutSeconds: Long = 5,
    ): ServerStatusResponse {
        val debug = ApiController.isDebuggable()
        val startedAt = if (debug) System.currentTimeMillis() else 0L
        return try {
            val raw = ApiController.requestJsonMap(
                baseUrl = baseUrl.trim(),
                path = "/api/auth/isNasCabServer",
                timeoutSeconds = timeoutSeconds,
            )
            val (success, message, data) = if (raw["success"] is Boolean) {
                val ok = raw["success"] == true
                val msg = raw["message"]?.toString()
                val inner =
                    (raw["data"] as? Map<*, *>)?.entries
                        ?.associate { it.key?.toString().orEmpty() to it.value }
                Triple(ok, msg, inner ?: raw)
            } else {
                Triple(true, raw["message"]?.toString(), raw)
            }

            val isNas = data?.get("isNasCabOSServer") == true
            val out = ServerStatusResponse(
                success = success,
                isNasCabServer = isNas,
                message = message,
                serverData = data,
            )
            if (debug) {
                Log.d(
                    "AuthApiService",
                    "checkServerStatus: baseUrl='${baseUrl.trim()}' costMs=${System.currentTimeMillis() - startedAt} rawHasData=${raw.containsKey("data")} rawKeys=${raw.keys.take(20)} dataKeys=${out.serverData?.keys?.take(30)} success=${out.success} isNas=${out.isNasCabServer} msg='${out.message?.trim().orEmpty()}'",
                )
            }
            out
        } catch (e: Exception) {
            val out = ServerStatusResponse(
                success = false,
                isNasCabServer = false,
                message = e.toString(),
                serverData = null,
            )
            if (debug) {
                Log.d(
                    "AuthApiService",
                    "checkServerStatus: baseUrl='${baseUrl.trim()}' costMs=${System.currentTimeMillis() - startedAt} failed err='${e}'",
                )
            }
            out
        }
    }

    suspend fun loginToServer(
        baseUrl: String,
        serverInfo: ServerInfo,
        appContext: Context,
        timeoutSeconds: Long = 8,
    ): LoginResponse {
        val debug = ApiController.isDebuggable()
        val startedAt = if (debug) System.currentTimeMillis() else 0L
        return try {
            ApiController.getOrCreateVideoDeviceId(appContext)
            val raw = ApiController.postJsonMap(
                baseUrl = baseUrl.trim(),
                path = "/api/auth/login",
                timeoutSeconds = timeoutSeconds,
                body = mapOf(
                    "username" to serverInfo.username,
                    "password" to obfuscatePassword(serverInfo.password),
                    "device_fingerprint" to buildDeviceFingerprintPayload(appContext),
                ),
            )
            val out = parseLoginResponse(raw)
            if (debug) {
                Log.d(
                    "AuthApiService",
                    "loginToServer: baseUrl='${baseUrl.trim()}' costMs=${System.currentTimeMillis() - startedAt} success=${out.success} code=${out.code} msg='${out.message?.trim().orEmpty()}' tokenLen=${out.accessToken?.length ?: 0}",
                )
            }
            out
        } catch (e: Exception) {
            val out = LoginResponse(success = false, message = e.toString())
            if (debug) {
                Log.d(
                    "AuthApiService",
                    "loginToServer: baseUrl='${baseUrl.trim()}' costMs=${System.currentTimeMillis() - startedAt} failed err='${e}'",
                )
            }
            out
        }
    }

    suspend fun verifyTwoFactorLogin(
        baseUrl: String,
        tempToken: String,
        code: String,
        appContext: Context,
        timeoutSeconds: Long = 8,
    ): LoginResponse {
        return try {
            ApiController.getOrCreateVideoDeviceId(appContext)
            val raw = ApiController.postJsonMap(
                baseUrl = baseUrl.trim(),
                path = "/api/auth/2fa/login/verify",
                timeoutSeconds = timeoutSeconds,
                body = mapOf(
                    "tempToken" to tempToken,
                    "code" to code,
                    "device_fingerprint" to buildDeviceFingerprintPayload(appContext),
                ),
            )
            parseLoginResponse(raw)
        } catch (e: Exception) {
            LoginResponse(success = false, message = e.toString())
        }
    }

    internal fun parseLoginResponse(raw: Map<String, Any?>): LoginResponse {
        val topSuccess = raw["success"] as? Boolean
        val topMessage = raw["message"]?.toString()
        val topCode = (raw["code"] as? Number)?.toInt()

        val data = raw["data"] as? Map<*, *>
        @Suppress("UNCHECKED_CAST")
        val dataMap = data?.entries?.associate { it.key?.toString().orEmpty() to it.value } as? Map<String, Any?>
        val map = if (topSuccess != null) dataMap.orEmpty() else raw

        val success = topSuccess ?: (map["success"] as? Boolean) ?: true
        val message = topMessage ?: map["message"]?.toString()
        val code = topCode ?: (map["code"] as? Number)?.toInt()

        return LoginResponse(
            success = success,
            message = message,
            code = code,
            accessToken = map["accessToken"]?.toString(),
            refreshToken = map["refreshToken"]?.toString(),
            expiresIn = (map["expiresIn"] as? Number)?.toLong(),
            serverVersion = map["serverVersion"]?.toString(),
            platform = map["platform"]?.toString(),
            hostname = map["hostname"]?.toString(),
            serverId = map["serverId"]?.toString(),
            httpPort = (map["httpPort"] as? Number)?.toInt() ?: map["httpPort"]?.toString()?.toIntOrNull(),
            httpsPort = (map["httpsPort"] as? Number)?.toInt() ?: map["httpsPort"]?.toString()?.toIntOrNull(),
            lanIpv4 = map["lanIpv4"]?.toString(),
            pairCode = map["pairCode"]?.toString(),
            twoFactorRequired = map["twoFactorRequired"] as? Boolean,
            tempToken = map["tempToken"]?.toString(),
        )
    }

    private fun obfuscatePassword(password: String): String {
        val b64 = Base64.encodeToString(password.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        return "b64:$b64"
    }

    private fun buildDeviceFingerprintPayload(appContext: Context): Map<String, Any?> {
        val prefs = appContext.getSharedPreferences("device_fingerprint", Context.MODE_PRIVATE)
        val existing = prefs.getString("storage_id", null)?.trim().orEmpty()
        val storageId = if (existing.isNotEmpty()) existing else UUID.randomUUID().toString().also {
            prefs.edit().putString("storage_id", it).apply()
        }

        val locale = Locale.getDefault().toLanguageTag()
        val tz = TimeZone.getDefault()
        val offsetMinutes = tz.getOffset(System.currentTimeMillis()) / 60000

        val platform = "AndroidTV"
        val osVersion = Build.VERSION.RELEASE ?: ""
        val deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
        val deviceName = "$platform $deviceModel".trim()

        val userAgent = runCatching {
            val pm = appContext.packageManager
            val pkg = appContext.packageName
            val pkgInfo = if (Build.VERSION.SDK_INT >= 33) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
            }
            val versionName = pkgInfo.versionName ?: "unknown"
            val versionCode = if (Build.VERSION.SDK_INT >= 28) pkgInfo.longVersionCode else {
                @Suppress("DEPRECATION")
                pkgInfo.versionCode.toLong()
            }
            val appName = runCatching {
                val appInfo = pm.getApplicationInfo(pkg, 0)
                pm.getApplicationLabel(appInfo)?.toString()?.trim().orEmpty()
            }.getOrNull().orEmpty().ifEmpty { "NasCabOS TV" }
            "$appName/$versionName+$versionCode ($platform; $osVersion; $deviceModel)"
        }.getOrElse { "NasCabOS TV/unknown ($platform; $osVersion; $deviceModel)" }

        return mapOf(
            "user_agent" to userAgent,
            "platform" to platform,
            "os_version" to osVersion,
            "device_model" to deviceModel,
            "device_name" to deviceName,
            "language" to locale,
            "timezone_offset" to offsetMinutes,
            "timezone_name" to tz.id,
            "storage_id" to storageId,
            "storage_type" to "shared_preferences",
        )
    }

    fun applyLoginResult(
        serverInfo: ServerInfo,
        login: LoginResponse,
    ): ServerInfo {
        val now = System.currentTimeMillis()
        val httpPort = login.httpPort?.toString().orEmpty()
        val httpsPort = login.httpsPort?.toString().orEmpty()
        val lanIpv4 = login.lanIpv4?.trim().orEmpty()
        val pairCode = login.pairCode?.trim().orEmpty()

        var out = serverInfo.copy(
            accessToken = login.accessToken.orEmpty(),
            refreshToken = login.refreshToken.orEmpty(),
            accessTokenExpiresAtEpochSec = login.expiresIn?.takeIf { it > 0L } ?: 0L,
            lastLoginTimeEpochMs = now,
            serverId = login.serverId?.toString().orEmpty().ifEmpty { serverInfo.serverId },
            serverPlatform = login.platform?.toString().orEmpty().ifEmpty { serverInfo.serverPlatform },
            serverVersion =
                login.serverVersion?.trim()?.takeIf { it.isNotEmpty() } ?: serverInfo.serverVersion,
            serverHostName = login.hostname?.toString().orEmpty().ifEmpty { serverInfo.serverHostName },
            serverPortHttp = httpPort.ifEmpty { serverInfo.serverPortHttp },
            serverPortHttps = httpsPort.ifEmpty { serverInfo.serverPortHttps },
        )

        // 登录成功后若服务器返回了最新配对码，更新本地（与 Flutter 端一致：服务器配对码可能已变更）
        if (pairCode.isNotEmpty()) out = out.copy(pairCode = pairCode)

        if (lanIpv4.isNotEmpty()) {
            out = out.copy(
                lanIpv4 = lanIpv4,
                lanHttpPort = httpPort.ifEmpty { out.lanHttpPort },
                lanHttpsPort = httpsPort.ifEmpty { out.lanHttpsPort },
            )
            val currentUrl = out.serverUrl.trim()
            if (currentUrl.isEmpty()) {
                val preferredScheme = runCatching {
                    val u = out.userInputUrl.trim()
                    if (u.isEmpty()) return@runCatching ""
                    (java.net.URI(u).scheme ?: "").trim().lowercase()
                }.getOrNull().orEmpty()

                val scheme =
                    if (preferredScheme == "https") "https"
                    else if (preferredScheme == "http") "http"
                    else if (httpPort.isEmpty() && httpsPort.isNotEmpty()) "https"
                    else "http"

                val port =
                    if (scheme == "https") httpsPort.ifEmpty { httpPort.ifEmpty { "9000" } }
                    else httpPort.ifEmpty { httpsPort.ifEmpty { "9000" } }

                val lanUrl = "$scheme://$lanIpv4:$port"
                out = out.copy(
                    serverUrl = lanUrl,
                    userInputUrl = out.userInputUrl.trim().ifEmpty { lanUrl },
                )
            }
        }

        val isP2p = out.serverUrl.trim().isEmpty() && out.pairCode.trim().isNotEmpty()
        return out.copy(isP2p = isP2p)
    }
}

data class LoginResponse(
    val success: Boolean,
    val message: String? = null,
    val code: Int? = null,
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val expiresIn: Long? = null,
    val serverVersion: String? = null,
    val platform: String? = null,
    val hostname: String? = null,
    val serverId: String? = null,
    val httpPort: Int? = null,
    val httpsPort: Int? = null,
    val lanIpv4: String? = null,
    val pairCode: String? = null,
    val twoFactorRequired: Boolean? = null,
    val tempToken: String? = null,
)
