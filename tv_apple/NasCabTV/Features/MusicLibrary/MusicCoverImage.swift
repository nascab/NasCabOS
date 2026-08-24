import SwiftUI

// MARK: - Music Cover Image (API cover + fallback to musicCover assets)

/// 封面逻辑参考 Flutter：showType=series 用 firstFilePath，否则 fullPath；无封面时用 musicCover 默认图
struct MusicCoverImage: View {
    let item: MusicItem?
    let filePath: String
    let size: Int
    let fallbackName: String?

    init(item: MusicItem? = nil, filePath: String, size: Int = 400, fallbackName: String? = nil) {
        self.item = item
        self.filePath = filePath.trimmingCharacters(in: .whitespaces)
        self.size = size
        self.fallbackName = fallbackName
    }

    private var coverURL: URL? {
        guard !filePath.isEmpty else { return nil }
        return MusicService.coverURL(filePath: filePath, size: size)
    }

    private var fallbackAssetName: String {
        fallbackName ?? MusicCoverImage.fallbackAssetName(genre: item?.genre ?? "", id: item?.id ?? 0)
    }

    var body: some View {
        Group {
            if let url = coverURL {
                MusicCoverAsyncImage(url: url, fallbackName: fallbackAssetName)
            } else {
                Image(fallbackAssetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }

    /// 参考 Flutter _pickFallbackCoverAsset：按 genre 选 blues/classical/country/gospel/hiphop/pop/rock 1-6，否则 other 1-20
    static func fallbackAssetName(genre: String, id: Int) -> String {
        let raw = genre.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: "/,;|")).map { $0.trimmingCharacters(in: .whitespaces) }
        let head = parts.first ?? ""
        let normalized = head.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map { Character($0) }
        let headNorm = String(normalized)

        let genreKeys = Set(["blues", "classical", "country", "gospel", "hiphop", "pop", "rock"])
        if !headNorm.isEmpty, genreKeys.contains(headNorm) {
            let idx = (abs(id) % 6) + 1
            return "\(headNorm)\(idx)"
        }
        let idx = (abs(id) % 20) + 1
        return "other\(idx)"
    }
}

// MARK: - Async Image with Fallback

private struct MusicCoverAsyncImage: View {
    let url: URL
    let fallbackName: String

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Image(fallbackName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            @unknown default:
                Image(fallbackName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
    }
}
