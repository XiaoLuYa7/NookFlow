import SwiftUI

struct WeatherNotificationSettings: Codable, Equatable {
    var isEnabled = true
    var checkFrequency = "30 分钟"
    var notifyCooldown = "2 小时"
    var severeWeatherTypes: Set<String> = [
        "强降雨 / 积水",
        "大风 / 台风",
        "高温 / 干热",
        "低温 / 雨雪冰冻",
        "雷电 / 冰雹",
        "其他严重天气"
    ]
    var rainTriggers: Set<String> = [
        "今天有雨",
        "一小时内可能下雨",
        "降雨概率超过阈值"
    ]
    var rainProbabilityThreshold = "30%"
}

struct DeviceNotificationSettings: Codable, Equatable {
    var isEnabled = false
    var lowBatteryEnabled = true
    var lowBatteryThreshold = "30%"
    var fullChargeReminderEnabled = true
    var fullChargeThreshold = "95%"
    var performanceAlertEnabled = true
    var performanceThreshold = "70%"
    var storageAlertEnabled = true
    var storageThreshold = "20 GB"
    var networkStatusAlertEnabled = true
}

struct DailyCareNotificationSettings: Codable, Equatable {
    var isEnabled = false
    var waterReminderEnabled = false
    var waterInterval = "60 分钟"
    var waterGoal = "8 杯"
    var waterStartTime = "09:00"
    var waterEndTime = "22:00"
    var waterProgress = 0
    var sitReminderEnabled = false
    var sitInterval = "60 分钟"
    var sitStartTime = "09:00"
    var sitEndTime = "18:00"
    var sleepReminderEnabled = true
    var targetSleepTime = "23:30"
    var preSleepLeadTime = "提前 30 分钟"
    var weekendScheduleEnabled = false
    var weekendTargetSleepTime = "00:30"
    var weekendPreSleepLeadTime = "提前 30 分钟"
}

@MainActor
final class NotificationSettingsViewModel: ObservableObject {
    static let shared = NotificationSettingsViewModel()

    @Published var weather: WeatherNotificationSettings { didSet { settingsDidChange() } }
    @Published var device: DeviceNotificationSettings { didSet { settingsDidChange() } }
    @Published var dailyCare: DailyCareNotificationSettings { didSet { settingsDidChange() } }

    let weatherCheckFrequencies = ["30 分钟", "60 分钟", "120 分钟"]
    let weatherCooldowns = ["1 小时", "2 小时", "6 小时", "12 小时"]
    let severeWeatherOptions = ["强降雨 / 积水", "大风 / 台风", "高温 / 干热", "低温 / 雨雪冰冻", "雷电 / 冰雹", "其他严重天气"]
    let rainTriggerOptions = ["今天有雨", "一小时内可能下雨", "降雨概率超过阈值"]
    let rainProbabilityOptions = ["15%", "30%", "60%", "80%"]
    let lowBatteryThresholds = ["10%", "20%", "30%", "35%", "40%"]
    let fullChargeThresholds = ["80%", "90%", "95%"]
    let performanceThresholds = ["60%", "70%", "80%", "90%", "95%"]
    let storageThresholds = ["10 GB", "20 GB", "30 GB", "50 GB", "100 GB"]
    let careIntervals = ["30 分钟", "45 分钟", "60 分钟", "90 分钟", "120 分钟"]
    let waterGoals = ["4 杯", "6 杯", "8 杯", "10 杯", "12 杯"]
    let timeOptions = ["06:00", "07:00", "08:00", "09:00", "18:00", "22:00", "23:00", "23:30", "00:30"]
    let preSleepOptions = ["提前 15 分钟", "提前 30 分钟", "提前 45 分钟", "提前 60 分钟"]

    private let defaults: UserDefaults
    private var isLoading = true

    private struct PersistedSettings: Codable {
        var weather: WeatherNotificationSettings
        var device: DeviceNotificationSettings
        var dailyCare: DailyCareNotificationSettings
    }

    private static let persistedSettingsKey = "notifications.preferences.v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.persistedSettingsKey),
           let saved = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            weather = saved.weather
            device = saved.device
            dailyCare = saved.dailyCare
        } else {
            weather = WeatherNotificationSettings()
            device = DeviceNotificationSettings()
            dailyCare = DailyCareNotificationSettings()
        }

        isLoading = false
    }

    var waterGoalCount: Int {
        Int(dailyCare.waterGoal.replacingOccurrences(of: " 杯", with: "")) ?? 8
    }

    func reset() {
        isLoading = true
        withAnimation(.easeInOut(duration: 0.18)) {
            weather = WeatherNotificationSettings()
            device = DeviceNotificationSettings()
            dailyCare = DailyCareNotificationSettings()
        }
        isLoading = false
        persistAndApply()
    }

    func previewNotification() {
        Task {
            _ = await NotificationCoordinator.shared.sendPreviewNotification()
        }
    }

    func toggleSevereWeather(_ option: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if weather.severeWeatherTypes.contains(option) {
                weather.severeWeatherTypes.remove(option)
            } else {
                weather.severeWeatherTypes.insert(option)
            }
        }
    }

    func toggleRainTrigger(_ option: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            if weather.rainTriggers.contains(option) {
                weather.rainTriggers.remove(option)
            } else {
                weather.rainTriggers.insert(option)
            }
        }
    }

    func incrementWaterProgress() {
        dailyCare.waterProgress = min(waterGoalCount, dailyCare.waterProgress + 1)
    }

    func decrementWaterProgress() {
        dailyCare.waterProgress = max(0, dailyCare.waterProgress - 1)
    }

    func resetWaterProgress() {
        dailyCare.waterProgress = 0
    }

    func activateNotifications() {
        NotificationCoordinator.shared.start()
        NotificationCoordinator.shared.preferencesDidChange(requestAuthorization: true)
    }

    private func settingsDidChange() {
        guard !isLoading else { return }
        persistAndApply()
    }

    private func persistAndApply() {
        let payload = PersistedSettings(
            weather: weather,
            device: device,
            dailyCare: dailyCare
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.persistedSettingsKey)
        }
        NotificationCoordinator.shared.preferencesDidChange(requestAuthorization: true)
    }
}

struct NotificationSettingsView: View {
    @StateObject private var model = NotificationSettingsViewModel.shared

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: NotificationStyle.contentMaxWidth) {
            PageHeaderView(
                title: "实时通知",
                subtitle: "分别管理天气、设备状态与日常关怀提醒。",
                icon: "bell.fill"
            ) {
                HStack(spacing: AppSpacing.sm) {
                    Button("预览通知", action: model.previewNotification)
                        .buttonStyle(AppButtonStyle(role: .secondary))
                    Button("重置", action: model.reset)
                        .buttonStyle(AppButtonStyle(role: .quiet))
                }
            }
        } content: {
            Group {
                NotificationStatusStrip(model: model)
                weatherSection
                deviceSection
                dailyCareSection
            }
        }
        .onAppear(perform: model.activateNotifications)
    }

    private var weatherSection: some View {
        NotificationSectionView(
            title: "天气提醒设置",
            footer: "在这里管理天气提醒，包括恶劣天气提醒和日常降雨提醒。",
            isEnabled: model.weather.isEnabled
        ) {
            NotificationToggleRow(
                icon: "cloud.sun.fill",
                title: "天气提醒设置",
                subtitle: "当你所在地区出现你关心的天气情况时提醒你",
                showsProBadge: true,
                isOn: $model.weather.isEnabled
            )

            NotificationActionRow(
                icon: "bell.fill",
                title: "查看提醒示例",
                subtitle: "先看看天气提醒弹出时会显示什么内容",
                buttonTitle: "预览提醒",
                action: model.previewNotification
            )
            .opacity(model.weather.isEnabled ? 1 : 0.56)

            NotificationSegmentedRow(
                icon: "timer",
                title: "天气检查频率",
                subtitle: "设置多久检查一次天气变化；越频繁越及时，也会更耗电",
                options: model.weatherCheckFrequencies,
                selection: $model.weather.checkFrequency
            )
            .opacity(model.weather.isEnabled ? 1 : 0.56)

            NotificationSegmentedRow(
                icon: "bell.fill",
                title: "天气通知频率",
                subtitle: "在这个时间范围内通知过一次后，就先不重复提醒",
                options: model.weatherCooldowns,
                selection: $model.weather.notifyCooldown
            )
            .opacity(model.weather.isEnabled ? 1 : 0.56)

            NotificationMultiSelectGridRow(
                icon: "cloud.heavyrain.fill",
                title: "恶劣天气提醒",
                subtitle: "选择你想收到的恶劣天气类型",
                options: model.severeWeatherOptions,
                selectedOptions: model.weather.severeWeatherTypes,
                action: model.toggleSevereWeather
            )
            .opacity(model.weather.isEnabled ? 1 : 0.56)

            NotificationMultiSelectGridRow(
                icon: "umbrella.fill",
                title: "降雨提醒时机",
                subtitle: "可多选；符合条件时会优先提醒更紧急的情况",
                options: model.rainTriggerOptions,
                selectedOptions: model.weather.rainTriggers,
                action: model.toggleRainTrigger
            )
            .opacity(model.weather.isEnabled ? 1 : 0.56)

            NotificationSegmentedRow(
                icon: "drop.fill",
                title: "降雨概率阈值",
                subtitle: "决定“降雨概率超过阈值”在什么概率时提醒",
                options: model.rainProbabilityOptions,
                selection: $model.weather.rainProbabilityThreshold
            )
            .opacity(model.weather.isEnabled && model.weather.rainTriggers.contains("降雨概率超过阈值") ? 1 : 0.50)
        }
    }

    private var deviceSection: some View {
        NotificationSectionView(
            title: "设备状态提醒",
            footer: "当电量、性能、存储空间或网络状态出现明显变化时提醒你，尽量只在需要时打扰。",
            isEnabled: model.device.isEnabled
        ) {
            NotificationToggleRow(
                icon: "desktopcomputer",
                title: "设备状态提醒",
                subtitle: "统一管理电池、性能、存储空间和网络提醒",
                showsProBadge: true,
                isOn: $model.device.isEnabled
            )

            NotificationToggleRow(
                icon: "battery.25",
                title: "低电量提醒",
                subtitle: "电量过低且未连接电源时提醒你充电",
                isOn: $model.device.lowBatteryEnabled
            )

            NotificationSegmentedRow(
                icon: "battery.25",
                title: "低电量提醒阈值",
                subtitle: "低于这个电量时提醒一次",
                options: model.lowBatteryThresholds,
                selection: $model.device.lowBatteryThreshold
            )

            NotificationToggleRow(
                icon: "bolt.batteryblock.fill",
                title: "充满前提醒",
                subtitle: "充电快满时提醒你，方便决定是否断开电源",
                isOn: $model.device.fullChargeReminderEnabled
            )

            NotificationSegmentedRow(
                icon: "bolt.batteryblock.fill",
                title: "充满前提醒阈值",
                subtitle: "充电达到这个百分比后提醒一次",
                options: model.fullChargeThresholds,
                selection: $model.device.fullChargeThreshold
            )

            NotificationToggleRow(
                icon: "cpu.fill",
                title: "性能占用过高提醒",
                subtitle: "CPU 或内存持续占用较高时提醒你留意",
                isOn: $model.device.performanceAlertEnabled
            )

            NotificationSegmentedRow(
                icon: "cpu.fill",
                title: "高占用提醒阈值",
                subtitle: "连续高于这个比例时提醒",
                options: model.performanceThresholds,
                selection: $model.device.performanceThreshold
            )

            NotificationToggleRow(
                icon: "internaldrive.fill",
                title: "存储空间不足提醒",
                subtitle: "可用空间不足时提醒你及时清理",
                isOn: $model.device.storageAlertEnabled
            )

            NotificationSegmentedRow(
                icon: "internaldrive.fill",
                title: "存储空间提醒阈值",
                subtitle: "可用空间低于这个容量时提醒",
                options: model.storageThresholds,
                selection: $model.device.storageThreshold
            )

            NotificationToggleRow(
                icon: "wifi",
                title: "网络状态变化提醒",
                subtitle: "断网或重新连上网络时及时告诉你",
                isOn: $model.device.networkStatusAlertEnabled
            )
        }
        .opacity(model.device.isEnabled ? 1 : 0.82)
    }

    private var dailyCareSection: some View {
        NotificationSectionView(
            title: "日常关怀",
            footer: "喝水提醒、久坐提醒和睡觉提醒会按你的习惯配置运行，适合希望用实时通知照看日常节奏的用户。",
            isEnabled: model.dailyCare.isEnabled
        ) {
            NotificationToggleRow(
                icon: "heart.fill",
                title: "日常关怀",
                subtitle: "统一管理喝水提醒、久坐提醒、睡前预提醒和睡觉提醒",
                showsProBadge: true,
                isOn: $model.dailyCare.isEnabled
            )

            NotificationToggleRow(
                icon: "drop.fill",
                title: "喝水提醒",
                subtitle: "按间隔提醒你补水，并记录今天已经喝了多少杯",
                isOn: $model.dailyCare.waterReminderEnabled
            )

            NotificationPickerRow(
                icon: "timer",
                title: "喝水提醒间隔",
                subtitle: "决定距离上次喝水多久后再次提醒",
                options: model.careIntervals,
                selection: $model.dailyCare.waterInterval
            )

            NotificationPickerRow(
                icon: "flag.fill",
                title: "每日喝水目标",
                subtitle: "用今天喝了多少杯来衡量补水进度",
                options: model.waterGoals,
                selection: $model.dailyCare.waterGoal
            )

            NotificationTimeRangeRow(
                icon: "sun.max.fill",
                title: "喝水提醒时段",
                subtitle: "只在这个时间段里计算喝水间隔，避免夜里也被提醒",
                startOptions: model.timeOptions,
                endOptions: model.timeOptions,
                startSelection: $model.dailyCare.waterStartTime,
                endSelection: $model.dailyCare.waterEndTime
            )

            NotificationStepperRow(
                icon: "drop.fill",
                title: "今日喝水进度",
                subtitle: "手动记录已经喝了几杯，让后续提醒节奏更贴近实际",
                valueText: "\(model.dailyCare.waterProgress)/\(model.waterGoalCount) 杯",
                onMinus: model.decrementWaterProgress,
                onPlus: model.incrementWaterProgress,
                onReset: model.resetWaterProgress
            )

            NotificationToggleRow(
                icon: "figure.walk",
                title: "久坐提醒",
                subtitle: "在设定时段里根据鼠标活动累计久坐时间，到点后提醒你起来活动一下",
                isOn: $model.dailyCare.sitReminderEnabled
            )

            NotificationPickerRow(
                icon: "hourglass",
                title: "久坐提醒间隔",
                subtitle: "连续活动满这个时长后提醒一次，继续久坐会按同样间隔再次提醒",
                options: model.careIntervals,
                selection: $model.dailyCare.sitInterval
            )

            NotificationTimeRangeRow(
                icon: "sun.max.fill",
                title: "久坐提醒时段",
                subtitle: "只在这个时间段里累计久坐时间，离开时段后会重新开始计时",
                startOptions: model.timeOptions,
                endOptions: model.timeOptions,
                startSelection: $model.dailyCare.sitStartTime,
                endSelection: $model.dailyCare.sitEndTime
            )

            NotificationToggleRow(
                icon: "moon.fill",
                title: "睡觉提醒",
                subtitle: "在睡前先提醒收尾，到点后再提醒你去休息",
                isOn: $model.dailyCare.sleepReminderEnabled
            )

            NotificationPickerRow(
                icon: "moon.stars.fill",
                title: "目标入睡时间",
                subtitle: "决定正式提醒你去休息的时间点",
                options: model.timeOptions,
                selection: $model.dailyCare.targetSleepTime
            )

            NotificationPickerRow(
                icon: "alarm.fill",
                title: "预备提醒时间",
                subtitle: "决定提前多久提醒你开始收尾和准备洗漱",
                options: model.preSleepOptions,
                selection: $model.dailyCare.preSleepLeadTime
            )

            NotificationToggleRow(
                icon: "calendar",
                title: "周末单独时间",
                subtitle: "开启后，周末可以晚一点睡，不再沿用工作日时间",
                isOn: $model.dailyCare.weekendScheduleEnabled
            )

            if model.dailyCare.weekendScheduleEnabled {
                NotificationPickerRow(
                    icon: "moon.stars.fill",
                    title: "周末目标入睡时间",
                    subtitle: "周末正式提醒你去休息的时间点",
                    options: model.timeOptions,
                    selection: $model.dailyCare.weekendTargetSleepTime
                )

                NotificationPickerRow(
                    icon: "alarm.fill",
                    title: "周末预备提醒时间",
                    subtitle: "周末提前多久提醒你开始收尾",
                    options: model.preSleepOptions,
                    selection: $model.dailyCare.weekendPreSleepLeadTime
                )
            }
        }
        .opacity(model.dailyCare.isEnabled ? 1 : 0.82)
    }
}

struct NotificationStatusStrip: View {
    @ObservedObject var model: NotificationSettingsViewModel

    private var items: [NotificationStatusItem] {
        [
            NotificationStatusItem(
                icon: "cloud.sun.fill",
                title: "天气",
                detail: model.weather.isEnabled
                    ? "每 \(model.weather.checkFrequency)检查"
                    : "提醒已关闭",
                isActive: model.weather.isEnabled
            ),
            NotificationStatusItem(
                icon: "desktopcomputer",
                title: "设备",
                detail: model.device.isEnabled ? "状态监测中" : "提醒已关闭",
                isActive: model.device.isEnabled
            ),
            NotificationStatusItem(
                icon: "heart.fill",
                title: "日常",
                detail: model.dailyCare.isEnabled ? "关怀提醒运行中" : "提醒已关闭",
                isActive: model.dailyCare.isEnabled
            )
        ]
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 0)],
            spacing: 0
        ) {
            ForEach(items) { item in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: item.icon)
                        .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isActive ? NotificationStyle.blue : NotificationStyle.secondaryText)
                        .frame(width: 30, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .fill(item.isActive ? AppColor.accentSoft : NotificationStyle.controlBackground)
                        }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(item.title)
                            .font(AppTypography.rowTitle)
                            .foregroundStyle(NotificationStyle.primaryText)

                        Text(item.detail)
                            .font(AppTypography.caption)
                            .foregroundStyle(NotificationStyle.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Circle()
                        .fill(item.isActive ? AppColor.positive : AppColor.textDisabled)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, AppSpacing.lg)
                .frame(height: 58)
            }
        }
        .appSurface(.inset, radius: AppRadius.row)
    }
}

private struct NotificationStatusItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let isActive: Bool
}

struct NotificationSectionView<Content: View>: View {
    let title: String
    let footer: String
    let isEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(NotificationStyle.primaryText)
                Spacer()
                Text(isEnabled ? "已启用" : "已关闭")
                    .font(AppTypography.caption)
                    .foregroundStyle(isEnabled ? AppColor.positive : NotificationStyle.secondaryText)
                Circle()
                    .fill(isEnabled ? AppColor.positive : AppColor.textDisabled)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, AppSpacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: NotificationStyle.cardRadius, style: .continuous)
                    .fill(NotificationStyle.cardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: NotificationStyle.cardRadius, style: .continuous)
                            .stroke(AppColor.border, lineWidth: 1)
                    }
            }

            Text(footer)
                .font(AppTypography.caption)
                .foregroundStyle(NotificationStyle.sectionTitle)
                .padding(.horizontal, AppSpacing.xs)
        }
        .animation(AppMotion.standard, value: isEnabled)
    }
}

struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var showsProBadge = false
    @Binding var isOn: Bool

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle, showsProBadge: showsProBadge) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(AppSwitchToggleStyle())
                .fixedSize()
        }
    }
}

struct NotificationActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle) {
            Button(buttonTitle, action: action)
                .buttonStyle(NotificationPrimaryButtonStyle())
        }
    }
}

struct NotificationSegmentedRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle) {
            NotificationSegmentedControl(options: options, selection: $selection)
        }
    }
}

struct NotificationPickerRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle) {
            NotificationMenuPicker(options: options, selection: $selection)
        }
    }
}

struct NotificationTimeRangeRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let startOptions: [String]
    let endOptions: [String]
    @Binding var startSelection: String
    @Binding var endSelection: String

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle) {
            HStack(spacing: AppSpacing.sm) {
                NotificationMenuPicker(options: startOptions, selection: $startSelection)
                Text("至")
                    .font(AppTypography.control)
                    .foregroundStyle(NotificationStyle.secondaryText)
                NotificationMenuPicker(options: endOptions, selection: $endSelection)
            }
        }
    }
}

struct NotificationStepperRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let valueText: String
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onReset: () -> Void

    var body: some View {
        NotificationBaseRow(icon: icon, title: title, subtitle: subtitle) {
            HStack(spacing: AppSpacing.sm) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                }
                .buttonStyle(NotificationRoundIconButtonStyle())

                Text(valueText)
                    .font(AppTypography.control)
                    .foregroundStyle(NotificationStyle.blue)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(NotificationStyle.controlBackground)
                    }

                Button(action: onPlus) {
                    Image(systemName: "plus")
                }
                .buttonStyle(NotificationRoundIconButtonStyle())

                Button("重置", action: onReset)
                    .buttonStyle(NotificationSoftButtonStyle())
            }
        }
    }
}

struct NotificationMultiSelectGridRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [String]
    let selectedOptions: Set<String>
    let action: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: AppSpacing.sm)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            NotificationBaseRow(icon: icon, title: title, subtitle: subtitle, accessory: { EmptyView() })

            LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selectedOptions.contains(option)
                    Button {
                        action(option)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: AppIconStyle.actionSize, weight: .semibold))

                            Text(option)
                                .font(AppTypography.control)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(AppButtonStyle(role: .secondary, isSelected: isSelected))
                    .handCursor()
                }
            }
            .padding(.bottom, AppSpacing.md)
        }
        .notificationDivider()
    }
}

struct NotificationBaseRow<Accessory: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var showsProBadge = false
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(NotificationStyle.secondaryText)
                .frame(width: AppIconStyle.rowFrame, height: AppIconStyle.rowFrame)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(NotificationStyle.controlBackground)
                }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(NotificationStyle.primaryText)

                    if showsProBadge {
                        ProBadgeView()
                    }
                }

                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(NotificationStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.lg)

            accessory()
                .frame(maxWidth: 480, alignment: .trailing)
        }
        .padding(.vertical, AppSpacing.md)
        .notificationDivider()
    }
}

struct NotificationSegmentedControl: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(AppMotion.standard) {
                        selection = option
                    }
                } label: {
                    Text(option)
                        .font(AppTypography.control)
                        .foregroundStyle(selection == option ? NotificationStyle.blue : NotificationStyle.controlText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(minWidth: 62)
                        .frame(height: AppControlStyle.compactHeight)
                        .padding(.horizontal, AppSpacing.sm)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .fill(selection == option ? AppColor.accentSoft : Color.clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                        .stroke(selection == option ? AppColor.accentBorder : .clear, lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
                .handCursor()
            }
        }
        .padding(AppSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(NotificationStyle.controlBackground)
        }
    }
}

struct NotificationMenuPicker: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(selection)
                    .font(AppTypography.control)
                    .foregroundStyle(NotificationStyle.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NotificationStyle.secondaryText)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(minWidth: 104)
            .frame(height: AppControlStyle.regularHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(NotificationStyle.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(AppColor.border, lineWidth: 1)
                    }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct ProBadgeView: View {
    var body: some View {
        ProBadge()
    }
}

struct CameraNotificationPreviewBubble: View {
    var body: some View {
        VStack(spacing: 7) {
            Capsule()
                .fill(Color.white.opacity(0.16))
                .frame(width: 72, height: 6)

            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.37, blue: 1.0))
                        .frame(width: 36, height: 36)
                    Image(systemName: "cloud.heavyrain.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("天气提醒")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("一小时内可能下雨，出门记得带伞。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(width: 350)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .shadow(color: Color.black.opacity(0.26), radius: 28, y: 16)
        }
    }
}

private struct NotificationPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.control)
            .foregroundStyle(NotificationStyle.blue)
            .padding(.horizontal, AppSpacing.lg)
            .frame(height: AppControlStyle.regularHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(AppColor.accentSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(AppColor.accentBorder, lineWidth: 1)
                    }
            }
            .scaleEffect(configuration.isPressed ? AppControlStyle.pressedScale : 1)
            .opacity(configuration.isPressed ? AppControlStyle.pressedOpacity : 1)
    }
}

private struct NotificationRoundIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(NotificationStyle.primaryText)
            .frame(width: AppControlStyle.iconButtonSize, height: AppControlStyle.iconButtonSize)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(NotificationStyle.controlBackground)
            }
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private struct NotificationSoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.control)
            .foregroundStyle(NotificationStyle.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: AppControlStyle.iconButtonSize)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(NotificationStyle.controlBackground)
            }
            .opacity(configuration.isPressed ? 0.70 : 1)
    }
}

private extension View {
    func notificationDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotificationStyle.divider)
                .frame(height: 1)
        }
    }
}

private enum NotificationStyle {
    static let pageBackground = AppColor.pageBackground
    static let cardBackground = AppColor.elevatedSurface
    static let tileBackground = AppColor.controlFill
    static let controlBackground = AppColor.controlFill
    static let blue = AppColor.accent
    static let primaryText = AppColor.textPrimary
    static let secondaryText = AppColor.textSecondary
    static let sectionTitle = AppColor.textTertiary
    static let controlText = AppColor.textBody
    static let divider = AppColor.divider
    static let cardRadius = AppRadius.row
    static let sectionSpacing = AppSpacing.lg
    static let contentMaxWidth: CGFloat = 980
}
