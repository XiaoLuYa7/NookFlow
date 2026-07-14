import AppKit
import XCTest
@testable import NookFlowCore

final class NotificationRuntimePolicyTests: XCTestCase {
    func testAllNotificationsDisabledDoNotNeedRuntimeResources() {
        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: NotificationSettingsSnapshot()),
            .inactive
        )
    }

    func testLocalDailyCareOnlyNeedsPeriodicChecks() {
        let settings = NotificationSettingsSnapshot(
            dailyCare: DailyCareNotificationSnapshot(
                isEnabled: true,
                waterReminderEnabled: true,
                sitReminderEnabled: false,
                sleepReminderEnabled: false
            )
        )

        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: settings),
            NotificationRuntimeRequirements(
                needsPeriodicChecks: true,
                needsNetworkMonitor: false,
                needsWeatherSubscription: false
            )
        )
    }

    func testWeatherNotificationNeedsPeriodicChecksAndWeatherSubscription() {
        let settings = NotificationSettingsSnapshot(
            weather: WeatherNotificationSnapshot(isEnabled: true)
        )

        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: settings),
            NotificationRuntimeRequirements(
                needsPeriodicChecks: true,
                needsNetworkMonitor: false,
                needsWeatherSubscription: true
            )
        )
    }

    func testNetworkStatusOnlyNeedsNetworkMonitor() {
        let settings = NotificationSettingsSnapshot(
            device: DeviceNotificationSnapshot(
                isEnabled: true,
                networkStatusAlertEnabled: true
            )
        )

        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: settings),
            NotificationRuntimeRequirements(
                needsPeriodicChecks: false,
                needsNetworkMonitor: true,
                needsWeatherSubscription: false
            )
        )
    }

    func testDeviceSamplingNotificationNeedsPeriodicChecks() {
        let settings = NotificationSettingsSnapshot(
            device: DeviceNotificationSnapshot(
                isEnabled: true,
                lowBatteryEnabled: true,
                performanceAlertEnabled: true
            )
        )

        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: settings),
            NotificationRuntimeRequirements(
                needsPeriodicChecks: true,
                needsNetworkMonitor: false,
                needsWeatherSubscription: false
            )
        )
    }

    func testMultipleNotificationsCombineRuntimeRequirements() {
        let settings = NotificationSettingsSnapshot(
            weather: WeatherNotificationSnapshot(isEnabled: true),
            device: DeviceNotificationSnapshot(
                isEnabled: true,
                storageAlertEnabled: true,
                networkStatusAlertEnabled: true
            ),
            dailyCare: DailyCareNotificationSnapshot(
                isEnabled: true,
                sleepReminderEnabled: true
            )
        )

        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: settings),
            NotificationRuntimeRequirements(
                needsPeriodicChecks: true,
                needsNetworkMonitor: true,
                needsWeatherSubscription: true
            )
        )
    }

    func testRequirementsCanMoveFromAllOnToAllOff() {
        let active = NotificationSettingsSnapshot(
            weather: WeatherNotificationSnapshot(isEnabled: true),
            device: DeviceNotificationSnapshot(
                isEnabled: true,
                lowBatteryEnabled: true,
                networkStatusAlertEnabled: true
            ),
            dailyCare: DailyCareNotificationSnapshot(
                isEnabled: true,
                waterReminderEnabled: true
            )
        )

        XCTAssertNotEqual(NotificationRuntimePolicy.requirements(for: active), .inactive)
        XCTAssertEqual(
            NotificationRuntimePolicy.requirements(for: NotificationSettingsSnapshot()),
            .inactive
        )
    }

    func testRequirementsCanMoveFromAllOffToPartialOn() {
        let inactive = NotificationRuntimePolicy.requirements(for: NotificationSettingsSnapshot())
        let partial = NotificationRuntimePolicy.requirements(for: NotificationSettingsSnapshot(
            device: DeviceNotificationSnapshot(
                isEnabled: true,
                networkStatusAlertEnabled: true
            )
        ))

        XCTAssertEqual(inactive, .inactive)
        XCTAssertEqual(
            partial,
            NotificationRuntimeRequirements(
                needsPeriodicChecks: false,
                needsNetworkMonitor: true,
                needsWeatherSubscription: false
            )
        )
    }
}

final class TimelineRefreshPolicyTests: XCTestCase {
    func testHiddenLyricDoesNotUseTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: false,
                isPlaying: true,
                hasContent: true,
                needsScrolling: true,
                isTransitioning: false
            )
        ))
    }

    func testPausedLyricDoesNotUseTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: false,
                hasContent: true,
                needsScrolling: true,
                isTransitioning: false
            )
        ))
    }

    func testEmptyLyricDoesNotUseTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: true,
                hasContent: false,
                needsScrolling: true,
                isTransitioning: false
            )
        ))
    }

    func testShortLyricDoesNotUseTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: true,
                hasContent: true,
                needsScrolling: false,
                isTransitioning: false
            )
        ))
    }

    func testShortLyricUsesTimelineWhileProgressScanIsActive() {
        XCTAssertTrue(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: true,
                hasContent: true,
                needsScrolling: false,
                needsProgressAnimation: true,
                isTransitioning: false
            )
        ))
    }

    func testPlayingOverflowingLyricUsesTimeline() {
        XCTAssertTrue(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: true,
                hasContent: true,
                needsScrolling: true,
                isTransitioning: false
            )
        ))
    }

    func testVisibleTransitioningLyricUsesTimeline() {
        XCTAssertTrue(TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: false,
                hasContent: true,
                needsScrolling: false,
                isTransitioning: true
            )
        ))
    }

    func testStaticWeatherDoesNotUseTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousWeatherTimeline(
            kind: .staticIcon,
            reduceMotion: false
        ))
    }

    func testReduceMotionDisablesWeatherTimeline() {
        XCTAssertFalse(TimelineRefreshPolicy.shouldUseContinuousWeatherTimeline(
            kind: .animatedIcon,
            reduceMotion: true
        ))
    }
}

final class TodoCardSettingsTests: XCTestCase {
    func testDefaultsRemainStable() {
        let defaults = TodoCardSettings.defaults

        XCTAssertTrue(defaults.showDateSelector)
        XCTAssertTrue(defaults.showTime)
        XCTAssertTrue(defaults.showCategory)
        XCTAssertFalse(defaults.showCompleted)
        XCTAssertEqual(defaults.maxVisibleItems, 2)
        XCTAssertEqual(defaults.defaultRange, .selectedDate)
        XCTAssertEqual(defaults.sortMode, .timeAsc)
        XCTAssertEqual(defaults.highlightColor, .blue)
        XCTAssertFalse(defaults.useCompactMode)
        XCTAssertTrue(defaults.showEdgeGlow)
        XCTAssertTrue(defaults.showReminderBadge)
        XCTAssertEqual(defaults.dueSoonMinutes, 15)
    }

    func testStorageKeysRemainStableAndUnique() {
        XCTAssertEqual(Set(TodoCardStorageKeys.all).count, TodoCardStorageKeys.all.count)
        XCTAssertEqual(TodoCardStorageKeys.maxVisibleItems, "todo.card.maxVisibleItems")
        XCTAssertEqual(TodoCardStorageKeys.sortMode, "todo.card.sortMode")
        XCTAssertEqual(TodoCardStorageKeys.showCompleted, "todo.card.showCompleted")
        XCTAssertEqual(TodoCardStorageKeys.all.count, 12)
    }
}

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

    func testReminderSyncPreservesStableTaskIdentity() {
        let calendar = testCalendar
        let today = date(2026, 6, 23, calendar: calendar)
        let existingID = UUID()
        let model = TodoViewModel(
            seedDate: today,
            calendar: calendar,
            tasks: [
                TodoTask(
                    id: existingID,
                    reminderIdentifier: "reminder-1",
                    title: "Before sync",
                    date: today
                )
            ]
        )

        model.replaceTasks([
            TodoTask(
                reminderIdentifier: "reminder-1",
                title: "After sync",
                date: today
            )
        ])

        XCTAssertEqual(model.tasks.first?.id, existingID)
        XCTAssertEqual(model.tasks.first?.title, "After sync")
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

    func testPausedPlaybackRestoresLyricAtCurrentElapsedPosition() {
        let cache = MemoryLyricsCache()
        cache.set(
            key: "paused-id",
            title: "Paused Song",
            artist: "Artist",
            lyrics: [
                LyricLine(startTimeMS: 0, words: "Opening"),
                LyricLine(startTimeMS: 60_000, words: "Current line"),
                LyricLine(startTimeMS: 90_000, words: "Later line")
            ]
        )
        let provider = LyricsProvider(networkService: DelayedLyricsNetwork(), cache: cache)
        var paused = snapshot(title: "Paused Song")
        paused.state = .paused
        paused.elapsed = 65

        provider.update(for: paused, trackID: "paused-id")

        XCTAssertEqual(provider.currentLineIndex, 1)

        paused.elapsed = 95
        provider.update(for: paused, trackID: "paused-id")

        XCTAssertEqual(provider.currentLineIndex, 2)
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

final class SettingsLayoutContractTests: XCTestCase {
    func testHomeCustomizationUsesFocusedEditingMode() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("showsHomeCustomization ? \"完成自定义\" : \"自定义首页\""))
        XCTAssertTrue(source.contains("showsHomeCustomization ? \"checkmark\" : \"slider.horizontal.3\""))
        XCTAssertTrue(source.contains("role: showsHomeCustomization ? .primary : .secondary"))
        XCTAssertTrue(source.contains("if showsHomeCustomization {\n                previewArea"))
        XCTAssertTrue(source.contains("} else {\n                homeOverviewSection\n                homeOperationsSection"))
    }

    func testHomeDoesNotShowRecentActivityPlaceholder() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("homeRecentActivitySection"))
        XCTAssertFalse(source.contains("最近活动"))
        XCTAssertFalse(source.contains("暂无可显示的活动记录"))
    }

    func testNewTodoSheetUsesCompactScheduleLayout() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/TodoView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".frame(width: 520, height: 650)"))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 10)"))
        XCTAssertTrue(source.contains("compactSchedulePanel("))
        XCTAssertTrue(source.contains("Text(\"快捷时间\")"))
    }

    func testSidebarLabelsDisappearBeforeWidthCollapses() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsAppShell.swift"),
            encoding: .utf8
        )

        let toggleStart = try XCTUnwrap(source.range(of: "private func toggleSidebar()"))
        let toggleSource = source[toggleStart.lowerBound...]
        let hideLabels = try XCTUnwrap(toggleSource.range(of: "areLabelsVisible = false"))
        let collapseWidth = try XCTUnwrap(toggleSource.range(of: "isCollapsed = true"))

        XCTAssertLessThan(hideLabels.lowerBound, collapseWidth.lowerBound)
        XCTAssertTrue(toggleSource.contains("Task.sleep(for: .milliseconds(140))"))
        XCTAssertTrue(toggleSource.contains("collapseAnimationTask?.cancel()"))
        XCTAssertTrue(source.contains("if showsTitle"))
    }

    func testCollapsedSidebarContentIsCentered() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsAppShell.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)"))
        XCTAssertTrue(source.contains(".padding(.horizontal, isCollapsed ? 0 : AppSpacing.xl)"))
        XCTAssertTrue(source.contains("if !isCollapsed {\n                    Spacer(minLength: 0)"))
    }

    func testSidebarDoesNotRenderGroupLabels() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsAppShell.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Text(group.title)"))
        XCTAssertFalse(source.contains("SettingsNavigationGroup(title:"))
        XCTAssertTrue(source.contains("SettingsNavigationGroup(id:"))
        XCTAssertTrue(source.contains("ForEach(navigationGroups)"))
    }
}

final class AppBrandIconPresentationContractTests: XCTestCase {
    func testSettingsBrandIconsCropTheOpaqueSourceCanvas() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSystem = try String(
            contentsOf: root.appendingPathComponent("Views/AppDesignSystem.swift"),
            encoding: .utf8
        )
        let about = try String(
            contentsOf: root.appendingPathComponent("Views/AboutView.swift"),
            encoding: .utf8
        )
        let sidebar = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsAppShell.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(designSystem.contains("struct AppBrandIconView: View"))
        XCTAssertFalse(designSystem.contains("AppBrandAsset.displayScale"))
        let componentStart = try XCTUnwrap(designSystem.range(of: "struct AppBrandIconView: View"))
        let componentEnd = try XCTUnwrap(
            designSystem.range(of: "enum AppColor", range: componentStart.upperBound..<designSystem.endIndex)
        )
        let componentSource = designSystem[componentStart.lowerBound..<componentEnd.lowerBound]
        XCTAssertFalse(componentSource.contains(".scaleEffect("))
        XCTAssertTrue(designSystem.contains(".clipShape("))
        XCTAssertTrue(designSystem.contains("RoundedRectangle("))
        XCTAssertTrue(about.contains("AppBrandIconView(size: 82)"))
        XCTAssertTrue(sidebar.contains("AppBrandIconView(size: 38)"))
        XCTAssertFalse(about.contains("Image(nsImage: AppBrandAsset.icon)"))
        XCTAssertFalse(sidebar.contains("Image(nsImage: AppBrandAsset.icon)"))
    }
}

final class AppIconAssetContractTests: XCTestCase {
    func testAppIconAssetsUseCroppedMasterArtworkAtEveryRequiredSize() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let iconDirectory = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        let expectedSizes: [String: Int] = [
            "AppIcon-16x16@1x.png": 16,
            "AppIcon-16x16@2x.png": 32,
            "AppIcon-32x32@1x.png": 32,
            "AppIcon-32x32@2x.png": 64,
            "AppIcon-128x128@1x.png": 128,
            "AppIcon-128x128@2x.png": 256,
            "AppIcon-256x256@1x.png": 256,
            "AppIcon-256x256@2x.png": 512,
            "AppIcon-512x512@1x.png": 512,
            "AppIcon-512x512@2x.png": 1024,
        ]

        for (filename, expectedSize) in expectedSizes {
            let image = try XCTUnwrap(NSImage(contentsOf: iconDirectory.appendingPathComponent(filename)))
            let representation = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            XCTAssertEqual(representation.pixelsWide, expectedSize, filename)
            XCTAssertEqual(representation.pixelsHigh, expectedSize, filename)
        }

        let master = try XCTUnwrap(
            NSImage(contentsOf: iconDirectory.appendingPathComponent("AppIcon-512x512@2x.png"))
        )
        let masterRepresentation = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(master.tiffRepresentation))
        )
        let leftEdgeColor = try XCTUnwrap(
            masterRepresentation.colorAt(x: 32, y: masterRepresentation.pixelsHigh / 2)?
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(
            leftEdgeColor.blueComponent - leftEdgeColor.redComponent,
            0.06,
            "AppIcon 仍包含外圈灰色画布"
        )
    }
}

final class AboutLegalContentContractTests: XCTestCase {
    func testPrivacyAndLicenseUseDetailedInAppDocuments() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/AboutView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".sheet(item: $model.presentedLegalInfo)"))
        XCTAssertTrue(source.contains("NookFlow 不会出售你的个人信息"))
        XCTAssertTrue(source.contains("Open-Meteo"))
        XCTAssertTrue(source.contains("CC BY 4.0"))
        XCTAssertTrue(source.contains("当前未发布开源许可证"))
        XCTAssertTrue(source.contains("lujunfeng.lucky@foxmail.com"))
    }
}

final class CompactPausedLyricContractTests: XCTestCase {
    func testCompactLyricsResolvePausedPositionDuringStartup() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("updateCompactLyric(index: viewModel.lyricsProvider.currentLineIndex)"))
        XCTAssertTrue(source.contains("resolvedCompactLyricIndex(requestedIndex: index, lyrics: lyrics)"))
        XCTAssertTrue(source.contains("currentSnapshot.elapsed + 0.5"))
        XCTAssertTrue(source.contains("lyrics.lastIndex { line in"))
    }
}

final class SettingsActionMenuContractTests: XCTestCase {
    func testExpandedSettingsButtonUsesNativeMacOSMenu() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var settingsButton: some View {\n        Menu {"))
        XCTAssertTrue(source.contains("Label(\"打开设置\", systemImage: \"gearshape\")"))
        XCTAssertTrue(source.contains("Label(\"问题反馈\", systemImage: \"bubble.left.and.exclamationmark\")"))
        XCTAssertTrue(source.contains("Label(\"退出 NookFlow\", systemImage: \"power\")"))
        XCTAssertTrue(source.contains(".menuStyle(.borderlessButton)"))
        XCTAssertTrue(source.contains("Color.clear\n                .frame(width: 28, height: 28)"))
        XCTAssertTrue(source.contains(".overlay {\n            SettingsMenuLabel()\n                .allowsHitTesting(false)"))
        XCTAssertFalse(source.contains("isSettingsMenuPresented"))
        XCTAssertFalse(source.contains("settingsActionMenuBackground"))
    }
}

final class FeedbackEmailContractTests: XCTestCase {
    func testFeedbackMailUsesConfiguredFoxmailAddress() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private let supportEmail = \"lujunfeng.lucky@foxmail.com\""))
        XCTAssertFalse(source.contains("ardenpro@icloud.com"))
    }
}

final class DockPresentationContractTests: XCTestCase {
    func testAppRemainsVisibleInDockForEntireRuntime() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("App/AppDelegate.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let settingsWindow = try String(
            contentsOf: root.appendingPathComponent("Panel/SettingsWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appDelegate.contains("NSApp.setActivationPolicy(.regular)"))
        XCTAssertFalse(settings.contains("@Published var hideDock"))
        XCTAssertFalse(settings.contains(".accessory"))
        XCTAssertTrue(settings.contains("defaults.removeObject(forKey: \"settings.hideDock\")"))
        XCTAssertFalse(settingsWindow.contains("previousActivationPolicy"))
        XCTAssertFalse(settingsWindow.contains("restoreActivationPolicyIfNeeded"))
    }
}

final class SettingsWindowActivationContractTests: XCTestCase {
    func testDockReopenKeepsSettingsWindowAtFrontWithoutLevelDemotion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Panel/SettingsWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("window.level = .normal\n        window.orderFrontRegardless()"))
        XCTAssertTrue(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertFalse(source.contains("window.level = .floating"))
        XCTAssertFalse(source.contains("420_000_000"))
    }
}

final class ModuleWidthContractTests: XCTestCase {
    func testUtilityModulesUseCompactWidthWeights() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )
        let layout = try String(
            contentsOf: root.appendingPathComponent("Views/IslandShellLayout.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(tokens.contains("quickAppsModuleWidthWeight: CGFloat = 0.86"))
        XCTAssertTrue(tokens.contains("shortcutsModuleWidthWeight: CGFloat = 0.82"))
        XCTAssertTrue(tokens.contains("deviceInfoModuleWidthWeight: CGFloat = 0.90"))
        XCTAssertTrue(layout.contains("case .quickApps:\n            return IslandDesignTokens.quickAppsModuleWidthWeight"))
        XCTAssertTrue(layout.contains("case .shortcuts:\n            return IslandDesignTokens.shortcutsModuleWidthWeight"))
        XCTAssertTrue(layout.contains("case .deviceInfo:\n            return IslandDesignTokens.deviceInfoModuleWidthWeight"))
    }
}

final class ShortcutsCardPresentationContractTests: XCTestCase {
    func testShortcutCardUsesCompactBlueCommandRowsAndSemanticSymbols() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/ShortcutsCardView.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Text(\"\\(configuredShortcutCount)/\\(ShortcutsStore.slotCount)\")"))
        XCTAssertTrue(source.contains("shortcutSymbol(for: item.name)"))
        XCTAssertTrue(source.contains("([\"音乐\", \"识别\"], \"waveform\")"))
        XCTAssertTrue(source.contains("StrokeStyle(lineWidth: 1, dash: [4, 3])"))
        XCTAssertTrue(source.contains("添加快捷指令"))
        XCTAssertFalse(source.contains("shortcutTint("))
        XCTAssertFalse(source.contains("let palette: [Color]"))
        XCTAssertTrue(expandedView.contains("module == .weather || module == .todo || module == .shortcuts"))
    }
}

final class WeatherPresentationContractTests: XCTestCase {
    func testExpandedIslandReusesRootWeatherProvider() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )
        let provider = try String(
            contentsOf: root.appendingPathComponent("Models/WeatherProvider.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(rootView.contains("weatherProvider: weatherProvider"))
        XCTAssertTrue(expandedView.contains("@ObservedObject var weatherProvider: WeatherProvider"))
        XCTAssertFalse(expandedView.contains("@StateObject private var weatherProvider = WeatherProvider()"))
        XCTAssertTrue(expandedView.contains("if weather.isLoading"))
        XCTAssertTrue(provider.contains("var isLoading: Bool"))
        XCTAssertTrue(provider.contains("condition == \"定位中\" || condition == \"加载中\""))
        XCTAssertTrue(provider.contains("condition: \"加载中\""))
        XCTAssertTrue(provider.contains("symbolName: \"\""))
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
