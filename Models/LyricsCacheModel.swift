import Foundation
#if !SWIFT_PACKAGE
import SwiftData
#endif

protocol LyricsCaching {
    nonisolated func cacheKey(
        for trackID: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String
    func get(key: String, maxAge: TimeInterval) async -> [LyricLine]?
    func set(key: String, title: String, artist: String, lyrics: [LyricLine]) async
}

extension LyricsCaching {
    func cacheKey(for trackID: String?, title: String, artist: String) -> String {
        cacheKey(for: trackID, title: title, artist: artist, album: "", duration: 0)
    }

    func get(key: String) async -> [LyricLine]? {
        await get(key: key, maxAge: 30 * 24 * 3600)
    }
}

// LyricLine Codable conformance
extension LyricLine: Codable {
    enum CodingKeys: String, CodingKey {
        case startTimeMS, words, translation, source, timedUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startTimeMS = try container.decode(TimeInterval.self, forKey: .startTimeMS)
        self.words = try container.decode(String.self, forKey: .words)
        self.translation = try container.decodeIfPresent(String.self, forKey: .translation)
        self.source = try container.decodeIfPresent(LyricsSource.self, forKey: .source)
        self.timedUnits = try container.decodeIfPresent([LyricTimedUnit].self, forKey: .timedUnits)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startTimeMS, forKey: .startTimeMS)
        try container.encode(words, forKey: .words)
        try container.encodeIfPresent(translation, forKey: .translation)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(timedUnits, forKey: .timedUnits)
    }
}

#if !SWIFT_PACKAGE
@Model
final class CachedLyrics {
    @Attribute(.unique) var cacheKey: String
    var title: String
    var artist: String
    var lyricsData: Data
    var fetchedAt: Date

    init(cacheKey: String, title: String, artist: String, lyrics: [LyricLine]) {
        self.cacheKey = cacheKey
        self.title = title
        self.artist = artist
        self.lyricsData = (try? JSONEncoder().encode(lyrics)) ?? Data()
        self.fetchedAt = Date()
    }

    var lyrics: [LyricLine] {
        (try? JSONDecoder().decode([LyricLine].self, from: lyricsData)) ?? []
    }
}

actor LyricsCacheService: LyricsCaching {
    private let container: ModelContainer?
    private let context: ModelContext?
    private var memoryEntries: [String: (lyrics: [LyricLine], fetchedAt: Date, lastAccess: Date)] = [:]
    private let maxMemoryEntries = 24
    private let maxDiskEntries = 256
    private let diskMaxAge: TimeInterval = 30 * 24 * 3600
    private var lastDiskMaintenance = Date.distantPast
    private var maintenanceTask: Task<Void, Never>?

    deinit {
        maintenanceTask?.cancel()
    }

    init(modelContainer: ModelContainer? = nil) {
        do {
            let container = try modelContainer ?? ModelContainer(for: CachedLyrics.self)
            self.container = container
            self.context = ModelContext(container)
        } catch {
            container = nil
            context = nil
        }
    }

    nonisolated func cacheKey(
        for trackID: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String {
        if let trackID, !trackID.isEmpty {
            return "lyrics_v2_itunes_\(trackID)"
        }

        let albumPart = album.normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationPart = duration > 0 ? String(Int(duration.rounded())) : ""
        return ["lyrics_v2", title.normalized, artist.normalized, albumPart, durationPart]
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    func get(key: String, maxAge: TimeInterval = 30 * 24 * 3600) -> [LyricLine]? {
        let now = Date()
        scheduleDiskMaintenance(now: now)
        if var entry = memoryEntries[key], now.timeIntervalSince(entry.fetchedAt) < maxAge {
            entry.lastAccess = now
            memoryEntries[key] = entry
            return entry.lyrics
        }
        memoryEntries.removeValue(forKey: key)

        guard let context else { return nil }

        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )

        guard let cached = try? context.fetch(descriptor).first else {
            return nil
        }

        guard now.timeIntervalSince(cached.fetchedAt) < maxAge else {
            context.delete(cached)
            try? context.save()
            return nil
        }

        let lyrics = cached.lyrics
        guard !lyrics.isEmpty else {
            context.delete(cached)
            try? context.save()
            return nil
        }
        memoryEntries[key] = (lyrics, cached.fetchedAt, now)
        trimMemoryCacheIfNeeded()
        return lyrics
    }

    func set(key: String, title: String, artist: String, lyrics: [LyricLine]) {
        guard !lyrics.isEmpty else {
            memoryEntries.removeValue(forKey: key)
            removePersistedEntry(key: key)
            return
        }

        let now = Date()
        memoryEntries[key] = (lyrics, now, now)
        trimMemoryCacheIfNeeded()

        guard let context else { return }

        // Remove existing entry
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }

        let entry = CachedLyrics(cacheKey: key, title: title, artist: artist, lyrics: lyrics)
        context.insert(entry)
        try? context.save()
        scheduleDiskMaintenance(now: now, force: true)
    }

    func remove(key: String) {
        memoryEntries.removeValue(forKey: key)
        removePersistedEntry(key: key)
    }

    private func removePersistedEntry(key: String) {
        guard let context else { return }

        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }

    private func scheduleDiskMaintenance(now: Date, force: Bool = false) {
        guard context != nil, maintenanceTask == nil,
              force || now.timeIntervalSince(lastDiskMaintenance) >= 3600 else { return }
        maintenanceTask = Task { [weak self] in
            await self?.performDiskMaintenance(now: now)
        }
    }

    private func performDiskMaintenance(now: Date) async {
        defer { maintenanceTask = nil }
        do {
            while !Task.isCancelled {
                if try !removeDiskBatch(now: now) { break }
                await Task.yield()
            }
            lastDiskMaintenance = now
        } catch {
            NSLog("Lyrics cache cleanup failed: %@", error.localizedDescription)
        }
    }

    // Fetch only a small batch of oldest records so old databases do not load all lyric blobs.
    private func removeDiskBatch(now: Date) throws -> Bool {
        guard let context else { return false }
        let cutoff = now.addingTimeInterval(-diskMaxAge)
        var expired = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.fetchedAt < cutoff },
            sortBy: [SortDescriptor(\.fetchedAt)]
        )
        expired.fetchLimit = 64
        var entries = try context.fetch(expired)
        if entries.isEmpty {
            let overflow = try context.fetchCount(FetchDescriptor<CachedLyrics>()) - maxDiskEntries
            guard overflow > 0 else { return false }
            var oldest = FetchDescriptor<CachedLyrics>(sortBy: [SortDescriptor(\.fetchedAt)])
            oldest.fetchLimit = min(overflow, 64)
            entries = try context.fetch(oldest)
        }
        guard !entries.isEmpty else { return false }
        entries.forEach { context.delete($0) }
        try context.save()
        return true
    }

    private func trimMemoryCacheIfNeeded() {
        guard memoryEntries.count > maxMemoryEntries else { return }
        let overflow = memoryEntries.count - maxMemoryEntries
        let keysToRemove = memoryEntries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(overflow)
            .map(\.key)
        keysToRemove.forEach { memoryEntries.removeValue(forKey: $0) }
    }
}
#else
actor LyricsCacheService: LyricsCaching {
    private var entries: [String: (title: String, artist: String, lyrics: [LyricLine], fetchedAt: Date)] = [:]
    private let maxEntries = 128

    nonisolated func cacheKey(
        for trackID: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String {
        if let trackID, !trackID.isEmpty {
            return "lyrics_v2_itunes_\(trackID)"
        }

        let albumPart = album.normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationPart = duration > 0 ? String(Int(duration.rounded())) : ""
        return ["lyrics_v2", title.normalized, artist.normalized, albumPart, durationPart]
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    func get(key: String, maxAge: TimeInterval = 30 * 24 * 3600) -> [LyricLine]? {
        guard let entry = entries[key],
              Date().timeIntervalSince(entry.fetchedAt) < maxAge else {
            return nil
        }

        return entry.lyrics
    }

    func set(key: String, title: String, artist: String, lyrics: [LyricLine]) {
        guard !lyrics.isEmpty else {
            entries.removeValue(forKey: key)
            return
        }

        entries[key] = (title, artist, lyrics, Date())
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }

        let keysToRemove = entries
            .sorted { $0.value.fetchedAt < $1.value.fetchedAt }
            .prefix(entries.count - maxEntries)
            .map(\.key)
        keysToRemove.forEach { entries.removeValue(forKey: $0) }
    }
}
#endif
