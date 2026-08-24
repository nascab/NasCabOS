package com.nascabos.tv.modules.video.detail

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.commit
import com.nascabos.tv.AppHostActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.i18n.LocaleManager
import com.nascabos.tv.core.ui.JwtSessionExpiredUi

/**
 * 独立 Activity 承载视频详情页。从影音列表进入详情后按返回键回到列表页，而不是应用首页。
 */
class VideoDetailActivity : AppCompatActivity(), AppHostActivity {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LocaleManager.init(applicationContext)
        LocaleManager.restoreSavedLanguage()
        setContentView(R.layout.activity_feature_host)

        val indexId = intent.getIntExtra(EXTRA_INDEX_ID, 0)
        if (indexId <= 0) {
            finish()
            return
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (supportFragmentManager.backStackEntryCount > 0) {
                    supportFragmentManager.popBackStack()
                } else {
                    finish()
                }
            }
        })

        if (supportFragmentManager.findFragmentById(R.id.main_container) == null) {
            supportFragmentManager.commit {
                replace(R.id.main_container, VideoDetailFragment.newInstance(indexId))
            }
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

    override fun setLoadingVisible(visible: Boolean) {
        findViewById<View>(R.id.global_loading_overlay)?.visibility =
            if (visible) View.VISIBLE else View.GONE
    }

    override fun showError(message: String) {
        if (isFinishing) return
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.error_title))
            .setMessage(message)
            .setPositiveButton(getString(R.string.action_ok), null)
            .show()
    }

    companion object {
        private const val EXTRA_INDEX_ID = "index_id"

        fun createIntent(context: Context, indexId: Int): Intent {
            return Intent(context, VideoDetailActivity::class.java).apply {
                putExtra(EXTRA_INDEX_ID, indexId)
            }
        }
    }
}
