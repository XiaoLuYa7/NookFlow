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
        detail: "Apple Music / Spotify",
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

    static let defaults = PlaybackAccessConfiguration(
        appleMusic: true,
        spotify: false
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
    }
}

enum PlaybackArtworkSource: Equatable {
    case file(URL, version: TimeInterval)
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
    private let commandQueue = DispatchQueue(label: "com.personal.L-Nook.playback-command")
    private let liveSeekLock = NSLock()
    private var latestLiveSeekCommand: PlaybackCommand?
    private var isLiveSeekDraining = false
    private var notificationObserver: Any?
    private var artworkLookupTask: Task<Void, Never>?
    private var lastArtworkLookupKey: String?
    private var fallbackArtworkDataByKey: [String: Data] = [:]

    @MainActor
    init(settings: IslandSettings) {
        accessConfiguration = Self.accessConfiguration(from: settings)
    }

    @MainActor
    func updateAccessConfiguration(from settings: IslandSettings) {
        accessConfiguration = Self.accessConfiguration(from: settings)
        refresh()
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }

        // Listen for Apple Music playback notifications for faster updates
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
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
                    self?.diagnosticText = result.diagnostic
                }
            }

            return
        }

        enqueueLiveSeek(command)
    }

    deinit {
        timer?.invalidate()
        artworkLookupTask?.cancel()
        cancelPendingLiveSeek()
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
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
                self?.diagnosticText = refreshedResult.diagnostic
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
        let access = resolvedAccessConfiguration()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.loadSnapshotResult(access: access)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      Date() >= self.ignoreExternalRefreshUntil else {
                    return
                }

                self.applySnapshot(result.snapshot)
                self.diagnosticText = result.diagnostic
            }
        }
    }

    private func resolvedAccessConfiguration() -> PlaybackAccessConfiguration {
        let access = PlaybackAccessConfiguration.persisted(fallback: accessConfiguration)
        accessConfiguration = access
        return access
    }

    @MainActor
    private static func accessConfiguration(from settings: IslandSettings) -> PlaybackAccessConfiguration {
        PlaybackAccessConfiguration(
            appleMusic: settings.allowAppleMusicAccess,
            spotify: settings.allowSpotifyAccess
        )
    }

    private func applySnapshot(_ snapshot: PlaybackSnapshot) {
        let enriched = snapshotWithCachedArtwork(snapshot)
        self.snapshot = enriched
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
            "access A\(access.appleMusic ? 1 : 0) S\(access.spotify ? 1 : 0)"
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
        let artwork = parts.indices.contains(7) ? artworkSource(from: parts[7]) : nil

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

    private static func artworkSource(from value: String) -> PlaybackArtworkSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") {
            return .remote(url)
        }

        if trimmed.hasPrefix("/") {
            let url = URL(fileURLWithPath: trimmed)
            return .file(url, version: artworkFileVersion(for: url))
        }

        return nil
    }

    private static func artworkFileVersion(for url: URL) -> TimeInterval {
        guard
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        else {
            return Date().timeIntervalSince1970
        }

        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = TimeInterval(values.fileSize ?? 0) / 1_000_000
        return modified + size
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
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard
            !query.isEmpty,
            let searchURL = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=musicTrack&media=music&limit=5&country=cn")
        else {
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

}
