import SwiftUI

struct VideoPlaybackSettingsView: View {
    @AppStorage(VideoPlaybackSettings.defaultsKey) private var selectedQuality: String = VideoPlaybackSettings.qualityOriginal

    var body: some View {
        NCModalPanelContainer(maxWidth: 900, maxHeight: 720) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.tr("home_video_playback_settings"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(L10n.tr("video_playback_default_quality_desc"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(L10n.tr("video_playback_default_quality"))
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(VideoPlaybackSettings.qualityOptions, id: \.self) { quality in
                            NCModalOptionButton(
                                label: VideoPlaybackSettings.label(for: quality),
                                isSelected: selectedQuality == quality
                            ) {
                                selectedQuality = quality
                                VideoPlaybackSettings.saveDefaultQuality(quality)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .clipped()

                Spacer()
            }
        }
    }
}
