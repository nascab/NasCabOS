package com.nascabos.tv.modules.music

import android.app.Dialog
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckedTextView
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.core.graphics.drawable.DrawableCompat
import androidx.core.os.bundleOf
import androidx.fragment.app.DialogFragment
import com.nascabos.tv.R

class MusicOptionsDialogFragment : DialogFragment() {
    private val currentSearch: String by lazy { requireArguments().getString(ARG_CURRENT_SEARCH).orEmpty() }
    private val sortBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(420f)
        val panel =
            FrameLayout(ctx).apply {
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val listView =
            ListView(ctx).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                dividerHeight = 0
                selector = resources.getDrawable(R.drawable.video_dialog_selector, ctx.theme)
            }
        panel.addView(listView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val rows = buildRows()
        val adapter =
            object : ArrayAdapter<Row>(ctx, android.R.layout.simple_list_item_2, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t1 = v.findViewById<TextView>(android.R.id.text1)
                    val t2 = v.findViewById<TextView>(android.R.id.text2)
                    val row = getItem(position)
                    t1.text = row?.title.orEmpty()
                    t2.text = row?.desc.orEmpty()
                    t2.visibility = if (row?.desc?.isNotBlank() == true) View.VISIBLE else View.GONE
                    t1.setTextColor(0xFFFFFFFF.toInt())
                    t2.setTextColor(0xB3FFFFFF.toInt())
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)
        listView.setOnItemClickListener { _, _, position, _ ->
            when (rows.getOrNull(position)?.id) {
                ID_SEARCH -> openSearchInput()
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    MusicTrackSortDialogFragment.newInstance(sortBy, sortOrder).show(parentFragmentManager, "music_sort")
                }
                ID_SOURCES -> {
                    dismissAllowingStateLoss()
                    MusicSourceDialogFragment
                        .newInstance(
                            titleRes = R.string.music_list_action_sources,
                            availablePaths = availablePaths,
                            selectedPaths = selectedPaths,
                            resultKey = MusicTrackGridFragment.RESULT_KEY_SOURCES,
                            resultField = MusicTrackGridFragment.RESULT_FIELD_SOURCES,
                        )
                        .show(parentFragmentManager, "music_sources")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(MusicTrackGridFragment.RESULT_KEY_SEARCH, bundleOf(MusicTrackGridFragment.RESULT_FIELD_QUERY to ""))
                    parentFragmentManager.setFragmentResult(
                        MusicTrackGridFragment.RESULT_KEY_SOURCES,
                        bundleOf(MusicTrackGridFragment.RESULT_FIELD_SOURCES to arrayListOf<String>()),
                    )
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun openSearchInput() {
        val ctx = requireContext()
        val input =
            EditText(ctx).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setText(currentSearch)
                setSelection(text?.length ?: 0)
                setTextColor(0xFFFFFFFF.toInt())
                setHintTextColor(0x99FFFFFF.toInt())
                setBackgroundColor(0xFF2A2A2A.toInt())
                setPadding(dpToPx(12f), dpToPx(10f), dpToPx(12f), dpToPx(10f))
            }
        AlertDialog.Builder(ctx, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.music_list_action_search))
            .setView(input)
            .setPositiveButton(getString(R.string.music_list_action_apply)) { _, _ ->
                val q = input.text?.toString()?.trim().orEmpty()
                parentFragmentManager.setFragmentResult(
                    MusicTrackGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicTrackGridFragment.RESULT_FIELD_QUERY to q),
                )
                dismissAllowingStateLoss()
            }
            .setNeutralButton(getString(R.string.music_list_action_clear_search)) { _, _ ->
                parentFragmentManager.setFragmentResult(
                    MusicTrackGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicTrackGridFragment.RESULT_FIELD_QUERY to ""),
                )
                dismissAllowingStateLoss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun buildRows(): List<Row> {
        val sortLabel = trackSortLabel(sortBy, sortOrder)
        val sourcesLabel =
            if (selectedPaths.isEmpty()) {
                getString(R.string.music_list_sources_all)
            } else {
                getString(R.string.music_list_sources_selected_count, selectedPaths.size)
            }
        val list = mutableListOf<Row>()
        list += Row(ID_SEARCH, getString(R.string.music_list_action_search), currentSearch.ifEmpty { getString(R.string.music_list_search_empty) })
        list += Row(ID_SORT, getString(R.string.music_list_action_sort), sortLabel)
        list += Row(ID_SOURCES, getString(R.string.music_list_action_sources), sourcesLabel)
        if (currentSearch.isNotBlank() || selectedPaths.isNotEmpty()) {
            list += Row(ID_CLEAR, getString(R.string.music_list_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun trackSortLabel(byRaw: String, orderRaw: String): String {
        val by = runCatching { MusicListSortBy.valueOf(byRaw) }.getOrNull() ?: MusicListSortBy.Filename
        val order = runCatching { MusicListSortOrder.valueOf(orderRaw) }.getOrNull() ?: MusicListSortOrder.Asc
        return when (by) {
            MusicListSortBy.Filename ->
                if (order == MusicListSortOrder.Asc) getString(R.string.music_sort_filename_asc) else getString(R.string.music_sort_filename_desc)
            MusicListSortBy.Title ->
                if (order == MusicListSortOrder.Asc) getString(R.string.music_sort_title_asc) else getString(R.string.music_sort_title_desc)
            MusicListSortBy.Artist ->
                if (order == MusicListSortOrder.Asc) getString(R.string.music_sort_artist_asc) else getString(R.string.music_sort_artist_desc)
            MusicListSortBy.Album ->
                if (order == MusicListSortOrder.Asc) getString(R.string.music_sort_album_asc) else getString(R.string.music_sort_album_desc)
            MusicListSortBy.Duration ->
                if (order == MusicListSortOrder.Asc) getString(R.string.music_sort_duration_asc) else getString(R.string.music_sort_duration_desc)
            MusicListSortBy.FavoriteTime ->
                if (order == MusicListSortOrder.Desc) getString(R.string.music_sort_favorite_time_desc) else getString(R.string.music_sort_favorite_time_asc)
            MusicListSortBy.Ctime ->
                if (order == MusicListSortOrder.Desc) getString(R.string.music_sort_create_time_desc) else getString(R.string.music_sort_create_time_asc)
            MusicListSortBy.Mtime ->
                if (order == MusicListSortOrder.Desc) getString(R.string.music_sort_modify_time_desc) else getString(R.string.music_sort_modify_time_asc)
            MusicListSortBy.Year ->
                if (order == MusicListSortOrder.Desc) getString(R.string.music_sort_year_desc) else getString(R.string.music_sort_year_asc)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_CURRENT_SEARCH = "current_search"
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        private const val ID_SEARCH = 1
        private const val ID_SORT = 2
        private const val ID_SOURCES = 3
        private const val ID_CLEAR = 4
        private const val ID_CLOSE = 5

        fun newInstance(
            currentSearch: String,
            sortBy: String,
            sortOrder: String,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
        ): MusicOptionsDialogFragment {
            return MusicOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
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

class MusicGroupOptionsDialogFragment : DialogFragment() {
    private val currentSearch: String by lazy { requireArguments().getString(ARG_CURRENT_SEARCH).orEmpty() }
    private val sortBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(420f)
        val panel =
            FrameLayout(ctx).apply {
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val listView =
            ListView(ctx).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                dividerHeight = 0
                selector = resources.getDrawable(R.drawable.video_dialog_selector, ctx.theme)
            }
        panel.addView(listView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val rows = buildRows()
        val adapter =
            object : ArrayAdapter<Row>(ctx, android.R.layout.simple_list_item_2, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t1 = v.findViewById<TextView>(android.R.id.text1)
                    val t2 = v.findViewById<TextView>(android.R.id.text2)
                    val row = getItem(position)
                    t1.text = row?.title.orEmpty()
                    t2.text = row?.desc.orEmpty()
                    t2.visibility = if (row?.desc?.isNotBlank() == true) View.VISIBLE else View.GONE
                    t1.setTextColor(0xFFFFFFFF.toInt())
                    t2.setTextColor(0xB3FFFFFF.toInt())
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)
        listView.setOnItemClickListener { _, _, position, _ ->
            when (rows.getOrNull(position)?.id) {
                ID_SEARCH -> openSearchInput()
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    MusicGroupSortDialogFragment.newInstance(sortBy, sortOrder).show(parentFragmentManager, "music_group_sort")
                }
                ID_SOURCES -> {
                    dismissAllowingStateLoss()
                    MusicSourceDialogFragment
                        .newInstance(
                            titleRes = R.string.music_list_action_sources,
                            availablePaths = availablePaths,
                            selectedPaths = selectedPaths,
                            resultKey = MusicGroupGridFragment.RESULT_KEY_SOURCES,
                            resultField = MusicGroupGridFragment.RESULT_FIELD_SOURCES,
                        )
                        .show(parentFragmentManager, "music_group_sources")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(MusicGroupGridFragment.RESULT_KEY_SEARCH, bundleOf(MusicGroupGridFragment.RESULT_FIELD_QUERY to ""))
                    parentFragmentManager.setFragmentResult(
                        MusicGroupGridFragment.RESULT_KEY_SOURCES,
                        bundleOf(MusicGroupGridFragment.RESULT_FIELD_SOURCES to arrayListOf<String>()),
                    )
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun openSearchInput() {
        val ctx = requireContext()
        val input =
            EditText(ctx).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setText(currentSearch)
                setSelection(text?.length ?: 0)
                setTextColor(0xFFFFFFFF.toInt())
                setHintTextColor(0x99FFFFFF.toInt())
                setBackgroundColor(0xFF2A2A2A.toInt())
                setPadding(dpToPx(12f), dpToPx(10f), dpToPx(12f), dpToPx(10f))
            }
        AlertDialog.Builder(ctx, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.music_list_action_search))
            .setView(input)
            .setPositiveButton(getString(R.string.music_list_action_apply)) { _, _ ->
                val q = input.text?.toString()?.trim().orEmpty()
                parentFragmentManager.setFragmentResult(
                    MusicGroupGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicGroupGridFragment.RESULT_FIELD_QUERY to q),
                )
                dismissAllowingStateLoss()
            }
            .setNeutralButton(getString(R.string.music_list_action_clear_search)) { _, _ ->
                parentFragmentManager.setFragmentResult(
                    MusicGroupGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicGroupGridFragment.RESULT_FIELD_QUERY to ""),
                )
                dismissAllowingStateLoss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun buildRows(): List<Row> {
        val sortLabel = groupSortLabel(sortBy, sortOrder)
        val sourcesLabel =
            if (selectedPaths.isEmpty()) {
                getString(R.string.music_list_sources_all)
            } else {
                getString(R.string.music_list_sources_selected_count, selectedPaths.size)
            }
        val list = mutableListOf<Row>()
        list += Row(ID_SEARCH, getString(R.string.music_list_action_search), currentSearch.ifEmpty { getString(R.string.music_list_search_empty) })
        list += Row(ID_SORT, getString(R.string.music_list_action_sort), sortLabel)
        list += Row(ID_SOURCES, getString(R.string.music_list_action_sources), sourcesLabel)
        if (currentSearch.isNotBlank() || selectedPaths.isNotEmpty()) {
            list += Row(ID_CLEAR, getString(R.string.music_list_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun groupSortLabel(byRaw: String, orderRaw: String): String {
        val by = runCatching { MusicGroupSortBy.valueOf(byRaw) }.getOrNull() ?: MusicGroupSortBy.Count
        val order = runCatching { MusicGroupSortOrder.valueOf(orderRaw) }.getOrNull() ?: MusicGroupSortOrder.Desc
        return when (by) {
            MusicGroupSortBy.Count ->
                if (order == MusicGroupSortOrder.Desc) getString(R.string.music_group_sort_count_desc) else getString(R.string.music_group_sort_count_asc)
            MusicGroupSortBy.Name ->
                if (order == MusicGroupSortOrder.Asc) getString(R.string.music_group_sort_name_asc) else getString(R.string.music_group_sort_name_desc)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_CURRENT_SEARCH = "current_search"
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"

        private const val ID_SEARCH = 1
        private const val ID_SORT = 2
        private const val ID_SOURCES = 3
        private const val ID_CLEAR = 4
        private const val ID_CLOSE = 5

        fun newInstance(
            currentSearch: String,
            sortBy: String,
            sortOrder: String,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
        ): MusicGroupOptionsDialogFragment {
            return MusicGroupOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
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

class MusicPlaylistOptionsDialogFragment : DialogFragment() {
    private val currentSearch: String by lazy { requireArguments().getString(ARG_CURRENT_SEARCH).orEmpty() }
    private val sortBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val sortOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(420f)
        val panel =
            FrameLayout(ctx).apply {
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val listView =
            ListView(ctx).apply {
                isFocusable = true
                isFocusableInTouchMode = true
                dividerHeight = 0
                selector = resources.getDrawable(R.drawable.video_dialog_selector, ctx.theme)
            }
        panel.addView(listView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val rows = buildRows()
        val adapter =
            object : ArrayAdapter<Row>(ctx, android.R.layout.simple_list_item_2, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t1 = v.findViewById<TextView>(android.R.id.text1)
                    val t2 = v.findViewById<TextView>(android.R.id.text2)
                    val row = getItem(position)
                    t1.text = row?.title.orEmpty()
                    t2.text = row?.desc.orEmpty()
                    t2.visibility = if (row?.desc?.isNotBlank() == true) View.VISIBLE else View.GONE
                    t1.setTextColor(0xFFFFFFFF.toInt())
                    t2.setTextColor(0xB3FFFFFF.toInt())
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)
        listView.setOnItemClickListener { _, _, position, _ ->
            when (rows.getOrNull(position)?.id) {
                ID_SEARCH -> openSearchInput()
                ID_SORT -> {
                    dismissAllowingStateLoss()
                    MusicPlaylistSortDialogFragment.newInstance(sortBy, sortOrder).show(parentFragmentManager, "music_playlist_sort")
                }
                ID_CLEAR -> {
                    parentFragmentManager.setFragmentResult(MusicPlaylistGridFragment.RESULT_KEY_SEARCH, bundleOf(MusicPlaylistGridFragment.RESULT_FIELD_QUERY to ""))
                    dismissAllowingStateLoss()
                }
                ID_CLOSE -> dismissAllowingStateLoss()
            }
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun openSearchInput() {
        val ctx = requireContext()
        val input =
            EditText(ctx).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                setText(currentSearch)
                setSelection(text?.length ?: 0)
                setTextColor(0xFFFFFFFF.toInt())
                setHintTextColor(0x99FFFFFF.toInt())
                setBackgroundColor(0xFF2A2A2A.toInt())
                setPadding(dpToPx(12f), dpToPx(10f), dpToPx(12f), dpToPx(10f))
            }
        AlertDialog.Builder(ctx, R.style.Theme_NasCabTv_AlertDialog)
            .setTitle(getString(R.string.music_list_action_search))
            .setView(input)
            .setPositiveButton(getString(R.string.music_list_action_apply)) { _, _ ->
                val q = input.text?.toString()?.trim().orEmpty()
                parentFragmentManager.setFragmentResult(
                    MusicPlaylistGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicPlaylistGridFragment.RESULT_FIELD_QUERY to q),
                )
                dismissAllowingStateLoss()
            }
            .setNeutralButton(getString(R.string.music_list_action_clear_search)) { _, _ ->
                parentFragmentManager.setFragmentResult(
                    MusicPlaylistGridFragment.RESULT_KEY_SEARCH,
                    bundleOf(MusicPlaylistGridFragment.RESULT_FIELD_QUERY to ""),
                )
                dismissAllowingStateLoss()
            }
            .setNegativeButton(getString(R.string.action_cancel), null)
            .show()
    }

    private fun buildRows(): List<Row> {
        val sortLabel = playlistSortLabel(sortBy, sortOrder)
        val list = mutableListOf<Row>()
        list += Row(ID_SEARCH, getString(R.string.music_list_action_search), currentSearch.ifEmpty { getString(R.string.music_list_search_empty) })
        list += Row(ID_SORT, getString(R.string.music_list_action_sort), sortLabel)
        if (currentSearch.isNotBlank()) {
            list += Row(ID_CLEAR, getString(R.string.music_list_action_clear_filters), "")
        }
        list += Row(ID_CLOSE, getString(R.string.action_cancel), "")
        return list
    }

    private fun playlistSortLabel(byRaw: String, orderRaw: String): String {
        val by = runCatching { MusicPlaylistSortBy.valueOf(byRaw) }.getOrNull() ?: MusicPlaylistSortBy.CreateTime
        val order = runCatching { MusicPlaylistSortOrder.valueOf(orderRaw) }.getOrNull() ?: MusicPlaylistSortOrder.Desc
        return when (by) {
            MusicPlaylistSortBy.CreateTime ->
                if (order == MusicPlaylistSortOrder.Desc) getString(R.string.music_playlist_sort_create_time_desc) else getString(R.string.music_playlist_sort_create_time_asc)
            MusicPlaylistSortBy.Name ->
                if (order == MusicPlaylistSortOrder.Asc) getString(R.string.music_playlist_sort_name_asc) else getString(R.string.music_playlist_sort_name_desc)
        }
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    private data class Row(val id: Int, val title: String, val desc: String)

    companion object {
        private const val ARG_CURRENT_SEARCH = "current_search"
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"

        private const val ID_SEARCH = 1
        private const val ID_SORT = 2
        private const val ID_CLEAR = 3
        private const val ID_CLOSE = 4

        fun newInstance(
            currentSearch: String,
            sortBy: String,
            sortOrder: String,
        ): MusicPlaylistOptionsDialogFragment {
            return MusicPlaylistOptionsDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_CURRENT_SEARCH to currentSearch,
                        ARG_SORT_BY to sortBy,
                        ARG_SORT_ORDER to sortOrder,
                    )
            }
        }
    }
}

class MusicTrackSortDialogFragment : DialogFragment() {
    private val currentBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val currentOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(460f)
        val panel =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val title =
            TextView(ctx).apply {
                text = getString(R.string.music_list_action_sort)
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 18f
                setPadding(dpToPx(18f), dpToPx(16f), dpToPx(18f), dpToPx(8f))
            }
        panel.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val listView =
            ListView(ctx).apply {
                choiceMode = ListView.CHOICE_MODE_SINGLE
                dividerHeight = 0
                selector = ctx.getDrawable(R.drawable.video_dialog_selector)
            }
        val listLp =
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0).apply {
                weight = 1f
            }
        panel.addView(listView, listLp)

        val options = buildTrackOptions()
        val currentKey = "${currentBy}_${currentOrder}".lowercase()
        val adapter =
            object : ArrayAdapter<SortOption>(ctx, android.R.layout.simple_list_item_single_choice, android.R.id.text1, options) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.setTextColor(0xFFFFFFFF.toInt())
                    if (t is CheckedTextView) {
                        val d = t.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            t.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)

        val idx = options.indexOfFirst { it.key.lowercase() == currentKey }
        if (idx >= 0) listView.setItemChecked(idx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val opt = options.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                MusicTrackGridFragment.RESULT_KEY_SORT,
                bundleOf(
                    MusicTrackGridFragment.RESULT_FIELD_SORT_BY to opt.by.name,
                    MusicTrackGridFragment.RESULT_FIELD_SORT_ORDER to opt.order.name,
                ),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class SortOption(
        val key: String,
        val label: String,
        val by: MusicListSortBy,
        val order: MusicListSortOrder,
    ) {
        override fun toString(): String = label
    }

    private fun buildTrackOptions(): List<SortOption> {
        return listOf(
            SortOption("Filename_Asc", getString(R.string.music_sort_filename_asc), MusicListSortBy.Filename, MusicListSortOrder.Asc),
            SortOption("Filename_Desc", getString(R.string.music_sort_filename_desc), MusicListSortBy.Filename, MusicListSortOrder.Desc),
            SortOption("Title_Asc", getString(R.string.music_sort_title_asc), MusicListSortBy.Title, MusicListSortOrder.Asc),
            SortOption("Title_Desc", getString(R.string.music_sort_title_desc), MusicListSortBy.Title, MusicListSortOrder.Desc),
            SortOption("Artist_Asc", getString(R.string.music_sort_artist_asc), MusicListSortBy.Artist, MusicListSortOrder.Asc),
            SortOption("Artist_Desc", getString(R.string.music_sort_artist_desc), MusicListSortBy.Artist, MusicListSortOrder.Desc),
            SortOption("Album_Asc", getString(R.string.music_sort_album_asc), MusicListSortBy.Album, MusicListSortOrder.Asc),
            SortOption("Album_Desc", getString(R.string.music_sort_album_desc), MusicListSortBy.Album, MusicListSortOrder.Desc),
            SortOption("Duration_Asc", getString(R.string.music_sort_duration_asc), MusicListSortBy.Duration, MusicListSortOrder.Asc),
            SortOption("Duration_Desc", getString(R.string.music_sort_duration_desc), MusicListSortBy.Duration, MusicListSortOrder.Desc),
            SortOption("FavoriteTime_Desc", getString(R.string.music_sort_favorite_time_desc), MusicListSortBy.FavoriteTime, MusicListSortOrder.Desc),
            SortOption("FavoriteTime_Asc", getString(R.string.music_sort_favorite_time_asc), MusicListSortBy.FavoriteTime, MusicListSortOrder.Asc),
        )
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"

        fun newInstance(sortBy: String, sortOrder: String): MusicTrackSortDialogFragment {
            return MusicTrackSortDialogFragment().apply {
                arguments = bundleOf(ARG_SORT_BY to sortBy, ARG_SORT_ORDER to sortOrder)
            }
        }
    }
}

class MusicGroupSortDialogFragment : DialogFragment() {
    private val currentBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val currentOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(460f)
        val panel =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val title =
            TextView(ctx).apply {
                text = getString(R.string.music_list_action_sort)
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 18f
                setPadding(dpToPx(18f), dpToPx(16f), dpToPx(18f), dpToPx(8f))
            }
        panel.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val listView =
            ListView(ctx).apply {
                choiceMode = ListView.CHOICE_MODE_SINGLE
                dividerHeight = 0
                selector = ctx.getDrawable(R.drawable.video_dialog_selector)
            }
        val listLp =
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0).apply {
                weight = 1f
            }
        panel.addView(listView, listLp)

        val options = buildGroupOptions()
        val currentKey = "${currentBy}_${currentOrder}".lowercase()
        val adapter =
            object : ArrayAdapter<SortOption>(ctx, android.R.layout.simple_list_item_single_choice, android.R.id.text1, options) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.setTextColor(0xFFFFFFFF.toInt())
                    if (t is CheckedTextView) {
                        val d = t.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            t.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)

        val idx = options.indexOfFirst { it.key.lowercase() == currentKey }
        if (idx >= 0) listView.setItemChecked(idx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val opt = options.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                MusicGroupGridFragment.RESULT_KEY_SORT,
                bundleOf(
                    MusicGroupGridFragment.RESULT_FIELD_SORT_BY to opt.by.name,
                    MusicGroupGridFragment.RESULT_FIELD_SORT_ORDER to opt.order.name,
                ),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class SortOption(
        val key: String,
        val label: String,
        val by: MusicGroupSortBy,
        val order: MusicGroupSortOrder,
    ) {
        override fun toString(): String = label
    }

    private fun buildGroupOptions(): List<SortOption> {
        return listOf(
            SortOption("Count_Desc", getString(R.string.music_group_sort_count_desc), MusicGroupSortBy.Count, MusicGroupSortOrder.Desc),
            SortOption("Count_Asc", getString(R.string.music_group_sort_count_asc), MusicGroupSortBy.Count, MusicGroupSortOrder.Asc),
            SortOption("Name_Asc", getString(R.string.music_group_sort_name_asc), MusicGroupSortBy.Name, MusicGroupSortOrder.Asc),
            SortOption("Name_Desc", getString(R.string.music_group_sort_name_desc), MusicGroupSortBy.Name, MusicGroupSortOrder.Desc),
        )
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"

        fun newInstance(sortBy: String, sortOrder: String): MusicGroupSortDialogFragment {
            return MusicGroupSortDialogFragment().apply {
                arguments = bundleOf(ARG_SORT_BY to sortBy, ARG_SORT_ORDER to sortOrder)
            }
        }
    }
}

class MusicPlaylistSortDialogFragment : DialogFragment() {
    private val currentBy: String by lazy { requireArguments().getString(ARG_SORT_BY).orEmpty() }
    private val currentOrder: String by lazy { requireArguments().getString(ARG_SORT_ORDER).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(460f)
        val panel =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val title =
            TextView(ctx).apply {
                text = getString(R.string.music_list_action_sort)
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 18f
                setPadding(dpToPx(18f), dpToPx(16f), dpToPx(18f), dpToPx(8f))
            }
        panel.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val listView =
            ListView(ctx).apply {
                choiceMode = ListView.CHOICE_MODE_SINGLE
                dividerHeight = 0
                selector = ctx.getDrawable(R.drawable.video_dialog_selector)
            }
        val listLp =
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0).apply {
                weight = 1f
            }
        panel.addView(listView, listLp)

        val options = buildPlaylistOptions()
        val currentKey = "${currentBy}_${currentOrder}".lowercase()
        val adapter =
            object : ArrayAdapter<SortOption>(ctx, android.R.layout.simple_list_item_single_choice, android.R.id.text1, options) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.setTextColor(0xFFFFFFFF.toInt())
                    if (t is CheckedTextView) {
                        val d = t.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            t.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)

        val idx = options.indexOfFirst { it.key.lowercase() == currentKey }
        if (idx >= 0) listView.setItemChecked(idx, true)

        listView.setOnItemClickListener { _, _, position, _ ->
            val opt = options.getOrNull(position) ?: return@setOnItemClickListener
            parentFragmentManager.setFragmentResult(
                MusicPlaylistGridFragment.RESULT_KEY_SORT,
                bundleOf(
                    MusicPlaylistGridFragment.RESULT_FIELD_SORT_BY to opt.by.name,
                    MusicPlaylistGridFragment.RESULT_FIELD_SORT_ORDER to opt.order.name,
                ),
            )
            dismissAllowingStateLoss()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private data class SortOption(
        val key: String,
        val label: String,
        val by: MusicPlaylistSortBy,
        val order: MusicPlaylistSortOrder,
    ) {
        override fun toString(): String = label
    }

    private fun buildPlaylistOptions(): List<SortOption> {
        return listOf(
            SortOption("CreateTime_Desc", getString(R.string.music_playlist_sort_create_time_desc), MusicPlaylistSortBy.CreateTime, MusicPlaylistSortOrder.Desc),
            SortOption("CreateTime_Asc", getString(R.string.music_playlist_sort_create_time_asc), MusicPlaylistSortBy.CreateTime, MusicPlaylistSortOrder.Asc),
            SortOption("Name_Asc", getString(R.string.music_playlist_sort_name_asc), MusicPlaylistSortBy.Name, MusicPlaylistSortOrder.Asc),
            SortOption("Name_Desc", getString(R.string.music_playlist_sort_name_desc), MusicPlaylistSortBy.Name, MusicPlaylistSortOrder.Desc),
        )
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_SORT_BY = "sort_by"
        private const val ARG_SORT_ORDER = "sort_order"

        fun newInstance(sortBy: String, sortOrder: String): MusicPlaylistSortDialogFragment {
            return MusicPlaylistSortDialogFragment().apply {
                arguments = bundleOf(ARG_SORT_BY to sortBy, ARG_SORT_ORDER to sortOrder)
            }
        }
    }
}

class MusicSourceDialogFragment : DialogFragment() {
    private val titleRes: Int by lazy { requireArguments().getInt(ARG_TITLE_RES) }
    private val availablePaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_AVAILABLE_PATHS) ?: arrayListOf() }
    private val selectedPaths: ArrayList<String> by lazy { requireArguments().getStringArrayList(ARG_SELECTED_PATHS) ?: arrayListOf() }
    private val resultKey: String by lazy { requireArguments().getString(ARG_RESULT_KEY).orEmpty() }
    private val resultField: String by lazy { requireArguments().getString(ARG_RESULT_FIELD).orEmpty() }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = Dialog(requireContext(), R.style.Theme_NasCabTv_Dialog)
        dialog.setCanceledOnTouchOutside(true)
        return dialog
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setGravity(Gravity.END)
            setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            setBackgroundDrawableResource(android.R.color.transparent)
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val root = FrameLayout(ctx)

        val scrim =
            View(ctx).apply {
                setBackgroundColor(0x66000000.toInt())
                setOnClickListener { dismissAllowingStateLoss() }
            }
        root.addView(scrim, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        val panelWidth = dpToPx(560f)
        val panel =
            LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(0xFF1E1E1E.toInt())
            }
        val panelLp =
            FrameLayout.LayoutParams(panelWidth, ViewGroup.LayoutParams.MATCH_PARENT).apply {
                gravity = Gravity.END
            }
        root.addView(panel, panelLp)

        val title =
            TextView(ctx).apply {
                text = getString(titleRes)
                setTextColor(0xFFEEEEEE.toInt())
                textSize = 18f
                setPadding(dpToPx(18f), dpToPx(16f), dpToPx(18f), dpToPx(8f))
            }
        panel.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        val listView =
            ListView(ctx).apply {
                choiceMode = ListView.CHOICE_MODE_MULTIPLE
                dividerHeight = 0
                selector = ctx.getDrawable(R.drawable.video_dialog_selector)
            }
        val listLp =
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0).apply {
                weight = 1f
            }
        panel.addView(listView, listLp)

        val allLabel = getString(R.string.music_list_sources_all_sources)
        val paths = availablePaths.map { it.trim() }.filter { it.isNotEmpty() }
        val selectedSet = selectedPaths.map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet()
        val rows = ArrayList<String>(paths.size + 1).apply {
            add(allLabel)
            addAll(paths)
        }

        val adapter =
            object : ArrayAdapter<String>(ctx, android.R.layout.simple_list_item_multiple_choice, android.R.id.text1, rows) {
                override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                    val v = super.getView(position, convertView, parent)
                    val t = v.findViewById<TextView>(android.R.id.text1)
                    t.setTextColor(0xFFFFFFFF.toInt())
                    if (t is CheckedTextView) {
                        val d = t.checkMarkDrawable
                        if (d != null) {
                            val wrap = DrawableCompat.wrap(d)
                            DrawableCompat.setTint(wrap, 0xCCFFFFFF.toInt())
                            t.setCheckMarkDrawable(wrap)
                        }
                    }
                    v.setBackgroundColor(0x00000000)
                    return v
                }
            }
        listView.adapter = adapter
        listView.setBackgroundColor(0x00000000)

        if (selectedSet.isEmpty()) {
            listView.setItemChecked(0, true)
        } else {
            listView.setItemChecked(0, false)
        }
        for (i in paths.indices) {
            listView.setItemChecked(i + 1, selectedSet.contains(paths[i]))
        }

        fun emitSelection() {
            if (resultKey.isEmpty() || resultField.isEmpty()) return
            val picked =
                if (selectedSet.isEmpty()) {
                    arrayListOf<String>()
                } else {
                    ArrayList(selectedSet.toList())
                }
            parentFragmentManager.setFragmentResult(resultKey, bundleOf(resultField to picked))
        }
        emitSelection()

        listView.setOnItemClickListener { _, _, position, _ ->
            if (position == 0) {
                listView.setItemChecked(0, true)
                selectedSet.clear()
                for (i in paths.indices) {
                    listView.setItemChecked(i + 1, false)
                }
                emitSelection()
                return@setOnItemClickListener
            }
            val p = paths.getOrNull(position - 1).orEmpty()
            if (p.isEmpty()) return@setOnItemClickListener
            if (selectedSet.contains(p)) selectedSet.remove(p) else selectedSet.add(p)
            if (selectedSet.isEmpty()) {
                listView.setItemChecked(0, true)
                for (i in paths.indices) listView.setItemChecked(i + 1, false)
            } else {
                listView.setItemChecked(0, false)
            }
            emitSelection()
        }

        listView.post { listView.requestFocus() }
        return root
    }

    private fun dpToPx(dp: Float): Int {
        return (dp * resources.displayMetrics.density).toInt().coerceAtLeast(0)
    }

    companion object {
        private const val ARG_TITLE_RES = "title_res"
        private const val ARG_AVAILABLE_PATHS = "available_paths"
        private const val ARG_SELECTED_PATHS = "selected_paths"
        private const val ARG_RESULT_KEY = "result_key"
        private const val ARG_RESULT_FIELD = "result_field"

        fun newInstance(
            titleRes: Int,
            availablePaths: ArrayList<String>,
            selectedPaths: ArrayList<String>,
            resultKey: String,
            resultField: String,
        ): MusicSourceDialogFragment {
            return MusicSourceDialogFragment().apply {
                arguments =
                    bundleOf(
                        ARG_TITLE_RES to titleRes,
                        ARG_AVAILABLE_PATHS to availablePaths,
                        ARG_SELECTED_PATHS to selectedPaths,
                        ARG_RESULT_KEY to resultKey,
                        ARG_RESULT_FIELD to resultField,
                    )
            }
        }
    }
}
