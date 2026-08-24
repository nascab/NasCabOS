import Foundation

struct SubtitleCue {
    let startMs: Int64
    let endMs: Int64
    let text: String
}

enum SubtitleBitmapUtil {
    static func isBitmapCodecName(_ codecName: String?) -> Bool {
        let v = codecName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return v == "pgssub"
            || v == "hdmv_pgs_subtitle"
            || v == "vobsub"
            || v == "dvd_subtitle"
            || v == "dvdsub"
            || v == "dvb_subtitle"
            || v == "xsub"
    }

    static func isBitmapExternalExtension(_ ext: String) -> Bool {
        let v = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == ".sup" || v == ".sub" || v == ".idx"
    }
}

enum WebVttParser {
    static func parseWebVtt(_ vttText: String) -> [SubtitleCue] {
        let lines = vttText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var cues: [SubtitleCue] = []
        var i = 0

        while i < lines.count, lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { i += 1 }
        if i < lines.count, lines[i].trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("WEBVTT") {
            i += 1
        }

        while i < lines.count {
            while i < lines.count, lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { i += 1 }
            if i >= lines.count { break }

            let head = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if head.hasPrefix("NOTE") || head.hasPrefix("STYLE") || head.hasPrefix("REGION") {
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { i += 1 }
                continue
            }

            var timeLine = lines[i]
            if !timeLine.contains("-->") {
                i += 1
                if i >= lines.count { break }
                timeLine = lines[i]
            }

            guard let arrowRange = timeLine.range(of: "-->") else {
                i += 1
                continue
            }
            let left = String(timeLine[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rightPart = String(timeLine[arrowRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = rightPart.split(whereSeparator: \.isWhitespace).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard let start = parseVttTimestamp(left), let end = parseVttTimestamp(right) else {
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { i += 1 }
                continue
            }
            i += 1

            var textLines: [String] = []
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textLines.append(lines[i])
                i += 1
            }
            let text = formatCueText(textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            if !text.isEmpty, end > start {
                cues.append(SubtitleCue(startMs: start, endMs: end, text: text))
            }
        }

        return cues.sorted { $0.startMs < $1.startMs }
    }

    static func findActiveCue(_ cues: [SubtitleCue], positionMs: Int64) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var lo = 0
        var hi = cues.count - 1
        var best = -1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let c = cues[mid]
            if c.startMs <= positionMs {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if best < 0 { return nil }
        let c = cues[best]
        return positionMs >= c.startMs && positionMs <= c.endMs ? c : nil
    }

    private static func parseVttTimestamp(_ raw: String) -> Int64? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 3 else { return nil }

        let hours: Int
        let minutes: Int
        let seconds: Double
        if parts.count == 3 {
            guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            hours = h
            minutes = m
            seconds = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? -1
        } else {
            hours = 0
            guard let m = Int(parts[0]) else { return nil }
            minutes = m
            seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")) ?? -1
        }
        guard hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
        return Int64(hours) * 3_600_000 + Int64(minutes) * 60_000 + Int64(seconds * 1000.0)
    }

    /// ffmpeg WebVTT 常带 `<br>`、`<font>` 等标签；叠层需转成纯文本。
    static func formatCueText(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if let br = try? NSRegularExpression(pattern: "<br\\s*/?>", options: [.caseInsensitive]) {
            let range = NSRange(s.startIndex..., in: s)
            s = br.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "\n")
        }
        if let tags = try? NSRegularExpression(pattern: "<[^>]*>") {
            let range = NSRange(s.startIndex..., in: s)
            s = tags.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        if let ass = try? NSRegularExpression(pattern: "\\{[^}]*\\}") {
            let range = NSRange(s.startIndex..., in: s)
            s = ass.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        s = s
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
