import Foundation
import Combine
import CoreGraphics

enum TodoCategory: String, Codable, CaseIterable, Sendable {
    case none
    case work
    case life
    case study
    case important

    var title: String {
        switch self {
        case .none: "无"
        case .work: "工作"
        case .life: "生活"
        case .study: "学习"
        case .important: "重要"
        }
    }

    var tagText: String? {
        self == .none ? nil : title
    }

    static func resolved(from text: String?) -> TodoCategory {
        let source = text ?? ""
        if source.contains("#工作") { return .work }
        if source.contains("#生活") { return .life }
        if source.contains("#学习") { return .study }
        if source.contains("#重要") { return .important }
        return .none
    }
}

enum TodoPriority: Int, Codable, CaseIterable, Sendable {
    case normal = 0
    case important = 1
    case urgent = 2

    var title: String {
        switch self {
        case .normal: "普通"
        case .important: "重要"
        case .urgent: "紧急"
        }
    }

    var tagText: String? {
        switch self {
        case .normal: nil
        case .important: "重要"
        case .urgent: "紧急"
        }
    }

    static func resolved(from text: String?) -> TodoPriority {
        let source = text ?? ""
        if source.contains("#紧急") { return .urgent }
        if source.contains("#重要") { return .important }
        return .normal
    }
}

enum TodoSortMode: String, Codable, CaseIterable, Sendable {
    case timeAsc
    case timeDesc
    case priority
    case createdAt

    var title: String {
        switch self {
        case .timeAsc: "按时间升序"
        case .timeDesc: "按时间降序"
        case .priority: "按优先级"
        case .createdAt: "按创建时间"
        }
    }
}

enum TodoDefaultRange: String, Codable, CaseIterable, Sendable {
    case today
    case selectedDate
    case week
    case all

    var title: String {
        switch self {
        case .today: "今天"
        case .selectedDate: "当前选中日期"
        case .week: "本周"
        case .all: "全部"
        }
    }
}

enum TodoHighlightColor: String, Codable, CaseIterable, Sendable {
    case blue
    case purple
    case orange
    case green

    var title: String {
        switch self {
        case .blue: "蓝色"
        case .purple: "紫色"
        case .orange: "橙色"
        case .green: "绿色"
        }
    }
}

struct TodoCardSettings: Codable, Equatable, Sendable {
    static let defaults = TodoCardSettings()

    var showDateSelector = true
    var showTime = true
    var showCategory = true
    var showCompleted = false
    var maxVisibleItems = 2
    var defaultRange: TodoDefaultRange = .selectedDate
    var sortMode: TodoSortMode = .timeAsc
    var highlightColor: TodoHighlightColor = .blue
    var useCompactMode = false
    var showEdgeGlow = true
    var showReminderBadge = true
    var dueSoonMinutes = 15
}

enum TodoCardStorageKeys {
    static let sortMode = "todo.card.sortMode"
    static let showDateSelector = "todo.card.showDateSelector"
    static let showTime = "todo.card.showTime"
    static let showCategory = "todo.card.showCategory"
    static let showCompleted = "todo.card.showCompleted"
    static let maxVisibleItems = "todo.card.maxVisibleItems"
    static let defaultRange = "todo.card.defaultRange"
    static let highlightColor = "todo.card.highlightColor"
    static let useCompactMode = "todo.card.useCompactMode"
    static let showEdgeGlow = "todo.card.showEdgeGlow"
    static let showReminderBadge = "todo.card.showReminderBadge"
    static let dueSoonMinutes = "todo.card.dueSoonMinutes"

    static let all = [
        sortMode,
        showDateSelector,
        showTime,
        showCategory,
        showCompleted,
        maxVisibleItems,
        defaultRange,
        highlightColor,
        useCompactMode,
        showEdgeGlow,
        showReminderBadge,
        dueSoonMinutes,
    ]
}

struct TodoTask: Identifiable, Equatable, Sendable {
    let id: UUID
    let reminderIdentifier: String?
    var title: String
    var notes: String
    var date: Date
    var dueTime: Date?
    var hasAlarm: Bool
    var location: String
    var category: TodoCategory
    var priority: TodoPriority
    var isCompleted: Bool
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        reminderIdentifier: String? = nil,
        title: String,
        notes: String = "",
        date: Date,
        dueTime: Date? = nil,
        hasAlarm: Bool = false,
        location: String = "",
        category: TodoCategory = .none,
        priority: TodoPriority = .normal,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.reminderIdentifier = reminderIdentifier
        self.title = title
        self.notes = notes
        self.date = date
        self.dueTime = dueTime
        self.hasAlarm = hasAlarm
        self.location = location
        self.category = category
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct TodoTaskDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var date: Date
    var dueTime: Date?
    var hasAlarm: Bool
    var location: String
}

enum TodoDateTimeInputParser {
    static func digitsOnly(_ text: String, maxLength: Int) -> String {
        String(text.filter(\.isNumber).prefix(maxLength))
    }

    static func parseDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separator: Character = trimmed.contains("-") ? "-" : "/"
        let parts = trimmed.split(separator: separator)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    static func parseDate(
        year: String,
        month: String,
        day: String,
        calendar: Calendar = .current
    ) -> Date? {
        let yearText = digitsOnly(year, maxLength: 4)
        let monthText = digitsOnly(month, maxLength: 2)
        let dayText = digitsOnly(day, maxLength: 2)

        guard yearText.count == 4,
              let yearValue = Int(yearText),
              let monthValue = Int(monthText),
              let dayValue = Int(dayText) else {
            return nil
        }

        return date(year: yearValue, month: monthValue, day: dayValue, calendar: calendar)
    }

    static func parseTime(_ text: String, on date: Date, calendar: Calendar = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    static func parseTime(
        hour: String,
        minute: String,
        on date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let hourText = digitsOnly(hour, maxLength: 2)
        let minuteText = digitsOnly(minute, maxLength: 2)

        guard let hourValue = Int(hourText),
              let minuteValue = Int(minuteText),
              (0...23).contains(hourValue),
              (0...59).contains(minuteValue) else {
            return nil
        }

        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: hourValue, minute: minuteValue, second: 0, of: day)
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }
}

struct TodoDayItem: Identifiable, Equatable, Sendable {
    let date: Date
    let taskCount: Int
    let isSelected: Bool

    var id: Date { date }
}

struct HorizontalDateStripMetrics: Equatable, Sendable {
    let visibleItemCount: CGFloat
    let spacing: CGFloat

    func itemWidth(for containerWidth: CGFloat) -> CGFloat {
        let visibleCount = max(1, visibleItemCount)
        let visibleSpacingCount = max(0, ceil(visibleCount) - 1)
        let availableWidth = max(1, containerWidth - spacing * visibleSpacingCount)

        return availableWidth / visibleCount
    }
}

struct TodoSchedulePreviewItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let reminderIdentifier: String?
    let title: String
    let date: Date
    let time: String
    let category: TodoCategory
    let priority: TodoPriority
    let isCompleted: Bool
    let completedAt: Date?

    init(task: TodoTask, calendar: Calendar) {
        self.id = task.id
        self.reminderIdentifier = task.reminderIdentifier
        self.title = task.title
        self.date = task.date
        self.time = Self.timeText(from: task.dueTime, calendar: calendar)
        self.category = task.category
        self.priority = task.priority
        self.isCompleted = task.isCompleted
        self.completedAt = task.completedAt
    }

    static func items(
        from tasks: [TodoTask],
        selectedDate: Date,
        today: Date = Date(),
        showTodayOnly: Bool = false,
        showCompleted: Bool = true,
        sortMode: TodoSortMode = .timeAsc,
        calendar: Calendar
    ) -> [TodoSchedulePreviewItem] {
        tasks
            .selectedTodoTasks(
                on: selectedDate,
                today: today,
                showTodayOnly: showTodayOnly,
                showCompleted: showCompleted,
                sortMode: sortMode,
                calendar: calendar
            )
            .map { TodoSchedulePreviewItem(task: $0, calendar: calendar) }
    }

    private static func timeText(from dueTime: Date?, calendar: Calendar) -> String {
        guard let dueTime else { return "" }

        let components = calendar.dateComponents([.hour, .minute], from: dueTime)
        guard let hour = components.hour, let minute = components.minute else { return "" }

        return String(format: "%02d:%02d", hour, minute)
    }
}

extension Sequence where Element == TodoTask {
    func selectedTodoTasks(
        on selectedDate: Date,
        today: Date = Date(),
        showTodayOnly: Bool = false,
        showCompleted: Bool = true,
        sortMode: TodoSortMode = .timeAsc,
        calendar: Calendar
    ) -> [TodoTask] {
        let filterDate = showTodayOnly ? today : selectedDate

        return self
            .filter { calendar.isDate($0.date, inSameDayAs: filterDate) }
            .filter { showCompleted || !$0.isCompleted }
            .sorted { lhs, rhs in
                compareTodoTasks(lhs, rhs, sortMode: sortMode, calendar: calendar)
            }
    }

    func completedTodoTasks(sortMode: TodoSortMode = .createdAt, calendar: Calendar) -> [TodoTask] {
        self
            .filter(\.isCompleted)
            .sorted { lhs, rhs in
                let lhsCompleted = lhs.completedAt ?? lhs.createdAt
                let rhsCompleted = rhs.completedAt ?? rhs.createdAt
                if lhsCompleted != rhsCompleted {
                    return lhsCompleted > rhsCompleted
                }
                return compareTodoTasks(lhs, rhs, sortMode: sortMode, calendar: calendar)
            }
    }
}

private func compareTodoTasks(
    _ lhs: TodoTask,
    _ rhs: TodoTask,
    sortMode: TodoSortMode,
    calendar: Calendar
) -> Bool {
    if lhs.isCompleted != rhs.isCompleted {
        return !lhs.isCompleted
    }

    switch sortMode {
    case .timeAsc:
        return compareTodoTime(lhs, rhs, ascending: true)
    case .timeDesc:
        return compareTodoTime(lhs, rhs, ascending: false)
    case .priority:
        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }
        return compareTodoTime(lhs, rhs, ascending: true)
    case .createdAt:
        return lhs.createdAt < rhs.createdAt
    }
}

private func compareTodoTime(_ lhs: TodoTask, _ rhs: TodoTask, ascending: Bool) -> Bool {
    let lhsDate = lhs.dueTime ?? lhs.date
    let rhsDate = rhs.dueTime ?? rhs.date

    if lhsDate != rhsDate {
        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
    }

    return lhs.createdAt < rhs.createdAt
}

@MainActor
final class TodoViewModel: ObservableObject {
    @Published private(set) var tasks: [TodoTask]
    @Published var selectedDate: Date
    @Published private(set) var isMultiSelectMode = false
    @Published private(set) var selectedTaskIDs: Set<TodoTask.ID> = []
    @Published private var visibleStartDate: Date

    private let calendar: Calendar
    private let dateWindowRadius = 365
    private var currentDate: Date

    init(
        seedDate: Date = Date(),
        calendar: Calendar = .current,
        tasks: [TodoTask]? = nil
    ) {
        self.calendar = calendar
        let initialDate = calendar.startOfDay(for: seedDate)
        self.currentDate = initialDate
        self.selectedDate = initialDate
        self.visibleStartDate = Self.startDate(around: initialDate, calendar: calendar)
        self.tasks = tasks ?? []
    }

    var dayItems: [TodoDayItem] {
        let taskCounts = Dictionary(grouping: tasks) { task in
            calendar.startOfDay(for: task.date)
        }
        .mapValues(\.count)

        return (-dateWindowRadius...dateWindowRadius).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: visibleStartDate) else {
                return nil
            }

            return TodoDayItem(
                date: date,
                taskCount: taskCounts[date, default: 0],
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate)
            )
        }
    }

    var selectedTasks: [TodoTask] {
        tasks.selectedTodoTasks(on: selectedDate, calendar: calendar)
    }

    var inProgressCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        selectedTaskIDs.removeAll()
    }

    func refreshForCurrentDate(_ date: Date = Date()) {
        let refreshedDate = calendar.startOfDay(for: date)
        guard !calendar.isDate(refreshedDate, inSameDayAs: currentDate) else { return }

        currentDate = refreshedDate
        selectedDate = refreshedDate
        visibleStartDate = Self.startDate(around: refreshedDate, calendar: calendar)
        selectedTaskIDs.removeAll()
    }

    func addTask(title: String, date: Date) {
        addTask(
            TodoTaskDraft(
                title: title,
                notes: "",
                date: date,
                dueTime: nil,
                hasAlarm: false,
                location: ""
            )
        )
    }

    func addTask(_ draft: TodoTaskDraft, reminderIdentifier: String? = nil) {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let trimmedLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TodoTask(
            reminderIdentifier: reminderIdentifier,
            title: trimmedTitle,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            date: calendar.startOfDay(for: draft.date),
            dueTime: draft.dueTime,
            hasAlarm: draft.hasAlarm,
            location: trimmedLocation,
            createdAt: Date()
        )

        tasks.append(task)
        selectedDate = task.date
        ensureDateIsVisible(task.date)
    }

    func replaceTasks(_ newTasks: [TodoTask]) {
        let existingIDsByReminder = tasks.reduce(into: [String: TodoTask.ID]()) { result, task in
            guard let reminderIdentifier = task.reminderIdentifier,
                  !reminderIdentifier.isEmpty else { return }
            result[reminderIdentifier] = task.id
        }

        tasks = newTasks.map { task in
            guard let reminderIdentifier = task.reminderIdentifier,
                  let existingID = existingIDsByReminder[reminderIdentifier] else {
                return task
            }

            return TodoTask(
                id: existingID,
                reminderIdentifier: reminderIdentifier,
                title: task.title,
                notes: task.notes,
                date: task.date,
                dueTime: task.dueTime,
                hasAlarm: task.hasAlarm,
                location: task.location,
                category: task.category,
                priority: task.priority,
                isCompleted: task.isCompleted,
                createdAt: task.createdAt,
                completedAt: task.completedAt
            )
        }
        selectedTaskIDs.removeAll()
        isMultiSelectMode = false
    }

    func toggleCompletion(for id: TodoTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

        tasks[index].isCompleted.toggle()
    }

    func markCompleted(for id: TodoTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted = true
    }

    func completeTask(
        id: TodoTask.ID,
        syncReminder: (String) async -> Bool
    ) async -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        guard !tasks[index].isCompleted else {
            tasks[index].isCompleted = false
            return true
        }

        if let reminderIdentifier = tasks[index].reminderIdentifier,
           !reminderIdentifier.isEmpty,
           !(await syncReminder(reminderIdentifier)) {
            return false
        }

        tasks[index].isCompleted = true
        return true
    }

    func toggleMultiSelectMode() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedTaskIDs.removeAll()
        }
    }

    func toggleSelection(for id: TodoTask.ID) {
        if selectedTaskIDs.contains(id) {
            selectedTaskIDs.remove(id)
        } else {
            selectedTaskIDs.insert(id)
        }
    }

    func taskCount(on date: Date) -> Int {
        tasks.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
    }

    private func ensureDateIsVisible(_ date: Date) {
        let normalizedDate = calendar.startOfDay(for: date)
        guard !isDateVisible(normalizedDate) else { return }

        visibleStartDate = Self.startDate(around: normalizedDate, calendar: calendar)
    }

    private func isDateVisible(_ date: Date) -> Bool {
        dayItems.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private static func startDate(around date: Date, calendar: Calendar) -> Date {
        let normalizedDate = calendar.startOfDay(for: date)
        let daysSinceSunday = calendar.component(.weekday, from: normalizedDate) - 1
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: normalizedDate) ?? normalizedDate
    }
}
