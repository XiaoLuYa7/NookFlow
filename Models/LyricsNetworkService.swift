import Foundation

protocol LyricsNetworking {
    func searchAndFetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> LyricsFetchResult
    func fetchITunesTrackID(title: String, artist: String) async -> String?
}

extension LyricsNetworking {
    func searchAndFetchLyrics(title: String, artist: String, album: String) async -> LyricsFetchResult {
        await searchAndFetchLyrics(title: title, artist: artist, album: album, duration: 0)
    }
}

final class LyricsNetworkService: LyricsNetworking {

    private let session: URLSession
    private let minimumAcceptedScore = 60

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public

    func searchAndFetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> LyricsFetchResult {
        let request = LyricsSearchRequest(
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )

        let candidates = await withTaskGroup(of: LyricsCandidate?.self, returning: [LyricsCandidate].self) { group in
            group.addTask { await self.fetchQQLyrics(request: request) }
            group.addTask { await self.fetchNetEaseLyrics(request: request) }
            group.addTask { await self.fetchKugouLyrics(request: request) }
            group.addTask { await self.fetchLrclibLyrics(request: request) }

            var candidates: [LyricsCandidate] = []
            for await candidate in group {
                if let candidate, !candidate.lyrics.isEmpty, candidate.score >= self.minimumAcceptedScore {
                    candidates.append(candidate)
                }
            }
            return candidates
        }

        guard let best = candidates.max(by: { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return sourcePriority(lhs.source) < sourcePriority(rhs.source)
        }) else {
            return .notFound
        }

        return .success(best.lyrics)
    }

    // MARK: - QQ Music

    private func fetchQQLyrics(request: LyricsSearchRequest) async -> LyricsCandidate? {
        let query = "\(request.title) \(request.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchURL = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=8&w=\(query)") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: searchURL)
            guard let rawText = String(data: data, encoding: .utf8),
                  let rangeStart = rawText.range(of: "("),
                  let rangeEnd = rawText.range(of: ")", options: .backwards) else {
                return nil
            }

            let jsonString = String(rawText[rangeStart.upperBound..<rangeEnd.lowerBound])
            guard let jsonData = jsonString.data(using: .utf8) else { return nil }

            let searchResult = try JSONDecoder().decode(QQSearchResponse.self, from: jsonData)
            let matches = searchResult.data.song.list.compactMap { song -> (QQSongItem, Int)? in
                let score = scoreCandidate(
                    title: song.songname,
                    artists: song.singer.map(\.name),
                    album: song.albumname,
                    duration: song.interval.map(TimeInterval.init),
                    request: request
                )
                return score.map { (song, $0 + 1) }
            }
            .sorted { $0.1 > $1.1 }

            for (song, score) in matches.prefix(3) {
                if let lyrics = await fetchQQLyricsBySongmid(song.songmid), !lyrics.isEmpty {
                    return LyricsCandidate(source: .qq, score: score, lyrics: lyrics)
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private func fetchQQLyricsBySongmid(_ songmid: String) async -> [LyricLine]? {
        guard let url = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songmid)&g_tk=5381") else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("y.qq.com/portal/player.html", forHTTPHeaderField: "Referer")

            let (data, _) = try await session.data(for: request)
            guard let rawText = String(data: data, encoding: .utf8),
                  let rangeStart = rawText.range(of: "("),
                  let rangeEnd = rawText.range(of: ")", options: .backwards) else {
                return nil
            }

            let jsonString = String(rawText[rangeStart.upperBound..<rangeEnd.lowerBound])
            guard let jsonData = jsonString.data(using: .utf8) else { return nil }

            let lyricsResponse = try JSONDecoder().decode(QQLyricsResponse.self, from: jsonData)
            guard let lyricString = lyricsResponse.lyricString, !lyricString.isEmpty else { return nil }

            let original = LyricsParser.parse(lyricString, format: .qq)

            if let transString = lyricsResponse.transString, !transString.isEmpty {
                let translation = LyricsParser.parse(transString, format: .qq)
                return LyricsParser.merge(original: original, translation: translation)
            }

            return original
        } catch {
            return nil
        }
    }

    // MARK: - NetEase

    private func fetchNetEaseLyrics(request: LyricsSearchRequest) async -> LyricsCandidate? {
        let query = "\(request.title) \(request.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchURL = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/cloudsearch?keywords=\(query)&limit=8") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: searchURL)
            let searchResult = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)
            let matches = searchResult.result.songs.compactMap { song -> (NetEaseSearchResponse.NetEaseSearchResult.NetEaseSong, Int)? in
                let duration = song.dt.map { TimeInterval($0) / 1000 }
                let score = scoreCandidate(
                    title: song.name,
                    artists: song.ar.map(\.name),
                    album: song.al.name,
                    duration: duration,
                    request: request
                )
                return score.map { (song, $0 + 1) }
            }
            .sorted { $0.1 > $1.1 }

            for (song, score) in matches.prefix(3) {
                if let lyrics = await fetchNetEaseLyricsByID(song.id), !lyrics.isEmpty {
                    return LyricsCandidate(source: .netEase, score: score, lyrics: lyrics)
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private func fetchNetEaseLyricsByID(_ songID: Int) async -> [LyricLine]? {
        guard let url = URL(string: "https://neteasecloudmusicapi-ten-wine.vercel.app/lyric?id=\(songID)") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: url)
            let lyricsResponse = try JSONDecoder().decode(NetEaseLyricsResponse.self, from: data)

            guard let lrcString = lyricsResponse.lrc?.lyric, !lrcString.isEmpty else { return nil }

            let original = LyricsParser.parse(lrcString, format: .netEase)

            if let tlyricString = lyricsResponse.tlyric?.lyric, !tlyricString.isEmpty {
                let translation = LyricsParser.parse(tlyricString, format: .netEase)
                return LyricsParser.merge(original: original, translation: translation)
            }

            return original
        } catch {
            return nil
        }
    }

    // MARK: - Kugou Music

    private func fetchKugouLyrics(request: LyricsSearchRequest) async -> LyricsCandidate? {
        let query = "\(request.title) \(request.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let searchURL = URL(string: "https://mobileservice.kugou.com/api/v3/search/song?keyword=\(query)&page=1&pagesize=8") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: searchURL)
            let searchResult = try JSONDecoder().decode(KugouSearchResponse.self, from: data)
            let matches = searchResult.data.info.compactMap { song -> (KugouSearchResponse.KugouSongInfo, Int)? in
                let score = scoreCandidate(
                    title: song.songname,
                    artists: [song.singername],
                    album: song.album_name,
                    duration: song.duration.map(TimeInterval.init),
                    request: request
                )
                return score.map { (song, $0) }
            }
            .sorted { $0.1 > $1.1 }

            for (song, score) in matches.prefix(3) {
                if let lyrics = await fetchKugouLyricsByHash(song.hash), !lyrics.isEmpty {
                    return LyricsCandidate(source: .kugou, score: score, lyrics: lyrics)
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private func fetchKugouLyricsByHash(_ hash: String) async -> [LyricLine]? {
        guard let searchURL = URL(string: "https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=&hash=\(hash)&album_audio_id=") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: searchURL)
            let searchResult = try JSONDecoder().decode(KugouLyricsSearchResponse.self, from: data)

            guard let candidate = searchResult.candidates.first else { return nil }

            guard let downloadURL = URL(string: "https://lyrics.kugou.com/download?ver=1&client=pc&id=\(candidate.id)&accesskey=\(candidate.accesskey)&fmt=lrc&charset=utf8") else {
                return nil
            }

            let (downloadData, _) = try await session.data(from: downloadURL)
            let downloadResult = try JSONDecoder().decode(KugouLyricsDownloadResponse.self, from: downloadData)

            guard let decodedData = Data(base64Encoded: downloadResult.content),
                  let lrcString = String(data: decodedData, encoding: .utf8),
                  !lrcString.isEmpty else {
                return nil
            }

            return LyricsParser.parse(lrcString, format: .netEase)
        } catch {
            return nil
        }
    }

    // MARK: - lrclib

    private func fetchLrclibLyrics(request: LyricsSearchRequest) async -> LyricsCandidate? {
        let encodedTitle = request.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedArtist = request.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedAlbum = request.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let exactURL = URL(string: "https://lrclib.net/api/get?track_name=\(encodedTitle)&artist_name=\(encodedArtist)&album_name=\(encodedAlbum)"),
           let exact = await fetchLrclibFromURL(exactURL, request: request, exactRequestBonus: 4) {
            return exact
        }

        guard let searchURL = URL(string: "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: searchURL)
            let results = try JSONDecoder().decode([LrclibResponse].self, from: data)
            let matches = results.compactMap { result -> LyricsCandidate? in
                guard let syncedLyrics = result.syncedLyrics, !syncedLyrics.isEmpty,
                      let score = scoreCandidate(
                        title: result.trackName,
                        artists: [result.artistName],
                        album: result.albumName,
                        duration: result.duration.map(TimeInterval.init),
                        request: request
                      ) else {
                    return nil
                }

                let lyrics = LyricsParser.parse(syncedLyrics, format: .netEase)
                guard !lyrics.isEmpty else { return nil }
                return LyricsCandidate(source: .lrclib, score: score + 2, lyrics: lyrics)
            }

            return matches.max(by: { $0.score < $1.score })
        } catch {
            return nil
        }
    }

    private func fetchLrclibFromURL(
        _ url: URL,
        request: LyricsSearchRequest,
        exactRequestBonus: Int
    ) async -> LyricsCandidate? {
        do {
            let (data, _) = try await session.data(from: url)
            let result = try JSONDecoder().decode(LrclibResponse.self, from: data)

            guard let syncedLyrics = result.syncedLyrics, !syncedLyrics.isEmpty,
                  let score = scoreCandidate(
                    title: result.trackName,
                    artists: [result.artistName],
                    album: result.albumName,
                    duration: result.duration.map(TimeInterval.init),
                    request: request
                  ) else {
                return nil
            }

            let lyrics = LyricsParser.parse(syncedLyrics, format: .netEase)
            guard !lyrics.isEmpty else { return nil }
            return LyricsCandidate(source: .lrclib, score: score + exactRequestBonus, lyrics: lyrics)
        } catch {
            return nil
        }
    }

    // MARK: - iTunes Search (for track ID)

    func fetchITunesTrackID(title: String, artist: String) async -> String? {
        let query = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=1") else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: url)
            struct ITunesResponse: Decodable {
                let results: [ITunesTrack]
                struct ITunesTrack: Decodable {
                    let trackId: Int
                }
            }
            let response = try JSONDecoder().decode(ITunesResponse.self, from: data)
            return response.results.first.map { String($0.trackId) }
        } catch {
            return nil
        }
    }
}

private struct LyricsSearchRequest {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

private struct LyricsCandidate {
    let source: LyricsSource
    let score: Int
    let lyrics: [LyricLine]
}

private func sourcePriority(_ source: LyricsSource) -> Int {
    switch source {
    case .lrclib:
        return 4
    case .qq:
        return 3
    case .netEase:
        return 2
    case .kugou:
        return 1
    }
}

private func scoreCandidate(
    title candidateTitle: String,
    artists candidateArtists: [String],
    album candidateAlbum: String?,
    duration candidateDuration: TimeInterval?,
    request: LyricsSearchRequest
) -> Int? {
    guard !hasExcludedVersionToken(candidateTitle, comparedWith: request.title),
          let titleScore = scoreTitle(candidateTitle, target: request.title),
          let artistScore = scoreArtist(candidateArtists, target: request.artist),
          let durationScore = scoreDuration(candidate: candidateDuration, target: request.duration) else {
        return nil
    }

    return titleScore
        + artistScore
        + scoreAlbum(candidate: candidateAlbum, target: request.album)
        + durationScore
}

private func scoreTitle(_ candidate: String, target: String) -> Int? {
    let candidate = comparableText(candidate)
    let target = comparableText(target)
    guard !candidate.isEmpty, !target.isEmpty else { return nil }

    if candidate == target { return 44 }

    let strippedCandidate = stripVersionText(candidate)
    let strippedTarget = stripVersionText(target)
    if !strippedCandidate.isEmpty, strippedCandidate == strippedTarget { return 40 }

    if target.hasPrefix(candidate + " ") || target.hasSuffix(" " + candidate) || target.contains(" " + candidate + " ") {
        return candidate.count >= 2 ? 30 : nil
    }

    if candidate.hasPrefix(target + " ") || candidate.hasSuffix(" " + target) || candidate.contains(" " + target + " ") {
        return target.count >= 2 ? 28 : nil
    }

    return nil
}

private func scoreArtist(_ candidates: [String], target: String) -> Int? {
    let targetNames = splitArtistNames(target)
    guard !targetNames.isEmpty else { return 8 }

    let candidateNames = candidates.flatMap(splitArtistNames)
    guard !candidateNames.isEmpty else { return nil }

    if candidateNames.contains(where: { candidate in targetNames.contains(candidate) }) {
        return 36
    }

    if candidateNames.contains(where: { candidate in
        targetNames.contains(where: { target in
            candidate.contains(target) || target.contains(candidate)
        })
    }) {
        return 26
    }

    return nil
}

private func scoreAlbum(candidate: String?, target: String) -> Int {
    let target = comparableText(target)
    guard !target.isEmpty else { return 0 }

    let candidate = comparableText(candidate ?? "")
    guard !candidate.isEmpty else { return 0 }

    if candidate == target { return 16 }
    if candidate.contains(target) || target.contains(candidate) { return 10 }
    return -8
}

private func scoreDuration(candidate: TimeInterval?, target: TimeInterval) -> Int? {
    guard target > 0, let candidate, candidate > 0 else { return 0 }
    let diff = abs(candidate - target)

    switch diff {
    case ...2:
        return 18
    case ...6:
        return 14
    case ...12:
        return 8
    case ...25:
        return 0
    case ...45:
        return -14
    default:
        return nil
    }
}

private func hasExcludedVersionToken(_ candidate: String, comparedWith target: String) -> Bool {
    let candidate = comparableText(candidate)
    let target = comparableText(target)
    let excludedTokens = [
        "instrumental", "karaoke", "remix", "cover", "demo", "live",
        "伴奏", "纯音乐", "翻唱", "现场", "剪辑", "片段"
    ]

    return excludedTokens.contains { token in
        candidate.contains(token) && !target.contains(token)
    }
}

private func splitArtistNames(_ value: String) -> [String] {
    comparableText(value)
        .replacingOccurrences(of: " featuring ", with: " ")
        .replacingOccurrences(of: " feat ", with: " ")
        .replacingOccurrences(of: " ft ", with: " ")
        .components(separatedBy: CharacterSet(charactersIn: "/&、,，;；|+"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func stripVersionText(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"\bversion\b"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\bver\b"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\bexplicit\b"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func comparableText(_ value: String) -> String {
    value.normalized
        .replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\{[^\}]*\}"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"['’]"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

enum LyricsFetchResult {
    case success([LyricLine])
    case notFound
}
