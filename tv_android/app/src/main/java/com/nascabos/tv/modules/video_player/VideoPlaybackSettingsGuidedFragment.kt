package com.nascabos.tv.modules.video_player

import android.os.Bundle
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoPlaybackSettingsGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.home_video_playback_settings),
            getString(R.string.video_playback_default_quality_desc),
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += buildDefaultQualityAction()
    }

    override fun onResume() {
        super.onResume()
        refreshDefaultQualityAction()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        if (action.id == ID_DEFAULT_QUALITY) {
            add(requireActivity().supportFragmentManager, VideoDefaultQualityGuidedFragment())
        }
    }

    private fun buildDefaultQualityAction(): GuidedAction {
        val current = VideoPlaybackSettingsStore.getDefaultQuality(requireContext())
        return GuidedAction.Builder(requireContext())
            .id(ID_DEFAULT_QUALITY)
            .title(getString(R.string.video_playback_default_quality))
            .description(VideoPlaybackSettingsStore.qualityLabel(requireContext(), current))
            .build()
    }

    internal fun refreshDefaultQualityAction() {
        if (!isAdded) return
        val action = findActionById(ID_DEFAULT_QUALITY) ?: return
        val label = VideoPlaybackSettingsStore.qualityLabel(
            requireContext(),
            VideoPlaybackSettingsStore.getDefaultQuality(requireContext()),
        )
        if (action.description?.toString() == label) return
        action.description = label
        val pos = findActionPositionById(ID_DEFAULT_QUALITY)
        if (pos >= 0) notifyActionChanged(pos)
    }

    companion object {
        private const val ID_DEFAULT_QUALITY = 1L
    }
}

class VideoDefaultQualityGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.video_playback_default_quality),
            getString(R.string.video_playback_default_quality_desc),
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        val ctx = requireContext()
        val selected = VideoPlaybackSettingsStore.getDefaultQuality(ctx)
        VideoPlaybackSettingsStore.QUALITY_OPTIONS.forEachIndexed { index, quality ->
            actions +=
                GuidedAction.Builder(ctx)
                    .id(QUALITY_ACTION_ID_BASE + index)
                    .title(VideoPlaybackSettingsStore.qualityLabel(ctx, quality))
                    .checkSetId(CHECK_SET_ID)
                    .checked(quality == selected)
                    .build()
        }
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        val index = (action.id - QUALITY_ACTION_ID_BASE).toInt()
        val quality = VideoPlaybackSettingsStore.QUALITY_OPTIONS.getOrNull(index) ?: return
        VideoPlaybackSettingsStore.setDefaultQuality(requireContext(), quality)
        findParentSettingsFragment()?.refreshDefaultQualityAction()
        requireActivity().supportFragmentManager.popBackStack()
    }

    private fun findParentSettingsFragment(): VideoPlaybackSettingsGuidedFragment? {
        return parentFragment as? VideoPlaybackSettingsGuidedFragment
            ?: requireActivity().supportFragmentManager.fragments
                .firstOrNull { it is VideoPlaybackSettingsGuidedFragment } as? VideoPlaybackSettingsGuidedFragment
    }

    companion object {
        private const val QUALITY_ACTION_ID_BASE = 100L
        private const val CHECK_SET_ID = 20
    }
}
