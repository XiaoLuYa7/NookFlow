import XCTest
@testable import NookFlowCore

final class CompactMusicPresentationTests: XCTestCase {
    private let track = CompactMusicTrackSnapshot(
        isLive: true,
        title: "Song",
        artist: "Artist"
    )

    func testTrackAndLyrics() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: track,
            currentLyric: "Current",
            nextLyric: "Next"
        )

        XCTAssertEqual(value?.leftText, "Song - Artist")
        XCTAssertEqual(value?.rightText, "Current")
    }

    func testTrackAndLyricsProvidesTitleFallback() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: CompactMusicTrackSnapshot(
                isLive: true,
                title: "A Very Long Song Title",
                artist: "A Very Long Artist Name"
            ),
            currentLyric: "Current",
            nextLyric: nil
        )

        XCTAssertEqual(value?.leftText, "A Very Long Song Title - A Very Long Artist Name")
        XCTAssertEqual(value?.leftFallbackText, "A Very Long Song Title")
    }

    func testTrackAndLyricsDoesNotDuplicateTrackWhenLyricMissing() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: track,
            currentLyric: nil,
            nextLyric: nil
        )

        XCTAssertEqual(value?.leftText, "Song - Artist")
        XCTAssertEqual(value?.rightText, "")
        XCTAssertEqual(value?.widthBasis, .trackOrArtist)
    }

    func testTrackAndLyricsShowsNotFoundStatus() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: track,
            currentLyric: "未找到歌词",
            nextLyric: nil
        )

        XCTAssertEqual(value?.leftText, "Song - Artist")
        XCTAssertEqual(value?.rightText, "未找到歌词")
        XCTAssertEqual(value?.widthBasis, .fixedLyrics)
    }

    func testTrackAndLyricsShowsLoadingStatus() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: track,
            currentLyric: "正在加载歌词··",
            nextLyric: nil
        )

        XCTAssertEqual(value?.leftText, "Song - Artist")
        XCTAssertEqual(value?.rightText, "正在加载歌词··")
        XCTAssertEqual(value?.widthBasis, .fixedLyrics)
    }

    func testTrackAndLyricsIgnoresTrackLabelAsLyric() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: true,
            track: track,
            currentLyric: "Song - Artist",
            nextLyric: nil
        )

        XCTAssertEqual(value?.leftText, "Song - Artist")
        XCTAssertEqual(value?.rightText, "")
        XCTAssertEqual(value?.widthBasis, .trackOrArtist)
    }

    func testTrackOnly() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: true,
            showsLyrics: false,
            track: track,
            currentLyric: "Current",
            nextLyric: "Next"
        )

        XCTAssertEqual(value?.leftText, "Song")
        XCTAssertEqual(value?.rightText, "Artist")
        XCTAssertEqual(value?.widthBasis, .trackOrArtist)
    }

    func testLyricsOnly() {
        let value = CompactMusicPresentation.resolve(
            showsTrackName: false,
            showsLyrics: true,
            track: track,
            currentLyric: "Current",
            nextLyric: "Next"
        )

        XCTAssertEqual(value?.leftText, "Current")
        XCTAssertEqual(value?.rightText, "Next")
        XCTAssertEqual(value?.widthBasis, .fixedLyrics)
    }

    func testNoMusicText() {
        XCTAssertNil(CompactMusicPresentation.resolve(
            showsTrackName: false,
            showsLyrics: false,
            track: track,
            currentLyric: "Current",
            nextLyric: "Next"
        ))
    }
}

final class PlaybackAccessConfigurationTests: XCTestCase {
    func testPersistedMusicAccessOverridesCachedFallback() {
        let suiteName = "PlaybackAccessConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "settings.allowSpotifyAccess")
        defaults.set(false, forKey: "settings.allowAppleMusicAccess")

        let cached = PlaybackAccessConfiguration.defaults
        let resolved = PlaybackAccessConfiguration.persisted(defaults: defaults, fallback: cached)

        XCTAssertFalse(resolved.appleMusic)
        XCTAssertTrue(resolved.spotify)
    }
}

@MainActor
final class TodoViewModelTests: XCTestCase {
    func testDefaultTasksAreEmpty() {
        XCTAssertTrue(TodoViewModel().tasks.isEmpty)
    }

    func testReminderFailureDoesNotCompleteTask() async {
        let task = TodoTask(
            reminderIdentifier: "eventkit-id",
            title: "System reminder",
            date: Date()
        )
        let model = TodoViewModel(tasks: [task])

        let succeeded = await model.completeTask(id: task.id) { _ in false }

        XCTAssertFalse(succeeded)
        XCTAssertFalse(model.tasks[0].isCompleted)
    }

    func testReminderSuccessCompletesTask() async {
        let task = TodoTask(
            reminderIdentifier: "eventkit-id",
            title: "System reminder",
            date: Date()
        )
        let model = TodoViewModel(tasks: [task])

        let succeeded = await model.completeTask(id: task.id) { _ in true }

        XCTAssertTrue(succeeded)
        XCTAssertTrue(model.tasks[0].isCompleted)
    }

    func testDateStripProvidesScrollableWindowAndSelectsToday() {
        let calendar = testCalendar
        let seedDate = date(2026, 6, 23, calendar: calendar)
        let model = TodoViewModel(seedDate: seedDate, calendar: calendar)

        XCTAssertEqual(model.dayItems.count, 731)
        XCTAssertEqual(model.dayItems.firstIndex(where: \.isSelected), 367)
        XCTAssertTrue(calendar.isDate(model.dayItems[367].date, inSameDayAs: seedDate))
    }

    func testDateStripItemWidthShowsThreeAndHalfDates() {
        let metrics = HorizontalDateStripMetrics(visibleItemCount: 3.5, spacing: 7)

        XCTAssertEqual(metrics.itemWidth(for: 320), 85.428, accuracy: 0.001)
    }

    func testTodoSchedulePreviewItemsMatchSelectedTodoTasks() {
        let calendar = testCalendar
        let selectedDate = date(2026, 7, 3, calendar: calendar)
        let otherDate = date(2026, 7, 4, calendar: calendar)
        let createdFirst = date(2026, 7, 1, calendar: calendar)
        let createdSecond = date(2026, 7, 2, calendar: calendar)
        let morning = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: selectedDate)!
        let afternoon = calendar.date(bySettingHour: 14, minute: 15, second: 0, of: selectedDate)!
        let tasks = [
            TodoTask(title: "Other day", date: otherDate, dueTime: nil, createdAt: createdFirst),
            TodoTask(title: "Second", date: selectedDate, dueTime: afternoon, createdAt: createdSecond),
            TodoTask(title: "First", date: selectedDate, dueTime: morning, createdAt: createdFirst),
            TodoTask(title: "Done", date: selectedDate, isCompleted: true, createdAt: createdFirst)
        ]

        let items = TodoSchedulePreviewItem.items(
            from: tasks,
            selectedDate: selectedDate,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.title), ["First", "Second", "Done"])
        XCTAssertEqual(items.map(\.time), ["09:30", "14:15", ""])
        XCTAssertTrue(items[2].isCompleted)
    }

    func testTodoSchedulePreviewHonorsTodayOnlyFilter() {
        let calendar = testCalendar
        let today = date(2026, 7, 3, calendar: calendar)
        let selectedDate = date(2026, 7, 4, calendar: calendar)
        let tasks = [
            TodoTask(title: "Today", date: today),
            TodoTask(title: "Selected", date: selectedDate)
        ]

        let items = TodoSchedulePreviewItem.items(
            from: tasks,
            selectedDate: selectedDate,
            today: today,
            showTodayOnly: true,
            showCompleted: false,
            sortMode: .timeAsc,
            calendar: calendar
        )

        XCTAssertEqual(items.map(\.title), ["Today"])
    }

    func testTodoSchedulePreviewSortsByPriorityAndTimeDescending() {
        let calendar = testCalendar
        let selectedDate = date(2026, 7, 3, calendar: calendar)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate)!
        let afternoon = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: selectedDate)!
        let tasks = [
            TodoTask(title: "Normal late", date: selectedDate, dueTime: afternoon, priority: .normal),
            TodoTask(title: "Urgent early", date: selectedDate, dueTime: morning, priority: .urgent),
            TodoTask(title: "Important late", date: selectedDate, dueTime: afternoon, priority: .important)
        ]

        let priorityItems = TodoSchedulePreviewItem.items(
            from: tasks,
            selectedDate: selectedDate,
            today: selectedDate,
            showTodayOnly: false,
            showCompleted: false,
            sortMode: .priority,
            calendar: calendar
        )
        let timeDescItems = TodoSchedulePreviewItem.items(
            from: tasks,
            selectedDate: selectedDate,
            today: selectedDate,
            showTodayOnly: false,
            showCompleted: false,
            sortMode: .timeDesc,
            calendar: calendar
        )

        XCTAssertEqual(priorityItems.map(\.title), ["Urgent early", "Important late", "Normal late"])
        XCTAssertEqual(timeDescItems.map(\.title), ["Normal late", "Important late", "Urgent early"])
    }

    func testRefreshMovesDateStripToNextWeekAndSelectsCurrentDate() {
        let calendar = testCalendar
        let model = TodoViewModel(
            seedDate: date(2026, 6, 27, calendar: calendar),
            calendar: calendar
        )
        let nextSunday = date(2026, 6, 28, calendar: calendar)

        model.refreshForCurrentDate(nextSunday)

        let selectedItem = model.dayItems.first(where: \.isSelected)

        XCTAssertTrue(calendar.isDate(model.selectedDate, inSameDayAs: nextSunday))
        XCTAssertNotNil(selectedItem)
        XCTAssertTrue(selectedItem.map { calendar.isDate($0.date, inSameDayAs: nextSunday) } ?? false)
    }

    func testReminderSyncKeepsCurrentDateSelected() {
        let calendar = testCalendar
        let today = date(2026, 6, 23, calendar: calendar)
        let earlierTask = TodoTask(title: "Earlier", date: date(2026, 6, 21, calendar: calendar))
        let model = TodoViewModel(seedDate: today, calendar: calendar)

        model.replaceTasks([earlierTask])

        XCTAssertTrue(calendar.isDate(model.selectedDate, inSameDayAs: today))
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

final class AsyncResultIdentityTests: XCTestCase {
    func testOldPreviewCannotCommitOverNewFile() {
        XCTAssertFalse(AsyncResultIdentity.matches(
            currentID: "new-file",
            requestedID: "old-file",
            isCancelled: false
        ))
    }

    func testCancelledResultCannotCommit() {
        XCTAssertFalse(AsyncResultIdentity.matches(
            currentID: "same-file",
            requestedID: "same-file",
            isCancelled: true
        ))
    }
}

@MainActor
final class LyricsProviderRequestTests: XCTestCase {
    func testOldTrackCannotOverwriteNewTrack() async throws {
        let network = DelayedLyricsNetwork()
        let provider = LyricsProvider(networkService: network, cache: MemoryLyricsCache())

        provider.update(for: snapshot(title: "Old"), trackID: "old-id")
        try await Task.sleep(for: .milliseconds(10))
        provider.update(for: snapshot(title: "New"), trackID: "new-id")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(provider.lyrics.first?.words, "New lyric")
    }

    func testTraditionalChineseLyricsAreShownAsSimplified() async throws {
        let network = DelayedLyricsNetwork()
        let provider = LyricsProvider(networkService: network, cache: MemoryLyricsCache())

        provider.update(for: snapshot(title: "愛與夢"), trackID: "traditional-id")
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(provider.lyrics.first?.words, "爱与梦 lyric")
    }

    private func snapshot(title: String) -> PlaybackSnapshot {
        PlaybackSnapshot(
            appName: "Music",
            state: .paused,
            title: title,
            artist: "Artist",
            album: "Album",
            detail: "Artist",
            artworkSource: nil,
            duration: 180,
            elapsed: 0,
            isLive: true
        )
    }
}

final class DateFormattingTests: XCTestCase {
    func testCalendarDateFormatIsUnchanged() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 23
        let date = components.date!

        XCTAssertEqual(CalendarSnapshot.formattedDate(date), "6 月 23 日")
    }
}

private final class DelayedLyricsNetwork: LyricsNetworking {
    func fetchITunesTrackID(title: String, artist: String) async -> String? { nil }

    func searchAndFetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> LyricsFetchResult {
        await withCheckedContinuation { continuation in
            let delay = title == "Old" ? 0.20 : 0.02
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                continuation.resume(returning: .success([
                    LyricLine(startTimeMS: 0, words: "\(title) lyric")
                ]))
            }
        }
    }
}

@MainActor
private final class MemoryLyricsCache: LyricsCaching {
    private var values: [String: [LyricLine]] = [:]

    func cacheKey(
        for trackID: String?,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String {
        trackID ?? "\(title)-\(artist)-\(album)-\(Int(duration.rounded()))"
    }

    func get(key: String, maxAge: TimeInterval) -> [LyricLine]? {
        values[key]
    }

    func set(key: String, title: String, artist: String, lyrics: [LyricLine]) {
        values[key] = lyrics
    }
}
