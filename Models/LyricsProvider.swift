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

@MainActor
final class LyricsProvider: ObservableObject {

    @Published var lyrics: [LyricLine] = []
    @Published var currentLineIndex: Int?
    @Published var desktopPresentationLineIndex: Int?
    @Published var isLoading = false
    @Published var statusText: String = ""

    private let networkService: any LyricsNetworking
    private let cache: any LyricsCaching
    private var syncTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var currentLyricsRequestID: UUID?
    private var currentTrackKey: String?
    private var lastElapsed: TimeInterval = -1
    private var syncAnchorDate: Date?
    private var syncAnchorElapsed: TimeInterval = 0
    private var latestPlaybackElapsed: TimeInterval = 0
    private var latestPlaybackState: PlaybackState = .idle
    private let lyricDisplayLeadTime: TimeInterval = 0.5
    private let desktopAnimationLeadTime: TimeInterval = 0.5

    convenience init() {
        self.init(
            networkService: LyricsNetworkService(),
            cache: LyricsCacheService()
        )
    }

    init(networkService: any LyricsNetworking, cache: any LyricsCaching) {
        self.networkService = networkService
        self.cache = cache
    }

    // MARK: - Public API

    /// Call when playback snapshot changes. Handles track change detection and lyrics loading.
    func update(for snapshot: PlaybackSnapshot, trackID: String?) {
        latestPlaybackElapsed = snapshot.elapsed
        latestPlaybackState = snapshot.state

        guard snapshot.isLive else {
            if currentTrackKey != nil { clear() }
            return
        }

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

    func clear() {
        stopSync()
        fetchTask?.cancel()
        currentLyricsRequestID = nil
        lyrics = []
        currentLineIndex = nil
        desktopPresentationLineIndex = nil
        currentTrackKey = nil
        lastElapsed = -1
        statusText = ""
        isLoading = false
    }

    // MARK: - Loading

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
        lyrics = []
        currentLineIndex = nil
        desktopPresentationLineIndex = nil
        isLoading = true
        statusText = ""

        let key = cache.cacheKey(
            for: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )

        // Check cache first
        if let cached = cache.get(key: key) {
            let displayLyrics = normalizedLyricsForDisplay(cached)
            lyrics = displayLyrics
            isLoading = false
            statusText = displayLyrics.isEmpty ? "暂无歌词" : ""
            startSyncIfNeeded()
            return
        }

        // Fetch from network
        fetchTask = Task { [weak self] in
            guard let self else { return }

            // Get track ID if not provided (for better cache key)
            var effectiveTrackID = trackID
            if effectiveTrackID == nil {
                effectiveTrackID = await self.networkService.fetchITunesTrackID(title: title, artist: artist)
                guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }

                // Update cache key if we got a track ID
                if let newID = effectiveTrackID {
                    let newKey = self.cache.cacheKey(
                        for: newID,
                        title: title,
                        artist: artist,
                        album: album,
                        duration: duration
                    )
                    if newKey != key, let cached = self.cache.get(key: newKey) {
                        guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }
                        let displayLyrics = self.normalizedLyricsForDisplay(cached)
                        self.lyrics = displayLyrics
                        self.isLoading = false
                        self.statusText = displayLyrics.isEmpty ? "暂无歌词" : ""
                        self.startSyncIfNeeded()
                        return
                    }
                }
            }

            let result = await self.networkService.searchAndFetchLyrics(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            )
            guard self.isCurrentLyricsRequest(requestID, trackKey: key) else { return }

            switch result {
            case .success(let fetchedLyrics):
                let displayLyrics = self.normalizedLyricsForDisplay(fetchedLyrics)
                self.lyrics = displayLyrics
                self.statusText = displayLyrics.isEmpty ? "暂无歌词" : ""
                self.cache.set(key: key, title: title, artist: artist, lyrics: displayLyrics)
            case .notFound:
                self.lyrics = []
                self.statusText = "未找到歌词"
            }

            self.isLoading = false
            self.startSyncIfNeeded()
        }
    }

    private func isCurrentLyricsRequest(_ requestID: UUID, trackKey: String) -> Bool {
        AsyncResultIdentity.matches(
            currentID: currentLyricsRequestID,
            requestedID: requestID,
            isCancelled: Task.isCancelled
        )
            && currentTrackKey == trackKey
    }

    private func normalizedLyricsForDisplay(_ lyrics: [LyricLine]) -> [LyricLine] {
        lyrics.map { line in
            LyricLine(
                startTimeMS: line.startTimeMS,
                words: line.words.simplifiedChineseForLyricsDisplay,
                translation: line.translation?.simplifiedChineseForLyricsDisplay
            )
        }
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
                let displayTime = currentTime + self.lyricDisplayLeadTime
                let nextIndex = self.findNextLineIndex(after: displayTime, in: lyrics)
                guard let nextIndex, nextIndex < lyrics.count else { break }

                let nextTime = lyrics[nextIndex].startTimeMS / 1000
                let presentationDelay = max(0, nextTime - self.desktopAnimationLeadTime - currentTime)

                if presentationDelay > 0 {
                    try? await Task.sleep(for: .seconds(presentationDelay))
                }
                guard !Task.isCancelled else { break }

                self.desktopPresentationLineIndex = nextIndex

                let exactElapsed = elapsed + Date().timeIntervalSince(anchorDate)
                let exactDelay = max(0, nextTime - self.lyricDisplayLeadTime - exactElapsed)
                if exactDelay > 0 {
                    try? await Task.sleep(for: .seconds(exactDelay))
                }
                guard !Task.isCancelled else { break }

                self.currentLineIndex = nextIndex
            }
        }
    }

    private func stopSync() {
        syncTask?.cancel()
        syncTask = nil
        syncAnchorDate = nil
    }

    private func updateCurrentLine(elapsed: TimeInterval) {
        let elapsedMS = (elapsed + lyricDisplayLeadTime) * 1000
        var bestIndex: Int?

        for (index, line) in lyrics.enumerated() {
            if line.startTimeMS <= elapsedMS {
                bestIndex = index
            } else {
                break
            }
        }

        if currentLineIndex != bestIndex {
            currentLineIndex = bestIndex
        }

        if desktopPresentationLineIndex != bestIndex {
            desktopPresentationLineIndex = bestIndex
        }
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
