import Foundation

// MARK: - Lyric Line

struct LyricLine: Identifiable, Hashable, Equatable {
    let id = UUID()
    var startTimeMS: TimeInterval
    let words: String
    var translation: String?

    init(startTimeMS: TimeInterval, words: String, translation: String? = nil) {
        self.startTimeMS = startTimeMS
        self.words = words
        self.translation = translation
    }
}

// MARK: - Candidate Song (for manual selection)

struct CandidateSong: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let source: LyricsSource
}

enum LyricsSource: String, Hashable {
    case qq
    case netEase
    case kugou
    case lrclib
}

// MARK: - QQ Music API Response

struct QQSearchResponse: Decodable {
    let data: QQSearchData

    struct QQSearchData: Decodable {
        let song: QQSearchSong

        struct QQSearchSong: Decodable {
            let list: [QQSongItem]
        }
    }
}

struct QQSongItem: Decodable {
    let songmid: String
    let songname: String
    let albumname: String
    let albummid: String
    let singer: [QQSinger]
    let interval: Int?

    struct QQSinger: Decodable {
        let name: String
    }
}

struct QQLyricsResponse: Decodable {
    let lyric: Data
    let trans: Data?

    var lyricString: String? {
        String(data: lyric, encoding: .utf8)?.decodingXMLEntities()
    }

    var transString: String? {
        guard let data = trans else { return nil }
        return String(data: data, encoding: .utf8)?.decodingXMLEntities()
    }
}

// MARK: - NetEase API Response

struct NetEaseSearchResponse: Decodable {
    let result: NetEaseSearchResult

    struct NetEaseSearchResult: Decodable {
        let songs: [NetEaseSong]

        struct NetEaseSong: Decodable {
            let name: String
            let id: Int
            let al: NetEaseAlbum
            let ar: [NetEaseArtist]
            let dt: Int?

            struct NetEaseAlbum: Decodable {
                let id: Int
                let name: String
                let picUrl: String?
            }

            struct NetEaseArtist: Decodable {
                let name: String
            }
        }
    }
}

struct NetEaseLyricsResponse: Decodable {
    let lrc: NetEaseLyric?
    let tlyric: NetEaseLyric?

    struct NetEaseLyric: Decodable {
        let lyric: String?
    }
}

// MARK: - String Extensions

extension String {
    var normalized: String {
        self
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(", with: "-")
            .replacingOccurrences(of: ")", with: "-")
            .replacingOccurrences(of: "：", with: "-")
            .replacingOccurrences(of: "（", with: "-")
            .replacingOccurrences(of: "）", with: "-")
            .lowercased()
    }

    func decodingXMLEntities() -> String {
        var result = ""
        var position = startIndex

        while let ampRange = self[position...].range(of: "&") {
            result.append(contentsOf: self[position..<ampRange.lowerBound])
            position = ampRange.lowerBound

            guard let semiRange = self[position...].range(of: ";") else { break }
            let entity = self[position..<semiRange.upperBound]
            position = semiRange.upperBound

            if let decoded = Self.decodeXMLEntity(entity) {
                result.append(decoded)
            } else {
                result.append(contentsOf: entity)
            }
        }

        result.append(contentsOf: self[position...])
        return result
    }

    private static let xmlEntities: [Substring: Character] = [
        "&quot;": "\"",
        "&amp;": "&",
        "&apos;": "'",
        "&lt;": "<",
        "&gt;": ">",
    ]

    private static func decodeXMLEntity(_ entity: Substring) -> Character? {
        if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
            let hex = entity.dropFirst(3).dropLast()
            return UInt32(hex, radix: 16).flatMap(UnicodeScalar.init).map(Character.init)
        } else if entity.hasPrefix("&#") {
            let dec = entity.dropFirst(2).dropLast()
            return UInt32(dec, radix: 10).flatMap(UnicodeScalar.init).map(Character.init)
        }
        return xmlEntities[entity]
    }
}

// MARK: - Kugou Music API Response

struct KugouSearchResponse: Decodable {
    let data: KugouSearchData

    struct KugouSearchData: Decodable {
        let info: [KugouSongInfo]
    }

    struct KugouSongInfo: Decodable {
        let hash: String
        let songname: String
        let singername: String
        let album_name: String?
        let duration: Int?
    }
}

struct KugouLyricsSearchResponse: Decodable {
    let candidates: [KugouCandidate]

    struct KugouCandidate: Decodable {
        let id: String
        let accesskey: String
        let duration: Int?
    }
}

struct KugouLyricsDownloadResponse: Decodable {
    let content: String
}

// MARK: - lrclib API Response

struct LrclibResponse: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Int?
    let plainLyrics: String?
    let syncedLyrics: String?
}
