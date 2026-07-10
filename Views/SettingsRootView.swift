import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case home
    case todo
    case music
    case quickApps
    case shortcuts
    case notifications
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .todo: "待办"
        case .music: "音乐"
        case .quickApps: "应用"
        case .shortcuts: "指令"
        case .notifications: "通知"
        case .general: "通用"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .todo: "checklist"
        case .music: "music.note"
        case .quickApps: "square.grid.2x2"
        case .shortcuts: "bolt"
        case .notifications: "bell"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

enum SettingsPreviewMode: String, CaseIterable, Identifiable {
    case normal
    case playing
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "默认"
        case .playing: "播放中"
        case .expanded: "展开"
        }
    }
}

enum SettingsAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var swatch: Color {
        switch self {
        case .system: Color(red: 0.18, green: 0.20, blue: 0.24)
        case .light: Color.white
        case .dark: Color(red: 0.12, green: 0.14, blue: 0.17)
        }
    }
}

enum SettingsHoverAnimationStyle: String, CaseIterable, Identifiable {
    case smooth
    case elastic
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: "平滑放大"
        case .elastic: "轻微弹性"
        case .none: "无动画"
        }
    }
}

enum SettingsStatusItem: String, CaseIterable, Identifiable {
    case network
    case lunar
    case calendar
    case clock
    case weekday
    case battery
    case weather
    case temperature
    case humidity
    case windSpeed
    case windDirection
    case dayProgress
    case weekProgress
    case monthProgress
    case quarterProgress
    case yearProgress
    case cpu
    case memory
    case disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "网速"
        case .lunar: "农历"
        case .calendar: "日历"
        case .clock: "时钟"
        case .weekday: "星期"
        case .battery: "电池"
        case .weather: "天气"
        case .temperature: "温度"
        case .humidity: "湿度"
        case .windSpeed: "风速"
        case .windDirection: "风向"
        case .dayProgress: "日进度"
        case .weekProgress: "周进度"
        case .monthProgress: "月进度"
        case .quarterProgress: "季进度"
        case .yearProgress: "年进度"
        case .cpu: "处理器"
        case .memory: "内存"
        case .disk: "磁盘"
        }
    }

    var icon: String {
        switch self {
        case .network: "arrow.up.arrow.down"
        case .lunar: "moon"
        case .calendar: "calendar"
        case .clock: "clock"
        case .weekday: "textformat.abc"
        case .battery: "battery.75percent"
        case .weather: "cloud"
        case .temperature: "thermometer.medium"
        case .humidity: "drop"
        case .windSpeed: "wind"
        case .windDirection: "location.north"
        case .dayProgress: "sun.max"
        case .weekProgress: "calendar.day.timeline.left"
        case .monthProgress: "calendar.badge.clock"
        case .quarterProgress: "chart.pie"
        case .yearProgress: "circle.dashed"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        }
    }

    var sample: String {
        switch self {
        case .network: "↓ 12M"
        case .lunar: "四月廿九"
        case .calendar: "6/15"
        case .clock: "14:30"
        case .weekday: "周一"
        case .battery: "83%"
        case .weather: "多云"
        case .temperature: "28°"
        case .humidity: "70%"
        case .windSpeed: "3m/s"
        case .windDirection: "东南"
        case .dayProgress: "日 62%"
        case .weekProgress: "周 41%"
        case .monthProgress: "月 50%"
        case .quarterProgress: "季 83%"
        case .yearProgress: "年 45%"
        case .cpu: "CPU 18%"
        case .memory: "内存 6G"
        case .disk: "磁盘 72%"
        }
    }
}

enum SettingsWidget: String, CaseIterable, Identifiable {
    case command
    case todo
    case note
    case mirror
    case pomodoro
    case weather
    case music
    case calendar
    case quickApps
    case shortcuts
    case imageCard
    case deviceInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "指令"
        case .todo: "待办事项"
        case .note: "临时笔记"
        case .mirror: "镜子"
        case .pomodoro: "番茄钟"
        case .weather: "天气"
        case .music: "音乐"
        case .calendar: "日历"
        case .quickApps: "快捷应用"
        case .shortcuts: "快捷指令"
        case .imageCard: "图片卡片"
        case .deviceInfo: "设备信息"
        }
    }

    var subtitle: String {
        switch self {
        case .command: "快速执行常用命令"
        case .todo: "管理轻量待办任务"
        case .note: "随手记录灵感"
        case .mirror: "查看仪容仪表"
        case .pomodoro: "专注计时提醒"
        case .weather: "查看天气与体感"
        case .music: "播放信息与歌词"
        case .calendar: "日程与农历信息"
        case .quickApps: "常用应用启动"
        case .shortcuts: "运行系统快捷指令"
        case .imageCard: "展示一张灵动岛图片"
        case .deviceInfo: "查看 CPU 与存储状态"
        }
    }

    var icon: String {
        switch self {
        case .command: "command"
        case .todo: "checklist"
        case .note: "note.text"
        case .mirror: "person.crop.square"
        case .pomodoro: "timer"
        case .weather: "cloud.sun"
        case .music: "music.note"
        case .calendar: "calendar"
        case .quickApps: "square.grid.2x2"
        case .shortcuts: "bolt"
        case .imageCard: "photo"
        case .deviceInfo: "desktopcomputer"
        }
    }

    var tag: String {
        switch self {
        case .command, .todo: "Pro"
        default: "Free"
        }
    }

    var settingsPage: SettingsPage? {
        switch self {
        case .todo: .todo
        case .music: .music
        case .quickApps: .quickApps
        case .shortcuts: .shortcuts
        default: nil
        }
    }
}

@MainActor
final class SettingsEditorModel: ObservableObject {
    @Published var selectedSettingsPage: SettingsPage = .home
    @Published var selectedPreviewMode: SettingsPreviewMode = .normal
    @Published var appearanceMode: SettingsAppearanceMode = .system
    @Published var spacingValue: Double = 0.46
    @Published var hoverAnimationEnabled = true
    @Published var hoverAnimationStyle: SettingsHoverAnimationStyle = .smooth
    @Published var selectedStatusItems: Set<SettingsStatusItem> = []
    @Published var leftStatusItems: [SettingsStatusItem] = [] { didSet { syncSelectedItems() } }
    @Published var rightStatusItems: [SettingsStatusItem] = [] { didSet { syncSelectedItems() } }
    @Published var enabledWidgets: Set<SettingsWidget> = [] { didSet { markChanged() } }
    @Published var showMusicTrackName = true { didSet { markChanged() } }
    @Published var showMusicLyrics = true { didSet { markChanged() } }
    @Published var showDesktopLyrics = true { didSet { markChanged() } }
    @Published var allowAppleMusicAccess = true { didSet { markChanged() } }
    @Published var allowSpotifyAccess = false { didSet { markChanged() } }
    @Published var showFeedbackSheet = false
    @Published var leftSideIcon: SettingsHomeSideIcon = .weather {
        didSet {
            markChanged()
        }
    }
    @Published var rightSideIcon: SettingsHomeSideIcon = .battery {
        didSet {
            markChanged()
        }
    }
    @Published var imageCardPath: String = "" {
        didSet {
            markChanged()
        }
    }
    @Published var limitNotice: String?

    private let settings: IslandSettings
    private var isLoading = false

    init(settings: IslandSettings) {
        self.settings = settings
        reloadFromSettings()
    }

    func resetPageForOpen() {
        selectedSettingsPage = .home
        reloadFromSettings()
    }

    func prepareForOpen(page: SettingsPage = .home, presentFeedback: Bool = false) {
        reloadFromSettings()
        selectedSettingsPage = page
        showFeedbackSheet = presentFeedback
    }

    func reloadFromSettings() {
        isLoading = true
        selectedPreviewMode = .normal
        appearanceMode = .system
        spacingValue = 0.46
        hoverAnimationEnabled = true
        hoverAnimationStyle = .smooth
        leftSideIcon = settings.showCustomCompactIcons
            ? supportedSideIcon(settings.compactLeftSideIcon, fallback: .weather)
            : .none
        rightSideIcon = settings.showCustomCompactIcons
            ? supportedSideIcon(settings.compactRightSideIcon, fallback: .battery)
            : .none
        imageCardPath = settings.imageCardPath
        leftStatusItems = [.network, .lunar, .battery, .temperature]
        rightStatusItems = [.calendar, .clock, .humidity, .weather]
        enabledWidgets = defaultEnabledWidgets(from: settings)
        showMusicTrackName = settings.showMusicTrackName
        showMusicLyrics = settings.showMusicLyrics
        showDesktopLyrics = settings.showDesktopLyrics
        allowAppleMusicAccess = settings.allowAppleMusicAccess
        allowSpotifyAccess = settings.allowSpotifyAccess
        syncSelectedItems()
        showFeedbackSheet = false
        limitNotice = nil
        isLoading = false
    }

    private func persistSettings() {
        update(\.showWeatherModule, to: enabledWidgets.contains(.weather))
        update(\.showCalendarModule, to: enabledWidgets.contains(.calendar))
        update(\.showMediaModule, to: enabledWidgets.contains(.music))
        update(\.showTodoModule, to: enabledWidgets.contains(.todo))
        update(\.showQuickAppsModule, to: enabledWidgets.contains(.quickApps))
        update(\.showShortcutsModule, to: enabledWidgets.contains(.shortcuts))
        update(\.showImageCardModule, to: enabledWidgets.contains(.imageCard))
        update(\.showDeviceInfoModule, to: enabledWidgets.contains(.deviceInfo))
        update(\.imageCardPath, to: imageCardPath)
        update(\.showMusicTrackName, to: showMusicTrackName)
        update(\.showMusicLyrics, to: showMusicLyrics)
        update(\.showDesktopLyrics, to: showDesktopLyrics)
        update(\.allowAppleMusicAccess, to: allowAppleMusicAccess)
        update(\.allowSpotifyAccess, to: allowSpotifyAccess)
        update(\.compactLeftSideIcon, to: supportedSideIcon(leftSideIcon, fallback: .weather))
        update(\.compactRightSideIcon, to: supportedSideIcon(rightSideIcon, fallback: .battery))
        if leftSideIcon != .none || rightSideIcon != .none {
            update(\.showCustomCompactIcons, to: true)
        }
    }

    private func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<IslandSettings, Value>,
        to value: Value
    ) {
        guard settings[keyPath: keyPath] != value else { return }
        settings[keyPath: keyPath] = value
    }

    private func supportedSideIcon(
        _ icon: SettingsHomeSideIcon,
        fallback: SettingsHomeSideIcon
    ) -> SettingsHomeSideIcon {
        SettingsHomeSideIcon.sideOptions.contains(icon) ? icon : fallback
    }

    func toggleStatus(_ item: SettingsStatusItem) {
        if selectedStatusItems.contains(item) {
            removeStatus(item)
            return
        }

        guard selectedStatusItems.count < 8 else {
            limitNotice = "主页最多显示 8 个状态图标"
            return
        }

        if leftStatusItems.count < 4 {
            leftStatusItems.append(item)
        } else if rightStatusItems.count < 4 {
            rightStatusItems.append(item)
        } else {
            limitNotice = "单侧最多 4 个状态图标"
        }
    }

    func removeStatus(_ item: SettingsStatusItem) {
        leftStatusItems.removeAll { $0 == item }
        rightStatusItems.removeAll { $0 == item }
    }

    func resetStatusLayout() {
        leftStatusItems = [.network, .lunar, .battery, .temperature]
        rightStatusItems = [.calendar, .clock, .humidity, .weather]
    }

    func moveStatus(_ source: IndexSet, fromLeft: Bool, to destination: Int, targetLeft: Bool) {
        var sourceItems = fromLeft ? leftStatusItems : rightStatusItems
        var targetItems = targetLeft ? leftStatusItems : rightStatusItems
        let moving = source.map { sourceItems[$0] }

        sourceItems.remove(atOffsets: source)
        if fromLeft == targetLeft {
            sourceItems.insert(contentsOf: moving, at: min(destination, sourceItems.count))
            if targetLeft {
                leftStatusItems = sourceItems
            } else {
                rightStatusItems = sourceItems
            }
            return
        }

        guard targetItems.count + moving.count <= 4 else {
            limitNotice = "单侧最多 4 个状态图标"
            return
        }

        targetItems.insert(contentsOf: moving, at: min(destination, targetItems.count))
        leftStatusItems = targetLeft ? targetItems : sourceItems
        rightStatusItems = targetLeft ? sourceItems : targetItems
    }

    func toggleWidget(_ widget: SettingsWidget) {
        if enabledWidgets.contains(widget) {
            enabledWidgets.remove(widget)
        } else {
            enabledWidgets.insert(widget)
        }
    }

    private func defaultEnabledWidgets(from settings: IslandSettings) -> Set<SettingsWidget> {
        var result: Set<SettingsWidget> = []
        if settings.showTodoModule { result.insert(.todo) }
        if settings.showWeatherModule { result.insert(.weather) }
        if settings.showMediaModule { result.insert(.music) }
        if settings.showCalendarModule { result.insert(.calendar) }
        if settings.showQuickAppsModule { result.insert(.quickApps) }
        if settings.showShortcutsModule { result.insert(.shortcuts) }
        if settings.showImageCardModule { result.insert(.imageCard) }
        if settings.showDeviceInfoModule { result.insert(.deviceInfo) }
        return result
    }

    private func syncSelectedItems() {
        selectedStatusItems = Set(leftStatusItems + rightStatusItems)
    }

    private func markChanged() {
        guard !isLoading else { return }
        persistSettings()
    }
}

struct SettingsRootView: View {
    @ObservedObject var settings: IslandSettings
    @StateObject private var model: SettingsEditorModel
    @State private var isSidebarCollapsed = false
    @State private var previewImageCardImage: NSImage?
    @State private var previewImageCardImagePath = ""
    @State private var previewImageCardLoadTask: Task<Void, Never>?

    init(settings: IslandSettings) {
        self.settings = settings
        _model = StateObject(wrappedValue: SettingsEditorModel(settings: settings))
    }

    init(settings: IslandSettings, model: SettingsEditorModel) {
        self.settings = settings
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        AppShellView {
            SidebarView(
                selection: $model.selectedSettingsPage,
                isCollapsed: $isSidebarCollapsed
            )
        } content: {
            content
        }
        .background(AppColor.pageBackground)
        .preferredColorScheme(.light)
        .environment(\.appFontPreference, settings.fontPreference)
        .fontDesign(settings.fontPreference.fontDesign)
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            consumeNavigationTriggers()
            loadPreviewImageCardThumbnailIfNeeded()
        }
        .onChange(of: model.imageCardPath) { _, _ in
            loadPreviewImageCardThumbnailIfNeeded()
        }
        .onChange(of: settings.quickAppsSettingsTrigger) { _, _ in
            consumeNavigationTriggers()
        }
        .onChange(of: settings.shortcutsSettingsTrigger) { _, _ in
            consumeNavigationTriggers()
        }
        .onDisappear {
            previewImageCardLoadTask?.cancel()
            previewImageCardLoadTask = nil
        }
        .sheet(isPresented: $model.showFeedbackSheet) {
            FeedbackMailSheet {
                model.showFeedbackSheet = false
            }
        }
    }

    private func consumeNavigationTriggers() {
        if settings.quickAppsSettingsTrigger {
            model.selectedSettingsPage = .quickApps
            settings.quickAppsSettingsTrigger = false
        }
        if settings.shortcutsSettingsTrigger {
            model.selectedSettingsPage = .shortcuts
            settings.shortcutsSettingsTrigger = false
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .topLeading) {
            if model.selectedSettingsPage == .home {
                homePage
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .todo {
                TodoView(settings: settings)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .music {
                musicPage
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .quickApps {
                QuickAppsSettingsView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .shortcuts {
                ShortcutsSettingsView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .notifications {
                NotificationSettingsView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .general {
                GeneralSettingsView(settings: settings)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if model.selectedSettingsPage == .about {
                AboutView {
                    model.showFeedbackSheet = true
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(AppMotion.page, value: model.selectedSettingsPage)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.pageBackground)
    }

    private var homePage: some View {
        SettingsPageScaffold {
            PageHeaderView(
                title: "灵动岛主页",
                subtitle: "调整紧凑状态、左右信息和展开后的常用模块。",
                icon: "capsule"
            )
        } content: {
            previewArea
            sideIconConfigurationCard
            widgetsCard
        }
    }

    private var musicPage: some View {
        SettingsPageScaffold {
            PageHeaderView(
                title: "微光乐境",
                subtitle: "管理播放信息、灵动岛歌词与桌面歌词的来源和显示方式。",
                icon: "music.note"
            )
        } content: {
            musicSupportedAppsSection
            musicDisplaySection
            musicAccessSection
        }
    }

    private var previewArea: some View {
        previewCard
    }

    private var previewCard: some View {
        SettingsCard(spacing: 10) {
            SectionTitle(title: "主页预览", systemName: nil)

            islandPreview
                .frame(height: 184)

            PillSegmentedControl(
                options: [SettingsPreviewMode.normal, .expanded],
                selection: $model.selectedPreviewMode,
                title: { $0.title }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var islandPreview: some View {
        GeometryReader { proxy in
            let spacing = 8 + model.spacingValue * 12
            let previewWidth = min(proxy.size.width - 8, 940)
            let screenTopInset = min(32, max(22, previewWidth * (66 / 1972)))
            let usesSideStatus = model.leftSideIcon != .none || model.rightSideIcon != .none
            let islandWidth: CGFloat = {
                switch model.selectedPreviewMode {
                case .normal:
                    return usesSideStatus
                        ? min(previewWidth * 0.56, 520)
                        : min(previewWidth * 0.36, 340)
                case .playing:
                    return min(previewWidth * 0.56, 520)
                case .expanded:
                    return min(previewWidth - 44, 860)
                }
            }()
            let islandHeight: CGFloat = model.selectedPreviewMode == .expanded ? 126 : 62

            ZStack(alignment: .top) {
                cameraStripPreview(width: previewWidth)

                previewIsland(width: islandWidth, height: islandHeight, spacing: spacing)
                    .padding(.top, screenTopInset)
                    .animation(AppMotion.page, value: model.selectedPreviewMode)
                    .animation(AppMotion.quick, value: model.spacingValue)
                    .animation(AppMotion.standard, value: model.leftSideIcon)
                    .animation(AppMotion.standard, value: model.rightSideIcon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func cameraStripPreview(width: CGFloat) -> some View {
        let sourceAspectHeight = width * (CGFloat(798) / CGFloat(1972))

        return ZStack(alignment: .top) {
            Image("ComputerPreviewBackground")
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: sourceAspectHeight)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
        }
        .frame(width: width, height: 184, alignment: .top)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
    }

    private func previewIsland(width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        previewIslandContent(width: width, height: height, spacing: spacing)
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(previewIslandShape(width: width, height: height))
        .contentShape(previewIslandShape(width: width, height: height))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }

    @ViewBuilder
    private func previewIslandContent(width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        if model.selectedPreviewMode == .expanded {
            previewExpandedContent(width: width, height: height, spacing: spacing)
        } else {
            let cameraZoneWidth = min(width * 0.44, 230)
            let sideZoneWidth = max(62, (width - cameraZoneWidth) / 2)
            let geometry = NotchGeometry(
                hasNotch: true,
                cameraZoneWidth: cameraZoneWidth,
                sideWidth: sideZoneWidth,
                totalWidth: width,
                height: height
            )

            CompactCapsuleContentView(
                mode: .status,
                geometry: geometry,
                snapshot: .idle,
                currentLyricText: nil,
                nextLyricText: nil,
                currentLyricStartTimeMS: nil,
                nextLyricStartTimeMS: nil,
                showsTrackName: false,
                showsLyrics: false,
                leftSideIcon: model.leftSideIcon,
                rightSideIcon: model.rightSideIcon,
                sideStatusContext: staticSideStatusContext,
                foregroundPromptDisplayMode: .applicationName,
                foregroundPrompt: nil,
                statusContentScale: 1.45
            )
        }
    }

    private var sideStatusContext: SideStatusContext {
        staticSideStatusContext
    }

    private var staticSideStatusContext: SideStatusContext {
        SideStatusContext(
            playback: .idle,
            weather: WeatherSnapshot(
                temperature: 23,
                apparentTemperature: 22,
                humidity: 90,
                windSpeed: 11,
                condition: "小雨",
                locationName: "上海市",
                symbolName: "cloud.rain.fill",
                detail: "静态预览",
                dailyForecasts: [
                    WeatherDailySummary(
                        id: "preview",
                        title: "今天",
                        symbolName: "cloud.rain.fill",
                        temperatureRangeText: "22°/24°"
                    )
                ],
                isLive: false
            ),
            deviceInfo: DeviceInfoSnapshot(
                cpuPercent: 42,
                memoryPercent: 82,
                diskPercent: 48,
                usedDiskText: "239G",
                totalDiskText: "494G",
                uploadBytesPerSecond: 4_000,
                downloadBytesPerSecond: 9_000
            ),
            battery: BatterySnapshot(percent: 90, isCharging: false),
            isMuted: false
        )
    }

    private func previewIslandShape(width: CGFloat, height: CGFloat) -> DynamicIslandShape {
        DynamicIslandShape(
            shoulderWidth: min(54, width * 0.14),
            shoulderDepth: min(28, height * 0.46),
            sideInset: min(10, width * 0.04),
            bottomCornerRadius: model.selectedPreviewMode == .expanded ? 20 : 10,
            visibleSize: CGSize(width: width, height: height)
        )
    }

    private func previewExpandedContent(width: CGFloat, height: CGFloat, spacing: CGFloat) -> some View {
        let widgets = expandedPreviewWidgets
        let cardHeight = max(74, height - 32)
        let itemSpacing = max(6, spacing * 0.42)
        let horizontalPadding: CGFloat = 20
        let contentWidth = widgets.reduce(CGFloat(0)) { $0 + previewWidgetWidth($1) }
            + itemSpacing * CGFloat(max(0, widgets.count - 1))
        let scale = min(1, max(0.2, (width - horizontalPadding * 2) / max(1, contentWidth)))

        return HStack(spacing: itemSpacing) {
            ForEach(widgets) { widget in
                previewWidgetCard(widget, height: cardHeight)
                    .frame(width: previewWidgetWidth(widget), height: cardHeight)
            }
        }
        .scaleEffect(scale, anchor: .center)
        .frame(
            width: max(1, contentWidth * scale),
            height: cardHeight * scale,
            alignment: .center
        )
        .frame(width: width, height: height, alignment: .center)
        .padding(.horizontal, horizontalPadding)
    }

    private var expandedPreviewWidgets: [SettingsWidget] {
        let savedOrder = settings.moduleOrder.compactMap { moduleRawValue -> SettingsWidget? in
            switch moduleRawValue {
            case IslandPanelModule.weather.rawValue:
                return .weather
            case IslandPanelModule.calendar.rawValue:
                return .calendar
            case IslandPanelModule.todo.rawValue:
                return .todo
            case IslandPanelModule.media.rawValue:
                return .music
            case IslandPanelModule.quickApps.rawValue:
                return .quickApps
            case IslandPanelModule.shortcuts.rawValue:
                return .shortcuts
            case IslandPanelModule.imageCard.rawValue:
                return .imageCard
            case IslandPanelModule.deviceInfo.rawValue:
                return .deviceInfo
            default:
                return nil
            }
        }

        let order = savedOrder.isEmpty
            ? homeWidgets
            : savedOrder + homeWidgets.filter { !savedOrder.contains($0) }

        return order.filter { model.enabledWidgets.contains($0) && $0 != .todo }
    }

    private func previewWidgetWidth(_ widget: SettingsWidget) -> CGFloat {
        switch widget {
        case .imageCard:
            return 82
        case .deviceInfo:
            return 128
        case .music:
            return 150
        case .shortcuts:
            return 116
        case .quickApps:
            return 104
        case .calendar:
            return 116
        case .weather:
            return 100
        default:
            return 92
        }
    }

    @ViewBuilder
    private func previewWidgetCard(_ widget: SettingsWidget, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            switch widget {
            case .imageCard:
                previewImageCardThumbnail
            case .deviceInfo:
                previewDeviceInfoThumbnail
            case .music:
                previewMusicThumbnail
            case .calendar:
                previewCalendarThumbnail
            case .weather:
                previewWeatherThumbnail
            case .quickApps:
                previewQuickAppsThumbnail
            case .shortcuts:
                previewShortcutsThumbnail
            default:
                VStack(spacing: 7) {
                    Image(systemName: widget.icon)
                        .font(.system(size: 18, weight: .semibold))
                    Text(widget.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white.opacity(0.76))
                .padding(10)
            }
        }
    }

    private var previewImageCardThumbnail: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .frame(width: 48, height: 48)
                .offset(x: 13, y: 16)

            Group {
                if let image = previewImageCardImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotationEffect(.degrees(-10), anchor: .bottomLeading)
            .offset(x: 9, y: 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewDeviceInfoThumbnail: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                previewMetric("17%", "CPU", icon: "waveform.path.ecg")
                previewMetric("67%", "RAM", icon: "chart.bar.fill")
                previewMetric("49%", "DISK", icon: "internaldrive")
            }

            HStack(spacing: 7) {
                previewFinderIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("225 / 460G")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("macOS 存储空间")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(AppColor.accent)
                            .frame(width: 34)
                    }
                    .frame(width: 64, height: 2.5)
                }
            }
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(10)
    }

    private var previewFinderIcon: some View {
        Group {
            if let image = AppCachedImageAssets.finderIcon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.cyan.opacity(0.92))
                    .overlay {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.black.opacity(0.65))
                    }
            }
        }
    }

    private func loadPreviewImageCardThumbnailIfNeeded() {
        let path = model.imageCardPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path != previewImageCardImagePath || previewImageCardImage == nil else {
            return
        }

        previewImageCardLoadTask?.cancel()
        previewImageCardImagePath = path
        previewImageCardImage = nil

        guard !path.isEmpty else {
            previewImageCardLoadTask = nil
            return
        }

        previewImageCardLoadTask = Task { @MainActor in
            let image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return NSImage(contentsOfFile: path)
            }.value

            guard !Task.isCancelled, previewImageCardImagePath == path else { return }
            previewImageCardImage = image
            previewImageCardLoadTask = nil
        }
    }

    private func previewMetric(_ value: String, _ label: String, icon: String) -> some View {
        VStack(spacing: 1.5) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(.system(size: 9.5, weight: .bold))
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }

    private var previewMusicThumbnail: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(Color.white.opacity(0.54))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("暂无播放")
                    .font(.system(size: 10.5, weight: .bold))
                Text("Apple Music")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 54, height: 3)
            }
        }
        .foregroundStyle(Color.white.opacity(0.82))
        .padding(10)
    }

    private var previewCalendarThumbnail: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("6月17日")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.92))
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { col in
                        Text(row == 1 && col == 2 ? "17" : "\(row * 5 + col + 8)")
                            .font(.system(size: 7.5, weight: .semibold))
                            .frame(width: 10, height: 10)
                            .background {
                                if row == 1 && col == 2 {
                                    Circle().fill(Color.red)
                                }
                            }
                    }
                }
            }
        }
        .foregroundStyle(Color.white.opacity(0.76))
        .padding(10)
    }

    private var previewWeatherThumbnail: some View {
        VStack(spacing: 5) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .white.opacity(0.72))
            Text("26°")
                .font(.system(size: 16, weight: .bold))
            Text("局部多云")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(10)
    }

    private var previewQuickAppsThumbnail: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 7), count: 2), spacing: 7) {
            ForEach(["message.fill", "terminal.fill", "doc.fill", "hammer.fill"], id: \.self) { icon in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.68))
                    }
            }
        }
        .padding(10)
    }

    private var previewShortcutsThumbnail: some View {
        VStack(spacing: 7) {
            previewShortcutPill("用高德地图回家", Color.teal)
            previewShortcutPill("恋爱纪念日", Color.green)
        }
        .padding(10)
    }

    private func previewShortcutPill(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
        .background(color.opacity(0.82), in: Capsule())
    }

    private var appearanceCard: some View {
        SettingsCard(spacing: 12) {
            SectionTitle(title: "外观主题", systemName: "paintpalette")
            Picker("", selection: $model.appearanceMode) {
                ForEach(SettingsAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var spacingCard: some View {
        SettingsCard(spacing: 12) {
            SectionTitle(title: "尺寸与间距", systemName: "arrow.up.left.and.arrow.down.right")
            Slider(value: $model.spacingValue, in: 0...1)
            HStack {
                Text("紧凑")
                Spacer()
                Text("宽松")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SettingsColors.secondaryText)
        }
    }

    private var hoverAnimationCard: some View {
        SettingsCard(spacing: 12) {
            HStack {
                SectionTitle(title: "悬停动画", systemName: "sparkles")
                Spacer()
                Toggle("", isOn: $model.hoverAnimationEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Picker("", selection: $model.hoverAnimationStyle) {
                ForEach(SettingsHoverAnimationStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .labelsHidden()
            .disabled(!model.hoverAnimationEnabled)
            .opacity(model.hoverAnimationEnabled ? 1 : 0.45)
        }
    }

    private var musicSupportedAppsSection: some View {
        SettingsSectionCard(
            title: "支持应用",
            subtitle: "读取播放状态、歌曲信息与播放进度",
            footer: "开启后可用于歌词匹配与同步显示。"
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: AppSpacing.sm, alignment: .top)
                ],
                spacing: AppSpacing.sm
            ) {
                ForEach(SettingsMusicSupportedApp.allCases) { app in
                    SettingsMusicSupportedAppCard(app: app)
                }
            }
        }
    }

    private var musicDisplaySection: some View {
        SettingsSectionCard(
            title: "显示内容",
            subtitle: "控制紧凑模式和歌词弹幕里要展示哪些内容"
        ) {
            SettingsToggleRow(
                title: "显示歌名",
                subtitle: "在紧凑模式下显示当前歌曲名称",
                isOn: $model.showMusicTrackName
            )
            SettingsToggleRow(
                title: "显示歌词",
                subtitle: "在紧凑模式下显示当前歌词内容",
                isOn: $model.showMusicLyrics
            )
            SettingsToggleRow(
                title: "歌词弹幕",
                subtitle: "在桌面上显示独立的歌词弹幕窗口",
                isOn: $model.showDesktopLyrics,
                showsDivider: false
            )
        }
    }

    private var musicAccessSection: some View {
        SettingsSectionCard(
            title: "应用访问",
            subtitle: "按需开启微光乐境可访问的应用来源",
            footer: "默认仅开启 Apple Music。若需处理相关权限，请前往“关于 - 权限管理”。"
        ) {
            SettingsToggleRow(
                title: "Apple Music",
                subtitle: "允许读取 Apple Music 的播放状态与歌曲信息",
                isOn: $model.allowAppleMusicAccess
            )
            SettingsToggleRow(
                title: "Spotify",
                subtitle: "允许读取 Spotify 的播放状态与歌曲信息",
                isOn: $model.allowSpotifyAccess,
                showsDivider: false
            )
        }
    }

    private var sideIconConfigurationCard: some View {
        SettingsCard(spacing: 16) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SectionTitle(title: "左右侧状态", systemName: nil)
                Text("配置灵动岛左右侧常驻信息")
                    .font(AppTypography.supporting)
                    .foregroundStyle(SettingsColors.secondaryText)
            }

            HStack(alignment: .top, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("左侧图标")
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)

                    SideIconPickerSection(
                        options: SettingsHomeSideIcon.sideOptions,
                        context: sideStatusContext,
                        selection: $model.leftSideIcon
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("右侧图标")
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)

                    SideIconPickerSection(
                        options: SettingsHomeSideIcon.sideOptions,
                        context: sideStatusContext,
                        selection: $model.rightSideIcon
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var statusConfigurationCard: some View {
        SettingsCard(spacing: 16) {
            HStack {
                SectionTitle(title: "状态图标配置", systemName: nil)
                Spacer()
                if let notice = model.limitNotice {
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .transition(.opacity)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 92, maximum: 132), spacing: 12, alignment: .top)
                ],
                spacing: 14
            ) {
                ForEach(SettingsStatusItem.allCases) { item in
                    StatusOptionCell(
                        item: item,
                        isSelected: model.selectedStatusItems.contains(item),
                        isDisabled: !model.selectedStatusItems.contains(item)
                            && model.selectedStatusItems.count >= 8
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            model.toggleStatus(item)
                        }
                    }
                }
            }
        }
    }

    private var statusLayoutCard: some View {
        SettingsCard(spacing: 14) {
            HStack {
                SectionTitle(title: "左右区域布局", systemName: "info.circle")
                Spacer()
                Button("重置") {
                    withAnimation(.easeOut(duration: 0.16)) {
                        model.resetStatusLayout()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .semibold))
            }

            HStack(alignment: .top, spacing: 14) {
                StatusColumnView(
                    title: "左侧",
                    items: $model.leftStatusItems,
                    targetLeft: true,
                    model: model
                )
                StatusColumnView(
                    title: "右侧",
                    items: $model.rightStatusItems,
                    targetLeft: false,
                    model: model
                )
            }
        }
    }

    private var widgetsCard: some View {
        SettingsCard(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(title: "小组件与卡片", systemName: nil)
                Text("启用你常用的高效功能，打造专属工作流。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(homeWidgets) { widget in
                        WidgetOptionCard(
                            widget: widget,
                            isEnabled: model.enabledWidgets.contains(widget),
                            onToggle: {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    model.toggleWidget(widget)
                                }
                            },
                            onSettings: {
                                if widget == .imageCard {
                                    chooseImageCardFile()
                                } else if let page = widget.settingsPage {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        model.selectedSettingsPage = page
                                    }
                                }
                            }
                        )
                        .frame(width: 218, height: 130)
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 2)
            }
        }
    }

    private var homeWidgets: [SettingsWidget] {
        [.imageCard, .todo, .deviceInfo, .weather, .music, .calendar, .quickApps, .shortcuts]
    }

    private func chooseImageCardFile() {
        let panel = NSOpenPanel()
        panel.title = "选择图片卡片"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            model.imageCardPath = url.path
            model.enabledWidgets.insert(.imageCard)
        }
    }

}

private struct FeedbackMailSheet: View {
    let onClose: () -> Void

    private let supportEmail = "ardenpro@icloud.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hello")
                        .font(.system(size: 86, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("问题反馈")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(SettingsColors.primaryText)
                        Text("Problem Feedback")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(SettingsColors.secondaryText)
                    }
                    .padding(.leading, 4)
                }

                Spacer(minLength: 16)

                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 92, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 18)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("您好，非常感谢您选择并使用我们的软件，您的支持与厚爱是我们不断进步的最大动力。使用过程中，如果您遇到任何问题、发现任何不便，或有任何改进建议，都非常欢迎您随时反馈给我们。您的每一条意见都至关重要，我们将认真核查并尽快优化。我们将竭诚为您提供更好的体验与服务！谢谢您！")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SettingsColors.primaryText)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "mailbox.fill")
                        .foregroundStyle(.red)
                    Text("技术支持的 Email：\(supportEmail)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsColors.primaryText)
                }
            }
            .padding(22)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 2)
            }
            .padding(.top, 16)

            HStack(spacing: 18) {
                Spacer()

                Button("关闭窗口", action: onClose)
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .frame(width: 128)

                Button {
                    openFeedbackMail()
                    onClose()
                } label: {
                    Label("发送邮件", systemImage: "paperplane.fill")
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .frame(width: 158)

                Spacer()
            }
            .padding(.top, 24)
        }
        .padding(30)
        .frame(width: 610)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.965, green: 0.976, blue: 0.992))
        }
    }

    private func openFeedbackMail() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let subject = "L-Nook 问题反馈"
        let body = """
        您好，我想反馈 L-Nook 使用中的问题或建议：

        问题描述：

        复现步骤：
        1.
        2.
        3.

        期望效果：

        设备与版本：
        - L-Nook: \(appVersion) (\(build))
        - macOS: \(osVersion)

        谢谢！
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsCard<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                .fill(SettingsColors.cardBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 1)
                }
                .appShadow(AppShadowStyle.card)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let systemName: String?

    var body: some View {
        HStack(spacing: 7) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
            }

            Text(title)
                .font(AppTypography.sectionTitle)
                .foregroundStyle(SettingsColors.primaryText)
        }
    }
}

private struct PreviewStatus: View {
    let item: SettingsStatusItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .bold))
            Text(item.sample)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.86))
        .lineLimit(1)
    }
}

private struct SideIconPickerSection: View {
    let options: [SettingsHomeSideIcon]
    let context: SideStatusContext
    @Binding var selection: SettingsHomeSideIcon

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: AppSpacing.md, alignment: .top),
                count: 4
            ),
            spacing: AppSpacing.md
        ) {
            ForEach(options) { option in
                SideIconOptionButton(
                    item: option,
                    isSelected: selection == option,
                    context: context
                ) {
                    withAnimation(AppMotion.quick) {
                        selection = option
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SideIconOptionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: SettingsHomeSideIcon
    let isSelected: Bool
    let context: SideStatusContext
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                SideIconCapsulePreview(
                    item: item,
                    isSelected: isSelected,
                    context: context
                )
                .frame(maxWidth: 112)
                .frame(height: 32)

                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.012 : 1)
        .offset(y: isHovering ? AppControlStyle.hoverLift : 0)
        .onHover { isHovering = $0 }
        .animation(AppMotion.resolved(AppMotion.quick, reduceMotion: reduceMotion), value: isHovering)
    }
}

private struct SideIconCapsulePreview: View {
    let item: SettingsHomeSideIcon
    let isSelected: Bool
    let context: SideStatusContext

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(item == .none ? Color.black.opacity(0.42) : AppColor.islandBackground)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? AppColor.accent : Color.white.opacity(0.06),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isSelected ? AppColor.accent.opacity(0.16) : .black.opacity(0.08),
                    radius: isSelected ? 6 : 3,
                    x: 0,
                    y: isSelected ? 3 : 2
                )

            SideIconCapsuleContent(item: item, context: context)
                .padding(.horizontal, AppSpacing.sm)
        }
    }
}

private struct SideIconCapsuleContent: View {
    let item: SettingsHomeSideIcon
    let context: SideStatusContext

    var body: some View {
        switch item {
        case .network:
            VStack(alignment: .leading, spacing: 1) {
                networkLine(systemName: "arrow.up", value: speedText(context.deviceInfo.uploadBytesPerSecond), color: AppColor.positive)
                networkLine(systemName: "arrow.down", value: speedText(context.deviceInfo.downloadBytesPerSecond), color: AppColor.accent)
            }
        case .dayProgress, .weekProgress, .monthProgress, .quarterProgress, .yearProgress:
            VStack(spacing: 4) {
                valueText(size: 12.5)
                capsuleProgressBar
            }
        case .cpu, .memory, .disk:
            usageMetric
        case .clock:
            ClockCapsuleDial(color: item.accentColor)
                .frame(width: 24, height: 24)
        case .weather:
            HStack(spacing: 6) {
                Image(systemName: item.icon(context: context))
                    .font(.system(size: 11.5, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                valueText(size: 12.5)
            }
        case .battery:
            HStack(spacing: 6) {
                Image(systemName: item.icon(context: context))
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.accentColor)
                valueText(size: 12.5)
            }
        case .windDirection:
            Text(item.statusText(context: context))
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(AppColor.positive)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        case .wind, .temperatureRange, .humidity:
            HStack(spacing: 6) {
                Image(systemName: item.icon(context: context))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(item.accentColor)
                valueText(size: 12.5)
            }
        case .none:
            Image(systemName: "nosign")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
        default:
            valueText(size: 12.5)
        }
    }

    private func valueText(size: CGFloat) -> some View {
        Text(item.statusText(context: context))
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.94))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private var progressValue: Double {
        let text = item.statusText(context: context).replacingOccurrences(of: "%", with: "")
        return min(max((Double(text) ?? 0) / 100, 0), 1)
    }

    private var capsuleProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(item.accentColor)
                    .frame(width: max(5, proxy.size.width * progressValue))
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 12)
    }

    private var usageMetric: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(usageShortTitle)
                    .font(.system(size: 7.4, weight: .bold))
                    .foregroundStyle(item.accentColor)
                Text(item.statusText(context: context))
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(item.accentColor)
                        .frame(width: max(5, proxy.size.width * progressValue))
                }
            }
            .frame(width: 44, height: 3)
        }
    }

    private var usageShortTitle: String {
        switch item {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .disk: "DSK"
        default: ""
        }
    }

    private func networkLine(systemName: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 9)
            Text("\(value)/s")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private func speedText(_ bytesPerSecond: UInt64) -> String {
        let value = Double(bytesPerSecond)
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        return String(format: "%.0f KB", value / 1_000)
    }
}

private struct ClockCapsuleDial: View {
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let date = timeline.date
            let calendar = Calendar.current
            let minute = Double(calendar.component(.minute, from: date))
            let hour = Double(calendar.component(.hour, from: date) % 12) + minute / 60

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(index % 3 == 0 ? 0.62 : 0.32))
                        .frame(width: 1.2, height: index % 3 == 0 ? 4 : 2.5)
                        .offset(y: -9.5)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 1.6, height: 7)
                    .offset(y: -3.5)
                    .rotationEffect(.degrees(hour * 30))

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 1.2, height: 9)
                    .offset(y: -4.5)
                    .rotationEffect(.degrees(minute * 6))

                Circle()
                    .fill(color)
                    .frame(width: 3.2, height: 3.2)
            }
        }
    }
}

private struct SelectableRow<Leading: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.black.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatusOptionCell: View {
    let item: SettingsStatusItem
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .bold))
                    Text(item.sample)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(Color.black.opacity(isDisabled ? 0.46 : 0.86))
                        .overlay {
                            Capsule()
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                        }
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
            }
            .opacity(isDisabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct StatusColumnView: View {
    let title: String
    @Binding var items: [SettingsStatusItem]
    let targetLeft: Bool
    @ObservedObject var model: SettingsEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("最多 4 项")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
            }

            VStack(spacing: 6) {
                ForEach(items) { item in
                    StatusLayoutRow(item: item) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            model.removeStatus(item)
                        }
                    }
                }
                .onMove { source, destination in
                    withAnimation(.easeOut(duration: 0.18)) {
                        model.moveStatus(
                            source,
                            fromLeft: targetLeft,
                            to: destination,
                            targetLeft: targetLeft
                        )
                    }
                }

                if items.isEmpty {
                    Text("拖入状态项")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.025))
            }
        }
    }
}

private struct StatusLayoutRow: View {
    let item: SettingsStatusItem
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsColors.secondaryText)
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SettingsColors.secondaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SettingsColors.divider, lineWidth: 1)
                }
        }
    }
}

private struct WidgetOptionCard: View {
    let widget: SettingsWidget
    let isEnabled: Bool
    let onToggle: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: widget.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.035))
                    }

                Spacer()

                Text(widget.tag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(widget.tag == "Pro" ? .orange : .green)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background {
                        Capsule()
                            .fill((widget.tag == "Pro" ? Color.orange : Color.green).opacity(0.12))
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(widget.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsColors.primaryText)
                Text(widget.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack {
                if widget.settingsPage != nil || widget == .imageCard {
                    Button(widget == .imageCard ? "选择图片" : "设置", action: onSettings)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Toggle("", isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.84)
            }
        }
        .padding(14)
        .opacity(isEnabled ? 1 : 0.52)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SettingsColors.divider, lineWidth: 1)
                }
        }
    }
}

private enum SettingsMusicSupportedApp: CaseIterable, Identifiable {
    case appleMusic
    case spotify

    var id: String { bundleIdentifier }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    var bundleIdentifier: String {
        bundleIdentifiers[0]
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .appleMusic: ["com.apple.Music"]
        case .spotify: ["com.spotify.client"]
        }
    }

    var imageResource: (name: String, extension: String)? {
        switch self {
        case .appleMusic: ("music", "png")
        case .spotify: ("spotify", "png")
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .appleMusic: Color(red: 0.98, green: 0.22, blue: 0.36)
        case .spotify: Color(red: 0.11, green: 0.72, blue: 0.28)
        }
    }

    var icon: NSImage? {
        if let installedIcon = bundleIdentifiers.compactMap(installedAppIcon).first {
            return installedIcon
        }

        guard let resource = imageResource else {
            return nil
        }

        guard let url = Bundle.main.url(
            forResource: resource.name,
            withExtension: resource.extension
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private func installedAppIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct SettingsMusicSupportedAppCard: View {
    let app: SettingsMusicSupportedApp

    var body: some View {
        HStack(spacing: 12) {
            iconView

            Text(app.title)
                .font(AppTypography.rowTitle)
                .foregroundStyle(SettingsColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 8)

            Image(systemName: "waveform")
                .font(.system(size: AppIconStyle.actionSize, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 58)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(AppColor.controlFill.opacity(0.7))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 1)
                }
        }
    }

    private var iconView: some View {
        Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .padding(3)
                } else {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(app.fallbackColor)
                        .overlay {
                            Image(systemName: app.fallbackSymbolName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(SettingsColors.primaryText)
                    Text(subtitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(SettingsColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 20)

                Toggle("", isOn: $isOn)
                    .toggleStyle(SettingsSwitchToggleStyle())
                    .labelsHidden()
            }
            .frame(minHeight: 58)
            .padding(.horizontal, AppSpacing.rowHorizontal)
            .padding(.vertical, AppSpacing.rowVertical)

            if showsDivider {
                Rectangle()
                    .fill(SettingsColors.divider)
                    .frame(height: 1)
                    .padding(.leading, AppSpacing.rowHorizontal)
            }
        }
    }
}

private struct SettingsSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(trackColor(isOn: configuration.isOn))
                .frame(width: 52, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .shadow(color: Color.black.opacity(0.18), radius: 4, y: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
    }

    private func trackColor(isOn: Bool) -> Color {
        guard isEnabled else {
            return Color.black.opacity(0.14)
        }

        return isOn ? Color.accentColor : Color.black.opacity(0.14)
    }
}

private struct SettingsPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.82) : Color.accentColor)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SettingsColors.primaryText)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(SettingsColors.divider, lineWidth: 1)
                    }
            }
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

enum SettingsColors {
    static let sidebarBackground = AppColor.sidebarBackground
    static let contentBackground = AppColor.pageBackground
    static let cardBackground = AppColor.elevatedSurface
    static let selectedSidebarItem = AppColor.accentSoft
    static let primaryText = AppColor.textPrimary
    static let secondaryText = AppColor.textSecondary
    static let divider = AppColor.divider
}
