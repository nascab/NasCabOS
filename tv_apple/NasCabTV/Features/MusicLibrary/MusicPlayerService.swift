import Foundation
import AVFoundation
#if canImport(TVVLCKit)
import TVVLCKit
import Combine
#endif

// MARK: - Music Player Service (AVPlayer or VLC, switchable)

// MARK: - Loop Mode (参考 Flutter)

enum MusicLoopMode: Int, CaseIterable {
    case sequence = 0   // 顺序播放
    case listLoop = 1   // 列表循环
    case singleLoop = 2 // 单曲循环
    case shuffle = 3    // 随机播放

    var next: MusicLoopMode {
        switch self {
        case .sequence: return .listLoop
        case .listLoop: return .singleLoop
        case .singleLoop: return .shuffle
        case .shuffle: return .sequence
        }
    }

    var sfSymbol: String {
        switch self {
        case .sequence: return "list.number"
        case .listLoop: return "repeat"
        case .singleLoop: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

@MainActor
final class MusicPlayerService: NSObject, ObservableObject {
    static let shared = MusicPlayerService()

    @Published private(set) var currentItem: MusicItem?
    @Published private(set) var queue: [MusicItem] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var playbackState: PlaybackState = .stopped
    @Published var loopMode: MusicLoopMode = .sequence
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var currentLyricIndex: Int = -1

    private var avPlayer: AVPlayer?
    private var avTimeObserver: Any?
    #if canImport(TVVLCKit)
    private var vlcPlayer: VLCMediaPlayer?
    private var vlcTimeCancellable: AnyCancellable?
    #endif
    private var lyricUpdateTask: Task<Void, Never>?
    private var lastNextTriggerTime: TimeInterval = -999
    private var avLoggedFailure = false
    #if canImport(TVVLCKit)
    private var vlcLoggedZeroTime = false
    #endif
    private var autoLyricTriedPaths: Set<String> = []

    enum PlaybackState {
        case stopped
        case playing
        case paused
    }

    var isPlaying: Bool { playbackState == .playing }
    var hasCurrentItem: Bool { currentItem != nil }

    private override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[MusicPlayer] Audio session setup failed: \(error)")
        }
    }

    // MARK: - Playback Control

    func play(item: MusicItem, queue: [MusicItem]? = nil, startIndex: Int = 0) {
        print("[MusicPlayer] play() id=\(item.id) title=\(item.displayTitle) path=\(item.fullPath) useVLC=\(MusicPlayerConfig.useVLCForMusic)")
        lastNextTriggerTime = -999
        let list = queue ?? [item]
        let idx = min(max(0, startIndex), list.count - 1)
        self.queue = list
        self.currentIndex = idx
        self.currentItem = list[idx]
        self.lyrics = []
        self.currentLyricIndex = -1

        loadAndPlay(item: list[idx])
    }

    func playFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        lastNextTriggerTime = -999
        currentIndex = index
        currentItem = queue[index]
        lyrics = []
        currentLyricIndex = -1
        loadAndPlay(item: queue[index])
    }

    func togglePlayPause() {
        #if canImport(TVVLCKit)
        if let vlc = vlcPlayer {
            if vlc.isPlaying {
                vlc.pause()
                playbackState = .paused
            } else {
                vlc.play()
                playbackState = .playing
            }
            return
        }
        #endif
        if let p = avPlayer {
            if playbackState == .playing {
                p.pause()
                playbackState = .paused
            } else {
                p.play()
                playbackState = .playing
            }
        }
    }

    func pause() {
        #if canImport(TVVLCKit)
        vlcPlayer?.pause()
        #endif
        avPlayer?.pause()
        playbackState = .paused
    }

    func resume() {
        #if canImport(TVVLCKit)
        vlcPlayer?.play()
        #endif
        avPlayer?.play()
        playbackState = .playing
    }

    func stop() {
        #if canImport(TVVLCKit)
        vlcPlayer?.stop()
        vlcPlayer?.media = nil
        vlcTimeCancellable?.cancel()
        vlcTimeCancellable = nil
        vlcPlayer = nil
        #endif
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        removeAVTimeObserver()
        playbackState = .stopped
        currentItem = nil
        currentTime = 0
        duration = 0
        lyrics = []
        currentLyricIndex = -1
    }

    func seek(to time: TimeInterval) {
        #if canImport(TVVLCKit)
        if let vlc = vlcPlayer {
            let ms = Int32(time * 1000)
            vlc.time = VLCTime(int: ms)
            return
        }
        #endif
        avPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    func cycleLoopMode() {
        loopMode = loopMode.next
    }

    func next() {
        guard !queue.isEmpty else { return }
        switch loopMode {
        case .shuffle:
            let nextIdx = Int.random(in: 0..<queue.count)
            playFromQueue(at: nextIdx)
        case .sequence:
            if currentIndex + 1 >= queue.count { return }
            playFromQueue(at: currentIndex + 1)
        case .listLoop, .singleLoop:
            let nextIdx = (currentIndex + 1) % queue.count
            playFromQueue(at: nextIdx)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        switch loopMode {
        case .shuffle:
            let prevIdx = Int.random(in: 0..<queue.count)
            playFromQueue(at: prevIdx)
        case .sequence:
            if currentIndex - 1 < 0 { return }
            playFromQueue(at: currentIndex - 1)
        case .listLoop, .singleLoop:
            let prevIdx = currentIndex - 1
            if prevIdx < 0 {
                playFromQueue(at: queue.count - 1)
            } else {
                playFromQueue(at: prevIdx)
            }
        }
    }

    // MARK: - Load & Play

    private func loadAndPlay(item: MusicItem) {
        let useVLC = MusicPlayerConfig.useVLCForMusic
        print("[MusicPlayer] loadAndPlay() useVLC=\(useVLC) id=\(item.id)")

        #if canImport(TVVLCKit)
        if useVLC {
            print("[MusicPlayer] 使用vlc播放音乐")
            loadAndPlayVLC(item: item)
            return
        }
        #endif
        loadAndPlayAVPlayer(item: item)
    }

    private func loadAndPlayAVPlayer(item: MusicItem) {
        #if canImport(TVVLCKit)
        vlcPlayer?.stop()
        vlcPlayer?.media = nil
        vlcTimeCancellable?.cancel()
        vlcPlayer = nil
        #endif
        avLoggedFailure = false
        print("[MusicPlayer][AV] prepare url for path=\(item.fullPath)")
        guard let url = MusicService.transcodeURL(filePath: item.fullPath) else {
            print("[MusicPlayer][AV] transcodeURL is nil, stop. path=\(item.fullPath)")
            playbackState = .stopped
            return
        }

        print("[MusicPlayer][AV] start play url=\(url.absoluteString)")
        let playerItem = AVPlayerItem(url: url)
        if avPlayer == nil {
            avPlayer = AVPlayer(playerItem: playerItem)
        } else {
            avPlayer?.replaceCurrentItem(with: playerItem)
        }

        addAVTimeObserver()
        avPlayer?.play()
        playbackState = .playing

        Task { await loadLyrics(for: item) }
    }

    #if canImport(TVVLCKit)
    private func loadAndPlayVLC(item: MusicItem) {
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        removeAVTimeObserver()
        vlcLoggedZeroTime = false
        print("[MusicPlayer][VLC] prepare raw url for path=\(item.fullPath)")
        guard let url = MusicService.rawFileURL(filePath: item.fullPath) else {
            print("[MusicPlayer][VLC] rawFileURL is nil, stop. path=\(item.fullPath)")
            playbackState = .stopped
            return
        }

        print("[MusicPlayer][VLC] start play url=\(url.absoluteString)")
        let media = VLCMedia(url: url)
        if vlcPlayer == nil {
            vlcPlayer = VLCMediaPlayer()
        }
        vlcPlayer?.delegate = self
        vlcPlayer?.stop()
        vlcPlayer?.media = media
        vlcPlayer?.play()
        playbackState = .playing

        setupVLCTimeObserver()
        Task { await loadLyrics(for: item) }
    }

    private func setupVLCTimeObserver() {
        vlcTimeCancellable?.cancel()
        vlcTimeCancellable = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleVLCTimeUpdate()
                }
            }
    }
    #endif

    // MARK: - AVPlayer Time Observer

    private func addAVTimeObserver() {
        removeAVTimeObserver()
        guard let p = avPlayer else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        avTimeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.handleAVTimeUpdate(time: time)
            }
        }
    }

    private func removeAVTimeObserver() {
        if let obs = avTimeObserver, let p = avPlayer {
            p.removeTimeObserver(obs)
        }
        avTimeObserver = nil
    }

    private func handleAVTimeUpdate(time: CMTime) {
        let sec = time.seconds
        currentTime = sec

        if let item = avPlayer?.currentItem, item.status == .failed, !avLoggedFailure {
            avLoggedFailure = true
            let url = (item.asset as? AVURLAsset)?.url.absoluteString ?? "n/a"
            print("[MusicPlayer][AV] item status failed, error=\(item.error?.localizedDescription ?? "nil"), url=\(url)")
        }

        if let item = avPlayer?.currentItem, item.status == .readyToPlay {
            let dur = item.duration.seconds
            if dur.isFinite, dur > 0 {
                duration = dur
            }
        }

        updateCurrentLyricIndex(time: sec)
        checkAutoNext(time: sec)
    }

    #if canImport(TVVLCKit)
    private func handleVLCTimeUpdate() {
        guard let vlc = vlcPlayer else { return }
        let ms = vlc.time.intValue
        let sec = TimeInterval(max(0, ms)) / 1000.0
        currentTime = sec

        if sec == 0, !vlc.isPlaying, !vlcLoggedZeroTime {
            vlcLoggedZeroTime = true
            let lenMs = vlc.media?.length.intValue ?? -1
            print("[MusicPlayer][VLC] time=0 and not playing, state=\(vlc.state.rawValue) mediaLenMs=\(lenMs)")
        }

        if let media = vlc.media {
            let lenMs = media.length.intValue
            if lenMs > 0 {
                duration = TimeInterval(lenMs) / 1000.0
            }
        }
        if duration <= 0, let item = currentItem, item.duration > 0 {
            duration = TimeInterval(item.duration)
        }

        playbackState = vlc.isPlaying ? .playing : .paused
        updateCurrentLyricIndex(time: sec)
        checkAutoNext(time: sec)
    }
    #endif

    private func checkAutoNext(time: TimeInterval) {
        let trackDuration = currentItem.map { Double($0.duration) } ?? duration
        guard trackDuration > 0 else { return }
        guard time >= trackDuration - 1.5, time - lastNextTriggerTime > 2 else { return }
        lastNextTriggerTime = time

        switch loopMode {
        case .singleLoop:
            // 单曲循环：歌曲自然结束时从头继续播放
            seek(to: 0)
        default:
            guard queue.count > 1 else { return }
            next()
        }
    }

    private func updateCurrentLyricIndex(time: TimeInterval) {
        guard !lyrics.isEmpty else {
            currentLyricIndex = -1
            return
        }
        var idx = -1
        for (i, line) in lyrics.enumerated() {
            if line.time <= time {
                idx = i
            }
        }
        if currentLyricIndex != idx {
            currentLyricIndex = idx
        }
    }

    private func loadLyrics(for item: MusicItem) async {
        lyricUpdateTask?.cancel()
        lyricUpdateTask = Task {
            let detail = await MusicService.getDetail(filePath: item.fullPath)
            guard !Task.isCancelled else { return }
            if let data = detail.data, !data.lyrics.isEmpty {
                lyrics = Self.parseLRC(data.lyrics)
            } else {
                lyrics = []
                await autoSearchLyricIfNeeded(for: item)
            }
        }
        await lyricUpdateTask?.value
    }

    func applyLyricOverride(filePath: String, lrc: String) {
        let trimmed = lrc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lines = Self.parseLRC(trimmed)
        lyrics = lines
        currentLyricIndex = -1
        autoLyricTriedPaths.insert(filePath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func autoSearchLyricIfNeeded(for item: MusicItem) async {
        let path = item.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        if autoLyricTriedPaths.contains(path) { return }
        if !lyrics.isEmpty { return }

        let expectedMs: Int
        if duration > 0 {
            expectedMs = Int(duration * 1000)
        } else if item.duration > 0 {
            let v = item.duration
            expectedMs = v < 24 * 60 * 60 ? v * 1000 : v
        } else {
            expectedMs = 0
        }
        guard expectedMs > 0 else { return }

        let keyword = buildLyricSearchKeyword(for: item, filePath: path)
        guard !keyword.isEmpty else { return }

        autoLyricTriedPaths.insert(path)

        let response = await MusicService.searchLyric(keyword: keyword)
        guard response.success, let rawItems = response.data, !rawItems.isEmpty else { return }

        let fileStemNorm = Self.normalizeForContains(fileStem(path))
        let candidates: [LyricSearchItem] = rawItems.compactMap { LyricSearchItem(json: $0) }
        let matched = candidates.filter { candidate in
            candidate.isHighMatch(fileStemNormalized: fileStemNorm, expectedDurationMs: expectedMs)
        }
        guard let chosen = (matched.first ?? candidates.first), !chosen.lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let setRes = await MusicService.setLyric(musicPath: path, lrc: chosen.lrc)
        guard setRes.success else { return }

        await MainActor.run {
            self.applyLyricOverride(filePath: path, lrc: chosen.lrc)
        }
    }

    private func buildLyricSearchKeyword(for item: MusicItem, filePath: String) -> String {
        let rawTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArtist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = fileStem(item.filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? filePath : item.filename)
        let title = (rawTitle.isEmpty ? fallbackTitle : rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "" }
        if !rawArtist.isEmpty {
            return "\(title) \(rawArtist)"
        }
        return title
    }

    private func fileStem(_ pathOrFile: String) -> String {
        let input = pathOrFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return "" }
        let ns = input as NSString
        let lastSlash = max(ns.range(of: "/", options: .backwards).location,
                            ns.range(of: "\\", options: .backwards).location)
        let name: String
        if lastSlash != NSNotFound {
            name = ns.substring(from: lastSlash + 1)
        } else {
            name = input
        }
        if let dotRange = name.range(of: ".", options: .backwards) {
            return String(name[..<dotRange.lowerBound])
        }
        return name
    }

    nonisolated(unsafe) private static func normalizeForContains(_ input: String) -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").union(
            CharacterSet(charactersIn: "\u{4e00}"..."\u{9fff}")
        )
        return String(s.unicodeScalars.filter { allowed.contains($0) })
    }

    private struct LyricSearchItem {
        let id: String
        let source: String
        let title: String
        let album: String
        let artist: String
        let durationMs: Int
        let preview: String
        let lrc: String

        init?(json: [String: Any]) {
            id = (json["id"] as? String) ?? ""
            source = (json["source"] as? String) ?? ""
            title = (json["title"] as? String) ?? ""
            album = (json["album"] as? String) ?? ""
            artist = (json["artist"] as? String) ?? ""
            let durationRaw = (json["duration"] as? String) ?? (json["duration"] as? NSNumber)?.stringValue ?? ""
            durationMs = Int(durationRaw) ?? 0
            preview = (json["preview"] as? String) ?? ""
            lrc = (json["lrc"] as? String) ?? ""
        }

        func isHighMatch(fileStemNormalized: String, expectedDurationMs: Int) -> Bool {
            let titleNorm = MusicPlayerService.normalizeForContains(title)
            guard !titleNorm.isEmpty else { return false }
            let durationMatch = durationMs > 0 && abs(durationMs - expectedDurationMs) <= 5000
            let nameMatch = !fileStemNormalized.isEmpty && fileStemNormalized.contains(titleNorm)
            return durationMatch && nameMatch
        }
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
        let lines = text.components(separatedBy: .newlines)
        var result: [LyricLine] = []
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let range = NSRange(trimmed.startIndex..., in: trimmed)
            let matches = regex.matches(in: trimmed, range: range)
            guard let first = matches.first else { continue }

            let minStr = (trimmed as NSString).substring(with: first.range(at: 1))
            let secStr = (trimmed as NSString).substring(with: first.range(at: 2))
            let msStr = first.numberOfRanges > 3 ? (trimmed as NSString).substring(with: first.range(at: 3)) : "0"

            let minVal = Double(minStr) ?? 0
            let sec = Double(secStr) ?? 0
            let ms = Double(msStr) ?? 0
            let time = minVal * 60 + sec + ms / 1000

            let matchRange = first.range(at: 0)
            let nsTrimmed = trimmed as NSString
            let textStart = Swift.min(matchRange.location + matchRange.length, nsTrimmed.length)
            let lyricText = (textStart < nsTrimmed.length ? nsTrimmed.substring(from: textStart) : "").trimmingCharacters(in: .whitespaces)
            if !lyricText.isEmpty {
                result.append(LyricLine(time: time, text: lyricText))
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}

#if canImport(TVVLCKit)
extension MusicPlayerService: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        print("[MusicPlayer][VLC] stateChanged state=\(player.state.rawValue) isPlaying=\(player.isPlaying)")
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        // 这里可能比较频繁，只打印前几次 0 秒的变化已经在 handleVLCTimeUpdate 里处理了
    }
}
#endif
