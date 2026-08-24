package com.nascabos.tv.data.storage

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.nascabos.tv.data.model.ServerInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.serverDataStore by preferencesDataStore(name = "server_store")

class ServerStore(
    private val appContext: Context,
    private val gson: Gson = Gson(),
) {
    private val keyServers = stringPreferencesKey("saved_servers")
    private val keyLastSelected = stringPreferencesKey("last_selected_server")
    private val keyHomeFocusRow = intPreferencesKey("home_focus_row")
    private val keyHomeFocusCard = intPreferencesKey("home_focus_card")

    val serversFlow: Flow<List<ServerInfo>> =
        appContext.serverDataStore.data.map { prefs ->
            decodeServers(prefs[keyServers])
        }

    suspend fun upsert(server: ServerInfo) {
        appContext.serverDataStore.edit { prefs ->
            val current = decodeServers(prefs[keyServers])
            val updated = upsertInto(current, server)
            prefs[keyServers] = gson.toJson(updated)
        }
    }

    suspend fun remove(server: ServerInfo) {
        appContext.serverDataStore.edit { prefs ->
            val current = decodeServers(prefs[keyServers])
            val updated = current.filterNot { uniqueKey(it) == uniqueKey(server) }
            prefs[keyServers] = gson.toJson(updated)
        }
    }

    suspend fun setLastSelected(server: ServerInfo) {
        appContext.serverDataStore.edit { prefs ->
            prefs[keyLastSelected] = gson.toJson(server)
        }
    }

    val lastSelectedFlow: Flow<ServerInfo?> =
        appContext.serverDataStore.data.map { prefs ->
            prefs[keyLastSelected]?.let { raw ->
                runCatching { gson.fromJson(raw, ServerInfo::class.java) }.getOrNull()
            }
        }

    val homeFocusRowFlow: Flow<Int> =
        appContext.serverDataStore.data.map { prefs ->
            prefs[keyHomeFocusRow] ?: 0
        }

    val homeFocusCardFlow: Flow<Int> =
        appContext.serverDataStore.data.map { prefs ->
            prefs[keyHomeFocusCard] ?: 0
        }

    suspend fun setHomeFocus(rowIndex: Int, cardIndex: Int) {
        appContext.serverDataStore.edit { prefs ->
            prefs[keyHomeFocusRow] = rowIndex.coerceAtLeast(0)
            prefs[keyHomeFocusCard] = cardIndex.coerceAtLeast(0)
        }
    }

    private fun decodeServers(raw: String?): List<ServerInfo> {
        val json = (raw ?: "").trim()
        if (json.isEmpty()) return emptyList()
        val type = object : TypeToken<List<ServerInfo>>() {}.type
        val list = runCatching { gson.fromJson<List<ServerInfo>>(json, type) }.getOrNull() ?: emptyList()
        return dedupeByUniqueKey(list)
    }

    private fun upsertInto(existing: List<ServerInfo>, incoming: ServerInfo): List<ServerInfo> {
        val key = uniqueKey(incoming)
        var idx = existing.indexOfFirst { uniqueKey(it) == key }
        // 登录成功后服务器可能返回新配对码，此时 incoming 的 key 为 sid:xxx|u:xxx，而本地可能是 pair:旧码|u:xxx，需按 serverId+username 再匹配一次，避免重复条目且正确更新配对码
        if (idx < 0 && incoming.serverId.trim().isNotEmpty()) {
            val u = normalizedUsername(incoming)
            idx = existing.indexOfFirst { it.serverId.trim() == incoming.serverId.trim() && normalizedUsername(it) == u }
        }
        val merged = if (idx >= 0) mergeByPreference(existing[idx], incoming) else incoming
        val out = if (idx >= 0) {
            existing.toMutableList().apply { set(idx, merged) }.toList()
        } else {
            existing + merged
        }
        return dedupeByUniqueKey(out)
    }

    private fun normalizedUsername(server: ServerInfo): String = server.username.trim()

    private fun uniqueKey(server: ServerInfo): String {
        val username = normalizedUsername(server)
        val sid = server.serverId.trim()
        if (sid.isNotEmpty()) return "sid:$sid|u:$username"

        val code = server.pairCode.trim()
        if (code.isNotEmpty()) return "pair:$code|u:$username"

        val url = server.serverUrl.trim()
        if (url.isNotEmpty()) return "url:$url|u:$username"

        val input = server.userInputUrl.trim()
        if (input.isNotEmpty()) return "input:$input|u:$username"

        return "empty|u:$username"
    }

    private fun dedupeByUniqueKey(list: List<ServerInfo>): List<ServerInfo> {
        val byKey = LinkedHashMap<String, ServerInfo>()
        for (s in list) {
            val key = uniqueKey(s)
            val existing = byKey[key]
            byKey[key] = if (existing == null) s else mergeByPreference(existing, s)
        }
        return byKey.values.toList()
    }

    private fun preferNonEmpty(incoming: String, existing: String): String =
        if (incoming.trim().isNotEmpty()) incoming else existing

    private fun mergeByPreference(existing: ServerInfo, incoming: ServerInfo): ServerInfo {
        val merged = ServerInfo(
            serverId = preferNonEmpty(incoming.serverId, existing.serverId),
            serverUrl = preferNonEmpty(incoming.serverUrl, existing.serverUrl),
            userInputUrl = preferNonEmpty(incoming.userInputUrl, existing.userInputUrl),
            lanIpv4 = preferNonEmpty(incoming.lanIpv4, existing.lanIpv4),
            lanHttpPort = preferNonEmpty(incoming.lanHttpPort, existing.lanHttpPort),
            lanHttpsPort = preferNonEmpty(incoming.lanHttpsPort, existing.lanHttpsPort),
            serverName = preferNonEmpty(incoming.serverName, existing.serverName),
            serverHost = preferNonEmpty(incoming.serverHost, existing.serverHost),
            serverPortHttp = preferNonEmpty(incoming.serverPortHttp, existing.serverPortHttp),
            serverPortHttps = preferNonEmpty(incoming.serverPortHttps, existing.serverPortHttps),
            serverHostName = preferNonEmpty(incoming.serverHostName, existing.serverHostName),
            serverPlatform = preferNonEmpty(incoming.serverPlatform, existing.serverPlatform),
            serverVersion = preferNonEmpty(incoming.serverVersion, existing.serverVersion),
            isAutoScanned = existing.isAutoScanned && incoming.isAutoScanned,
            isLocalServer = existing.isLocalServer || incoming.isLocalServer,
            isP2p = false,
            pairCode = preferNonEmpty(incoming.pairCode, existing.pairCode),
            username = preferNonEmpty(incoming.username, existing.username),
            password = preferNonEmpty(incoming.password, existing.password),
            requirePasswordEveryLogin = incoming.requirePasswordEveryLogin,
            accessToken = preferNonEmpty(incoming.accessToken, existing.accessToken),
            refreshToken = preferNonEmpty(incoming.refreshToken, existing.refreshToken),
            lastLoginTimeEpochMs = if (incoming.lastLoginTimeEpochMs != 0L) incoming.lastLoginTimeEpochMs else existing.lastLoginTimeEpochMs,
        )
        return merged.copy(isP2p = merged.serverUrl.trim().isEmpty() && merged.pairCode.trim().isNotEmpty())
    }
}
