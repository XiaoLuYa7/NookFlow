import AppKit
import EventKit
import Foundation

struct CalendarEventSummary: Identifiable, Sendable {
    let id: String
    let title: String
    let timeText: String
    let calendarColorHex: String?
}

struct CalendarSnapshot: Sendable {
    var dayTitle: String
    var dateTitle: String
    var statusText: String
    var events: [CalendarEventSummary]
    var eventsByDay: [String: [CalendarEventSummary]]
    var isAuthorized: Bool

    static let placeholder = CalendarSnapshot(
        dayTitle: "今天",
        dateTitle: Self.formattedDate(Date()),
        statusText: "正在读取日历",
        events: [],
        eventsByDay: [:],
        isAuthorized: false
    )

    static func formattedDate(_ date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return displayDateFormatter.string(from: date)
    }

    static func dayKey(for date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return dayKeyFormatter.string(from: date)
    }

    private static let formatterLock = NSLock()
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter
    }()
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@MainActor
final class CalendarProvider: ObservableObject {

    @Published private(set) var snapshot: CalendarSnapshot = .placeholder

    private let store = EKEventStore()
    private var hasStarted = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var refreshWorkItem: DispatchWorkItem?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    deinit {
        refreshWorkItem?.cancel()
        loadTask?.cancel()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeCalendarChanges()
        requestCalendarAccess()
    }

    func stop() {
        hasStarted = false
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        loadTask?.cancel()
        loadTask = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
    }

    private func observeCalendarChanges() {
        let center = NotificationCenter.default

        notificationTokens.append(
            center.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefresh(resetStore: true)
                }
            }
        )

        notificationTokens.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRefresh(resetStore: true)
                }
            }
        )
    }

    private func scheduleRefresh(resetStore: Bool) {
        refreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard Self.hasCalendarReadAccess else {
                self.requestCalendarAccess()
                return
            }
            self.loadTodayEvents(resetStore: resetStore)
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private static var hasCalendarReadAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    private func requestCalendarAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleAuthorizationResult(granted: granted, error: error)
                    }
                }
            } else {
                store.requestAccess(to: .event) { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleAuthorizationResult(granted: granted, error: error)
                    }
                }
            }
        case .authorized, .fullAccess:
            loadTodayEvents()
        case .writeOnly:
            updateSnapshot(
                statusText: "仅写入授权",
                events: [],
                isAuthorized: false
            )
        case .denied, .restricted:
            updateSnapshot(
                statusText: "未授权访问",
                events: [],
                isAuthorized: false
            )
        @unknown default:
            updateSnapshot(
                statusText: "日历不可用",
                events: [],
                isAuthorized: false
            )
        }
    }

    private func handleAuthorizationResult(granted: Bool, error: Error?) {
        guard error == nil else {
            updateSnapshot(
                statusText: "授权失败",
                events: [],
                isAuthorized: false
            )
            return
        }

        if granted {
            loadTodayEvents()
        } else {
            updateSnapshot(
                statusText: "未授权访问",
                events: [],
                isAuthorized: false
            )
        }
    }

    private func loadTodayEvents(resetStore: Bool = false) {
        if resetStore {
            store.reset()
        }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadTask = Task.detached(priority: .utility) { [generation] in
            guard !Task.isCancelled else { return }
            let result = Self.makeTodaySnapshot()
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self,
                      self.loadGeneration == generation,
                      !Task.isCancelled else { return }
                self.snapshot = result
                self.loadTask = nil
            }
        }
    }

    nonisolated private static func makeTodaySnapshot() -> CalendarSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
            let rangeStart = calendar.date(byAdding: .day, value: -45, to: startOfDay),
            let rangeEnd = calendar.date(byAdding: .day, value: 120, to: startOfDay)
        else {
            return snapshot(
                statusText: "日历不可用",
                events: [],
                eventsByDay: [:],
                isAuthorized: false
            )
        }

        let store = EKEventStore()
        let todayPredicate = store.predicateForEvents(
            withStart: startOfDay,
            end: endOfDay,
            calendars: nil
        )

        let events = store.events(matching: todayPredicate)
            .filter { event in
                event.endDate > now
            }
            .sorted { left, right in
                left.startDate < right.startDate
            }
            .prefix(3)
            .map(Self.summary(for:))

        let rangePredicate = store.predicateForEvents(
            withStart: rangeStart,
            end: rangeEnd,
            calendars: nil
        )
        let eventsByDay = Dictionary(grouping: store.events(matching: rangePredicate)
            .sorted { left, right in
                left.startDate < right.startDate
            }) { event in
                CalendarSnapshot.dayKey(for: event.startDate)
            }
            .mapValues { events in
                events.map(Self.summary(for:))
            }

        return snapshot(
            statusText: events.isEmpty ? "今日没有日程" : "\(events.count) 个即将开始",
            events: Array(events),
            eventsByDay: eventsByDay,
            isAuthorized: true
        )
    }

    private func updateSnapshot(
        statusText: String,
        events: [CalendarEventSummary],
        eventsByDay: [String: [CalendarEventSummary]] = [:],
        isAuthorized: Bool
    ) {
        snapshot = Self.snapshot(
            statusText: statusText,
            events: events,
            eventsByDay: eventsByDay,
            isAuthorized: isAuthorized
        )
    }

    nonisolated private static func snapshot(
        statusText: String,
        events: [CalendarEventSummary],
        eventsByDay: [String: [CalendarEventSummary]] = [:],
        isAuthorized: Bool
    ) -> CalendarSnapshot {
        CalendarSnapshot(
            dayTitle: "今天",
            dateTitle: CalendarSnapshot.formattedDate(Date()),
            statusText: statusText,
            events: events,
            eventsByDay: eventsByDay,
            isAuthorized: isAuthorized
        )
    }

    nonisolated private static func summary(for event: EKEvent) -> CalendarEventSummary {
        CalendarEventSummary(
            id: event.eventIdentifier ?? "\(event.startDate.timeIntervalSince1970)-\(event.title ?? "")",
            title: event.title?.isEmpty == false ? event.title : "未命名日程",
            timeText: timeText(for: event),
            calendarColorHex: event.calendar.cgColor.flatMap(Self.hexString(for:))
        )
    }

    nonisolated private static func timeText(for event: EKEvent) -> String {
        if event.isAllDay {
            return "全天"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.startDate)
    }

    nonisolated private static func hexString(for color: CGColor) -> String? {
        guard let components = color.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        )?.components else {
            return nil
        }

        let red = Int((components[safe: 0] ?? 0) * 255)
        let green = Int((components[safe: 1] ?? 0) * 255)
        let blue = Int((components[safe: 2] ?? 0) * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
