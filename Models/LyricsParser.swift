import Foundation

enum LyricsFormat {
    case netEase
    case qq
}

final class LyricsParser {

    // [MM:SS.ms] or [MM:SS]
    private static let timeRegex = try! NSRegularExpression(
        pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#
    )

    // QQ format: [time]lyrics【translation】
    private static let qqLineRegex = try! NSRegularExpression(
        pattern: #"^(\[[+-]?\d+:\d+(?:\.\d+)?\])+(?!\[)([^【\n\r]*)(?:【(.*)】)?"#,
        options: .anchorsMatchLines
    )

    // MARK: - Public

    static func parse(_ lrc: String, format: LyricsFormat) -> [LyricLine] {
        switch format {
        case .netEase:
            return parseNetEase(lrc)
        case .qq:
            return parseQQ(lrc)
        }
    }

    static func merge(original: [LyricLine], translation: [LyricLine], threshold: TimeInterval = 20) -> [LyricLine] {
        var merged: [LyricLine] = []
        var i = 0
        var j = 0

        while i < original.count && j < translation.count {
            let orig = original[i]
            let trans = translation[j]
            let diff = abs(orig.startTimeMS - trans.startTimeMS)

            if diff < threshold {
                var line = orig
                line.translation = trans.words
                merged.append(line)
                i += 1
                j += 1
            } else if orig.startTimeMS < trans.startTimeMS {
                merged.append(orig)
                i += 1
            } else {
                j += 1
            }
        }

        while i < original.count {
            merged.append(original[i])
            i += 1
        }

        return merged
    }

    // MARK: - NetEase (Standard LRC)

    private static func parseNetEase(_ lrc: String) -> [LyricLine] {
        let lines = lrc
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)

        var results: [LyricLine] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip header tags like [ti:], [ar:], [offset:]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && !trimmed.contains("]:") {
                // Check if it's a time tag without lyrics (e.g. [00:01.00])
                let timeMatches = timeRegex.matches(
                    in: trimmed,
                    range: NSRange(trimmed.startIndex..., in: trimmed)
                )
                if timeMatches.isEmpty { continue }
            }

            results.append(contentsOf: parseLRCLine(trimmed))
        }

        return results.sorted { $0.startTimeMS < $1.startTimeMS }
    }

    // MARK: - QQ Format

    private static func parseQQ(_ lrc: String) -> [LyricLine] {
        let lines = lrc
            .replacingOccurrences(of: "\\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)

        var results: [LyricLine] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let nsLine = trimmed as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            guard let match = qqLineRegex.firstMatch(in: trimmed, range: fullRange) else {
                continue
            }

            // Extract time tags
            let timeTagStr = match.range(at: 1)
            guard timeTagStr.location != NSNotFound else { continue }
            let timeTags = resolveTimeTags(nsLine.substring(with: timeTagStr))

            // Extract lyrics text
            let lyricsRange = match.range(at: 2)
            let lyricsText = lyricsRange.location != NSNotFound
                ? nsLine.substring(with: lyricsRange).trimmingCharacters(in: .whitespaces)
                : ""

            // Extract translation
            let transRange = match.range(at: 3)
            let translation = transRange.location != NSNotFound
                ? nsLine.substring(with: transRange).trimmingCharacters(in: .whitespaces)
                : nil

            guard !lyricsText.isEmpty || translation?.isEmpty == false else {
                continue
            }

            for timeTag in timeTags {
                let line = LyricLine(
                    startTimeMS: timeTag * 1000,
                    words: lyricsText,
                    translation: translation?.isEmpty == true ? nil : translation
                )
                results.append(line)
            }
        }

        return results.sorted { $0.startTimeMS < $1.startTimeMS }
    }

    // MARK: - Helpers

    /// Parse a standard LRC line like `[01:23.45]Hello World`
    private static func parseLRCLine(_ line: String) -> [LyricLine] {
        var results: [LyricLine] = []
        var remaining = line

        while remaining.hasPrefix("[") {
            guard let closeBracket = remaining.firstIndex(of: "]") else { break }

            let tagContent = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])

            // Check if it's a header tag (e.g. "offset:500")
            if tagContent.contains(":") && !tagContent.contains(".") {
                let parts = tagContent.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    if ["ti", "ar", "al", "by", "offset", "re", "ve"].contains(key) {
                        // It's a header, skip this line
                        if remaining[closeBracket...].dropFirst().trimmingCharacters(in: .whitespaces).isEmpty {
                            return results
                        }
                    }
                }
            }

            // Parse time value
            guard let timeMS = parseTimeTag(tagContent) else { break }

            remaining = String(remaining[remaining.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespaces)

            // Collect additional time tags
            var times = [timeMS]
            while remaining.hasPrefix("[") {
                guard let nextClose = remaining.firstIndex(of: "]") else { break }
                let nextTag = String(remaining[remaining.index(after: remaining.startIndex)..<nextClose])
                if let nextTime = parseTimeTag(nextTag) {
                    times.append(nextTime)
                    remaining = String(remaining[remaining.index(after: nextClose)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    break
                }
            }

            let words = remaining.trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { break }

            for time in times {
                results.append(LyricLine(startTimeMS: time, words: words))
            }
            break
        }

        return results
    }

    /// Parse a time tag like "01:23.45" into milliseconds
    private static func parseTimeTag(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count >= 2 else { return nil }

        guard let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else { return nil }

        return (minutes * 60 + seconds) * 1000
    }

    /// Resolve time tags from a string like "[00:01.00][00:02.00]"
    private static func resolveTimeTags(_ str: String) -> [TimeInterval] {
        let matches = timeRegex.matches(in: str, range: NSRange(str.startIndex..., in: str))
        return matches.compactMap { match in
            guard let minRange = Range(match.range(at: 1), in: str),
                  let secRange = Range(match.range(at: 2), in: str),
                  let min = Double(str[minRange]),
                  let sec = Double(str[secRange]) else { return nil }
            return min * 60 + sec
        }
    }
}

// NSRegularExpression helper
private extension NSRegularExpression {
    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }
}
