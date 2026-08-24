package com.nascabos.tv.modules.serverlist

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.BitmapDrawable
import android.content.pm.ApplicationInfo
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
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
import com.google.gson.Gson
import com.nascabos.tv.AppHostActivity
import com.nascabos.tv.FeatureHostActivity
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.api.AuthApiService
import com.nascabos.tv.core.api.p2p.P2pIcePreference
import com.nascabos.tv.data.model.ServerInfo
import com.nascabos.tv.modules.music.MusicGroupGridFragment
import com.nascabos.tv.modules.music.MusicPlaylistGridFragment
import com.nascabos.tv.modules.music.MusicTrackGridFragment
import com.nascabos.tv.modules.music.player.MusicNowPlayingActivity
import com.nascabos.tv.modules.music.player.MusicPlaybackService
import com.nascabos.tv.modules.photo.library.PhotoLibraryGridFragment
import com.nascabos.tv.modules.photo.library.PhotoLibraryKind
import com.nascabos.tv.modules.serverlist.presenter.HomeCardPresenter
import com.nascabos.tv.modules.serverlist.presenter.HomeEntryCard
import com.nascabos.tv.modules.serverlist.presenter.HomeEntryKind
import com.nascabos.tv.modules.photo.timeline.PhotoTimelineBrowseFragment
import com.nascabos.tv.modules.video_player.VideoPlaybackSettingsGuidedFragment
import com.nascabos.tv.modules.video.VideoGridFragment
import com.nascabos.tv.modules.video.VideoLibraryGridFragment
import com.nascabos.tv.modules.video.VideoLibraryKind
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class HomeBrowseFragment : BrowseSupportFragment() {
    private val viewModel: ServerListViewModel by viewModels()
    private val gson = Gson()

    private val listRowPresenter =
        object : ListRowPresenter() {
            init {
                setHeaderPresenter(null)
            }
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
    private val cardPresenter by lazy { HomeCardPresenter(requireContext()) }
    private var rootView: View? = null
    private var initialFocusAttempt = 0
    private var isMusicPlaying = false
    private var musicService: MusicPlaybackService? = null
    private var musicServiceBound = false
    private var musicStateJob: Job? = null
    private val musicServiceConnection =
        object : ServiceConnection {
            override fun onServiceConnected(name: android.content.ComponentName?, binder: IBinder?) {
                val b = binder as? MusicPlaybackService.LocalBinder ?: return
                musicService = b.service()
                musicServiceBound = true
                musicStateJob?.cancel()
                // 使用 Fragment 的 lifecycleScope，避免在 getView() 为 null（如 onDestroyView 之后回调才到达）时访问 viewLifecycleOwner 导致崩溃
                musicStateJob = lifecycleScope.launch {
                    musicService?.state?.collectLatest { state ->
                        val playing = state.current != null && state.isPlaying
                        if (playing != isMusicPlaying) {
                            isMusicPlaying = playing
                            if (view != null) renderRows(viewModel.lastSelected.value)
                        }
                    }
                }
            }

            override fun onServiceDisconnected(name: android.content.ComponentName?) {
                musicStateJob?.cancel()
                musicStateJob = null
                musicServiceBound = false
                musicService = null
                if (isMusicPlaying) {
                    isMusicPlaying = false
                    if (view != null) renderRows(viewModel.lastSelected.value)
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_display_name)
        headersState = HEADERS_DISABLED
        brandColor = Color.parseColor("#121212")
        searchAffordanceColor = Color.parseColor("#1E88E5")
        badgeDrawable = buildTextBadgeDrawable("NasCabOS TV")
        adapter = rowsAdapter

        onItemViewClickedListener = OnItemViewClickedListener { _, item, _, _ ->
            when (item) {
                is HomeEntryCard -> onEntryClicked(item.kind)
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
            viewModel.lastSelected.collectLatest { server ->
                renderRows(server)
                requestInitialFocus()
            }
        }

        viewLifecycleOwner.lifecycleScope.launch {
            ApiController.connectChannelRevision.collectLatest {
                renderRows(viewModel.lastSelected.value)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        requireContext().bindService(
            Intent(requireContext(), MusicPlaybackService::class.java),
            musicServiceConnection,
            0,
        )
    }

    override fun onStop() {
        super.onStop()
        musicStateJob?.cancel()
        musicStateJob = null
        if (musicServiceBound) {
            requireContext().unbindService(musicServiceConnection)
            musicServiceBound = false
        }
        musicService = null
        if (isMusicPlaying) {
            isMusicPlaying = false
            renderRows(viewModel.lastSelected.value)
        }
    }

    private fun renderRows(server: ServerInfo?) {
        rowsAdapter.clear()

        val serverName = server?.serverName?.trim().orEmpty()
        title = if (serverName.isNotEmpty()) serverName else getString(R.string.app_display_name)

        val videoTitle = getString(R.string.home_menu_video)
        val videoHeader = HeaderItem(0L, videoTitle)
        val video = ArrayObjectAdapter(cardPresenter).apply {
            add(HomeEntryCard(HomeEntryKind.VideoMovies, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoTvSeries, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoRecent, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoFavorite, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoCustomAlbums, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoSmartAlbums, subtitle = videoTitle))
            add(HomeEntryCard(HomeEntryKind.VideoCollections, subtitle = videoTitle))
        }
        rowsAdapter.add(ListRow(videoHeader, video))

        val photoTitle = getString(R.string.home_menu_photo)
        val photoHeader = HeaderItem(1L, photoTitle)
        val photo = ArrayObjectAdapter(cardPresenter).apply {
            add(HomeEntryCard(HomeEntryKind.PhotoTimeline, subtitle = photoTitle))
            add(HomeEntryCard(HomeEntryKind.PhotoToday, subtitle = photoTitle))
            add(HomeEntryCard(HomeEntryKind.PhotoFavorite, subtitle = photoTitle))
            add(HomeEntryCard(HomeEntryKind.PhotoCustomAlbums, subtitle = photoTitle))
            add(HomeEntryCard(HomeEntryKind.PhotoSmartAlbums, subtitle = photoTitle))
            add(HomeEntryCard(HomeEntryKind.PhotoCollections, subtitle = photoTitle))
        }
        rowsAdapter.add(ListRow(photoHeader, photo))

        val musicTitle = getString(R.string.home_menu_music)
        val musicHeader = HeaderItem(2L, musicTitle)
        val music = ArrayObjectAdapter(cardPresenter).apply {
            if (isMusicPlaying) {
                add(HomeEntryCard(HomeEntryKind.MusicNowPlaying, subtitle = musicTitle))
            }
            add(HomeEntryCard(HomeEntryKind.MusicTracks, subtitle = musicTitle))
            add(HomeEntryCard(HomeEntryKind.MusicAlbums, subtitle = musicTitle))
            add(HomeEntryCard(HomeEntryKind.MusicArtists, subtitle = musicTitle))
            add(HomeEntryCard(HomeEntryKind.MusicPlaylists, subtitle = musicTitle))
            add(HomeEntryCard(HomeEntryKind.MusicFavorite, subtitle = musicTitle))
        }
        rowsAdapter.add(ListRow(musicHeader, music))

        val settingsTitle = getString(R.string.home_settings_section)
        val settingsHeader = HeaderItem(3L, settingsTitle)
        val settings = ArrayObjectAdapter(cardPresenter).apply {
            if (isDebuggable()) {
                add(HomeEntryCard(HomeEntryKind.DevNetworkChannel, subtitle = ApiController.connectChannelDisplayValue))
            }
            add(HomeEntryCard(HomeEntryKind.SettingsVideoPlayback, subtitle = settingsTitle))
            add(HomeEntryCard(HomeEntryKind.SettingsLanguage, subtitle = settingsTitle))
            add(HomeEntryCard(HomeEntryKind.SettingsLogout, subtitle = settingsTitle))
        }
        rowsAdapter.add(ListRow(settingsHeader, settings))
    }

    private fun onEntryClicked(kind: HomeEntryKind) {
        when (kind) {
            HomeEntryKind.VideoMovies -> openVideoList(mediaType = "movie")
            HomeEntryKind.VideoTvSeries -> openVideoList(mediaType = "tv")
            HomeEntryKind.VideoRecent -> openVideoHistory()
            HomeEntryKind.VideoFavorite -> openVideoFavorite()
            HomeEntryKind.VideoCustomAlbums -> openVideoLibrary(VideoLibraryKind.Album)
            HomeEntryKind.VideoSmartAlbums -> openVideoLibrary(VideoLibraryKind.SmartAlbum)
            HomeEntryKind.VideoCollections -> openVideoLibrary(VideoLibraryKind.Collection)

            HomeEntryKind.PhotoTimeline -> openPhotoTimeline()
            HomeEntryKind.PhotoToday -> openPhotoTimeline(title = getString(R.string.home_photo_today), loadTheDay = true)
            HomeEntryKind.PhotoFavorite -> openPhotoTimeline(title = getString(R.string.home_photo_favorite), listType = "favorite")
            HomeEntryKind.PhotoCustomAlbums -> openPhotoLibrary(PhotoLibraryKind.Album)
            HomeEntryKind.PhotoSmartAlbums -> openPhotoLibrary(PhotoLibraryKind.SmartAlbum)
            HomeEntryKind.PhotoCollections -> openPhotoLibrary(PhotoLibraryKind.Collection)

            HomeEntryKind.MusicTracks -> openMusicTracks()
            HomeEntryKind.MusicAlbums -> openMusicAlbums()
            HomeEntryKind.MusicArtists -> openMusicArtists()
            HomeEntryKind.MusicPlaylists -> openMusicPlaylists()
            HomeEntryKind.MusicFavorite -> openMusicFavorite()
            HomeEntryKind.MusicNowPlaying -> openMusicNowPlaying()

            HomeEntryKind.FileBrowse -> openPlaceholder(R.string.home_file_browse, R.string.feature_placeholder_files)

            HomeEntryKind.DevNetworkChannel -> openDevNetworkChannel()

            HomeEntryKind.SettingsVideoPlayback -> openVideoPlaybackSettings()
            HomeEntryKind.SettingsLanguage -> openLanguage()
            HomeEntryKind.SettingsLogout -> openLogoutConfirm()
        }
    }

    /** 在新 Activity 中打开子功能，生命周期独立，返回时 MainActivity 与首页焦点保留 */
    private fun openInNewActivity(fragment: Fragment) {
        startActivity(FeatureHostActivity.createIntent(requireContext(), fragment.javaClass.name, fragment.arguments))
    }

    private fun openPlaceholder(titleRes: Int, messageRes: Int) {
        openInNewActivity(FeaturePlaceholderGuidedFragment.newInstance(titleRes, messageRes))
    }

    private fun openMusicTracks() {
        openInNewActivity(MusicTrackGridFragment.newInstance(title = getString(R.string.home_music_tracks)))
    }

    private fun openMusicFavorite() {
        openInNewActivity(
            MusicTrackGridFragment.newInstance(
                title = getString(R.string.home_music_favorite),
                isFavorite = true,
            ),
        )
    }

    private fun openMusicAlbums() {
        openInNewActivity(
            MusicGroupGridFragment.newInstance(
                keyType = "album",
                title = getString(R.string.home_music_albums),
            ),
        )
    }

    private fun openMusicArtists() {
        openInNewActivity(
            MusicGroupGridFragment.newInstance(
                keyType = "artist",
                title = getString(R.string.home_music_artists),
            ),
        )
    }

    private fun openMusicPlaylists() {
        openInNewActivity(MusicPlaylistGridFragment.newInstance())
    }

    private fun openMusicNowPlaying() {
        val ctx = context ?: return
        startActivity(MusicNowPlayingActivity.newIntent(ctx))
    }

    private fun openVideoList(mediaType: String) {
        openInNewActivity(VideoGridFragment.newInstance(mediaType))
    }

    private fun openPhotoTimeline(
        title: String? = null,
        listType: String? = null,
        loadTheDay: Boolean = false,
    ) {
        openInNewActivity(
            PhotoTimelineBrowseFragment.newInstance(
                title = title,
                listType = listType,
                loadTheDay = loadTheDay,
            ),
        )
    }

    private fun openVideoHistory() {
        openInNewActivity(
            VideoGridFragment.newInstance(
                mediaType = "all",
                title = getString(R.string.home_video_recent),
                listType = "history",
            ),
        )
    }

    private fun openVideoFavorite() {
        openInNewActivity(
            VideoGridFragment.newInstance(
                mediaType = "all",
                title = getString(R.string.home_video_favorite),
                listType = "favorite",
            ),
        )
    }

    private fun openVideoLibrary(kind: VideoLibraryKind) {
        openInNewActivity(VideoLibraryGridFragment.newInstance(kind))
    }

    private fun openPhotoLibrary(kind: PhotoLibraryKind) {
        openInNewActivity(PhotoLibraryGridFragment.newInstance(kind))
    }

    private fun openLanguage() {
        openInNewActivity(LanguageGuidedFragment())
    }

    private fun openVideoPlaybackSettings() {
        openInNewActivity(VideoPlaybackSettingsGuidedFragment())
    }

    /** 登出确认在 MainActivity 内用 replace+backStack 打开，这样确认后 popBackStack+replace 会正确在 MainActivity 显示服务器列表，再次点击连接才能正常进入首页（避免在 FeatureHostActivity 内登出导致后续点击失效）。 */
    private fun openLogoutConfirm() {
        val activity = activity as? MainActivity ?: return
        val server = viewModel.lastSelected.value ?: ServerInfo()
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, LogoutConfirmGuidedFragment.newInstance(server))
            addToBackStack(null)
        }
    }

    private fun openDevNetworkChannel() {
        val server = viewModel.lastSelected.value ?: ServerInfo()
        openInNewActivity(DevNetworkChannelGuidedFragment.newInstance(server))
    }

    private fun openSettings() {
        val server = viewModel.lastSelected.value ?: ServerInfo()
        openInNewActivity(HomeSettingsGuidedFragment.newInstance(server))
    }

    fun openSettingsFromActivity() {
        openSettings()
    }

    /** 退出确认留在 MainActivity 内，用 replace + backStack，不另开 Activity */
    private fun openExitConfirm() {
        val activity = activity as? MainActivity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(R.id.main_container, ServerBrowseFragment.ExitConfirmGuidedFragment())
            addToBackStack(null)
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
        val view = rootView ?: return false
        val rowsGrid = findVerticalGridView(view)
        if (rowsGrid != null) {
            rowsGrid.setSelectedPosition(0)
            rowsGrid.requestFocus()
        }

        val grid = findHorizontalGridView(view) ?: return false
        grid.setSelectedPosition(0)
        return grid.requestFocus()
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

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
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

    private fun isDebuggable(): Boolean {
        val flags = requireContext().applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun devConnectModeLabel(): String {
        return when (ApiController.getDevConnectMode()) {
            ApiController.DevConnectMode.Auto -> getString(R.string.dev_network_mode_auto)
            ApiController.DevConnectMode.Direct -> getString(R.string.dev_network_mode_direct)
            ApiController.DevConnectMode.P2pDirect -> getString(R.string.dev_network_mode_p2p_direct)
            ApiController.DevConnectMode.P2pRelay -> getString(R.string.dev_network_mode_p2p_relay)
        }
    }

    companion object {
        fun newInstance(): HomeBrowseFragment = HomeBrowseFragment()
    }

    class HomeSettingsGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        private val gson = Gson()
        private lateinit var server: ServerInfo

        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            server = runCatching {
                gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
            }.getOrNull() ?: ServerInfo()
        }

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(R.string.home_settings_section),
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
                .id(ID_LANGUAGE)
                .title(getString(R.string.action_language))
                .build()

            if (isDebuggable()) {
                actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                    .id(ID_NETWORK)
                    .title(getString(R.string.dev_network_channel))
                    .description(devConnectModeLabel())
                    .build()
            }

            val serverName = server.serverName.trim().ifEmpty { server.serverHostName.trim().ifEmpty { "NasCab" } }
            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_LOGOUT)
                .title(getString(R.string.action_logout))
                .description(getString(R.string.logout_desc, serverName))
                .build()
        }

        override fun onGuidedActionClicked(action: androidx.leanback.widget.GuidedAction) {
            when (action.id) {
                ID_LANGUAGE -> openLanguage()
                ID_NETWORK -> openDevNetworkChannel()
                ID_LOGOUT -> openLogoutConfirm()
            }
        }

        private fun openLanguage() {
            requireActivity().supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.main_container, LanguageGuidedFragment())
                addToBackStack(null)
            }
        }

        private fun openLogoutConfirm() {
            requireActivity().supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.main_container, LogoutConfirmGuidedFragment.newInstance(server))
                addToBackStack(null)
            }
        }

        private fun openDevNetworkChannel() {
            requireActivity().supportFragmentManager.commit {
                setReorderingAllowed(true)
                replace(R.id.main_container, DevNetworkChannelGuidedFragment.newInstance(server))
                addToBackStack(null)
            }
        }

        private fun isDebuggable(): Boolean {
            val flags = requireContext().applicationInfo.flags
            return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        }

        private fun devConnectModeLabel(): String {
            return when (ApiController.getDevConnectMode()) {
                ApiController.DevConnectMode.Auto -> getString(R.string.dev_network_mode_auto)
                ApiController.DevConnectMode.Direct -> getString(R.string.dev_network_mode_direct)
                ApiController.DevConnectMode.P2pDirect -> getString(R.string.dev_network_mode_p2p_direct)
                ApiController.DevConnectMode.P2pRelay -> getString(R.string.dev_network_mode_p2p_relay)
            }
        }

        companion object {
            private const val ARG_SERVER_JSON = "server_json"
            private const val ID_LANGUAGE = 1L
            private const val ID_NETWORK = 2L
            private const val ID_LOGOUT = 3L

            fun newInstance(server: ServerInfo): HomeSettingsGuidedFragment {
                return HomeSettingsGuidedFragment().apply {
                    arguments = Bundle().apply {
                        putString(ARG_SERVER_JSON, Gson().toJson(server))
                    }
                }
            }
        }
    }

    class FeaturePlaceholderGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            val titleRes = requireArguments().getInt(ARG_TITLE_RES)
            val msgRes = requireArguments().getInt(ARG_MESSAGE_RES)
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(titleRes),
                getString(msgRes),
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(
            actions: MutableList<androidx.leanback.widget.GuidedAction>,
            savedInstanceState: Bundle?,
        ) {
            actions += androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(ID_BACK)
                .title(getString(R.string.action_ok))
                .build()
        }

        override fun onGuidedActionClicked(action: androidx.leanback.widget.GuidedAction) {
            if (action.id == ID_BACK) {
                requireActivity().supportFragmentManager.popBackStack()
            }
        }

        companion object {
            private const val ARG_TITLE_RES = "title_res"
            private const val ARG_MESSAGE_RES = "message_res"
            private const val ID_BACK = 1L

            fun newInstance(titleRes: Int, messageRes: Int): FeaturePlaceholderGuidedFragment {
                return FeaturePlaceholderGuidedFragment().apply {
                    arguments = Bundle().apply {
                        putInt(ARG_TITLE_RES, titleRes)
                        putInt(ARG_MESSAGE_RES, messageRes)
                    }
                }
            }
        }
    }

    class LogoutConfirmGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        private val viewModel: ServerListViewModel by viewModels()
        private val gson = Gson()

        private lateinit var server: ServerInfo

        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            server = runCatching {
                gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
            }.getOrNull() ?: ServerInfo()
        }

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            val serverName = server.serverName.trim().ifEmpty { server.serverHostName.trim().ifEmpty { "NasCab" } }
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(R.string.logout_title),
                getString(R.string.logout_confirm_message, serverName),
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
                ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
                ID_CONFIRM -> logout()
            }
        }

        private fun logout() {
            viewLifecycleOwner.lifecycleScope.launch {
                runCatching { ApiController.disconnectP2p() }
                ApiController.setBaseUrl("")
                ApiController.setTokens("", "")
                if (server.accessToken.trim().isNotEmpty() || server.refreshToken.trim().isNotEmpty()) {
                    val updated = server.copy(accessToken = "", refreshToken = "")
                    viewModel.upsert(updated)
                    viewModel.setLastSelected(updated)
                }
                val fm = requireActivity().supportFragmentManager
                fm.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
                fm.commit {
                    setReorderingAllowed(true)
                    replace(R.id.main_container, ServerBrowseFragment.newInstance())
                }
            }
        }

        companion object {
            private const val ARG_SERVER_JSON = "server_json"
            private const val ID_CONFIRM = 1L
            private const val ID_CANCEL = 2L

            fun newInstance(server: ServerInfo): LogoutConfirmGuidedFragment {
                return LogoutConfirmGuidedFragment().apply {
                    arguments = Bundle().apply {
                        putString(ARG_SERVER_JSON, Gson().toJson(server))
                    }
                }
            }
        }
    }

    class DevNetworkChannelGuidedFragment : androidx.leanback.app.GuidedStepSupportFragment() {
        private val gson = Gson()
        private lateinit var server: ServerInfo

        override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            server = runCatching {
                gson.fromJson(requireArguments().getString(ARG_SERVER_JSON), ServerInfo::class.java)
            }.getOrNull() ?: ServerInfo()
        }

        override fun onCreateGuidance(savedInstanceState: Bundle?): androidx.leanback.widget.GuidanceStylist.Guidance {
            return androidx.leanback.widget.GuidanceStylist.Guidance(
                getString(R.string.dev_network_channel),
                getString(R.string.dev_network_channel_desc),
                getString(R.string.app_display_name),
                null,
            )
        }

        override fun onCreateActions(
            actions: MutableList<androidx.leanback.widget.GuidedAction>,
            savedInstanceState: Bundle?,
        ) {
            val current = currentModeId()
            actions += option(ID_MODE_DIRECT, R.string.dev_network_mode_direct, current == ID_MODE_DIRECT)
            actions += option(ID_MODE_P2P_DIRECT, R.string.dev_network_mode_p2p_direct, current == ID_MODE_P2P_DIRECT)
            actions += option(ID_MODE_P2P_RELAY, R.string.dev_network_mode_p2p_relay, current == ID_MODE_P2P_RELAY)
            actions += option(ID_MODE_AUTO, R.string.dev_network_mode_auto, current == ID_MODE_AUTO)
        }

        private fun option(id: Long, titleRes: Int, checked: Boolean): androidx.leanback.widget.GuidedAction {
            return androidx.leanback.widget.GuidedAction.Builder(requireContext())
                .id(id)
                .title(getString(titleRes))
                .checkSetId(CHECK_SET_ID)
                .checked(checked)
                .build()
        }

        private fun currentModeId(): Long {
            return when (ApiController.getDevConnectMode()) {
                ApiController.DevConnectMode.Direct -> ID_MODE_DIRECT
                ApiController.DevConnectMode.P2pDirect -> ID_MODE_P2P_DIRECT
                ApiController.DevConnectMode.P2pRelay -> ID_MODE_P2P_RELAY
                ApiController.DevConnectMode.Auto -> ID_MODE_AUTO
            }
        }

        override fun onGuidedActionClicked(action: androidx.leanback.widget.GuidedAction) {
            val mode = when (action.id) {
                ID_MODE_DIRECT -> ApiController.DevConnectMode.Direct
                ID_MODE_P2P_DIRECT -> ApiController.DevConnectMode.P2pDirect
                ID_MODE_P2P_RELAY -> ApiController.DevConnectMode.P2pRelay
                else -> ApiController.DevConnectMode.Auto
            }
            ApiController.setDevConnectMode(mode)
            viewLifecycleOwner.lifecycleScope.launch {
                val activity = activity as? AppHostActivity
                activity?.setLoadingVisible(true)
                val ok =
                    try {
                        applyMode(mode)
                    } catch (_: Throwable) {
                        false
                    } finally {
                        activity?.setLoadingVisible(false)
                    }
                if (!ok) {
                    ApiController.setDevConnectMode(ApiController.DevConnectMode.Auto)
                } else {
                    if (isAdded) {
                        val message =
                            getString(
                                R.string.dev_network_switch_success,
                                ApiController.connectChannelDisplayValue,
                            )
                        androidx.appcompat.app.AlertDialog.Builder(requireContext(), R.style.Theme_NasCabTv_AlertDialog)
                            .setTitle(getString(R.string.dev_network_channel))
                            .setMessage(message)
                            .setPositiveButton(getString(R.string.action_ok), null)
                            .show()
                    }
                }
                if (isAdded) requireActivity().supportFragmentManager.popBackStack()
            }
        }

        private suspend fun applyMode(mode: ApiController.DevConnectMode): Boolean {
            val activity = activity as? AppHostActivity
            val prevBaseUrl = ApiController.baseUrl
            val prevWasP2p = ApiController.isP2pMode
            val prevTokens = server.accessToken.trim().isNotEmpty() || server.refreshToken.trim().isNotEmpty()

            fun restore() {
                if (!prevWasP2p && prevBaseUrl.trim().isNotEmpty() && prevBaseUrl.trim() != ApiConfig.p2pBaseUrl) {
                    ApiController.setBaseUrl(prevBaseUrl)
                }
            }

            ApiController.setTokens(
                server.accessToken,
                server.refreshToken,
                server.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
                server.serverVersion.trim().takeIf { it.isNotEmpty() },
            )
            if (!prevTokens && mode != ApiController.DevConnectMode.Direct) {
                if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_not_logged_in))
                restore()
                return false
            }

            return when (mode) {
                ApiController.DevConnectMode.Direct -> {
                    val urls = pickDirectBaseUrls(server)
                    if (urls.isEmpty()) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_no_direct_url))
                        restore()
                        return false
                    }
                    val ok =
                        withContext(Dispatchers.IO) {
                            runCatching { ApiController.disconnectP2p() }
                            var ok = false
                            for (url in urls) {
                                ApiController.setBaseUrl(url)
                                val status = AuthApiService.checkServerStatus(url, timeoutSeconds = 5)
                                if (status.success && status.isNasCabServer) {
                                    ok = true
                                    break
                                }
                            }
                            ok
                        }
                    if (!ok) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_network_failed))
                        restore()
                        return false
                    }
                    true
                }

                ApiController.DevConnectMode.P2pDirect -> {
                    val code = server.pairCode.trim()
                    if (code.isEmpty()) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_no_pair_code))
                        restore()
                        return false
                    }
                    val (status, error) =
                        withContext(Dispatchers.IO) {
                            try {
                                ApiController.connectP2pByPairCode(code, icePreference = P2pIcePreference.DirectOnly)
                                val status = AuthApiService.checkServerStatus(ApiConfig.p2pBaseUrl, timeoutSeconds = 5)
                                status to null
                            } catch (e: Throwable) {
                                null to e
                            }
                        }
                    if (error != null) {
                        if (isAdded) {
                            val msg = when (ApiController.formatP2pConnectError(error)) {
                                "pair_server_unreachable" -> getString(R.string.error_server_unreachable)
                                "pair_code_invalid" -> getString(R.string.error_server_unreachable)
                                else -> getString(R.string.error_network_failed)
                            }
                            (activity as? AppHostActivity)?.showError(msg)
                        }
                        withContext(Dispatchers.IO) { runCatching { ApiController.disconnectP2p() } }
                        restore()
                        return false
                    }
                    if (status == null || !status.success || !status.isNasCabServer) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_network_failed))
                        withContext(Dispatchers.IO) { runCatching { ApiController.disconnectP2p() } }
                        restore()
                        return false
                    }
                    true
                }

                ApiController.DevConnectMode.P2pRelay -> {
                    val code = server.pairCode.trim()
                    if (code.isEmpty()) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_no_pair_code))
                        restore()
                        return false
                    }
                    val (status, error) =
                        withContext(Dispatchers.IO) {
                            try {
                                ApiController.connectP2pByPairCode(code, icePreference = P2pIcePreference.RelayOnly)
                                val status = AuthApiService.checkServerStatus(ApiConfig.p2pBaseUrl, timeoutSeconds = 5)
                                status to null
                            } catch (e: Throwable) {
                                null to e
                            }
                        }
                    if (error != null) {
                        if (isAdded) {
                            val msg = when (ApiController.formatP2pConnectError(error)) {
                                "pair_server_unreachable" -> getString(R.string.error_server_unreachable)
                                "pair_code_invalid" -> getString(R.string.error_server_unreachable)
                                else -> getString(R.string.error_network_failed)
                            }
                            (activity as? AppHostActivity)?.showError(msg)
                        }
                        withContext(Dispatchers.IO) { runCatching { ApiController.disconnectP2p() } }
                        restore()
                        return false
                    }
                    if (status == null || !status.success || !status.isNasCabServer) {
                        if (isAdded) (activity as? AppHostActivity)?.showError(getString(R.string.error_network_failed))
                        withContext(Dispatchers.IO) { runCatching { ApiController.disconnectP2p() } }
                        restore()
                        return false
                    }
                    true
                }

                ApiController.DevConnectMode.Auto -> true
            }
        }

        companion object {
            private const val ARG_SERVER_JSON = "server_json"
            private const val CHECK_SET_ID = 10

            private const val ID_MODE_DIRECT = 1L
            private const val ID_MODE_P2P_DIRECT = 2L
            private const val ID_MODE_P2P_RELAY = 3L
            private const val ID_MODE_AUTO = 4L

            fun newInstance(server: ServerInfo): DevNetworkChannelGuidedFragment {
                return DevNetworkChannelGuidedFragment().apply {
                    arguments = Bundle().apply {
                        putString(ARG_SERVER_JSON, Gson().toJson(server))
                    }
                }
            }
        }
    }
}
