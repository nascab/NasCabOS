package com.nascabos.tv.modules.video.presenter

import android.content.Context
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.core.ui.TvImageLoader
import com.nascabos.tv.modules.video.VideoLibraryKind
import com.nascabos.tv.modules.video.VideoLibraryListItem

class VideoLibraryCardPresenter(
    private val context: Context,
    private val kind: VideoLibraryKind,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view =
            LayoutInflater.from(parent.context).inflate(R.layout.video_library_grid_card, parent, false).apply {
                isFocusable = true
                isFocusableInTouchMode = true
            }

        val titleView = view.findViewById<TextView>(R.id.video_library_card_title)
        view.onFocusChangeListener =
            View.OnFocusChangeListener { _, hasFocus ->
                titleView.isSelected = hasFocus
            }

        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val view = viewHolder.view
        val data = item as? VideoLibraryListItem ?: return

        val title = view.findViewById<TextView>(R.id.video_library_card_title)
        val subtitle = view.findViewById<TextView>(R.id.video_library_card_subtitle)
        val tag = view.findViewById<TextView>(R.id.video_library_card_tag)

        title.text = data.name.trim()

        val sub = if (kind == VideoLibraryKind.SmartAlbum) "" else data.type.trim()
        subtitle.text = sub
        subtitle.visibility = if (sub.isNotEmpty()) View.VISIBLE else View.GONE

        tag.text =
            when (kind) {
                VideoLibraryKind.Album -> context.getString(R.string.video_library_tag_album)
                VideoLibraryKind.SmartAlbum -> context.getString(R.string.video_library_tag_smart_album)
                VideoLibraryKind.Collection -> context.getString(R.string.video_library_tag_collection)
            }

        val single = view.findViewById<ImageView>(R.id.video_library_thumb_single)
        val row = view.findViewById<View>(R.id.video_library_thumb_row)
        val iv1 = view.findViewById<ImageView>(R.id.video_library_thumb_1)
        val iv2 = view.findViewById<ImageView>(R.id.video_library_thumb_2)
        val iv3 = view.findViewById<ImageView>(R.id.video_library_thumb_3)
        val iv4 = view.findViewById<ImageView>(R.id.video_library_thumb_4)

        val paths =
            data.previews.mapNotNull {
                val p = it.fullPath.trim().ifEmpty { it.firstFilePath.trim() }
                p.ifEmpty { null }
            }.take(4)

        if (paths.size <= 1) {
            row.visibility = View.GONE
            single.visibility = View.VISIBLE
            val p = paths.firstOrNull().orEmpty()
            if (p.isEmpty()) {
                bindEmptyThumb(single)
            } else {
                bindCoverThumb(single, p)
            }
        } else {
            single.visibility = View.GONE
            row.visibility = View.VISIBLE
            bindThumbSlot(iv1, paths.getOrNull(0))
            bindThumbSlot(iv2, paths.getOrNull(1))
            bindThumbSlot(iv3, paths.getOrNull(2))
            bindThumbSlot(iv4, paths.getOrNull(3))
        }
    }

    private fun bindThumbSlot(iv: ImageView, path: String?) {
        val p = path?.trim().orEmpty()
        iv.visibility = View.VISIBLE
        if (p.isEmpty()) {
            bindEmptyThumb(iv)
        } else {
            bindCoverThumb(iv, p)
        }
    }

    private fun bindCoverThumb(iv: ImageView, path: String) {
        iv.setBackgroundColor(Color.TRANSPARENT)
        iv.colorFilter = null
        iv.scaleType = ImageView.ScaleType.CENTER_CROP
        TvImageLoader.loadTinyInto(iv, path, size = 480)
    }

    private fun bindEmptyThumb(iv: ImageView) {
        iv.setBackgroundColor(Color.parseColor("#121212"))
        iv.colorFilter = null
        iv.scaleType = ImageView.ScaleType.FIT_CENTER
        iv.setImageResource(R.drawable.no_data)
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {}
}
