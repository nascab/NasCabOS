package com.nascabos.tv.modules.video

import android.os.Bundle
import android.text.InputType
import androidx.core.os.bundleOf
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoSearchGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private var query: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        query = arguments?.getString(ARG_QUERY)?.trim().orEmpty()
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.video_list_action_search),
            getString(R.string.video_list_search_hint),
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions +=
            GuidedAction.Builder(requireContext())
                .id(ID_QUERY)
                .title(getString(R.string.video_list_search_field))
                .description(query)
                .editable(true)
                .editDescription(query)
                .descriptionInputType(InputType.TYPE_CLASS_TEXT)
                .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_APPLY)
            .title(getString(R.string.video_list_action_apply))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_CLEAR)
            .title(getString(R.string.video_list_action_clear_search))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_CANCEL)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionEdited(action: GuidedAction) {
        if (action.id != ID_QUERY) return
        query = action.editDescription?.toString().orEmpty()
        action.description = query
        action.editDescription = query
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_APPLY -> {
                parentFragmentManager.setFragmentResult(
                    VideoGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to query.trim()),
                )
                requireActivity().supportFragmentManager.popBackStack()
            }
            ID_CLEAR -> {
                parentFragmentManager.setFragmentResult(
                    VideoGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to ""),
                )
                requireActivity().supportFragmentManager.popBackStack()
            }
            ID_CANCEL -> requireActivity().supportFragmentManager.popBackStack()
        }
    }

    companion object {
        private const val ARG_QUERY = "query"

        private const val ID_QUERY = 1L
        private const val ID_APPLY = 2L
        private const val ID_CLEAR = 3L
        private const val ID_CANCEL = 4L

        fun newInstance(currentSearch: String): VideoSearchGuidedFragment {
            return VideoSearchGuidedFragment().apply {
                arguments = bundleOf(ARG_QUERY to currentSearch)
            }
        }
    }
}

