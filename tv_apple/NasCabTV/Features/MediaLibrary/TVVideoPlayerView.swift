import SwiftUI
import Combine
import AVFoundation
import GameController
import UIKit
#if canImport(FSPlayer)
import FSPlayer
#endif

// MARK: - Playlist Item

struct TVVideoPlaylistItem: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String
    /// 与 Android `internalPath` 一致：ISO/BDMV 等容器内真实媒体路径，供服务端解析；可为空。
    var internalPath: String = ""
}

#if canImport(FSPlayer)

// MARK: - Subtitle Search Models (Thunder)

fileprivate struct TVSubtitleSearchItem: Identifiable, Equatable {
    let id = UUID()
    let sname: String
    let displayName: String
    let language: String
    let surl: String
    let ext: String
}

// MARK: - Stream Info Models

private struct TVVideoStreamInfo {
    struct Track {
        enum Kind {
            case video
            case audio
            case subtitle
        }

        let kind: Kind
        let index: Int
        let mapIndex: Int
        let label: String
        let isExternal: Bool
        let externalPath: String?
        let codecName: String?
    }

    let durationSeconds: Int
    let audioTracks: [Track]
    let subtitleTracks: [Track]
}

// MARK: - URL Builder

@MainActor
private enum TVVideoPlaybackURLBuilder {
    /// P2P 模式下使用本地代理 base，直连使用 API base。
    private static var effectiveBase: String? {
        let api = APIClient.shared
        if api.isP2pMode, let proxyBase = LocalPlaybackProxy.shared.baseURL {
            return proxyBase
        }
        var base = api.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        return base.isEmpty ? nil : base
    }

    /// 与 Flutter `Uri.encodeComponent` 等价的编码
    private static let componentAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return set
    }()

    private static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? value
    }

    static func buildOriginalURL(path: String, p2pChannel: String = "file") -> URL? {
        let api = APIClient.shared
        let base = effectiveBase
        if api.isP2pMode && base == nil {
            print("[P2P] TVVideoPlaybackURLBuilder: buildOriginalURL effectiveBase=nil (proxy not ready?) path=\(path.prefix(60))...")
        }
        guard let base else { return nil }
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        let encodedPath = encodeComponent(trimmedPath)

        var url = "\(base)/api/file/rawFile?path=\(encodedPath)&raw=1"
        if api.isP2pMode { url += "&p2pChannel=\(encodeComponent(p2pChannel))" }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        let urlForLog = url.replacingOccurrences(of: "accessToken=[^&]+", with: "accessToken=***", options: .regularExpression)
        print("[P2P] TVVideoPlaybackURLBuilder: buildOriginalURL base=\(base) url=\(urlForLog.prefix(100))...")
        return URL(string: url)
    }

    static func buildOriginalVideoURL(path: String) -> URL? {
        buildOriginalURL(path: path, p2pChannel: "video")
    }

    static func buildTranscodeURL(
        path: String,
        playId: String,
        seekSeconds: Int,
        quality: String,
        selectedAudio: TVVideoStreamInfo.Track?,
        selectedSubtitle: TVVideoStreamInfo.Track?
    ) -> URL? {
        guard let base = effectiveBase else { return nil }
        let api = APIClient.shared

        var width: Int?
        var bitrate: String?

        let parts = quality.split(separator: "_")
        if parts.count >= 2 {
            let res = parts[0].lowercased()
            let br = parts[1].lowercased()

            switch res {
            case "4k":
                width = 3840
            case "1080p":
                width = 1920
            case "720p":
                width = 1280
            case "480p":
                width = 854
            default:
                break
            }

            if let m = br.range(of: #"^(\d+)(m|k)$"#, options: .regularExpression) {
                let numPart = String(br[m].dropLast())
                let unit = br.last
                if let n = Int(numPart), n > 0 {
                    if unit == "m" {
                        bitrate = "\(n * 1000)k"
                    } else {
                        bitrate = "\(n)k"
                    }
                }
            }
        }

        var audioIndexParam: Int?
        if let a = selectedAudio {
            audioIndexParam = a.mapIndex
        }

        var subtitleIndexParam: Int?
        var subtitlePathParam: String?
        var burnSubtitle = false

        if let s = selectedSubtitle, subtitleTrackNeedsTranscodeBurn(s) {
            if s.isExternal {
                subtitlePathParam = s.externalPath
                burnSubtitle = true
            } else {
                subtitleIndexParam = s.mapIndex
                burnSubtitle = true
            }
        }

        let encodedPath = encodeComponent(path)
        var url = "\(base)/api/videoPlayer/transcode?playId=\(encodeComponent(playId))&filePath=\(encodedPath)&seek=\(seekSeconds)"
        let deviceId = DeviceFingerprint.getOrCreateVideoPlayerDeviceId().trimmingCharacters(in: .whitespacesAndNewlines)
        if !deviceId.isEmpty {
            url += "&device_id=\(encodeComponent(deviceId))"
        }

        if let w = width {
            url += "&width=\(w)"
        }
        if let br = bitrate {
            url += "&bitrate=\(br)"
        }
        if let ai = audioIndexParam {
            url += "&audioIndex=\(ai)"
        }
        if let si = subtitleIndexParam {
            url += "&subtitleIndex=\(si)"
        }
        if let sp = subtitlePathParam {
            url += "&subtitlePath=\(encodeComponent(sp))"
        }
        if burnSubtitle {
            url += "&subtitleBurn=true"
        }

        if api.isP2pMode {
            url += "&p2pChannel=video"
        }
        if let token = api.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            url += "&accessToken=\(encodeComponent(token))"
        }
        let urlForLog = url.replacingOccurrences(of: "accessToken=[^&]+", with: "accessToken=***", options: .regularExpression)
        print("[P2P] TVVideoPlaybackURLBuilder: buildTranscodeURL base=\(base) url=\(urlForLog.prefix(100))...")
        return URL(string: url)
    }

    fileprivate static func subtitleTrackNeedsTranscodeBurn(_ track: TVVideoStreamInfo.Track) -> Bool {
        if track.isExternal {
            let path = track.externalPath ?? ""
            let ext = (path as NSString).pathExtension
            let dotted = ext.isEmpty ? "" : ".\(ext.lowercased())"
            return SubtitleBitmapUtil.isBitmapExternalExtension(dotted)
        }
        return SubtitleBitmapUtil.isBitmapCodecName(track.codecName)
    }
}

// MARK: - ViewModel

@MainActor
final class TVVideoPlayerViewModel: NSObject, ObservableObject {
    enum SubtitleFontSize: String, CaseIterable {
        case small
        case medium
        case large

        var scaleValue: Double {
            switch self {
            case .small: return 0.8
            case .medium: return 1.0
            case .large: return 1.3
            }
        }
    }

    private static let subtitleFontSizeDefaultsKey = "TVVideoSubtitleFontSize"

    // Public state
    @Published var playlist: [TVVideoPlaylistItem]
    @Published var currentIndex: Int
    @Published var isPlaying: Bool = false
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var buffered: TimeInterval = 0

    @Published var playbackSpeed: Float = 1.0

    @Published var subtitleFontSize: SubtitleFontSize

    /// 隐藏控制栏下方向键快进预览位置（用于中间 HUD 展示）
    @Published var scrubbingPosition: TimeInterval?

    @Published var currentQuality: String = "original"
    let qualityOptions: [String] = [
        "original",
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
        "480p_1m"
    ]

    @Published fileprivate var availableAudioTracks: [TVVideoStreamInfo.Track] = []
    @Published fileprivate var availableSubtitleTracks: [TVVideoStreamInfo.Track] = []
    @Published fileprivate var selectedAudioTrack: TVVideoStreamInfo.Track?
    @Published fileprivate var selectedSubtitleTrack: TVVideoStreamInfo.Track?

    @Published var showControls: Bool = true
    /// 视频加载中（拉流/起播阶段）
    @Published var isLoading: Bool = false
    @Published var clientSubtitleText: String = ""

    // Private
    private var hideControlsWorkItem: DispatchWorkItem?
    private var playId: String?
    private var sourceDurationSeconds: Int?
    /// 转码模式下当前流的起始秒数（用于 position = transcodeBaseSeconds + vlc 当前时间）
    private var transcodeBaseSeconds: Int = 0
    private let initialSeekSeconds: Int
    /// 为 true 时不使用服务端偏好的播放进度（如从照片模块进入时从头播放）
    private let ignorePlaybackHistory: Bool
    /// 串行化：同一时间只允许一次 load，避免快进/切换音轨等触发多次并发导致服务端多转码进程
    private var loadTask: Task<Void, Never>?
    /// 转码下连续快进防抖：待跳转秒数，防抖任务触发后执行 load
    private var pendingSeekSeconds: Int?
    private var seekDebounceTask: Task<Void, Never>?
    /// 隐藏控制栏时，按住左右键连续预览快进/快退；松开后再执行 seek
    private var directionalScrubTask: Task<Void, Never>?
    private var directionalScrubTapSettleTask: Task<Void, Never>?
    private var directionalScrubStepSeconds: TimeInterval?

    // GameController 监听（Siri Remote 会作为 microGamepad 出现）
    private var gcObservers: [NSObjectProtocol] = []
    private var gcActiveDirection: Int = 0 // -1 left, 0 none, 1 right
    private var gcLastX: Float = 0
    private var gcLeftPressed: Bool = false
    private var gcRightPressed: Bool = false
    private var gcPendingDirection: Int = 0
    private var gcLongPressTask: Task<Void, Never>?
    private var inputOverlayActive: Bool = false

    /// 播放重试计数（用于处理 KSPlayer 提前结束或错误时的自动重试）
    private var playRetryCount: Int = 0
    /// 最近一次上报的播放位置（秒），用于断流后恢复到接近原位置
    private var lastKnownPositionSeconds: Int = 0
    /// 最近一次上报的总时长（秒），用于判断“是否异常提前结束”
    private var lastKnownDurationSeconds: Int?

    /// 从 getVideoInfo 返回的偏好，用于还原音轨/字幕/进度
    private struct VideoPreference {
        let playbackPosition: Int
        let audioLabel: String?
        let subtitleLabel: String?
    }
    private var lastFetchedPreference: VideoPreference?
    /// 已应用偏好进度的文件 path，换片后对新片可再次应用
    private var lastAppliedPreferenceSeekPath: String?
    /// 当前缓存的流信息对应的 path，换片后需重新拉取
    private var lastFetchedStreamInfoPath: String?
    /// 仅播放中每 30 秒保存一次偏好（nonisolated 以便 deinit 中清理）
    private nonisolated(unsafe) var preferenceSaveTimer: Timer?
    /// 上次保存尚未完成时不发起新请求，避免积压
    private var isPreferenceSaveInFlight: Bool = false

    // FSPlayer
    private var player: FSPlayer?
    private weak var drawableView: UIView?
    private var fsObservers: [NSObjectProtocol] = []
    /// FSPlayer 准备好后需要执行的初始 seek 秒数（仅原画）
    private var pendingInitialSeekSeconds: Int?
    private var clientSubtitleCues: [SubtitleCue] = []
    private var clientSubtitleCacheKey: String = ""
    private var clientSubtitleLoading = false

    // MARK: - Track helpers (FSPlayer original quality)

    init(
        playlist: [TVVideoPlaylistItem],
        initialIndex: Int,
        initialSeekSeconds: Int = 0,
        ignorePlaybackHistory: Bool = false,
        ignoreFindSub: Int = 1
    ) {
        self.playlist = playlist
        self.currentIndex = min(max(initialIndex, 0), max(playlist.count - 1, 0))
        self.initialSeekSeconds = max(0, initialSeekSeconds)
        self.ignorePlaybackHistory = ignorePlaybackHistory
        self.ignoreFindSub = ignoreFindSub == 0 ? 0 : 1
        self.currentQuality = VideoPlaybackSettings.loadDefaultQuality()
        if let stored = UserDefaults.standard.string(forKey: Self.subtitleFontSizeDefaultsKey),
           let size = SubtitleFontSize(rawValue: stored) {
            self.subtitleFontSize = size
        } else {
            self.subtitleFontSize = .medium
        }
        super.init()
    }

    /// 1: 跳过扫描同目录同名外挂字幕；0: 允许扫描（仅影音模块进入播放器时使用）
    private let ignoreFindSub: Int

    deinit {
        let t = preferenceSaveTimer
        preferenceSaveTimer = nil
        if t != nil {
            DispatchQueue.main.async { t?.invalidate() }
        }
        // 恢复系统休眠（播放器销毁时）
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // 清理 FSPlayer 通知与播放器
        NotificationCenter.default.removeObserver(self)
        player?.shutdown()
    }

    /// 停止当前转码会话（退出播放器或重新转码前调用），与 Flutter _stopTranscoding 一致
    func stopTranscodeIfNeeded() async {
        guard let pid = playId else { return }
        await stopTranscodeAPI(playId: pid)
        playId = nil
        transcodeBaseSeconds = 0
    }

    private func stopTranscodeAPI(playId id: String) async {
        let api = APIClient.shared
        _ = await api.apiPost(
            "/api/videoPlayer/stop",
            body: ["playId": id],
            dataParser: { _, _ in [String: Any]() }
        )
        // 服务端 return 200 后进程可能仍在退出，稍作延迟再起新转码，避免多进程
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
    }

    func attachDrawableView(_ view: UIView) {
        drawableView = view
        if let playerView = player?.view {
            attachPlayerView(playerView, to: view)
        }
    }

    private func attachPlayerView(_ playerView: UIView, to container: UIView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        playerView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: container.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    func start() {
        guard !playlist.isEmpty else { return }
        Task {
            await loadCurrentItem(seekSeconds: initialSeekSeconds, keepQuality: false)
        }
    }

    private func currentItem() -> TVVideoPlaylistItem? {
        guard currentIndex >= 0, currentIndex < playlist.count else { return nil }
        return playlist[currentIndex]
    }

    /// 与 Flutter `currentSourcePathForInfo()` 一致：如果 path 是 URL（含 filePath/path query），取 query 值；否则直接返回 path
    private func currentSourcePathForInfo() -> String {
        let raw = currentItem()?.path.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "" }
        guard
            let url = URL(string: raw),
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = comps.queryItems
        else { return raw }
        if let v = items.first(where: { $0.name == "filePath" })?.value, !v.isEmpty { return v }
        if let v = items.first(where: { $0.name == "path" })?.value, !v.isEmpty { return v }
        return raw
    }

    /// 当前正在播放的文件名（从 path 取最后一段，供顶部标题栏显示）
    var currentItemFileName: String {
        let path = currentItem()?.path ?? ""
        return (path as NSString).lastPathComponent
    }

    // MARK: - Subtitle Search (Thunder service)

    fileprivate func searchSubtitles(searchType: String, keyword: String? = nil) async -> [TVSubtitleSearchItem] {
        let filePath = currentSourcePathForInfo()
        guard !filePath.isEmpty else { return [] }

        var body: [String: Any] = [
            "filePath": filePath,
            "searchType": searchType
        ]
        let kw = (keyword ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            body["keyword"] = kw
        }

        let api = APIClient.shared
        let response: APIResponse<[String: Any]> = await api.apiPost(
            "/api/videoPlayer/searchSubtitle",
            body: body,
            dataParser: { data, _ in data }
        )
        guard response.success, let data = response.data else { return [] }
        let items = data["items"] as? [Any] ?? []
        return items.compactMap { any in
            guard let m = any as? [String: Any] else { return nil }
            let sname = (m["sname"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (m["displayName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let language = (m["language"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let surl = (m["surl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ext = (m["ext"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !surl.isEmpty else { return nil }
            return TVSubtitleSearchItem(sname: sname, displayName: displayName, language: language, surl: surl, ext: ext)
        }
    }

    fileprivate func downloadSearchedSubtitle(item: TVSubtitleSearchItem) async throws -> (savedPath: String, filename: String) {
        let filePath = currentSourcePathForInfo()
        guard !filePath.isEmpty else { throw NSError(domain: "TVVideoPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("player_cannot_get_video_path")]) }
        guard !item.surl.isEmpty else { throw NSError(domain: "TVVideoPlayer", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("operation_failed")]) }

        let body: [String: Any] = [
            "filePath": filePath,
            "surl": item.surl,
            "sname": item.sname,
            "language": item.language
        ]

        let api = APIClient.shared
        let response: APIResponse<[String: Any]> = await api.apiPost(
            "/api/videoPlayer/downloadSearchedSubtitle",
            body: body,
            dataParser: { data, _ in data }
        )
        guard response.success, let data = response.data else {
            throw NSError(domain: "TVVideoPlayer", code: 3, userInfo: [NSLocalizedDescriptionKey: response.message])
        }
        let savedPath = (data["path"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = (data["filename"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !savedPath.isEmpty, !filename.isEmpty else {
            throw NSError(domain: "TVVideoPlayer", code: 4, userInfo: [NSLocalizedDescriptionKey: L10n.tr("operation_failed")])
        }
        return (savedPath, filename)
    }

    /// 将下载完成的外挂字幕加入列表并立刻应用（对齐 Flutter “下载后立刻出现并选中”体验）
    func addAndSelectExternalSubtitle(savedPath: String, filename: String) {
        let p = savedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !name.isEmpty else { return }

        // 去重：若已存在同 path 的外挂字幕，不重复插入
        if availableSubtitleTracks.contains(where: { $0.isExternal && ($0.externalPath ?? "") == p }) == false {
            availableSubtitleTracks.insert(
                .init(kind: .subtitle, index: -1, mapIndex: -1, label: name, isExternal: true, externalPath: p, codecName: nil),
                at: 0
            )
        }

        if let match = availableSubtitleTracks.first(where: { $0.isExternal && ($0.externalPath ?? "") == p }) {
            changeSubtitleTrack(to: match)
        } else {
            // fallback: 按 label 选择
            changeSubtitleTrack(to: availableSubtitleTracks.first(where: { $0.label == name }) ?? selectedSubtitleTrack)
        }
    }

    private func fetchStreamInfoIfNeeded(for path: String) async {
        // 与 Flutter _fetchStreamInfo 保持一致：解析出用于请求 /info 的 filePath
        let apiFilePath: String = {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = comps.queryItems,
                  ["filePath", "path"].contains(where: { name in items.contains(where: { $0.name == name }) })
            else {
                return path
            }
            if let v = items.first(where: { $0.name == "filePath" })?.value ?? items.first(where: { $0.name == "path" })?.value {
                return v
            }
            return path
        }()

        // 换片后需重新拉取该片的流信息与偏好
        if apiFilePath != lastFetchedStreamInfoPath {
            sourceDurationSeconds = nil
            availableAudioTracks = []
            availableSubtitleTracks = []
            lastFetchedPreference = nil
        }
        guard sourceDurationSeconds == nil || availableAudioTracks.isEmpty || availableSubtitleTracks.isEmpty else {
            return
        }

        let api = APIClient.shared
        let response: APIResponse<[String: Any]> = await api.apiGet(
            "/api/videoPlayer/info",
            queryParams: ["filePath": apiFilePath, "ignoreFindSub": "\(ignoreFindSub)"],
            dataParser: { data, _ in data }
        )
        guard response.success, let data = response.data else { return }

        var durationSecs: Int = 0
        if let d = data["duration"] as? NSNumber {
            durationSecs = d.intValue
        } else if let d = data["duration"] as? Double {
            durationSecs = Int(d.rounded())
        } else if let s = data["duration"] as? String, let v = Int(s) {
            durationSecs = v
        }
        sourceDurationSeconds = max(0, durationSecs)

        var audioTracks: [TVVideoStreamInfo.Track] = []
        var subtitleTracks: [TVVideoStreamInfo.Track] = []

        let streams = data["streams"] as? [Any] ?? []
        var audioOrder = 0
        var subtitleOrder = 0
        for any in streams {
            guard let s = any as? [String: Any] else { continue }
            let codecType = (s["codec_type"] as? String ?? "").lowercased()
            let index = (s["index"] as? NSNumber)?.intValue ?? 0
            let tags = s["tags"] as? [String: Any] ?? [:]
            let lang = (tags["language"] as? String ?? "und")
            let title = (tags["title"] as? String) ?? (s["codec_name"] as? String ?? "")
            let codecName = s["codec_name"] as? String

            if codecType == "audio" {
                let label = "Audio \(index) (\(lang)) - \(title)"
                audioTracks.append(
                    .init(
                        kind: .audio,
                        index: index,
                        mapIndex: audioOrder,
                        label: label,
                        isExternal: false,
                        externalPath: nil,
                        codecName: codecName
                    )
                )
                audioOrder += 1
            } else if codecType == "subtitle" {
                let display = "(\(lang)) \(title)"
                subtitleTracks.append(
                    .init(
                        kind: .subtitle,
                        index: index,
                        mapIndex: subtitleOrder,
                        label: display,
                        isExternal: false,
                        externalPath: nil,
                        codecName: codecName
                    )
                )
                subtitleOrder += 1
            }
        }

        if let external = data["externalSubtitles"] as? [Any] {
            for any in external {
                guard let sub = any as? [String: Any] else { continue }
                let path = sub["path"] as? String
                let filename = sub["filename"] as? String ?? ""
                let label = filename.isEmpty ? (path ?? "") : filename
                subtitleTracks.insert(
                    .init(
                        kind: .subtitle,
                        index: -1,
                        mapIndex: -1,
                        label: label,
                        isExternal: true,
                        externalPath: path,
                        codecName: nil
                    ),
                    at: 0
                )
            }
        }

        // 解析服务端返回的偏好（登录用户），用于还原音轨/字幕/进度
        var pref: VideoPreference?
        if let prefs = data["preference"] as? [String: Any] {
            let pos: Int = {
                if let n = prefs["playback_position"] as? NSNumber { return n.intValue }
                if let n = prefs["playback_position"] as? Int { return n }
                if let d = prefs["playback_position"] as? Double { return Int(d) }
                return 0
            }()
            let audioL = prefs["audio_label"] as? String
            let subL = prefs["subtitle_label"] as? String
            pref = VideoPreference(playbackPosition: max(0, pos), audioLabel: audioL?.isEmpty == false ? audioL : nil, subtitleLabel: subL?.isEmpty == false ? subL : nil)
        }
        lastFetchedPreference = pref

        availableAudioTracks = audioTracks
        availableSubtitleTracks = subtitleTracks

        // 应用偏好中的音轨/字幕轨（按 label 匹配）
        if selectedAudioTrack == nil {
            if let label = pref?.audioLabel, let match = audioTracks.first(where: { $0.label == label }) {
                selectedAudioTrack = match
            } else {
                selectedAudioTrack = audioTracks.first
            }
        }
        if selectedSubtitleTrack == nil {
            if let label = pref?.subtitleLabel, let match = subtitleTracks.first(where: { $0.label == label }) {
                selectedSubtitleTrack = match
            } else {
                selectedSubtitleTrack = subtitleTracks.first
            }
        }

        lastFetchedStreamInfoPath = apiFilePath
    }

    private func buildPlaybackURLAndOptions(
        for path: String,
        seekSeconds: Int
    ) async -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[P2P] TVVideoPlayerViewModel: buildMedia path empty")
            return nil
        }
        print("[P2P] TVVideoPlayerViewModel: buildMedia start path=\(trimmed.prefix(60))... quality=\(currentQuality) seek=\(seekSeconds)")

        await fetchStreamInfoIfNeeded(for: trimmed)

        if currentQuality == "original" {
            transcodeBaseSeconds = 0
            guard let url = TVVideoPlaybackURLBuilder.buildOriginalVideoURL(path: trimmed) else {
                print("[P2P] TVVideoPlayerViewModel: buildMedia buildOriginalURL returned nil")
                return nil
            }
            print("[P2P] TVVideoPlayerViewModel: buildMedia original url=\(url.absoluteString.prefix(80))...")
            return url
        } else {
            transcodeBaseSeconds = seekSeconds
            if playId == nil {
                playId = UUID().uuidString
            }
            guard
                let pid = playId,
                let url = TVVideoPlaybackURLBuilder.buildTranscodeURL(
                    path: trimmed,
                    playId: pid,
                    seekSeconds: seekSeconds,
                    quality: currentQuality,
                    selectedAudio: selectedAudioTrack,
                    selectedSubtitle: selectedSubtitleTrack
                )
            else {
                print("[P2P] TVVideoPlayerViewModel: buildMedia buildTranscodeURL returned nil")
                return nil
            }
            print("[P2P] TVVideoPlayerViewModel: buildMedia transcode url=\(url.absoluteString.prefix(80))...")
            return url
        }
    }

    // MARK: - FSPlayer setup & observers
    
    private func setupFSPlayer(url: URL, startSeconds: Int) {
        // 清理旧播放器
        if let old = player {
            removeFSObservers(for: old)
            old.shutdown()
        }
        
        let options = FSOptions.byDefault()
        options.metalRenderer = true
        options.automaticallySetupAudioSession = true
        options.currentPlaybackTimeNotificationInterval = 0.5
        
        let content = url.absoluteString
        let p = FSPlayer(content: content, options: options)
        player = p
        
        // 显示相关
        p.scalingMode = .aspectFit
        p.shouldAutoplay = true
        
        // 字幕样式：FS 内建字幕 + 自定义字体
        var sp = p.subtitlePreference
        sp.Scale = Float(subtitleFontSize.scaleValue)
        sp.BottomMargin = 0.05
        // 如果项目中已添加 NotoSansSC-Regular.ttf，则强制使用该字体（避免中文乱码）
        if let fontURL = Bundle.main.url(forResource: "NotoSansSC-Regular", withExtension: "ttf") {
            sp.ForceOverride = 1
            // 1) 字体目录
            let dirPath = fontURL.deletingLastPathComponent().path
            dirPath.withCString { cstr in
                withUnsafeMutableBytes(of: &sp.FontsDir) { rawBuf in
                    let buf = rawBuf.bindMemory(to: CChar.self)
                    let maxCount = buf.count
                    let len = strlen(cstr)
                    let copyCount = min(Int(len), maxCount - 1)
                    if copyCount > 0 {
                        memcpy(buf.baseAddress, cstr, copyCount)
                        buf.baseAddress?[copyCount] = 0
                    }
                }
            }
            // 2) 字体名称（使用 PostScript 名称或 family 名称，这里先用文件名）
            let fontName = "NotoSansSC-Regular"
            fontName.withCString { cstr in
                withUnsafeMutableBytes(of: &sp.FontName) { rawBuf in
                    let buf = rawBuf.bindMemory(to: CChar.self)
                    let maxCount = buf.count
                    let len = strlen(cstr)
                    let copyCount = min(Int(len), maxCount - 1)
                    if copyCount > 0 {
                        memcpy(buf.baseAddress, cstr, copyCount)
                        buf.baseAddress?[copyCount] = 0
                    }
                }
            }
        }
        p.subtitlePreference = sp
        
        if let container = drawableView {
            attachPlayerView(p.view, to: container)
        }
        
        installFSObservers(for: p)
        
        if currentQuality == "original", startSeconds > 0 {
            pendingInitialSeekSeconds = startSeconds
        } else {
            pendingInitialSeekSeconds = nil
        }
        
        p.prepareToPlay()
    }

    func changeSubtitleFontSize(to size: SubtitleFontSize) {
        subtitleFontSize = size
        UserDefaults.standard.set(size.rawValue, forKey: Self.subtitleFontSizeDefaultsKey)
        guard let p = player else { return }
        var sp = p.subtitlePreference
        sp.Scale = Float(size.scaleValue)
        p.subtitlePreference = sp
    }
    
    private func installFSObservers(for player: FSPlayer) {
        let center = NotificationCenter.default
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerIsPreparedToPlay,
                object: player,
                queue: .main
            ) { [weak self] note in
                self?.fs_mediaIsPreparedToPlay(note)
            }
        )
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerPlaybackStateDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                self?.fs_playbackStateDidChange()
            }
        )
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerLoadStateDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                self?.fs_loadStateDidChange()
            }
        )
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerCurrentPlaybackTimeDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                self?.fs_currentTimeDidChange()
            }
        )
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerBufferingDidChange,
                object: player,
                queue: .main
            ) { [weak self] _ in
                self?.fs_bufferingDidChange()
            }
        )
        
        fsObservers.append(
            center.addObserver(
                forName: NSNotification.Name.FSPlayerDidFinish,
                object: player,
                queue: .main
            ) { [weak self] note in
                self?.fs_didFinish(note)
            }
        )
    }
    
    private func removeFSObservers(for player: FSPlayer) {
        let center = NotificationCenter.default
        fsObservers.forEach { center.removeObserver($0) }
        fsObservers.removeAll()
    }

    /// 用 Task.detached 在后台等待上一 load 完成，再在 MainActor 执行 impl，避免 MainActor 上嵌套 Task 导致新 load 不调度
    private func loadCurrentItem(seekSeconds: Int, keepQuality: Bool) async {
        let previousTask = loadTask
        let seek = seekSeconds
        let keep = keepQuality
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await previousTask?.value
            await Task { @MainActor [weak self] in
                guard let self else { return }
                await self.loadCurrentItemImpl(seekSeconds: seek, keepQuality: keep)
            }.value
        }
        loadTask = task
    }

    private func loadCurrentItemImpl(seekSeconds: Int, keepQuality: Bool) async {
        guard let item = currentItem() else { return }
        print("[P2P] TVVideoPlayerViewModel: loadCurrentItemImpl start path=\(item.path.prefix(60))... index=\(currentIndex)")

        isLoading = true

        // 先拉取流信息与偏好，再决定起始 seek（用于还原上次进度）
        await fetchStreamInfoIfNeeded(for: item.path)

        // 首次加载该文件且未手动指定 seek 时，使用服务端偏好的播放进度（从照片模块进入时忽略历史）
        // 10 分钟以内的视频，或历史记录距离结束少于 10 分钟，都不自动跳历史进度
        let minDurationForResumeSeconds = 10 * 60
        var targetSeek = max(0, seekSeconds)
        if !ignorePlaybackHistory, lastAppliedPreferenceSeekPath != item.path, let pref = lastFetchedPreference, pref.playbackPosition > 0 {
            let totalSec = sourceDurationSeconds ?? 0
            let distanceToEnd = totalSec > 0 ? (totalSec - pref.playbackPosition) : 0
            if totalSec > minDurationForResumeSeconds, distanceToEnd >= minDurationForResumeSeconds {
                targetSeek = pref.playbackPosition
                lastAppliedPreferenceSeekPath = item.path
            }
        }

        // 重新转码前先停止当前转码会话（Flutter _initializePlayer 中先 _stopTranscoding(playId: prevPlayId)）
        if let pid = playId {
            await stopTranscodeAPI(playId: pid)
            playId = nil
        }

        if !keepQuality {
            currentQuality = VideoPlaybackSettings.loadDefaultQuality()
            playId = nil
        }

        guard let url = await buildPlaybackURLAndOptions(for: item.path, seekSeconds: targetSeek) else {
            print("[P2P] TVVideoPlayerViewModel: loadCurrentItemImpl buildMedia nil, stop loading")
            isLoading = false
            return
        }
        
        print("[P2P] TVVideoPlayerViewModel: loadCurrentItemImpl media built, calling FSPlayer")
        let startSec: Int = {
            if currentQuality == "original" { return targetSeek }
            return 0
        }()
        setupFSPlayer(url: url, startSeconds: startSec)
        isPlaying = true

        if currentQuality != "original", let total = sourceDurationSeconds, total > 0 {
            duration = TimeInterval(total)
        }

        if useClientSubtitleOverlay() {
            await loadClientSubtitleIfNeeded(force: true)
        } else {
            clearClientSubtitle()
        }
    }

    // MARK: - Client subtitle overlay (transcode text subs, aligned with Flutter)

    private func useClientSubtitleOverlay() -> Bool {
        guard currentQuality != "original" else { return false }
        guard let track = selectedSubtitleTrack else { return false }
        return !TVVideoPlaybackURLBuilder.subtitleTrackNeedsTranscodeBurn(track)
    }

    private func clearClientSubtitle() {
        clientSubtitleCues = []
        clientSubtitleCacheKey = ""
        clientSubtitleText = ""
    }

    private func updateClientSubtitleCue() {
        guard useClientSubtitleOverlay() else {
            if !clientSubtitleText.isEmpty { clearClientSubtitle() }
            return
        }
        let posMs = Int64(max(0, position) * 1000.0)
        let text =
            WebVttParser.findActiveCue(clientSubtitleCues, positionMs: posMs)?
                .text
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        clientSubtitleText = text
    }

    private func loadClientSubtitleIfNeeded(force: Bool = false) async {
        guard useClientSubtitleOverlay(),
              let track = selectedSubtitleTrack,
              let item = currentItem()
        else {
            clearClientSubtitle()
            return
        }

        let idx = track.mapIndex
        let subPath = track.externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = track.isExternal ? "ext:\(subPath)#\(idx)" : "emb:\(item.path)#\(idx)"
        if !force, key == clientSubtitleCacheKey, !clientSubtitleCues.isEmpty {
            updateClientSubtitleCue()
            return
        }
        if clientSubtitleLoading { return }
        clientSubtitleLoading = true
        clientSubtitleCacheKey = key
        defer { clientSubtitleLoading = false }

        var params: [String: String] = [:]
        params["subtitleIndex"] = "\(max(0, idx))"
        if track.isExternal {
            guard !subPath.isEmpty else {
                clearClientSubtitle()
                return
            }
            params["subtitlePath"] = subPath
        } else {
            params["filePath"] = item.path
        }
        if let token = APIClient.shared.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            params["accessToken"] = token
        }

        guard let vtt = await APIClient.shared.fetchPlainText("/api/videoPlayer/subtitle-vtt", queryParams: params) else {
            clearClientSubtitle()
            return
        }
        clientSubtitleCues = WebVttParser.parseWebVtt(vtt)
        updateClientSubtitleCue()
    }

    private func applySubtitleTrackWhileTranscoding(previous: TVVideoStreamInfo.Track?) async {
        let prevBurn = previous.map { TVVideoPlaybackURLBuilder.subtitleTrackNeedsTranscodeBurn($0) } ?? false
        let nextBurn = selectedSubtitleTrack.map { TVVideoPlaybackURLBuilder.subtitleTrackNeedsTranscodeBurn($0) } ?? false

        if prevBurn, !nextBurn {
            let sec = Int(position)
            await loadCurrentItem(seekSeconds: sec, keepQuality: true)
            await loadClientSubtitleIfNeeded(force: true)
            return
        }

        if selectedSubtitleTrack != nil, nextBurn {
            let sec = Int(position)
            await loadCurrentItem(seekSeconds: sec, keepQuality: true)
            return
        }

        if selectedSubtitleTrack == nil {
            clearClientSubtitle()
            return
        }

        await loadClientSubtitleIfNeeded(force: true)
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying() {
            p.pause()
        } else {
            p.play()
        }
        isPlaying = p.isPlaying()
    }

    func seek(by seconds: TimeInterval) {
        if currentQuality != "original" {
            let totalSec = (sourceDurationSeconds ?? 0) > 0 ? sourceDurationSeconds! : Int(duration)
            let currentSec = Int(position)
            let targetSec = max(0, min(currentSec + Int(seconds), totalSec > 0 ? totalSec : Int.max))
            scheduleSeekDebounce(seekSeconds: targetSec)
            return
        }
        guard let p = player else { return }
        let currentSec = p.currentPlaybackTime
        let target = max(0, currentSec + seconds)
        p.currentPlaybackTime = target
    }

    /// 隐藏控制栏时用于方向键快进预览：按下立即显示，按住持续变化，松开后再 seek
    fileprivate func beginDirectionalScrub(by seconds: TimeInterval) {
        guard duration > 0 else { return }

        if directionalScrubStepSeconds != seconds {
            directionalScrubTask?.cancel()
            directionalScrubTask = nil
        }
        directionalScrubStepSeconds = seconds

        applyDirectionalScrubStep(seconds)

        guard directionalScrubTask == nil else { return }
        directionalScrubTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            while !Task.isCancelled {
                self.applyDirectionalScrubStep(seconds)
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }
    }

    fileprivate func endDirectionalScrub(by seconds: TimeInterval) {
        guard directionalScrubStepSeconds == seconds else { return }
        directionalScrubTask?.cancel()
        directionalScrubTask = nil
        directionalScrubStepSeconds = nil

        guard let finalPos = scrubbingPosition, duration > 0 else { return }
        let progress = finalPos / max(duration, 0.1)
        seek(to: progress)
        scrubbingPosition = nil
    }

    fileprivate func cancelDirectionalScrub() {
        directionalScrubTask?.cancel()
        directionalScrubTask = nil
        directionalScrubTapSettleTask?.cancel()
        directionalScrubTapSettleTask = nil
        directionalScrubStepSeconds = nil
        scrubbingPosition = nil
    }

    /// `onMoveCommand` 无法拿到抬起事件：用于点击的兜底（短暂停止后提交一次 seek）
    fileprivate func handleDirectionalScrubTap(by seconds: TimeInterval) {
        guard duration > 0 else { return }
        guard showControls == false, inputOverlayActive == false else { return }

        applyDirectionalScrubStep(seconds)

        directionalScrubTapSettleTask?.cancel()
        directionalScrubTapSettleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard self.showControls == false, self.inputOverlayActive == false else { return }
            guard let finalPos = self.scrubbingPosition, self.duration > 0 else { return }
            let progress = finalPos / max(self.duration, 0.1)
            self.seek(to: progress)
            self.scrubbingPosition = nil
        }
    }

    func setOverlayActive(_ active: Bool) {
        inputOverlayActive = active
        if active {
            // overlay 出现时应立即停掉隐藏态方向键逻辑（不触发 seek）
            cancelDirectionalScrub()
            gcActiveDirection = 0
            gcPendingDirection = 0
            gcLongPressTask?.cancel()
            gcLongPressTask = nil
        }
    }

    // MARK: - GameController remote input

    func startRemoteMonitoring() {
        guard gcObservers.isEmpty else { return }

        GCController.controllers().forEach { configureController($0) }

        let center = NotificationCenter.default
        gcObservers.append(
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.configureController(controller)
            }
        )
        gcObservers.append(
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.handleControllerDisconnected(controller)
            }
        )

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        print("[GC] startRemoteMonitoring controllers=\(GCController.controllers().count)")
    }

    func stopRemoteMonitoring() {
        gcObservers.forEach { NotificationCenter.default.removeObserver($0) }
        gcObservers.removeAll()
        gcActiveDirection = 0
        gcPendingDirection = 0
        gcLongPressTask?.cancel()
        gcLongPressTask = nil
        gcLeftPressed = false
        gcRightPressed = false
        gcLastX = 0
        print("[GC] stopRemoteMonitoring")
    }

    private func configureController(_ controller: GCController) {
        guard let pad = controller.microGamepad else {
            return
        }
        pad.reportsAbsoluteDpadValues = true
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.handleMicroGamepadDpad(x: x, y: y, controller: controller)
        }
        let name = controller.vendorName ?? "unknown"
        print("[GC] configured microGamepad vendor=\(name)")
    }

    private func handleControllerDisconnected(_ controller: GCController) {
        let name = controller.vendorName ?? "unknown"
        print("[GC] disconnected vendor=\(name)")
        if gcActiveDirection != 0 {
            let dir = gcActiveDirection
            gcActiveDirection = 0
            if dir < 0 {
                endDirectionalScrub(by: -30)
            } else if dir > 0 {
                endDirectionalScrub(by: 30)
            }
        }
    }

    private func handleMicroGamepadDpad(x: Float, y: Float, controller: GCController) {
        // 打印原始值（调试用）：无论控制栏是否显示，都先确认遥控输入是否进来了
        if abs(x - gcLastX) > 0.02 {
            gcLastX = x
            let name = controller.vendorName ?? "unknown"
            print("[GC] dpad vendor=\(name) x=\(String(format: "%.2f", x)) y=\(String(format: "%.2f", y)) showControls=\(showControls) overlay=\(inputOverlayActive)")
        }

        // 只在控制栏隐藏且无其他 overlay 时执行预览/seek
        guard showControls == false, inputOverlayActive == false else {
            if gcActiveDirection != 0 {
                let dir = gcActiveDirection
                gcActiveDirection = 0
                if dir < 0 { endDirectionalScrub(by: -30) }
                if dir > 0 { endDirectionalScrub(by: 30) }
            }
            return
        }

        let threshold: Float = 0.6
        let leftPressed = x <= -threshold
        let rightPressed = x >= threshold

        var newDir = 0
        if leftPressed { newDir = -1 }
        if rightPressed { newDir = 1 }

        if newDir == gcActiveDirection {
            return
        }

        let old = gcActiveDirection
        gcActiveDirection = newDir

        if old < 0 {
            endDirectionalScrub(by: -30)
        } else if old > 0 {
            endDirectionalScrub(by: 30)
        }

        if newDir < 0 {
            beginDirectionalScrub(by: -30)
        } else if newDir > 0 {
            beginDirectionalScrub(by: 30)
        }
    }

    private func applyDirectionalScrubStep(_ seconds: TimeInterval) {
        guard duration > 0 else { return }
        let base = scrubbingPosition ?? position
        let clampedBase = max(0, min(base, duration))
        let targetPos = max(0, min(clampedBase + seconds, duration))
        scrubbingPosition = targetPos
    }

    func seek(to progress: Double) {
        guard progress.isFinite, progress >= 0, progress <= 1 else { return }
        if currentQuality != "original" {
            let totalSec = sourceDurationSeconds ?? Int(duration)
            guard totalSec > 0 else { return }
            let targetSec = Int(Double(totalSec) * progress)
            scheduleSeekDebounce(seekSeconds: targetSec)
            return
        }
        guard duration > 0, let p = player else { return }
        let target = duration * progress
        p.currentPlaybackTime = target
    }

    /// 转码下快进/快退防抖：连续操作只触发最后一次，300ms 无新操作后执行 load
    private func scheduleSeekDebounce(seekSeconds: Int) {
        pendingSeekSeconds = seekSeconds
        seekDebounceTask?.cancel()
        seekDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard let self else { return }
            let sec = self.pendingSeekSeconds
            self.pendingSeekSeconds = nil
            self.seekDebounceTask = nil
            if let s = sec {
                await self.loadCurrentItem(seekSeconds: s, keepQuality: true)
            }
        }
    }

    func playNext() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        Task { await loadCurrentItem(seekSeconds: 0, keepQuality: false) }
    }

    func playPrevious() {
        guard !playlist.isEmpty else { return }
        currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        Task { await loadCurrentItem(seekSeconds: 0, keepQuality: false) }
    }

    func changeQuality(to quality: String) {
        guard qualityOptions.contains(quality) else { return }
        if currentQuality == quality { return }
        currentQuality = quality

        let currentSeconds = Int(position)
        Task { await loadCurrentItem(seekSeconds: currentSeconds, keepQuality: true) }
    }

    fileprivate func changeAudioTrack(to track: TVVideoStreamInfo.Track?) {
        selectedAudioTrack = track
        if currentQuality == "original" {
            if let t = track {
                player?.exchangeSelectedStream(Int32(t.index))
            } else {
                player?.closeCurrentStream(FS_VAL_TYPE__AUDIO)
            }
        } else {
            let currentSeconds = Int(position)
            Task { await loadCurrentItem(seekSeconds: currentSeconds, keepQuality: true) }
        }
        saveVideoPreference()
    }
    
    fileprivate func changeSubtitleTrack(to track: TVVideoStreamInfo.Track?) {
        let previous = selectedSubtitleTrack
        selectedSubtitleTrack = track
        if currentQuality == "original" {
            guard let p = player else {
                saveVideoPreference()
                return
            }
            if let t = track {
                if t.isExternal {
                    if let path = t.externalPath,
                       let url = TVVideoPlaybackURLBuilder.buildOriginalURL(path: path) {
                        _ = p.loadThenActiveSubtitle(url)
                    }
                } else {
                    p.exchangeSelectedStream(Int32(t.index))
                }
            } else {
                p.closeCurrentStream(FS_VAL_TYPE__SUBTITLE)
            }
        } else {
            Task { await applySubtitleTrackWhileTranscoding(previous: previous) }
        }
        saveVideoPreference()
    }

    func changeSpeed(to speed: Float) {
        let clamped = max(0.5, min(2.0, speed))
        playbackSpeed = clamped
        player?.playbackRate = clamped
    }

    func userInteracted() {
        showControls = true
        scheduleHideControls()
    }

    /// 隐藏控制栏（如按返回键时），并取消自动隐藏定时
    func hideControls() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        showControls = false
    }

    private func scheduleHideControls() {
        hideControlsWorkItem?.cancel()
        guard isPlaying else {
            hideControlsWorkItem = nil
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.showControls = false
        }
        hideControlsWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - FSPlayer notifications
    
    private func fs_mediaIsPreparedToPlay(_ note: Notification) {
        guard let p = player, note.object as AnyObject? === p else { return }
        if let sec = pendingInitialSeekSeconds {
            pendingInitialSeekSeconds = nil
            p.currentPlaybackTime = TimeInterval(sec)
        }
        // 原画模式下，播放器准备好后应用当前选择的音轨和字幕轨（含外挂字幕）
        if currentQuality == "original" {
            applyCurrentTracksToFSPlayer()
        }
    }

    /// 将当前 viewModel 中记录的音轨/字幕轨应用到 FSPlayer（用于初次加载或重新加载）
    private func applyCurrentTracksToFSPlayer() {
        guard let p = player else { return }

        // 音轨：根据 streams 的 index 选择对应流
        if let audio = selectedAudioTrack {
            p.exchangeSelectedStream(Int32(audio.index))
        } else {
            p.closeCurrentStream(FS_VAL_TYPE__AUDIO)
        }

        // 字幕：支持内嵌和外挂字幕
        if let sub = selectedSubtitleTrack {
            if sub.isExternal {
                if let path = sub.externalPath,
                   let url = TVVideoPlaybackURLBuilder.buildOriginalURL(path: path) {
                    _ = p.loadThenActiveSubtitle(url)
                }
            } else {
                p.exchangeSelectedStream(Int32(sub.index))
            }
        } else {
            p.closeCurrentStream(FS_VAL_TYPE__SUBTITLE)
        }
    }
    
    private func fs_playbackStateDidChange() {
        guard let p = player else { return }
        let nowPlaying = p.playbackState == .playing
        if isPlaying != nowPlaying {
            isPlaying = nowPlaying
            if nowPlaying {
                startPreferenceSaveTimer()
                // 播放中禁用系统休眠/屏保，保持常亮
                UIApplication.shared.isIdleTimerDisabled = true
            } else {
                stopPreferenceSaveTimer()
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        isLoading = false
        if isPlaying, showControls {
            scheduleHideControls()
        }
    }
    
    private func fs_loadStateDidChange() {
        guard let p = player else { return }
        let state = p.loadState
        if state.contains(.playthroughOK) {
            isLoading = false
        } else if state.contains(.stalled) {
            isLoading = true
        }
        if isPlaying, showControls {
            scheduleHideControls()
        }
    }
    
    private func fs_currentTimeDidChange() {
        guard let p = player else { return }
        if currentQuality != "original" {
            position = TimeInterval(transcodeBaseSeconds) + p.currentPlaybackTime
            if let total = sourceDurationSeconds, total > 0 {
                duration = TimeInterval(total)
            } else if p.duration > 0 {
                duration = p.duration
            }
        } else {
            position = p.currentPlaybackTime
            if p.duration > 0 {
                duration = p.duration
            }
        }
        updateClientSubtitleCue()
        if position.isFinite, position >= 0 {
            lastKnownPositionSeconds = Int(position)
        }
        if duration.isFinite, duration > 0 {
            lastKnownDurationSeconds = Int(duration)
        }
    }
    
    private func fs_bufferingDidChange() {
        guard let p = player else { return }
        buffered = p.playableDuration
    }
    
    private func fs_didFinish(_ note: Notification) {
        isPlaying = false
        isLoading = false
        UIApplication.shared.isIdleTimerDisabled = false
        
        let reasonRaw = (note.userInfo?[FSPlayerDidFinishReasonUserInfoKey] as? NSNumber)?.intValue
        let reason = FSFinishReason(rawValue: reasonRaw ?? FSFinishReason.playbackEnded.rawValue) ?? .playbackEnded
        
        if reason == .playbackError {
            let resumePos = lastKnownPositionSeconds
            print("[P2P] TVVideoPlayerViewModel: finish with error reason retry=\(playRetryCount) resumePos=\(resumePos)")
            if playRetryCount < 3 {
                playRetryCount += 1
                isLoading = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if APIClient.shared.isP2pMode {
                        _ = await P2PService.shared.ensureConnected(timeout: 15)
                    }
                    await self.loadCurrentItem(seekSeconds: resumePos, keepQuality: true)
                }
                return
            } else {
                return
            }
        }
        
        let dur = lastKnownDurationSeconds
        let pos = lastKnownPositionSeconds
        let isPrematureEnd = (dur != nil && dur! > 0 && pos + 5 < dur!)
        if isPrematureEnd {
            print("[P2P] TVVideoPlayerViewModel: premature end pos=\(pos) dur=\(dur ?? 0) retry=\(playRetryCount)")
            if playRetryCount < 3 {
                playRetryCount += 1
                isLoading = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if APIClient.shared.isP2pMode {
                        _ = await P2PService.shared.ensureConnected(timeout: 15)
                    }
                    await self.loadCurrentItem(seekSeconds: pos, keepQuality: true)
                }
                return
            } else {
                return
            }
        }
        
        playRetryCount = 0
        playNext()
    }

    // MARK: - 播放偏好保存与定时

    /// 仅当 path 为本地/网络文件路径时保存（非 http(s) URL 源）
    private func shouldSavePreference(for path: String) -> Bool {
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !p.hasPrefix("http://") && !p.hasPrefix("https://")
    }

    /// 保存当前播放进度与音轨/字幕选择到服务端，供下次还原。前次未完成时直接返回，不积压。
    func saveVideoPreference() {
        guard !isPreferenceSaveInFlight else { return }
        guard let item = currentItem(), shouldSavePreference(for: item.path) else { return }
        let path = item.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let pos = Int(position)
        let audioLabel = selectedAudioTrack?.label
        let subtitleLabel = selectedSubtitleTrack?.label

        isPreferenceSaveInFlight = true
        Task { @MainActor in
            defer { self.isPreferenceSaveInFlight = false }
            let body: [String: Any] = [
                "filePath": path,
                "playback_position": pos,
                "subtitle_label": subtitleLabel as Any,
                "audio_label": audioLabel as Any,
            ]
            _ = await APIClient.shared.apiPost(
                "/api/videoPlayer/preference",
                body: body,
                dataParser: { _, _ in () as Void }
            )
        }
    }

    private func startPreferenceSaveTimer() {
        stopPreferenceSaveTimer()
        preferenceSaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying { self.saveVideoPreference() }
            }
        }
        preferenceSaveTimer?.tolerance = 2
        if let t = preferenceSaveTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopPreferenceSaveTimer() {
        preferenceSaveTimer?.invalidate()
        preferenceSaveTimer = nil
    }
}

// MARK: - 播放器菜单触发按钮（带焦点边框，避免 Menu 闪烁用自定义 overlay）

private struct PlayerMenuTriggerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.clear, lineWidth: 1.5)
            )
            .modifier(PlayerMenuTriggerFocusOverlay())
    }
}

private struct PlayerMenuTriggerFocusOverlay: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? Color.white.opacity(0.5) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - 控制栏隐藏时的 overlay（承接焦点与 move 命令）

private struct PlayerHiddenControlsOverlay: View {
    @ObservedObject var viewModel: TVVideoPlayerViewModel
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable(true)
            .focused(isFocused)
            .onAppear { isFocused.wrappedValue = true }
            .onTapGesture {
                viewModel.cancelDirectionalScrub()
                viewModel.userInteracted()
            }
            .onMoveCommand { direction in
                // 只用来唤起控制栏：隐藏态左右快进/快退仅由 GameController 的 press + 长按识别触发
                switch direction {
                case .up, .down:
                    viewModel.userInteracted()
                default:
                    break
                }
            }
    }
}

// MARK: - Drawable Container

private struct TVVideoPlayerDrawableView: UIViewRepresentable {
    @ObservedObject var viewModel: TVVideoPlayerViewModel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        viewModel.attachDrawableView(v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Main View

struct TVVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TVVideoPlayerViewModel

    @FocusState private var hiddenOverlayFocused: Bool

    private enum FocusField: Hashable {
        case play
        case prev
        case next
        case seekBackward
        case seekForward
        case quality
        case audio
        case subtitle
        case subtitleFont
        case speed
    }

    @FocusState private var focusedField: FocusField?
    @State private var lastMenuFocusedField: FocusField?

    @State private var showQualityPicker = false
    @State private var showAudioPicker = false
    @State private var showSubtitlePicker = false
    @State private var showSpeedPicker = false
    @State private var showSubtitleFontPicker = false
    @State private var showExitConfirm = false
    @State private var showSubtitleSearchSheet = false
    @State private var showServerVersionTooLowAlert = false

    private var isAnyOverlayShown: Bool {
        showQualityPicker || showAudioPicker || showSubtitlePicker || showSpeedPicker || showSubtitleFontPicker || showExitConfirm || showSubtitleSearchSheet
    }

    init(
        playlist: [TVVideoPlaylistItem],
        initialIndex: Int,
        initialSeekSeconds: Int = 0,
        ignorePlaybackHistory: Bool = false,
        ignoreFindSub: Int = 1
    ) {
        _viewModel = StateObject(
            wrappedValue: TVVideoPlayerViewModel(
                playlist: playlist,
                initialIndex: initialIndex,
                initialSeekSeconds: initialSeekSeconds,
                ignorePlaybackHistory: ignorePlaybackHistory,
                ignoreFindSub: ignoreFindSub
            )
        )
    }

    var body: some View {
        playerStack
            .background(Color.black.ignoresSafeArea())
        .onMoveCommand { direction in
            switch direction {
            case .up, .down:
                if viewModel.showControls && !isAnyOverlayShown {
                    viewModel.hideControls()
                    hiddenOverlayFocused = true
                } else {
                    viewModel.userInteracted()
                }
            case .left, .right:
                if viewModel.showControls && !isAnyOverlayShown {
                    viewModel.userInteracted()
                }
            default:
                if viewModel.showControls && !isAnyOverlayShown {
                    viewModel.userInteracted()
                }
            }
        }
        .onChange(of: isAnyOverlayShown) { shown in
            viewModel.setOverlayActive(shown)
        }
        .onExitCommand {
            if isAnyOverlayShown {
                showQualityPicker = false
                showAudioPicker = false
                showSubtitlePicker = false
                showSpeedPicker = false
            showSubtitleFontPicker = false
            } else if viewModel.showControls {
                viewModel.hideControls()
            } else {
                showExitConfirm = true
            }
        }
        .confirmationDialog(L10n.tr("player_exit_confirm_title"), isPresented: $showExitConfirm) {
            Button(L10n.tr("player_exit_confirm_title"), role: .destructive) {
                Task {
                    await viewModel.stopTranscodeIfNeeded()
                    dismiss()
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_exit_confirm_message"))
        }
        .confirmationDialog("", isPresented: $showQualityPicker) {
            ForEach(viewModel.qualityOptions, id: \.self) { q in
                Button {
                    viewModel.changeQuality(to: q)
                } label: {
                    HStack {
                        if viewModel.currentQuality == q {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                        Text(
                            viewModel.currentQuality == q
                                ? "\(labelForQuality(q)) · \(L10n.tr("current"))"
                                : labelForQuality(q)
                        )
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_quality_title"))
        }
        .confirmationDialog("", isPresented: $showAudioPicker) {
            Button {
                viewModel.changeAudioTrack(to: nil)
            } label: {
                HStack {
                    if viewModel.selectedAudioTrack == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                    Text(
                        viewModel.selectedAudioTrack == nil
                            ? "\(L10n.tr("player_audio_track_auto")) · \(L10n.tr("current"))"
                            : L10n.tr("player_audio_track_auto")
                    )
                }
            }
            ForEach(viewModel.availableAudioTracks, id: \.label) { track in
                Button {
                    viewModel.changeAudioTrack(to: track)
                } label: {
                    HStack {
                        if viewModel.selectedAudioTrack?.label == track.label {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                        Text(
                            viewModel.selectedAudioTrack?.label == track.label
                                ? "\(track.label) · \(L10n.tr("current"))"
                                : track.label
                        )
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_audio_title"))
        }
        .confirmationDialog("", isPresented: $showSubtitlePicker) {
            Button {
                showSubtitlePicker = false
                if !APIClient.shared.state.isServerMajorVersionAtLeast(6) {
                    showServerVersionTooLowAlert = true
                    return
                }
                showSubtitleSearchSheet = true
            } label: {
                Text(L10n.tr("player_subtitle_search"))
            }
            Button {
                viewModel.changeSubtitleTrack(to: nil)
            } label: {
                HStack {
                    if viewModel.selectedSubtitleTrack == nil {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                    Text(
                        viewModel.selectedSubtitleTrack == nil
                            ? "\(L10n.tr("player_subtitle_off")) · \(L10n.tr("current"))"
                            : L10n.tr("player_subtitle_off")
                    )
                }
            }
            ForEach(viewModel.availableSubtitleTracks, id: \.label) { track in
                Button {
                    viewModel.changeSubtitleTrack(to: track)
                } label: {
                    HStack {
                        if viewModel.selectedSubtitleTrack?.label == track.label {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                        Text(
                            viewModel.selectedSubtitleTrack?.label == track.label
                                ? "\(track.label) · \(L10n.tr("current"))"
                                : track.label
                        )
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_subtitle_title"))
        }
        .confirmationDialog("", isPresented: $showSpeedPicker) {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { s in
                Button {
                    viewModel.changeSpeed(to: Float(s))
                } label: {
                    HStack {
                        if abs(Double(viewModel.playbackSpeed) - s) < 0.001 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                        Text(
                            abs(Double(viewModel.playbackSpeed) - s) < 0.001
                                ? String(format: "%.2gx · %@", s, L10n.tr("current"))
                                : String(format: "%.2gx", s)
                        )
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_speed_title"))
        }
        .onChange(of: showQualityPicker) { if !$0, let f = lastMenuFocusedField { focusedField = f } }
        .onChange(of: showAudioPicker) { if !$0, let f = lastMenuFocusedField { focusedField = f } }
        .onChange(of: showSubtitlePicker) { if !$0, let f = lastMenuFocusedField { focusedField = f } }
        .onChange(of: showSpeedPicker) { if !$0, let f = lastMenuFocusedField { focusedField = f } }
        .sheet(isPresented: $showSubtitleSearchSheet) {
            TVSubtitleSearchSheet(viewModel: viewModel, isPresented: $showSubtitleSearchSheet)
        }
        .alert(L10n.tr("tip"), isPresented: $showServerVersionTooLowAlert) {
            Button(L10n.tr("ok"), role: .cancel) {}
        } message: {
            Text(L10n.tr("server_version_too_low"))
        }
        .confirmationDialog("", isPresented: $showSubtitleFontPicker) {
            ForEach(TVVideoPlayerViewModel.SubtitleFontSize.allCases, id: \.self) { size in
                Button {
                    viewModel.changeSubtitleFontSize(to: size)
                } label: {
                    HStack {
                        if size == viewModel.subtitleFontSize {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                        Text(
                            size == viewModel.subtitleFontSize
                                ? "\(labelForSubtitleFontSize(size)) · \(L10n.tr("current"))"
                                : labelForSubtitleFontSize(size)
                        )
                    }
                }
            }
            Button(L10n.tr("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("player_subtitle_font_title"))
        }
        .onChange(of: showSubtitleFontPicker) { if !$0, let f = lastMenuFocusedField { focusedField = f } }
        .onDisappear {
            viewModel.cancelDirectionalScrub()
            viewModel.stopRemoteMonitoring()
            Task { await viewModel.stopTranscodeIfNeeded() }
            // 退出播放器时恢复系统休眠，避免常亮影响其他场景
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var playerStack: some View {
        ZStack {
            TVVideoPlayerDrawableView(viewModel: viewModel)
                .ignoresSafeArea()
                .onAppear {
                    viewModel.start()
                    viewModel.setOverlayActive(isAnyOverlayShown)
                    viewModel.startRemoteMonitoring()
                }
                .onTapGesture {
                    viewModel.userInteracted()
                }

            if viewModel.isLoading {
                loadingOverlay
            }

            if viewModel.showControls && !isAnyOverlayShown {
                controlsAndTitleBar
            }

            if !viewModel.showControls && !isAnyOverlayShown {
                PlayerHiddenControlsOverlay(viewModel: viewModel, isFocused: $hiddenOverlayFocused)
            }

            if let scrubPos = viewModel.scrubbingPosition, !isAnyOverlayShown {
                scrubPositionHUD(scrubPos)
            }

            if !viewModel.clientSubtitleText.isEmpty {
                Text(viewModel.clientSubtitleText)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text(L10n.tr("loading"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    private var controlsAndTitleBar: some View {
        Group {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewModel.currentItemFileName)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, 5)
                            .padding(.bottom, 15)
                            .padding(.leading, 30)
                            .padding(.trailing, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: [.top, .leading, .trailing])
            .allowsHitTesting(false)

            VStack {
                Spacer()
                controlsBar
            }
            .padding(.bottom, 40)
            .padding(.horizontal, 80)
            .transition(.opacity)
        }
    }

    private func scrubPositionHUD(_ scrubPos: TimeInterval) -> some View {
        VStack {
            Text("\(format(time: scrubPos)) / \(format(time: viewModel.duration))")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var controlsBar: some View {
        VStack(spacing: 16) {
            progressView
            HStack(spacing: 24) {
                Button {
                    viewModel.togglePlayPause()
                    viewModel.userInteracted()
                } label: {
                    Image(
                        systemName: viewModel.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.system(size: 32, weight: .bold))
                }
                .buttonStyle(NCPlainFocusButtonStyle())
                .focused($focusedField, equals: .play)

                Button {
                    viewModel.playPrevious()
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 24, weight: .medium))
                }
                .buttonStyle(NCPlainFocusButtonStyle())
                .focused($focusedField, equals: .prev)

                Button {
                    viewModel.playNext()
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 24, weight: .medium))
                }
                .buttonStyle(NCPlainFocusButtonStyle())
                .focused($focusedField, equals: .next)

                Button {
                    viewModel.seek(by: -10)
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 24, weight: .medium))
                }
                .buttonStyle(NCPlainFocusButtonStyle())
                .focused($focusedField, equals: .seekBackward)

                Button {
                    viewModel.seek(by: 30)
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 24, weight: .medium))
                }
                .buttonStyle(NCPlainFocusButtonStyle())
                .focused($focusedField, equals: .seekForward)

                Spacer()

                Button {
                    lastMenuFocusedField = .quality
                    showQualityPicker = true
                    viewModel.userInteracted()
                } label: {
                    HStack(spacing: 6) {
                        Text(labelForQuality(viewModel.currentQuality))
                            .font(.footnote)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .modifier(PlayerMenuTriggerStyle())
                .focused($focusedField, equals: .quality)

                Button {
                    lastMenuFocusedField = .audio
                    showAudioPicker = true
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .modifier(PlayerMenuTriggerStyle())
                .focused($focusedField, equals: .audio)

                Button {
                    lastMenuFocusedField = .subtitle
                    showSubtitlePicker = true
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .modifier(PlayerMenuTriggerStyle())
                .focused($focusedField, equals: .subtitle)

                Button {
                    lastMenuFocusedField = .subtitleFont
                    showSubtitleFontPicker = true
                    viewModel.userInteracted()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .modifier(PlayerMenuTriggerStyle())
                .focused($focusedField, equals: .subtitleFont)

                Button {
                    lastMenuFocusedField = .speed
                    showSpeedPicker = true
                    viewModel.userInteracted()
                } label: {
                    Text(String(format: "%.1fx", viewModel.playbackSpeed))
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .modifier(PlayerMenuTriggerStyle())
                .focused($focusedField, equals: .speed)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.black.opacity(0.7))
        )
    }

    private var progressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // tvOS 无 Slider，用 ProgressView 仅展示进度；调节进度用下方 -10s / +30s 按钮
            ProgressView(
                value: {
                    guard viewModel.duration > 0, viewModel.position.isFinite else { return 0 }
                    let raw = viewModel.position / max(viewModel.duration, 0.1)
                    return min(max(raw, 0), 1)
                }(),
                total: 1.0
            )
            .progressViewStyle(.linear)
            .tint(.blue)

            HStack {
                Text(format(time: viewModel.position))
                    .font(.footnote)
                Spacer()
                Text(format(time: viewModel.duration))
                    .font(.footnote)
            }
        }
    }

    private func format(time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "00:00" }
        let totalSeconds = Int(time.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func labelForQuality(_ quality: String) -> String {
        if quality == "original" {
            return L10n.tr("player_quality_original")
        }
        return quality.uppercased()
    }

    private func labelForSubtitleFontSize(_ size: TVVideoPlayerViewModel.SubtitleFontSize) -> String {
        switch size {
        case .small:
            return L10n.tr("player_subtitle_font_small")
        case .medium:
            return L10n.tr("player_subtitle_font_medium")
        case .large:
            return L10n.tr("player_subtitle_font_large")
        }
    }

}

// MARK: - Subtitle Search Sheet (tvOS)

private struct TVSubtitleSearchSheet: View {
    @ObservedObject var viewModel: TVVideoPlayerViewModel
    @Binding var isPresented: Bool

    private enum Tab: Int, CaseIterable {
        case feature = 0
        case keyword = 1
    }

    @State private var tab: Tab = .feature
    @State private var keyword: String = ""
    @State private var loading: Bool = true
    @State private var downloadingItemId: UUID?
    @State private var items: [TVSubtitleSearchItem] = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("", selection: $tab) {
                    Text(L10n.tr("player_subtitle_search_feature")).tag(Tab.feature)
                    Text(L10n.tr("player_subtitle_search_keyword")).tag(Tab.keyword)
                }
                .pickerStyle(.segmented)
                .onChange(of: tab) { _ in
                    Task { await runSearchForCurrentTab() }
                }

                if tab == .keyword {
                    HStack(spacing: 12) {
                        TextField(L10n.tr("player_subtitle_keyword_hint"), text: $keyword)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.10))
                            )
                            .onSubmit { Task { await runSearchForCurrentTab() } }
                        Button(L10n.tr("player_subtitle_search_action")) {
                            Task { await runSearchForCurrentTab() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(loading)
                    }
                }

                if let err = errorText, !err.isEmpty {
                    Text(err)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }

                if loading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.tr("player_subtitle_searching"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }

                if !loading && items.isEmpty {
                    Text(L10n.tr("player_subtitle_search_no_results"))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    List(items) { it in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(titleForItem(it))
                                .font(.headline)
                                .lineLimit(2)

                            HStack(spacing: 10) {
                                infoChip("\(L10n.tr("player_subtitle_language")): \(languageText(it))")
                                infoChip("\(L10n.tr("player_subtitle_type")): \(it.ext.isEmpty ? "-" : it.ext)")
                            }

                            HStack {
                                Spacer()
                                Button {
                                    Task { await downloadAndApply(it) }
                                } label: {
                                    if downloadingItemId == it.id {
                                        HStack(spacing: 10) {
                                            ProgressView()
                                            Text(L10n.tr("player_subtitle_downloading"))
                                        }
                                    } else {
                                        Text(L10n.tr("download"))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(downloadingItemId != nil)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(24)
            .navigationTitle(L10n.tr("player_subtitle_search_results"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("cancel")) { isPresented = false }
                }
            }
            .onAppear {
                // 默认关键词：取当前文件名（去扩展名），对齐 Flutter defaultKeyword
                if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let raw = viewModel.currentItemFileName
                    keyword = (raw as NSString).deletingPathExtension
                }
                Task { await runFeatureThenFallback() }
            }
        }
    }

    private func runFeatureThenFallback() async {
        loading = true
        errorText = nil
        tab = .feature
        items = []

        let feature = await viewModel.searchSubtitles(searchType: "feature")
        if !feature.isEmpty {
            items = feature
            loading = false
            tab = .feature
            return
        }

        tab = .keyword
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordItems = await viewModel.searchSubtitles(searchType: "keyword", keyword: kw)
        items = keywordItems
        loading = false
    }

    private func runSearchForCurrentTab() async {
        loading = true
        errorText = nil
        items = []
        let type = (tab == .feature) ? "feature" : "keyword"
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await viewModel.searchSubtitles(searchType: type, keyword: kw)
        items = result
        loading = false
    }

    private func downloadAndApply(_ it: TVSubtitleSearchItem) async {
        downloadingItemId = it.id
        errorText = nil
        do {
            let saved = try await viewModel.downloadSearchedSubtitle(item: it)
            viewModel.addAndSelectExternalSubtitle(savedPath: saved.savedPath, filename: saved.filename)
            downloadingItemId = nil
            isPresented = false
        } catch {
            downloadingItemId = nil
            errorText = (error as NSError).localizedDescription
        }
    }

    private func titleForItem(_ it: TVSubtitleSearchItem) -> String {
        if !it.displayName.isEmpty { return it.displayName }
        if !it.sname.isEmpty { return it.sname }
        return "subtitle"
    }

    private func languageText(_ it: TVSubtitleSearchItem) -> String {
        it.language.isEmpty ? L10n.tr("player_subtitle_language_unknown") : it.language
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

#else

/// 当工程尚未集成 KSPlayer 时的占位实现，保证编译通过。
struct TVVideoPlayerView: View {
    let playlist: [TVVideoPlaylistItem]
    let initialIndex: Int
    let initialSeekSeconds: Int
    let ignorePlaybackHistory: Bool
    let ignoreFindSub: Int

    init(
        playlist: [TVVideoPlaylistItem],
        initialIndex: Int,
        initialSeekSeconds: Int = 0,
        ignorePlaybackHistory: Bool = false,
        ignoreFindSub: Int = 1
    ) {
        self.playlist = playlist
        self.initialIndex = initialIndex
        self.initialSeekSeconds = initialSeekSeconds
        self.ignorePlaybackHistory = ignorePlaybackHistory
        self.ignoreFindSub = ignoreFindSub == 0 ? 0 : 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.yellow)
                    .font(.system(size: 40))
                Text("TVVLCKit not available.\nPlease integrate TVVLCKit framework for full playback.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
            }
        }
    }
}

#endif
