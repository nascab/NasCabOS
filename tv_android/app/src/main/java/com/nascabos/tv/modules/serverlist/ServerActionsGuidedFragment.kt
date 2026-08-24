package com.nascabos.tv.modules.serverlist

import android.os.Bundle
import android.content.pm.ApplicationInfo
import android.util.Log
import androidx.fragment.app.viewModels
import androidx.fragment.app.commit
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.AuthApiService
import com.nascabos.tv.core.api.p2p.P2pIcePreference
import com.nascabos.tv.data.model.ServerInfo
import androidx.fragment.app.FragmentManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class ServerActionsGuidedFragment : GuidedStepSupportFragment() {
    private val viewModel: ServerListViewModel by viewModels()
    private val gson = Gson()

    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private lateinit var server: ServerInfo
    private var instanceId: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instanceId = Integer.toHexString(System.identityHashCode(this))
        server = runCatching {
            gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
        }.getOrNull() ?: ServerInfo()
        logD(
            "onCreate: serverId='${server.serverId.trim()}' url='${server.serverUrl.trim()}' inputUrl='${server.userInputUrl.trim()}' pair=${server.pairCode.trim().isNotEmpty()} user='${maskUser(server.username)}' passLen=${server.password.length}",
        )
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        val title = server.serverName.trim().ifEmpty { server.serverHostName.trim().ifEmpty { "NasCab" } }
        val desc = when {
            server.isP2p || server.pairCode.trim().isNotEmpty() && server.serverUrl.trim().isEmpty() -> "P2P"
            server.serverUrl.trim().isNotEmpty() -> normalizeUrlPort(server.serverUrl.trim())
            else -> ""
        }
        return GuidanceStylist.Guidance(title, desc, getString(R.string.app_name), null)
    }

    private fun normalizeUrlPort(url: String): String {
        val s = url.trim()
        if (s.isEmpty()) return s
        return s.replace(Regex(":(\\d+)\\.0(?=\\b|/|$)"), ":$1")
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += GuidedAction.Builder(requireContext())
            .id(ID_CONNECT)
            .title(getString(R.string.action_connect))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_EDIT)
            .title(getString(R.string.action_edit))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_DELETE)
            .title(getString(R.string.action_delete))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_BACK)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_CONNECT -> connect()
            ID_EDIT -> edit()
            ID_DELETE -> delete()
            ID_BACK -> requireActivity().supportFragmentManager.popBackStack()
        }
    }

    private fun connect() {
        if (server.requirePasswordEveryLogin) {
            val activity = activity as? MainActivity ?: return
            activity.supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.main_container, PasswordPromptGuidedFragment.newInstance(server))
                addToBackStack(null)
            }
            return
        }
        setIsLoading(true)
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val mode = ApiController.getDevConnectMode()
                logD("connect: start mode=$mode baseUrlBefore='${ApiController.baseUrl.trim()}' isP2pBefore=${ApiController.isP2pMode}")
                val outcome =
                    withContext(Dispatchers.IO) {
                        resolveChannelForLogin(server, mode)
                    }
                val resolved = outcome.resolved
                if (resolved == null) {
                    val msgRes = when (outcome.failure) {
                        ResolveFailure.NoDirectUrl -> R.string.error_no_direct_url
                        ResolveFailure.NoPairCode -> R.string.error_no_pair_code
                        ResolveFailure.NotNasCab -> R.string.error_not_nascab_server
                        ResolveFailure.NetworkFailed -> R.string.error_server_unreachable
                    }
                    logD("connect: resolve failed failure=${outcome.failure}")
                    (activity as? MainActivity)?.showError(getString(msgRes))
                    return@launch
                }

                val baseUrl = resolved.baseUrl
                val authServer = resolved.serverForAuth
                logD(
                    "connect: resolved baseUrl='${baseUrl.trim()}' serverId='${authServer.serverId.trim()}' url='${authServer.serverUrl.trim()}' inputUrl='${authServer.userInputUrl.trim()}' pair=${authServer.pairCode.trim().isNotEmpty()} user='${maskUser(authServer.username)}'",
                )
                ApiController.setBaseUrl(baseUrl)
                val loginStartAt = System.currentTimeMillis()
                val login =
                    withContext(Dispatchers.IO) {
                        AuthApiService.loginToServer(
                            baseUrl = baseUrl,
                            serverInfo = authServer,
                            appContext = requireContext().applicationContext,
                        )
                    }
                logD(
                    "connect: login done costMs=${System.currentTimeMillis() - loginStartAt} success=${login.success} code=${login.code} msg='${login.message?.trim().orEmpty()}' tokenLen=${login.accessToken?.length ?: 0}",
                )
                if (!login.success) {
                    (activity as? MainActivity)?.showError(login.message ?: getString(R.string.error_network_failed))
                    return@launch
                }
                if (login.twoFactorRequired == true && !login.tempToken.isNullOrBlank()) {
                    val activity = activity as? MainActivity ?: return@launch
                    activity.supportFragmentManager.commit {
                        setReorderingAllowed(true)
                        replace(R.id.main_container, TwofaPromptGuidedFragment.newForConnect(authServer, login.tempToken!!))
                        addToBackStack(null)
                    }
                    return@launch
                }
                val updated = AuthApiService.applyLoginResult(authServer, login)
                logD(
                    "connect: applyLoginResult updated serverId='${updated.serverId.trim()}' url='${updated.serverUrl.trim()}' inputUrl='${updated.userInputUrl.trim()}' pair=${updated.pairCode.trim().isNotEmpty()} accessLen=${updated.accessToken.trim().length} refreshLen=${updated.refreshToken.trim().length}",
                )
                viewModel.upsert(updated)
                viewModel.setLastSelected(updated)
                ApiController.setTokens(
                    updated.accessToken,
                    updated.refreshToken,
                    updated.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
                    updated.serverVersion.trim().takeIf { it.isNotEmpty() },
                )
                logD("connect: tokens set baseUrlNow='${ApiController.baseUrl.trim()}' isP2pNow=${ApiController.isP2pMode} -> openHome()")
                openHome()
            } finally {
                if (isAdded) setIsLoading(false)
            }
        }
    }

    private fun setIsLoading(loading: Boolean) {
        val actions = actions
        val connectAction = actions.find { it.id == ID_CONNECT }
        connectAction?.title = if (loading) getString(R.string.status_connecting) else getString(R.string.action_connect)
        connectAction?.isEnabled = !loading

        actions.forEachIndexed { index, action ->
            if (action.id != ID_CONNECT) {
                action.isEnabled = !loading
            }
            notifyActionChanged(index)
        }
    }

    private fun edit() {
        val activity = activity as? MainActivity ?: return
        val latest = viewModel.servers.value.firstOrNull { isSameServer(it, server) }
        val seed = latest ?: server
        logD(
            "edit: latestFound=${latest != null} seed serverId='${seed.serverId.trim()}' url='${seed.serverUrl.trim()}' inputUrl='${seed.userInputUrl.trim()}' pair=${seed.pairCode.trim().isNotEmpty()} user='${maskUser(seed.username)}' passLen=${seed.password.length}",
        )
        val mode = if (seed.serverUrl.trim().isNotEmpty()) {
            AddEditServerGuidedFragment.newAddDirect(seed, popCount = 2)
        } else {
            AddEditServerGuidedFragment.newAddByPairCode(seed, popCount = 2)
        }
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, mode)
            addToBackStack(null)
        }
    }

    private fun isSameServer(a: ServerInfo, b: ServerInfo): Boolean {
        val au = a.username.trim()
        val bu = b.username.trim()
        if (au != bu) return false

        val asid = a.serverId.trim()
        val bsid = b.serverId.trim()
        if (asid.isNotEmpty() && bsid.isNotEmpty()) return asid == bsid

        val ac = a.pairCode.trim()
        val bc = b.pairCode.trim()
        if (ac.isNotEmpty() && bc.isNotEmpty()) return ac == bc

        val auUrl = a.serverUrl.trim().ifEmpty { a.userInputUrl.trim() }
        val buUrl = b.serverUrl.trim().ifEmpty { b.userInputUrl.trim() }
        if (auUrl.isNotEmpty() && buUrl.isNotEmpty()) return auUrl == buUrl

        return false
    }

    private fun logD(message: String) {
        if (isDebuggable()) Log.d("ServerActionsGF", "[$instanceId] $message")
    }

    private fun isDebuggable(): Boolean {
        val flags = requireContext().applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun maskUser(raw: String): String {
        val s = raw.trim()
        if (s.isEmpty()) return ""
        if (s.length <= 2) return "*".repeat(s.length)
        return s.take(1) + "***" + s.takeLast(1)
    }

    private fun delete() {
        viewModel.remove(server)
        requireActivity().supportFragmentManager.popBackStack()
    }

    private fun openHome() {
        val activity = activity as? MainActivity ?: return
        val fm = activity.supportFragmentManager
        fm.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
        fm.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, HomeBrowseFragment.newInstance())
        }
    }

    companion object {
        private const val ARG_SERVER_JSON = "server_json"

        private const val ID_CONNECT = 1L
        private const val ID_EDIT = 2L
        private const val ID_DELETE = 3L
        private const val ID_BACK = 4L

        fun newInstance(server: ServerInfo): ServerActionsGuidedFragment =
            ServerActionsGuidedFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_SERVER_JSON, Gson().toJson(server))
                }
            }
    }

    class PasswordPromptGuidedFragment : GuidedStepSupportFragment() {
        private val viewModel: ServerListViewModel by viewModels()
        private val gson = Gson()
        private val instanceId: String = Integer.toHexString(System.identityHashCode(this))

        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        private lateinit var server: ServerInfo
        private var password: String = ""

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            server = runCatching {
                gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
            }.getOrNull() ?: ServerInfo()
        }

        override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
            val title = server.serverName.trim().ifEmpty { server.serverHostName.trim().ifEmpty { "NasCab" } }
            return GuidanceStylist.Guidance(
                title,
                getString(R.string.prompt_password_desc),
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
            actions += GuidedAction.Builder(requireContext())
                .id(ID_PASSWORD)
                .title(getString(R.string.field_password))
                .description("")
                .descriptionEditable(true)
                .editDescription("")
                .editInputType(android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD)
                .build()
            actions += GuidedAction.Builder(requireContext())
                .id(ID_CONNECT)
                .title(getString(R.string.action_connect))
                .build()
            actions += GuidedAction.Builder(requireContext())
                .id(ID_CANCEL)
                .title(getString(R.string.action_cancel))
                .build()
        }

        override fun onGuidedActionEdited(action: GuidedAction) {
            if (action.id == ID_PASSWORD) {
                password = action.editDescription?.toString().orEmpty()
                action.description = maskPassword(password)
                action.editDescription = password
                val pos = findActionPositionById(ID_PASSWORD)
                if (pos >= 0) notifyActionChanged(pos)
            }
        }

        override fun onGuidedActionClicked(action: GuidedAction) {
            when (action.id) {
                ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
                ID_CONNECT -> connectWithPassword()
            }
        }

        private fun connectWithPassword() {
            val p = password
            if (p.isEmpty()) {
                (activity as? MainActivity)?.showError(getString(R.string.error_password_empty))
                return
            }
            setIsLoading(true)
            viewLifecycleOwner.lifecycleScope.launch {
                try {
                    val mode = ApiController.getDevConnectMode()
                    val serverWithPassword = server.copy(password = p)
                    val loginStartAt = System.currentTimeMillis()
                    logD("connectWithPassword: start mode=$mode baseUrlBefore='${ApiController.baseUrl.trim()}' isP2pBefore=${ApiController.isP2pMode}")
                    val outcome =
                        withContext(Dispatchers.IO) {
                            resolveChannelForLogin(serverWithPassword, mode)
                        }
                    val resolved = outcome.resolved
                    if (resolved == null) {
                        val msgRes = when (outcome.failure) {
                            ResolveFailure.NoDirectUrl -> R.string.error_no_direct_url
                            ResolveFailure.NoPairCode -> R.string.error_no_pair_code
                            ResolveFailure.NotNasCab -> R.string.error_not_nascab_server
                            ResolveFailure.NetworkFailed -> R.string.error_server_unreachable
                        }
                        logD("connectWithPassword: resolve failed failure=${outcome.failure}")
                        (activity as? MainActivity)?.showError(getString(msgRes))
                        return@launch
                    }

                    val baseUrl = resolved.baseUrl
                    val authServer = resolved.serverForAuth.copy(password = p)
                    logD(
                        "connectWithPassword: resolved baseUrl='${baseUrl.trim()}' serverId='${authServer.serverId.trim()}' url='${authServer.serverUrl.trim()}' inputUrl='${authServer.userInputUrl.trim()}' pair=${authServer.pairCode.trim().isNotEmpty()} user='${maskUser(authServer.username)}'",
                    )
                    ApiController.setBaseUrl(baseUrl)
                    val login =
                        withContext(Dispatchers.IO) {
                            AuthApiService.loginToServer(
                                baseUrl = baseUrl,
                                serverInfo = authServer,
                                appContext = requireContext().applicationContext,
                            )
                        }
                    logD(
                        "connectWithPassword: login done costMs=${System.currentTimeMillis() - loginStartAt} success=${login.success} code=${login.code} msg='${login.message?.trim().orEmpty()}' tokenLen=${login.accessToken?.length ?: 0}",
                    )
                    if (!login.success) {
                        (activity as? MainActivity)?.showError(login.message ?: getString(R.string.error_network_failed))
                        return@launch
                    }
                    if (login.twoFactorRequired == true && !login.tempToken.isNullOrBlank()) {
                        val activity = activity as? MainActivity ?: return@launch
                        activity.supportFragmentManager.commit {
                            setReorderingAllowed(true)
                            replace(R.id.main_container, TwofaPromptGuidedFragment.newForConnect(authServer, login.tempToken!!, popCount = 3))
                            addToBackStack(null)
                        }
                        return@launch
                    }
                    val updated = AuthApiService.applyLoginResult(authServer, login)
                    logD(
                        "connectWithPassword: applyLoginResult updated serverId='${updated.serverId.trim()}' url='${updated.serverUrl.trim()}' inputUrl='${updated.userInputUrl.trim()}' pair=${updated.pairCode.trim().isNotEmpty()} accessLen=${updated.accessToken.trim().length} refreshLen=${updated.refreshToken.trim().length}",
                    )
                    viewModel.upsert(updated)
                    viewModel.setLastSelected(updated)
                    ApiController.setTokens(
                        updated.accessToken,
                        updated.refreshToken,
                        updated.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
                        updated.serverVersion.trim().takeIf { it.isNotEmpty() },
                    )
                    logD("connectWithPassword: tokens set baseUrlNow='${ApiController.baseUrl.trim()}' isP2pNow=${ApiController.isP2pMode} -> openHome()")
                    openHome()
                } finally {
                    if (isAdded) setIsLoading(false)
                }
            }
        }

        private fun setIsLoading(loading: Boolean) {
            val actions = actions
            val connectAction = actions.find { it.id == ID_CONNECT }
            connectAction?.title = if (loading) getString(R.string.status_connecting) else getString(R.string.action_connect)
            connectAction?.isEnabled = !loading

            actions.forEachIndexed { index, action ->
                if (action.id != ID_CONNECT) {
                    action.isEnabled = !loading
                }
                notifyActionChanged(index)
            }
        }

        private fun openHome() {
            val activity = activity as? MainActivity ?: return
            val fm = activity.supportFragmentManager
            fm.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
            fm.commit {
                setReorderingAllowed(true)
                replace(R.id.main_container, HomeBrowseFragment.newInstance())
            }
        }

        private fun logD(message: String) {
            if (isDebuggable()) Log.d("ServerActionsPwdGF", "[$instanceId] $message")
        }

        private fun isDebuggable(): Boolean {
            val flags = requireContext().applicationInfo.flags
            return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        }

        private fun maskUser(raw: String): String {
            val s = raw.trim()
            if (s.isEmpty()) return ""
            if (s.length <= 2) return "*".repeat(s.length)
            return s.take(1) + "***" + s.takeLast(1)
        }

        private fun maskPassword(value: String): String {
            val s = value
            if (s.isEmpty()) return ""
            if (s.length == 1) return s
            return "*".repeat(s.length - 1) + s.last()
        }

        companion object {
            private const val ARG_SERVER_JSON = "server_json"

            private const val ID_PASSWORD = 1L
            private const val ID_CONNECT = 2L
            private const val ID_CANCEL = 3L

            fun newInstance(server: ServerInfo): PasswordPromptGuidedFragment =
                PasswordPromptGuidedFragment().apply {
                    arguments = Bundle().apply {
                        putString(ARG_SERVER_JSON, Gson().toJson(server))
                    }
                }
        }
    }
}

private enum class ResolveFailure { NoDirectUrl, NoPairCode, NetworkFailed, NotNasCab }

private data class ResolveOutcome(
    val resolved: ResolvedChannel?,
    val failure: ResolveFailure,
)

private data class ResolvedChannel(
    val baseUrl: String,
    val serverForAuth: ServerInfo,
)

fun pickDirectBaseUrls(server: ServerInfo): List<String> {
    val urls = LinkedHashSet<String>()

    fun addUrl(raw: String) {
        val trimmed = raw.trim().trimEnd('/')
        if (trimmed.isEmpty()) return
        val lower = trimmed.lowercase()
        val fixed =
            if (lower.startsWith("http://") || lower.startsWith("https://")) trimmed
            else "http://$trimmed"
        urls += fixed
    }

    addUrl(server.serverUrl)
    addUrl(server.userInputUrl)

    val lanIp = server.lanIpv4.trim()
    val host = server.serverHost.trim().ifEmpty { server.serverHostName.trim() }
    val lanHttpPort = server.lanHttpPort.trim().ifEmpty { server.serverPortHttp.trim() }
    val lanHttpsPort = server.lanHttpsPort.trim().ifEmpty { server.serverPortHttps.trim() }

    fun addHostPorts(h: String) {
        if (h.isEmpty()) return
        if (lanHttpPort.isNotEmpty()) urls += "http://$h:$lanHttpPort"
        if (lanHttpsPort.isNotEmpty()) urls += "https://$h:$lanHttpsPort"
    }

    if (lanIp.isNotEmpty()) addHostPorts(lanIp)
    if (host.isNotEmpty()) addHostPorts(host)

    if (ApiController.isDebuggable()) {
        Log.d(
            "ServerConnect",
            "pickDirectBaseUrls: serverId='${server.serverId.trim()}' urls=${urls.toList()} lanIp='${lanIp}' host='${host}' ports(http=${lanHttpPort},https=${lanHttpsPort})",
        )
    }
    return urls.toList()
}

private suspend fun resolveChannelForLogin(
    server: ServerInfo,
    mode: ApiController.DevConnectMode,
): ResolveOutcome {
    val directUrls = pickDirectBaseUrls(server)
    val pairCode = server.pairCode.trim()

    fun directResolved(url: String): ResolvedChannel {
        val fixed = url.trim().trimEnd('/')
        val authServer = server.copy(
            serverUrl = fixed,
            userInputUrl = server.userInputUrl.trim().ifEmpty { fixed },
        )
        return ResolvedChannel(baseUrl = fixed, serverForAuth = authServer)
    }

    fun p2pResolved(): ResolvedChannel = ResolvedChannel(baseUrl = ApiConfig.p2pBaseUrl, serverForAuth = server)

    suspend fun checkDirectStatus(url: String) = AuthApiService.checkServerStatus(url, timeoutSeconds = 3)

    suspend fun checkP2pStatus(code: String, pref: P2pIcePreference) =
        try {
            if (ApiController.isDebuggable()) {
                Log.d(
                    "ServerConnect",
                    "resolveChannelForLogin: p2p connect start pref=$pref",
                )
            }
            ApiController.connectP2pByPairCode(code, icePreference = pref)
            val status =
                AuthApiService.checkServerStatus(
                    ApiConfig.p2pBaseUrl,
                    timeoutSeconds = 5,
                )
            if (ApiController.isDebuggable()) {
                Log.d(
                    "ServerConnect",
                    "resolveChannelForLogin: p2p probe pref=$pref success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}'",
                )
            }
            status
        } catch (e: Exception) {
            if (ApiController.isDebuggable()) {
                Log.d(
                    "ServerConnect",
                    "resolveChannelForLogin: p2p connect/probe failed pref=$pref err='${ApiController.formatP2pConnectError(e)}' raw='${e}'",
                )
            }
            null
        }

    fun toFailure(status: com.nascabos.tv.core.api.response.ServerStatusResponse?): ResolveFailure {
        if (status == null) return ResolveFailure.NetworkFailed
        if (!status.success) return ResolveFailure.NetworkFailed
        if (!status.isNasCabServer) return ResolveFailure.NotNasCab
        return ResolveFailure.NetworkFailed
    }

    return when (mode) {
        ApiController.DevConnectMode.Direct -> {
            if (directUrls.isEmpty()) return ResolveOutcome(null, ResolveFailure.NoDirectUrl)
            val statuses = ArrayList<com.nascabos.tv.core.api.response.ServerStatusResponse>(directUrls.size)
            for (url in directUrls) {
                val status = checkDirectStatus(url)
                statuses += status
                if (ApiController.isDebuggable()) {
                    Log.d(
                        "ServerConnect",
                        "resolveChannelForLogin: direct probe url='$url' success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}'",
                    )
                }
                if (status.success && status.isNasCabServer) {
                    return ResolveOutcome(directResolved(url), ResolveFailure.NetworkFailed)
                }
            }
            val anyNonNas = statuses.any { it.success && !it.isNasCabServer }
            ResolveOutcome(null, if (anyNonNas) ResolveFailure.NotNasCab else ResolveFailure.NetworkFailed)
        }

        ApiController.DevConnectMode.P2pDirect -> {
            if (pairCode.isEmpty()) return ResolveOutcome(null, ResolveFailure.NoPairCode)
            if (directUrls.isNotEmpty()) {
                for (url in directUrls) {
                    val status = checkDirectStatus(url)
                    if (ApiController.isDebuggable()) {
                        Log.d(
                            "ServerConnect",
                            "resolveChannelForLogin: p2pDirect fallback direct probe url='$url' success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}'",
                        )
                    }
                    if (status.success && status.isNasCabServer) {
                        return ResolveOutcome(directResolved(url), ResolveFailure.NetworkFailed)
                    }
                }
            }
            val status = checkP2pStatus(pairCode, P2pIcePreference.DirectOnly)
            if (status != null && status.success && status.isNasCabServer) ResolveOutcome(p2pResolved(), ResolveFailure.NetworkFailed)
            else ResolveOutcome(null, toFailure(status))
        }

        ApiController.DevConnectMode.P2pRelay -> {
            if (pairCode.isEmpty()) return ResolveOutcome(null, ResolveFailure.NoPairCode)
            if (directUrls.isNotEmpty()) {
                for (url in directUrls) {
                    val status = checkDirectStatus(url)
                    if (ApiController.isDebuggable()) {
                        Log.d(
                            "ServerConnect",
                            "resolveChannelForLogin: p2pRelay fallback direct probe url='$url' success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}'",
                        )
                    }
                    if (status.success && status.isNasCabServer) {
                        return ResolveOutcome(directResolved(url), ResolveFailure.NetworkFailed)
                    }
                }
            }
            val status = checkP2pStatus(pairCode, P2pIcePreference.RelayOnly)
            if (status != null && status.success && status.isNasCabServer) ResolveOutcome(p2pResolved(), ResolveFailure.NetworkFailed)
            else ResolveOutcome(null, toFailure(status))
        }

        ApiController.DevConnectMode.Auto -> {
            if (directUrls.isEmpty() && pairCode.isEmpty()) return ResolveOutcome(null, ResolveFailure.NetworkFailed)
            val directStatuses = ArrayList<com.nascabos.tv.core.api.response.ServerStatusResponse>(directUrls.size)
            for (url in directUrls) {
                val status = checkDirectStatus(url)
                directStatuses += status
                if (ApiController.isDebuggable()) {
                    Log.d(
                        "ServerConnect",
                        "resolveChannelForLogin: auto direct probe url='$url' success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}'",
                    )
                }
                if (status.success && status.isNasCabServer) {
                    return ResolveOutcome(directResolved(url), ResolveFailure.NetworkFailed)
                }
            }

            val p2pDirectStatus =
                if (pairCode.isNotEmpty()) checkP2pStatus(pairCode, P2pIcePreference.DirectOnly) else null
            if (p2pDirectStatus != null && p2pDirectStatus.success && p2pDirectStatus.isNasCabServer) {
                return ResolveOutcome(p2pResolved(), ResolveFailure.NetworkFailed)
            }

            val p2pRelayStatus =
                if (pairCode.isNotEmpty()) checkP2pStatus(pairCode, P2pIcePreference.RelayOnly) else null
            if (p2pRelayStatus != null && p2pRelayStatus.success && p2pRelayStatus.isNasCabServer) {
                return ResolveOutcome(p2pResolved(), ResolveFailure.NetworkFailed)
            }

            val anyNonNas =
                (directStatuses.any { it.success && !it.isNasCabServer }) ||
                    listOf(p2pDirectStatus, p2pRelayStatus).any { it != null && it.success && !it.isNasCabServer }
            ResolveOutcome(null, if (anyNonNas) ResolveFailure.NotNasCab else ResolveFailure.NetworkFailed)
        }
    }
}
