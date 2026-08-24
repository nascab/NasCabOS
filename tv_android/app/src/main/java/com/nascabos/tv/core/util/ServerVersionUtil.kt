package com.nascabos.tv.core.util

object ServerVersionUtil {
    fun parseMajorVersion(version: String?): Int? {
        val trimmed = version?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val normalized =
            if (trimmed.startsWith("v", ignoreCase = true)) {
                trimmed.substring(1)
            } else {
                trimmed
            }
        val parts = normalized.split('.')
        if (parts.isEmpty()) return null
        val first = parts.first()
        val match = Regex("(\\d+)").find(first) ?: return null
        return match.groupValues.getOrNull(1)?.toIntOrNull()
    }

    fun isAtLeast(
        version: String?,
        majorVersion: Int,
        unknownAsSupported: Boolean = true,
    ): Boolean {
        val major = parseMajorVersion(version)
        if (major == null) return unknownAsSupported
        return major >= majorVersion
    }
}
