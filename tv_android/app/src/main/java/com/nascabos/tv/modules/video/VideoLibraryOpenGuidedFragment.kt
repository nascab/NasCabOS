package com.nascabos.tv.modules.video

import android.os.Bundle
import androidx.core.os.bundleOf
import androidx.fragment.app.commit
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R

class VideoLibraryOpenGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    private val kind: VideoLibraryKind by lazy {
        val raw = requireArguments().getString(ARG_KIND).orEmpty()
        runCatching { VideoLibraryKind.valueOf(raw) }.getOrNull() ?: VideoLibraryKind.Album
    }
    private val libraryId: Int by lazy { requireArguments().getInt(ARG_ID) }
    private val titleText: String by lazy { requireArguments().getString(ARG_TITLE).orEmpty() }
    private val titleWithPrefix: String by lazy {
        val prefix =
            when (kind) {
                VideoLibraryKind.Album -> getString(R.string.video_library_prefix_album)
                VideoLibraryKind.SmartAlbum -> getString(R.string.video_library_prefix_smart_album)
                VideoLibraryKind.Collection -> getString(R.string.video_library_prefix_collection)
            }.trim()
        val name = titleText.trim()
        if (name.isNotEmpty()) "${prefix}-${name}" else prefix
    }

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.video_library_open_title),
            titleWithPrefix,
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        actions += GuidedAction.Builder(requireContext())
            .id(ID_MOVIES)
            .title(getString(R.string.home_video_movies))
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_TV)
            .title(getString(R.string.home_video_tv_series))
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_CLOSE)
            .title(getString(R.string.action_cancel))
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_MOVIES -> openList(mediaType = "movie")
            ID_TV -> openList(mediaType = "tv")
            ID_CLOSE -> requireActivity().supportFragmentManager.popBackStack()
        }
    }

    private fun openList(mediaType: String) {
        val activity = activity ?: return
        val aid = if (kind == VideoLibraryKind.Album) libraryId else null
        val cid = if (kind == VideoLibraryKind.Collection) libraryId else null
        val sid = if (kind == VideoLibraryKind.SmartAlbum) libraryId else null
        activity.supportFragmentManager.commit {
            setReorderingAllowed(true)
            replace(
                R.id.main_container,
                VideoGridFragment.newInstance(
                    mediaType = mediaType,
                    title = titleWithPrefix,
                    albumId = aid,
                    collectionId = cid,
                    smartAlbumId = sid,
                ),
            )
            addToBackStack(null)
        }
    }

    companion object {
        private const val ARG_KIND = "kind"
        private const val ARG_ID = "id"
        private const val ARG_TITLE = "title"

        private const val ID_MOVIES = 1L
        private const val ID_TV = 2L
        private const val ID_CLOSE = 3L

        fun newInstance(kind: String, id: Int, title: String): VideoLibraryOpenGuidedFragment {
            return VideoLibraryOpenGuidedFragment().apply {
                arguments = bundleOf(ARG_KIND to kind, ARG_ID to id, ARG_TITLE to title)
            }
        }
    }
}
