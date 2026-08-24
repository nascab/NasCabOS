package com.nascabos.tv.modules.serverlist.presenter

import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.leanback.widget.ImageCardView
import androidx.leanback.widget.Presenter
import com.nascabos.tv.R
import com.nascabos.tv.data.model.ServerInfo

sealed interface ServerCardItem

data class ServerInfoCard(val server: ServerInfo) : ServerCardItem

data class ActionCard(val kind: ActionKind) : ServerCardItem

enum class ActionKind { Language, AddDirect, AddByPairCode }

class ServerCardPresenter(
    private val context: Context,
) : Presenter() {
    override fun onCreateViewHolder(parent: ViewGroup): ViewHolder {
        val view = ImageCardView(parent.context).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            setMainImageDimensions(360, 200)
            setInfoAreaBackgroundColor(Color.parseColor("#1E1E1E"))
            mainImageView.scaleType = ImageView.ScaleType.CENTER_INSIDE
        }
        runCatching {
            val content = view.findViewById<TextView>(androidx.leanback.R.id.content_text)
            content.minLines = 3
            content.maxLines = 3
            content.ellipsize = TextUtils.TruncateAt.END
        }
        return ViewHolder(view)
    }

    override fun onBindViewHolder(viewHolder: ViewHolder, item: Any) {
        val cardView = viewHolder.view as ImageCardView
        when (item) {
            is ActionCard -> bindAction(cardView, item)
            is ServerInfoCard -> bindServer(cardView, item.server)
        }
    }

    override fun onUnbindViewHolder(viewHolder: ViewHolder) {
        val cardView = viewHolder.view as ImageCardView
        cardView.mainImage = null
    }

    private fun bindAction(cardView: ImageCardView, item: ActionCard) {
        val (title, iconRes) =
            when (item.kind) {
                ActionKind.Language ->
                    context.getString(R.string.action_language) to R.drawable.ic_language
                ActionKind.AddDirect ->
                    context.getString(R.string.server_add_direct) to R.drawable.ic_add
                ActionKind.AddByPairCode ->
                    context.getString(R.string.server_add_by_pair_code) to R.drawable.ic_qr
            }
        val desc =
            when (item.kind) {
                ActionKind.Language -> ""
                ActionKind.AddDirect -> context.getString(R.string.server_add_direct_desc)
                ActionKind.AddByPairCode -> context.getString(R.string.server_add_by_pair_code_desc)
            }
        cardView.titleText = title
        cardView.contentText = desc
        cardView.mainImageView.setBackgroundColor(Color.parseColor("#2C2C2C"))
        cardView.mainImageView.scaleType = ImageView.ScaleType.CENTER
        val pad = (22f * context.resources.displayMetrics.density).toInt()
        cardView.mainImageView.setPadding(pad, pad, pad, pad)
        cardView.mainImage = ContextCompat.getDrawable(context, iconRes)
    }

    private fun bindServer(cardView: ImageCardView, server: ServerInfo) {
        val title = server.serverName.trim().ifEmpty { server.serverHostName.trim().ifEmpty { "NasCab" } }
        val primary = when {
            server.isP2p || server.pairCode.trim().isNotEmpty() && server.serverUrl.trim().isEmpty() -> "P2P"
            server.serverUrl.trim().isNotEmpty() -> normalizeUrlPort(server.serverUrl.trim())
            else -> ""
        }
        val username = server.username.trim()
        val lines = mutableListOf<String>()
        if (isDiscoveredOnly(server)) lines += context.getString(R.string.server_tag_auto_discovered)
        if (username.isNotEmpty()) lines += username
        if (primary.isNotEmpty()) lines += primary
        val code = server.pairCode.trim()
        if (code.isNotEmpty()) lines += "${context.getString(R.string.field_pair_code)}：$code"
        val content = lines.filter { it.isNotBlank() }.take(3).joinToString("\n")
        cardView.titleText = title
        cardView.contentText = content
        cardView.mainImageView.setBackgroundColor(Color.parseColor("#2C2C2C"))
        cardView.mainImageView.scaleType = ImageView.ScaleType.CENTER_INSIDE

        val platform = server.serverPlatform.trim().lowercase()
        val tokens =
            platform
                .split(Regex("[^a-z0-9]+"))
                .filter { it.isNotBlank() }
                .toSet()
        val isMac = "darwin" in tokens || "mac" in tokens || "osx" in tokens || platform.contains("macos")
        val isWindows =
            "windows" in tokens ||
                "win" in tokens ||
                "win32" in tokens ||
                "win64" in tokens ||
                platform.contains("windows")
        val isLinux = "linux" in tokens || platform.contains("linux")
        val platformIconRes =
            when {
                isMac -> R.drawable.server_mac
                isWindows -> R.drawable.server_windows
                isLinux -> R.drawable.server_linux
                else -> R.drawable.ic_server
            }

        if (platformIconRes == R.drawable.ic_server) {
            val pad = (18f * context.resources.displayMetrics.density).toInt()
            cardView.mainImageView.setPadding(pad, pad, pad, pad)
        } else {
            cardView.mainImageView.setPadding(0, 0, 0, 0)
        }

        cardView.mainImage = ContextCompat.getDrawable(context, platformIconRes)
    }

    private fun normalizeUrlPort(url: String): String {
        val s = url.trim()
        if (s.isEmpty()) return s
        return s.replace(Regex(":(\\d+)\\.0(?=\\b|/|$)"), ":$1")
    }

    private fun isDiscoveredOnly(server: ServerInfo): Boolean {
        if (!server.isAutoScanned) return false
        if (server.serverId.trim().isEmpty()) return false
        if (server.username.trim().isNotEmpty()) return false
        if (server.password.trim().isNotEmpty()) return false
        if (server.accessToken.trim().isNotEmpty()) return false
        if (server.refreshToken.trim().isNotEmpty()) return false
        return true
    }
}
