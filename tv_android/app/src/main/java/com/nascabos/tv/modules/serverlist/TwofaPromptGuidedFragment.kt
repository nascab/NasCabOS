package com.nascabos.tv.modules.serverlist

import android.os.Bundle
import androidx.fragment.app.viewModels
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commit
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.api.AuthApiService
import com.nascabos.tv.data.model.ServerInfo
import kotlinx.coroutines.launch

class TwofaPromptGuidedFragment : GuidedStepSupportFragment() {
    private val viewModel: ServerListViewModel by viewModels()
    private val gson = Gson()

    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private lateinit var server: ServerInfo
    private var tempToken: String = ""
    private var codeText: String = ""
    private var popCount: Int = 1
    private var openHomeOnSuccess: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        server = runCatching {
            gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
        }.getOrNull() ?: ServerInfo()
        tempToken = requireArguments().getString(ARG_TEMP_TOKEN).orEmpty()
        popCount = requireArguments().getInt(ARG_POP_COUNT, 1).coerceAtLeast(1)
        openHomeOnSuccess = requireArguments().getBoolean(ARG_OPEN_HOME, false)
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.twofa_prompt_title),
            getString(R.string.twofa_prompt_desc),
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += GuidedAction.Builder(requireContext())
            .id(ID_CODE)
            .title(getString(R.string.field_twofa_code))
            .description(codeText)
            .descriptionEditable(true)
            .editDescription(codeText)
            .editInputType(android.text.InputType.TYPE_CLASS_NUMBER)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_VERIFY)
            .title(getString(R.string.action_ok))
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_CANCEL)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionEdited(action: GuidedAction) {
        if (action.id == ID_CODE) {
            codeText = action.editDescription?.toString().orEmpty()
            action.description = codeText
            action.editDescription = codeText
        }
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
            ID_VERIFY -> verify()
        }
    }

    private fun verify() {
        val code = codeText.trim()
        if (code.isEmpty()) {
            (activity as? MainActivity)?.showError(getString(R.string.error_twofa_empty))
            return
        }
        val currentBaseUrl = ApiController.baseUrl.trim()
        val baseUrl =
            if (currentBaseUrl.isNotEmpty()) {
                currentBaseUrl
            } else if (server.serverUrl.trim().isNotEmpty()) {
                server.serverUrl.trim()
            } else {
                ApiConfig.p2pBaseUrl
            }
        viewLifecycleOwner.lifecycleScope.launch {
            val result = AuthApiService.verifyTwoFactorLogin(
                baseUrl = baseUrl,
                tempToken = tempToken,
                code = code,
                appContext = requireContext().applicationContext,
            )
            if (!result.success) {
                val msg = mapTwofaMessage(result.message)
                (activity as? MainActivity)?.showError(msg)
                return@launch
            }

            val updated = AuthApiService.applyLoginResult(server, result)
            viewModel.upsert(updated)
            viewModel.setLastSelected(updated)
            ApiController.setBaseUrl(baseUrl)
            ApiController.setTokens(
                updated.accessToken,
                updated.refreshToken,
                updated.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
                updated.serverVersion.trim().takeIf { it.isNotEmpty() },
            )

            if (openHomeOnSuccess) {
                val fm = requireActivity().supportFragmentManager
                fm.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
                fm.commit {
                    setReorderingAllowed(true)
                    replace(R.id.main_container, HomeBrowseFragment.newInstance())
                }
            } else {
                val fm = requireActivity().supportFragmentManager
                repeat(popCount.coerceAtMost(10)) { fm.popBackStack() }
            }
        }
    }

    private fun mapTwofaMessage(raw: String?): String {
        val s = raw?.trim().orEmpty()
        if (s.isEmpty()) return getString(R.string.error_network_failed)
        return when (s) {
            "twofa.INVALID_CODE" -> getString(R.string.error_twofa_invalid)
            "twofa.TOO_MANY_ATTEMPTS" -> getString(R.string.error_twofa_too_many_attempts)
            "auth.INVALID_TOKEN" -> getString(R.string.error_twofa_invalid_token)
            else -> s
        }
    }

    companion object {
        private const val ARG_SERVER_JSON = "server_json"
        private const val ARG_TEMP_TOKEN = "temp_token"
        private const val ARG_POP_COUNT = "pop_count"
        private const val ARG_OPEN_HOME = "open_home"

        private const val ID_CODE = 1L
        private const val ID_VERIFY = 2L
        private const val ID_CANCEL = 3L

        fun newForConnect(
            server: ServerInfo,
            tempToken: String,
            popCount: Int = 2,
        ): TwofaPromptGuidedFragment {
            return TwofaPromptGuidedFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_SERVER_JSON, Gson().toJson(server))
                    putString(ARG_TEMP_TOKEN, tempToken)
                    putInt(ARG_POP_COUNT, popCount)
                    putBoolean(ARG_OPEN_HOME, true)
                }
            }
        }

        fun newForSave(
            server: ServerInfo,
            tempToken: String,
            popCount: Int = 2,
        ): TwofaPromptGuidedFragment {
            return TwofaPromptGuidedFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_SERVER_JSON, Gson().toJson(server))
                    putString(ARG_TEMP_TOKEN, tempToken)
                    putInt(ARG_POP_COUNT, popCount.coerceAtLeast(1))
                    putBoolean(ARG_OPEN_HOME, false)
                }
            }
        }
    }
}
