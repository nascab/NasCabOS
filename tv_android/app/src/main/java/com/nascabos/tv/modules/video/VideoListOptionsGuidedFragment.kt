package com.nascabos.tv.modules.video

import android.os.Bundle
import androidx.core.os.bundleOf
import androidx.fragment.app.commit
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoListOptionsGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private val mediaType: String by lazy { requireArguments().getString(ARG_MEDIA_TYPE).orEmpty() }
    private val currentSearch: String by lazy { requireArguments().getString(ARG_CURRENT_SEARCH).orEmpty() }
    private val sortBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        val title = getString(R.string.video_list_options_title)
        val desc = buildDescription()
        return GuidanceStylist.Guidance(title, desc, getString(R.string.app_display_name), null)
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += GuidedAction.Builder(requireContext())
            .id(ID_SEARCH)
            .title(getString(R.string.video_list_action_search))
            .description(currentSearch.ifEmpty { getString(R.string.video_list_search_empty) })
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_SORT)
            .title(getString(R.string.video_list_action_sort))
            .build()

        actions += GuidedAction.Builder(requireContext())
            .id(ID_SOURCES)
            .title(getString(R.string.video_list_action_sources))
            .description(
                if (selectedPaths.isEmpty()) {
                    getString(R.string.video_list_sources_all)
                } else {
                    getString(R.string.video_list_sources_selected_count, selectedPaths.size)
                },
            )
            .build()

        if (currentSearch.isNotBlank() || selectedPaths.isNotEmpty()) {
            actions += GuidedAction.Builder(requireContext())
                .id(ID_CLEAR_FILTERS)
                .title(getString(R.string.video_list_action_clear_filters))
                .build()
        }

        actions += GuidedAction.Builder(requireContext())
            .id(ID_CLOSE)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_SEARCH -> openSearch()
            ID_SORT -> openSort()
            ID_SOURCES -> openSources()
            ID_CLEAR_FILTERS -> clearFiltersAndClose()
            ID_CLOSE -> requireActivity().supportFragmentManager.popBackStack()
        }
    }

    private fun openSearch() {
        val activity = activity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(
                R.id.main_container,
                VideoSearchGuidedFragment.newInstance(
                    currentSearch = currentSearch,
                ),
            )
            addToBackStack(null)
        }
    }

    private fun openSort() {
        val activity = activity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(
                R.id.main_container,
                VideoSortGuidedFragment.newInstance(
                    currentSortBy = sortBy,
                    currentSortOrder = sortOrder,
                ),
            )
            addToBackStack(null)
        }
    }

    private fun openSources() {
        val activity = activity ?: return
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(
                R.id.main_container,
                VideoSourceFilterGuidedFragment.newInstance(
                    availablePaths = availablePaths,
                    selectedPaths = selectedPaths,
                ),
            )
            addToBackStack(null)
        }
    }

    private fun clearFiltersAndClose() {
        parentFragmentManager.setFragmentResult(VideoGridFragment.RESULT_KEY_SEARCH, bundleOf(VideoGridFragment.RESULT_FIELD_QUERY to ""))
        parentFragmentManager.setFragmentResult(VideoGridFragment.RESULT_KEY_SOURCES, bundleOf(VideoGridFragment.RESULT_FIELD_SOURCES to arrayListOf<String>()))
        requireActivity().supportFragmentManager.popBackStack()
    }

    private fun buildDescription(): String? {
        val mt = mediaType.trim().lowercase()
        val typeLabel =
            when (mt) {
                "tv" -> getString(R.string.home_video_tv_series)
                else -> getString(R.string.home_video_movies)
            }
        return typeLabel
    }

    companion object {
        private const val ARG_MEDIA_TYPE = "media_type"
        private const val ARG_CURRENT_SEARCH = "current_search"
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        private const val ID_SEARCH = 1L
        private const val ID_SORT = 2L
        private const val ID_SOURCES = 3L
        private const val ID_CLEAR_FILTERS = 4L
        private const val ID_CLOSE = 5L

        fun newInstance(
            mediaType: String,
            currentSearch: String,
            sortBy: String,
            sortOrder: String,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
        ): VideoListOptionsGuidedFragment {
            return VideoListOptionsGuidedFragment().apply {
                arguments =
                    bundleOf(
                        ARG_MEDIA_TYPE to mediaType,
                        ARG_CURRENT_SEARCH to currentSearch,
                        ARG_SORT_BY to sortBy,
                        ARG_SORT_ORDER to sortOrder,
                        ARG_AVAILABLE_PATHS to availablePaths,
                        ARG_SELECTED_PATHS to selectedPaths,
                    )
            }
        }
    }
}

