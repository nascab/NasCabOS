package com.nascabos.tv.modules.serverlist

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.commit
import androidx.fragment.app.viewModels
import androidx.leanback.app.BrowseSupportFragment
import androidx.leanback.widget.ArrayObjectAdapter
import androidx.leanback.widget.BaseGridView
import androidx.leanback.widget.HeaderItem
import androidx.leanback.widget.HorizontalGridView
import androidx.leanback.widget.ListRow
import androidx.leanback.widget.ListRowPresenter
import androidx.leanback.widget.OnItemViewClickedListener
import androidx.leanback.widget.RowPresenter
import androidx.leanback.widget.VerticalGridView
import androidx.lifecycle.lifecycleScope
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.data.model.ServerInfo
import com.nascabos.tv.core.api.AuthApiService
import com.nascabos.tv.modules.serverlist.presenter.ActionCard
import com.nascabos.tv.modules.serverlist.presenter.ActionKind
import com.nascabos.tv.modules.serverlist.presenter.ServerCardPresenter
import com.nascabos.tv.modules.serverlist.presenter.ServerInfoCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.util.Log

class ServerBrowseFragment : BrowseSupportFragment() {
    private val viewModel: ServerListViewModel by viewModels()

    private val listRowPresenter =
        object : ListRowPresenter() {
            override fun initializeRowViewHolder(holder: RowPresenter.ViewHolder) {
                super.initializeRowViewHolder(holder)
                val viewHolder = holder as ViewHolder
                viewHolder.gridView.setItemSpacing(dpToPx(10f))
                viewHolder.gridView.windowAlignment = BaseGridView.WINDOW_ALIGN_NO_EDGE
                viewHolder.gridView.setWindowAlignmentOffsetPercent(50f)
                viewHolder.gridView.setItemAlignmentOffsetPercent(50f)
            }
        }

    private val rowsAdapter = ArrayObjectAdapter(listRowPresenter)
    private val cardPresenter by lazy { ServerCardPresenter(requireContext()) }
    private var hasAutoFocusedFirstRow = false
    private var rootView: View? = null
    private var initialFocusAttempt = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_display_name)
        badgeDrawable = buildTextBadgeDrawable(getString(R.string.app_display_name))
        headersState = HEADERS_HIDDEN
        adapter = rowsAdapter

        onItemViewClickedListener = OnItemViewClickedListener { _, item, _, _ ->
            when (item) {
                is ActionCard ->
                    when (item.kind) {
                        ActionKind.Language -> openLanguage()
                        ActionKind.AddDirect -> openAddEditServer(null, Mode.AddDirect)
                        ActionKind.AddByPairCode -> openPairCodeInput()
                    }

                is ServerInfoCard ->
                    if (isDiscoveredOnly(item.server)) {
                        openAddEditServer(item.server, Mode.AddDirect)
                    } else {
                        openServerActions(item.server)
                    }
            }
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        rootView = view
        requireActivity().onBackPressedDispatcher.addCallback(
            viewLifecycleOwner,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    openExitConfirm()
                }
            },
        )
        viewLifecycleOwner.lifecycleScope.launch {
            combine(viewModel.discoveredServers, viewModel.servers) { discovered, saved ->
                discovered to saved
            }.collectLatest { (discovered, saved) ->
                renderRows(saved, discovered)
                requestInitialFocus()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        viewModel.startUdpDiscovery()
    }

    override fun onStop() {
        viewModel.stopUdpDiscovery()
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        requestInitialFocus()
    }

    private fun renderRows(
        savedServers: List<ServerInfo>,
        discoveredServers: List<ServerInfo>,
    ) {
        rowsAdapter.clear()

        val header = HeaderItem(0L, "")
        val rowAdapter = ArrayObjectAdapter(cardPresenter)
        savedServers.forEach { rowAdapter.add(ServerInfoCard(it)) }
        rowAdapter.add(ActionCard(ActionKind.AddDirect))
        rowAdapter.add(ActionCard(ActionKind.AddByPairCode))
        rowAdapter.add(ActionCard(ActionKind.Language))
        rowsAdapter.add(ListRow(header, rowAdapter))

        if (discoveredServers.isNotEmpty()) {
            val discoveredHeader = HeaderItem(1L, getString(R.string.server_discovered_section))
            val discoveredAdapter = ArrayObjectAdapter(cardPresenter)
            discoveredServers.forEach { discoveredAdapter.add(ServerInfoCard(it)) }
            rowsAdapter.add(ListRow(discoveredHeader, discoveredAdapter))
        }

        if (!hasAutoFocusedFirstRow) {
            hasAutoFocusedFirstRow = true
            setSelectedPosition(0, false)
        }
    }

    private fun requestInitialFocus() {
        val view = rootView ?: return
        if (initialFocusAttempt > 20) return
        view.post {
            if (tryFocusFirstCard()) return@post
            initialFocusAttempt += 1
            view.postDelayed({ requestInitialFocus() }, 80L)
        }
    }

    private fun tryFocusFirstCard(): Boolean {
        setSelectedPosition(0, false)
        val view = rootView ?: return false
        val rowsGrid = findVerticalGridView(view)
        if (rowsGrid != null) {
            rowsGrid.requestFocus()
        }

        val grid = findHorizontalGridView(view) ?: return false
        grid.setSelectedPosition(0)
        return grid.requestFocus()
    }

    private fun openAddEditServer(server: ServerInfo?, mode: Mode) {
        val activity = activity as? MainActivity ?: return
        val fragment = when (mode) {
            Mode.AddDirect -> AddEditServerGuidedFragment.newAddDirect(server)
            Mode.AddByPairCode -> AddEditServerGuidedFragment.newAddByPairCode(server)
        }
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, fragment)
            addToBackStack(null)
        }
    }

    private fun openServerActions(server: ServerInfo) {
        val activity = activity as? MainActivity ?: return
        val fragment = ServerActionsGuidedFragment.newInstance(server)
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, fragment)
            addToBackStack(null)
        }
    }

    private fun openPairCodeInput() {
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, PairCodeInputGuidedFragment())
            addToBackStack(null)
        }
    }

    private fun openLanguage() {
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, LanguageGuidedFragment())
            addToBackStack(null)
        }
    }

    private enum class Mode { AddDirect, AddByPairCode }

    companion object {
        fun newInstance(): ServerBrowseFragment = ServerBrowseFragment()
    }

    private fun openExitConfirm() {
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, ExitConfirmGuidedFragment())
            addToBackStack(null)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private fun findHorizontalGridView(root: View): HorizontalGridView? {
        if (root is HorizontalGridView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findHorizontalGridView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun findVerticalGridView(root: View): VerticalGridView? {
        if (root is VerticalGridView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findVerticalGridView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun buildTextBadgeDrawable(text: String): BitmapDrawable {
        val paint =
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textSize = 18f * resources.displayMetrics.scaledDensity
            }

        val paddingX = dpToPx(12f)
        val height = dpToPx(32f).coerceAtLeast(1)
        val textWidth = paint.measureText(text).toInt()
        val width = (textWidth + paddingX * 2).coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val metrics = paint.fontMetrics
        val baseline = (height - metrics.bottom - metrics.top) / 2f
        canvas.drawText(text, paddingX.toFloat(), baseline, paint)

        return BitmapDrawable(resources, bitmap)
    }

    private fun isDiscoveredOnly(server: ServerInfo): Boolean {
        if (!server.isAutoScanned) return false
        if (server.serverId.trim().isEmpty()) return false
        if (server.username.trim().isNotEmpty()) return false
        if (server.password.trim().isNotEmpty()) return false
        if (server.accessToken.trim().isNotEmpty()) return false
        if (server.refreshToken.trim().isNotEmpty()) return false
        return true
    }

    class ExitConfirmGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(R.string.exit_confirm_title),
                getString(R.string.exit_confirm_message),
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(
            actions: MutableList<androidx.leanback.widget.GuidedAction>,
            savedInstanceState: Bundle?,
        ) {
            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_CONFIRM)
                .title(getString(R.string.action_ok))
                .build()
            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_CANCEL)
                .title(getString(R.string.action_cancel))
                .build()
        }

        override fun onGuidedActionClicked(action: androidx.leanback.widget.GuidedAction) {
            when (action.id) {
                ID_CONFIRM -> requireActivity().finishAffinity()
                ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
            }
        }

        companion object {
            private const val ID_CONFIRM = 1L
            private const val ID_CANCEL = 2L
        }
    }

    class PairCodeInputGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        private var pairCode: String = ""
        private var isConnecting: Boolean = false

        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(R.string.pair_code_input_title),
                null,
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(
            actions: MutableList<androidx.leanback.widget.GuidedAction>,
            savedInstanceState: Bundle?,
        ) {
            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_PAIR_CODE)
                .title(getString(R.string.field_pair_code))
                .description(pairCode)
                .descriptionEditable(true)
                .editInputType(android.text.InputType.TYPE_CLASS_TEXT)
                .build()

            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_CONNECT)
                .title(getString(R.string.action_connect))
                .build()

            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_CANCEL)
                .title(getString(R.string.action_cancel))
                .build()
        }

        override fun onGuidedActionEdited(action: androidx.leanback.widget.GuidedAction) {
            if (action.id == ID_PAIR_CODE) {
                pairCode = action.description.toString()
            }
        }

        override fun onGuidedActionClicked(action: androidx.leanback.widget.GuidedAction) {
            when (action.id) {
                ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
                ID_CONNECT -> connectAndOpenAddByPairCode()
            }
        }

        private fun connectAndOpenAddByPairCode() {
            if (isConnecting) return
            val code = pairCode.trim()
            val err = ApiController.validatePairCodeText(code)
            if (err != null) {
                val message = when (err) {
                    com.nascabos.tv.core.api.PairCodeError.Empty -> getString(R.string.error_pair_code_empty)
                    com.nascabos.tv.core.api.PairCodeError.Invalid -> getString(R.string.error_pair_code_invalid)
                }
                (activity as? MainActivity)?.showError(message)
                return
            }

            viewLifecycleOwner.lifecycleScope.launch {
                val activity = activity as? MainActivity ?: return@launch
                isConnecting = true
                activity.setLoadingVisible(true)
                try {
                    if (ApiController.isDebuggable()) {
                        val masked = if (code.length <= 2) "*".repeat(code.length) else code.take(1) + "***" + code.takeLast(1)
                        Log.d("PairCodeAdd", "connectAndOpenAddByPairCode: start pairCode='$masked'")
                    }
                    val status =
                        withContext(Dispatchers.IO) {
                            ApiController.connectP2pByPairCode(code)
                            AuthApiService.checkServerStatus(ApiConfig.p2pBaseUrl, timeoutSeconds = 5)
                        }
                    if (ApiController.isDebuggable()) {
                        Log.d(
                            "PairCodeAdd",
                            "connectAndOpenAddByPairCode: status success=${status.success} isNas=${status.isNasCabServer} msg='${status.message?.trim().orEmpty()}' dataKeys=${status.serverData?.keys?.take(20)}",
                        )
                    }
                    if (!status.success) {
                        activity.showError(getString(R.string.error_server_unreachable))
                        return@launch
                    }
                    if (!status.isNasCabServer) {
                        activity.showError(getString(R.string.error_not_nascab_server))
                        return@launch
                    }

                    val fragment = AddEditServerGuidedFragment.newAddByPairCode(
                        existing = null,
                        seedPairCode = code,
                        popCount = 2,
                    )
                    activity.supportFragmentManager.commit {
                        setReorderingAllowed(true)
                        replace(R.id.main_container, fragment)
                        addToBackStack(null)
                    }
                } catch (e: Exception) {
                    if (ApiController.isDebuggable()) {
                        Log.d("PairCodeAdd", "connectAndOpenAddByPairCode: failed err='${e}' mapped='${ApiController.formatP2pConnectError(e)}'")
                    }
                    activity.showError(mapPairCodeConnectError(e))
                    return@launch
                } finally {
                    activity.setLoadingVisible(false)
                    isConnecting = false
                }
            }
        }

        private fun mapPairCodeConnectError(e: Throwable): String {
            return when (ApiController.formatP2pConnectError(e)) {
                "pair_server_unreachable" -> getString(R.string.error_server_unreachable)
                "pair_code_invalid" -> getString(R.string.error_server_unreachable)
                else -> getString(R.string.error_server_unreachable)
            }
        }

        companion object {
            private const val ID_PAIR_CODE = 1L
            private const val ID_CONNECT = 2L
            private const val ID_CANCEL = 3L
        }
    }
}
