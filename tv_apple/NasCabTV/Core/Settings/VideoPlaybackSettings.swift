import Foundation

enum VideoPlaybackSettings {
    static let defaultsKey = "video_playback_default_quality"
    static let qualityOriginal = "original"

    static let qualityOptions: [String] = [
        qualityOriginal,
        "4k_20m",
        "4k_15m",
        "4k_10m",
        "1080p_8m",
        "1080p_5m",
        "1080p_3m",
        "1080p_2m",
        "720p_3m",
        "720p_2m",
        "720p_1m",
        "480p_1m",
    ]

    static func loadDefaultQuality() -> String {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return qualityOptions.contains(saved) ? saved : qualityOriginal
    }

    static func saveDefaultQuality(_ quality: String) {
        guard qualityOptions.contains(quality) else { return }
        UserDefaults.standard.set(quality, forKey: defaultsKey)
    }

    static func label(for quality: String) -> String {
        if quality == qualityOriginal {
            return L10n.tr("player_quality_original")
        }
        return quality.uppercased()
    }
}
