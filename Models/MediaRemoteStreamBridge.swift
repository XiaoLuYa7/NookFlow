import AppKit
import Foundation
import ImageIO

extension Notification.Name {
    static let mediaRemoteStreamDidUpdate = Notification.Name(
        "com.personal.NookFlow.media-remote-stream-did-update"
    )
    static let mediaRemoteQueueDidUpdate = Notification.Name(
        "com.personal.NookFlow.media-remote-queue-did-update"
    )
}

struct MediaRemoteNextTrack: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let trackID: String?

    init?(payload: [String: Any]) {
        guard
            let title = payload["title"] as? String,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        self.title = title
        artist = payload["artist"] as? String ?? ""
        album = payload["album"] as? String ?? ""
        duration = (payload["duration"] as? NSNumber)?.doubleValue ?? 0
        trackID = ["uniqueIdentifier", "contentItemIdentifier"]
            .compactMap { payload[$0] as? String }
            .first { !$0.isEmpty }
    }
}

/// Maintains one event-driven MediaRemote stream for players that do not expose AppleScript playback APIs.
final class MediaRemoteStreamBridge: @unchecked Sendable {
    static let shared = MediaRemoteStreamBridge()

    private struct StreamState {
        var values: [String: Any] = [:]
        var artworkData: Data?
        var artworkTrackID: String?
        var nextTrack: MediaRemoteNextTrack?
    }

    private enum ArtworkUpdate {
        case unchanged
        case clear
        case data(Data)
    }

    private let queue = DispatchQueue(label: "com.personal.NookFlow.media-remote-stream", qos: .utility)
    private let lock = NSLock()
    private var process: Process?
    private var outputPipe: Pipe?
    private var outputBuffer = Data()
    private var restartWorkItem: DispatchWorkItem?
    private var restartAttempt = 0
    private var shouldRun = false
    private var allowedBundleIdentifiers: Set<String> = []
    private var state = StreamState()
    private var artworkCache: [(trackID: String, data: Data)] = []

    private init() {}

    func configure(isEnabled: Bool, allowedBundleIdentifiers: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }

            self.lock.withLock {
                self.allowedBundleIdentifiers = allowedBundleIdentifiers
            }
            self.shouldRun = isEnabled && !allowedBundleIdentifiers.isEmpty
            if self.shouldRun {
                self.startIfNeeded()
            } else {
                self.stopProcess(clearSnapshot: true)
            }
        }
    }

    func shutdown() {
        queue.sync {
            shouldRun = false
            stopProcess(clearSnapshot: true)
        }
    }

    func snapshot(allowedBundleIdentifiers: Set<String>, now: Date = Date()) -> PlaybackSnapshot? {
        lock.withLock {
            guard
                let bundleIdentifier = state.values["bundleIdentifier"] as? String,
                allowedBundleIdentifiers.contains(bundleIdentifier)
            else {
                return nil
            }

            var info = state.values
            if let artworkData = state.artworkData {
                info["artworkData"] = artworkData
            }
            return SystemNowPlayingMetadataParser.snapshot(
                info: info,
                bundleIdentifier: bundleIdentifier,
                isPlaying: state.values["playing"] as? Bool,
                now: now
            )
        }
    }

    func nextTrack() -> MediaRemoteNextTrack? {
        lock.withLock {
            guard
                let bundleIdentifier = state.values["bundleIdentifier"] as? String,
                allowedBundleIdentifiers.contains(bundleIdentifier)
            else {
                return nil
            }
            return state.nextTrack
        }
    }

    @discardableResult
    func sendCommand(_ command: Int) -> Bool {
        runOneShot(arguments: ["send", String(command)])
    }

    @discardableResult
    func seek(to seconds: TimeInterval) -> Bool {
        let microseconds = Int64((max(0, seconds) * 1_000_000).rounded())
        return runOneShot(arguments: ["seek", String(microseconds)])
    }

    private func startIfNeeded() {
        guard shouldRun, process == nil else { return }
        guard let resources = Self.resources() else {
            publishEmptyStateIfNeeded()
            return
        }

        restartWorkItem?.cancel()
        restartWorkItem = nil

        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [
            resources.script.path,
            resources.framework.path,
            "stream",
            "--debounce=100"
        ]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                self?.consume(data)
            }
        }

        task.terminationHandler = { [weak self] finishedTask in
            self?.queue.async { [weak self] in
                self?.handleTermination(finishedTask)
            }
        }

        process = task
        outputPipe = pipe
        do {
            try task.run()
        } catch {
            process = nil
            outputPipe = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            scheduleRestart()
        }
    }

    private func stopProcess(clearSnapshot: Bool) {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        restartAttempt = 0

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        outputBuffer.removeAll(keepingCapacity: false)

        let runningProcess = process
        process = nil
        runningProcess?.terminationHandler = nil
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }

        if clearSnapshot {
            lock.withLock {
                state = StreamState()
                artworkCache.removeAll(keepingCapacity: false)
            }
            notifyUpdate()
        }
    }

    private func handleTermination(_ finishedTask: Process) {
        guard process === finishedTask else { return }

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: false)

        guard shouldRun else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard shouldRun, restartWorkItem == nil else { return }

        restartAttempt += 1
        let delay = min(pow(2, Double(max(restartAttempt - 1, 0))), 15)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWorkItem = nil
            self.startIfNeeded()
        }
        restartWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        guard outputBuffer.count <= 8 * 1_024 * 1_024 else {
            outputBuffer.removeAll(keepingCapacity: false)
            return
        }

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            consumeLine(Data(line))
        }
    }

    private func consumeLine(_ line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let type = object["type"] as? String,
            let payload = object["payload"] as? [String: Any]
        else {
            return
        }

        if type == "queue" {
            let nextTrack = MediaRemoteNextTrack(payload: payload)
            let didChange = lock.withLock { () -> Bool in
                guard state.nextTrack != nextTrack else { return false }
                state.nextTrack = nextTrack
                return true
            }
            if didChange {
                notifyQueueUpdate()
            }
            return
        }

        guard type == "data" else { return }

        let isDiff = object["diff"] as? Bool ?? false
        let artworkUpdate = preparedArtworkUpdate(from: payload["artworkData"])
        var didChange = false
        lock.withLock {
            didChange = apply(payload: payload, isDiff: isDiff, artworkUpdate: artworkUpdate)
        }
        if didChange {
            restartAttempt = 0
            notifyUpdate()
        }
    }

    private func apply(
        payload: [String: Any],
        isDiff: Bool,
        artworkUpdate: ArtworkUpdate
    ) -> Bool {
        let previousBundleIdentifier = state.values["bundleIdentifier"] as? String
        let previousTrackID = trackID(from: state.values)

        if !isDiff {
            state.values.removeAll(keepingCapacity: true)
        }

        for (key, value) in payload where key != "artworkData" {
            if value is NSNull {
                state.values.removeValue(forKey: key)
            } else {
                state.values[key] = value
            }
        }

        let newBundleIdentifier = state.values["bundleIdentifier"] as? String
        let newTrackID = trackID(from: state.values)
        let trackChanged = newTrackID != previousTrackID || newBundleIdentifier != previousBundleIdentifier
        if trackChanged {
            cacheCurrentArtwork()
            state.artworkData = cachedArtwork(for: newTrackID)
            state.artworkTrackID = state.artworkData == nil ? nil : newTrackID
            state.nextTrack = nil
        }

        switch artworkUpdate {
        case .data(let data):
            state.artworkData = data
            state.artworkTrackID = newTrackID
        case .clear:
            state.artworkData = nil
            state.artworkTrackID = nil
        case .unchanged:
            break
        }

        guard
            let bundleIdentifier = newBundleIdentifier,
            allowedBundleIdentifiers.contains(bundleIdentifier),
            let title = state.values["title"] as? String,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return previousBundleIdentifier != nil || previousTrackID != nil
        }

        return true
    }

    private func preparedArtworkUpdate(from value: Any?) -> ArtworkUpdate {
        if value is NSNull {
            return .clear
        }
        guard
            let encodedArtwork = value as? String,
            let decoded = Data(base64Encoded: encodedArtwork, options: .ignoreUnknownCharacters),
            !decoded.isEmpty
        else {
            return .unchanged
        }
        return .data(Self.downsampledArtworkData(decoded))
    }

    private func publishEmptyStateIfNeeded() {
        let didChange = lock.withLock { () -> Bool in
            guard !state.values.isEmpty || state.artworkData != nil else { return false }
            state = StreamState()
            return true
        }
        if didChange {
            notifyUpdate()
        }
    }

    private func cacheCurrentArtwork() {
        guard let trackID = state.artworkTrackID, let data = state.artworkData else { return }
        artworkCache.removeAll { $0.trackID == trackID }
        artworkCache.insert((trackID, data), at: 0)
        if artworkCache.count > 2 {
            artworkCache.removeLast(artworkCache.count - 2)
        }
    }

    private func cachedArtwork(for trackID: String?) -> Data? {
        guard let trackID else { return nil }
        return artworkCache.first { $0.trackID == trackID }?.data
    }

    private func trackID(from values: [String: Any]) -> String? {
        let preferredKeys = ["uniqueIdentifier", "contentItemIdentifier"]
        for key in preferredKeys {
            if let value = values[key] as? String, !value.isEmpty {
                return value
            }
        }

        let parts = ["bundleIdentifier", "title", "artist", "album"]
            .compactMap { values[$0] as? String }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "|")
    }

    private func notifyUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mediaRemoteStreamDidUpdate, object: nil)
        }
    }

    private func notifyQueueUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mediaRemoteQueueDidUpdate, object: nil)
        }
    }

    private func runOneShot(arguments: [String]) -> Bool {
        guard let resources = Self.resources() else { return false }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [resources.script.path, resources.framework.path] + arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func resources() -> (script: URL, framework: URL)? {
        guard
            let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworksURL = Bundle.main.privateFrameworksURL
        else {
            return nil
        }

        let framework = frameworksURL.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        guard FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return (script, framework)
    }

    private static func downsampledArtworkData(_ data: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512
        ]
        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return data
        }
        let bitmap = NSBitmapImageRep(cgImage: thumbnail)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.84]) ?? data
    }
}
