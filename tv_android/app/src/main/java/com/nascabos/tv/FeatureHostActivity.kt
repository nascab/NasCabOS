package com.nascabos.tv

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.commit
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.nascabos.tv.core.api.ApiConfig
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.core.api.p2p.P2pIcePreference
import com.nascabos.tv.core.i18n.LocaleManager
import com.nascabos.tv.core.ui.JwtSessionExpiredUi
import com.nascabos.tv.data.storage.ServerStore
import com.nascabos.tv.modules.music.MusicGroupGridFragment
import com.nascabos.tv.modules.music.MusicPlaylistGridFragment
import com.nascabos.tv.modules.music.MusicTrackGridFragment
import com.nascabos.tv.modules.photo.library.PhotoLibraryGridFragment
import com.nascabos.tv.modules.photo.timeline.PhotoTimelineBrowseFragment
import com.nascabos.tv.modules.video.VideoGridFragment
import com.nascabos.tv.modules.video.VideoLibraryGridFragment
import com.nascabos.tv.R
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * 承载从首页进入的子功能 Fragment。独立 Activity 生命周期，返回时直接 finish，
 * 主界面 MainActivity 及其首页视图与焦点得以保留。
 */
class FeatureHostActivity : AppCompatActivity(), AppHostActivity {

    private var loadingOverlay: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocaleManager.init(applicationContext)
        LocaleManager.restoreSavedLanguage()
        ApiController.init(applicationContext)
        setContentView(R.layout.activity_feature_host)
        loadingOverlay = findViewById(R.id.global_loading_overlay)
        lifecycleScope.launch { restoreLastSelectedConnectionIfNeeded() }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finish()
            }
        })

        val className = intent.getStringExtra(EXTRA_FRAGMENT_CLASS)
        val args = intent.getBundleExtra(EXTRA_FRAGMENT_ARGS)

        if (className.isNullOrEmpty()) {
            finish()
            return
        }

        val fragment = supportFragmentManager.fragmentFactory.instantiate(classLoader, className)
        fragment.arguments = args

        supportFragmentManager.commit {
            replace(R.id.main_container, fragment)
        }
    }

    override fun onResume() {
        super.onResume()
        JwtSessionExpiredUi.attachResumedActivity(this)
    }

    override fun onDestroy() {
        JwtSessionExpiredUi.detachIfSame(this)
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_UP) {
            val code = event.keyCode
            if (code == KeyEvent.KEYCODE_MENU || code == KeyEvent.KEYCODE_SETTINGS) {
                val current = supportFragmentManager.findFragmentById(R.id.main_container)
                when (current) {
                    is VideoGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is VideoLibraryGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is PhotoTimelineBrowseFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is PhotoLibraryGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is MusicTrackGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is MusicGroupGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                    is MusicPlaylistGridFragment -> {
                        current.openOptionsFromActivity()
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun setLoadingVisible(visible: Boolean) {
        loadingOverlay?.visibility = if (visible) View.VISIBLE else View.GONE
    }

    override fun showError(message: String) {
        if (isFinishing) return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.error_title))
            .setMessage(message)
            .setPositiveButton(getString(R.string.action_ok), null)
            .show()
    }

    private suspend fun restoreLastSelectedConnectionIfNeeded() {
        if (ApiController.baseUrl.trim().isNotEmpty()) return
        val store = ServerStore(applicationContext, Gson())
        val last = runCatching { store.lastSelectedFlow.first() }.getOrNull() ?: return
        ApiController.setTokens(
            last.accessToken,
            last.refreshToken,
            last.accessTokenExpiresAtEpochSec.takeIf { it > 0L },
            last.serverVersion.trim().takeIf { it.isNotEmpty() },
        )

        val direct = last.serverUrl.trim()
        if (direct.isNotEmpty()) {
            ApiController.setBaseUrl(direct)
            return
        }

        val code = last.pairCode.trim()
        if (code.isEmpty()) return
        val pref =
            when (ApiController.getDevConnectMode()) {
                ApiController.DevConnectMode.P2pDirect -> P2pIcePreference.DirectOnly
                ApiController.DevConnectMode.P2pRelay -> P2pIcePreference.RelayOnly
                else -> P2pIcePreference.Auto
            }
        runCatching { ApiController.connectP2pByPairCode(code, icePreference = pref) }
        if (ApiController.baseUrl.trim().isEmpty()) {
            ApiController.setBaseUrl(ApiConfig.p2pBaseUrl)
        }
    }

    companion object {
        private const val EXTRA_FRAGMENT_CLASS = "feature_fragment_class"
        private const val EXTRA_FRAGMENT_ARGS = "feature_fragment_args"

        fun createIntent(context: Context, fragmentClass: String, fragmentArgs: Bundle?): Intent {
            return Intent(context, FeatureHostActivity::class.java).apply {
                putExtra(EXTRA_FRAGMENT_CLASS, fragmentClass)
                putExtra(EXTRA_FRAGMENT_ARGS, fragmentArgs)
            }
        }
    }
}
