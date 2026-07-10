import EventKit
import Foundation

struct ReminderItemSummary: Identifiable, Sendable {
    let id: String
    let title: String
    let dueText: String
    let isOverdue: Bool
}

struct ReminderSnapshot: Sendable {
    var statusText: String
    var items: [ReminderItemSummary]
    var isAuthorized: Bool

    static let placeholder = ReminderSnapshot(
        statusText: "正在读取提醒事项",
        items: [],
        isAuthorized: false
    )
}

struct ReminderCreationRequest: Sendable {
    var title: String
    var notes: String
    var hasDueDate: Bool
    var dueDate: Date
    var hasDueTime: Bool
    var dueTime: Date
    var hasAlarm: Bool
    var location: String
    var tagsText: String
}

private final class ReminderFetchState: @unchecked Sendable {
    private let lock = NSLock()
    private var store: EKEventStore?
    private var requestID: Any?
    private var continuation: CheckedContinuation<[EKReminder], Never>?
    private var isResolved = false

    func configure(
        store: EKEventStore,
        requestID: Any,
        continuation: CheckedContinuation<[EKReminder], Never>
    ) {
        lock.lock()
        if isResolved {
            lock.unlock()
            store.cancelFetchRequest(requestID)
            return
        }

        self.store = store
        self.requestID = requestID
        self.continuation = continuation
        lock.unlock()
    }

    func resolve(_ reminders: [EKReminder]) {
        let state = finish()
        state.continuation?.resume(returning: reminders)
    }

    func cancel() {
        let state = finish()
        if let store = state.store, let requestID = state.requestID {
            store.cancelFetchRequest(requestID)
        }
        state.continuation?.resume(returning: [])
    }

    private func finish() -> (store: EKEventStore?, requestID: Any?, continuation: CheckedContinuation<[EKReminder], Never>?) {
        lock.lock()
        defer { lock.unlock() }

        guard !isResolved else {
            return (nil, nil, nil)
        }

        isResolved = true
        let finished = (store, requestID, continuation)
        store = nil
        requestID = nil
        continuation = nil
        return finished
    }
}

@MainActor
final class ReminderProvider: ObservableObject {

    @Published private(set) var snapshot: ReminderSnapshot = .placeholder

    private let store = EKEventStore()
    private var hasStarted = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    deinit {
        loadTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        requestReminderAccess()
    }

    func stop() {
        hasStarted = false
        loadTask?.cancel()
        loadTask = nil
    }

    func addReminder(title: String) {
        let request = ReminderCreationRequest(
            title: title,
            notes: "",
            hasDueDate: false,
            dueDate: Date(),
            hasDueTime: false,
            dueTime: Date(),
            hasAlarm: false,
            location: "",
            tagsText: ""
        )
        addReminder(request: request)
    }

    func addReminder(request: ReminderCreationRequest) {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withReminderAccess {
            _ = self.createReminder(request: request)
        }
    }

    func completeReminder(_ reminder: ReminderItemSummary) {
        withReminderAccess {
            _ = self.markReminderCompleted(identifier: reminder.id)
        }
    }

    func createTodoReminder(request: ReminderCreationRequest) async -> String? {
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              await requestTodoSyncAccess() else { return nil }
        return createReminder(request: request)
    }

    func completeTodoReminder(identifier: String) async -> Bool {
        guard await requestTodoSyncAccess() else { return false }
        return updateReminderCompletion(identifier: identifier, isCompleted: true)
    }

    func restoreTodoReminder(identifier: String) async -> Bool {
        guard await requestTodoSyncAccess() else { return false }
        return updateReminderCompletion(identifier: identifier, isCompleted: false)
    }

    func deleteTodoReminder(identifier: String) async -> Bool {
        guard await requestTodoSyncAccess() else { return false }
        return removeReminder(identifier: identifier)
    }

    func loadTodoTasksForSync(includeCompleted: Bool = false) async -> [TodoTask] {
        guard await requestTodoSyncAccess() else { return [] }

        updateSnapshot(
            statusText: "正在同步提醒事项",
            items: snapshot.items,
            isAuthorized: true
        )

        let tasks = await Self.makeTodoTasksFromReminders(includeCompleted: includeCompleted)
        updateSnapshot(
            statusText: tasks.isEmpty ? "暂无待办" : "已同步 \(tasks.count) 个待办",
            items: snapshot.items,
            isAuthorized: true
        )
        return tasks
    }

    private func requestReminderAccess() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleAuthorizationResult(granted: granted, error: error)
                    }
                }
            } else {
                store.requestAccess(to: .reminder) { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleAuthorizationResult(granted: granted, error: error)
                    }
                }
            }
        case .authorized, .fullAccess:
            loadIncompleteReminders()
        case .writeOnly:
            updateSnapshot(
                statusText: "仅写入授权",
                items: [],
                isAuthorized: false
            )
        case .denied, .restricted:
            updateSnapshot(
                statusText: "未授权访问",
                items: [],
                isAuthorized: false
            )
        @unknown default:
            updateSnapshot(
                statusText: "提醒事项不可用",
                items: [],
                isAuthorized: false
            )
        }
    }

    private func withReminderAccess(_ action: @MainActor @escaping () -> Void) {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleActionAuthorizationResult(granted: granted, error: error, action: action)
                    }
                }
            } else {
                store.requestAccess(to: .reminder) { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        self?.handleActionAuthorizationResult(granted: granted, error: error, action: action)
                    }
                }
            }
        case .authorized, .fullAccess:
            action()
        case .writeOnly:
            updateSnapshot(
                statusText: "仅写入授权",
                items: snapshot.items,
                isAuthorized: false
            )
        case .denied, .restricted:
            updateSnapshot(
                statusText: "未授权访问",
                items: snapshot.items,
                isAuthorized: false
            )
        @unknown default:
            updateSnapshot(
                statusText: "提醒事项不可用",
                items: snapshot.items,
                isAuthorized: false
            )
        }
    }

    private func handleActionAuthorizationResult(
        granted: Bool,
        error: Error?,
        action: @MainActor @escaping () -> Void
    ) {
        guard error == nil else {
            updateSnapshot(
                statusText: "授权失败",
                items: snapshot.items,
                isAuthorized: false
            )
            return
        }

        if granted {
            action()
        } else {
            updateSnapshot(
                statusText: "未授权访问",
                items: snapshot.items,
                isAuthorized: false
            )
        }
    }

    private func requestTodoSyncAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                let completion: @Sendable (Bool, Error?) -> Void = { [weak self] granted, error in
                    Task { @MainActor [weak self] in
                        if error != nil {
                            self?.updateSnapshot(
                                statusText: "授权失败",
                                items: self?.snapshot.items ?? [],
                                isAuthorized: false
                            )
                        } else if !granted {
                            self?.updateSnapshot(
                                statusText: "未授权访问",
                                items: self?.snapshot.items ?? [],
                                isAuthorized: false
                            )
                        }
                        continuation.resume(returning: granted && error == nil)
                    }
                }

                if #available(macOS 14.0, *) {
                    store.requestFullAccessToReminders(completion: completion)
                } else {
                    store.requestAccess(to: .reminder, completion: completion)
                }
            }
        case .writeOnly:
            updateSnapshot(
                statusText: "仅写入授权",
                items: snapshot.items,
                isAuthorized: false
            )
            return false
        case .denied, .restricted:
            updateSnapshot(
                statusText: "未授权访问",
                items: snapshot.items,
                isAuthorized: false
            )
            return false
        @unknown default:
            updateSnapshot(
                statusText: "提醒事项不可用",
                items: snapshot.items,
                isAuthorized: false
            )
            return false
        }
    }

    @discardableResult
    private func createReminder(request: ReminderCreationRequest) -> String? {
        guard let calendar = store.defaultCalendarForNewReminders() else {
            updateSnapshot(
                statusText: "没有默认提醒列表",
                items: snapshot.items,
                isAuthorized: true
            )
            return nil
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.calendar = calendar
        reminder.notes = Self.notesText(for: request)

        let schedule = Self.effectiveSchedule(for: request)
        if let dueDateComponents = schedule.dueDateComponents {
            reminder.dueDateComponents = dueDateComponents
        }

        let trimmedLocation = request.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocation.isEmpty {
            reminder.location = trimmedLocation
        }

        if schedule.shouldAddAlarm {
            reminder.addAlarm(EKAlarm(relativeOffset: 0))
        }

        do {
            try store.save(reminder, commit: true)
            loadIncompleteReminders()
            return reminder.calendarItemIdentifier
        } catch {
            updateSnapshot(
                statusText: "新增失败",
                items: snapshot.items,
                isAuthorized: true
            )
            return nil
        }
    }

    private struct ReminderSchedule {
        let dueDateComponents: DateComponents?
        let shouldAddAlarm: Bool
    }

    private static func effectiveSchedule(for request: ReminderCreationRequest) -> ReminderSchedule {
        guard request.hasDueDate || request.hasDueTime || request.hasAlarm else {
            return ReminderSchedule(dueDateComponents: nil, shouldAddAlarm: false)
        }

        let calendar = reminderCalendar()
        let baseDate = request.hasDueDate ? request.dueDate : Date()
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)

        if request.hasDueTime || request.hasAlarm {
            let timeDate = request.hasDueTime
                ? request.dueTime
                : defaultAlarmTime(on: baseDate, calendar: calendar)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
        }

        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return ReminderSchedule(
            dueDateComponents: components,
            shouldAddAlarm: request.hasAlarm && components.hour != nil
        )
    }

    private static func defaultAlarmTime(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private static func reminderCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale.current
        calendar.timeZone = .current
        return calendar
    }

    private static func notesText(for request: ReminderCreationRequest) -> String? {
        let notes = request.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = normalizedTags(from: request.tagsText)
        let tagLine = tags.isEmpty ? "" : tags.joined(separator: " ")
        let body = [notes, tagLine]
            .filter { !$0.isEmpty }
            .joined(separator: notes.isEmpty || tagLine.isEmpty ? "" : "\n")

        return body.isEmpty ? nil : body
    }

    private static func normalizedTags(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",，;； \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { tag in
                let bareTag = tag.trimmingCharacters(in: CharacterSet(charactersIn: "#＃"))
                return bareTag.isEmpty ? "" : "#\(bareTag)"
            }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    private func markReminderCompleted(identifier: String) -> Bool {
        updateReminderCompletion(identifier: identifier, isCompleted: true)
    }

    @discardableResult
    private func updateReminderCompletion(identifier: String, isCompleted: Bool) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            loadIncompleteReminders()
            return false
        }

        reminder.isCompleted = isCompleted
        reminder.completionDate = isCompleted ? Date() : nil

        do {
            try store.save(reminder, commit: true)
            loadIncompleteReminders()
            return true
        } catch {
            updateSnapshot(
                statusText: isCompleted ? "完成失败" : "恢复失败",
                items: snapshot.items,
                isAuthorized: true
            )
            return false
        }
    }

    @discardableResult
    private func removeReminder(identifier: String) -> Bool {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            loadIncompleteReminders()
            return false
        }

        do {
            try store.remove(reminder, commit: true)
            loadIncompleteReminders()
            return true
        } catch {
            updateSnapshot(
                statusText: "删除失败",
                items: snapshot.items,
                isAuthorized: true
            )
            return false
        }
    }

    private func handleAuthorizationResult(granted: Bool, error: Error?) {
        guard error == nil else {
            updateSnapshot(
                statusText: "授权失败",
                items: [],
                isAuthorized: false
            )
            return
        }

        if granted {
            loadIncompleteReminders()
        } else {
            updateSnapshot(
                statusText: "未授权访问",
                items: [],
                isAuthorized: false
            )
        }
    }

    private func loadIncompleteReminders() {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        loadTask = Task.detached(priority: .utility) { [generation] in
            guard !Task.isCancelled else { return }
            let result = await Self.makeIncompleteRemindersSnapshot()
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

    nonisolated private static func makeIncompleteRemindersSnapshot() async -> ReminderSnapshot {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        let reminders = await fetchReminders(matching: predicate, store: store)
        guard !Task.isCancelled else {
            return ReminderSnapshot(statusText: "正在读取提醒事项", items: [], isAuthorized: false)
        }

        let sortedReminders = reminders
            .filter { !$0.isCompleted }
            .sorted(by: Self.sortReminders)

        let items = sortedReminders
            .prefix(50)
            .map(Self.summary(for:))

        return ReminderSnapshot(
            statusText: sortedReminders.isEmpty ? "暂无待办" : "\(sortedReminders.count) 个未完成",
            items: Array(items),
            isAuthorized: true
        )
    }

    nonisolated private static func makeTodoTasksFromReminders(includeCompleted: Bool) async -> [TodoTask] {
        let store = EKEventStore()
        let incompletePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )

        var reminders = await fetchReminders(matching: incompletePredicate, store: store)
        guard !Task.isCancelled else { return [] }

        if includeCompleted {
            let completedPredicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: nil,
                ending: nil,
                calendars: nil
            )
            let completedReminders = await fetchReminders(matching: completedPredicate, store: store)
            guard !Task.isCancelled else { return [] }
            reminders.append(contentsOf: completedReminders)
        }

        return reminders
            .sorted(by: Self.sortReminders)
            .map(Self.todoTask(for:))
    }

    nonisolated private static func fetchReminders(matching predicate: NSPredicate, store: EKEventStore) async -> [EKReminder] {
        let fetchState = ReminderFetchState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: [])
                    return
                }

                let requestID = store.fetchReminders(matching: predicate) { reminders in
                    fetchState.resolve(reminders ?? [])
                }

                fetchState.configure(store: store, requestID: requestID, continuation: continuation)

                if Task.isCancelled {
                    fetchState.cancel()
                }
            }
        } onCancel: {
            fetchState.cancel()
        }
    }

    private func updateSnapshot(
        statusText: String,
        items: [ReminderItemSummary],
        isAuthorized: Bool
    ) {
        snapshot = ReminderSnapshot(
            statusText: statusText,
            items: items,
            isAuthorized: isAuthorized
        )
    }

    nonisolated private static func sortReminders(_ left: EKReminder, _ right: EKReminder) -> Bool {
        let leftDate = sortDate(for: left)
        let rightDate = sortDate(for: right)

        switch (leftDate, rightDate) {
        case let (leftDate?, rightDate?):
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    nonisolated private static func summary(for reminder: EKReminder) -> ReminderItemSummary {
        let date = sortDate(for: reminder)

        return ReminderItemSummary(
            id: reminder.calendarItemIdentifier,
            title: reminder.title.isEmpty ? "未命名提醒" : reminder.title,
            dueText: dueText(for: reminder, date: date),
            isOverdue: date.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: Date()) } ?? false
        )
    }

    nonisolated private static func todoTask(for reminder: EKReminder) -> TodoTask {
        let calendar = Calendar.current
        let date = sortDate(for: reminder) ?? Date()
        let dueComponents = reminder.dueDateComponents ?? reminder.startDateComponents
        let hasDueTime = dueComponents?.hour != nil

        return TodoTask(
            reminderIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title.isEmpty ? "未命名提醒" : reminder.title,
            notes: reminder.notes ?? "",
            date: calendar.startOfDay(for: date),
            dueTime: hasDueTime ? date : nil,
            hasAlarm: reminder.alarms?.isEmpty == false,
            location: reminder.location ?? "",
            category: TodoCategory.resolved(from: reminder.notes),
            priority: TodoPriority.resolved(from: reminder.notes),
            isCompleted: reminder.isCompleted,
            createdAt: reminder.creationDate ?? Date(),
            completedAt: reminder.completionDate
        )
    }

    nonisolated private static func sortDate(for reminder: EKReminder) -> Date? {
        resolvedDate(from: reminder.dueDateComponents)
            ?? resolvedDate(from: reminder.startDateComponents)
    }

    nonisolated private static func resolvedDate(from components: DateComponents?) -> Date? {
        guard var components else { return nil }
        let calendar = components.calendar ?? Calendar.current
        components.calendar = calendar
        return calendar.date(from: components)
    }

    nonisolated private static func dueText(for reminder: EKReminder, date: Date?) -> String {
        guard let date else {
            return "无日期"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeTextIfNeeded(for: reminder) ?? "今天"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天"
        }
        if calendar.startOfDay(for: date) < calendar.startOfDay(for: Date()) {
            return "逾期"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    nonisolated private static func timeTextIfNeeded(for reminder: EKReminder) -> String? {
        guard
            let components = reminder.dueDateComponents,
            components.hour != nil
        else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return resolvedDate(from: components).map(formatter.string(from:))
    }
}
