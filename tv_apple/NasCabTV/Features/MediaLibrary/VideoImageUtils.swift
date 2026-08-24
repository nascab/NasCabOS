import Foundation

enum TVVideoImageUtils {
    /// P2P 模式下使用本地代理 base（与播放器一致），否则 AsyncImage 无法解析 p2p.local。
    @MainActor private static var effectiveBase: String? {
        let api = APIClient.shared
        if api.isP2pMode, let proxyBase = LocalPlaybackProxy.shared.baseURL {
            return proxyBase
        }
        var base = api.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        return base.isEmpty ? nil : base
    }

    /// 与 Flutter `Uri.encodeComponent` 等价的编码：仅保留 RFC 3986 unreserved 字符
    private static let componentAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return set
    }()

    private static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? value
    }

    @MainActor static func posterURL(for item: TVVideoItem, size: Int = 640) -> URL? {
        let api = APIClient.shared
        guard let base = effectiveBase else { return nil }

        let posterPath = item.posterPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstFile = item.firstFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullPath = item.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let filePath: String
        if !posterPath.isEmpty {
            filePath = posterPath
        } else if !firstFile.isEmpty {
            filePath = firstFile
        } else {
            filePath = fullPath
        }
        guard !filePath.isEmpty else { return nil }

        var baseUrlString = base
        if baseUrlString.hasSuffix("/") { baseUrlString.removeLast() }

        // 按照 Flutter getTinyUrl 的 fallback 方式拼接 URL
        let encodedPath = encodeComponent(filePath)
        var url = "\(baseUrlString)/api/file/tiny?path=\(encodedPath)"
        if api.isP2pMode { url += "&p2pChannel=file" }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        url += "&size=\(size)"
        return URL(string: url)
    }

    @MainActor static func fanartURL(for item: TVVideoItem, size: Int = 1000) -> URL? {
        let api = APIClient.shared
        guard let base = effectiveBase else { return nil }

        let fanartPath = item.fanartPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstFile = item.firstFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullPath = item.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let filePath: String
        if !fanartPath.isEmpty {
            filePath = fanartPath
        } else if !firstFile.isEmpty {
            filePath = firstFile
        } else {
            filePath = fullPath
        }
        guard !filePath.isEmpty else { return nil }

        var baseUrlString = base
        if baseUrlString.hasSuffix("/") { baseUrlString.removeLast() }
        let encodedPath = encodeComponent(filePath)
        var url = "\(baseUrlString)/api/file/tiny?path=\(encodedPath)"
        if api.isP2pMode { url += "&p2pChannel=file" }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        url += "&size=\(size)"
        return URL(string: url)
    }

    /// 原始文件 URL（大图预览用），不带 raw=1 以便 size 参数生效
    @MainActor static func rawFileURL(forPath filePath: String, size: Int = 4000) -> URL? {
        let api = APIClient.shared
        guard let base = effectiveBase else { return nil }
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var baseUrlString = base
        if baseUrlString.hasSuffix("/") { baseUrlString.removeLast() }
        let encodedPath = encodeComponent(trimmed)
        var url = "\(baseUrlString)/api/file/rawFile?path=\(encodedPath)"
        if api.isP2pMode { url += "&p2pChannel=file" }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        url += "&size=\(size)"
        return URL(string: url)
    }

    @MainActor static func tinyArtworkURL(forPath artworkPath: String, size: Int = 640) -> URL? {
        let api = APIClient.shared
        guard let base = effectiveBase else { return nil }

        let trimmed = artworkPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var baseUrlString = base
        if baseUrlString.hasSuffix("/") { baseUrlString.removeLast() }
        let encodedPath = encodeComponent(trimmed)
        var url = "\(baseUrlString)/api/file/tiny?path=\(encodedPath)"
        if api.isP2pMode { url += "&p2pChannel=file" }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        url += "&size=\(size)"
        return URL(string: url)
    }

    @MainActor static func personImageURL(
        tmdbId: String,
        thumb: String?,
        size: Int = 240
    ) -> URL? {
        let api = APIClient.shared
        guard let base = effectiveBase else { return nil }

        let id = tmdbId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        var baseNorm = base
        if baseNorm.hasSuffix("/") { baseNorm.removeLast() }
        var query: [String] = []
        query.append("tmdb_id=\(encodeComponent(id))")
        query.append("size=\(size)")
        if let thumb, !thumb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let t = thumb.trimmingCharacters(in: .whitespacesAndNewlines)
            query.append("thumb=\(encodeComponent(t))")
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            query.append("accessToken=\(encodeComponent(token))")
        }

        let queryString = query.joined(separator: "&")
        let urlString = "\(baseNorm)/api/video/person/image?\(queryString)"
        return URL(string: urlString)
    }
}

