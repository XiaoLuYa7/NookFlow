import SwiftUI

enum TodoStyle {
    static let pageBackground = AppColor.pageBackground
    static let cardBackground = AppColor.elevatedSurface
    static let selectedDateBackground = AppColor.accentSoft
    static let blue = AppColor.accent
    static let primaryText = AppColor.textPrimary
    static let secondaryText = AppColor.textSecondary
    static let mutedText = AppColor.textTertiary
    static let checkFill = AppColor.accentSoft

    static let contentMaxWidth: CGFloat = 980
    static let dateCardWidth: CGFloat = 124
    static let dateCardHeight: CGFloat = 70
    static let dateCardRadius = AppRadius.row
    static let pillRadius = AppRadius.row
}

struct TodoView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var settings: IslandSettings
    @StateObject private var model = TodoViewModel()
    @StateObject private var reminderProvider = ReminderProvider()
    @State private var isShowingNewTaskSheet = false
    @State private var isShowingTodoSettings = false
    @State private var errorMessage: String?
    @State private var syncTask: Task<Void, Never>?
    @State private var createTask: Task<Void, Never>?
    @State private var completionTasks: [TodoTask.ID: Task<Void, Never>] = [:]

    var body: some View {
        TodoMainContentView(
            model: model,
            isShowingNewTaskSheet: $isShowingNewTaskSheet,
            onSync: syncReminders,
            onOpenSettings: { isShowingTodoSettings = true },
            onToggleCompletion: toggleCompletion
        )
        .background(TodoStyle.pageBackground)
        .preferredColorScheme(.light)
        .onAppear {
            model.refreshForCurrentDate()
            syncReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshForCurrentDate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            model.refreshForCurrentDate()
        }
        .onDisappear {
            syncTask?.cancel()
            syncTask = nil
            createTask?.cancel()
            createTask = nil
            completionTasks.values.forEach { $0.cancel() }
            completionTasks.removeAll()
        }
        .sheet(isPresented: $isShowingNewTaskSheet) {
            NewTodoSheetView(
                initialDate: model.selectedDate,
                onCancel: { isShowingNewTaskSheet = false },
                onSave: createTodo
            )
        }
        .sheet(isPresented: $isShowingTodoSettings) {
            TodoSettingsSheetView(settings: settings)
        }
        .alert(
            "待办事项",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func syncReminders() {
        guard syncTask == nil else { return }
        syncTask = Task { @MainActor in
            defer { syncTask = nil }
            let tasks = await reminderProvider.loadTodoTasksForSync()
            guard !Task.isCancelled else { return }
            model.replaceTasks(tasks)
        }
    }

    private func toggleCompletion(_ task: TodoTask) {
        guard completionTasks[task.id] == nil else { return }
        completionTasks[task.id] = Task { @MainActor in
            defer { completionTasks[task.id] = nil }
            let succeeded = await model.completeTask(id: task.id) { identifier in
                await reminderProvider.completeTodoReminder(identifier: identifier)
            }
            guard !Task.isCancelled else { return }
            if !succeeded {
                errorMessage = "未能完成系统提醒事项，任务状态未更改。"
            }
        }
    }

    private func createTodo(_ draft: TodoTaskDraft) {
        guard createTask == nil else { return }
        createTask = Task { @MainActor in
            defer { createTask = nil }
            guard let identifier = await reminderProvider.createTodoReminder(
                request: draft.reminderCreationRequest
            ) else {
                guard !Task.isCancelled else { return }
                errorMessage = "无法保存到系统提醒事项，请检查权限后重试。"
                return
            }

            guard !Task.isCancelled else { return }
            model.addTask(draft, reminderIdentifier: identifier)
            isShowingNewTaskSheet = false
        }
    }
}

private struct TodoMainContentView: View {
    @ObservedObject var model: TodoViewModel
    @Binding var isShowingNewTaskSheet: Bool
    let onSync: () -> Void
    let onOpenSettings: () -> Void
    let onToggleCompletion: (TodoTask) -> Void

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: TodoStyle.contentMaxWidth) {
            PageHeaderView(
                title: "待办事项",
                subtitle: "轻量安排每天的任务，并与系统提醒事项保持同步。",
                icon: "checklist"
            ) {
                HStack(spacing: AppSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                        Text("进行中")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textTertiary)
                        Text("\(model.inProgressCount)")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColor.accent)
                    }
                    Button(action: onOpenSettings) {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(AppButtonStyle(role: .secondary))
                    .help("待办设置")
                    Button(action: onSync) {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(AppButtonStyle(role: .secondary))
                    .help("同步提醒事项")
                    Button {
                        isShowingNewTaskSheet = true
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .buttonStyle(AppButtonStyle(role: .primary))
                }
            }
        } content: {
            SettingsSectionCard(title: "日期", subtitle: "选择一天查看对应任务") {
                TodoDateStripView(
                    days: model.dayItems,
                    onSelect: model.selectDate
                )
            }

            SettingsSectionCard {
                TodoTaskListView(
                    model: model,
                    onToggleCompletion: onToggleCompletion
                )
            }
        }
    }
}

private struct TodoSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: IslandSettings

    @AppStorage(TodoCardStorageKeys.showDateSelector) private var showDateSelector = true
    @AppStorage(TodoCardStorageKeys.showTime) private var showTime = true
    @AppStorage(TodoCardStorageKeys.showCategory) private var showCategory = true
    @AppStorage(TodoCardStorageKeys.showCompleted) private var showCompleted = false
    @AppStorage(TodoCardStorageKeys.maxVisibleItems) private var maxVisibleItems = 2
    @AppStorage(TodoCardStorageKeys.defaultRange) private var defaultRangeRaw = TodoDefaultRange.selectedDate.rawValue
    @AppStorage(TodoCardStorageKeys.sortMode) private var sortModeRaw = TodoSortMode.timeAsc.rawValue
    @AppStorage(TodoCardStorageKeys.highlightColor) private var highlightColorRaw = TodoHighlightColor.blue.rawValue
    @AppStorage(TodoCardStorageKeys.useCompactMode) private var useCompactMode = false
    @AppStorage(TodoCardStorageKeys.showEdgeGlow) private var showEdgeGlow = true
    @AppStorage(TodoCardStorageKeys.showReminderBadge) private var showReminderBadge = true
    @AppStorage(TodoCardStorageKeys.dueSoonMinutes) private var dueSoonMinutes = 15

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    SettingsSectionCard(title: "模块", subtitle: "控制待办在灵动岛中的显示") {
                        AppSettingsToggleRow(
                            icon: "checklist",
                            title: "显示待办卡片",
                            subtitle: "关闭后，灵动岛首页不再显示待办模块。",
                            showsDivider: false,
                            isOn: $settings.showTodoModule
                        )
                    }

                    SettingsSectionCard(title: "卡片显示", subtitle: "调整灵动岛待办卡片中的信息密度") {
                        AppSettingsToggleRow(
                            icon: "calendar",
                            title: "显示日期选择器",
                            subtitle: "在卡片顶部显示可切换日期。",
                            isOn: $showDateSelector
                        )
                        AppSettingsToggleRow(
                            icon: "clock",
                            title: "显示时间",
                            subtitle: "任务行展示提醒时间。",
                            isOn: $showTime
                        )
                        AppSettingsToggleRow(
                            icon: "tag",
                            title: "显示标签",
                            subtitle: "展示分组、优先级等标签信息。",
                            isOn: $showCategory
                        )
                        AppSettingsToggleRow(
                            icon: "checkmark.circle",
                            title: "显示已完成事项",
                            subtitle: "卡片列表中包含已完成任务。",
                            isOn: $showCompleted
                        )
                        TodoSettingsStepperRow(
                            icon: "number",
                            title: "最大显示数量",
                            subtitle: "限制卡片中直接展示的任务数量。",
                            value: $maxVisibleItems,
                            range: 1...4,
                            showsDivider: false
                        )
                    }

                    SettingsSectionCard(title: "筛选与排序", subtitle: "设置卡片默认展示范围和排序规则") {
                        TodoSettingsRawPickerRow<TodoDefaultRange>(
                            icon: "calendar.day.timeline.left",
                            title: "默认显示范围",
                            subtitle: "打开卡片时默认查看的待办范围。",
                            selection: $defaultRangeRaw,
                            values: TodoDefaultRange.allCases
                        )
                        TodoSettingsRawPickerRow<TodoSortMode>(
                            icon: "arrow.up.arrow.down",
                            title: "默认排序方式",
                            subtitle: "影响待办卡片和弹窗列表的排列顺序。",
                            selection: $sortModeRaw,
                            values: TodoSortMode.allCases,
                            showsDivider: false
                        )
                    }

                    SettingsSectionCard(title: "视觉与提醒", subtitle: "调整卡片强调色和提醒提示") {
                        TodoSettingsRawPickerRow<TodoHighlightColor>(
                            icon: "paintpalette",
                            title: "高亮颜色",
                            subtitle: "用于选中日期、按钮和提醒状态。",
                            selection: $highlightColorRaw,
                            values: TodoHighlightColor.allCases
                        )
                        AppSettingsToggleRow(
                            icon: "sparkles",
                            title: "边缘光",
                            subtitle: "在卡片边缘显示轻微强调效果。",
                            isOn: $showEdgeGlow
                        )
                        AppSettingsToggleRow(
                            icon: "rectangle.compress.vertical",
                            title: "紧凑模式",
                            subtitle: "减少卡片内边距，适合较小模块尺寸。",
                            isOn: $useCompactMode
                        )
                        AppSettingsToggleRow(
                            icon: "bell.badge",
                            title: "显示提醒标识",
                            subtitle: "临近提醒时在任务旁展示提示。",
                            isOn: $showReminderBadge
                        )
                        TodoSettingsValuePickerRow(
                            icon: "timer",
                            title: "即将到期",
                            subtitle: "距离提醒多少分钟内显示临近状态。",
                            selection: $dueSoonMinutes,
                            options: [5, 15, 30, 60],
                            titleForValue: { $0 == 60 ? "1 小时" : "\($0) 分钟" },
                            showsDivider: false
                        )
                    }
                }
                .padding(AppSpacing.xxl)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 620, height: 680)
        .background(AppColor.pageBackground)
        .preferredColorScheme(.light)
    }

    private var sheetHeader: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.accent)
                .frame(width: 38, height: 38)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                        .fill(AppColor.accentSoft)
                }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("待办设置")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("管理灵动岛待办卡片的显示、筛选、排序与提醒。")
                    .font(AppTypography.pageSubtitle)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button("完成") {
                dismiss()
            }
            .buttonStyle(AppButtonStyle(role: .primary))
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.top, AppSpacing.xxl)
        .padding(.bottom, AppSpacing.lg)
    }
}

private struct TodoSettingsStepperRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var showsDivider = true

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            showsDivider: showsDivider
        ) {
            Stepper(value: $value, in: range) {
                Text("\(value) 项")
                    .font(AppTypography.control.monospacedDigit())
                    .foregroundStyle(AppColor.textBody)
                    .frame(minWidth: 46, alignment: .trailing)
            }
            .fixedSize()
        }
    }
}

private struct TodoSettingsRawPickerRow<Value>: View where Value: RawRepresentable & CaseIterable & Hashable, Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selection: String
    let values: Value.AllCases
    var showsDivider = true

    var body: some View {
        TodoSettingsValuePickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            selection: $selection,
            options: values.map(\.rawValue),
            titleForValue: { rawValue in
                values.first(where: { $0.rawValue == rawValue }).map(displayTitle) ?? rawValue
            },
            showsDivider: showsDivider
        )
    }

    private func displayTitle(for value: Value) -> String {
        switch value {
        case let range as TodoDefaultRange:
            range.title
        case let sort as TodoSortMode:
            sort.title
        case let color as TodoHighlightColor:
            color.title
        default:
            String(describing: value)
        }
    }
}

private struct TodoSettingsValuePickerRow<Value: Hashable>: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var selection: Value
    let options: [Value]
    let titleForValue: (Value) -> String
    var showsDivider = true

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            showsDivider: showsDivider
        ) {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { value in
                    Text(titleForValue(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 190)
        }
    }
}

private extension TodoTaskDraft {
    var reminderCreationRequest: ReminderCreationRequest {
        let dueTime = dueTime ?? date
        return ReminderCreationRequest(
            title: title,
            notes: notes,
            hasDueDate: true,
            dueDate: date,
            hasDueTime: self.dueTime != nil,
            dueTime: dueTime,
            hasAlarm: hasAlarm,
            location: location,
            tagsText: ""
        )
    }
}

struct TodoDateStripView: View {
    let days: [TodoDayItem]
    let onSelect: (Date) -> Void

    private var selectedDayID: Date? {
        days.first(where: \.isSelected)?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: AppSpacing.sm) {
                    ForEach(days) { item in
                        TodoDateCardView(item: item) {
                            onSelect(item.date)
                        }
                        .frame(width: TodoStyle.dateCardWidth)
                        .id(item.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .onAppear {
                scrollToSelectedDay(using: proxy, animated: false)
            }
            .onChange(of: selectedDayID) { _, _ in
                scrollToSelectedDay(using: proxy, animated: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func scrollToSelectedDay(using proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedDayID else { return }

        if animated {
            withAnimation(AppMotion.standard) {
                proxy.scrollTo(selectedDayID, anchor: .center)
            }
        } else {
            proxy.scrollTo(selectedDayID, anchor: .center)
        }
    }
}

struct TodoDateCardView: View {
    let item: TodoDayItem
    let onSelect: () -> Void

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text(Self.monthFormatter.string(from: item.date))
                        .font(AppTypography.caption)
                        .foregroundStyle(TodoStyle.secondaryText)

                    Spacer(minLength: AppSpacing.xs)

                    Text("\(item.taskCount)")
                        .font(AppTypography.caption)
                        .foregroundStyle(item.taskCount > 0 ? AppColor.accent : TodoStyle.mutedText)
                }

                Text(Self.dayFormatter.string(from: item.date))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TodoStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Text(Self.weekdayFormatter.string(from: item.date))
                    .font(AppTypography.supporting)
                    .foregroundStyle(TodoStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .frame(height: TodoStyle.dateCardHeight)
            .background {
                RoundedRectangle(cornerRadius: TodoStyle.dateCardRadius, style: .continuous)
                    .fill(item.isSelected ? TodoStyle.selectedDateBackground : TodoStyle.cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: TodoStyle.dateCardRadius, style: .continuous)
                            .stroke(item.isSelected ? AppColor.accentBorder : AppColor.border, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: TodoStyle.dateCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(AppMotion.standard, value: item.isSelected)
    }
}

struct TodoTaskListView: View {
    @ObservedObject var model: TodoViewModel
    let onToggleCompletion: (TodoTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("任务列表")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(TodoStyle.primaryText)
                    Text(dayTitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(TodoStyle.secondaryText)
                }

                Spacer()

                Text("\(model.selectedTasks.count)")
                    .font(AppTypography.control)
                    .foregroundStyle(TodoStyle.secondaryText)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.controlFill)
                    }
            }

            if model.selectedTasks.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "这一天还没有任务",
                    message: "从右上角新建一项，让计划保持简单。"
                )
            } else {
                LazyVStack(spacing: AppSpacing.xs) {
                    ForEach(model.selectedTasks) { task in
                        TodoTaskRowView(
                            task: task,
                            isMultiSelectMode: model.isMultiSelectMode,
                            isSelected: model.selectedTaskIDs.contains(task.id),
                            onToggleCompletion: { onToggleCompletion(task) },
                            onToggleSelection: { model.toggleSelection(for: task.id) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(AppMotion.standard, value: model.selectedTasks)
            }
        }
    }

    private var dayTitle: String {
        Calendar.current.isDateInToday(model.selectedDate) ? "今天" : Self.dayFormatter.string(from: model.selectedDate)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

struct TodoTaskRowView: View {
    let task: TodoTask
    let isMultiSelectMode: Bool
    let isSelected: Bool
    let onToggleCompletion: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Button(action: isMultiSelectMode ? onToggleSelection : onToggleCompletion) {
                ZStack {
                    Circle()
                        .fill(circleFill)
                        .frame(width: 22, height: 22)

                    Circle()
                        .stroke(circleStroke, lineWidth: 1.2)
                        .frame(width: 22, height: 22)

                    if task.isCompleted || isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(task.isCompleted ? .white : TodoStyle.blue)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(task.isCompleted ? TodoStyle.secondaryText : TodoStyle.primaryText)
                    .strikethrough(task.isCompleted, color: TodoStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                if !taskSecondaryText.isEmpty {
                    Text(taskSecondaryText)
                        .font(AppTypography.supporting)
                        .foregroundStyle(TodoStyle.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(isSelected ? AppColor.accentSoft : AppColor.controlFill.opacity(0.55))
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous))
        .animation(AppMotion.standard, value: task.isCompleted)
        .animation(AppMotion.quick, value: isSelected)
    }

    private var circleFill: Color {
        if task.isCompleted {
            return TodoStyle.blue
        }
        if isSelected {
            return TodoStyle.selectedDateBackground
        }
        return TodoStyle.checkFill
    }

    private var circleStroke: Color {
        isSelected || task.isCompleted ? TodoStyle.blue.opacity(0.55) : Color.clear
    }

    private var taskSecondaryText: String {
        var pieces: [String] = []
        if !task.notes.isEmpty {
            pieces.append(task.notes)
        }
        if let dueTime = task.dueTime {
            pieces.append("提醒 \(Self.timeFormatter.string(from: dueTime))")
        } else if task.hasAlarm {
            pieces.append("提醒")
        }
        if !task.location.isEmpty {
            pieces.append(task.location)
        }
        return pieces.joined(separator: " · ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct NewTodoSheetView: View {
    private enum TimeOption: String, CaseIterable, Identifiable {
        case morning
        case noon
        case afternoon
        case evening
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .morning: "早上"
            case .noon: "中午"
            case .afternoon: "下午"
            case .evening: "晚上"
            case .custom: "自定义"
            }
        }

        var timeComponents: (hour: Int, minute: Int)? {
            switch self {
            case .morning: (9, 0)
            case .noon: (12, 0)
            case .afternoon: (17, 0)
            case .evening: (21, 0)
            case .custom: nil
            }
        }
    }

    @State private var title = ""
    @State private var notes = ""
    @State private var date: Date
    @State private var yearText: String
    @State private var monthText: String
    @State private var dayText: String
    @State private var selectedTimeOption: TimeOption = .morning
    @State private var customTime: Date
    @State private var hourText: String
    @State private var minuteText: String
    @State private var isProgrammaticallyUpdatingTimeFields = false
    @State private var hasAlarm = false
    @State private var location = ""
    @FocusState private var isTitleFocused: Bool

    let onCancel: () -> Void
    let onSave: (TodoTaskDraft) -> Void

    init(initialDate: Date, onCancel: @escaping () -> Void, onSave: @escaping (TodoTaskDraft) -> Void) {
        let normalizedDate = Calendar.current.startOfDay(for: initialDate)
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: normalizedDate)
        _date = State(initialValue: normalizedDate)
        _yearText = State(initialValue: String(dateComponents.year ?? 2026))
        _monthText = State(initialValue: String(dateComponents.month ?? 1))
        _dayText = State(initialValue: String(dateComponents.day ?? 1))
        _customTime = State(initialValue: Self.time(on: normalizedDate, hour: 9, minute: 0))
        _hourText = State(initialValue: "09")
        _minuteText = State(initialValue: "00")
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    taskContentSection
                    scheduleSection
                    reminderDetailsSection
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.lg)
            }
            .scrollIndicators(.never)

            sheetFooter
        }
        .frame(width: 560, height: 620)
        .background(AppColor.pageBackground)
        .onAppear {
            isTitleFocused = true
        }
    }

    private var sheetHeader: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checklist")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.accent)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(AppColor.accentSoft)
                }

            Text("新建待办")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(TodoStyle.primaryText)

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(AppButtonStyle(role: .icon))
            .help("关闭")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.vertical, AppSpacing.lg)
    }

    private var taskContentSection: some View {
        sheetSection {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("任务内容")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textTertiary)

                TextField("输入待办标题", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TodoStyle.primaryText)
                    .focused($isTitleFocused)

                Rectangle()
                    .fill(AppColor.divider)
                    .frame(height: 1)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $notes)
                        .font(AppTypography.body)
                        .foregroundStyle(TodoStyle.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(height: 48)
                        .padding(.horizontal, -5)
                        .padding(.vertical, -7)

                    if notes.isEmpty {
                        Text("添加备注（可选）")
                            .font(AppTypography.body)
                            .foregroundStyle(TodoStyle.secondaryText)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        sheetSection {
            sheetRow(systemName: "calendar", title: "日期") {
                HStack(spacing: AppSpacing.xs) {
                    numericField($yearText, placeholder: "YYYY", width: 70, maxLength: 4, isInvalid: dateValidationMessage != nil) {
                        updateDateFromSegments()
                    }

                    dateTimeSeparator("/")

                    numericField($monthText, placeholder: "MM", width: 42, maxLength: 2, isInvalid: dateValidationMessage != nil) {
                        updateDateFromSegments()
                    }

                    dateTimeSeparator("/")

                    numericField($dayText, placeholder: "DD", width: 42, maxLength: 2, isInvalid: dateValidationMessage != nil) {
                        updateDateFromSegments()
                    }
                }
            }

            if let dateValidationMessage {
                validationMessage(dateValidationMessage)
            }

            sectionDivider

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sheetRow(systemName: "clock", title: "时间") {
                    HStack(spacing: AppSpacing.xs) {
                        numericField($hourText, placeholder: "HH", width: 44, maxLength: 2, isInvalid: timeValidationMessage != nil) {
                            updateTimeFromSegments()
                        }

                        dateTimeSeparator(":")

                        numericField($minuteText, placeholder: "MM", width: 44, maxLength: 2, isInvalid: timeValidationMessage != nil) {
                            updateTimeFromSegments()
                        }
                    }
                }

                if let timeValidationMessage {
                    validationMessage(timeValidationMessage)
                }

                HStack(spacing: AppSpacing.sm) {
                    ForEach(TimeOption.allCases) { option in
                        timeOptionButton(option)
                    }
                }
            }
        }
    }

    private var reminderDetailsSection: some View {
        sheetSection {
            sheetRow(systemName: "alarm", title: "添加闹钟") {
                Toggle("", isOn: $hasAlarm)
                    .labelsHidden()
                    .toggleStyle(AppSwitchToggleStyle())
            }

            sectionDivider

            sheetRow(systemName: "location", title: "位置") {
                TextField("添加位置", text: $location)
                    .textFieldStyle(.plain)
                    .font(AppTypography.control)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(width: 210, height: AppControlStyle.regularHeight)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.controlFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(AppColor.border, lineWidth: 1)
                            }
                    }
            }
        }
    }

    private var sheetFooter: some View {
        HStack(spacing: AppSpacing.sm) {
            Spacer()

            Button("取消", action: onCancel)
                .buttonStyle(AppButtonStyle(role: .quiet))

            Button {
                onSave(
                    TodoTaskDraft(
                        title: title,
                        notes: notes,
                        date: date,
                        dueTime: resolvedDueTime,
                        hasAlarm: hasAlarm,
                        location: location
                    )
                )
            } label: {
                Label("保存待办", systemImage: "checkmark")
            }
            .buttonStyle(AppButtonStyle(role: .primary))
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.vertical, AppSpacing.md)
        .background(AppColor.elevatedSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func sheetSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md, content: content)
            .padding(14)
            .appSurface(.elevated, radius: AppRadius.card)
    }

    private func sheetRow<Content: View>(
        systemName: String,
        title: String,
        @ViewBuilder accessory: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(TodoStyle.blue)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(AppColor.accentSoft)
                }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TodoStyle.primaryText)

            Spacer(minLength: 16)

            accessory()
        }
        .frame(minHeight: 36)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(height: 1)
            .padding(.leading, 42)
    }

    private func dateTimeSeparator(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.control.monospacedDigit())
            .foregroundStyle(TodoStyle.secondaryText)
    }

    private func numericField(
        _ text: Binding<String>,
        placeholder: String,
        width: CGFloat,
        maxLength: Int,
        isInvalid: Bool,
        onValidChange: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(TodoInlineFieldStyle(width: width, isInvalid: isInvalid))
            .multilineTextAlignment(.center)
            .onChange(of: text.wrappedValue) { _, newValue in
                let sanitized = TodoDateTimeInputParser.digitsOnly(newValue, maxLength: maxLength)
                if sanitized != newValue {
                    text.wrappedValue = sanitized
                    return
                }
                onValidChange()
            }
    }

    private func validationMessage(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.red.opacity(0.78))
        .padding(.leading, 42)
    }

    private func timeOptionButton(_ option: TimeOption) -> some View {
        Button {
            selectedTimeOption = option
            syncTimeText(for: option)
        } label: {
            VStack(spacing: 2) {
                Text(option.title)
                    .font(AppTypography.caption)
                Text(timeTitle(for: option))
                    .font(AppTypography.control.monospacedDigit())
            }
            .foregroundStyle(selectedTimeOption == option ? AppColor.accent : TodoStyle.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(selectedTimeOption == option ? AppColor.accentSoft : AppColor.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(
                                selectedTimeOption == option ? AppColor.accentBorder : AppColor.border,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private var resolvedDueTime: Date {
        if selectedTimeOption == .custom {
            return Self.time(on: date, from: customTime)
        }

        guard let components = selectedTimeOption.timeComponents else {
            return Self.time(on: date, from: customTime)
        }

        return Self.time(on: date, hour: components.hour, minute: components.minute)
    }

    private func timeTitle(for option: TimeOption) -> String {
        guard let components = option.timeComponents else {
            return Self.timeFormatter.string(from: customTime)
        }
        return String(format: "%02d:%02d", components.hour, components.minute)
    }

    private func updateDateFromSegments() {
        guard let parsedDate = Self.parseDate(year: yearText, month: monthText, day: dayText) else { return }
        date = Calendar.current.startOfDay(for: parsedDate)
    }

    private func updateTimeFromSegments() {
        guard !isProgrammaticallyUpdatingTimeFields else { return }
        guard let parsedTime = Self.parseTime(hour: hourText, minute: minuteText, on: date) else { return }

        customTime = parsedTime
        selectedTimeOption = .custom
    }

    private func syncTimeText(for option: TimeOption) {
        if let components = option.timeComponents {
            customTime = Self.time(on: date, hour: components.hour, minute: components.minute)
            syncTimeSegments(hour: components.hour, minute: components.minute)
        } else {
            let components = Calendar.current.dateComponents([.hour, .minute], from: customTime)
            syncTimeSegments(hour: components.hour ?? 9, minute: components.minute ?? 0)
        }
    }

    private func syncTimeSegments(hour: Int, minute: Int) {
        isProgrammaticallyUpdatingTimeFields = true
        hourText = String(format: "%02d", hour)
        minuteText = String(format: "%02d", minute)
        DispatchQueue.main.async {
            isProgrammaticallyUpdatingTimeFields = false
        }
    }

    private static func parseDate(year: String, month: String, day: String) -> Date? {
        TodoDateTimeInputParser.parseDate(year: year, month: month, day: day)
    }

    private static func parseTime(hour: String, minute: String, on date: Date) -> Date? {
        TodoDateTimeInputParser.parseTime(hour: hour, minute: minute, on: date)
    }

    private static func dateText(from date: Date) -> String {
        dateTextFormatter.string(from: date)
    }

    private static func time(on date: Date, from time: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return Self.time(
            on: date,
            hour: components.hour ?? 9,
            minute: components.minute ?? 0
        )
    }

    private static func time(on date: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateTextFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    private var dateValidationMessage: String? {
        Self.parseDate(year: yearText, month: monthText, day: dayText) == nil ? "请输入有效日期" : nil
    }

    private var timeValidationMessage: String? {
        Self.parseTime(hour: hourText, minute: minuteText, on: date) == nil ? "请输入 00:00-23:59 的时间" : nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dateValidationMessage == nil
            && timeValidationMessage == nil
    }

    private func normalizeDateText() {
        guard let parsedDate = Self.parseDate(year: yearText, month: monthText, day: dayText) else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: parsedDate)
        date = parsedDate
        yearText = String(components.year ?? 2026)
        monthText = String(components.month ?? 1)
        dayText = String(components.day ?? 1)
    }
}

private struct TodoInlineFieldStyle: TextFieldStyle {
    let width: CGFloat
    var isInvalid = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 18, weight: .semibold).monospacedDigit())
            .foregroundStyle(isInvalid ? Color.red.opacity(0.86) : TodoStyle.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(width: width, height: AppControlStyle.regularHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(AppColor.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(isInvalid ? Color.red.opacity(0.42) : AppColor.border, lineWidth: 1)
                    }
            }
    }
}
