import Foundation

struct CompactMusicTrackSnapshot: Equatable {
    var isLive: Bool
    var title: String
    var artist: String
}

struct CompactMusicPresentation: Equatable {
    enum WidthBasis: Equatable {
        case fixedLyrics
        case trackOrArtist
    }

    var leftText: String
    var rightText: String
    var widthBasis: WidthBasis
    var leftFallbackText: String = ""

    static func resolve(
        showsTrackName: Bool,
        showsLyrics: Bool,
        track: CompactMusicTrackSnapshot,
        currentLyric: String?,
        nextLyric: String?
    ) -> CompactMusicPresentation? {
        guard track.isLive else { return nil }

        let title = sanitized(track.title)
        let artist = sanitized(track.artist)
        let currentLyric = sanitized(currentLyric ?? "")
        let nextLyric = sanitized(nextLyric ?? "")
        let trackLabel = trackText(title: title, artist: artist)
        let titleFallback = trackTitleFallback(title: title, trackLabel: trackLabel)
        let displayCurrentLyric = sanitizedLyricText(
            currentLyric,
            title: title,
            artist: artist,
            trackLabel: trackLabel
        )
        let displayNextLyric = sanitizedLyricText(
            nextLyric,
            title: title,
            artist: artist,
            trackLabel: trackLabel
        )

        switch (showsTrackName, showsLyrics) {
        case (true, true):
            guard !trackLabel.isEmpty else {
                return displayCurrentLyric.isEmpty ? nil : CompactMusicPresentation(
                    leftText: "",
                    rightText: displayCurrentLyric,
                    widthBasis: .fixedLyrics
                )
            }

            if !displayCurrentLyric.isEmpty {
                return CompactMusicPresentation(
                    leftText: trackLabel,
                    rightText: displayCurrentLyric,
                    widthBasis: .fixedLyrics,
                    leftFallbackText: titleFallback
                )
            }

            return CompactMusicPresentation(
                leftText: trackLabel,
                rightText: "",
                widthBasis: .trackOrArtist,
                leftFallbackText: titleFallback
            )

        case (false, true):
            guard !displayCurrentLyric.isEmpty || !displayNextLyric.isEmpty else { return nil }
            return CompactMusicPresentation(
                leftText: displayCurrentLyric,
                rightText: displayNextLyric,
                widthBasis: .fixedLyrics
            )

        case (true, false):
            guard !title.isEmpty || !artist.isEmpty else { return nil }
            return CompactMusicPresentation(
                leftText: title,
                rightText: artist,
                widthBasis: .trackOrArtist
            )

        case (false, false):
            return nil
        }
    }

    private static func sanitized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trackText(title: String, artist: String) -> String {
        if title.isEmpty { return artist }
        if artist.isEmpty { return title }
        return "\(title) - \(artist)"
    }

    private static func trackTitleFallback(title: String, trackLabel: String) -> String {
        guard !title.isEmpty, title != trackLabel else { return "" }
        return title
    }

    private static func sanitizedLyricText(
        _ text: String,
        title: String,
        artist: String,
        trackLabel: String
    ) -> String {
        let text = sanitized(text)
        let normalizedText = text.normalized
        guard !text.isEmpty,
              normalizedText != title.normalized,
              normalizedText != artist.normalized,
              normalizedText != trackLabel.normalized else {
            return ""
        }
        return text
    }
}
