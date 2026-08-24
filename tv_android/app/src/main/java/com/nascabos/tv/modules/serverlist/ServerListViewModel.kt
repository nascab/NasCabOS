package com.nascabos.tv.modules.serverlist

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.nascabos.tv.data.model.ServerInfo
import com.nascabos.tv.data.storage.ServerStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import kotlin.math.min

class ServerListViewModel(
    app: Application,
) : AndroidViewModel(app) {
    private val store = ServerStore(app.applicationContext, Gson())
    private val gson = Gson()

    val servers: StateFlow<List<ServerInfo>> =
        store.serversFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val lastSelected: StateFlow<ServerInfo?> =
        store.lastSelectedFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val homeFocusRow: StateFlow<Int> =
        store.homeFocusRowFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    val homeFocusCard: StateFlow<Int> =
        store.homeFocusCardFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    private val discoveredServersRaw = MutableStateFlow<List<ServerInfo>>(emptyList())
    val discoveredServers: StateFlow<List<ServerInfo>> =
        combine(discoveredServersRaw, servers) { discovered, saved ->
            val savedIds = saved.mapNotNull { it.serverId.trim().ifEmpty { null } }.toSet()
            discovered.filterNot { it.serverId.trim().isNotEmpty() && it.serverId.trim() in savedIds }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private var udpJob: Job? = null
    private var udpSocket: DatagramSocket? = null

    fun upsert(server: ServerInfo) {
        viewModelScope.launch { store.upsert(server) }
    }

    fun remove(server: ServerInfo) {
        viewModelScope.launch { store.remove(server) }
    }

    fun setLastSelected(server: ServerInfo) {
        viewModelScope.launch { store.setLastSelected(server) }
    }

    fun setHomeFocus(rowIndex: Int, cardIndex: Int) {
        viewModelScope.launch { store.setHomeFocus(rowIndex, cardIndex) }
    }

    suspend fun upsertNow(server: ServerInfo) {
        withContext(Dispatchers.IO) { store.upsert(server) }
    }

    suspend fun removeNow(server: ServerInfo) {
        withContext(Dispatchers.IO) { store.remove(server) }
    }

    fun startUdpDiscovery() {
        if (udpJob?.isActive == true) return
        udpJob = viewModelScope.launch(Dispatchers.IO) {
            startUdpDiscoveryLoop()
        }
    }

    fun stopUdpDiscovery() {
        udpJob?.cancel()
        udpJob = null
        try {
            udpSocket?.close()
        } catch (_: Exception) {}
        udpSocket = null
    }

    private suspend fun startUdpDiscoveryLoop() {
        val socket = DatagramSocket(null).apply {
            reuseAddress = true
            soTimeout = 1_000
            bind(InetSocketAddress(8888))
        }
        udpSocket = socket

        val buffer = ByteArray(8192)
        val type = object : TypeToken<Map<String, Any?>>() {}.type

        while (true) {
            try {
                val packet = DatagramPacket(buffer, buffer.size)
                socket.receive(packet)
                val msg = String(packet.data, 0, min(packet.length, buffer.size), Charsets.UTF_8)
                val map = runCatching { gson.fromJson<Map<String, Any?>>(msg, type) }.getOrNull() ?: continue
                val service = map["service"]?.toString().orEmpty()
                if (service != "nascab-pro-service") continue
                val host = map["host"]?.toString().orEmpty()
                val port = normalizePort(map["port"])
                if (host.isBlank() || port.isBlank()) continue

                val serverId = map["serverId"]?.toString().orEmpty()
                val httpsPort = normalizePort(map["httpsPort"])
                val hostname = map["hostname"]?.toString().orEmpty()
                val platform = map["platform"]?.toString().orEmpty().ifEmpty { "unknown" }
                val url = "http://$host:$port"

                val discovered = ServerInfo(
                    serverId = serverId,
                    serverUrl = url,
                    userInputUrl = url,
                    lanIpv4 = packet.address?.hostAddress.orEmpty(),
                    lanHttpPort = port,
                    lanHttpsPort = httpsPort,
                    serverName = "NasCabServer",
                    serverHost = host,
                    serverPortHttp = port,
                    serverPortHttps = httpsPort,
                    serverHostName = hostname,
                    serverPlatform = platform,
                    isAutoScanned = true,
                    isLocalServer = false,
                    isP2p = false,
                    pairCode = "",
                    username = "",
                    password = "",
                    requirePasswordEveryLogin = false,
                )

                withContext(Dispatchers.Main) {
                    onDiscoveredServer(discovered)
                }
            } catch (e: java.net.SocketTimeoutException) {
                continue
            } catch (e: Exception) {
                break
            }
        }
    }

    private fun normalizePort(value: Any?): String {
        return when (value) {
            null -> ""
            is Number -> value.toInt().toString()
            else -> {
                val s = value.toString().trim()
                if (s.isEmpty()) return ""
                if (s.endsWith(".0")) {
                    val d = s.toDoubleOrNull()
                    if (d != null) return d.toInt().toString()
                }
                s
            }
        }
    }

    private fun onDiscoveredServer(server: ServerInfo) {
        val sid = server.serverId.trim()
        if (sid.isEmpty()) return


        val saved = servers.value
        val matches = saved.filter { it.serverId.trim().isNotEmpty() && it.serverId.trim() == sid }
        if (matches.isNotEmpty()) {
            matches.forEach { existing ->
                upsert(
                    existing.copy(
                        serverUrl = server.serverUrl,
                        userInputUrl = existing.userInputUrl,
                        serverHost = server.serverHost,
                        serverPortHttp = server.serverPortHttp,
                        serverPortHttps = server.serverPortHttps,
                        serverHostName = server.serverHostName,
                        serverPlatform = server.serverPlatform,
                        lanIpv4 = server.lanIpv4,
                        lanHttpPort = server.lanHttpPort,
                        lanHttpsPort = server.lanHttpsPort,
                    ),
                )
            }
            return
        }

        val current = discoveredServersRaw.value
        val exists = current.any { it.serverId.trim().isNotEmpty() && it.serverId.trim() == sid }
        if (exists) return
        discoveredServersRaw.value = current + server
    }
}
