import Foundation
import QuartzCore

enum LyricUnitKind: String, Equatable, Sendable {
    case chineseCharacter
    case englishWord
    case number
    case punctuation
    case whitespace

    var isVocal: Bool {
        switch self {
        case .chineseCharacter, .englishWord, .number:
            true
        case .punctuation, .whitespace:
            false
        }
    }
}

struct EstimatedLyricUnit: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    /// UTF-16 offsets into `EstimatedLyricLine.text`.
    let range: Range<Int>
    let kind: LyricUnitKind

    func progress(at playbackTime: TimeInterval) -> Double {
        guard endTime > startTime else {
            return playbackTime >= startTime ? 1 : 0
        }
        return min(max((playbackTime - startTime) / (endTime - startTime), 0), 1)
    }
}

struct LyricRevealState: Equatable, Sendable {
    let completedUTF16Offset: Int
    let activeUnitRange: Range<Int>?
    let activeUnitProgress: Double
    let isComplete: Bool
}

enum LyricTimingPrecision: String, Equatable, Sendable {
    case exactWord
    case estimated
}

struct EstimatedLyricLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceIndex: Int
    let text: String
    let lineStartTime: TimeInterval
    let vocalEndTime: TimeInterval
    let lineEndTime: TimeInterval
    let units: [EstimatedLyricUnit]
    let localRate: Double
    let baseVocalDuration: TimeInterval
    let finalHoldDuration: TimeInterval
    let trailingRestDuration: TimeInterval
    let precision: LyricTimingPrecision

    func revealState(at playbackTime: TimeInterval) -> LyricRevealState {
        let fullLength = text.utf16.count
        guard playbackTime >= lineStartTime else {
            return LyricRevealState(
                completedUTF16Offset: 0,
                activeUnitRange: nil,
                activeUnitProgress: 0,
                isComplete: false
            )
        }
        guard playbackTime < vocalEndTime else {
            return LyricRevealState(
                completedUTF16Offset: fullLength,
                activeUnitRange: nil,
                activeUnitProgress: 1,
                isComplete: true
            )
        }

        var completedOffset = 0
        for unit in units {
            if unit.endTime <= unit.startTime {
                if playbackTime >= unit.startTime {
                    completedOffset = max(completedOffset, unit.range.upperBound)
                    continue
                }
                break
            }

            if playbackTime >= unit.endTime {
                completedOffset = max(completedOffset, unit.range.upperBound)
                continue
            }

            if playbackTime >= unit.startTime {
                return LyricRevealState(
                    completedUTF16Offset: max(completedOffset, unit.range.lowerBound),
                    activeUnitRange: unit.range,
                    activeUnitProgress: unit.progress(at: playbackTime),
                    isComplete: false
                )
            }
            break
        }

        return LyricRevealState(
            completedUTF16Offset: completedOffset,
            activeUnitRange: nil,
            activeUnitProgress: 0,
            isComplete: false
        )
    }
}

struct LyricTimingEstimatorConfiguration: Equatable, Sendable {
    var defaultRate: Double = 3.2
    var minimumRate: Double = 1.8
    var maximumRate: Double = 6.5

    var minimumUnitDuration: TimeInterval = 0.10
    var maximumNormalUnitDuration: TimeInterval = 0.75

    var maximumFinalHoldDuration: TimeInterval = 2.2
    var shortLineMaximumFinalHoldDuration: TimeInterval = 3.0

    var localContextRadius: Int = 3
    var maximumBaseDurationRatio: Double = 0.90
    var shortWindowBaseDurationRatio: Double = 0.98

    var minimumObservedLineDuration: TimeInterval = 0.8
    var maximumObservedLineDuration: TimeInterval = 8.0
    var minimumObservedRate: Double = 1.2
    var maximumObservedRate: Double = 8.0

    var shortPunctuationPause: TimeInterval = 0.08
    var mediumPunctuationPause: TimeInterval = 0.14
    var longPunctuationPause: TimeInterval = 0.22

    var noPunctuationFinalHoldRatio: Double = 0.70
    var longPunctuationFinalHoldRatio: Double = 0.85
    var shortPunctuationFinalHoldRatio: Double = 0.52
    var sentencePunctuationFinalHoldRatio: Double = 0.32

    var fallbackTrailingRestDuration: TimeInterval = 0.9
    var minimumFallbackLineDuration: TimeInterval = 1.5
    var maximumFallbackLineDuration: TimeInterval = 4.5
}

struct PlaybackTimeAnchor: Equatable, Sendable {
    let mediaTime: TimeInterval
    let hostTime: CFTimeInterval
    let playbackRate: Double

    init(
        mediaTime: TimeInterval,
        playbackRate: Double,
        hostTime: CFTimeInterval = CACurrentMediaTime()
    ) {
        self.mediaTime = max(0, mediaTime)
        self.playbackRate = max(0, playbackRate)
        self.hostTime = hostTime
    }

    static func anchored(to elapsed: TimeInterval, isPlaying: Bool) -> PlaybackTimeAnchor {
        PlaybackTimeAnchor(mediaTime: elapsed, playbackRate: isPlaying ? 1 : 0)
    }

    func estimatedTime(at hostTime: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval {
        max(0, mediaTime + max(0, hostTime - self.hostTime) * playbackRate)
    }
}

enum LyricPlaybackTiming {
    /// Word highlighting follows playback time exactly. Presentation surfaces
    /// may move to the next line early, but must not advance its sung progress.
    static let revealOffset: TimeInterval = 0
}

struct LyricTimingEstimator: Sendable {
    let configuration: LyricTimingEstimatorConfiguration

    init(configuration: LyricTimingEstimatorConfiguration = .init()) {
        self.configuration = configuration
    }

    func estimate(
        lines: [LyricLine],
        songDuration: TimeInterval?
    ) -> [EstimatedLyricLine] {
        guard !lines.isEmpty else { return [] }

        let tokensByLine = lines.map { tokenize(displayText(for: $0)) }
        let observedDurations = lines.indices.compactMap {
            observedDuration(at: $0, lines: lines)
        }

        return lines.indices.map { index in
            estimateLine(
                at: index,
                lines: lines,
                tokensByLine: tokensByLine,
                songDuration: songDuration,
                observedDurations: observedDurations
            )
        }
    }

    private func estimateLine(
        at index: Int,
        lines: [LyricLine],
        tokensByLine: [[Token]],
        songDuration: TimeInterval?,
        observedDurations: [TimeInterval]
    ) -> EstimatedLyricLine {
        let line = lines[index]
        let text = displayText(for: line)
        let tokens = tokensByLine[index]
        let lineStart = max(0, line.startTimeMS / 1000)
        let localRate = localRate(
            around: index,
            lines: lines,
            tokensByLine: tokensByLine
        )
        let lineEnd = resolvedLineEnd(
            at: index,
            lines: lines,
            tokens: tokens,
            localRate: localRate,
            songDuration: songDuration,
            observedDurations: observedDurations
        )
        let lineDuration = max(0.05, lineEnd - lineStart)

        if let exact = exactTimedLine(
            sourceIndex: index,
            line: line,
            text: text,
            lineStart: lineStart,
            resolvedLineEnd: lineEnd,
            localRate: localRate
        ) {
            return exact
        }

        let vocalIndices = tokens.indices.filter { tokens[$0].kind.isVocal }

        guard let finalVocalIndex = vocalIndices.last else {
            let units = tokens.enumerated().map { unitIndex, token in
                EstimatedLyricUnit(
                    id: unitIndex,
                    text: token.text,
                    startTime: lineStart,
                    endTime: lineStart,
                    range: token.range,
                    kind: token.kind
                )
            }
            return EstimatedLyricLine(
                id: line.id,
                sourceIndex: index,
                text: text,
                lineStartTime: lineStart,
                vocalEndTime: lineStart,
                lineEndTime: lineEnd,
                units: units,
                localRate: localRate,
                baseVocalDuration: 0,
                finalHoldDuration: 0,
                trailingRestDuration: lineDuration,
                precision: .estimated
            )
        }

        var unitDurations = Array(repeating: TimeInterval.zero, count: tokens.count)
        var punctuationPauses = Array(repeating: TimeInterval.zero, count: tokens.count)

        for tokenIndex in vocalIndices {
            unitDurations[tokenIndex] = min(
                configuration.maximumNormalUnitDuration,
                max(
                    configuration.minimumUnitDuration,
                    tokens[tokenIndex].weight / localRate
                )
            )
        }

        for tokenIndex in tokens.indices where tokens[tokenIndex].kind == .punctuation {
            guard vocalIndices.contains(where: { $0 > tokenIndex }) else { continue }
            punctuationPauses[tokenIndex] = punctuationPause(for: tokens[tokenIndex].text)
        }

        let unscaledBase = unitDurations.reduce(0, +) + punctuationPauses.reduce(0, +)
        let baseRatio = lineDuration < 1.2
            ? configuration.shortWindowBaseDurationRatio
            : configuration.maximumBaseDurationRatio
        let maximumBase = max(0.05, lineDuration * baseRatio)
        let scale = unscaledBase > maximumBase && unscaledBase > 0
            ? maximumBase / unscaledBase
            : 1

        if scale < 1 {
            unitDurations = unitDurations.map { $0 * scale }
            punctuationPauses = punctuationPauses.map { $0 * scale }
        }

        let baseDuration = unitDurations.reduce(0, +) + punctuationPauses.reduce(0, +)
        let extraDuration = max(0, lineDuration - baseDuration)
        let finalHoldLimit = vocalIndices.count <= 3
            ? configuration.shortLineMaximumFinalHoldDuration
            : configuration.maximumFinalHoldDuration
        let finalHold = min(
            finalHoldLimit,
            extraDuration * finalHoldRatio(for: trailingPunctuation(in: tokens))
        )
        let trailingRest = max(0, extraDuration - finalHold)

        var cursor = lineStart
        var units: [EstimatedLyricUnit] = []
        units.reserveCapacity(tokens.count)

        for tokenIndex in tokens.indices {
            let token = tokens[tokenIndex]
            let start = cursor
            var duration = unitDurations[tokenIndex]
            if tokenIndex == finalVocalIndex {
                duration += finalHold
            }
            let end = start + duration

            units.append(EstimatedLyricUnit(
                id: tokenIndex,
                text: token.text,
                startTime: start,
                endTime: end,
                range: token.range,
                kind: token.kind
            ))

            cursor = end + punctuationPauses[tokenIndex]
        }

        let vocalEnd = min(lineEnd, lineStart + baseDuration + finalHold)
        let result = EstimatedLyricLine(
            id: line.id,
            sourceIndex: index,
            text: text,
            lineStartTime: lineStart,
            vocalEndTime: vocalEnd,
            lineEndTime: lineEnd,
            units: units,
            localRate: localRate,
            baseVocalDuration: baseDuration,
            finalHoldDuration: finalHold,
            trailingRestDuration: max(trailingRest, lineEnd - vocalEnd),
            precision: .estimated
        )

        logDebugTiming(result)
        return result
    }

    private func exactTimedLine(
        sourceIndex: Int,
        line: LyricLine,
        text: String,
        lineStart: TimeInterval,
        resolvedLineEnd: TimeInterval,
        localRate: Double
    ) -> EstimatedLyricLine? {
        guard line.hasExactWordTiming,
              let timedUnits = line.timedUnits,
              timedUnits.map(\.text).joined() == text else {
            return nil
        }

        var utf16Offset = 0
        let units = timedUnits.compactMap { timedUnit -> EstimatedLyricUnit? in
            guard !timedUnit.text.isEmpty else { return nil }
            let length = timedUnit.text.utf16.count
            let range = utf16Offset..<(utf16Offset + length)
            utf16Offset += length

            let start = max(lineStart, timedUnit.startTimeMS / 1_000)
            let end = max(start, timedUnit.endTimeMS / 1_000)
            return EstimatedLyricUnit(
                id: range.lowerBound,
                text: timedUnit.text,
                startTime: start,
                endTime: end,
                range: range,
                kind: unitKind(for: timedUnit.text)
            )
        }
        guard !units.isEmpty, utf16Offset == text.utf16.count else { return nil }

        let vocalUnits = units.filter(\.kind.isVocal)
        let vocalEnd = max(
            lineStart,
            vocalUnits.map(\.endTime).max() ?? units.map(\.endTime).max() ?? lineStart
        )
        let lineEnd = max(resolvedLineEnd, vocalEnd)
        let firstVocalStart = vocalUnits.map(\.startTime).min() ?? lineStart

        return EstimatedLyricLine(
            id: line.id,
            sourceIndex: sourceIndex,
            text: text,
            lineStartTime: lineStart,
            vocalEndTime: vocalEnd,
            lineEndTime: lineEnd,
            units: units,
            localRate: localRate,
            baseVocalDuration: max(0, vocalEnd - firstVocalStart),
            finalHoldDuration: 0,
            trailingRestDuration: max(0, lineEnd - vocalEnd),
            precision: .exactWord
        )
    }

    private func unitKind(for text: String) -> LyricUnitKind {
        let characters = Array(text)
        if characters.allSatisfy(isWhitespace) {
            return .whitespace
        }
        if characters.allSatisfy(isDigit) {
            return .number
        }
        if characters.contains(where: isCJK) {
            return .chineseCharacter
        }
        if characters.contains(where: isWordLetter) {
            return .englishWord
        }
        return .punctuation
    }

    private func localRate(
        around index: Int,
        lines: [LyricLine],
        tokensByLine: [[Token]]
    ) -> Double {
        let lowerBound = max(0, index - configuration.localContextRadius)
        let upperBound = min(lines.count - 1, index + configuration.localContextRadius)
        var samples: [Double] = []

        guard lowerBound <= upperBound else { return configuration.defaultRate }

        for sampleIndex in lowerBound...upperBound where sampleIndex != index {
            let text = displayText(for: lines[sampleIndex])
            guard !isMetadataLine(text),
                  let duration = observedDuration(at: sampleIndex, lines: lines),
                  configuration.minimumObservedLineDuration...configuration.maximumObservedLineDuration ~= duration else {
                continue
            }

            let weight = tokensByLine[sampleIndex]
                .filter { $0.kind.isVocal }
                .reduce(0) { $0 + $1.weight }
            guard weight >= 2 else { continue }

            let rate = weight / duration
            guard configuration.minimumObservedRate...configuration.maximumObservedRate ~= rate else {
                continue
            }
            samples.append(rate)
        }

        let rate = median(samples) ?? configuration.defaultRate
        return min(max(rate, configuration.minimumRate), configuration.maximumRate)
    }

    private func resolvedLineEnd(
        at index: Int,
        lines: [LyricLine],
        tokens: [Token],
        localRate: Double,
        songDuration: TimeInterval?,
        observedDurations: [TimeInterval]
    ) -> TimeInterval {
        let start = max(0, lines[index].startTimeMS / 1000)
        if let nextStart = nextLaterStart(after: index, lines: lines) {
            return nextStart
        }

        if let songDuration,
           songDuration.isFinite,
           songDuration > start + 0.05 {
            return songDuration
        }

        let localMedian = median(observedDurations.filter {
            configuration.minimumObservedLineDuration...configuration.maximumObservedLineDuration ~= $0
        })
        let vocalWeight = tokens
            .filter { $0.kind.isVocal }
            .reduce(0) { $0 + $1.weight }
        let estimated = vocalWeight / max(localRate, 0.1)
            + configuration.fallbackTrailingRestDuration
        let fallback = localMedian ?? min(
            configuration.maximumFallbackLineDuration,
            max(configuration.minimumFallbackLineDuration, estimated)
        )
        return start + max(0.05, fallback)
    }

    private func observedDuration(at index: Int, lines: [LyricLine]) -> TimeInterval? {
        let start = lines[index].startTimeMS / 1000
        guard let nextStart = nextLaterStart(after: index, lines: lines) else { return nil }
        let duration = nextStart - start
        return duration.isFinite && duration > 0 ? duration : nil
    }

    private func nextLaterStart(after index: Int, lines: [LyricLine]) -> TimeInterval? {
        guard lines.indices.contains(index) else { return nil }
        let start = lines[index].startTimeMS / 1000
        guard index + 1 < lines.count else { return nil }

        for candidate in lines[(index + 1)...] {
            let candidateStart = candidate.startTimeMS / 1000
            if candidateStart > start + 0.05 {
                return candidateStart
            }
        }
        return nil
    }

    private func displayText(for line: LyricLine) -> String {
        let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { return words }
        return line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        var utf16Offset = 0

        while index < text.endIndex {
            let character = text[index]
            let startOffset = utf16Offset

            if isWhitespace(character) {
                let (tokenText, nextIndex, utf16Length) = consume(
                    from: index,
                    in: text,
                    while: isWhitespace
                )
                tokens.append(Token(
                    text: tokenText,
                    range: startOffset..<(startOffset + utf16Length),
                    kind: .whitespace,
                    weight: 0
                ))
                index = nextIndex
                utf16Offset += utf16Length
                continue
            }

            if isDigit(character) {
                let (tokenText, nextIndex, utf16Length) = consume(
                    from: index,
                    in: text,
                    while: isDigit
                )
                let digitCount = tokenText.count
                tokens.append(Token(
                    text: tokenText,
                    range: startOffset..<(startOffset + utf16Length),
                    kind: .number,
                    weight: min(2, max(1, 0.75 + Double(digitCount) * 0.25))
                ))
                index = nextIndex
                utf16Offset += utf16Length
                continue
            }

            if isWordLetter(character) {
                let (tokenText, nextIndex, utf16Length) = consumeWord(
                    from: index,
                    in: text
                )
                tokens.append(Token(
                    text: tokenText,
                    range: startOffset..<(startOffset + utf16Length),
                    kind: .englishWord,
                    weight: Double(estimatedSyllables(in: tokenText))
                ))
                index = nextIndex
                utf16Offset += utf16Length
                continue
            }

            if isCJK(character) {
                let tokenText = String(character)
                let utf16Length = tokenText.utf16.count
                tokens.append(Token(
                    text: tokenText,
                    range: startOffset..<(startOffset + utf16Length),
                    kind: .chineseCharacter,
                    weight: 1
                ))
                index = text.index(after: index)
                utf16Offset += utf16Length
                continue
            }

            let (tokenText, nextIndex, utf16Length) = consumePunctuation(
                from: index,
                in: text
            )
            tokens.append(Token(
                text: tokenText,
                range: startOffset..<(startOffset + utf16Length),
                kind: .punctuation,
                weight: 0
            ))
            index = nextIndex
            utf16Offset += utf16Length
        }

        return tokens
    }

    private func consume(
        from start: String.Index,
        in text: String,
        while predicate: (Character) -> Bool
    ) -> (String, String.Index, Int) {
        var end = start
        while end < text.endIndex, predicate(text[end]) {
            end = text.index(after: end)
        }
        let token = String(text[start..<end])
        return (token, end, token.utf16.count)
    }

    private func consumeWord(
        from start: String.Index,
        in text: String
    ) -> (String, String.Index, Int) {
        var end = start
        var consumedLetter = false

        while end < text.endIndex {
            let character = text[end]
            if isWordLetter(character) {
                consumedLetter = true
                end = text.index(after: end)
                continue
            }

            if consumedLetter,
               isApostrophe(character) {
                let afterApostrophe = text.index(after: end)
                if afterApostrophe < text.endIndex, isWordLetter(text[afterApostrophe]) {
                    end = afterApostrophe
                    continue
                }
            }
            break
        }

        let token = String(text[start..<end])
        return (token, end, token.utf16.count)
    }

    private func consumePunctuation(
        from start: String.Index,
        in text: String
    ) -> (String, String.Index, Int) {
        var end = start
        while end < text.endIndex {
            let character = text[end]
            if isWhitespace(character)
                || isDigit(character)
                || isWordLetter(character)
                || isCJK(character) {
                break
            }
            end = text.index(after: end)
        }
        let token = String(text[start..<end])
        return (token, end, token.utf16.count)
    }

    private func punctuationPause(for text: String) -> TimeInterval {
        if text.contains(where: { "…～~".contains($0) }) {
            return configuration.longPunctuationPause
        }
        if text.contains(where: { "。！？!?.".contains($0) }) {
            return configuration.mediumPunctuationPause
        }
        if text.contains(where: { "，、,；;：:".contains($0) }) {
            return configuration.shortPunctuationPause
        }
        return 0
    }

    private func trailingPunctuation(in tokens: [Token]) -> String? {
        for token in tokens.reversed() {
            switch token.kind {
            case .whitespace:
                continue
            case .punctuation:
                return token.text
            default:
                return nil
            }
        }
        return nil
    }

    private func finalHoldRatio(for punctuation: String?) -> Double {
        guard let punctuation else {
            return configuration.noPunctuationFinalHoldRatio
        }
        if punctuation.contains(where: { "…～~".contains($0) }) {
            return configuration.longPunctuationFinalHoldRatio
        }
        if punctuation.contains(where: { "，、,".contains($0) }) {
            return configuration.shortPunctuationFinalHoldRatio
        }
        if punctuation.contains(where: { "。！？!?.".contains($0) }) {
            return configuration.sentencePunctuationFinalHoldRatio
        }
        return configuration.noPunctuationFinalHoldRatio
    }

    private func estimatedSyllables(in word: String) -> Int {
        let vowels = CharacterSet(charactersIn: "aeiouy")
        var count = 0
        var previousWasVowel = false

        for scalar in word.lowercased().unicodeScalars {
            let isVowel = vowels.contains(scalar)
            if isVowel && !previousWasVowel {
                count += 1
            }
            previousWasVowel = isVowel
        }
        return max(1, count)
    }

    private func isMetadataLine(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prefixes = [
            "作词", "作曲", "编曲", "制作人", "混音", "母带",
            "间奏", "前奏", "instrumental", "lyrics by", "music by"
        ]
        return prefixes.contains { normalized.hasPrefix($0) }
    }

    private func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    private func isWordLetter(_ character: Character) -> Bool {
        !isCJK(character)
            && character.unicodeScalars.contains(where: CharacterSet.letters.contains)
    }

    private func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x3040...0x30FF,
                 0xAC00...0xD7AF:
                true
            default:
                false
            }
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func logDebugTiming(_ line: EstimatedLyricLine) {
        #if DEBUG && !SWIFT_PACKAGE
        print(
            """
            Lyric timing:
            text = \(line.text)
            lineDuration = \(String(format: "%.2f", line.lineEndTime - line.lineStartTime))
            units = \(line.units.filter(\.kind.isVocal).count)
            localRate = \(String(format: "%.2f", line.localRate))
            baseDuration = \(String(format: "%.2f", line.baseVocalDuration))
            finalHold = \(String(format: "%.2f", line.finalHoldDuration))
            trailingRest = \(String(format: "%.2f", line.trailingRestDuration))
            vocalEndTime = \(String(format: "%.2f", line.vocalEndTime))
            """
        )
        #endif
    }

    private struct Token: Sendable {
        let text: String
        let range: Range<Int>
        let kind: LyricUnitKind
        let weight: Double
    }
}
