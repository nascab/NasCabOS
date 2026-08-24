package com.nascabos.tv.modules.video_player

import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.nascabos.tv.R

data class TvPanelRow(
    val title: String,
    val subtitle: String,
)

class TvPlayerPanelAdapter(
    private val onClick: (Int) -> Unit,
) : RecyclerView.Adapter<TvPlayerPanelAdapter.Vh>() {
    private val items: MutableList<TvPanelRow> = ArrayList()

    fun submit(list: List<TvPanelRow>) {
        items.clear()
        items.addAll(list)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Vh {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_tv_player_panel_row, parent, false)
        return Vh(v, onClick)
    }

    override fun onBindViewHolder(holder: Vh, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    class Vh(
        itemView: View,
        onClick: (Int) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(R.id.title)
        private val subtitleView: TextView = itemView.findViewById(R.id.subtitle)

        private val focusedBg: Int = Color.parseColor("#CC1E88E5")
        private val normalBg: Int = Color.TRANSPARENT
        private val focusedTitle: Int = Color.WHITE
        private val focusedSubtitle: Int = Color.parseColor("#E6FFFFFF")
        private val normalTitle: Int = Color.WHITE
        private val normalSubtitle: Int = Color.parseColor("#B3FFFFFF")

        init {
            itemView.setOnClickListener {
                val pos = bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) onClick(pos)
            }
            itemView.setOnFocusChangeListener { _, hasFocus ->
                applyFocus(hasFocus)
            }
        }

        fun bind(item: TvPanelRow) {
            titleView.text = item.title
            subtitleView.text = item.subtitle
            applyFocus(itemView.hasFocus())
        }

        private fun applyFocus(hasFocus: Boolean) {
            if (hasFocus) {
                itemView.setBackgroundColor(focusedBg)
                titleView.setTextColor(focusedTitle)
                subtitleView.setTextColor(focusedSubtitle)
                itemView.scaleX = 1.04f
                itemView.scaleY = 1.04f
            } else {
                itemView.setBackgroundColor(normalBg)
                titleView.setTextColor(normalTitle)
                subtitleView.setTextColor(normalSubtitle)
                itemView.scaleX = 1.0f
                itemView.scaleY = 1.0f
            }
        }
    }
}
