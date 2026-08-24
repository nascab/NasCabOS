package com.nascabos.tv.modules.video_player

data class TvSubtitleCue(
    val startMs: Long,
    val endMs: Long,
    val text: String,
)

object TvWebVttParser {
    fun parseWebVtt(vttText: String): List<TvSubtitleCue> {
        val lines = vttText.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        val cues = ArrayList<TvSubtitleCue>()

        var i = 0
        while (i < lines.size && lines[i].trim().isEmpty()) i++
        if (i < lines.size) {
            val first = lines[i].trimStart()
            if (first.startsWith("\uFEFF")) {
                // BOM handled by trimStart on first content line
            }
        }
        if (i < lines.size && lines[i].trim().uppercase().startsWith("WEBVTT")) {
            i++
        }

        while (i < lines.size) {
            while (i < lines.size && lines[i].trim().isEmpty()) i++
            if (i >= lines.size) break

            val head = lines[i].trim()
            if (head.startsWith("NOTE") || head.startsWith("STYLE") || head.startsWith("REGION")) {
                i++
                while (i < lines.size && lines[i].trim().isNotEmpty()) i++
                continue
            }

            var timeLine = lines[i]
            if (!timeLine.contains("-->")) {
                i++
                if (i >= lines.size) break
                timeLine = lines[i]
            }

            val arrow = timeLine.indexOf("-->")
            if (arrow == -1) {
                i++
                continue
            }
            val left = timeLine.substring(0, arrow).trim()
            val rightPart = timeLine.substring(arrow + 3).trim()
            val right = rightPart.split(Regex("\\s+")).firstOrNull()?.trim().orEmpty()

            val start = parseVttTimestamp(left)
            val end = parseVttTimestamp(right)
            i++
            if (start == null || end == null) {
                while (i < lines.size && lines[i].trim().isNotEmpty()) i++
                continue
            }

            val buf = StringBuilder()
            while (i < lines.size && lines[i].trim().isNotEmpty()) {
                if (buf.isNotEmpty()) buf.append('\n')
                buf.append(lines[i])
                i++
            }
            val text = formatCueText(buf.toString().trim())
            if (text.isNotEmpty() && end > start) {
                cues += TvSubtitleCue(startMs = start, endMs = end, text = text)
            }
        }

        cues.sortBy { it.startMs }
        return cues
    }

    fun findActiveCue(cues: List<TvSubtitleCue>, positionMs: Long): TvSubtitleCue? {
        if (cues.isEmpty()) return null
        var lo = 0
        var hi = cues.size - 1
        var best = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val c = cues[mid]
            if (c.startMs <= positionMs) {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if (best < 0) return null
        val c = cues[best]
        return if (positionMs in c.startMs..c.endMs) c else null
    }

    private fun parseVttTimestamp(raw: String): Long? {
        val s = raw.trim()
        if (s.isEmpty()) return null
        val parts = s.split(':')
        if (parts.size !in 2..3) return null
        val hours: Int
        val minutes: Int
        val seconds: Double
        if (parts.size == 3) {
            hours = parts[0].toIntOrNull() ?: return null
            minutes = parts[1].toIntOrNull() ?: return null
            seconds = parts[2].replace(',', '.').toDoubleOrNull() ?: return null
        } else {
            hours = 0
            minutes = parts[0].toIntOrNull() ?: return null
            seconds = parts[1].replace(',', '.').toDoubleOrNull() ?: return null
        }
        if (hours < 0 || minutes < 0 || seconds < 0) return null
        return (hours * 3600_000L) + (minutes * 60_000L) + (seconds * 1000.0).toLong()
    }

    /** ffmpeg WebVTT 常带 &lt;br&gt;、&lt;font&gt; 等标签；叠层 TextView 需转成纯文本。 */
    fun formatCueText(raw: String): String {
        var s = raw.trim()
        if (s.isEmpty()) return s
        s = Regex("(?i)<br\\s*/?>").replace(s, "\n")
        s = Regex("<[^>]*>").replace(s, "")
        s = Regex("\\{[^}]*\\}").replace(s, "")
        s =
            s
                .replace("&nbsp;", " ")
                .replace("&amp;", "&")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
        return s.trim()
    }
}
