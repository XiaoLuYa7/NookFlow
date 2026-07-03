import AppKit
import Combine
import CoreGraphics
import Foundation
import Network

@MainActor
final class NotificationCoordinator {
    static let shared = NotificationCoordinator()

    private let weatherProvider = WeatherProvider()
    private let batteryProvider = BatteryProvider()
    private let deviceInfoProvider = DeviceInfoProvider()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.personal.DynamicNook.notification-network")
    private let defaults = UserDefaults.standard

    private var isStarted = false
    private var runtimeTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var weatherCancellable: AnyCancellable?
    private var lastWeatherRefresh = Date.distantPast
    private var lastRuntimeCheck = Date()
    private var lastDeviceCheck = Date.distantPast
    private var lastNetworkStatus: NWPath.Status?
    private var lastSentDates: [String: Date] = [:]
    private var lastScheduleKeys = Set<String>()
    private var sittingActiveDuration: TimeInterval = 0
    private var highUsageSampleCount = 0
    private var wasLowBattery = false
    private var wasNearlyCharged = false
    private var wasLowStorage = false

    private static let waterProgressDayKey = "notifications.waterProgressDay"

    private init() {}

    deinit {
        runtimeTask?.cancel()
        applyTask?.cancel()
        networkMonitor.cancel()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        weatherCancellable = weatherProvider.$snapshot
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    await self?.evaluateWeather(snapshot)
                }
            }

        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handleNetworkStatus(path.status)
            }
        }
        networkMonitor.start(queue: networkQueue)

        runtimeTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.runRuntimeChecks()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        preferencesDidChange(requestAuthorization: false)
    }

    func preferencesDidChange(requestAuthorization _: Bool) {
        if !isStarted {
            start()
        }

        applyTask?.cancel()
        applyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            if NotificationSettingsViewModel.shared.weather.isEnabled {
                weatherProvider.start()
            }
        }
    }

    func sendPreviewNotification() async -> Bool {
        InAppNotificationWindowController.shared.show(
            InAppNotificationPayload(
                title: "天气提醒",
                message: "一小时内可能下雨，出门记得带伞。",
                kind: .weather
            )
        )
        return true
    }

    private func runRuntimeChecks() async {
        resetWaterProgressIfNeeded()

        let now = Date()
        let elapsed = min(max(now.timeIntervalSince(lastRuntimeCheck), 0), 60)
        lastRuntimeCheck = now
        let preferences = NotificationSettingsViewModel.shared

        await evaluateDailySchedule(preferences.dailyCare, now: now)
        await evaluateSittingReminder(preferences.dailyCare, now: now, elapsed: elapsed)

        if preferences.device.isEnabled,
           now.timeIntervalSince(lastDeviceCheck) >= 60 {
            lastDeviceCheck = now
            batteryProvider.refresh()
            deviceInfoProvider.refresh()
            await evaluateDeviceStatus(
                preferences.device,
                battery: batteryProvider.snapshot,
                device: deviceInfoProvider.snapshot
            )
        } else if !preferences.device.isEnabled {
            highUsageSampleCount = 0
            wasLowBattery = false
            wasNearlyCharged = false
            wasLowStorage = false
        }

        if preferences.weather.isEnabled {
            let interval = TimeInterval(max(30, parseMinutes(preferences.weather.checkFrequency)) * 60)
            if now.timeIntervalSince(lastWeatherRefresh) >= interval {
                lastWeatherRefresh = now
                weatherProvider.refresh()
            }
        }
    }

    private func evaluateDailySchedule(
        _ preferences: DailyCareNotificationSettings,
        now: Date
    ) async {
        guard preferences.isEnabled else { return }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let dayKey = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        lastScheduleKeys = lastScheduleKeys.filter { $0.hasPrefix(dayKey) }

        if preferences.waterReminderEnabled,
           preferences.waterProgress < parseCount(preferences.waterGoal) {
            let interval = max(15, parseMinutes(preferences.waterInterval))
            let times = reminderTimes(
                start: preferences.waterStartTime,
                end: preferences.waterEndTime,
                interval: interval
            )
            if times.contains(currentMinute) {
                await fireScheduledOnce(
                    key: "\(dayKey).water.\(currentMinute)",
                    identifier: "lnook.daily.water",
                    title: "该喝水了",
                    body: "起来活动一下，顺便喝一杯水。"
                )
            }
        }

        guard preferences.sleepReminderEnabled else { return }
        let weekday = components.weekday ?? 1
        let events = sleepEvents(preferences)
        for event in events where event.weekday == weekday && event.minute == currentMinute {
            await fireScheduledOnce(
                key: "\(dayKey).sleep.\(event.id).\(currentMinute)",
                identifier: "lnook.daily.sleep.\(event.id)",
                title: event.title,
                body: event.body
            )
        }
    }

    private func sleepEvents(_ preferences: DailyCareNotificationSettings) -> [SleepEvent] {
        if preferences.weekendScheduleEnabled {
            var events: [SleepEvent] = []
            for weekday in 2...6 {
                events += sleepEvents(
                    weekday: weekday,
                    target: preferences.targetSleepTime,
                    lead: preferences.preSleepLeadTime,
                    id: "weekday.\(weekday)"
                )
            }
            for weekday in [1, 7] {
                events += sleepEvents(
                    weekday: weekday,
                    target: preferences.weekendTargetSleepTime,
                    lead: preferences.weekendPreSleepLeadTime,
                    id: "weekend.\(weekday)"
                )
            }
            return events
        }

        return (1...7).flatMap { weekday in
            sleepEvents(
                weekday: weekday,
                target: preferences.targetSleepTime,
                lead: preferences.preSleepLeadTime,
                id: "daily.\(weekday)"
            )
        }
    }

    private func sleepEvents(
        weekday: Int,
        target: String,
        lead: String,
        id: String
    ) -> [SleepEvent] {
        let targetMinute = parseTime(target)
        let leadMinutes = parseMinutes(lead)
        var prepareWeekday = weekday
        var prepareMinute = targetMinute - leadMinutes
        while prepareMinute < 0 {
            prepareMinute += 24 * 60
            prepareWeekday = prepareWeekday == 1 ? 7 : prepareWeekday - 1
        }

        return [
            SleepEvent(
                id: "\(id).target",
                weekday: weekday,
                minute: targetMinute,
                title: "该休息了",
                body: "今天辛苦了，准备放下屏幕去睡觉吧。"
            ),
            SleepEvent(
                id: "\(id).prepare",
                weekday: prepareWeekday,
                minute: prepareMinute,
                title: "准备休息",
                body: "距离入睡时间还有 \(leadMinutes) 分钟，可以开始收尾和洗漱了。"
            )
        ]
    }

    private func fireScheduledOnce(
        key: String,
        identifier: String,
        title: String,
        body: String
    ) async {
        guard lastScheduleKeys.insert(key).inserted else { return }
        await deliver(identifier: identifier, title: title, body: body, cooldown: 0)
    }

    private func evaluateDeviceStatus(
        _ preferences: DeviceNotificationSettings,
        battery: BatterySnapshot,
        device: DeviceInfoSnapshot
    ) async {
        if preferences.lowBatteryEnabled, let percent = battery.percent {
            let threshold = parseCount(preferences.lowBatteryThreshold)
            let isLow = percent <= threshold && !battery.isCharging
            if isLow && !wasLowBattery {
                await deliver(
                    identifier: "lnook.device.low-battery",
                    title: "电量较低",
                    body: "当前电量为 \(percent)%，建议连接电源。",
                    cooldown: 6 * 60 * 60
                )
            }
            wasLowBattery = isLow
        }

        if preferences.fullChargeReminderEnabled, let percent = battery.percent {
            let threshold = parseCount(preferences.fullChargeThreshold)
            let isNearlyCharged = percent >= threshold && battery.isCharging
            if isNearlyCharged && !wasNearlyCharged {
                await deliver(
                    identifier: "lnook.device.nearly-charged",
                    title: "电量即将充满",
                    body: "当前电量为 \(percent)%，可以考虑断开电源。",
                    cooldown: 6 * 60 * 60
                )
            }
            wasNearlyCharged = isNearlyCharged
        }

        if preferences.performanceAlertEnabled {
            let threshold = parseCount(preferences.performanceThreshold)
            let isHigh = device.cpuPercent >= threshold || device.memoryPercent >= threshold
            highUsageSampleCount = isHigh ? highUsageSampleCount + 1 : 0
            if highUsageSampleCount >= 3 {
                await deliver(
                    identifier: "lnook.device.high-usage",
                    title: "设备占用持续偏高",
                    body: "CPU \(device.cpuPercent)% · 内存 \(device.memoryPercent)%",
                    cooldown: 2 * 60 * 60
                )
                highUsageSampleCount = 0
            }
        } else {
            highUsageSampleCount = 0
        }

        if preferences.storageAlertEnabled, let availableGB = availableStorageGB() {
            let threshold = parseCount(preferences.storageThreshold)
            let isLow = availableGB <= threshold
            if isLow && !wasLowStorage {
                await deliver(
                    identifier: "lnook.device.low-storage",
                    title: "存储空间不足",
                    body: "macOS 可用空间约为 \(availableGB) GB，建议及时清理。",
                    cooldown: 12 * 60 * 60
                )
            }
            wasLowStorage = isLow
        }
    }

    private func handleNetworkStatus(_ status: NWPath.Status) async {
        defer { lastNetworkStatus = status }
        guard let previous = lastNetworkStatus, previous != status else { return }
        let preferences = NotificationSettingsViewModel.shared.device
        guard preferences.isEnabled, preferences.networkStatusAlertEnabled else { return }

        if status == .satisfied {
            await deliver(
                identifier: "lnook.device.network-restored",
                title: "网络已恢复",
                body: "设备已重新连接到网络。",
                cooldown: 60
            )
        } else if previous == .satisfied {
            await deliver(
                identifier: "lnook.device.network-lost",
                title: "网络连接中断",
                body: "当前无法连接到网络，请检查网络状态。",
                cooldown: 60
            )
        }
    }

    private func evaluateSittingReminder(
        _ preferences: DailyCareNotificationSettings,
        now: Date,
        elapsed: TimeInterval
    ) async {
        guard preferences.isEnabled,
              preferences.sitReminderEnabled,
              isWithinTimeRange(now, start: preferences.sitStartTime, end: preferences.sitEndTime)
        else {
            sittingActiveDuration = 0
            return
        }

        guard recentInputIdleSeconds() < 5 * 60 else {
            sittingActiveDuration = 0
            return
        }

        sittingActiveDuration += elapsed
        let threshold = TimeInterval(max(15, parseMinutes(preferences.sitInterval)) * 60)
        guard sittingActiveDuration >= threshold else { return }

        sittingActiveDuration = 0
        await deliver(
            identifier: "lnook.daily.sitting",
            title: "起来活动一下",
            body: "你已经持续使用电脑 \(parseMinutes(preferences.sitInterval)) 分钟，伸展一下身体吧。",
            cooldown: threshold * 0.9
        )
    }

    private func evaluateWeather(_ snapshot: WeatherSnapshot) async {
        let preferences = NotificationSettingsViewModel.shared.weather
        guard preferences.isEnabled, snapshot.isLive else { return }

        let symbol = snapshot.symbolName.lowercased()
        let condition = snapshot.condition
        let isRain = symbol.contains("rain") || symbol.contains("drizzle") || condition.contains("雨")
        let isThunder = symbol.contains("bolt") || condition.contains("雷") || condition.contains("冰雹")
        let isWind = (snapshot.windSpeed ?? 0) >= 10 || condition.contains("大风") || condition.contains("台风")
        let isHot = (snapshot.temperature ?? 0) >= 35
        let isCold = (snapshot.temperature ?? 100) <= 0 || condition.contains("雪") || condition.contains("冻")

        var alert: (key: String, title: String, body: String)?
        if isThunder, preferences.severeWeatherTypes.contains("雷电 / 冰雹") {
            alert = ("thunder", "雷电天气提醒", "\(snapshot.locationName)当前为\(condition)，请注意安全。")
        } else if isRain,
                  preferences.severeWeatherTypes.contains("强降雨 / 积水")
                    || !preferences.rainTriggers.isEmpty {
            alert = ("rain", "降雨提醒", "\(snapshot.locationName)当前为\(condition)，外出记得带伞。")
        } else if isWind, preferences.severeWeatherTypes.contains("大风 / 台风") {
            alert = ("wind", "大风天气提醒", "\(snapshot.locationName)风力较强，外出请注意安全。")
        } else if isHot, preferences.severeWeatherTypes.contains("高温 / 干热") {
            alert = ("heat", "高温提醒", "\(snapshot.locationName)当前约 \(snapshot.temperatureText)，注意防晒补水。")
        } else if isCold, preferences.severeWeatherTypes.contains("低温 / 雨雪冰冻") {
            alert = ("cold", "低温天气提醒", "\(snapshot.locationName)当前为\(condition)，注意保暖。")
        }

        guard let alert else { return }
        await deliver(
            identifier: "lnook.weather.\(alert.key)",
            title: alert.title,
            body: alert.body,
            cooldown: TimeInterval(max(60, parseMinutes(preferences.notifyCooldown)) * 60)
        )
    }

    private func deliver(
        identifier: String,
        title: String,
        body: String,
        cooldown: TimeInterval
    ) async {
        let now = Date()
        if cooldown > 0,
           let lastSent = lastSentDates[identifier],
           now.timeIntervalSince(lastSent) < cooldown {
            return
        }

        InAppNotificationWindowController.shared.show(
            InAppNotificationPayload(
                title: title,
                message: body,
                kind: notificationKind(for: identifier)
            )
        )
        lastSentDates[identifier] = now
    }

    private func notificationKind(for identifier: String) -> InAppNotificationKind {
        if identifier.contains("weather") { return .weather }
        if identifier.contains("battery") || identifier.contains("charged") { return .battery }
        if identifier.contains("high-usage") { return .performance }
        if identifier.contains("storage") { return .storage }
        if identifier.contains("network") { return .network }
        if identifier.contains("water") { return .water }
        if identifier.contains("sitting") { return .movement }
        if identifier.contains("sleep") { return .sleep }
        return .general
    }

    private func reminderTimes(start: String, end: String, interval: Int) -> [Int] {
        let startMinute = parseTime(start)
        var endMinute = parseTime(end)
        if endMinute <= startMinute { endMinute += 24 * 60 }

        var result: [Int] = []
        var minute = startMinute + interval
        while minute <= endMinute, result.count < 40 {
            result.append(normalizedMinute(minute))
            minute += interval
        }
        return Array(Set(result)).sorted()
    }

    private func parseTime(_ value: String) -> Int {
        let components = value.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return 0 }
        return normalizedMinute(components[0] * 60 + components[1])
    }

    private func parseMinutes(_ value: String) -> Int {
        let amount = Int(value.filter(\.isNumber)) ?? 0
        return value.contains("小时") ? amount * 60 : amount
    }

    private func parseCount(_ value: String) -> Int {
        Int(value.filter(\.isNumber)) ?? 0
    }

    private func normalizedMinute(_ value: Int) -> Int {
        ((value % (24 * 60)) + (24 * 60)) % (24 * 60)
    }

    private func isWithinTimeRange(_ date: Date, start: String, end: String) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let startMinute = parseTime(start)
        let endMinute = parseTime(end)
        if endMinute > startMinute {
            return current >= startMinute && current <= endMinute
        }
        return current >= startMinute || current <= endMinute
    }

    private func recentInputIdleSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func availableStorageGB() -> Int? {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let available = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int((Double(available) / 1_000_000_000).rounded(.down))
    }

    private func resetWaterProgressIfNeeded() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let savedDay = defaults.string(forKey: Self.waterProgressDayKey)
        if let savedDay, savedDay != today {
            NotificationSettingsViewModel.shared.dailyCare.waterProgress = 0
        }
        defaults.set(today, forKey: Self.waterProgressDayKey)
    }
}

private struct SleepEvent {
    let id: String
    let weekday: Int
    let minute: Int
    let title: String
    let body: String
}
