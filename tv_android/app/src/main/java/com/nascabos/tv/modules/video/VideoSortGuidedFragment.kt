package com.nascabos.tv.modules.video

import android.os.Bundle
import androidx.core.os.bundleOf
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoSortGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private var currentBy: VideoListSortBy = VideoListSortBy.ViewTime
    private var currentOrder: VideoListSortOrder = VideoListSortOrder.Desc
    private var listType: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val byRaw = arguments?.getString(ARG_SORT_BY)?.trim().orEmpty()
        val orderRaw = arguments?.getString(ARG_SORT_ORDER)?.trim().orEmpty()
        listType = arguments?.getString(ARG_LIST_TYPE)?.trim().orEmpty()
        currentBy = runCatching { VideoListSortBy.valueOf(byRaw) }.getOrNull() ?: VideoListSortBy.ViewTime
        currentOrder = runCatching { VideoListSortOrder.valueOf(orderRaw) }.getOrNull() ?: VideoListSortOrder.Desc
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.video_list_action_sort),
            null,
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        val entries = sortEntries()
        entries.forEachIndexed { idx, e ->
            actions += GuidedAction.Builder(requireContext())
                .id(ID_BASE + idx)
                .title(getString(e.labelRes))
                .checkSetId(CHECK_SET_ID)
                .checked(e.by == currentBy && e.order == currentOrder)
                .build()
        }
        actions += GuidedAction.Builder(requireContext())
            .id(ID_CANCEL)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        if (action.id == ID_CANCEL) {
            requireActivity().supportFragmentManager.popBackStack()
            return
        }
        val idx = (action.id - ID_BASE).toInt()
        val entries = sortEntries()
        val e = entries.getOrNull(idx) ?: return
        parentFragmentManager.setFragmentResult(
            VideoGridFragment.RESULT_KEY_SORT,
            bundleOf(
                VideoGridFragment.RESULT_FIELD_SORT_BY to e.by.name,
                VideoGridFragment.RESULT_FIELD_SORT_ORDER to e.order.name,
            ),
        )
        requireActivity().supportFragmentManager.popBackStack()
    }

    private data class SortEntry(
        val by: VideoListSortBy,
        val order: VideoListSortOrder,
        val labelRes: Int,
    )

    private fun sortEntries(): List<SortEntry> {
        val createTimeResDesc =
            if (listType.trim().lowercase() == "favorite") {
                R.string.video_list_sort_favorite_time_desc
            } else {
                R.string.video_list_sort_create_time_desc
            }
        val createTimeResAsc =
            if (listType.trim().lowercase() == "favorite") {
                R.string.video_list_sort_favorite_time_asc
            } else {
                R.string.video_list_sort_create_time_asc
            }
        return listOf(
            SortEntry(VideoListSortBy.ViewTime, VideoListSortOrder.Desc, R.string.video_list_sort_view_time_desc),
            SortEntry(VideoListSortBy.ViewTime, VideoListSortOrder.Asc, R.string.video_list_sort_view_time_asc),
            SortEntry(VideoListSortBy.CreateTime, VideoListSortOrder.Desc, createTimeResDesc),
            SortEntry(VideoListSortBy.CreateTime, VideoListSortOrder.Asc, createTimeResAsc),
            SortEntry(VideoListSortBy.Year, VideoListSortOrder.Desc, R.string.video_list_sort_year_desc),
            SortEntry(VideoListSortBy.Year, VideoListSortOrder.Asc, R.string.video_list_sort_year_asc),
            SortEntry(VideoListSortBy.Score, VideoListSortOrder.Desc, R.string.video_list_sort_score_desc),
            SortEntry(VideoListSortBy.Score, VideoListSortOrder.Asc, R.string.video_list_sort_score_asc),
            SortEntry(VideoListSortBy.Name, VideoListSortOrder.Asc, R.string.video_list_sort_name_asc),
            SortEntry(VideoListSortBy.Name, VideoListSortOrder.Desc, R.string.video_list_sort_name_desc),
        )
    }

    companion object {
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_LIST_TYPE = "list_type"

        private const val CHECK_SET_ID = 10
        private const val ID_BASE = 100L
        private const val ID_CANCEL = 2L

        fun newInstance(currentSortBy: String, currentSortOrder: String, listType: String = ""): VideoSortGuidedFragment {
            return VideoSortGuidedFragment().apply {
                arguments =
                    bundleOf(
                        ARG_SORT_BY to currentSortBy,
                        ARG_SORT_ORDER to currentSortOrder,
                        ARG_LIST_TYPE to listType,
                    )
            }
        }
    }
}
