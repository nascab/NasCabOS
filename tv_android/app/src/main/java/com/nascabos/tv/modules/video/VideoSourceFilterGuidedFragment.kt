package com.nascabos.tv.modules.video

import android.os.Bundle
import androidx.core.os.bundleOf
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoSourceFilterGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private var availablePaths: List<String> = emptyList()
    private var selected: MutableSet<String> = mutableSetOf()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        availablePaths = arguments?.getStringArrayList(ARG_AVAILABLE_PATHS)?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
        selected = (arguments?.getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf()).map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet()
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.video_list_action_sources),
            getString(R.string.video_list_sources_hint),
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += GuidedAction.Builder(requireContext())
            .id(ID_SELECT_ALL)
            .title(getString(R.string.video_list_sources_all))
            .build()

        availablePaths.forEachIndexed { idx, p ->
            val title = displayName(p)
            actions += GuidedAction.Builder(requireContext())
                .id(ID_PATH_BASE + idx)
                .title(title)
                .description(p)
                .checkSetId(GuidedAction.CHECKBOX_CHECK_SET_ID)
                .checked(selected.contains(p))
                .build()
        }

        actions += GuidedAction.Builder(requireContext())
            .id(ID_APPLY)
            .title(getString(R.string.video_list_action_apply))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_CANCEL)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when {
            action.id == ID_SELECT_ALL -> {
                selected.clear()
                refreshCheckStates()
            }
            action.id == ID_APPLY -> {
                parentFragmentManager.setFragmentResult(
                    VideoGridFragment.RESULT_KEY_SOURCES,
                    bundleOf(VideoGridFragment.RESULT_FIELD_SOURCES to ArrayList(selected.toList())),
                )
                requireActivity().supportFragmentManager.popBackStack()
            }
            action.id == ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
            action.id >= ID_PATH_BASE -> {
                val idx = (action.id - ID_PATH_BASE).toInt()
                val p = availablePaths.getOrNull(idx) ?: return
                if (selected.contains(p)) selected.remove(p) else selected.add(p)
                action.isChecked = selected.contains(p)
                val pos = findActionPositionById(action.id)
                if (pos >= 0) notifyActionChanged(pos)
            }
        }
    }

    private fun refreshCheckStates() {
        val actions = actions
        for (i in actions.indices) {
            val a = actions[i]
            if (a.id < ID_PATH_BASE) continue
            val idx = (a.id - ID_PATH_BASE).toInt()
            val p = availablePaths.getOrNull(idx) ?: continue
            val checked = selected.contains(p)
            if (a.isChecked != checked) {
                a.isChecked = checked
                notifyActionChanged(i)
            }
        }
    }

    private fun displayName(path: String): String {
        val s = path.trim().trimEnd('/', '\\')
        val i1 = s.lastIndexOf('/')
        val i2 = s.lastIndexOf('\\')
        val i = maxOf(i1, i2)
        val name = if (i >= 0) s.substring(i + 1) else s
        return name.ifEmpty { s }
    }

    companion object {
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        private const val ID_SELECT_ALL = 1L
        private const val ID_APPLY = 2L
        private const val ID_CANCEL = 3L
        private const val ID_PATH_BASE = 1000L

        fun newInstance(availablePaths: ArrayList<String>, selectedPaths: ArrayList<String>): VideoSourceFilterGuidedFragment {
            return VideoSourceFilterGuidedFragment().apply {
                arguments =
                    bundleOf(
                        ARG_AVAILABLE_PATHS to availablePaths,
                        ARG_SELECTED_PATHS to selectedPaths,
                    )
            }
        }
    }
}

