package com.nascabos.tv.modules.serverlist

import android.os.Bundle
import android.content.pm.ApplicationInfo
import android.text.InputType
import android.util.Log
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.commit
import androidx.fragment.app.viewModels
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
import com.nascabos.tv.data.model.ServerInfo
import kotlinx.coroutines.launch
import java.net.URI

class AddEditServerGuidedFragment : GuidedStepSupportFragment() {
    private val viewModel: ServerListViewModel by viewModels()
    private val gson = Gson()

    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private var mode: Mode = Mode.AddDirect
    private var existing: ServerInfo? = null
    private var popCount: Int = 1

    private var serverName: String = ""
    private var serverUrl: String = ""
    private var pairCode: String = ""
    private var username: String = ""
    private var password: String = ""
    private var requirePasswordEveryLogin: Boolean = false

    private var serverUrlAction: GuidedAction? = null
    private var passwordAction: GuidedAction? = null
    private var requirePasswordEveryLoginAction: GuidedAction? = null
    private val instanceId: String = Integer.toHexString(System.identityHashCode(this))

    override fun onCreate(savedInstanceState: Bundle?) {
        val args = arguments ?: Bundle.EMPTY
        mode = Mode.valueOf(args.getString(ARG_MODE) ?: Mode.AddDirect.name)
        existing = args.getString(ARG_SERVER_JSON)?.let { raw ->
            runCatching { gson.fromJson(raw, ServerInfo::class.java) }.getOrNull()
        }
        popCount = args.getInt(ARG_POP_COUNT, 1).coerceAtLeast(1)
        logD("onCreate: mode=$mode popCount=$popCount argsHasServerJson=${args.containsKey(ARG_SERVER_JSON)} argsHasSeedPairCode=${args.containsKey(ARG_SEED_PAIR_CODE)}")
        existing?.let { s ->
            logD(
                "onCreate: existing loaded serverId='${s.serverId.trim()}' url='${s.serverUrl.trim()}' inputUrl='${s.userInputUrl.trim()}' pair=${s.pairCode.trim().isNotEmpty()} user='${maskUser(s.username)}' passLen=${s.password.length} requireEvery=${s.requirePasswordEveryLogin}",
            )
        } ?: logD("onCreate: existing is null")
        if (existing == null && mode == Mode.AddByPairCode) {
            pairCode = args.getString(ARG_SEED_PAIR_CODE).orEmpty().ifEmpty { pairCode }
        }

        val seed = existing
        if (seed != null) {
            serverName = seed.serverName
            serverUrl = seed.userInputUrl.ifEmpty { seed.serverUrl }
            pairCode = seed.pairCode
            username = seed.username
            password = seed.password
            requirePasswordEveryLogin = seed.requirePasswordEveryLogin
        }
        logD(
            "onCreate: seeded vars name='${serverName.trim()}' url='${serverUrl.trim()}' pair=${pairCode.trim().isNotEmpty()} user='${maskUser(username)}' passLen=${password.length} requireEvery=$requirePasswordEveryLogin",
        )

        if (serverName.trim().isEmpty()) serverName = "NasCabServer"
        if (mode == Mode.AddDirect) {
            if (serverUrl.trim().isEmpty()) {
                serverUrl = if (isDebuggable()) "http://192.168.31.100:9000" else "http://"
            }
        }

        super.onCreate(savedInstanceState)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    openCancelConfirm()
                }
            },
        )
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        val title = when (mode) {
            Mode.AddDirect -> getString(R.string.server_add_direct)
            Mode.AddByPairCode -> getString(R.string.server_add_by_pair_code)
        }
        return GuidanceStylist.Guidance(title, null, getString(R.string.app_name), null)
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        applyDefaultsForAddIfNeeded()
        logD(
            "onCreateActions: name='${serverName.trim()}' url='${serverUrl.trim()}' pair=${pairCode.trim().isNotEmpty()} user='${maskUser(username)}' passLen=${password.length} requireEvery=$requirePasswordEveryLogin",
        )
        actions += textAction(
            id = ID_SERVER_NAME,
            title = getString(R.string.field_server_name),
            value = serverName,
            inputType = InputType.TYPE_CLASS_TEXT,
        )

        if (mode == Mode.AddDirect) {
            actions += textAction(
                id = ID_SERVER_URL,
                title = getString(R.string.field_server_url),
                value = serverUrl,
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI,
            ).also { serverUrlAction = it }
        } else {
            actions += textAction(
                id = ID_PAIR_CODE,
                title = getString(R.string.field_pair_code),
                value = pairCode,
                inputType = InputType.TYPE_CLASS_TEXT,
            )
        }

        actions += textAction(
            id = ID_USERNAME,
            title = getString(R.string.field_username),
            value = username,
            inputType = InputType.TYPE_CLASS_TEXT,
        )

        actions += passwordAction(
            id = ID_PASSWORD,
            title = getString(R.string.field_password),
            value = password,
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
        ).also { passwordAction = it }

        actions += GuidedAction.Builder(requireContext())
            .id(ID_REQUIRE_PASSWORD_EVERY_LOGIN)
            .title(getString(R.string.field_require_password_every_login))
            .checkSetId(GuidedAction.CHECKBOX_CHECK_SET_ID)
            .checked(requirePasswordEveryLogin)
            .build()
            .also { requirePasswordEveryLoginAction = it }

        actions += GuidedAction.Builder(requireContext())
            .id(ID_SAVE)
            .title(getString(R.string.action_save))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_CANCEL)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionEdited(action: GuidedAction) {
        val newValue = action.editDescription?.toString().orEmpty()
        when (action.id) {
            ID_SERVER_NAME -> {
                serverName = newValue
                action.description = newValue
                action.editDescription = newValue
            }
            ID_SERVER_URL -> {
                val normalized = normalizeHttpUrlInput(newValue)
                serverUrl = normalized
                action.description = normalized
                action.editDescription = normalized
                notifyActionChangedById(ID_SERVER_URL)
            }
            ID_PAIR_CODE -> {
                pairCode = newValue
                action.description = newValue
                action.editDescription = newValue
            }
            ID_USERNAME -> {
                username = newValue
                action.description = newValue
                action.editDescription = newValue
            }
            ID_PASSWORD -> {
                password = newValue
                action.description = maskPassword(password)
                action.editDescription = password
                notifyActionChangedById(ID_PASSWORD)
            }
        }
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
            ID_SAVE -> save()
        }
    }



    private fun openCancelConfirm() {
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, CancelAddConfirmGuidedFragment())
            addToBackStack(null)
        }
    }

    private fun notifyActionChangedById(id: Long) {
        val pos = findActionPositionById(id)
        if (pos >= 0) notifyActionChanged(pos)
    }

    private fun save() {
        syncFromActions()
        logD(
            "save: syncFromActions done name='${serverName.trim()}' url='${serverUrl.trim()}' pair=${pairCode.trim().isNotEmpty()} user='${maskUser(username)}' passLen=${password.length} requireEvery=$requirePasswordEveryLogin existingNull=${existing == null}",
        )
        viewLifecycleOwner.lifecycleScope.launch {
            val saved = when (mode) {
                Mode.AddDirect -> saveDirect()
                Mode.AddByPairCode -> saveByPairCode()
            } ?: return@launch

            val staged = mergeSessionFromExisting(saved)
            logD(
                "save: staged serverId='${staged.serverId.trim()}' url='${staged.serverUrl.trim()}' inputUrl='${staged.userInputUrl.trim()}' pair=${staged.pairCode.trim().isNotEmpty()} user='${maskUser(staged.username)}' passLen=${staged.password.length}",
            )
            existing?.let { viewModel.removeNow(it) }
            viewModel.upsertNow(staged)

            val baseUrl = if (staged.serverUrl.trim().isNotEmpty()) staged.serverUrl.trim() else ApiConfig.p2pBaseUrl
            val login = AuthApiService.loginToServer(
                baseUrl = baseUrl,
                serverInfo = staged,
                appContext = requireContext().applicationContext,
            )
            if (!login.success) {
                logD("save: login failed message='${login.message?.trim().orEmpty()}'")
                (activity as? MainActivity)?.showError(login.message ?: getString(R.string.error_network_failed))
                return@launch
            }
            if (login.twoFactorRequired == true && !login.tempToken.isNullOrBlank()) {
                logD("save: login requires 2fa")
                val activity = activity as? MainActivity ?: return@launch
                activity.supportFragmentManager.commit {
                    setReorderingAllowed(true)
                    replace(
                        R.id.main_container,
                        TwofaPromptGuidedFragment.newForSave(staged, login.tempToken!!, popCount = popCount + 1),
                    )
                    addToBackStack(null)
                }
                return@launch
            }

            val updated = AuthApiService.applyLoginResult(staged, login)
            logD(
                "save: applyLoginResult updated serverId='${updated.serverId.trim()}' url='${updated.serverUrl.trim()}' inputUrl='${updated.userInputUrl.trim()}' user='${maskUser(updated.username)}' passLen=${updated.password.length}",
            )
            viewModel.upsertNow(updated)
            ApiController.setBaseUrl(baseUrl)
            ApiController.setTokens(
                updated.accessToken,
                updated.refreshToken,
                updated.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
                updated.serverVersion.trim().takeIf { it.isNotEmpty() },
            )
            val fm = requireActivity().supportFragmentManager
            repeat(popCount.coerceAtMost(10)) { fm.popBackStack() }
        }
    }

    private fun mergeSessionFromExisting(incoming: ServerInfo): ServerInfo {
        val seed = existing ?: return incoming
        return incoming.copy(
            accessToken = seed.accessToken,
            refreshToken = seed.refreshToken,
            lastLoginTimeEpochMs = seed.lastLoginTimeEpochMs,
            serverId = incoming.serverId.ifEmpty { seed.serverId },
            serverPlatform = incoming.serverPlatform.ifEmpty { seed.serverPlatform },
            serverVersion = incoming.serverVersion.ifEmpty { seed.serverVersion },
            serverHostName = incoming.serverHostName.ifEmpty { seed.serverHostName },
            serverPortHttp = incoming.serverPortHttp.ifEmpty { seed.serverPortHttp },
            serverPortHttps = incoming.serverPortHttps.ifEmpty { seed.serverPortHttps },
            lanIpv4 = incoming.lanIpv4.ifEmpty { seed.lanIpv4 },
            lanHttpPort = incoming.lanHttpPort.ifEmpty { seed.lanHttpPort },
            lanHttpsPort = incoming.lanHttpsPort.ifEmpty { seed.lanHttpsPort },
            isAutoScanned = seed.isAutoScanned,
            isLocalServer = seed.isLocalServer,
        )
    }

    private fun syncFromActions() {
        findActionById(ID_SERVER_NAME)?.let {
            serverName = it.editDescription?.toString() ?: it.description.toString()
        }
        if (mode == Mode.AddDirect) {
            findActionById(ID_SERVER_URL)?.let {
                serverUrl = it.editDescription?.toString() ?: it.description.toString()
            }
        } else {
            findActionById(ID_PAIR_CODE)?.let {
                pairCode = it.editDescription?.toString() ?: it.description.toString()
            }
        }
        findActionById(ID_USERNAME)?.let {
            username = it.editDescription?.toString() ?: it.description.toString()
        }
        requirePasswordEveryLogin = requirePasswordEveryLoginAction?.isChecked ?: requirePasswordEveryLogin
    }

    private suspend fun saveDirect(): ServerInfo? {
        val url = normalizeHttpUrlInput(serverUrl)
        serverUrl = url
        serverUrlAction?.let {
            it.description = url
            it.editDescription = url
            notifyActionChangedById(ID_SERVER_URL)
        }
        if (url.isEmpty() || url == "http://" || url == "https://") {
            (activity as? MainActivity)?.showError(getString(R.string.error_server_url_empty))
            return null
        }
        val u = username.trim()
        if (u.isEmpty()) {
            (activity as? MainActivity)?.showError(getString(R.string.error_username_empty))
            return null
        }
        if (password.isEmpty()) {
            (activity as? MainActivity)?.showError(getString(R.string.error_password_empty))
            return null
        }

        val status = AuthApiService.checkServerStatus(url, timeoutSeconds = 3)
        if (!status.success) {
            (activity as? MainActivity)?.showError(getString(R.string.error_network_failed))
            return null
        }
        if (!status.isNasCabServer) {
            (activity as? MainActivity)?.showError(getString(R.string.error_not_nascab_server))
            return null
        }

        val uri = runCatching { URI(url) }.getOrNull()
        val host = uri?.host.orEmpty()
        val port = if (uri?.port != null && uri.port != -1) uri.port.toString() else ""

        val data = status.serverData.orEmpty()
        val serverId = data["serverId"]?.toString().orEmpty()
        val httpPort = normalizePortValue(data["httpPort"])
        val httpsPort = normalizePortValue(data["httpsPort"])
        val hostname = data["hostname"]?.toString().orEmpty()
        val platform = data["platform"]?.toString().orEmpty().ifEmpty { "unknown" }

        return ServerInfo(
            serverId = serverId,
            serverUrl = url,
            userInputUrl = url,
            serverName = serverName.trim().ifEmpty { "NasCabServer" },
            serverHost = host,
            serverPortHttp = if (httpPort.isNotEmpty()) httpPort else port,
            serverPortHttps = httpsPort,
            serverHostName = hostname,
            serverPlatform = platform,
            isAutoScanned = false,
            isLocalServer = false,
            isP2p = false,
            pairCode = "",
            username = u,
            password = password,
            requirePasswordEveryLogin = requirePasswordEveryLogin,
        )
    }

    private suspend fun saveByPairCode(): ServerInfo? {
        val code = pairCode.trim()
        val err = ApiController.validatePairCodeText(code)
        if (err != null) {
            val message = when (err) {
                com.nascabos.tv.core.api.PairCodeError.Empty -> getString(R.string.error_pair_code_empty)
                com.nascabos.tv.core.api.PairCodeError.Invalid -> getString(R.string.error_pair_code_invalid)
            }
            (activity as? MainActivity)?.showError(message)
            return null
        }
        val u = username.trim()
        if (u.isEmpty()) {
            (activity as? MainActivity)?.showError(getString(R.string.error_username_empty))
            return null
        }
        if (password.isEmpty()) {
            (activity as? MainActivity)?.showError(getString(R.string.error_password_empty))
            return null
        }

        return try {
            if (ApiController.isDebuggable()) {
                val masked = if (code.length <= 2) "*".repeat(code.length) else code.take(1) + "***" + code.takeLast(1)
                Log.d("PairCodeAdd", "saveByPairCode: start pairCode='$masked' user='${maskUser(u)}'")
            }
            ApiController.connectP2pByPairCode(code)
            val status = AuthApiService.checkServerStatus(ApiConfig.p2pBaseUrl, timeoutSeconds = 5)
            if (ApiController.isDebuggable()) {
                Log.d(
                    "PairCodeAdd",
                    "saveByPairCode: status success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}' dataKeys=${status.serverData?.keys?.take(20)}",
                )
            }
            if (!status.success) {
                (activity as? MainActivity)?.showError(getString(R.string.error_server_unreachable))
                null
            } else if (!status.isNasCabServer) {
                (activity as? MainActivity)?.showError(getString(R.string.error_not_nascab_server))
                null
            } else {
                val data = status.serverData.orEmpty()
                ServerInfo(
                    serverId = data["serverId"]?.toString().orEmpty(),
                    serverUrl = "",
                    userInputUrl = "",
                    serverName = serverName.trim().ifEmpty { "NasCabServer" },
                    serverHost = "",
                    serverPortHttp = normalizePortValue(data["httpPort"]),
                    serverPortHttps = normalizePortValue(data["httpsPort"]),
                    serverHostName = data["hostname"]?.toString().orEmpty(),
                    serverPlatform = data["platform"]?.toString().orEmpty().ifEmpty { "unknown" },
                    isAutoScanned = false,
                    isLocalServer = false,
                    isP2p = true,
                    pairCode = code,
                    username = u,
                    password = password,
                    requirePasswordEveryLogin = requirePasswordEveryLogin,
                )
            }
        } catch (e: Exception) {
            if (ApiController.isDebuggable()) {
                Log.d("PairCodeAdd", "saveByPairCode: failed err='${e}' mapped='${ApiController.formatP2pConnectError(e)}'")
            }
            val msg = when (ApiController.formatP2pConnectError(e)) {
                "pair_server_unreachable" -> getString(R.string.error_server_unreachable)
                "pair_code_invalid" -> getString(R.string.error_server_unreachable)
                else -> getString(R.string.error_network_failed)
            }
            (activity as? MainActivity)?.showError(msg)
            null
        }
    }

    private fun normalizePortValue(value: Any?): String {
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

    private fun textAction(
        id: Long,
        title: String,
        value: String,
        inputType: Int,
    ): GuidedAction {
        return GuidedAction.Builder(requireContext())
            .id(id)
            .title(title)
            .description(value)
            .descriptionEditable(true)
            .editDescription(value)
            .editInputType(inputType)
            .build()
    }

    private fun passwordAction(
        id: Long,
        title: String,
        value: String,
        inputType: Int,
    ): GuidedAction {
        return GuidedAction.Builder(requireContext())
            .id(id)
            .title(title)
            .description(maskPassword(value))
            .descriptionEditable(true)
            .editDescription(value)
            .editInputType(inputType)
            .build()
    }

    private fun maskPassword(value: String): String {
        val s = value
        if (s.isEmpty()) return ""
        if (s.length == 1) return s
        return "*".repeat(s.length - 1) + s.last()
    }

    private fun applyDefaultsForAddIfNeeded() {
        if (existing == null) {
            val name = serverName.trim()
            if (name.isEmpty() || name == "NasCabOS") {
                serverName = "NasCabServer"
            }
            if (mode == Mode.AddDirect) {
                val url = serverUrl.trim()
                if (url.isEmpty() || url == "http://" || url == "https://") {
                    serverUrl = if (isDebuggable()) "http://192.168.31.100:9000" else "http://"
                }
            }
        } else if (serverName.trim().isEmpty()) {
            serverName = "NasCabServer"
        }
    }

    private fun normalizeHttpUrlInput(input: String): String {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return ""
        val lower = trimmed.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) return trimmed
        return "http://$trimmed"
    }

    private fun isDebuggable(): Boolean {
        val flags = requireContext().applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun logD(message: String) {
        if (isDebuggable()) Log.d("AddEditServerGF", "[$instanceId] $message")
    }

    private fun maskUser(raw: String): String {
        val s = raw.trim()
        if (s.isEmpty()) return ""
        if (s.length <= 2) return "*".repeat(s.length)
        return s.take(1) + "***" + s.takeLast(1)
    }

    private enum class Mode { AddDirect, AddByPairCode }

    class CancelAddConfirmGuidedFragment : GuidedStepSupportFragment() {
        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
            return GuidanceStylist.Guidance(
                getString(R.string.cancel_add_confirm_title),
                getString(R.string.cancel_add_confirm_message),
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
            actions += GuidedAction.Builder(requireContext())
                .id(ID_CONFIRM)
                .title(getString(R.string.action_ok))
                .build()
            actions += GuidedAction.Builder(requireContext())
                .id(ID_CANCEL)
                .title(getString(R.string.action_cancel))
                .build()
        }

        override fun onGuidedActionClicked(action: GuidedAction) {
            val fm = requireActivity().supportFragmentManager
            when (action.id) {
                ID_CONFIRM -> {
                    fm.popBackStack()
                    fm.popBackStack()
                }
                ID_CANCEL -> fm.popBackStack()
            }
        }

        companion object {
            private const val ID_CONFIRM = 1L
            private const val ID_CANCEL = 2L
        }
    }

    companion object {
        private const val ARG_MODE = "mode"
        private const val ARG_SERVER_JSON = "server_json"
        private const val ARG_SEED_PAIR_CODE = "seed_pair_code"
        private const val ARG_POP_COUNT = "pop_count"

        private const val ID_SERVER_NAME = 1L
        private const val ID_SERVER_URL = 2L
        private const val ID_PAIR_CODE = 3L
        private const val ID_USERNAME = 4L
        private const val ID_PASSWORD = 5L
        private const val ID_REQUIRE_PASSWORD_EVERY_LOGIN = 6L
        private const val ID_SAVE = 100L
        private const val ID_CANCEL = 101L

        fun newAddDirect(existing: ServerInfo?, popCount: Int = 1): AddEditServerGuidedFragment =
            AddEditServerGuidedFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_MODE, Mode.AddDirect.name)
                    if (existing != null) putString(ARG_SERVER_JSON, Gson().toJson(existing))
                    putInt(ARG_POP_COUNT, popCount.coerceAtLeast(1))
                }
            }

        fun newAddByPairCode(
            existing: ServerInfo?,
            seedPairCode: String? = null,
            popCount: Int = 1,
        ): AddEditServerGuidedFragment =
            AddEditServerGuidedFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_MODE, Mode.AddByPairCode.name)
                    if (existing != null) putString(ARG_SERVER_JSON, Gson().toJson(existing))
                    if (seedPairCode != null) putString(ARG_SEED_PAIR_CODE, seedPairCode)
                    putInt(ARG_POP_COUNT, popCount.coerceAtLeast(1))
                }
            }
    }
}
