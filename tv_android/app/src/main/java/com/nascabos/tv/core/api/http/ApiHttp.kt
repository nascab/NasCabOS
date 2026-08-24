package com.nascabos.tv.core.api.http

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Call
import okhttp3.Callback
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

class ApiHttp(
    private val client: OkHttpClient,
    private val gson: Gson = Gson(),
) {
    suspend fun getJsonMap(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long = 5,
        headers: Map<String, String> = emptyMap(),
    ): Map<String, Any?> {
        return getJsonMapWithHttpCode(baseUrl, path, timeoutSeconds, headers).second
    }

    /** 返回 HTTP 状态码与解析后的 JSON（与 Flutter BaseApiService 401 处理一致）。 */
    suspend fun getJsonMapWithHttpCode(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long = 5,
        headers: Map<String, String> = emptyMap(),
    ): Pair<Int, Map<String, Any?>> {
        return withContext(Dispatchers.IO) {
            val url = buildUrl(baseUrl, path)
            val timedClient = client.newBuilder()
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()
            val requestBuilder = Request.Builder().url(url).get()
            for ((k, v) in headers) requestBuilder.addHeader(k, v)
            val resp = timedClient.newCall(requestBuilder.build()).execute()
            resp.use {
                val code = it.code
                val body = it.body?.string().orEmpty()
                val type = object : TypeToken<Map<String, Any?>>() {}.type
                val parsed = runCatching { gson.fromJson<Map<String, Any?>>(body, type) }.getOrNull()
                val map =
                    if (parsed != null) {
                        parsed
                    } else if (it.isSuccessful) {
                        emptyMap()
                    } else {
                        mapOf("success" to false, "message" to "HTTP_$code")
                    }
                code to map
            }
        }
    }

    suspend fun postJsonMap(
        baseUrl: String,
        path: String,
        body: Any?,
        timeoutSeconds: Long = 5,
        headers: Map<String, String> = emptyMap(),
    ): Map<String, Any?> {
        return postJsonMapWithHttpCode(baseUrl, path, body, timeoutSeconds, headers).second
    }

    suspend fun postJsonMapWithHttpCode(
        baseUrl: String,
        path: String,
        body: Any?,
        timeoutSeconds: Long = 5,
        headers: Map<String, String> = emptyMap(),
    ): Pair<Int, Map<String, Any?>> {
        return withContext(Dispatchers.IO) {
            val url = buildUrl(baseUrl, path)
            val timedClient = client.newBuilder()
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()
            val json = gson.toJson(body)
            val requestBody = json.toRequestBody("application/json; charset=utf-8".toMediaType())
            val requestBuilder = Request.Builder().url(url).post(requestBody)
            requestBuilder.addHeader("Content-Type", "application/json")
            for ((k, v) in headers) requestBuilder.addHeader(k, v)
            val resp = timedClient.newCall(requestBuilder.build()).execute()
            resp.use {
                val code = it.code
                val respBody = it.body?.string().orEmpty()
                val type = object : TypeToken<Map<String, Any?>>() {}.type
                val parsed = runCatching { gson.fromJson<Map<String, Any?>>(respBody, type) }.getOrNull()
                val map =
                    if (parsed != null) {
                        parsed
                    } else if (it.isSuccessful) {
                        emptyMap()
                    } else {
                        mapOf("success" to false, "message" to "HTTP_$code")
                    }
                code to map
            }
        }
    }

    suspend fun getBytes(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long = 8,
        headers: Map<String, String> = emptyMap(),
    ): ByteArray {
        return getBytesWithHttpCode(baseUrl, path, timeoutSeconds, headers).second
    }

    suspend fun getBytesWithHttpCode(
        baseUrl: String,
        path: String,
        timeoutSeconds: Long = 8,
        headers: Map<String, String> = emptyMap(),
    ): Pair<Int, ByteArray> {
        return withContext(Dispatchers.IO) {
            val url = buildUrl(baseUrl, path)
            val timedClient = client.newBuilder()
                .callTimeout(timeoutSeconds, TimeUnit.SECONDS)
                .build()
            val requestBuilder = Request.Builder().url(url).get()
            for ((k, v) in headers) requestBuilder.addHeader(k, v)
            val request = requestBuilder.build()
            suspendCancellableCoroutine { cont ->
                val call = timedClient.newCall(request)
                cont.invokeOnCancellation { call.cancel() }
                call.enqueue(
                    object : Callback {
                        override fun onFailure(call: Call, e: IOException) {
                            if (cont.isCancelled) return
                            cont.resume(0 to ByteArray(0))
                        }

                        override fun onResponse(call: Call, response: Response) {
                            response.use {
                                if (cont.isCancelled) return
                                val code = it.code
                                if (!it.isSuccessful) {
                                    cont.resume(code to ByteArray(0))
                                    return
                                }
                                cont.resume(code to (it.body?.bytes() ?: ByteArray(0)))
                            }
                        }
                    },
                )
            }
        }
    }

    private fun buildUrl(baseUrl: String, path: String): String {
        val base = baseUrl.trim().trimEnd('/')
        val p = if (path.startsWith("/")) path else "/$path"
        val url = "$base$p"
        val parsed = url.toHttpUrlOrNull() ?: throw IllegalArgumentException("invalid_url")
        return parsed.toString()
    }
}
