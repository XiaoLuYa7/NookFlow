import Foundation
import SwiftData

@MainActor
protocol LyricsCaching {
    func cacheKey(
        for trackID: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String
    func get(key: String, maxAge: TimeInterval) -> [LyricLine]?
    func set(key: String, title: String, artist: String, lyrics: [LyricLine])
}

extension LyricsCaching {
    func cacheKey(for trackID: String?, title: String, artist: String) -> String {
        cacheKey(for: trackID, title: title, artist: artist, album: "", duration: 0)
    }

    func get(key: String) -> [LyricLine]? {
        get(key: key, maxAge: 30 * 24 * 3600)
    }
}

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

// LyricLine Codable conformance
extension LyricLine: Codable {
    enum CodingKeys: String, CodingKey {
        case startTimeMS, words, translation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.startTimeMS = try container.decode(TimeInterval.self, forKey: .startTimeMS)
        self.words = try container.decode(String.self, forKey: .words)
        self.translation = try container.decodeIfPresent(String.self, forKey: .translation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startTimeMS, forKey: .startTimeMS)
        try container.encode(words, forKey: .words)
        try container.encodeIfPresent(translation, forKey: .translation)
    }
}

@MainActor
final class LyricsCacheService: LyricsCaching {
    private let container: ModelContainer?

    init() {
        do {
            container = try ModelContainer(for: CachedLyrics.self)
        } catch {
            container = nil
        }
    }

    func cacheKey(
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
        guard let container else { return nil }

        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )

        guard let cached = try? container.mainContext.fetch(descriptor).first,
              Date().timeIntervalSince(cached.fetchedAt) < maxAge else {
            return nil
        }

        return cached.lyrics
    }

    func set(key: String, title: String, artist: String, lyrics: [LyricLine]) {
        guard let container else { return }
        let context = container.mainContext

        // Remove existing entry
        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }

        // Don't cache empty results — allow re-fetching next time
        guard !lyrics.isEmpty else {
            try? context.save()
            return
        }

        let entry = CachedLyrics(cacheKey: key, title: title, artist: artist, lyrics: lyrics)
        context.insert(entry)
        try? context.save()
    }

    func remove(key: String) {
        guard let container else { return }
        let context = container.mainContext

        let descriptor = FetchDescriptor<CachedLyrics>(
            predicate: #Predicate { $0.cacheKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
    }
}
