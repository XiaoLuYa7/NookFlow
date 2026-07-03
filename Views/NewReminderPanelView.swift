import CoreLocation
import SwiftUI

final class NewReminderDraft: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var title = ""
    @Published var notes = ""
    @Published var hasDueDate = true
    @Published var dueDate = Date()
    @Published var hasDueTime = false
    @Published var dueTime = Date()
    @Published var hasAlarm = false
    @Published var location = ""
    @Published var tagsText = ""
    @Published var isResolvingLocation = false

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isWaitingForLocationAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var request: ReminderCreationRequest {
        ReminderCreationRequest(
            title: title,
            notes: notes,
            hasDueDate: hasDueDate,
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            dueTime: dueTime,
            hasAlarm: hasAlarm,
            location: location,
            tagsText: tagsText
        )
    }

    func requestCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            location = "定位服务已关闭"
            return
        }

        isResolvingLocation = true
        location = "定位中..."

        switch locationManager.authorizationStatus {
        case .notDetermined:
            isWaitingForLocationAuthorization = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            isResolvingLocation = false
            location = "定位未授权"
        @unknown default:
            isResolvingLocation = false
            location = "定位不可用"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isWaitingForLocationAuthorization else { return }
        isWaitingForLocationAuthorization = false

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isResolvingLocation = false
            location = "定位未授权"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finishResolvingLocation(with: "当前位置")
            return
        }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let placemark = placemarks?.first
            let name = [
                placemark?.subLocality,
                placemark?.locality,
                placemark?.administrativeArea
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .removingDuplicates()
            .joined(separator: " ")

            self?.finishResolvingLocation(with: name.isEmpty ? "当前位置" : name)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishResolvingLocation(with: "定位失败")
    }

    private func finishResolvingLocation(with name: String) {
        DispatchQueue.main.async {
            self.isResolvingLocation = false
            self.location = name
        }
    }
}

struct NewReminderPanelView: View {
    static let panelSize = CGSize(width: 500, height: 318)

    @ObservedObject var draft: NewReminderDraft
    let onCancel: () -> Void
    let onAdd: (ReminderCreationRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 14) {
                titleAndNotes
                reminderControls
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.94))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 20, height: 20)

            Text("新增待办")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.90))

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var titleAndNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("名称", text: $draft.title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))
                .textFieldStyle(.plain)

            notesEditor

            TextField("添加标签，用空格或逗号分隔", text: $draft.tagsText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
                .textFieldStyle(.plain)
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft.notes)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, -5)
                .padding(.vertical, -7)

            if draft.notes.isEmpty {
                Text("备注")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 76)
    }

    private var reminderControls: some View {
        HStack(spacing: 8) {
            ReminderDatePickerChip(
                systemName: "calendar",
                title: dateChipTitle,
                inactiveTitle: "添加日期",
                isOn: $draft.hasDueDate,
                selection: $draft.dueDate,
                displayedComponents: .date
            )

            ReminderDatePickerChip(
                systemName: "clock",
                title: draft.hasDueTime ? timeChipTitle : "添加时间",
                inactiveTitle: "添加时间",
                isOn: $draft.hasDueTime,
                selection: $draft.dueTime,
                displayedComponents: .hourAndMinute
            )

            ReminderToggleChip(
                systemName: "alarm",
                title: "闹钟",
                isOn: alarmBinding
            )

            ReminderLocationChip(
                systemName: "location.fill",
                title: locationChipTitle,
                isResolving: draft.isResolvingLocation,
                action: { draft.requestCurrentLocation() }
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("将同步到 macOS 提醒事项")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))

            Spacer()

            Button("取消", action: onCancel)
                .buttonStyle(ReminderPanelButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)

            Button("添加") {
                onAdd(draft.request)
            }
            .buttonStyle(ReminderPanelButtonStyle(kind: .primary, isEnabled: draft.canSubmit))
            .disabled(!draft.canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var dateChipTitle: String {
        if Calendar.current.isDateInToday(draft.dueDate) {
            return "今天"
        }

        return Self.fixedDateFormatter.string(from: draft.dueDate)
    }

    private var timeChipTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: draft.dueTime)
    }

    private var locationChipTitle: String {
        draft.location.isEmpty ? "添加位置" : draft.location
    }

    private var alarmBinding: Binding<Bool> {
        Binding(
            get: { draft.hasAlarm },
            set: { newValue in
                draft.hasAlarm = newValue

                guard newValue else { return }
                draft.hasDueDate = true

                if !draft.hasDueTime {
                    draft.hasDueTime = true
                    draft.dueTime = Self.defaultAlarmTime(on: draft.dueDate)
                }
            }
        )
    }

    private static let fixedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static func defaultAlarmTime(on date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}

private struct ReminderDatePickerChip: View {
    let systemName: String
    let title: String
    let inactiveTitle: String
    @Binding var isOn: Bool
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents

    @State private var isShowingPicker = false
    @State private var isShowingCustomPicker = false
    @State private var customInput = ""

    var body: some View {
        Button {
            preparePickerState()
            isOn = true
            isShowingPicker = true
        } label: {
            chipContent(title: isOn ? title : inactiveTitle, opacity: isOn ? 0.92 : 0.58)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            suggestionPopover
                .padding(isShowingCustomPicker && isDateMode ? 10 : 14)
                .frame(width: popoverWidth, alignment: .leading)
                .background(Color.black.opacity(0.94))
                .preferredColorScheme(.dark)
        }
    }

    private var suggestionPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isShowingCustomPicker {
                customEditor
            } else {
                Text("建议")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .padding(.horizontal, 2)

                if isDateMode {
                    ForEach(dateSuggestions) { suggestion in
                        suggestionButton(
                            systemName: "calendar",
                            title: suggestion.title,
                            subtitle: suggestion.subtitle
                        ) {
                            selection = suggestion.date
                            customInput = customInputText(for: suggestion.date)
                            isOn = true
                            isShowingPicker = false
                        }
                    }
                } else {
                    ForEach(timeSuggestions) { suggestion in
                        suggestionButton(
                            systemName: "clock",
                            title: suggestion.title,
                            subtitle: suggestion.subtitle
                        ) {
                            let date = timeDate(hour: suggestion.hour, minute: suggestion.minute)
                            selection = date
                            customInput = customInputText(for: date)
                            isOn = true
                            isShowingPicker = false
                        }
                    }
                }

                if isDateMode {
                    Divider()
                        .overlay(Color.white.opacity(0.09))
                        .padding(.vertical, 2)

                    customEntry
                }
            }
        }
    }

    private var customEntry: some View {
        Button {
            isShowingCustomPicker = true
        } label: {
            suggestionRow(
                systemName: "calendar",
                title: "自定义...",
                subtitle: "使用日历挑选日期"
            )
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDateMode {
                ReminderInlineCalendarPicker(selection: $selection) { newValue in
                    customInput = customInputText(for: newValue)
                    isOn = true
                }
            } else {
                TextField("例如 09:00", text: $customInput)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    }
                    .onSubmit {
                        applyCustomInputIfPossible()
                    }

                customPicker
            }
        }
    }

    @ViewBuilder
    private var customPicker: some View {
        if !isDateMode {
            DatePicker("", selection: $selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .onChange(of: selection) { _, newValue in
                    customInput = customInputText(for: newValue)
                    isOn = true
                }
        }
    }

    private var popoverWidth: CGFloat {
        if isShowingCustomPicker && isDateMode {
            return 226
        }

        return isDateMode ? 290 : 250
    }

    private func suggestionButton(
        systemName: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            suggestionRow(systemName: systemName, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private func suggestionRow(systemName: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.52))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.90))

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(height: 38)
        .contentShape(Rectangle())
    }

    private func chipContent(title: String, opacity: Double) -> some View {
        let dateMinWidth: CGFloat? = title == "今天" ? 70 : 126

        return HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color.white.opacity(opacity))
        .padding(.horizontal, 11)
        .frame(minWidth: isDateMode ? dateMinWidth : nil)
        .frame(height: 30)
        .background {
            Capsule()
                .fill(Color.white.opacity(isOn ? 0.13 : 0.08))
        }
        .contentShape(Capsule())
    }

    private var isDateMode: Bool {
        displayedComponents == .date
    }

    private var dateSuggestions: [ReminderDateSuggestion] {
        [
            ReminderDateSuggestion(title: "今天", date: startOfDay(Date())),
            ReminderDateSuggestion(title: "明天", date: dateByAddingDays(1)),
            ReminderDateSuggestion(title: "本周末", date: upcomingWeekendDate()),
            ReminderDateSuggestion(title: "下周", date: nextWeekDate())
        ]
    }

    private var timeSuggestions: [ReminderTimeSuggestion] {
        [
            ReminderTimeSuggestion(title: "09:00", subtitle: "上午", hour: 9, minute: 0),
            ReminderTimeSuggestion(title: "12:00", subtitle: "中午", hour: 12, minute: 0),
            ReminderTimeSuggestion(title: "15:00", subtitle: "下午", hour: 15, minute: 0),
            ReminderTimeSuggestion(title: "18:00", subtitle: "晚上", hour: 18, minute: 0),
            ReminderTimeSuggestion(title: "21:00", subtitle: "夜间", hour: 21, minute: 0)
        ]
    }

    private func preparePickerState() {
        isShowingCustomPicker = false
        customInput = customInputText(for: selection)
    }

    private func applyCustomInputIfPossible() {
        guard !customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if isDateMode, let date = Self.parseDate(customInput) {
            selection = date
            isOn = true
        } else if !isDateMode, let date = Self.parseTime(customInput) {
            selection = date
            isOn = true
        }
    }

    private func customInputText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = isDateMode ? "yyyy/MM/dd" : "HH:mm"
        return formatter.string(from: date)
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func dateByAddingDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startOfDay(Date())) ?? Date()
    }

    private func upcomingWeekendDate() -> Date {
        let calendar = Calendar.current
        let today = startOfDay(Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSaturday = (7 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: today) ?? today
    }

    private func nextWeekDate() -> Date {
        let calendar = Calendar.current
        let today = startOfDay(Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilMonday = (2 - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: today) ?? today
    }

    private func timeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: selection
        ) ?? Date()
    }

    private static func parseDate(_ input: String) -> Date? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "-", with: "/")
            .replacingOccurrences(of: ".", with: "/")

        let calendar = Calendar.current
        let parts = normalized
            .split(separator: "/")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        if parts.count == 2 {
            let year = calendar.component(.year, from: Date())
            return date(year: year, month: parts[0], day: parts[1], calendar: calendar)
        }

        if parts.count == 3 {
            return date(year: parts[0], month: parts[1], day: parts[2], calendar: calendar)
        }

        return nil
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard
            (1...12).contains(month),
            let monthRangeDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let dayRange = calendar.range(of: .day, in: .month, for: monthRangeDate),
            dayRange.contains(day)
        else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func parseTime(_ input: String) -> Date? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")

        let parts = normalized
            .split(separator: ":")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard
            let hour = parts.first,
            (0...23).contains(hour)
        else {
            return nil
        }

        let minute = parts.count > 1 ? parts[1] : 0
        guard (0...59).contains(minute) else { return nil }

        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }
}

private struct ReminderDateSuggestion: Identifiable {
    let title: String
    let date: Date

    var id: String { title }

    var subtitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

private struct ReminderTimeSuggestion: Identifiable {
    let title: String
    let subtitle: String
    let hour: Int
    let minute: Int

    var id: String { title }
}

private struct ReminderInlineCalendarPicker: View {
    @Binding var selection: Date
    let onSelect: (Date) -> Void

    @State private var visibleMonth = Calendar.current.startOfMonth(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.fixed(25), spacing: 4, alignment: .center), count: 7)
    private let weekdayTitles = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(monthTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))

                Spacer(minLength: 0)

                Button(action: { moveMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.52))
                .handCursor()

                Circle()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: 7, height: 7)

                Button(action: { moveMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.52))
                .handCursor()
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.46))
                        .frame(width: 25, height: 16)
                }

                ForEach(calendarDays) { day in
                    Button {
                        selection = day.date
                        visibleMonth = calendar.startOfMonth(for: day.date)
                        onSelect(day.date)
                    } label: {
                        Text("\(calendar.component(.day, from: day.date))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(dayTextColor(day))
                            .frame(width: 25, height: 22)
                            .background {
                                if calendar.isDate(day.date, inSameDayAs: selection) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.blue.opacity(0.90))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
            }
        }
        .frame(width: 206, alignment: .leading)
        .onAppear {
            visibleMonth = calendar.startOfMonth(for: selection)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: visibleMonth)
    }

    private var calendarDays: [InlineCalendarDay] {
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: visibleMonth),
            let firstDate = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth))
        else {
            return []
        }

        let leadingCount = calendar.component(.weekday, from: firstDate) - 1
        var days: [InlineCalendarDay] = []

        if leadingCount > 0 {
            for offset in stride(from: leadingCount, to: 0, by: -1) {
                if let date = calendar.date(byAdding: .day, value: -offset, to: firstDate) {
                    days.append(InlineCalendarDay(date: date, isCurrentMonth: false))
                }
            }
        }

        for day in monthRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDate) {
                days.append(InlineCalendarDay(date: date, isCurrentMonth: true))
            }
        }

        while days.count < 42 {
            guard let lastDate = days.last?.date,
                  let nextDate = calendar.date(byAdding: .day, value: 1, to: lastDate) else {
                break
            }
            days.append(InlineCalendarDay(date: nextDate, isCurrentMonth: false))
        }

        return days
    }

    private func moveMonth(by value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func dayTextColor(_ day: InlineCalendarDay) -> Color {
        if calendar.isDate(day.date, inSameDayAs: selection) {
            return Color.white
        }

        return day.isCurrentMonth ? Color.white.opacity(0.86) : Color.white.opacity(0.25)
    }
}

private struct InlineCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}

private struct ReminderToggleChip: View {
    let systemName: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(isOn ? 0.92 : 0.58))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(Color.white.opacity(isOn ? 0.13 : 0.08))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

private struct ReminderLocationChip: View {
    let systemName: String
    let title: String
    let isResolving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isResolving {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                }
            }
            .foregroundStyle(Color.white.opacity(title == "添加位置" ? 0.58 : 0.86))
            .padding(.horizontal, 11)
            .frame(maxWidth: 128)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.08))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private struct ReminderPanelButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    var kind: Kind
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(foregroundOpacity))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(Capsule())
    }

    private var foregroundOpacity: Double {
        isEnabled ? 0.94 : 0.38
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Color.white.opacity(isEnabled ? (isPressed ? 0.20 : 0.16) : 0.07)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.12 : 0.08)
        }
    }
}
