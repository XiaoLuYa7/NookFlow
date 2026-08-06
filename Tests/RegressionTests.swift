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

final class NotificationDeliveryPolicyTests: XCTestCase {
    func testRejectsNotificationsWhileSystemIsSleeping() {
        let now = Date()

        XCTAssertFalse(NotificationDeliveryPolicy.shouldDeliver(
            createdAt: now,
            now: now,
            isSystemSleeping: true,
            suppressedUntil: nil
        ))
    }

    func testRejectsNotificationsDuringWakeRecoveryWindow() {
        let now = Date()

        XCTAssertFalse(NotificationDeliveryPolicy.shouldDeliver(
            createdAt: now,
            now: now,
            isSystemSleeping: false,
            suppressedUntil: now.addingTimeInterval(10)
        ))
    }

    func testRejectsQueuedNotificationThatIsTooOld() {
        let now = Date()

        XCTAssertFalse(NotificationDeliveryPolicy.shouldDeliver(
            createdAt: now.addingTimeInterval(-31),
            now: now,
            isSystemSleeping: false,
            suppressedUntil: nil
        ))
    }

    func testAllowsFreshNotificationAfterRecoveryWindow() {
        let now = Date()

        XCTAssertTrue(NotificationDeliveryPolicy.shouldDeliver(
            createdAt: now.addingTimeInterval(-2),
            now: now,
            isSystemSleeping: false,
            suppressedUntil: now.addingTimeInterval(-1)
        ))
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
        defaults.set(true, forKey: "settings.allowQQMusicAccess")
        defaults.set(true, forKey: "settings.allowNetEaseMusicAccess")

        let cached = PlaybackAccessConfiguration.defaults
        let resolved = PlaybackAccessConfiguration.persisted(defaults: defaults, fallback: cached)

        XCTAssertFalse(resolved.appleMusic)
        XCTAssertTrue(resolved.spotify)
        XCTAssertTrue(resolved.qqMusic)
        XCTAssertTrue(resolved.netEaseMusic)
    }
}

final class SystemNowPlayingMetadataParserTests: XCTestCase {
    func testAdapterStreamKeysAdvancePlayingPositionFromTimestamp() throws {
        let snapshot = try XCTUnwrap(SystemNowPlayingMetadataParser.snapshot(
            info: [
                "title": "流式歌曲",
                "artist": "流式歌手",
                "album": "流式专辑",
                "duration": 240.0,
                "elapsedTime": 60.0,
                "playbackRate": 1.0,
                "timestamp": "1970-01-01T00:01:40Z"
            ],
            bundleIdentifier: "com.tencent.QQMusicMac",
            isPlaying: true,
            now: Date(timeIntervalSince1970: 102)
        ))

        XCTAssertEqual(snapshot.appName, "QQ音乐")
        XCTAssertEqual(snapshot.elapsed, 62)
    }

    func testQQMusicSnapshotReadsSystemNowPlayingMetadata() throws {
        let timestamp = Date(timeIntervalSince1970: 100)
        let snapshot = try XCTUnwrap(SystemNowPlayingMetadataParser.snapshot(
            info: [
                "kMRMediaRemoteNowPlayingInfoTitle": "测试歌曲",
                "kMRMediaRemoteNowPlayingInfoArtist": "测试歌手",
                "kMRMediaRemoteNowPlayingInfoAlbum": "测试专辑",
                "kMRMediaRemoteNowPlayingInfoDuration": 240.0,
                "kMRMediaRemoteNowPlayingInfoElapsedTime": 60.0,
                "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0,
                "kMRMediaRemoteNowPlayingInfoTimestamp": timestamp
            ],
            bundleIdentifier: "com.tencent.QQMusicMac",
            isPlaying: true,
            now: timestamp.addingTimeInterval(2)
        ))

        XCTAssertEqual(snapshot.appName, "QQ音乐")
        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.title, "测试歌曲")
        XCTAssertEqual(snapshot.artist, "测试歌手")
        XCTAssertEqual(snapshot.album, "测试专辑")
        XCTAssertEqual(snapshot.duration, 240)
        XCTAssertEqual(snapshot.elapsed, 62)
    }

    func testNetEasePausedSnapshotKeepsReportedPosition() throws {
        let snapshot = try XCTUnwrap(SystemNowPlayingMetadataParser.snapshot(
            info: [
                "kMRMediaRemoteNowPlayingInfoTitle": "暂停歌曲",
                "kMRMediaRemoteNowPlayingInfoElapsedTime": 35.0,
                "kMRMediaRemoteNowPlayingInfoPlaybackRate": 0.0
            ],
            bundleIdentifier: "com.netease.163music",
            isPlaying: false
        ))

        XCTAssertEqual(snapshot.appName, "网易云音乐")
        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.elapsed, 35)
    }

    func testUnsupportedSystemPlayerIsIgnored() {
        XCTAssertNil(SystemNowPlayingMetadataParser.snapshot(
            info: ["kMRMediaRemoteNowPlayingInfoTitle": "Other"],
            bundleIdentifier: "com.example.OtherPlayer",
            isPlaying: true
        ))
    }
}

final class TodoDateTimeInputParserTests: XCTestCase {
    func testNumericInputClampsOnlyValuesAboveMaximum() {
        XCTAssertEqual(
            TodoDateTimeInputParser.clampedDigits("19", maxLength: 2, maximum: 12),
            "12"
        )
        XCTAssertEqual(
            TodoDateTimeInputParser.clampedDigits("99", maxLength: 2, maximum: 23),
            "23"
        )
        XCTAssertEqual(
            TodoDateTimeInputParser.clampedDigits("88", maxLength: 2, maximum: 59),
            "59"
        )
        XCTAssertEqual(
            TodoDateTimeInputParser.clampedDigits("09", maxLength: 2, maximum: 12),
            "09"
        )
    }

    func testMaximumDayUsesSelectedYearAndMonth() {
        XCTAssertEqual(TodoDateTimeInputParser.maximumDay(year: "2024", month: "2"), 29)
        XCTAssertEqual(TodoDateTimeInputParser.maximumDay(year: "2025", month: "2"), 28)
        XCTAssertEqual(TodoDateTimeInputParser.maximumDay(year: "2026", month: "4"), 30)
    }
}

@MainActor
final class TodoViewModelTests: XCTestCase {
    func testDefaultTasksAreEmpty() {
        XCTAssertTrue(TodoViewModel().tasks.isEmpty)
    }

    func testTodoDraftExposesCategoryAndPriority() throws {
        let draft = TodoTaskDraft(
            title: "Task",
            notes: "",
            date: Date(),
            dueTime: nil,
            hasAlarm: false,
            location: ""
        )
        let labels = Set(Mirror(reflecting: draft).children.compactMap(\.label))

        XCTAssertTrue(labels.contains("category"))
        XCTAssertTrue(labels.contains("priority"))
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
    func testNetworkPublishesNotFoundOnlyAfterEverySourceCompletes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Models/LyricsNetworkService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let sourceCount = 4"))
        XCTAssertTrue(source.contains("completedSourceCount += 1"))
        XCTAssertTrue(source.contains("if completedSourceCount == sourceCount"))
        XCTAssertTrue(source.contains("guard let best else { return .notFound }"))
        XCTAssertTrue(source.contains(
            "case .softDeadline:\n                    if let best"
        ))
        XCTAssertTrue(source.contains("URLQueryItem(name: \"keywords\""))
        XCTAssertTrue(source.contains("URLQueryItem(name: \"track_name\""))
        XCTAssertFalse(source.contains("addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)"))
    }

    func testTransientPlaybackGapStaysLoadingUntilNextTrackLyricsArrive() async throws {
        let cache = MemoryLyricsCache()
        await cache.set(
            key: "old-id",
            title: "Old",
            artist: "Artist",
            lyrics: [LyricLine(startTimeMS: 0, words: "Old lyric")]
        )
        let provider = LyricsProvider(
            networkService: DelayedLyricsNetwork(),
            cache: cache
        )
        provider.update(for: snapshot(title: "Old"), trackID: "old-id")

        provider.update(for: .idle, trackID: nil)

        XCTAssertEqual(provider.displayState, .loading)
        XCTAssertTrue(provider.lyrics.isEmpty)

        provider.update(for: snapshot(title: "Next"), trackID: "next-id")

        XCTAssertEqual(provider.displayState, .loading)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(provider.displayState, .ready)
        XCTAssertEqual(provider.lyrics.first?.words, "Next lyric")
    }

    func testUnavailableAppearsOnlyAfterAggregatedSearchFinishes() async throws {
        let provider = LyricsProvider(
            networkService: DelayedNotFoundLyricsNetwork(),
            cache: MemoryLyricsCache()
        )

        provider.update(for: snapshot(title: "Missing"), trackID: "missing-id")

        XCTAssertEqual(provider.displayState, .loading)
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertEqual(provider.displayState, .loading)

        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(provider.displayState, .unavailable("暂无歌词"))
    }

    func testTrackChangePublishesLoadingBeforeClearingPreviousLyrics() async throws {
        let cache = MemoryLyricsCache()
        await cache.set(
            key: "cached-id",
            title: "Cached",
            artist: "Artist",
            lyrics: [LyricLine(startTimeMS: 0, words: "Cached lyric")]
        )
        let provider = LyricsProvider(networkService: DelayedLyricsNetwork(), cache: cache)
        provider.update(for: snapshot(title: "Cached"), trackID: "cached-id")
        try await Task.sleep(for: .milliseconds(30))

        var stateWhenLyricsCleared: LyricsDisplayState?
        let cancellable = provider.$lyrics
            .dropFirst()
            .sink { lines in
                if lines.isEmpty {
                    stateWhenLyricsCleared = provider.displayState
                }
            }

        provider.update(for: snapshot(title: "Next"), trackID: "next-id")

        XCTAssertEqual(stateWhenLyricsCleared, .loading)
        withExtendedLifetime(cancellable) {}
    }

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

    func testPausedPlaybackRestoresLyricAtCurrentElapsedPosition() async throws {
        let cache = MemoryLyricsCache()
        await cache.set(
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
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(provider.currentLineIndex, 1)

        paused.elapsed = 95
        provider.update(for: paused, trackID: "paused-id")

        XCTAssertEqual(provider.currentLineIndex, 2)
    }

    func testDesktopLyricsUseFourTenthsLeadWithoutChangingSharedLead() async throws {
        let cache = MemoryLyricsCache()
        await cache.set(
            key: "desktop-lead-id",
            title: "Desktop Lead",
            artist: "Artist",
            lyrics: [
                LyricLine(startTimeMS: 0, words: "Opening"),
                LyricLine(startTimeMS: 60_000, words: "Next line")
            ]
        )
        let provider = LyricsProvider(networkService: DelayedLyricsNetwork(), cache: cache)
        var paused = snapshot(title: "Desktop Lead")
        paused.state = .paused
        paused.elapsed = 59.55

        provider.update(for: paused, trackID: "desktop-lead-id")
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(provider.currentLineIndex, 1)
        XCTAssertEqual(provider.desktopPresentationLineIndex, 0)

        paused.elapsed = 59.65
        provider.update(for: paused, trackID: "desktop-lead-id")

        XCTAssertEqual(provider.desktopPresentationLineIndex, 1)
    }

    func testNextTrackLyricsArePrefetchedIntoCache() async throws {
        let cache = MemoryLyricsCache()
        let provider = LyricsProvider(networkService: DelayedLyricsNetwork(), cache: cache)
        let nextTrack = try XCTUnwrap(MediaRemoteNextTrack(payload: [
            "title": "Next",
            "artist": "Artist",
            "album": "Album",
            "duration": 180.0,
            "uniqueIdentifier": "next-id"
        ]))

        provider.prefetch(nextTrack)
        try await Task.sleep(for: .milliseconds(80))

        let cachedLyrics = await cache.get(key: "next-id")
        XCTAssertEqual(cachedLyrics?.first?.words, "Next lyric")
        XCTAssertTrue(provider.lyrics.isEmpty)
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

final class MediaRemoteNextTrackTests: XCTestCase {
    func testQueuePayloadMapsMetadataWithoutArtwork() throws {
        let track = try XCTUnwrap(MediaRemoteNextTrack(payload: [
            "title": "下一首",
            "artist": "歌手",
            "album": "专辑",
            "duration": 210,
            "contentItemIdentifier": "queue-item"
        ]))

        XCTAssertEqual(track.title, "下一首")
        XCTAssertEqual(track.artist, "歌手")
        XCTAssertEqual(track.duration, 210)
        XCTAssertEqual(track.trackID, "queue-item")
    }
}

final class CalendarCardRemovalContractTests: XCTestCase {
    func testStandaloneCalendarCardIsRemovedWhileTodoDateFeaturesRemain() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileManager = FileManager.default

        XCTAssertFalse(fileManager.fileExists(
            atPath: root.appendingPathComponent("Models/CalendarProvider.swift").path
        ))

        let productionFiles = [
            "Models/IslandSettings.swift",
            "Views/ExpandedIslandView.swift",
            "Views/IslandShellLayout.swift",
            "Views/SettingsRootView.swift",
            "Panel/IslandWindowController.swift",
            "NookFlow.xcodeproj/project.pbxproj",
            "Package.swift"
        ]
        let productionSource = try productionFiles.map { path in
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }.joined(separator: "\n")

        XCTAssertFalse(productionSource.contains("CalendarProvider"))
        XCTAssertFalse(productionSource.contains("showCalendarModule"))
        XCTAssertFalse(productionSource.contains("calendarStyle"))
        XCTAssertFalse(productionSource.contains("NSCalendarsFullAccessUsageDescription"))

        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let reminderPanel = try String(
            contentsOf: root.appendingPathComponent("Views/NewReminderPanelView.swift"),
            encoding: .utf8
        )
        let expandedIsland = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("showTodoModule"))
        XCTAssertTrue(reminderPanel.contains("ReminderInlineCalendarPicker"))
        XCTAssertTrue(expandedIsland.contains("TodoDarkCalendarPopover"))
    }
}

final class IslandPanelTopEdgeContractTests: XCTestCase {
    func testIslandPanelBleedsTwoPhysicalPixelsPastScreenTop() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Panel/IslandWindowController.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let screenTop = ceil(screenFrame.maxY * scale) / scale"))
        XCTAssertTrue(source.contains(
            "let topEdgeBleed = IslandDesignTokens.shellTopEdgeBleedPhysicalPixels / scale"
        ))
        XCTAssertTrue(tokens.contains("static let shellTopEdgeBleedPhysicalPixels: CGFloat = 2"))
        XCTAssertTrue(source.contains("let y = screenTop + topEdgeBleed - height"))
    }
}

final class MenuBarLyricsContractTests: XCTestCase {
    func testMenuBarLyricsReusePlaybackAndLyricsProvidersWithoutPolling() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: root.appendingPathComponent("Panel/DesktopLyricsWindowController.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let settingsView = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )
        let islandRoot = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("enum LyricsPresentationMode"))
        XCTAssertTrue(settings.contains("case capsule"))
        XCTAssertTrue(settings.contains("@Published var menuBarLyricsWidth: Double"))
        XCTAssertTrue(settings.contains(
            "@Published var menuBarLyricsShowsPlaybackControls: Bool"
        ))
        XCTAssertTrue(settings.contains("synchronizeLyricsPresentation()"))
        XCTAssertTrue(settings.contains(
            "showDesktopLyrics && lyricsPresentationMode == .capsule"
        ))
        XCTAssertTrue(controller.contains("NSStatusBar.system.statusItem"))
        XCTAssertTrue(controller.contains("NSStatusBar.system.removeStatusItem"))
        XCTAssertTrue(controller.contains("static let playbackControlsWidth: CGFloat = 73"))
        XCTAssertTrue(controller.contains("static let maximumLyricsWidth: CGFloat = 150"))
        XCTAssertTrue(controller.contains(
            "static let maximumDisplayedWidthWithControls: CGFloat = 220"
        ))
        XCTAssertTrue(controller.contains("static func maximumDisplayedWidth("))
        XCTAssertTrue(controller.contains("static func displayedWidth("))
        XCTAssertTrue(controller.contains("static func displayedWidthRange("))
        XCTAssertTrue(controller.contains("static func preferredLyricsWidth("))
        XCTAssertTrue(controller.contains(
            "showsPlaybackControls ? playbackControlsWidth : 0"
        ))
        XCTAssertTrue(controller.contains("@ObservedObject var playbackProvider: PlaybackProvider"))
        XCTAssertTrue(controller.contains("@ObservedObject var lyricsProvider: LyricsProvider"))
        XCTAssertFalse(controller.contains("hostingView.passesMouseEventsThrough = true"))
        XCTAssertTrue(controller.contains("playbackControlsMouseMonitor"))
        XCTAssertTrue(controller.contains("NSEvent.mouseLocation"))
        XCTAssertTrue(controller.contains("window.convertToScreen"))
        XCTAssertTrue(controller.contains("button.cell as? NSButtonCell"))
        XCTAssertTrue(controller.contains("buttonCell.highlightsBy = []"))
        XCTAssertTrue(controller.contains("buttonCell.showsStateBy = []"))
        XCTAssertTrue(controller.contains("matching: [.leftMouseDown, .leftMouseUp]"))
        XCTAssertTrue(controller.contains("guard event.type == .leftMouseDown else { return true }"))
        XCTAssertFalse(controller.contains("event.window === button.window"))
        XCTAssertTrue(controller.contains("Button(action: action)"))
        XCTAssertTrue(controller.contains("action: playbackProvider.previousTrack"))
        XCTAssertTrue(controller.contains("action: playbackProvider.togglePlayback"))
        XCTAssertTrue(controller.contains("action: playbackProvider.nextTrack"))
        XCTAssertTrue(controller.contains("case .capsule:"))
        XCTAssertTrue(controller.contains(
            ".animation(paused: !needsContinuousTimeline(for: presentation))"
        ))
        XCTAssertTrue(controller.contains("menuBarLyricText(presentation.text, color: sungLyricColor)"))
        XCTAssertTrue(controller.contains("needsProgressAnimation: presentation.timing.map"))
        XCTAssertTrue(controller.contains(
            "playbackAnchor.estimatedTime() + LyricPlaybackTiming.revealOffset"
        ))
        XCTAssertTrue(controller.contains("-overflow * scrollingProgress(from: playbackProgress)"))
        XCTAssertTrue(controller.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertFalse(controller.contains(".truncationMode(.tail)"))

        let menuBarController = try XCTUnwrap(
            controller.components(separatedBy: "private final class MenuBarLyricsController")
                .dropFirst().first?
                .components(separatedBy: "private struct MenuBarLyricsView").first
        )
        XCTAssertFalse(menuBarController.contains("Timer"))
        XCTAssertFalse(menuBarController.contains("DispatchQueue"))

        XCTAssertTrue(settingsView.contains("options: LyricsPresentationMode.allCases"))
        XCTAssertTrue(settingsView.contains("value: menuBarLyricsDisplayedWidth"))
        XCTAssertTrue(settingsView.contains("MenuBarLyricsLayout.displayedWidthRange("))
        XCTAssertTrue(settingsView.contains("菜单栏常驻播控"))
        XCTAssertTrue(settingsView.contains(
            "MenuBarLyricsLayout.displayedWidth("
        ))
        XCTAssertTrue(settingsView.contains(
            "showsPlaybackControls: model.menuBarLyricsShowsPlaybackControls"
        ))
        XCTAssertTrue(settings.contains("min(max(menuBarLyricsWidth, 100), 150)"))
        XCTAssertFalse(settingsView.contains("title: \"显示歌名\""))
        XCTAssertTrue(islandRoot.contains("|| settings.showDesktopLyrics"))
        XCTAssertTrue(islandRoot.contains(
            "settings.lyricsPresentationMode == .menuBar {\n            mode = .camera"
        ))
        XCTAssertFalse(islandRoot.contains(
            "settings.lyricsPresentationMode == .desktop {\n            mode = .status"
        ))
        XCTAssertTrue(islandRoot.contains("showsTrackName: false"))
        XCTAssertTrue(controller.contains("identity: \"status.unavailable\""))
        XCTAssertTrue(controller.contains("text: \"暂无歌词\""))
    }
}

final class MenuBarLyricTransitionContractTests: XCTestCase {
    func testLineChangeCrossfadesIndependentLayersWithoutReversingScrollOffset() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Panel/DesktopLyricsWindowController.swift"),
            encoding: .utf8
        )
        let menuBarView = try XCTUnwrap(
            source.components(separatedBy: "private struct MenuBarLyricsView").dropFirst().first?
                .components(separatedBy: "private struct MenuBarLyricPresentation").first
        )

        XCTAssertTrue(menuBarView.contains(".id(presentation.identity)"))
        XCTAssertTrue(menuBarView.contains(".transition(.opacity)"))
        XCTAssertTrue(menuBarView.contains(
            ".animation(lineTransitionAnimation, value: presentation.identity)"
        ))
        XCTAssertFalse(menuBarView.contains(
            ".animation(.easeInOut(duration: 0.18), value: presentation.text)"
        ))
    }
}

final class LyricDisplayRefreshCadenceContractTests: XCTestCase {
    func testVisibleLyricAnimationsUseDisplaySynchronizedTimelines() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let desktopSource = try String(
            contentsOf: root.appendingPathComponent("Panel/DesktopLyricsWindowController.swift"),
            encoding: .utf8
        )
        let capsuleSource = try String(
            contentsOf: root.appendingPathComponent("Views/CompactCapsuleContentView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(desktopSource.contains(".periodic(from: .now, by: 1.0 / 30.0)"))
        XCTAssertFalse(capsuleSource.contains(".periodic(from: .now, by: 1.0 / 30.0)"))
        XCTAssertFalse(desktopSource.contains("minimumInterval: 1.0 / 30.0"))
        XCTAssertTrue(desktopSource.contains(
            ".animation(paused: !needsContinuousTimeline(for: presentation))"
        ))
        XCTAssertTrue(desktopSource.contains(
            "TimelineView(.animation(paused: !needsContinuousTimeline))"
        ))
        XCTAssertTrue(capsuleSource.contains(
            "TimelineView(.animation(paused: !usesTimeline))"
        ))
    }
}

final class IslandDisplayRefreshCadenceContractTests: XCTestCase {
    func testIslandMotionUsesDisplaySynchronizedRenderingWithoutManualFrameCaps() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expandedSource = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )
        let notchLyricSource = try String(
            contentsOf: root.appendingPathComponent("Views/NotchLyricView.swift"),
            encoding: .utf8
        )
        let quickAppsSource = try String(
            contentsOf: root.appendingPathComponent("Views/QuickAppsCardView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(expandedSource.contains("minimumInterval: 1.0 / 30.0"))
        XCTAssertTrue(expandedSource.contains(
            "TimelineView(.animation(paused: !needsContinuousTimeline))"
        ))
        XCTAssertEqual(
            notchLyricSource.components(
                separatedBy: "TimelineView(.animation(paused: !needsTimeline))"
            ).count - 1,
            2
        )
        XCTAssertFalse(notchLyricSource.contains("if needsTimeline"))

        XCTAssertTrue(expandedSource.contains("ScrollView(.horizontal)"))
        XCTAssertTrue(expandedSource.contains(
            ".scrollTargetBehavior(.viewAligned(limitBehavior: .always))"
        ))
        XCTAssertTrue(quickAppsSource.contains(".compositingGroup()"))
        XCTAssertTrue(quickAppsSource.contains(
            ".animation(pageAnimation, value: currentPage)"
        ))
        XCTAssertFalse(quickAppsSource.contains("Timer"))
        XCTAssertFalse(quickAppsSource.contains("TimelineView"))
    }
}

final class DesktopLyricsVisualContractTests: XCTestCase {
    func testDesktopLyricsUseFiveLineHierarchyAndHoverHiding() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Panel/DesktopLyricsWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private struct DesktopLyricsFocusSurface"))
        XCTAssertTrue(source.contains("if #available(macOS 26.0, *)"))
        XCTAssertTrue(source.contains(".glassEffect(.regular.tint(glassTint), in: shape)"))
        XCTAssertTrue(source.contains("private struct DesktopLyricsBackdropMaterial"))
        XCTAssertTrue(source.contains("view.blendingMode = .behindWindow"))
        XCTAssertTrue(source.contains("palette.usesDarkText ? .popover : .hudWindow"))
        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(source.contains("contrastHalo"))
        XCTAssertTrue(source.contains(
            "lyricsPlaceholder(\"正在加载歌词...\", showsSurface: false)"
        ))
        let lyricLineView = try XCTUnwrap(
            source.components(separatedBy: "private struct LyricLineView").dropFirst().first?
                .components(separatedBy: "private struct DesktopLyricsFocusSurface").first
        )
        XCTAssertFalse(lyricLineView.contains("DesktopLyricsFocusSurface"))
        XCTAssertFalse(lyricLineView.contains(".background"))
        XCTAssertTrue(source.contains("radius: style.isCurrent ? 0.7 : 1.05"))
        XCTAssertTrue(source.contains("style.shadowStrength * 0.16"))
        XCTAssertTrue(source.contains("maximumTextWidth + 40"))
        XCTAssertTrue(source.contains("fontSize = 17"))
        XCTAssertTrue(source.contains("let visibleLineCount = 5"))
        XCTAssertTrue(source.contains("let anchorRatio: CGFloat = 0.5"))
        XCTAssertTrue(source.contains("opacity = 0.68"))
        XCTAssertTrue(source.contains("blurRadius = 0.45"))
        XCTAssertTrue(source.contains("opacity = 0.40"))
        XCTAssertTrue(source.contains("blurRadius = 1.25"))
        XCTAssertEqual(source.components(separatedBy: "fontSize = 14.5").count - 1, 3)
        XCTAssertTrue(source.contains("default:\n            opacity = 0"))
        XCTAssertFalse(source.contains("isPlayed ?"))
        XCTAssertTrue(source.contains("private func startPointerTracking()"))
        XCTAssertTrue(source.contains("matching: [.mouseMoved]"))
        XCTAssertTrue(source.contains("private func stopPointerTracking()"))
        XCTAssertTrue(source.contains("private func desktopLyricsHoverRegion(in panel: NSPanel)"))
        XCTAssertTrue(source.contains("timelineController.setWindowVisibility(panel.alphaValue > 0 && !isHovering)"))
        XCTAssertTrue(source.contains(".opacity(timeline.isPointerHovering ? 0 : 1)"))
        XCTAssertTrue(source.contains("stopPointerTracking()\n        menuBarLyricsController.close()"))
        XCTAssertTrue(source.contains("response: 0.44"))
        XCTAssertTrue(source.contains("dampingFraction: 0.92"))
        XCTAssertTrue(source.contains("distance <= timeline.visibleLineCount"))
        XCTAssertTrue(source.contains("withAnimation(scrollAnimation)"))
        XCTAssertTrue(source.contains("paused: !needsContinuousTimeline"))
        XCTAssertFalse(source.contains("@State private var contentOpacity"))
        XCTAssertFalse(source.contains("@State private var jumpTask"))
        XCTAssertFalse(source.contains("Task.sleep(for: .milliseconds(90))"))
        XCTAssertFalse(lyricLineView.contains("if needsContinuousTimeline"))
        XCTAssertFalse(source.contains("backgroundOpacity = isPlayed ? 0.52 : 0.58"))
        XCTAssertFalse(source.contains("backgroundOpacity = isPlayed ? 0.34 : 0.40"))
        XCTAssertTrue(source.contains("panel?.ignoresMouseEvents = !isEnabled"))
        XCTAssertFalse(source.contains("isHoverHidden"))
        XCTAssertFalse(source.contains("private func startMouseTracking()"))
        XCTAssertTrue(source.contains("globalPointerMonitor = NSEvent.addGlobalMonitorForEvents"))
    }
}

final class SettingsLayoutContractTests: XCTestCase {
    func testHomeAlwaysShowsFocusedCustomizationWithoutMonitoringDashboard() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("showsHomeCustomization"))
        XCTAssertFalse(source.contains("homeOverviewSection"))
        XCTAssertFalse(source.contains("homeOperationsSection"))
        XCTAssertFalse(source.contains("系统脉搏"))
        XCTAssertFalse(source.contains("今日概览"))
        XCTAssertTrue(source.contains(
            "previewArea\n            sideIconConfigurationCard\n            widgetsCard"
        ))
        XCTAssertTrue(source.contains("SectionTitle(title: \"灵动岛预览\""))
        XCTAssertTrue(source.contains("SectionTitle(title: \"小组件与卡片\""))
        XCTAssertTrue(source.contains("HStack(alignment: .top"))
        XCTAssertTrue(source.contains(".frame(width: 204, height: 148)"))
        XCTAssertTrue(source.contains("@State private var isHovering = false"))
        XCTAssertTrue(source.contains("AppMotion.settingsQuick"))
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

    func testNewTodoSheetUsesFullWidthScheduleRowsAndTaskAttributes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/TodoView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".frame(width: 520, height: 650)"))
        XCTAssertTrue(source.contains("taskAttributesSection"))
        XCTAssertTrue(source.contains("selection: $category"))
        XCTAssertTrue(source.contains("selection: $priority"))
        XCTAssertTrue(source.contains("sheetRow(\n                systemName: \"calendar\""))
        XCTAssertTrue(source.contains("sheetRow(\n                systemName: \"clock\""))
        XCTAssertTrue(source.contains("inlineTimeOptions"))
        XCTAssertTrue(source.contains("private var customTimeControl"))
        XCTAssertTrue(source.contains("private func numericInputField"))
        XCTAssertTrue(source.contains("OutsideTextFieldFocusDismissal"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(source.contains("NSEvent.removeMonitor"))
        XCTAssertTrue(source.contains("TodoDateTimeInputParser.maximumDay"))
        XCTAssertTrue(source.contains("maximum: 12"))
        XCTAssertTrue(source.contains("maximum: 23"))
        XCTAssertTrue(source.contains("maximum: 59"))
        XCTAssertFalse(source.contains("compactSchedulePanel("))
        XCTAssertFalse(source.contains("Text(\"快捷时间\")"))
        XCTAssertFalse(source.contains("private var timeSelectionControl"))
        XCTAssertFalse(source.contains("private func selectionMenu("))
        XCTAssertFalse(source.contains("DatePicker(\"\", selection: $customTime, displayedComponents: .hourAndMinute)"))
        XCTAssertFalse(source.contains("if selectedTimeOption == .custom {\n                HStack"))

        let timeButtonStart = try XCTUnwrap(source.range(of: "private func timeOptionButton"))
        let timeButtonSource = source[timeButtonStart.lowerBound...]
        XCTAssertTrue(timeButtonSource.contains(".contentShape(Rectangle())"))
    }

    func testSettingsTodoCreationSerializesCategoryAndPriorityTags() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let todoViewSource = try String(
            contentsOf: root.appendingPathComponent("Views/TodoView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: root.appendingPathComponent("Models/TodoViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(modelSource.contains("var category: TodoCategory = .none"))
        XCTAssertTrue(modelSource.contains("var priority: TodoPriority = .normal"))
        XCTAssertTrue(modelSource.contains("category: draft.category"))
        XCTAssertTrue(modelSource.contains("priority: draft.priority"))
        XCTAssertTrue(todoViewSource.contains("[category.tagText, priority.tagText]"))
        XCTAssertFalse(todoViewSource.contains("tagsText: \"\""))
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

    func testSidebarUsesCompactExpandedWidth() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsAppShell.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".frame(width: isCollapsed ? 60 : 184)"))
        XCTAssertFalse(source.contains(".frame(width: isCollapsed ? 60 : 208)"))
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

final class PlaybackArtworkStabilityContractTests: XCTestCase {
    func testArtworkPollingUsesStableTrackIdentityAndKeepsVisibleImageDuringReload() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let provider = try String(
            contentsOf: root.appendingPathComponent("Models/PlaybackProvider.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(provider.contains("case file(URL, id: String)"))
        XCTAssertTrue(provider.contains("artworkSource(from: parts[7], id: artworkID)"))
        XCTAssertFalse(provider.contains("artworkFileVersion"))
        XCTAssertTrue(expandedView.contains("PlaybackArtworkImageCache.cacheKey(for: url, id: id)"))
        XCTAssertFalse(expandedView.contains("\n        image = nil\n        let source = source"))
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
        XCTAssertTrue(source.contains("Color.clear\n                .frame(width: 32, height: 30)"))
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

    func testIslandSettingsMenuUsesItsVisibleLabelAsTheHitTarget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expanded = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: root.appendingPathComponent("Panel/IslandWindowController.swift"),
            encoding: .utf8
        )
        let settingsButton = try XCTUnwrap(
            expanded.components(separatedBy: "private var settingsButton: some View")
                .dropFirst().first?
                .components(separatedBy: "private func closeTodoFloatingPanel").first
        )

        XCTAssertTrue(settingsButton.contains(
            "Color.clear\n                .frame(width: 32, height: 30)"
        ))
        XCTAssertTrue(settingsButton.contains(
            ".overlay {\n            SettingsMenuLabel()\n                .allowsHitTesting(false)"
        ))
        XCTAssertFalse(settingsButton.contains("await Task.yield()"))
        XCTAssertTrue(expanded.contains(".frame(width: 32, height: 30)"))
        XCTAssertTrue(controller.contains(
            "private var settingsPresentationTask: Task<Void, Never>?"
        ))
        XCTAssertTrue(controller.contains("settingsPresentationTask?.cancel()"))
        XCTAssertTrue(controller.contains(
            "settingsPresentationTask = Task { @MainActor [weak self] in"
        ))
        XCTAssertTrue(controller.contains("guard let self, !Task.isCancelled else { return }"))
    }
}

final class ModuleFixedWidthContractTests: XCTestCase {
    func testHomeModulesUseStablePointWidthsInsteadOfContainerPercentages() throws {
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
        let expanded = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(tokens.contains("weatherModuleFixedWidth: CGFloat = 168"))
        XCTAssertTrue(tokens.contains("mediaModuleFixedWidth: CGFloat = 240"))
        XCTAssertTrue(tokens.contains("todoModuleFixedWidth: CGFloat = 188"))
        XCTAssertTrue(tokens.contains("quickAppsTwoColumnFixedWidth: CGFloat = 126"))
        XCTAssertTrue(tokens.contains("quickAppsThreeColumnFixedWidth: CGFloat = 156"))
        XCTAssertTrue(tokens.contains("shortcutsModuleFixedWidth: CGFloat = 156"))
        XCTAssertTrue(tokens.contains("imageCardModuleFixedWidth: CGFloat = 124"))
        XCTAssertTrue(tokens.contains("deviceInfoModuleFixedWidth: CGFloat = 168"))
        XCTAssertTrue(tokens.contains("mirrorModuleFixedWidth: CGFloat = 168"))
        XCTAssertTrue(tokens.contains(
            "fourColumnsMinimumExpandedWidth: CGFloat = defaultExpandedSize.width"
        ))
        XCTAssertTrue(layout.contains(
            "case .quickApps:\n            return IslandDesignTokens.quickAppsModuleFixedWidth(for: quickAppsColumnCount)"
        ))
        XCTAssertTrue(layout.contains("cardsWidth = modules.reduce(CGFloat(0))"))
        XCTAssertTrue(layout.contains("partial + moduleFixedWidth("))
        XCTAssertTrue(layout.contains("fixedContentWidth"))
        XCTAssertTrue(layout.contains(
            "IslandDesignTokens.fourColumnsMinimumExpandedWidth,\n            fixedContentWidth"
        ))
        XCTAssertTrue(layout.contains(
            "case .applications:\n            return CGSize(\n                width: settings.islandSize.width"
        ))
        XCTAssertTrue(layout.contains(
            "case .files:\n            return CGSize(\n                width: settings.islandSize.width"
        ))
        XCTAssertTrue(expanded.contains("private var fixedModuleRow: some View"))
        XCTAssertTrue(expanded.contains("let w = moduleCardWidth(module)"))
        XCTAssertTrue(expanded.contains(
            ".frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)"
        ))
        XCTAssertTrue(expanded.contains("let artworkSize = max(1, cardHeight - 2)"))
        XCTAssertTrue(expanded.contains("private func moduleRowLeadingInset("))
        XCTAssertTrue(expanded.contains(
            "modules _: [IslandPanelModule],\n        containerWidth _: CGFloat\n    ) -> CGFloat {\n        0"
        ))
        XCTAssertFalse(expanded.contains(
            "(containerWidth - cardsWidth - spacingWidth) / 2"
        ))
        XCTAssertTrue(expanded.contains(") { moduleCardWidth($0) }"))
        XCTAssertFalse(expanded.contains("availableWidth * moduleWidthWeight"))
        XCTAssertFalse(expanded.contains("totalWeight"))
    }
}

final class EmptyModulesPresentationContractTests: XCTestCase {
    func testEmptyHomeUsesAFocusedLocalizedSetupAction() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        let emptyState = try XCTUnwrap(
            source.components(separatedBy: "private var emptyModulesView").dropFirst().first?
                .components(separatedBy: "@ViewBuilder").first
        )

        XCTAssertTrue(emptyState.contains("Text(\"定制你的首页\")"))
        XCTAssertTrue(emptyState.contains("Text(\"选择常用模块，让重要信息始终触手可及。\")"))
        XCTAssertTrue(emptyState.contains("Button(action: onOpenSettings)"))
        XCTAssertTrue(emptyState.contains("Label(\"自定义首页\", systemImage: \"slider.horizontal.3\")"))
        XCTAssertTrue(emptyState.contains(".frame(maxWidth: 620)"))
        XCTAssertTrue(emptyState.contains("AppMotion.resolved("))
        XCTAssertFalse(emptyState.contains("No modules enabled"))
        XCTAssertFalse(emptyState.contains("Open Settings to choose what appears here."))
        XCTAssertTrue(source.contains("IslandEmptyStateActionButtonStyle"))
        XCTAssertTrue(source.contains("reduceMotion: viewModel.reduceMotionEnabled"))
    }
}

final class QuickAppsColumnLayoutTests: XCTestCase {
    func testTwoColumnsAreTheDefaultAndColumnCountKeepsTwoRowsPerPage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let layout = try String(
            contentsOf: root.appendingPathComponent("Views/IslandShellLayout.swift"),
            encoding: .utf8
        )
        let card = try String(
            contentsOf: root.appendingPathComponent("Views/QuickAppsCardView.swift"),
            encoding: .utf8
        )
        let settingsPage = try String(
            contentsOf: root.appendingPathComponent("Views/QuickAppsSettingsView.swift"),
            encoding: .utf8
        )
        let settingsRoot = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("as? Int ?? 2"))
        XCTAssertTrue(settings.contains("case two = 2"))
        XCTAssertTrue(settings.contains("case three = 3"))
        XCTAssertTrue(settings.contains("var pageSize: Int { rawValue * 2 }"))
        XCTAssertTrue(layout.contains("quickAppsColumnCount: settings.quickAppsColumnCount"))
        XCTAssertTrue(card.contains("private var columnCount: Int { settings.quickAppsColumnCount.rawValue }"))
        XCTAssertTrue(card.contains("private var pageSize: Int { settings.quickAppsColumnCount.pageSize }"))
        XCTAssertTrue(card.contains("ZStack(alignment: .leading)"))
        XCTAssertTrue(card.contains(".compositingGroup()"))
        XCTAssertTrue(card.contains(
            ".frame(width: proxy.size.width, height: pageHeight)"
        ))
        XCTAssertTrue(settingsPage.contains("init(settings: IslandSettings)"))
        XCTAssertFalse(settingsPage.contains("@EnvironmentObject private var settings: IslandSettings"))
        XCTAssertTrue(settingsRoot.contains("QuickAppsSettingsView(settings: settings)"))
    }
}

final class NotchGeometryContractTests: XCTestCase {
    func testEmptyCompactStateReturnsToTheMeasuredCameraCapsule() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let islandRoot = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Models/IslandViewModel.swift"),
            encoding: .utf8
        )

        let modeResolver = try XCTUnwrap(
            islandRoot.components(separatedBy: "private func updateCompactCapsuleMode()")
                .dropFirst().first?
                .components(separatedBy: "private func handleForegroundPrompt").first
        )

        XCTAssertTrue(modeResolver.contains("mode = .camera"))
        XCTAssertFalse(modeResolver.contains("else if currentSnapshot.isLive"))
        XCTAssertFalse(modeResolver.contains(
            "settings.lyricsPresentationMode == .desktop {\n            mode = .status"
        ))
        XCTAssertTrue(islandRoot.contains(
            ".onChange(of: settings.showDesktopLyrics) { _, _ in"
        ))
        XCTAssertTrue(islandRoot.contains(
            "refreshRuntimeProviders()\n            updateCompactCapsuleMode()"
        ))
        XCTAssertTrue(islandRoot.contains(
            "let shouldRun = settings.showMusicLyrics\n            && currentSnapshot.isLive"
        ))
        XCTAssertTrue(viewModel.contains(
            "case .camera:\n            size = compactCameraCapsuleSize"
        ))
    }

    func testCompactCameraCapsuleUsesTheMeasuredHardwareGap() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let provider = try String(
            contentsOf: root.appendingPathComponent("Models/NotchGeometryProvider.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: root.appendingPathComponent("Panel/IslandWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(provider.contains("rightArea.minX"))
        XCTAssertTrue(provider.contains("leftArea.maxX"))
        XCTAssertTrue(provider.contains("let notchWidth = rightEdge - leftEdge"))
        XCTAssertTrue(provider.contains("cameraSafeRegionRect(for: screen)?.midX"))
        XCTAssertTrue(provider.contains("backingScaleFactor: screen.backingScaleFactor"))
        XCTAssertTrue(provider.contains(
            "menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY)"
        ))
        XCTAssertTrue(provider.contains("max(safeAreaTopInset, menuBarHeight)"))
        XCTAssertFalse(provider.contains("screen.frame.width - leftArea.width"))
        XCTAssertFalse(tokens.contains("cameraSafeRegionVisualWidthCompensation"))
        XCTAssertTrue(tokens.contains(
            "compactCameraShellHorizontalExtension: CGFloat = 10"
        ))
        XCTAssertTrue(tokens.contains(
            "shellTopEdgeBleedPhysicalPixels: CGFloat = 2"
        ))
        XCTAssertTrue(controller.contains(
            "cameraWidth\n            + IslandDesignTokens.compactCameraShellHorizontalExtension * 2"
        ))
        XCTAssertEqual(
            controller.components(
                separatedBy: "IslandDesignTokens.shellTopEdgeBleedPhysicalPixels / scale"
            ).count - 1,
            2
        )
        XCTAssertTrue(controller.contains(
            "let height = max(1, cameraCapsule.height + topEdgeBleed)"
        ))
        XCTAssertTrue(controller.contains("let displayAlignedHeight = ceil(height * scale) / scale"))
        XCTAssertTrue(controller.contains("CGSize(width: ceil(cameraShellWidth)"))
    }

    func testCompactHoverRestoresTheOriginalRestrainedGeometry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Models/IslandViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(tokens.contains("compactHoverWidthScale: CGFloat = 1.08"))
        XCTAssertTrue(tokens.contains("compactHoverHeightScale: CGFloat = 1.04"))
        XCTAssertTrue(tokens.contains("compactHoverPreviewDuration: TimeInterval = 0.12"))
        XCTAssertTrue(tokens.contains("compactHoverRestoreDuration: TimeInterval = 0.15"))
        XCTAssertFalse(tokens.contains("compactHoverHorizontalExpansion"))
        XCTAssertTrue(viewModel.contains(
            "compactCapsuleScaleX = IslandDesignTokens.compactHoverWidthScale"
        ))
        XCTAssertFalse(viewModel.contains("compactHoverWidthScale("))
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
    func testDebugBuildUsesStableLocalSigningRequirement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: root.appendingPathComponent("NookFlow.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let requirement = try String(
            contentsOf: root.appendingPathComponent("NookFlowDebug.requirements"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("ENABLE_DEBUG_DYLIB = NO;"))
        XCTAssertTrue(project.contains(
            "OTHER_CODE_SIGN_FLAGS = \"--requirements $(PROJECT_DIR)/NookFlowDebug.requirements\";"
        ))
        XCTAssertTrue(requirement.contains(
            "designated => identifier \"com.personal.DynamicNook\""
        ))
    }

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
        XCTAssertTrue(provider.contains("authorizationRequestInFlight"))
        XCTAssertTrue(provider.contains("claimAuthorizationRequest()"))
        XCTAssertTrue(provider.contains("manager.startUpdatingLocation()"))
        XCTAssertTrue(provider.contains("locationTimeoutTimer"))
        XCTAssertTrue(provider.contains("clError.code == .locationUnknown"))
        XCTAssertFalse(provider.contains("manager.requestLocation()"))
    }
}

final class IslandExpansionSmoothnessContractTests: XCTestCase {
    func testOpeningUsesOneContinuousInertialSpringPerAxis() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("case .standard: 1.028"))
        XCTAssertTrue(settings.contains("case .standard: 1.019"))
        XCTAssertTrue(settings.contains("case .standard: 0.91"))
        XCTAssertFalse(settings.contains("undershootScale"))
        XCTAssertFalse(settings.contains("settlingOvershootScale"))

        XCTAssertTrue(tokens.contains(
            "static let shellOpenBalancedDuration: TimeInterval = 0.78"
        ))
        XCTAssertTrue(tokens.contains(
            "static let shellOpenMinimumDuration: TimeInterval = 0.69"
        ))
        XCTAssertTrue(tokens.contains(
            "static let shellOpenMaximumDuration: TimeInterval = 0.87"
        ))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenBalancedDuration: TimeInterval = 0.48"
        ))
        XCTAssertTrue(tokens.contains("shellOpenExpansionRatio: Double = 0.49"))
        XCTAssertTrue(tokens.contains("shellOpenReboundRatio: Double = 0.12"))
        XCTAssertTrue(tokens.contains("shellOpenRecoveryRatio: Double = 0.22"))
        XCTAssertTrue(tokens.contains("shellOpenFinalSettleRatio: Double = 0.17"))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenExpansionRatio: Double = 0.55"
        ))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenFinalSettleRatio: Double = 0.14"
        ))
        XCTAssertTrue(tokens.contains("expansion + rebound + recovery + settle"))
        XCTAssertTrue(tokens.contains(
            "shellOpenBalancedDuration + (setting - 0.59)"
        ))
        XCTAssertTrue(tokens.contains(
            "static let contentLoadingDelay: TimeInterval = 0.08"
        ))
        XCTAssertTrue(tokens.contains(
            "static let cardRevealInterval: TimeInterval = 0.05"
        ))
        XCTAssertTrue(rootView.contains(
            "timing: IslandDesignTokens.fileDropShellOpenTiming("
        ))
        let standardShell = try XCTUnwrap(
            rootView.components(separatedBy: "private func standardAnimatedIslandShell").dropFirst().first?
                .components(separatedBy: "private func fileDropShellSize").first
        )
        XCTAssertTrue(standardShell.contains(
            "timing: IslandDesignTokens.shellOpenTiming(setting: settings.openSpeed)"
        ))
        XCTAssertFalse(standardShell.contains("fileDropShellOpenTiming"))
        let openingAnimator = try XCTUnwrap(
            rootView.components(
                separatedBy: "private struct IslandOpeningKeyframeAnimator"
            ).dropFirst().first?
                .components(separatedBy: "/// A purpose-built drag destination").first
        )
        XCTAssertEqual(
            openingAnimator.components(separatedBy: "SpringKeyframe(").count - 1,
            3
        )
        XCTAssertEqual(
            openingAnimator.components(
                separatedBy: """
                SpringKeyframe(
                                    1,
                                    duration: timing.total
                """
            ).count - 1,
            2
        )
        XCTAssertTrue(tokens.contains(
            "min(0.48, max(0.26, total * 0.56))"
        ))
        XCTAssertTrue(tokens.contains("motionResponse * 0.96"))
        XCTAssertTrue(tokens.contains("expansion + rebound"))
        XCTAssertTrue(openingAnimator.contains(
            "springDampingRatio(\n                forConfiguredOvershoot"
        ))
        XCTAssertTrue(openingAnimator.contains(
            "response: timing.widthMotionResponse"
        ))
        XCTAssertTrue(openingAnimator.contains(
            "response: timing.motionResponse"
        ))
        XCTAssertTrue(openingAnimator.contains(
            "let logarithm = log(min(amplitude, 0.20))"
        ))
        XCTAssertTrue(openingAnimator.contains(
            "sqrt(Double.pi * Double.pi + logarithm * logarithm)"
        ))
        XCTAssertFalse(openingAnimator.contains("widthUndershoot"))
        XCTAssertFalse(openingAnimator.contains("heightUndershoot"))
        XCTAssertFalse(openingAnimator.contains("RecoveryOvershoot"))
        XCTAssertFalse(openingAnimator.contains("endVelocity: 0"))
        XCTAssertFalse(openingAnimator.contains("settleDampingReduction"))
    }

    func testExpandedRuntimeStartsAfterVisualSettlementAndCanBeCancelled() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Models/IslandViewModel.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(viewModel.contains(
            "@Published private(set) var isExpandedRuntimeActive = false"
        ))
        XCTAssertTrue(viewModel.contains("private var runtimeActivationTask: Task<Void, Never>?"))
        XCTAssertTrue(viewModel.contains("runtimeActivationTask?.cancel()"))
        XCTAssertTrue(viewModel.contains("scheduleExpandedRuntimeActivation"))
        XCTAssertTrue(rootView.contains(
            "runtimeIsActive: viewModel.isExpandedRuntimeActive"
        ))
        XCTAssertTrue(rootView.contains(
            "let isExpanded = viewModel.isExpandedRuntimeActive"
        ))
        XCTAssertTrue(expandedView.contains("let runtimeIsActive: Bool"))
        XCTAssertTrue(expandedView.contains(".onChange(of: runtimeIsActive)"))
        XCTAssertFalse(expandedView.contains(
            "if phase == .expanded {\n                    refreshContentProviders(forceTodoSync: true)"
        ))
    }

    func testOpeningRevealBeginsBeforeFinalSettleWithReducedMotionFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Models/IslandViewModel.swift"),
            encoding: .utf8
        )
        let state = try String(
            contentsOf: root.appendingPathComponent("Models/IslandState.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(state.contains("case loadingContent"))
        XCTAssertTrue(viewModel.contains(
            "@Published private(set) var visibleCardCount = 0"
        ))
        XCTAssertTrue(viewModel.contains("private func loadExpandedContent("))
        XCTAssertTrue(viewModel.contains(
            "seconds: reduceMotionEnabled ? 0.02 : IslandDesignTokens.contentLoadingDelay"
        ))
        XCTAssertTrue(viewModel.contains(
            "await Self.sleep(seconds: shellTiming.expansion + shellTiming.rebound)"
        ))
        XCTAssertTrue(viewModel.contains(
            "await Self.sleep(seconds: shellTiming.recovery + shellTiming.settle)"
        ))
        XCTAssertFalse(viewModel.contains("schedulesRuntimeActivation"))
        XCTAssertTrue(viewModel.contains(
            "guard await contentLoaded else { return }\n            self.finishExpandedPresentation"
        ))
        XCTAssertTrue(viewModel.contains("for item in 1...itemCount"))
        XCTAssertTrue(viewModel.contains(
            "await Self.sleep(seconds: IslandDesignTokens.cardRevealInterval)"
        ))
        XCTAssertTrue(viewModel.contains(".smooth(duration: 0.26, extraBounce: 0)"))
        XCTAssertTrue(rootView.contains(
            "struct IslandContentMaterializationModifier: ViewModifier"
        ))
        XCTAssertTrue(rootView.contains(".opacity(isVisible ? 1 : 0.11)"))
        XCTAssertTrue(rootView.contains(
            ".blur(radius: reduceMotion || isVisible ? 0 : 3)"
        ))
        XCTAssertTrue(rootView.contains(
            "reduceMotion || isVisible ? 1 : 0.985"
        ))
        XCTAssertTrue(rootView.contains(
            ".offset(y: reduceMotion || isVisible ? 0 : 4)"
        ))
        XCTAssertTrue(expandedView.contains(
            "isVisible: idx + 1 < viewModel.visibleCardCount"
        ))
        XCTAssertTrue(rootView.contains(
            "@StateObject private var applicationsProvider = ApplicationsProvider()"
        ))
        XCTAssertTrue(rootView.contains(
            "@StateObject private var fileProvider = FileDataProvider()"
        ))
        XCTAssertTrue(expandedView.contains(
            "@ObservedObject var applicationsProvider: ApplicationsProvider"
        ))
        XCTAssertTrue(expandedView.contains(
            "@ObservedObject var fileProvider: FileDataProvider"
        ))
        XCTAssertFalse(expandedView.contains(
            "@StateObject private var applicationsProvider"
        ))
        XCTAssertFalse(expandedView.contains(
            "@StateObject private var fileProvider"
        ))
        XCTAssertFalse(expandedView.contains("TimelineView(.animation)"))
        XCTAssertFalse(expandedView.contains(".id(loadToken)"))
        XCTAssertFalse(expandedView.contains(".id(isExpanded)"))
    }
}

final class IslandAnimationPaceContractTests: XCTestCase {
    func testPacePresetsUseModeratedValuesAndBalancedDefaults() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = try String(
            contentsOf: root.appendingPathComponent("Views/GeneralSettingsView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let tokens = try String(
            contentsOf: root.appendingPathComponent("Views/IslandDesignTokens.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsView.contains("case .slow: 0.68"))
        XCTAssertTrue(settingsView.contains("case .balanced: 0.59"))
        XCTAssertTrue(settingsView.contains("case .fast: 0.50"))
        XCTAssertFalse(settingsView.contains("case .fast: 0.36"))
        XCTAssertTrue(settingsView.contains("if settings.openSpeed >= 0.635"))
        XCTAssertTrue(settingsView.contains("if settings.openSpeed <= 0.545"))
        XCTAssertTrue(tokens.contains("shellCloseMinimumDuration: TimeInterval = 0.25"))
        XCTAssertTrue(tokens.contains("shellCloseMaximumDuration: TimeInterval = 0.63"))
        XCTAssertTrue(tokens.contains("shellOpenBalancedDuration: TimeInterval = 0.78"))
        XCTAssertTrue(tokens.contains("shellOpenMinimumDuration: TimeInterval = 0.69"))
        XCTAssertTrue(tokens.contains("shellOpenMaximumDuration: TimeInterval = 0.87"))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenBalancedDuration: TimeInterval = 0.48"
        ))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenMinimumDuration: TimeInterval = 0.39"
        ))
        XCTAssertTrue(tokens.contains(
            "fileDropShellOpenMaximumDuration: TimeInterval = 0.57"
        ))

        XCTAssertEqual(settings.components(separatedBy: "?? 0.59").count - 1, 2)
        XCTAssertEqual(settings.components(separatedBy: "openSpeed = 0.59").count - 1, 1)
        XCTAssertEqual(settings.components(separatedBy: "closeSpeed = 0.59").count - 1, 1)
        XCTAssertTrue(settings.contains("private static func migratedAnimationSpeed"))
        XCTAssertTrue(settings.contains("abs(value - 0.36) < 0.0001 ? 0.50 : value"))
        XCTAssertTrue(settings.contains("openSpeed = Self.migratedAnimationSpeed(storedOpenSpeed)"))
        XCTAssertTrue(settings.contains("closeSpeed = Self.migratedAnimationSpeed(storedCloseSpeed)"))
    }
}

final class ForegroundPromptDurationContractTests: XCTestCase {
    func testPromptDurationIsLimitedToHalfThroughTwoSecondsEverywhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = try String(
            contentsOf: root.appendingPathComponent("Views/GeneralSettingsView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let islandRoot = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsView.contains("in: 0.5...2.0"))
        XCTAssertTrue(settings.contains(
            "let clampedValue = min(max(foregroundHoldDuration, 0.5), 2.0)"
        ))
        XCTAssertTrue(settings.contains(
            "foregroundHoldDuration = min(max(savedForegroundHoldDuration, 0.5), 2.0)"
        ))
        XCTAssertTrue(islandRoot.contains(
            "let delay = min(max(settings.foregroundHoldDuration, 0.5), 2.0)"
        ))
    }
}

final class ReminderEventKitQueryContractTests: XCTestCase {
    func testReminderQueriesReuseOneStoreAndAvoidDuplicateIslandFetches() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let provider = try String(
            contentsOf: root.appendingPathComponent("Models/ReminderProvider.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )

        XCTAssertEqual(provider.components(separatedBy: "EKEventStore()").count - 1, 1)
        XCTAssertTrue(provider.contains("private static let sharedStore = EKEventStore()"))
        XCTAssertTrue(provider.contains("private var store: EKEventStore { Self.sharedStore }"))
        XCTAssertTrue(provider.contains("let calendars = store.calendars(for: .reminder)"))
        XCTAssertTrue(provider.contains("store.predicateForReminders(in: calendars)"))

        let syncSection = try XCTUnwrap(
            provider.components(separatedBy: "private func makeTodoTasksFromReminders").dropFirst().first?
                .components(separatedBy: "private func fetchAllReminders").first
        )
        XCTAssertTrue(syncSection.contains("let reminders = await fetchAllReminders()"))
        XCTAssertTrue(syncSection.contains("includeCompleted ? reminders : reminders.filter"))
        XCTAssertFalse(syncSection.contains("predicateForIncompleteReminders"))
        XCTAssertFalse(syncSection.contains("predicateForCompletedReminders"))

        let refreshSection = try XCTUnwrap(
            expandedView.components(separatedBy: "private func refreshContentProviders").dropFirst().first?
                .components(separatedBy: "private func stopContentProviders").first
        )
        XCTAssertFalse(refreshSection.contains("reminderProvider.start()"))
        XCTAssertTrue(provider.contains("createReminder(request: request, refreshSnapshot: false)"))
        XCTAssertTrue(provider.contains("updateReminderCompletion(identifier: identifier, isCompleted: true, refreshSnapshot: false)"))
        XCTAssertTrue(provider.contains("updateReminderCompletion(identifier: identifier, isCompleted: false, refreshSnapshot: false)"))
        XCTAssertTrue(provider.contains("removeReminder(identifier: identifier, refreshSnapshot: false)"))
    }
}

final class TutorialHintRemovalContractTests: XCTestCase {
    func testTutorialHintFeatureIsCompletelyRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let generalSettings = try String(
            contentsOf: root.appendingPathComponent("Views/GeneralSettingsView.swift"),
            encoding: .utf8
        )
        let islandRoot = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        for source in [settings, generalSettings, islandRoot] {
            XCTAssertFalse(source.contains("TutorialHint"))
            XCTAssertFalse(source.contains("tutorialHint"))
            XCTAssertFalse(source.contains("教学引导提示"))
        }
        XCTAssertFalse(settings.contains("hasShownTutorialHint"))
        XCTAssertFalse(islandRoot.contains("功能提示"))
    }
}

final class FileDropChooserLayoutContractTests: XCTestCase {
    func testChooserUsesCompactGeometryAndCurrentIslandShape() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let state = try String(
            contentsOf: root.appendingPathComponent("Models/IslandState.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(state.contains("CGSize(width: 560, height: 176)"))
        XCTAssertTrue(state.contains("horizontalPadding: CGFloat = 26"))
        XCTAssertTrue(state.contains("spacing: CGFloat = 12"))
        XCTAssertTrue(state.contains("destinationHeight: CGFloat = 92"))
        XCTAssertTrue(state.contains("destinationsTopInset: CGFloat = 42"))
        XCTAssertTrue(state.contains("compactActivationHorizontalPadding: CGFloat = 12"))
        XCTAssertTrue(state.contains("compactActivationBottomPadding: CGFloat = 24"))
        XCTAssertTrue(state.contains("transientExitGraceDuration: TimeInterval = 0.60"))
        XCTAssertTrue(state.contains("topBarLeadingPadding: CGFloat = 0"))
        XCTAssertTrue(state.contains("topBarTrailingPadding: CGFloat = 18"))
        XCTAssertTrue(state.contains("dragPreviewSafeTopInset: CGFloat = 46"))
        XCTAssertTrue(state.contains("static var windowSize: CGSize"))
        XCTAssertTrue(state.contains("static func openingCanvasSize("))
        XCTAssertTrue(rootView.contains("IslandShellLayout.shellShapeMetrics("))
        XCTAssertTrue(rootView.contains("let shellShape = DynamicIslandShape("))
        XCTAssertTrue(rootView.contains(
            "let windowCanvasSize = IslandFileDropLayout.windowSize(for: canvasSize)"
        ))
        XCTAssertFalse(rootView.contains("windowSize(for: shellSize)"))
        XCTAssertTrue(rootView.contains("private struct FileDropShellSurface: View"))
        XCTAssertTrue(rootView.contains(
            "private struct FileDropChooserContentSurface: View"
        ))
        XCTAssertTrue(rootView.contains(".clipShape(shellShape)"))
        XCTAssertTrue(rootView.contains("ForEach(IslandTopTab.allCases)"))
        XCTAssertTrue(rootView.contains("PinButton(isPinned: isPinned"))
        XCTAssertTrue(rootView.contains(
            "size: target == .staging ? 27 : 25"
        ))
        XCTAssertTrue(rootView.contains(
            "size: 16, weight: .bold, design: .rounded"
        ))
        XCTAssertFalse(rootView.contains(".clipShape(RoundedRectangle(cornerRadius: 38"))
    }
}

final class FileDropExclusivePresentationContractTests: XCTestCase {
    func testInternalAndExternalDragsKeepTheChooserExclusive() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let filesView = try String(
            contentsOf: root.appendingPathComponent("Views/FilesGridView.swift"),
            encoding: .utf8
        )
        let expandedView = try String(
            contentsOf: root.appendingPathComponent("Views/ExpandedIslandView.swift"),
            encoding: .utf8
        )
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let viewModel = try String(
            contentsOf: root.appendingPathComponent("Models/IslandViewModel.swift"),
            encoding: .utf8
        )
        let controller = try String(
            contentsOf: root.appendingPathComponent("Panel/IslandWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(filesView.contains("onDragStateChanged?(true, file.name)"))
        XCTAssertTrue(filesView.contains("onDragStateChanged?(false, nil)"))
        XCTAssertTrue(expandedView.contains("onExternalDragStateChanged: { isDragging, fileName in"))
        XCTAssertTrue(expandedView.contains("viewModel.beginFileDrop(previewName: fileName)"))
        XCTAssertTrue(expandedView.contains("viewModel.finishFileDropInteraction()"))
        XCTAssertTrue(viewModel.contains("if isFileDropChooserVisible {"))
        XCTAssertTrue(viewModel.contains("resumeFileDropChooser()"))
        XCTAssertTrue(viewModel.contains("shouldMountExpandedContent = false"))
        XCTAssertFalse(viewModel.contains("fileDropReturnsToExpandedIsland"))
        let beginFileDrop = try XCTUnwrap(
            viewModel.components(separatedBy: "func beginFileDrop").dropFirst().first?
                .components(separatedBy: "func updateFileDropTarget").first
        )
        XCTAssertFalse(beginFileDrop.contains("beginShellExpansion("))
        XCTAssertFalse(beginFileDrop.contains("expandedContentHideDuration"))
        XCTAssertTrue(beginFileDrop.contains("fileDropOpeningSourceSize = sourceSize"))
        XCTAssertTrue(beginFileDrop.contains(
            "width: compactCapsuleSize.width * compactCapsuleScaleX"
        ))
        XCTAssertTrue(beginFileDrop.contains(
            "fileDropShellCanvasSize = IslandFileDropLayout.openingCanvasSize("
        ))
        XCTAssertTrue(beginFileDrop.contains(
            "IslandDesignTokens.fileDropShellOpenDuration("
        ))
        XCTAssertTrue(beginFileDrop.contains("fileDropOpeningAnimationTrigger &+= 1"))
        XCTAssertTrue(beginFileDrop.contains("fileDropShellSize = IslandFileDropLayout.size"))
        XCTAssertTrue(beginFileDrop.contains("fileDropVisibleItemCount = 0"))
        XCTAssertTrue(beginFileDrop.contains("private func loadFileDropContent("))
        XCTAssertTrue(beginFileDrop.contains("let itemCount = 3"))
        let shellSettlement = try XCTUnwrap(
            beginFileDrop.range(of: "await Self.sleep(seconds: shellDuration)")
        )
        let contentReveal = try XCTUnwrap(
            beginFileDrop.range(of: "fileDropContentOpacity = 1")
        )
        XCTAssertLessThan(shellSettlement.lowerBound, contentReveal.lowerBound)
        let chooserOwnership = try XCTUnwrap(
            beginFileDrop.range(of: "isFileDropChooserVisible = true")
        )
        let phaseChange = try XCTUnwrap(
            beginFileDrop.range(of: "presentationPhase = .expanded")
        )
        let transitionTask = try XCTUnwrap(
            beginFileDrop.range(of: "fileDropTransitionTask = Task")
        )
        XCTAssertLessThan(chooserOwnership.lowerBound, phaseChange.lowerBound)
        XCTAssertLessThan(chooserOwnership.lowerBound, transitionTask.lowerBound)
        XCTAssertTrue(beginFileDrop.contains("cancelCapsuleHoverForFileDrop()"))
        XCTAssertTrue(beginFileDrop.contains(
            "presentationPhase == .expanded || presentationPhase == .loadingContent"
        ))
        XCTAssertFalse(beginFileDrop.contains("mode == .expanded"))
        XCTAssertTrue(rootView.contains("? viewModel.fileDropSourceShellOpacity"))
        XCTAssertTrue(rootView.contains(
            "rendersShellChrome: !viewModel.isFileDropChooserVisible"
        ))
        XCTAssertTrue(rootView.contains(
            "shape.fill(rendersShellChrome ? shellFillColor : Color.clear)"
        ))
        XCTAssertTrue(rootView.contains(
            ".opacity(viewModel.isFileDropChooserVisible ? 1 : 0)"
        ))
        XCTAssertTrue(rootView.contains(
            "trigger: viewModel.fileDropOpeningAnimationTrigger"
        ))
        let chooserAnimation = try XCTUnwrap(
            rootView.components(separatedBy: "private var animatedFileDropChooserSurface").dropFirst().first?
                .components(separatedBy: "private func standardAnimatedIslandShell").first
        )
        XCTAssertTrue(chooserAnimation.contains("FileDropShellSurface("))
        XCTAssertTrue(chooserAnimation.contains("FileDropChooserContentSurface("))
        XCTAssertTrue(chooserAnimation.contains(
            "visibleItemCount: viewModel.fileDropVisibleItemCount"
        ))
        let animatedShellClosure = try XCTUnwrap(
            chooserAnimation.components(separatedBy: ") { keyframeState in").dropFirst().first?
                .components(separatedBy: "FileDropChooserContentSurface(").first
        )
        XCTAssertFalse(animatedShellClosure.contains("contentOpacity:"))
        XCTAssertFalse(animatedShellClosure.contains("ForEach(IslandTopTab.allCases)"))
        XCTAssertTrue(rootView.contains(
            "private struct IslandOpeningKeyframeAnimator<Content: View>: View"
        ))
        XCTAssertTrue(rootView.contains(
            "width: IslandFileDropLayout.size.width"
        ))
        XCTAssertFalse(rootView.contains(
            "if viewModel.isFileDropChooserVisible {\n                FileDropChooserSurface("
        ))
        XCTAssertTrue(rootView.contains(
            ".padding(.leading, IslandFileDropLayout.topBarLeadingPadding)"
        ))
        XCTAssertTrue(rootView.contains(
            ".padding(.trailing, IslandFileDropLayout.topBarTrailingPadding)"
        ))
        let finishInteraction = try XCTUnwrap(
            viewModel.components(separatedBy: "func finishFileDropInteraction").dropFirst().first?
                .components(separatedBy: "private func restoreIslandFromFileDrop").first
        )
        XCTAssertTrue(finishInteraction.contains("guard !isPinned else { return }"))
        XCTAssertTrue(finishInteraction.contains("dismissFileDropChooser()"))
        XCTAssertTrue(finishInteraction.contains("pendingFileDropDismissal = true"))
        XCTAssertTrue(finishInteraction.contains("isFileDropChooserVisible = false"))
        XCTAssertTrue(finishInteraction.contains("fileDropShellSize = self.compactCapsuleSize"))
        XCTAssertTrue(finishInteraction.contains("fileDropShellMorphProgress = 0"))
        XCTAssertTrue(finishInteraction.contains("fileDropHoverTarget = nil"))
        XCTAssertTrue(viewModel.contains("if isFileDropChooserVisible {\n            restoreIslandFromFileDrop(to: tab)"))
        XCTAssertTrue(viewModel.contains("fileDropRestorationTarget = tab"))
        XCTAssertTrue(viewModel.contains("fileDropShellSize = targetSize"))
        let resumeFileDrop = try XCTUnwrap(
            viewModel.components(separatedBy: "private func resumeFileDropChooser").dropFirst().first?
                .components(separatedBy: "private func restoreIslandFromFileDrop").first
        )
        XCTAssertTrue(resumeFileDrop.contains(
            "self.fileDropShellSize = IslandFileDropLayout.size"
        ))
        XCTAssertFalse(resumeFileDrop.contains("fileDropOpeningAnimationTrigger &+= 1"))
        XCTAssertTrue(viewModel.contains(
            "guard !isFileDropChooserVisible, !isPinned else { return }"
        ))
        XCTAssertTrue(controller.contains("viewModel.$isFileDropChooserVisible"))
        XCTAssertTrue(controller.contains("self.setPanelFrameForFileDropChooser(display: false)"))
        XCTAssertTrue(controller.contains("layoutImmediately: false"))
        XCTAssertTrue(controller.contains("let fileDropCanvas = IslandFileDropLayout.openingCanvasSize("))
        XCTAssertTrue(controller.contains(
            "let fileDropEnvelope = IslandFileDropLayout.windowSize(for: fileDropCanvas)"
        ))
        XCTAssertTrue(controller.contains(
            "for: viewModel.fileDropShellCanvasSize"
        ))
        XCTAssertFalse(controller.contains("fileDropPanelFrameSettlementTask"))
        let pointerMonitors = try XCTUnwrap(
            controller.components(separatedBy: "private func installPointerMonitors").dropFirst().first?
                .components(separatedBy: "private func removePointerMonitors").first
        )
        XCTAssertTrue(pointerMonitors.contains("matching: [.mouseMoved]"))
        XCTAssertFalse(pointerMonitors.contains(".leftMouseDragged"))
        XCTAssertFalse(pointerMonitors.contains(".rightMouseDragged"))
        XCTAssertTrue(controller.contains("trackingView.shouldActivateFileDrop"))
        XCTAssertTrue(controller.contains("self.fileDropActivationRect.contains(screenPoint)"))
        XCTAssertTrue(controller.contains("trackingView.shouldRetainFileDropAfterExit"))
        XCTAssertTrue(controller.contains(
            "self?.fileDropActivationRect.contains(screenPoint) == true"
        ))
        XCTAssertTrue(controller.contains("private var fileDropActivationRect: NSRect"))
        XCTAssertTrue(controller.contains(
            "IslandFileDropLayout.compactActivationBottomPadding"
        ))
        XCTAssertTrue(controller.contains("viewModel.$fileDropRestorationTarget"))
        XCTAssertTrue(controller.contains("preparePanelFrameForFileDropRestoration(to: tab)"))
        XCTAssertTrue(controller.contains("!self.viewModel.isFileDropChooserVisible"))
        XCTAssertTrue(controller.contains("requiresFreshNotchHoverAfterFileDrop"))
        XCTAssertTrue(controller.contains("shouldSuppressHoverAfterFileDrop(at:"))
        XCTAssertTrue(controller.contains("allowsRelease: true"))
        XCTAssertTrue(controller.contains("handleCameraAreaHoverChanged(isHovering)"))
        XCTAssertTrue(controller.contains(
            "shellRect.width >= IslandFileDropLayout.size.width"
        ))
        XCTAssertTrue(controller.contains(
            "shellRect.height >= IslandFileDropLayout.size.height"
        ))
        XCTAssertTrue(controller.contains(
            "let shellRect = visualShellRect(for: IslandFileDropLayout.size)"
        ))
        XCTAssertTrue(controller.contains("fileDropExitWorkItem"))
        XCTAssertTrue(controller.contains("scheduleFileDropExit()"))
        XCTAssertTrue(controller.contains(
            "shouldRetainFileDropAfterExit?(exitPoint) == true"
        ))
        XCTAssertTrue(controller.contains(
            "onFileDragChanged?(true, nil, activeExternalDragPreviewName)"
        ))
        XCTAssertTrue(controller.contains("private func draggingScreenPoint("))
        XCTAssertTrue(controller.contains(
            "deadline: .now() + IslandFileDropLayout.transientExitGraceDuration"
        ))
        XCTAssertTrue(controller.contains("override func draggingEnded("))
        XCTAssertTrue(controller.contains("override func updateDraggingItemsForDrag("))
        XCTAssertTrue(controller.contains(
            "bounds.maxY - IslandFileDropLayout.dragPreviewSafeTopInset"
        ))
        XCTAssertTrue(controller.contains("draggingItem.draggingFrame = frame"))
        XCTAssertTrue(controller.contains("activeExternalDragSequenceNumber"))
        XCTAssertTrue(controller.contains("private func externalFileDragPayload("))
        XCTAssertTrue(controller.contains(
            "if activeExternalDragSequenceNumber == sequenceNumber"
        ))
        XCTAssertTrue(controller.contains("onExternalFileDragSessionChanged?(true)"))
        XCTAssertTrue(controller.contains(
            "private func finishExternalFileDragSession("
        ))
        XCTAssertTrue(controller.contains(
            "guard !isFileDropActive, NSEvent.pressedMouseButtons == 0"
        ))
        XCTAssertTrue(controller.contains(
            "private var isExternalFileDragSessionActive = false"
        ))
        XCTAssertTrue(controller.contains("private var workspaceVisibilitySettlementTask"))
        XCTAssertTrue(controller.contains(
            "selector: #selector(activeSpaceDidChange)"
        ))
        XCTAssertTrue(controller.contains(
            "selector: #selector(activeApplicationDidChange)"
        ))
        XCTAssertTrue(controller.contains("guard !isExternalFileDragSessionActive,"))
        XCTAssertTrue(controller.contains(
            "schedulePanelVisibilityReconciliation(delay: 0.28)"
        ))
        XCTAssertTrue(controller.contains(
            "schedulePanelVisibilityReconciliation(delay: 0.10)"
        ))
        let panelVisibility = try XCTUnwrap(
            controller.components(separatedBy: "private func applyPanelVisibility").dropFirst().first?
                .components(separatedBy: "private func applyPanelCollectionBehavior").first
        )
        XCTAssertTrue(panelVisibility.contains(
            "if isExternalFileDragSessionActive || viewModel.isFileDropChooserVisible {"
        ))
        XCTAssertTrue(panelVisibility.contains(
            "if !panel.isVisible || !panel.isOnActiveSpace"
        ))
        XCTAssertLessThan(
            try XCTUnwrap(panelVisibility.range(
                of: "if isExternalFileDragSessionActive || viewModel.isFileDropChooserVisible {"
            )?.lowerBound),
            try XCTUnwrap(panelVisibility.range(
                of: "if settings.hideInFullscreen, isFullscreenAppActive()"
            )?.lowerBound)
        )
        let collectionBehavior = try XCTUnwrap(
            controller.components(separatedBy: "private func applyPanelCollectionBehavior").dropFirst().first?
                .components(separatedBy: "private func isFullscreenAppActive").first
        )
        XCTAssertTrue(collectionBehavior.contains(
            "if panel.collectionBehavior != behavior"
        ))
        let fileDropUpdate = try XCTUnwrap(
            controller.components(separatedBy: "private func updateFileDrop").dropFirst().first?
                .components(separatedBy: "private func scheduleFileDropExit").first
        )
        let internalDragGuard = try XCTUnwrap(
            fileDropUpdate.components(separatedBy: "guard !isInternalFileDrag(sender) else").dropFirst().first?
                .components(separatedBy: "}").first
        )
        XCTAssertLessThan(
            try XCTUnwrap(fileDropUpdate.range(of: "cancelPendingFileDropExit()")?.lowerBound),
            try XCTUnwrap(fileDropUpdate.range(of: "guard !isInternalFileDrag(sender) else")?.lowerBound)
        )
        XCTAssertFalse(internalDragGuard.contains("onFileDragChanged?(false"))
    }
}

final class ExternalPinButtonAnchorContractTests: XCTestCase {
    func testPinButtonUsesFinalContentAnchorDuringShellBounce() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootView = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )
        let windowController = try String(
            contentsOf: root.appendingPathComponent("Panel/IslandWindowController.swift"),
            encoding: .utf8
        )

        let overlay = try XCTUnwrap(
            rootView.components(separatedBy: "private func externalPinButtonOverlay").dropFirst().first?
                .components(separatedBy: "private var sideStatusContext").first
        )
        XCTAssertTrue(overlay.contains("let anchorSize = IslandShellLayout.contentSize("))
        XCTAssertTrue(overlay.contains("canvasSize.width / 2"))
        XCTAssertTrue(overlay.contains("anchorSize.width / 2"))
        XCTAssertTrue(overlay.contains("y: anchorSize.height"))
        XCTAssertFalse(overlay.contains("x: 20 + canvasSize.width -"))

        let hitTesting = try XCTUnwrap(
            windowController.components(separatedBy: "private func interactiveShellRect").dropFirst().first?
                .components(separatedBy: "private func externalPinButtonHitRect").first
        )
        XCTAssertTrue(hitTesting.contains("let pinAnchorSize = IslandShellLayout.contentSize("))
        XCTAssertTrue(hitTesting.contains("let pinAnchorRect = visualShellRect(for: pinAnchorSize)"))
        XCTAssertTrue(hitTesting.contains("externalPinButtonHitRect(attachedTo: pinAnchorRect)"))
    }
}

private final class DelayedLyricsNetwork: LyricsNetworking {
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

private final class DelayedNotFoundLyricsNetwork: LyricsNetworking {
    func searchAndFetchLyrics(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> LyricsFetchResult {
        try? await Task.sleep(for: .milliseconds(50))
        return .notFound
    }
}

private actor MemoryLyricsCache: LyricsCaching {
    private var values: [String: [LyricLine]] = [:]

    nonisolated func cacheKey(
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

final class MirrorCardContractTests: XCTestCase {
    func testMirrorIsOptionalAndOnlyRunsWhileExpandedContentIsActive() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try source("Models/IslandSettings.swift", root: root)
        let layout = try source("Views/IslandShellLayout.swift", root: root)
        let expanded = try source("Views/ExpandedIslandView.swift", root: root)
        let card = try source("Views/MirrorCardView.swift", root: root)

        XCTAssertTrue(settings.contains(
            "showMirrorModule = defaults.object(forKey: Keys.showMirrorModule) as? Bool ?? false"
        ))
        XCTAssertTrue(layout.contains("case .mirror:     settings.showMirrorModule"))
        XCTAssertTrue(expanded.contains(
            "MirrorCardView(isActive: isContentReady && runtimeIsActive)"
        ))
        XCTAssertTrue(card.contains("AVCaptureDevice.requestAccess(for: .video)"))
        XCTAssertTrue(card.contains("session.startRunning()"))
        XCTAssertTrue(card.contains("session.stopRunning()"))
        XCTAssertTrue(card.contains("@State private var isCameraEnabled = false"))
        XCTAssertTrue(card.contains("Button(action: toggleCamera)"))
        XCTAssertTrue(card.contains("isCameraEnabled ? deactivateCamera() : activateCamera()"))
        XCTAssertTrue(card.contains("if isActive, isCameraEnabled"))
        XCTAssertTrue(card.contains(".onDisappear { deactivateCamera() }"))
        XCTAssertTrue(card.contains("private var latestRequestID: UInt64 = 0"))
        XCTAssertTrue(card.contains("guard isCurrentRequest(requestID) else { return }"))
        XCTAssertTrue(card.contains("private var operationGeneration: UInt64 = 0"))
        XCTAssertTrue(card.contains("self.operationGeneration == generation"))
        XCTAssertTrue(card.contains("@Published private(set) var previewGeneration: UInt64 = 0"))
        XCTAssertTrue(card.contains("previewGeneration &+= 1"))
        XCTAssertTrue(card.contains("AVCaptureVideoDataOutputSampleBufferDelegate"))
        XCTAssertTrue(card.contains("videoOutput.setSampleBufferDelegate(nil, queue: nil)"))
        XCTAssertTrue(card.contains("videoOutput.connection(with: .video)?.isEnabled = false"))
        XCTAssertTrue(card.contains("self.isPreviewReady = true"))
        XCTAssertTrue(card.contains("static func dismantleNSView"))
        XCTAssertTrue(card.contains("previewLayer.session = nil"))
        XCTAssertTrue(card.contains("Text(\"正在连接画面\")"))
        let stablePreviewSurface = try XCTUnwrap(
            card.components(separatedBy: "private var previewSurface").dropFirst().first?
                .components(separatedBy: "private var previewContent").first
        )
        XCTAssertTrue(stablePreviewSurface.contains("MirrorCameraPreview("))
        XCTAssertTrue(card.contains("Text(\"点击开启镜子\")"))
        XCTAssertTrue(card.contains(".padding(10)"))
        XCTAssertTrue(card.contains("NSWorkspace.willSleepNotification"))
        XCTAssertTrue(card.contains("NSWorkspace.didWakeNotification"))
        XCTAssertTrue(card.contains("connection.isVideoMirrored = true"))
        XCTAssertTrue(card.contains("实时镜像 · 不会保存"))
        XCTAssertFalse(card.contains("Timer("))
        XCTAssertFalse(card.contains("TimelineView"))
    }

    func testTopBarActionsStayInsideTheVisibleDisplayWidth() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expanded = try source("Views/ExpandedIslandView.swift", root: root)

        XCTAssertTrue(expanded.contains(".frame(width: visibleTopBarWidth)"))
        XCTAssertTrue(expanded.contains("screenWidth - 72"))
        XCTAssertTrue(expanded.contains("settingsButton\n                .offset(x: -10)\n                .zIndex(1)"))
    }

    func testMirrorSettingsPreviewDoesNotOpenTheCamera() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = try source("Views/SettingsRootView.swift", root: root)
        let project = try source("NookFlow.xcodeproj/project.pbxproj", root: root)

        XCTAssertTrue(settingsView.contains(
            "[.mirror, .imageCard, .todo, .deviceInfo, .weather, .music, .quickApps, .shortcuts]"
        ))
        XCTAssertTrue(settingsView.contains("case .mirror:\n                previewMirrorThumbnail"))
        XCTAssertFalse(settingsView.contains("MirrorCardView(isActive:"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSCameraUsageDescription"))
        XCTAssertTrue(settingsView.contains("IslandShellLayout.contentSize("))
        XCTAssertTrue(settingsView.contains("IslandShellLayout.visibleModules(settings: settings)"))
        XCTAssertTrue(settingsView.contains("IslandShellLayout.moduleFixedWidth("))
        XCTAssertTrue(settingsView.contains("case .todo:\n                previewTodoThumbnail"))
        XCTAssertFalse(settingsView.contains("&& $0 != .todo"))
    }

    private func source(_ path: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

final class SettingsIslandPreviewContractTests: XCTestCase {
    func testHomeWidgetCardsAreBuiltImmediatelyInsteadOfLazily() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )
        let widgetsSection = try XCTUnwrap(
            source.components(separatedBy: "private var widgetsCard").dropFirst().first?
                .components(separatedBy: "private var homeWidgets").first
        )

        XCTAssertTrue(widgetsSection.contains("HStack(alignment: .top, spacing: AppSpacing.md)"))
        XCTAssertFalse(widgetsSection.contains("LazyHStack"))
    }

    func testExpandedPreviewScalesTheFinishedLayoutAsOneComputerSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Views/SettingsRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".frame(height: 254)"))
        XCTAssertTrue(source.contains("cameraStripPreview(width: previewWidth, height: computerHeight)"))
        XCTAssertTrue(source.contains("let previewWidth = max(320, proxy.size.width - 12)"))
        XCTAssertTrue(source.contains("let screenHorizontalInset = max(18, previewWidth * (74 / 1972))"))
        XCTAssertTrue(source.contains("let screenWidth = max(280, previewWidth - (screenHorizontalInset * 2))"))
        XCTAssertTrue(source.contains("let expandedScale = min(\n                1,\n                min("))
        XCTAssertTrue(source.contains(".aspectRatio(contentMode: .fill)"))
        XCTAssertTrue(source.contains("computerScreenGlassOverlay("))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains("previewExpandedContent(\n                width: actualSize.width"))
        XCTAssertTrue(source.contains(".scaleEffect(expandedScale, anchor: .topLeading)"))
        XCTAssertTrue(source.contains(".compositingGroup()"))
        XCTAssertTrue(source.contains("Capsule(style: .continuous)"))
    }
}
