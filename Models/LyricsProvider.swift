import Combine
import Foundation
import SwiftUI

struct AsyncResultIdentity {
    static func matches<ID: Equatable>(
        currentID: ID?,
        requestedID: ID,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && currentID == requestedID
    }
}

enum LyricsDisplayState: Equatable {
    case idle
    case loading
    case ready
    case unavailable(String)

    var isLoading: Bool {
        self == .loading
    }

    var placeholderText: String? {
        guard case .unavailable(let text) = self else { return nil }
        return text
    }
}

private struct ScheduledLyricLine {
    let index: Int
    let deadline: TimeInterval
}

@MainActor
final class LyricsProvider: ObservableObject {

    @Published var lyrics: [LyricLine] = []
    @Published private(set) var estimatedTimeline: [EstimatedLyricLine] = []
    @Published var currentLineIndex: Int?
    @Published private(set) var capsuleLineIndex: Int?
    @Published var desktopPresentationLineIndex: Int?
    @Published var isLoading = false
    @Published var statusText: String = ""
    @Published private(set) var displayState: LyricsDisplayState = .idle

    private let networkService: any LyricsNetworking
    private let cache: any LyricsCaching
    private let timingEstimator: LyricTimingEstimator
    private var syncTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var nextTrackTransitionTask: Task<Void, Never>?
    private var queueObserver: AnyCancellable?
    private var currentLyricsRequestID: UUID?
    private var currentTrackKey: String?
    private var prefetchedTrackKey: String?
    private var lastElapsed: TimeInterval = -1
    private var syncAnchorDate: Date?
    private var syncAnchorElapsed: TimeInterval = 0
    private var latestPlaybackElapsed: TimeInterval = 0
    private var latestPlaybackState: PlaybackState = .idle
    private var timingCache: [String: [EstimatedLyricLine]] = [:]
    private var timingCacheOrder: [String] = []
    private let maximumTimingCacheEntries = 8
    private let lyricDisplayLeadTime: TimeInterval = 0.5
    private let desktopAnimationLeadTime: TimeInterval = 0.4
    private let nextTrackTransitionGracePeriod: TimeInterval = 1.2

    convenience init(observesMediaQueue: Bool = true) {
        self.init(
            networkService: LyricsNetworkService(),
            cache: LyricsCacheService(),
            timingEstimator: LyricTimingEstimator(),
            observesMediaQueue: observesMediaQueue
        )
    }

    init(
        networkService: any LyricsNetworking,
        cache: any LyricsCaching,
        timingEstimator: LyricTimingEstimator = LyricTimingEstimator(),
        observesMediaQueue: Bool = true
    ) {
        self.networkService = networkService
        self.cache = cache
        self.timingEstimator = timingEstimator
        guard observesMediaQueue else { return }
        queueObserver = NotificationCenter.default.publisher(for: .mediaRemoteQueueDidUpdate)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.prefetchNextTrackIfAvailable()
                }
            }
    }

    // MARK: - Public API

    /// Call when playback snapshot changes. Handles track change detection and lyrics loading.
    func update(for snapshot: PlaybackSnapshot, trackID: String?) {
        latestPlaybackElapsed = snapshot.elapsed
        latestPlaybackState = snapshot.state

        guard snapshot.isLive else {
            if currentTrackKey != nil {
                beginWaitingForNextTrack()
            }
            return
        }

        cancelNextTrackTransition()

        let trackKey = cache.cacheKey(
            for: trackID,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )

        // Track changed — start loading lyrics
        if trackKey != currentTrackKey {
            currentTrackKey = trackKey
            lastElapsed = -1
            stopSync()
            loadLyrics(
                title: snapshot.title,
                artist: snapshot.artist,
                album: snapshot.album,
                duration: snapshot.duration,
                trackID: trackID
            )
        }

        // Sync lyrics to playback position. Paused playback still needs one
        // position update, but must not keep a running timeline task.
        if snapshot.state == .playing, !lyrics.isEmpty {
            let syncIsActive = syncTask != nil
            let expectedElapsed = syncAnchorDate.map {
                syncAnchorElapsed + Date().timeIntervalSince($0)
            } ?? snapshot.elapsed
            let didSeek = syncIsActive && abs(snapshot.elapsed - expectedElapsed) > 0.75

            // The local monotonic clock drives normal playback. Re-anchor only
            // after a real seek or resume so periodic player polling cannot
            // cancel and recreate the lyric animation timeline every two seconds.
            if !syncIsActive || didSeek {
                lastElapsed = snapshot.elapsed
                updateCurrentLine(elapsed: snapshot.elapsed)
                restartSync(from: snapshot.elapsed)
            } else {
                lastElapsed = snapshot.elapsed
            }
        } else if snapshot.state == .paused {
            stopSync()
            guard !lyrics.isEmpty else { return }

            if lastElapsed < 0
                || currentLineIndex == nil
                || abs(snapshot.elapsed - lastElapsed) > 0.1 {
                lastElapsed = snapshot.elapsed
                updateCurrentLine(elapsed: snapshot.elapsed)
            }
        } else {
            stopSync()
        }
    }

    /// Called when user drags the progress bar.
    func seek(to elapsed: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        lastElapsed = elapsed
        updateCurrentLine(elapsed: elapsed)
        if latestPlaybackState == .playing {
            restartSync(from: elapsed)
        } else {
            stopSync()
        }
    }

    func estimatedLine(at sourceIndex: Int?) -> EstimatedLyricLine? {
        guard let sourceIndex else { return nil }
        return estimatedTimeline.first { $0.sourceIndex == sourceIndex }
    }

    func clear() {
        stopSync()
        fetchTask?.cancel()
        prefetchTask?.cancel()
        nextTrackTransitionTask?.cancel()
        fetchTask = nil
        prefetchTask = nil
        nextTrackTransitionTask = nil
        prefetchedTrackKey = nil
        currentLyricsRequestID = nil
        estimatedTimeline = []
        lyrics = []
        capsuleLineIndex = nil
        currentLineIndex = nil
        desktopPresentationLineIndex = nil
        currentTrackKey = nil
        lastElapsed = -1
        applyDisplayState(.idle)
    }

    func prefetch(_ track: MediaRemoteNextTrack) {
        let key = cache.cacheKey(
            for: track.trackID,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
        guard key != currentTrackKey, key != prefetchedTrackKey else { return }

        prefetchTask?.cancel()
        prefetchedTrackKey = key
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.prefetchedTrackKey == key {
                    self.prefetchTask = nil
                }
            }
            if await self.cache.get(key: key) != nil {
                return
            }
            guard !Task.isCancelled, self.prefetchedTrackKey == key else { return }

            let result = await self.networkService.searchAndFetchLyrics(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
            guard !Task.isCancelled, self.prefetchedTrackKey == key else { return }
            guard case .success(let lyrics) = result else { return }

            let prepared = await Self.prepareLyrics(
                lyrics,
                songDuration: track.duration,
                estimator: self.timingEstimator
            )
            guard !Task.isCancelled, self.prefetchedTrackKey == key else { return }

            let displayLyrics = prepared.lyrics
            let timeline = prepared.timeline
            self.storeTimingTimeline(timeline, for: key)
            await self.cache.set(
                key: key,
                title: track.title,
                artist: track.artist,
                lyrics: displayLyrics
            )
        }
    }

    // MARK: - Loading

    private func prefetchNextTrackIfAvailable() {
        guard let track = MediaRemoteStreamBridge.shared.nextTrack() else {
            prefetchTask?.cancel()
            prefetchTask = nil
            prefetchedTrackKey = nil
            return
        }
        prefetch(track)
    }

    private func loadLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        trackID: String?
    ) {
        fetchTask?.cancel()
        let requestID = UUID()
        currentLyricsRequestID = requestID
        // Publish loading before clearing the previous timeline so every lyric
        // surface transitions directly to loading instead of flashing empty.
        applyDisplayState(.loading)
        estimatedTimeline = []
        lyrics = []
        capsuleLineIndex = nil
        currentLineIndex = nil
        desktopPresentationLineIndex = nil

        let key = cache.cacheKey(
            for: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )

        fetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.currentLyricsRequestID == requestID {
                    self.fetchTask = nil
                }
            }

            if let cached = await self.cache.get(key: key) {
                let prepared = await Self.prepareLyrics(
                    cached,
                    songDuration: duration,
                    estimator: self.timingEstimator
                )
                guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }
                self.applyLyrics(
                    prepared.lyrics,
                    preparedTimeline: prepared.timeline,
                    timingCacheKey: key
                )
                self.applyDisplayState(prepared.lyrics.isEmpty ? .unavailable("暂无歌词") : .ready)
                self.startSyncIfNeeded()
                return
            }

            guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }

            let result = await self.networkService.searchAndFetchLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }

            switch result {
            case .success(let fetchedLyrics):
                let prepared = await Self.prepareLyrics(
                    fetchedLyrics,
                    songDuration: duration,
                    estimator: self.timingEstimator
                )
                guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }
                self.applyLyrics(
                    prepared.lyrics,
                    preparedTimeline: prepared.timeline,
                    timingCacheKey: key
                )
                self.applyDisplayState(prepared.lyrics.isEmpty ? .unavailable("暂无歌词") : .ready)
                self.startSyncIfNeeded()
                await self.cache.set(
                    key: key,
                    title: title,
                    artist: artist,
                    lyrics: prepared.lyrics
                )
            case .notFound:
                self.estimatedTimeline = []
                self.lyrics = []
                self.applyDisplayState(.unavailable("暂无歌词"))
                self.startSyncIfNeeded()
            }
        }
    }

    private func applyDisplayState(_ state: LyricsDisplayState) {
        displayState = state
        statusText = state.placeholderText ?? ""
        isLoading = state.isLoading
    }

    private func beginWaitingForNextTrack() {
        guard nextTrackTransitionTask == nil else { return }

        stopSync()
        fetchTask?.cancel()
        fetchTask = nil
        currentLyricsRequestID = nil
        currentTrackKey = nil
        lastElapsed = -1

        // Players can briefly publish an empty snapshot between two tracks.
        // Treat that gap as part of the next lyric request instead of exposing
        // an idle/empty state that flashes “暂无歌词”.
        applyDisplayState(.loading)
        estimatedTimeline = []
        lyrics = []
        capsuleLineIndex = nil
        currentLineIndex = nil
        desktopPresentationLineIndex = nil

        nextTrackTransitionTask = Task { @MainActor [weak self] in
            guard let gracePeriod = self?.nextTrackTransitionGracePeriod else { return }
            try? await Task.sleep(for: .seconds(gracePeriod))
            guard !Task.isCancelled, let self else { return }

            self.nextTrackTransitionTask = nil
            guard self.currentTrackKey == nil else { return }
            self.applyDisplayState(.idle)
        }
    }

    private func cancelNextTrackTransition() {
        nextTrackTransitionTask?.cancel()
        nextTrackTransitionTask = nil
    }

    private func isCurrentLyricsRequest(_ requestID: UUID, trackKey: String) -> Bool {
        AsyncResultIdentity.matches(
            currentID: currentLyricsRequestID,
            requestedID: requestID,
            isCancelled: Task.isCancelled
        )
            && currentTrackKey == trackKey
    }

    private nonisolated static func normalizedLyricsForDisplay(_ lyrics: [LyricLine]) -> [LyricLine] {
        lyrics.map { line in
            LyricLine(
                startTimeMS: line.startTimeMS,
                words: line.words.simplifiedChineseForLyricsDisplay,
                translation: line.translation?.simplifiedChineseForLyricsDisplay,
                source: line.source,
                timedUnits: line.timedUnits?.map { unit in
                    LyricTimedUnit(
                        text: unit.text.simplifiedChineseForLyricsDisplay,
                        startTimeMS: unit.startTimeMS,
                        durationMS: unit.durationMS
                    )
                }
            )
        }
    }

    private nonisolated static func prepareLyrics(
        _ lyrics: [LyricLine],
        songDuration: TimeInterval,
        estimator: LyricTimingEstimator
    ) async -> (lyrics: [LyricLine], timeline: [EstimatedLyricLine]) {
        let task = Task.detached(priority: .userInitiated) {
            () -> (lyrics: [LyricLine], timeline: [EstimatedLyricLine]) in
            guard !Task.isCancelled else { return ([], []) }
            let displayLyrics = normalizedLyricsForDisplay(lyrics)
            guard !Task.isCancelled else { return ([], []) }
            return (
                displayLyrics,
                estimator.estimate(lines: displayLyrics, songDuration: songDuration)
            )
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func applyLyrics(
        _ displayLyrics: [LyricLine],
        preparedTimeline: [EstimatedLyricLine],
        timingCacheKey: String
    ) {
        let timeline: [EstimatedLyricLine]
        if let cached = timingCache[timingCacheKey],
           cached.count == displayLyrics.count,
           zip(cached, displayLyrics).allSatisfy({ pair in
               pair.0.text == displayText(for: pair.1)
                   && abs(pair.0.lineStartTime - pair.1.startTimeMS / 1000) < 0.001
           }) {
            timeline = cached
            touchTimingCacheKey(timingCacheKey)
        } else {
            timeline = preparedTimeline
            storeTimingTimeline(timeline, for: timingCacheKey)
        }

        // Publish the derived timeline first so lyric surfaces never observe
        // a new line paired with timing from the previous track.
        estimatedTimeline = timeline
        lyrics = displayLyrics
    }

    private func displayText(for line: LyricLine) -> String {
        let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { return words }
        return line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func storeTimingTimeline(
        _ timeline: [EstimatedLyricLine],
        for key: String
    ) {
        timingCache[key] = timeline
        touchTimingCacheKey(key)

        while timingCacheOrder.count > maximumTimingCacheEntries {
            let removedKey = timingCacheOrder.removeFirst()
            timingCache.removeValue(forKey: removedKey)
        }
    }

    private func touchTimingCacheKey(_ key: String) {
        timingCacheOrder.removeAll { $0 == key }
        timingCacheOrder.append(key)
    }

    // MARK: - Sync

    /// Start sync if lyrics are available and playback is active. Called after lyrics load.
    private func startSyncIfNeeded() {
        guard !lyrics.isEmpty, currentTrackKey != nil else { return }
        if syncTask == nil {
            let elapsed = latestPlaybackState == .idle ? 0 : latestPlaybackElapsed
            lastElapsed = elapsed
            updateCurrentLine(elapsed: elapsed)
            if latestPlaybackState == .playing {
                restartSync(from: elapsed)
            }
        }
    }

    private func restartSync(from elapsed: TimeInterval) {
        syncTask?.cancel()

        let lyrics = self.lyrics
        guard !lyrics.isEmpty else { return }

        syncAnchorDate = Date()
        syncAnchorElapsed = elapsed
        syncTask = Task { [weak self] in
            guard let anchorDate = self?.syncAnchorDate else { return }

            while !Task.isCancelled {
                guard let self else { return }

                let currentTime = elapsed + Date().timeIntervalSince(anchorDate)
                let currentLineEvent = self.nextScheduledLine(
                    after: currentTime,
                    leadTime: self.lyricDisplayLeadTime,
                    in: lyrics
                )
                let desktopLineEvent = self.nextScheduledLine(
                    after: currentTime,
                    leadTime: self.desktopAnimationLeadTime,
                    in: lyrics
                )
                let capsuleLineEvent = self.nextScheduledLine(after: currentTime, leadTime: 0, in: lyrics)
                guard let nextDeadline = [
                    currentLineEvent?.deadline,
                    capsuleLineEvent?.deadline,
                    desktopLineEvent?.deadline
                ].compactMap({ $0 }).min() else {
                    break
                }

                let delay = max(0, nextDeadline - currentTime)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { break }

                let reachedTime = elapsed + Date().timeIntervalSince(anchorDate)
                let capsuleIndex = self.bestLineIndex(at: reachedTime, in: lyrics)
                if self.capsuleLineIndex != capsuleIndex {
                    self.capsuleLineIndex = capsuleIndex
                }
                if let currentLineEvent,
                   currentLineEvent.deadline <= reachedTime + 0.002 {
                    self.currentLineIndex = currentLineEvent.index
                }
                if let desktopLineEvent,
                   desktopLineEvent.deadline <= reachedTime + 0.002 {
                    self.desktopPresentationLineIndex = desktopLineEvent.index
                }
            }
        }
    }

    private func stopSync() {
        syncTask?.cancel()
        syncTask = nil
        syncAnchorDate = nil
    }

    private func updateCurrentLine(elapsed: TimeInterval) {
        let capsuleIndex = bestLineIndex(at: elapsed, in: lyrics)
        if capsuleLineIndex != capsuleIndex { capsuleLineIndex = capsuleIndex }
        let currentBestIndex = bestLineIndex(
            at: elapsed + lyricDisplayLeadTime,
            in: lyrics
        )
        let desktopBestIndex = bestLineIndex(
            at: elapsed + desktopAnimationLeadTime,
            in: lyrics
        )

        if currentLineIndex != currentBestIndex {
            currentLineIndex = currentBestIndex
        }

        if desktopPresentationLineIndex != desktopBestIndex {
            desktopPresentationLineIndex = desktopBestIndex
        }
    }

    private func bestLineIndex(
        at displayTime: TimeInterval,
        in lyrics: [LyricLine]
    ) -> Int? {
        let elapsedMS = displayTime * 1000
        var bestIndex: Int?

        for (index, line) in lyrics.enumerated() {
            if line.startTimeMS <= elapsedMS {
                bestIndex = index
            } else {
                break
            }
        }
        return bestIndex
    }

    private func nextScheduledLine(
        after currentTime: TimeInterval,
        leadTime: TimeInterval,
        in lyrics: [LyricLine]
    ) -> ScheduledLyricLine? {
        guard let index = findNextLineIndex(
            after: currentTime + leadTime,
            in: lyrics
        ) else {
            return nil
        }
        return ScheduledLyricLine(
            index: index,
            deadline: lyrics[index].startTimeMS / 1000 - leadTime
        )
    }

    private func findNextLineIndex(after elapsed: TimeInterval, in lyrics: [LyricLine]) -> Int? {
        let elapsedMS = elapsed * 1000
        for (index, line) in lyrics.enumerated() {
            if line.startTimeMS > elapsedMS {
                return index
            }
        }
        return nil
    }
}

private extension String {
    var simplifiedChineseForLyricsDisplay: String {
        guard !containsJapaneseKana else { return self }
        let mutable = NSMutableString(string: self)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    private var containsJapaneseKana: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x309F, 0x30A0...0x30FF, 0xFF66...0xFF9F:
                return true
            default:
                return false
            }
        }
    }
}
