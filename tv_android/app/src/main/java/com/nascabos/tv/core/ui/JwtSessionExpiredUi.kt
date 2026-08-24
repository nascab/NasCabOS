package com.nascabos.tv.core.ui

import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.FragmentManager
import androidx.fragment.app.commit
import com.nascabos.tv.FeatureHostActivity
import com.nascabos.tv.MainActivity
import com.nascabos.tv.R
import com.nascabos.tv.core.api.ApiController
import com.nascabos.tv.modules.photo.timeline.PhotoPreviewActivity
import com.nascabos.tv.modules.serverlist.ServerBrowseFragment
import com.nascabos.tv.modules.video.detail.VideoDetailActivity
import com.nascabos.tv.modules.video_player.TvVideoPlayerActivity

/**
 * 与 Flutter BaseApiService._showTokenExpiredDialogAndNavigate 对齐：当前顶层 Activity 负责弹窗与导航。
 * 在 [AppCompatActivity.onResume] 调用 [attachResumedActivity]，在 [AppCompatActivity.onDestroy] 调用 [detachIfSame]。
 */
object JwtSessionExpiredUi {
    private var resumed: AppCompatActivity? = null

    fun attachResumedActivity(activity: AppCompatActivity) {
        resumed = activity
        ApiController.onJwtSessionExpired = sessionExpired@{
            val act = resumed ?: return@sessionExpired
            if (act.isFinishing) return@sessionExpired
            act.runOnUiThread { showSessionExpiredDialog(act) }
        }
    }

    fun detachIfSame(activity: AppCompatActivity) {
        if (resumed === activity) {
            resumed = null
            ApiController.onJwtSessionExpired = null
        }
    }

    private fun showSessionExpiredDialog(activity: AppCompatActivity) {
        AlertDialog.Builder(activity, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(activity.getString(R.string.error_title))
            .setMessage(activity.getString(R.string.service_nascab_session_expired))
            .setCancelable(false)
            .setPositiveButton(activity.getString(R.string.action_ok)) { _, _ ->
                ApiController.setTokens("", "")
                when (activity) {
                    is MainActivity -> {
                        activity.supportFragmentManager.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
                        activity.supportFragmentManager.commit {
                            replace(R.id.main_container, ServerBrowseFragment.newInstance())
                        }
                    }
                    is FeatureHostActivity,
                    is TvVideoPlayerActivity,
                    is VideoDetailActivity,
                    is PhotoPreviewActivity,
                    -> activity.finish()
                    else -> Unit
                }
            }
            .show()
    }
}
