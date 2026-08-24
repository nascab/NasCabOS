import SwiftUI

private enum PlayerControlFocus: Hashable {
    case lyricSearch, loop, prev, play, next, playlist, favorite
}

struct MusicPlayerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = MusicPlayerService.shared
    @FocusState private var focusedControl: PlayerControlFocus?
    @State private var showQueueSheet = false
    @State private var showLyricSearchSheet = false
    @State private var isTogglingFavorite = false
    /// 本地覆盖的收藏状态，nil 表示使用 currentItem.isFavorite
    @State private var favoriteState: Bool?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.black,
                        Color.pink.opacity(0.15),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    if let item = player.currentItem {
                        coverAndInfoSection(item: item)
                        lyricSection
                        controlSection
                    } else {
                        Text(L10n.musicNoTrack)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 48)
            }
            .navigationTitle(L10n.musicNowPlaying)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedControl = .next
                }
            }
            .sheet(isPresented: $showQueueSheet) {
                MusicQueueSheet()
            }
            .onChange(of: player.currentItem?.id) { _ in
                favoriteState = nil
            }
            .sheet(isPresented: $showLyricSearchSheet) {
                if let item = player.currentItem {
                    MusicLyricSearchSheet(
                        item: item,
                        duration: player.duration > 0 ? player.duration : TimeInterval(item.duration),
                        onApplyLyric: { path, lrc in
                            player.applyLyricOverride(filePath: path, lrc: lrc)
                        }
                    )
                } else {
                    Text(L10n.musicNoTrack)
                        .font(.title3)
                        .padding()
                }
            }
        }
    }

    private func coverAndInfoSection(item: MusicItem) -> some View {
        HStack(spacing: 48) {
            MusicRotatingDiscView(item: item, isPlaying: player.isPlaying)

            VStack(alignment: .leading, spacing: 16) {
                Text(item.displayTitle)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(2)
                if !item.displaySubtitle.isEmpty {
                    Text(item.displaySubtitle)
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if player.duration > 0 {
                    Text(formatTime(player.currentTime) + " / " + formatTime(player.duration))
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
    }

    private var lyricSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if player.lyrics.isEmpty {
                        Text(L10n.musicNoLyrics)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { idx, line in
                            Text(line.text)
                                .font(.system(size: idx == player.currentLyricIndex ? 32 : 24))
                                .fontWeight(idx == player.currentLyricIndex ? .semibold : .regular)
                                .foregroundStyle(idx == player.currentLyricIndex ? Color.white : Color.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(idx)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .frame(maxHeight: 280)
            .onChange(of: player.currentLyricIndex) { newIdx in
                if newIdx >= 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIdx, anchor: .center)
                    }
                }
            }
        }
    }

    private var controlSection: some View {
        HStack(spacing: 48) {
            Button {
                showLyricSearchSheet = true
            } label: {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 26))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .lyricSearch)

            Button {
                player.cycleLoopMode()
            } label: {
                Image(systemName: player.loopMode.sfSymbol)
                    .font(.system(size: 28))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .loop)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 36))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .prev)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .play)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 36))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .next)

            Button {
                showQueueSheet = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 28))
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .playlist)

            Button {
                Task { await toggleFavorite() }
            } label: {
                if isTogglingFavorite {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: effectiveFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 28))
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
            .focused($focusedControl, equals: .favorite)
            .disabled(isTogglingFavorite || player.currentItem == nil)
        }
        .padding(.vertical, 24)
    }

    /// 当前展示的收藏状态：本地覆盖优先，否则用 currentItem.isFavorite
    private var effectiveFavorite: Bool {
        if let v = favoriteState { return v }
        return player.currentItem?.isFavorite ?? false
    }

    private func toggleFavorite() async {
        guard let item = player.currentItem, item.id > 0, !isTogglingFavorite else { return }
        isTogglingFavorite = true
        let next = !effectiveFavorite
        let res = next
            ? await MusicService.addFavorite(indexId: item.id)
            : await MusicService.removeFavorite(indexId: item.id)
        await MainActor.run {
            isTogglingFavorite = false
            if res.success {
                favoriteState = next
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Queue Sheet (播放列表)

struct MusicQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = MusicPlayerService.shared

    var body: some View {
        let screenWidth = UIScreen.main.bounds.width
        let minWidth = screenWidth * 0.5
        let maxWidth = min(screenWidth * 0.9, 900)

        ZStack {
            Color.black.ignoresSafeArea()
            if player.queue.isEmpty {
                Text(L10n.musicNoTrack)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxyReader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(player.queue.enumerated()), id: \.element.id) { idx, item in
                                Button {
                                    player.playFromQueue(at: idx)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 16) {
                                        if idx == player.currentIndex {
                                            Image(systemName: "music.note")
                                                .foregroundStyle(Color.pink)
                                                .font(.system(size: 20))
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.displayTitle)
                                                .font(.system(size: 22))
                                                .foregroundStyle(idx == player.currentIndex ? Color.white : Color.primary)
                                                .lineLimit(1)
                                            if !item.displaySubtitle.isEmpty {
                                                Text(item.displaySubtitle)
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(idx + 1)")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(idx == player.currentIndex ? Color.pink.opacity(0.2) : Color.white.opacity(0.04))
                                    )
                                }
                                .buttonStyle(NCCardButtonStyle(cornerRadius: 12, focusScale: 1.02))
                                .id(idx)
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 32)
                    }
                    .onAppear {
                        if player.currentIndex >= 0, player.currentIndex < player.queue.count {
                            proxyReader.scrollTo(player.currentIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth, maxHeight: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rotating Disc (Now Playing)

struct MusicRotatingDiscView: View {
    let item: MusicItem
    let isPlaying: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Image("player_disc")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .rotationEffect(.degrees(rotation), anchor: .center)

            MusicCoverImage(item: item, filePath: item.fullPath, size: 500)
                .frame(width: 180, height: 180)
                .clipShape(Circle())
        }
        .frame(width: 320, height: 320)
        .clipped()
        .onAppear { startIfNeeded() }
        .onChange(of: isPlaying) { _ in
            startIfNeeded()
        }
    }

    private func startIfNeeded() {
        if isPlaying {
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            rotation = 0
        }
    }
}

// MARK: - Playing Indicator (animated bars)

struct MusicPlayingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.pink.opacity(0.9))
                    .frame(width: 6, height: animating ? CGFloat([24, 40, 32, 48][i]) : 16)
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Lyric Search Sheet

private struct MusicLyricSearchSheet: View {
    let item: MusicItem
    let duration: TimeInterval
    let onApplyLyric: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String = ""
    @State private var isLoading: Bool = false
    @State private var results: [LyricSearchItem] = []
    @State private var selectingId: String = ""
    @State private var didAutoSearch = false

    private var musicPath: String {
        let full = item.fullPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        let p = item.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let f = item.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "" }
        if f.isEmpty { return p }
        return p.hasSuffix("/") ? "\(p)\(f)" : "\(p)/\(f)"
    }

    private var trackDurationMs: Int {
        let v = duration > 0 ? Int(duration * 1000) : (item.duration > 0 ? item.duration * 1000 : 0)
        return v
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.musicSearchLyric)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(L10n.search, text: $keyword)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await performSearch() } }

                    if !keyword.isEmpty {
                        Button {
                            keyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                )

                HStack {
                    Spacer()
                    Button {
                        Task { await performSearch() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(L10n.search)
                        }
                    }
                    .buttonStyle(NCPlainFocusButtonStyle())
                }

                Group {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(1.0)
                            Text(L10n.loading)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    } else if results.isEmpty {
                        Text(L10n.noData)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(results) { r in
                                    lyricRow(for: r)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                        }
                    }
                }

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: 900, maxHeight: 700, alignment: .topLeading)
            .onAppear {
                keyword = "\(item.title.trimmingCharacters(in: .whitespacesAndNewlines)) \(item.artist.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespacesAndNewlines)
                if keyword.isEmpty {
                    keyword = "\(item.displayTitle)".trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !didAutoSearch {
                    didAutoSearch = true
                    Task { await performSearch() }
                }
            }
        }
    }

    private func performSearch() async {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        await MainActor.run {
            isLoading = true
            results = []
        }
        let resp = await MusicService.searchLyric(keyword: q)
        await MainActor.run {
            isLoading = false
            if resp.success, let raw = resp.data {
                results = raw.compactMap { LyricSearchItem(json: $0, musicPath: musicPath, expectedDurationMs: trackDurationMs) }
            } else {
                results = []
            }
        }
    }

    @ViewBuilder
    private func lyricRow(for item: LyricSearchItem) -> some View {
        let highMatch = item.highMatch
        let metaParts: [String] = [
            item.artist.isEmpty ? nil : item.artist,
            item.album.isEmpty ? nil : item.album,
            item.durationText.isEmpty ? nil : item.durationText,
        ].compactMap { $0 }
        let meta = metaParts.joined(separator: " · ")

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if highMatch {
                        Text("高匹配度")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            )
                    }
                    Text(item.title.isEmpty ? item.id : item.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await apply(item: item) }
            } label: {
                if selectingId == item.id {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(L10n.ok)
                        .font(.subheadline)
                }
            }
            .buttonStyle(NCPlainFocusButtonStyle())
        }
        .padding(.vertical, 6)
    }

    private func apply(item: LyricSearchItem) async {
        await MainActor.run {
            selectingId = item.id
        }
        let res = await MusicService.setLyric(musicPath: musicPath, lrc: item.lrc)
        await MainActor.run {
            selectingId = ""
            if res.success {
                onApplyLyric(musicPath, item.lrc)
                dismiss()
            }
        }
    }

    private struct LyricSearchItem: Identifiable {
        let id: String
        let source: String
        let title: String
        let album: String
        let artist: String
        let durationMs: Int
        let preview: String
        let lrc: String
        let highMatch: Bool

        var durationText: String {
            guard durationMs > 0 else { return "" }
            let totalSeconds = durationMs / 1000
            let m = totalSeconds / 60
            let s = totalSeconds % 60
            return String(format: "%d:%02d", m, s)
        }

        init?(json: [String: Any], musicPath: String, expectedDurationMs: Int) {
            id = (json["id"] as? String) ?? ""
            source = (json["source"] as? String) ?? ""
            title = (json["title"] as? String) ?? ""
            album = (json["album"] as? String) ?? ""
            artist = (json["artist"] as? String) ?? ""
            let durationRaw = (json["duration"] as? String) ?? (json["duration"] as? NSNumber)?.stringValue ?? ""
            durationMs = Int(durationRaw) ?? 0
            preview = (json["preview"] as? String) ?? ""
            lrc = (json["lrc"] as? String) ?? ""

            let fileStemNorm = Self.normalizeForContains(Self.fileStem(musicPath))
            let titleNorm = Self.normalizeForContains(title)
            let durationMatch = durationMs > 0 && abs(durationMs - expectedDurationMs) <= 5000
            let nameMatch = !fileStemNorm.isEmpty && !titleNorm.isEmpty && fileStemNorm.contains(titleNorm)
            highMatch = durationMatch && nameMatch
        }

        private static func fileStem(_ pathOrFile: String) -> String {
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

        private static func normalizeForContains(_ input: String) -> String {
            let s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !s.isEmpty else { return "" }
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").union(
                CharacterSet(charactersIn: "\u{4e00}"..."\u{9fff}")
            )
            return String(s.unicodeScalars.filter { allowed.contains($0) })
        }
    }
}
