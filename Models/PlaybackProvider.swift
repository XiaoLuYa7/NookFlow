import AppKit
import Foundation

struct PlaybackSnapshot: Equatable {
    var appName: String
    var state: PlaybackState
    var title: String
    var artist: String
    var album: String
    var detail: String
    var artworkSource: PlaybackArtworkSource?
    var duration: TimeInterval
    var elapsed: TimeInterval
    var isLive: Bool

    static let idle = PlaybackSnapshot(
        appName: "Media",
        state: .idle,
        title: "暂无播放",
        artist: "",
        album: "",
        detail: "支持多平台音乐",
        artworkSource: nil,
        duration: 0,
        elapsed: 0,
        isLive: false
    )

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var elapsedText: String {
        Self.timeText(elapsed)
    }

    var durationText: String {
        duration > 0 ? Self.timeText(duration) : "--:--"
    }

    var canSeek: Bool {
        isLive && duration > 0
    }

    func elapsedText(for progress: Double) -> String {
        guard canSeek else { return "--:--" }
        return Self.timeText(duration * min(max(progress, 0), 1))
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }

        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct PlaybackAccessConfiguration: Equatable {
    var appleMusic: Bool
    var spotify: Bool
    var qqMusic: Bool
    var netEaseMusic: Bool

    static let defaults = PlaybackAccessConfiguration(
        appleMusic: true,
        spotify: false,
        qqMusic: false,
        netEaseMusic: false
    )

    static func persisted(
        defaults: UserDefaults = .standard,
        fallback: PlaybackAccessConfiguration
    ) -> PlaybackAccessConfiguration {
        PlaybackAccessConfiguration(
            appleMusic: bool(
                for: Keys.allowAppleMusicAccess,
                defaults: defaults,
                fallback: fallback.appleMusic
            ),
            spotify: bool(
                for: Keys.allowSpotifyAccess,
                defaults: defaults,
                fallback: fallback.spotify
            ),
            qqMusic: bool(
                for: Keys.allowQQMusicAccess,
                defaults: defaults,
                fallback: fallback.qqMusic
            ),
            netEaseMusic: bool(
                for: Keys.allowNetEaseMusicAccess,
                defaults: defaults,
                fallback: fallback.netEaseMusic
            )
        )
    }

    private static func bool(
        for key: String,
        defaults: UserDefaults,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private enum Keys {
        static let allowAppleMusicAccess = "settings.allowAppleMusicAccess"
        static let allowSpotifyAccess = "settings.allowSpotifyAccess"
        static let allowQQMusicAccess = "settings.allowQQMusicAccess"
        static let allowNetEaseMusicAccess = "settings.allowNetEaseMusicAccess"
    }
}

enum PlaybackArtworkSource: Equatable {
    case file(URL, id: String)
    case imageData(Data, id: String)
    case remote(URL)
}

enum PlaybackState: Equatable {
    case playing
    case paused
    case idle

    var symbolName: String {
        switch self {
        case .playing:
            return "play.fill"
        case .paused:
            return "pause.fill"
        case .idle:
            return "waveform"
        }
    }

    var controlSymbolName: String {
        switch self {
        case .playing:
            return "pause.fill"
        case .paused, .idle:
            return "play.fill"
        }
    }

    var title: String {
        switch self {
        case .playing:
            return "正在播放"
        case .paused:
            return "已暂停"
        case .idle:
            return "当前播放"
        }
    }
}

final class PlaybackProvider: ObservableObject {

    @Published private(set) var snapshot: PlaybackSnapshot = .idle
    @Published private(set) var diagnosticText: String = ""

    private var accessConfiguration: PlaybackAccessConfiguration
    private var timer: Timer?
    private var ignoreExternalRefreshUntil = Date.distantPast
    private let commandQueue = DispatchQueue(label: "com.personal.NookFlow.playback-command")
    private let liveSeekLock = NSLock()
    private var latestLiveSeekCommand: PlaybackCommand?
    private var isLiveSeekDraining = false
    private var notificationObserver: Any?
    private var mediaRemoteObserver: Any?
    private var artworkLookupTask: Task<Void, Never>?
    private var lastArtworkLookupKey: String?
    private var fallbackArtworkDataByKey: [String: Data] = [:]
    private var isRefreshInFlight = false
    private var needsRefreshAfterCurrent = false
    private var refreshGeneration = 0

    @MainActor
    init(settings: IslandSettings) {
        accessConfiguration = Self.accessConfiguration(from: settings)
        configureMediaRemoteStream(from: settings)
    }

    @MainActor
    func updateAccessConfiguration(from settings: IslandSettings) {
        accessConfiguration = Self.accessConfiguration(from: settings)
        configureMediaRemoteStream(from: settings)
        refresh()
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // Listen for Apple Music playback notifications for faster updates
        if notificationObserver == nil {
            notificationObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.Music.playerInfo"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }

        if mediaRemoteObserver == nil {
            mediaRemoteObserver = NotificationCenter.default.addObserver(
                forName: .mediaRemoteStreamDidUpdate,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.applyMediaRemoteStreamUpdate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshGeneration += 1
        isRefreshInFlight = false
        needsRefreshAfterCurrent = false
        artworkLookupTask?.cancel()
        artworkLookupTask = nil
        cancelPendingLiveSeek()

        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }

        if let observer = mediaRemoteObserver {
            NotificationCenter.default.removeObserver(observer)
            mediaRemoteObserver = nil
        }
    }

    func togglePlayback() {
        runTransportCommand(.toggle, allowFallback: true)
    }

    func previousTrack() {
        runTransportCommand(.previous, allowFallback: false)
    }

    func nextTrack() {
        runTransportCommand(.next, allowFallback: false)
    }

    func seek(to progress: Double, refreshAfterSeek: Bool = true) {
        let appName = snapshot.appName
        let duration = snapshot.duration
        guard snapshot.canSeek else { return }

        let seconds = duration * min(max(progress, 0), 1)
        guard let command = Self.seekCommand(for: appName, seconds: seconds) else {
            return
        }

        if refreshAfterSeek {
            cancelPendingLiveSeek()
            let access = resolvedAccessConfiguration()

            var optimisticSnapshot = snapshot
            optimisticSnapshot.elapsed = seconds
            DispatchQueue.main.async { [weak self] in
                self?.ignoreExternalRefreshUntil = Date().addingTimeInterval(0.65)
                self?.snapshot = optimisticSnapshot
            }

            commandQueue.async { [weak self, command] in
                Self.runCommand(command)
                Thread.sleep(forTimeInterval: 0.12)

                let result = Self.loadSnapshotResult(access: access)
                DispatchQueue.main.async { [weak self] in
                    self?.ignoreExternalRefreshUntil = .distantPast
                    self?.applySnapshot(result.snapshot)
                    if self?.diagnosticText != result.diagnostic {
                        self?.diagnosticText = result.diagnostic
                    }
                }
            }

            return
        }

        enqueueLiveSeek(command)
    }

    deinit {
        stop()
    }

    private func runTransportCommand(_ commandKind: PlaybackTransportCommand, allowFallback: Bool) {
        let appName = snapshot.appName
        let originalSnapshot = snapshot
        let access = resolvedAccessConfiguration()

        commandQueue.async { [weak self, appName, originalSnapshot] in
            guard
                let command = Self.transportCommand(commandKind, for: appName)
                    ?? (allowFallback ? Self.firstRunningTransportCommand(commandKind) : nil)
            else {
                return
            }

            Self.runCommand(command)
            Thread.sleep(forTimeInterval: commandKind == .previous ? 0.22 : 0.12)

            var refreshedResult = Self.loadSnapshotResult(access: access)
            var refreshedSnapshot = refreshedResult.snapshot
            if commandKind == .previous,
               Self.representsSameTrack(originalSnapshot, refreshedSnapshot) {
                Self.runCommand(command)
                Thread.sleep(forTimeInterval: 0.18)
                refreshedResult = Self.loadSnapshotResult(access: access)
                refreshedSnapshot = refreshedResult.snapshot
            }

            DispatchQueue.main.async { [weak self] in
                self?.applySnapshot(refreshedSnapshot)
                if self?.diagnosticText != refreshedResult.diagnostic {
                    self?.diagnosticText = refreshedResult.diagnostic
                }
            }
        }
    }

    private static func representsSameTrack(
        _ lhs: PlaybackSnapshot,
        _ rhs: PlaybackSnapshot
    ) -> Bool {
        guard lhs.isLive, rhs.isLive else { return false }

        return lhs.title.normalized == rhs.title.normalized
            && lhs.artist.normalized == rhs.artist.normalized
            && lhs.album.normalized == rhs.album.normalized
    }

    private func enqueueLiveSeek(_ command: PlaybackCommand) {
        liveSeekLock.lock()
        latestLiveSeekCommand = command
        let shouldStartDraining = !isLiveSeekDraining
        if shouldStartDraining {
            isLiveSeekDraining = true
        }
        liveSeekLock.unlock()

        guard shouldStartDraining else {
            return
        }

        commandQueue.async { [weak self] in
            self?.drainLiveSeekCommands()
        }
    }

    private func drainLiveSeekCommands() {
        while true {
            liveSeekLock.lock()
            guard let command = latestLiveSeekCommand else {
                isLiveSeekDraining = false
                liveSeekLock.unlock()
                return
            }

            latestLiveSeekCommand = nil
            liveSeekLock.unlock()

            Self.runCommand(command)
            Thread.sleep(forTimeInterval: 0.035)
        }
    }

    private func cancelPendingLiveSeek() {
        liveSeekLock.lock()
        latestLiveSeekCommand = nil
        liveSeekLock.unlock()
    }

    private func refresh() {
        guard !isRefreshInFlight else {
            needsRefreshAfterCurrent = true
            return
        }

        isRefreshInFlight = true
        let generation = refreshGeneration
        let access = resolvedAccessConfiguration()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.loadSnapshotResult(access: access)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.refreshGeneration == generation
                else {
                    return
                }

                self.isRefreshInFlight = false

                guard
                      Date() >= self.ignoreExternalRefreshUntil else {
                    if self.needsRefreshAfterCurrent {
                        self.needsRefreshAfterCurrent = false
                        self.refresh()
                    }
                    return
                }

                self.applySnapshot(result.snapshot)
                if self.diagnosticText != result.diagnostic {
                    self.diagnosticText = result.diagnostic
                }

                if self.needsRefreshAfterCurrent {
                    self.needsRefreshAfterCurrent = false
                    self.refresh()
                }
            }
        }
    }

    private func resolvedAccessConfiguration() -> PlaybackAccessConfiguration {
        let access = PlaybackAccessConfiguration.persisted(fallback: accessConfiguration)
        accessConfiguration = access
        return access
    }

    private func applyMediaRemoteStreamUpdate() {
        let access = resolvedAccessConfiguration()
        let allowedBundleIdentifiers = SystemNowPlayingMetadataParser.allowedBundleIdentifiers(
            qqMusic: access.qqMusic,
            netEaseMusic: access.netEaseMusic
        )
        if let systemSnapshot = MediaRemoteStreamBridge.shared.snapshot(
            allowedBundleIdentifiers: allowedBundleIdentifiers
        ) {
            applySnapshot(systemSnapshot)
            diagnosticText = "System stream \(systemSnapshot.appName) \(systemSnapshot.state)"
        } else {
            refresh()
        }
    }

    @MainActor
    private func configureMediaRemoteStream(from settings: IslandSettings) {
        let allowedBundleIdentifiers = SystemNowPlayingMetadataParser.allowedBundleIdentifiers(
            qqMusic: settings.allowQQMusicAccess,
            netEaseMusic: settings.allowNetEaseMusicAccess
        )
        let mediaFeaturesEnabled = settings.showMediaModule
            || settings.showMusicLyrics
            || settings.showDesktopLyrics
        MediaRemoteStreamBridge.shared.configure(
            isEnabled: mediaFeaturesEnabled,
            allowedBundleIdentifiers: allowedBundleIdentifiers
        )
    }

    @MainActor
    private static func accessConfiguration(from settings: IslandSettings) -> PlaybackAccessConfiguration {
        PlaybackAccessConfiguration(
            appleMusic: settings.allowAppleMusicAccess,
            spotify: settings.allowSpotifyAccess,
            qqMusic: settings.allowQQMusicAccess,
            netEaseMusic: settings.allowNetEaseMusicAccess
        )
    }

    private func applySnapshot(_ snapshot: PlaybackSnapshot) {
        let enriched = snapshotWithCachedArtwork(snapshot)
        if self.snapshot != enriched {
            self.snapshot = enriched
        }
        loadFallbackArtworkIfNeeded(for: enriched)
    }

    private func snapshotWithCachedArtwork(_ snapshot: PlaybackSnapshot) -> PlaybackSnapshot {
        guard
            Self.shouldUseFallbackArtwork(for: snapshot.artworkSource),
            let key = Self.artworkLookupKey(for: snapshot),
            let data = fallbackArtworkDataByKey[key]
        else {
            return snapshot
        }

        var enriched = snapshot
        enriched.artworkSource = .imageData(data, id: key)
        return enriched
    }

    private func loadFallbackArtworkIfNeeded(for snapshot: PlaybackSnapshot) {
        guard
            Self.shouldUseFallbackArtwork(for: snapshot.artworkSource),
            let key = Self.artworkLookupKey(for: snapshot)
        else {
            return
        }

        guard fallbackArtworkDataByKey[key] == nil,
              lastArtworkLookupKey != key else {
            return
        }

        lastArtworkLookupKey = key
        artworkLookupTask?.cancel()

        let title = snapshot.title
        let artist = snapshot.artist
        let album = snapshot.album
        artworkLookupTask = Task.detached(priority: .utility) { [weak self] in
            guard let data = await Self.fetchITunesArtworkData(title: title, artist: artist, album: album),
                  !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self else { return }

                self.fallbackArtworkDataByKey[key] = data
                self.trimFallbackArtworkCache()

                guard Self.artworkLookupKey(for: self.snapshot) == key,
                      Self.shouldUseFallbackArtwork(for: self.snapshot.artworkSource) else {
                    return
                }

                var enriched = self.snapshot
                enriched.artworkSource = .imageData(data, id: key)
                self.snapshot = enriched
            }
        }
    }

    private func trimFallbackArtworkCache() {
        guard fallbackArtworkDataByKey.count > 8 else { return }

        for key in fallbackArtworkDataByKey.keys.prefix(fallbackArtworkDataByKey.count - 8) {
            fallbackArtworkDataByKey.removeValue(forKey: key)
        }
    }

    private static func loadSnapshot(access: PlaybackAccessConfiguration) -> PlaybackSnapshot {
        loadSnapshotResult(access: access).snapshot
    }

    private static func loadSnapshotResult(access: PlaybackAccessConfiguration) -> (
        snapshot: PlaybackSnapshot,
        diagnostic: String
    ) {
        let result = loadAudioSnapshotResult(access: access)
        return (result.snapshot ?? .idle, result.diagnostic)
    }

    private static func loadAudioSnapshot(access: PlaybackAccessConfiguration) -> PlaybackSnapshot? {
        loadAudioSnapshotResult(access: access).snapshot
    }

    private static func loadAudioSnapshotResult(access: PlaybackAccessConfiguration) -> (
        snapshot: PlaybackSnapshot?,
        diagnostic: String
    ) {
        var snapshots: [PlaybackSnapshot] = []
        var diagnostics: [String] = [
            "access A\(access.appleMusic ? 1 : 0) S\(access.spotify ? 1 : 0) Q\(access.qqMusic ? 1 : 0) N\(access.netEaseMusic ? 1 : 0)"
        ]

        let isMusicRunning = isApplicationRunning(bundleIdentifier: musicBundleIdentifier)
        diagnostics.append("Music running \(isMusicRunning ? 1 : 0)")
        if access.appleMusic, isMusicRunning {
            if let music = runPlaybackScript(musicScript) {
                snapshots.append(music)
                diagnostics.append("Music snapshot \(music.state)")
            } else {
                diagnostics.append("Music script nil")
            }
        }

        let isSpotifyRunning = isApplicationRunning(bundleIdentifier: spotifyBundleIdentifier)
        diagnostics.append("Spotify running \(isSpotifyRunning ? 1 : 0)")
        if access.spotify, isSpotifyRunning {
            if let spotify = runPlaybackScript(spotifyScript) {
                snapshots.append(spotify)
                diagnostics.append("Spotify snapshot \(spotify.state)")
            } else {
                diagnostics.append("Spotify script nil")
            }
        }

        let systemPlayerBundleIdentifiers = SystemNowPlayingMetadataParser.allowedBundleIdentifiers(
            qqMusic: access.qqMusic,
            netEaseMusic: access.netEaseMusic
        )
        if !systemPlayerBundleIdentifiers.isEmpty {
            if let systemPlayer = MediaRemoteStreamBridge.shared.snapshot(
                allowedBundleIdentifiers: systemPlayerBundleIdentifiers
            ) {
                snapshots.append(systemPlayer)
                diagnostics.append("System snapshot \(systemPlayer.appName) \(systemPlayer.state)")
            } else {
                diagnostics.append("System snapshot nil")
            }
        }

        let selected = snapshots.first { $0.state == .playing } ?? snapshots.first
        diagnostics.append("snapshots \(snapshots.count)")
        if let selected {
            diagnostics.append("selected \(selected.appName) \(selected.state)")
        }
        return (selected, diagnostics.joined(separator: " | "))
    }

    private static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private static func runPlaybackScript(_ source: String) -> PlaybackSnapshot? {
        guard let output = runScript(source), !output.isEmpty else {
            return nil
        }

        return snapshot(from: output)
    }

    private static func runCommand(_ command: PlaybackCommand) {
        switch command {
        case .script(let source):
            _ = runScript(source)
        case .system(let command):
            _ = MediaRemoteStreamBridge.shared.sendCommand(command)
        case .systemSeek(let seconds):
            _ = MediaRemoteStreamBridge.shared.seek(to: seconds)
        }
    }

    private static func runScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            return nil
        }

        return result.stringValue
    }

    private static func transportCommand(_ command: PlaybackTransportCommand, for appName: String) -> PlaybackCommand? {
        switch appName {
        case "Music":
            guard isApplicationRunning(bundleIdentifier: musicBundleIdentifier) else { return nil }
            return .script(musicTransportScript(command))
        case "Spotify":
            guard isApplicationRunning(bundleIdentifier: spotifyBundleIdentifier) else { return nil }
            return .script(spotifyTransportScript(command))
        case "QQ音乐", "网易云音乐":
            return .system(command.systemNowPlayingCommand)
        default:
            return nil
        }
    }

    private static func seekCommand(for appName: String, seconds: TimeInterval) -> PlaybackCommand? {
        let secondsText = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            max(seconds, 0)
        )

        switch appName {
        case "Music":
            guard isApplicationRunning(bundleIdentifier: musicBundleIdentifier) else { return nil }
            return .script(musicSeekScript(secondsText: secondsText))
        case "Spotify":
            guard isApplicationRunning(bundleIdentifier: spotifyBundleIdentifier) else { return nil }
            return .script(spotifySeekScript(secondsText: secondsText))
        case "QQ音乐", "网易云音乐":
            return .systemSeek(max(seconds, 0))
        default:
            return nil
        }
    }

    private static func firstRunningTransportCommand(_ command: PlaybackTransportCommand) -> PlaybackCommand? {
        if isApplicationRunning(bundleIdentifier: musicBundleIdentifier) {
            return .script(musicTransportScript(command))
        }

        if isApplicationRunning(bundleIdentifier: spotifyBundleIdentifier) {
            return .script(spotifyTransportScript(command))
        }

        return nil
    }

    private static func snapshot(from output: String) -> PlaybackSnapshot? {
        let parts = output.components(separatedBy: String(separatorCharacter))
        guard parts.count >= 7 else { return nil }

        let appName = parts[0]
        let state = state(from: parts[1])
        let title = parts[2].isEmpty ? "未命名媒体" : parts[2]
        let artist = parts[3]
        let album = parts[4]
        let duration = seconds(from: parts[5])
        let elapsed = seconds(from: parts[6])
        let artworkID = [
            appName,
            title,
            artist,
            album,
            String(Int(duration.rounded()))
        ]
            .map { $0.normalized }
            .joined(separator: "|")
        let artwork = parts.indices.contains(7)
            ? artworkSource(from: parts[7], id: artworkID)
            : nil

        let detailParts = [artist, album]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return PlaybackSnapshot(
            appName: appName,
            state: state,
            title: title,
            artist: artist,
            album: album,
            detail: detailParts.isEmpty ? state.title : detailParts.joined(separator: " · "),
            artworkSource: artwork,
            duration: duration,
            elapsed: elapsed,
            isLive: true
        )
    }

    private static func state(from value: String) -> PlaybackState {
        switch value.lowercased() {
        case "playing":
            return .playing
        case "paused":
            return .paused
        default:
            return .idle
        }
    }

    private static func seconds(from value: String) -> TimeInterval {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func artworkSource(from value: String, id: String) -> PlaybackArtworkSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") {
            return .remote(url)
        }

        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed)
            return .file(url, id: id)
        }

        return nil
    }

    private static func shouldUseFallbackArtwork(for source: PlaybackArtworkSource?) -> Bool {
        switch source {
        case .file, .imageData:
            return false
        case .remote, nil:
            return true
        }
    }

    private static func artworkLookupKey(for snapshot: PlaybackSnapshot) -> String? {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = snapshot.album.trimmingCharacters(in: .whitespacesAndNewlines)

        guard snapshot.isLive,
              !title.isEmpty,
              title != PlaybackSnapshot.idle.title,
              (!artist.isEmpty || !album.isEmpty) else {
            return nil
        }

        return [title, artist, album]
            .map { $0.normalized }
            .joined(separator: "|")
    }

    private static func fetchITunesArtworkData(title: String, artist: String, album: String) async -> Data? {
        let query = [title, artist, album]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "musicTrack"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "country", value: "cn")
        ]
        guard !query.isEmpty, let searchURL = components?.url else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: searchURL)
            let response = try JSONDecoder().decode(ITunesArtworkSearchResponse.self, from: data)
            guard let artworkURL = bestArtworkURL(
                from: response.results,
                title: title,
                artist: artist,
                album: album
            ) else {
                return nil
            }

            let (artworkData, _) = try await URLSession.shared.data(from: artworkURL)
            return artworkData
        } catch {
            return nil
        }
    }

    private static func bestArtworkURL(
        from tracks: [ITunesArtworkSearchResponse.Track],
        title: String,
        artist: String,
        album: String
    ) -> URL? {
        let normalizedTitle = title.normalized
        let normalizedArtist = artist.normalized
        let normalizedAlbum = album.normalized

        let ranked = tracks.sorted {
            score(track: $0, title: normalizedTitle, artist: normalizedArtist, album: normalizedAlbum)
                > score(track: $1, title: normalizedTitle, artist: normalizedArtist, album: normalizedAlbum)
        }

        guard let artwork = ranked.first?.artworkUrl100 else { return nil }
        let largerArtwork = artwork
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100-75", with: "600x600-75")
        return URL(string: largerArtwork)
    }

    private static func score(
        track: ITunesArtworkSearchResponse.Track,
        title: String,
        artist: String,
        album: String
    ) -> Int {
        var score = 0
        let trackTitle = track.trackName.normalized
        let trackArtist = track.artistName.normalized
        let trackAlbum = track.collectionName.normalized

        if trackTitle == title {
            score += 4
        } else if trackTitle.contains(title) || title.contains(trackTitle) {
            score += 2
        }

        if !artist.isEmpty {
            if trackArtist == artist {
                score += 3
            } else if trackArtist.contains(artist) || artist.contains(trackArtist) {
                score += 1
            }
        }

        if !album.isEmpty {
            if trackAlbum == album {
                score += 2
            } else if trackAlbum.contains(album) || album.contains(trackAlbum) {
                score += 1
            }
        }

        return score
    }

    private static let separatorCharacter = Character(UnicodeScalar(31))
    private static let musicBundleIdentifier = "com.apple.Music"
    private static let spotifyBundleIdentifier = "com.spotify.client"

    private struct ITunesArtworkSearchResponse: Decodable {
        let results: [Track]

        struct Track: Decodable {
            let trackName: String
            let artistName: String
            let collectionName: String
            let artworkUrl100: String
        }
    }

    private static func musicTransportScript(_ command: PlaybackTransportCommand) -> String {
        """
        tell application "Music"
            \(command.appleScriptCommand)
        end tell
        """
    }

    private static func spotifyTransportScript(_ command: PlaybackTransportCommand) -> String {
        """
        tell application "Spotify"
            \(command.appleScriptCommand)
        end tell
        """
    }

    private static func musicSeekScript(secondsText: String) -> String {
        """
        tell application "Music"
            set player position to \(secondsText)
        end tell
        """
    }

    private static func spotifySeekScript(secondsText: String) -> String {
        """
        tell application "Spotify"
            set player position to \(secondsText)
        end tell
        """
    }

    private static let musicScript = """
    if application "Music" is running then
        tell application "Music"
            if (player state is playing) or (player state is paused) then
                set sep to ASCII character 31
                try
                    set trackName to name of current track
                on error
                    set trackName to ""
                end try
                try
                    set artistName to artist of current track
                on error
                    set artistName to ""
                end try
                try
                    set albumName to album of current track
                on error
                    set albumName to ""
                end try
                try
                    set durationSeconds to duration of current track
                on error
                    set durationSeconds to 0
                end try
                try
                    set positionSeconds to player position
                on error
                    set positionSeconds to 0
                end try
                set artworkSource to ""
                try
                    set artworkData to data of (artwork 1 of current track)
                    set artworkFormat to (format of (artwork 1 of current track)) as text
                    set artworkExtension to "jpg"
                    if artworkFormat contains "PNG" then set artworkExtension to "png"
                    set artworkSource to (POSIX path of (path to temporary items)) & "lnook-current-artwork." & artworkExtension
                    set artworkFile to open for access (POSIX file artworkSource) with write permission
                    set eof artworkFile to 0
                    write artworkData to artworkFile starting at 0
                    close access artworkFile
                on error
                    try
                        close access (POSIX file artworkSource)
                    end try
                    set artworkSource to ""
                end try
                return "Music" & sep & (player state as text) & sep & trackName & sep & artistName & sep & albumName & sep & (durationSeconds as text) & sep & (positionSeconds as text) & sep & artworkSource
            end if
        end tell
    end if
    return ""
    """

    private static let spotifyScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            if (player state is playing) or (player state is paused) then
                set sep to ASCII character 31
                try
                    set trackName to name of current track
                on error
                    set trackName to ""
                end try
                try
                    set artistName to artist of current track
                on error
                    set artistName to ""
                end try
                try
                    set albumName to album of current track
                on error
                    set albumName to ""
                end try
                try
                    set durationSeconds to (duration of current track) / 1000
                on error
                    set durationSeconds to 0
                end try
                try
                    set positionSeconds to player position
                on error
                    set positionSeconds to 0
                end try
                try
                    set artworkSource to artwork url of current track
                on error
                    set artworkSource to ""
                end try
                return "Spotify" & sep & (player state as text) & sep & trackName & sep & artistName & sep & albumName & sep & (durationSeconds as text) & sep & (positionSeconds as text) & sep & artworkSource
            end if
        end tell
    end if
    return ""
    """
}

private enum PlaybackCommand {
    case script(String)
    case system(Int)
    case systemSeek(TimeInterval)
}

private enum PlaybackTransportCommand: Equatable {
    case toggle
    case previous
    case next

    var appleScriptCommand: String {
        switch self {
        case .toggle:
            return "playpause"
        case .previous:
            return "previous track"
        case .next:
            return "next track"
        }
    }

    var systemNowPlayingCommand: Int {
        switch self {
        case .toggle:
            return 2
        case .previous:
            return 5
        case .next:
            return 4
        }
    }

}

enum SystemNowPlayingMetadataParser {
    static let qqMusicBundleIdentifiers: Set<String> = [
        "com.tencent.QQMusicMac"
    ]

    static let netEaseMusicBundleIdentifiers: Set<String> = [
        "com.netease.163music",
        "com.netease.163music.mac",
        "com.netease.cloudmusic"
    ]

    static func allowedBundleIdentifiers(qqMusic: Bool, netEaseMusic: Bool) -> Set<String> {
        var identifiers: Set<String> = []
        if qqMusic {
            identifiers.formUnion(qqMusicBundleIdentifiers)
        }
        if netEaseMusic {
            identifiers.formUnion(netEaseMusicBundleIdentifiers)
        }
        return identifiers
    }

    static func snapshot(
        info: [String: Any],
        bundleIdentifier: String,
        isPlaying: Bool?,
        now: Date = Date()
    ) -> PlaybackSnapshot? {
        guard let appName = appName(for: bundleIdentifier) else { return nil }

        let title = stringValue(value(in: info, keys: Keys.title)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let artist = stringValue(value(in: info, keys: Keys.artist)).trimmingCharacters(in: .whitespacesAndNewlines)
        let album = stringValue(value(in: info, keys: Keys.album)).trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = max(0, numberValue(value(in: info, keys: Keys.duration)))
        var elapsed = max(0, numberValue(value(in: info, keys: Keys.elapsedTime)))
        let playbackRate = numberValue(value(in: info, keys: Keys.playbackRate))
        let resolvedIsPlaying = isPlaying ?? (playbackRate > 0.001)

        if resolvedIsPlaying,
           let timestamp = dateValue(value(in: info, keys: Keys.timestamp)) {
            elapsed += max(0, now.timeIntervalSince(timestamp)) * max(playbackRate, 0)
        }
        if duration > 0 {
            elapsed = min(elapsed, duration)
        }

        let detailParts = [artist, album].filter { !$0.isEmpty }
        let artworkSource: PlaybackArtworkSource?
        if let artworkData = value(in: info, keys: Keys.artworkData) as? Data, !artworkData.isEmpty {
            artworkSource = .imageData(
                artworkData,
                id: [bundleIdentifier, title, artist, album].joined(separator: "|")
            )
        } else {
            artworkSource = nil
        }

        return PlaybackSnapshot(
            appName: appName,
            state: resolvedIsPlaying ? .playing : .paused,
            title: title,
            artist: artist,
            album: album,
            detail: detailParts.isEmpty ? (resolvedIsPlaying ? "正在播放" : "已暂停") : detailParts.joined(separator: " · "),
            artworkSource: artworkSource,
            duration: duration,
            elapsed: elapsed,
            isLive: true
        )
    }

    private static func appName(for bundleIdentifier: String) -> String? {
        if qqMusicBundleIdentifiers.contains(bundleIdentifier) {
            return "QQ音乐"
        }
        if netEaseMusicBundleIdentifiers.contains(bundleIdentifier) {
            return "网易云音乐"
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func numberValue(_ value: Any?) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let number = value as? Double {
            return number
        }
        if let number = value as? String {
            return Double(number) ?? 0
        }
        return 0
    }

    private static func value(in info: [String: Any], keys: [String]) -> Any? {
        for key in keys where info[key] != nil {
            return info[key]
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        guard let text = value as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private enum Keys {
        static let title = ["title", "kMRMediaRemoteNowPlayingInfoTitle"]
        static let artist = ["artist", "kMRMediaRemoteNowPlayingInfoArtist"]
        static let album = ["album", "kMRMediaRemoteNowPlayingInfoAlbum"]
        static let duration = ["duration", "kMRMediaRemoteNowPlayingInfoDuration"]
        static let elapsedTime = ["elapsedTime", "kMRMediaRemoteNowPlayingInfoElapsedTime"]
        static let playbackRate = ["playbackRate", "kMRMediaRemoteNowPlayingInfoPlaybackRate"]
        static let artworkData = ["artworkData", "kMRMediaRemoteNowPlayingInfoArtworkData"]
        static let timestamp = ["timestamp", "kMRMediaRemoteNowPlayingInfoTimestamp"]
    }
}
