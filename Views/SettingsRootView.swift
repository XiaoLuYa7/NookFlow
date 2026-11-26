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
    case license
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
        case .license: "许可"
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
        case .license: "key"
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
        case .mirror: "摄像头仅在卡片可见时开启"
        case .pomodoro: "专注计时提醒"
        case .weather: "查看天气与体感"
        case .music: "播放信息与歌词"
        case .quickApps: "常用应用启动"
        case .shortcuts: "运行系统快捷指令"
        case .imageCard: "展示图片或循环播放文件夹"
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
        case .quickApps: "square.grid.2x2"
        case .shortcuts: "bolt"
        case .imageCard: "photo"
        case .deviceInfo: "desktopcomputer"
        }
    }

    var requiresPro: Bool {
        self == .todo || self == .music
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
    @Published var showDesktopLyrics = true { didSet { markChanged() } }
    @Published var lyricsPresentationMode: LyricsPresentationMode = .desktop {
        didSet { markChanged() }
    }
    @Published var capsuleLyricsWidth = CapsuleLyricsLayout.defaultWidth { didSet { markChanged() } }
    @Published var capsuleLyricsFontSize = CapsuleLyricsLayout.defaultFontSize { didSet { markChanged() } }
    @Published var menuBarLyricsWidth = 220.0 { didSet { markChanged() } }
    @Published var menuBarLyricsShowsPlaybackControls = true {
        didSet { markChanged() }
    }
    @Published var allowAppleMusicAccess = true { didSet { markChanged() } }
    @Published var allowSpotifyAccess = false { didSet { markChanged() } }
    @Published var allowQQMusicAccess = false { didSet { markChanged() } }
    @Published var allowNetEaseMusicAccess = false { didSet { markChanged() } }
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
    @Published var imageCardBookmarkData = Data() {
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
        imageCardBookmarkData = settings.imageCardBookmarkData
        leftStatusItems = [.network, .lunar, .battery, .temperature]
        rightStatusItems = [.calendar, .clock, .humidity, .weather]
        enabledWidgets = defaultEnabledWidgets(from: settings)
        showDesktopLyrics = settings.showDesktopLyrics
        lyricsPresentationMode = settings.lyricsPresentationMode
        capsuleLyricsWidth = settings.capsuleLyricsWidth
        capsuleLyricsFontSize = settings.capsuleLyricsFontSize
        menuBarLyricsWidth = settings.menuBarLyricsWidth
        menuBarLyricsShowsPlaybackControls = settings.menuBarLyricsShowsPlaybackControls
        allowAppleMusicAccess = settings.allowAppleMusicAccess
        allowSpotifyAccess = settings.allowSpotifyAccess
        allowQQMusicAccess = settings.allowQQMusicAccess
        allowNetEaseMusicAccess = settings.allowNetEaseMusicAccess
        syncSelectedItems()
        showFeedbackSheet = false
        limitNotice = nil
        isLoading = false
    }

    private func persistSettings() {
        update(\.showWeatherModule, to: enabledWidgets.contains(.weather))
        update(\.showMediaModule, to: enabledWidgets.contains(.music))
        update(\.showTodoModule, to: enabledWidgets.contains(.todo))
        update(\.showQuickAppsModule, to: enabledWidgets.contains(.quickApps))
        update(\.showShortcutsModule, to: enabledWidgets.contains(.shortcuts))
        update(\.showImageCardModule, to: enabledWidgets.contains(.imageCard))
        update(\.showDeviceInfoModule, to: enabledWidgets.contains(.deviceInfo))
        update(\.showMirrorModule, to: enabledWidgets.contains(.mirror))
        update(\.imageCardPath, to: imageCardPath)
        update(\.imageCardBookmarkData, to: imageCardBookmarkData)
        update(\.showDesktopLyrics, to: showDesktopLyrics)
        update(\.lyricsPresentationMode, to: lyricsPresentationMode)
        update(\.capsuleLyricsWidth, to: capsuleLyricsWidth)
        update(\.capsuleLyricsFontSize, to: capsuleLyricsFontSize)
        update(\.menuBarLyricsWidth, to: menuBarLyricsWidth)
        update(
            \.menuBarLyricsShowsPlaybackControls,
            to: menuBarLyricsShowsPlaybackControls
        )
        update(\.allowAppleMusicAccess, to: allowAppleMusicAccess)
        update(\.allowSpotifyAccess, to: allowSpotifyAccess)
        update(\.allowQQMusicAccess, to: allowQQMusicAccess)
        update(\.allowNetEaseMusicAccess, to: allowNetEaseMusicAccess)
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
        if settings.showQuickAppsModule { result.insert(.quickApps) }
        if settings.showShortcutsModule { result.insert(.shortcuts) }
        if settings.showImageCardModule { result.insert(.imageCard) }
        if settings.showDeviceInfoModule { result.insert(.deviceInfo) }
        if settings.showMirrorModule { result.insert(.mirror) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var settings: IslandSettings
    @StateObject private var model: SettingsEditorModel
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var isSidebarCollapsed = false
    @State private var previewImageCardImage: NSImage?
    @State private var previewImageCardImagePath = ""
    @State private var previewImageCardLoadTask: Task<Void, Never>?
    @State private var pendingProWidget: SettingsWidget?
    @State private var isShowingProActivation = false

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
                selection: settingsPageSelection,
                isCollapsed: $isSidebarCollapsed,
                onLicenseRequested: presentLicenseActivation
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
            Task { await licenseManager.refreshIfNeeded() }
        }
        .onChange(of: model.imageCardPath) { _, _ in
            loadPreviewImageCardThumbnailIfNeeded()
        }
        .onChange(of: model.imageCardBookmarkData) { _, _ in
            previewImageCardImagePath = ""
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
        .overlay {
            if isShowingProActivation {
                ProActivationModal(
                    manager: licenseManager,
                    requestedFeatureName: pendingProWidget?.title,
                    onActivated: {
                        completeProActivation()
                    },
                    onClose: dismissProActivation
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
                )
                .zIndex(10)
            }
        }
    }

    private func consumeNavigationTriggers() {
        if model.selectedSettingsPage == .license {
            model.selectedSettingsPage = .home
            presentLicenseActivation()
        }
        if settings.quickAppsSettingsTrigger {
            model.selectedSettingsPage = .quickApps
            settings.quickAppsSettingsTrigger = false
        }
        if settings.shortcutsSettingsTrigger {
            model.selectedSettingsPage = .shortcuts
            settings.shortcutsSettingsTrigger = false
        }
    }

    private var settingsPageSelection: Binding<SettingsPage> {
        Binding(
            get: { model.selectedSettingsPage },
            set: { requestedPage in
                guard requestedPage != .license else {
                    presentLicenseActivation()
                    return
                }
                model.selectedSettingsPage = requestedPage
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        selectedPageContent
            .id(model.selectedSettingsPage)
            .transition(.opacity)
            .animation(
                AppMotion.resolved(AppMotion.settingsPage, reduceMotion: reduceMotion),
                value: model.selectedSettingsPage
            )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.pageBackground)
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch model.selectedSettingsPage {
        case .home:
            homePage
        case .todo:
            TodoView(settings: settings)
        case .music:
            musicPage
        case .quickApps:
            QuickAppsSettingsView(settings: settings)
        case .shortcuts:
            ShortcutsSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .license:
            LicenseSettingsView(manager: licenseManager)
        case .general:
            GeneralSettingsView(settings: settings)
        case .about:
            AboutView {
                model.showFeedbackSheet = true
            }
        }
    }

    private var homePage: some View {
        SettingsPageScaffold(contentMaxWidth: 1120) {
            PageHeaderView(
                title: "首页",
                subtitle: "预览并选择要在灵动岛中显示的内容。",
                icon: "house.fill"
            )
        } content: {
            previewArea
            sideIconConfigurationCard
            widgetsCard
            moduleOrderSection
        }
    }

    private var musicPage: some View {
        SettingsPageScaffold {
            PageHeaderView(
                title: "音乐",
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
        SettingsCard(spacing: 14) {
            HStack(spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    SectionTitle(title: "灵动岛预览", systemName: "sparkles.rectangle.stack")
                    Text("效果预览 · 示例内容，非设备实时数据。")
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: AppSpacing.lg)

                PillSegmentedControl(
                    options: [SettingsPreviewMode.normal, .expanded],
                    selection: $model.selectedPreviewMode,
                    title: { $0.title }
                )
                .frame(width: 190)
            }

            islandPreview
                .frame(height: 254)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColor.accentSoft.opacity(0.52),
                                    AppColor.controlFill.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 1)
                }
        }
    }

    private var islandPreview: some View {
        GeometryReader { proxy in
            let previewWidth = max(320, proxy.size.width - 12)
            let computerHeight = min(
                max(180, previewWidth * 0.34),
                max(180, proxy.size.height - 10)
            )
            let screenTopInset = max(20, previewWidth * (70 / 1972))
            let screenHorizontalInset = max(18, previewWidth * (74 / 1972))
            let screenWidth = max(280, previewWidth - (screenHorizontalInset * 2))
            let usesSideStatus = model.leftSideIcon != .none || model.rightSideIcon != .none
            let expandedSize = IslandShellLayout.contentSize(
                settings: settings,
                selectedTopTab: .home
            )
            let availableIslandHeight = max(80, computerHeight - screenTopInset - 20)
            let expandedScale = min(
                1,
                min(
                    (screenWidth - 16) / max(1, expandedSize.width),
                    availableIslandHeight / max(1, expandedSize.height)
                )
            )
            let islandWidth: CGFloat = {
                switch model.selectedPreviewMode {
                case .normal:
                    return usesSideStatus
                        ? min(screenWidth * 0.56, 520)
                        : min(screenWidth * 0.36, 340)
                case .playing:
                    return min(screenWidth * 0.56, 520)
                case .expanded:
                    return expandedSize.width * expandedScale
                }
            }()
            let islandHeight = model.selectedPreviewMode == .expanded
                ? expandedSize.height * expandedScale
                : 62

            ZStack(alignment: .top) {
                cameraStripPreview(width: previewWidth, height: computerHeight)

                previewIsland(
                    width: islandWidth,
                    height: islandHeight,
                    expandedScale: expandedScale
                )
                    .padding(.top, screenTopInset)
                    .animation(AppMotion.resolved(AppMotion.page, reduceMotion: reduceMotion), value: model.selectedPreviewMode)
                    .animation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion), value: model.leftSideIcon)
                    .animation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion), value: model.rightSideIcon)
                    .animation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion), value: settings.moduleOrder)

                computerScreenGlassOverlay(
                    width: previewWidth,
                    height: computerHeight,
                    screenTopInset: screenTopInset,
                    screenHorizontalInset: screenHorizontalInset
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func cameraStripPreview(width: CGFloat, height: CGFloat) -> some View {
        let displayHeight = max(1, height - 12)

        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color(red: 0.018, green: 0.026, blue: 0.038)

                Image("ComputerPreviewBackground")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: displayHeight, alignment: .top)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.14), location: 0),
                        .init(color: Color.white.opacity(0.025), location: 0.28),
                        .init(color: Color.clear, location: 0.62),
                        .init(color: Color.black.opacity(0.24), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.34)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: displayHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.58),
                                Color.white.opacity(0.12),
                                Color.black.opacity(0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .inset(by: 3)
                            .stroke(Color.black.opacity(0.68), lineWidth: 2)
                    }
            }

            ZStack(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.88),
                                Color(red: 0.54, green: 0.57, blue: 0.62),
                                Color(red: 0.20, green: 0.22, blue: 0.26)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width * 0.91, height: 9)

                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .frame(width: width * 0.16, height: 2)
                    .padding(.top, 1)
            }
            .frame(width: width, height: 12, alignment: .top)
        }
        .frame(width: width, height: height, alignment: .top)
        .shadow(color: Color.black.opacity(0.17), radius: 18, y: 9)
    }

    private func computerScreenGlassOverlay(
        width: CGFloat,
        height: CGFloat,
        screenTopInset: CGFloat,
        screenHorizontalInset: CGFloat
    ) -> some View {
        let screenWidth = max(1, width - (screenHorizontalInset * 2))
        let screenHeight = max(1, height - screenTopInset - 18)

        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.09), location: 0),
                    .init(color: Color.white.opacity(0.018), location: 0.24),
                    .init(color: Color.clear, location: 0.58),
                    .init(color: Color.black.opacity(0.08), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [Color.black.opacity(0.22), Color.clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.16)
            )
        }
        .frame(width: screenWidth, height: screenHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.black.opacity(0.46), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
        }
        .padding(.top, screenTopInset)
        .allowsHitTesting(false)
    }

    private func previewIsland(
        width: CGFloat,
        height: CGFloat,
        expandedScale: CGFloat
    ) -> some View {
        previewIslandContent(
            width: width,
            height: height,
            expandedScale: expandedScale
        )
        .frame(width: width, height: height)
        .background(Color.black)
        .clipShape(previewIslandShape(width: width, height: height))
        .contentShape(previewIslandShape(width: width, height: height))
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
    }

    @ViewBuilder
    private func previewIslandContent(
        width: CGFloat,
        height: CGFloat,
        expandedScale: CGFloat
    ) -> some View {
        if model.selectedPreviewMode == .expanded {
            let actualSize = IslandShellLayout.contentSize(
                settings: settings,
                selectedTopTab: .home
            )

            previewExpandedContent(
                width: actualSize.width,
                height: actualSize.height,
                scale: 1
            )
            .frame(width: actualSize.width, height: actualSize.height, alignment: .topLeading)
            .compositingGroup()
            .scaleEffect(expandedScale, anchor: .topLeading)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
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
                currentLyricTiming: nil,
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
        if model.selectedPreviewMode == .expanded {
            let actualSize = IslandShellLayout.contentSize(
                settings: settings,
                selectedTopTab: .home
            )
            let scale = width / max(1, actualSize.width)
            let metrics = IslandShellLayout.shellShapeMetrics(
                shellSize: actualSize,
                compactSize: IslandDesignTokens.defaultCompactCapsuleSize,
                morphProgress: 1
            )
            return DynamicIslandShape(
                shoulderWidth: metrics.shoulderWidth * scale,
                shoulderDepth: metrics.shoulderDepth * scale,
                sideInset: metrics.sideInset * scale,
                bottomCornerRadius: metrics.bottomCornerRadius * scale,
                visibleSize: CGSize(width: width, height: height)
            )
        }

        return DynamicIslandShape(
            shoulderWidth: min(54, width * 0.14),
            shoulderDepth: min(28, height * 0.46),
            sideInset: min(10, width * 0.04),
            bottomCornerRadius: 10,
            visibleSize: CGSize(width: width, height: height)
        )
    }

    private func previewExpandedContent(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat
    ) -> some View {
        let modules = IslandShellLayout.visibleModules(settings: settings)
        let actualHeight = IslandShellLayout.effectiveIslandHeight(settings: settings)
        let cardHeight = max(104, actualHeight - 38) * scale
        let itemSpacing = IslandShellLayout.moduleCardLayoutSpacing * scale
        let horizontalPadding = IslandDesignTokens.expandedPadding * scale

        return VStack(spacing: 0) {
            previewExpandedTopBar(scale: scale)

            if modules.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2")
                    Text("尚未启用卡片")
                }
                .font(.system(size: max(8, 12 * scale), weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: itemSpacing) {
                    ForEach(modules) { module in
                        previewWidgetCard(module, height: cardHeight)
                            .frame(
                                width: previewWidgetWidth(module, scale: scale),
                                height: cardHeight
                            )
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private func previewExpandedTopBar(scale: CGFloat) -> some View {
        HStack(spacing: max(5, 14 * scale)) {
            Text("NookFlow")
                .font(.system(size: max(8, 15 * scale), weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))
                .padding(.horizontal, max(4, 8 * scale))
                .frame(height: 24 * scale)
                .background(Color.white.opacity(0.14), in: Capsule())

            Image(systemName: "appstore")
            Image(systemName: "folder")

            Spacer(minLength: 0)

            if settings.showPinButton {
                Image(systemName: "lock.open")
            }
            Image(systemName: "gearshape.fill")
        }
        .font(.system(size: max(7, 12 * scale), weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.54))
        .padding(.horizontal, max(10, 22 * scale))
        .frame(height: IslandDesignTokens.expandedTopBarControlHeight * scale)
    }

    private func previewWidgetWidth(_ module: IslandPanelModule, scale: CGFloat) -> CGFloat {
        IslandShellLayout.moduleFixedWidth(
            module,
            quickAppsColumnCount: settings.quickAppsColumnCount
        ) * scale
    }

    @ViewBuilder
    private func previewWidgetCard(_ module: IslandPanelModule, height: CGFloat) -> some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape
                .fill(IslandDesignTokens.moduleSurface)
                .overlay { shape.strokeBorder(IslandDesignTokens.moduleBorder, lineWidth: 0.5) }

            switch module {
            case .imageCard:
                previewImageCardThumbnail
            case .deviceInfo:
                previewDeviceInfoThumbnail
            case .mirror:
                previewMirrorThumbnail
            case .media:
                previewMusicThumbnail
            case .weather:
                previewWeatherThumbnail
            case .quickApps:
                previewQuickAppsThumbnail
            case .shortcuts:
                previewShortcutsThumbnail
            case .todo:
                previewTodoThumbnail
            }
        }
    }

    private var previewImageCardThumbnail: some View {
        IslandImageCardArtwork(size: 52) {
            if let image = previewImageCardImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("ImageCardDefault")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewMirrorThumbnail: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 0) {
                    Text("镜子")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    Text("• 未开启")
                        .font(.system(size: 6.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }

                Spacer(minLength: 0)

                Image(systemName: "camera.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .frame(width: 19, height: 19)
                    .background(Color(red: 0.20, green: 0.62, blue: 0.61), in: Circle())
            }
            .foregroundStyle(Color.white.opacity(0.88))

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.32, blue: 0.35).opacity(0.72),
                            Color(red: 0.035, green: 0.055, blue: 0.065)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("点击开启镜子")
                            .font(.system(size: 6.8, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.white.opacity(0.76))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
                }
        }
        .padding(6)
    }

    private var previewTodoThumbnail: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("8月")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                ForEach([("周日", "2"), ("周一", "3"), ("周二", "4")], id: \.1) { day in
                    VStack(spacing: 1) {
                        Text(day.0)
                            .font(.system(size: 5.8, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.42))
                        Text(day.1)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(day.1 == "3" ? AppColor.accent : Color.white.opacity(0.58))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "ellipsis")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 18, height: 18)
                    .overlay { Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.7) }
            }

            Text("暂无已安排待办")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.40))

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white.opacity(0.90))
        .padding(9)
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

        let bookmarkData = model.imageCardBookmarkData
        previewImageCardLoadTask = Task { @MainActor in
            guard let sourceURL = ImageCardSourceAccess.resolveURL(
                path: path,
                bookmarkData: bookmarkData
            ) else { return }
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let urls = await Task.detached(priority: .utility) {
                ImageCardSourceAccess.imageURLs(in: sourceURL)
            }.value
            guard !Task.isCancelled, let url = urls.first else { return }
            let image = await ThreadSafeImageCache.shared.preview(
                for: url,
                targetSize: NSSize(width: 160, height: 160)
            )

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
            subtitle: "控制歌词的显示位置"
        ) {
            SettingsToggleRow(
                title: "开启歌词展示",
                subtitle: "在胶囊、桌面或 macOS 菜单栏显示当前歌词",
                isOn: $model.showDesktopLyrics
            )
            SettingsSegmentedRow(
                icon: nil,
                title: "展示位置",
                subtitle: "桌面展示使用独立歌词窗口；菜单栏展示会占用菜单栏空间",
                options: LyricsPresentationMode.allCases,
                optionTitle: { $0.title(language: settings.language) },
                isEnabled: model.showDesktopLyrics,
                selection: $model.lyricsPresentationMode
            )
            if model.lyricsPresentationMode == .capsule {
                SettingsSliderRow(
                    icon: nil, title: "胶囊宽度",
                    subtitle: "整个歌词胶囊的宽度，包含刘海安全区；实际宽度受屏幕空间限制",
                    value: $model.capsuleLyricsWidth, in: CapsuleLyricsLayout.widthRange, step: 1,
                    isEnabled: model.showDesktopLyrics,
                    valueText: { "\(Int($0)) pt" }
                )
                SettingsSliderRow(
                    icon: nil, title: "字体大小", subtitle: "同时调整左右歌词和绿色扫词高亮",
                    value: $model.capsuleLyricsFontSize, in: CapsuleLyricsLayout.fontSizeRange, step: 0.5,
                    isEnabled: model.showDesktopLyrics, showsDivider: false,
                    valueText: { String(format: "%.1f pt", $0) }
                )
            }
            if model.lyricsPresentationMode == .menuBar {
                SettingsSliderRow(
                    icon: nil,
                    title: "歌词显示宽度",
                    subtitle: "菜单栏空间不足时，系统可能隐藏部分状态项目",
                    value: menuBarLyricsDisplayedWidth,
                    in: MenuBarLyricsLayout.displayedWidthRange(
                        showsPlaybackControls: model.menuBarLyricsShowsPlaybackControls
                    ),
                    step: 1,
                    isEnabled: model.showDesktopLyrics,
                    valueText: { "\(Int($0)) pt" }
                )
                SettingsToggleRow(
                    title: "菜单栏常驻播控",
                    subtitle: "显示上一首、播放或暂停、下一首",
                    isOn: $model.menuBarLyricsShowsPlaybackControls,
                    isEnabled: model.showDesktopLyrics,
                    showsDivider: false
                )
            }
        }
    }

    private var menuBarLyricsDisplayedWidth: Binding<Double> {
        Binding(
            get: {
                Double(MenuBarLyricsLayout.displayedWidth(
                    lyricsWidth: model.menuBarLyricsWidth,
                    showsPlaybackControls: model.menuBarLyricsShowsPlaybackControls
                ))
            },
            set: { displayedWidth in
                model.menuBarLyricsWidth = MenuBarLyricsLayout.preferredLyricsWidth(
                    fromDisplayedWidth: displayedWidth,
                    showsPlaybackControls: model.menuBarLyricsShowsPlaybackControls
                )
            }
        )
    }

    private var musicAccessSection: some View {
        SettingsSectionCard(
            title: "应用访问",
            subtitle: "选择允许 NookFlow 读取播放信息的应用",
            footer: "QQ 音乐与网易云音乐通过 macOS 系统媒体中心读取；播放器需先出现在系统控制中心的“正在播放”中。"
        ) {
            SettingsToggleRow(
                title: "Apple Music",
                subtitle: "允许读取 Apple Music 的播放状态与歌曲信息",
                isOn: $model.allowAppleMusicAccess
            )
            SettingsToggleRow(
                title: "Spotify",
                subtitle: "允许读取 Spotify 的播放状态与歌曲信息",
                isOn: $model.allowSpotifyAccess
            )
            SettingsToggleRow(
                title: "QQ音乐",
                subtitle: "通过系统媒体中心读取 QQ 音乐播放信息",
                isOn: $model.allowQQMusicAccess
            )
            SettingsToggleRow(
                title: "网易云音乐",
                subtitle: "通过系统媒体中心读取网易云音乐播放信息",
                isOn: $model.allowNetEaseMusicAccess,
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

    private var widgetsCard: some View {
        SettingsCard(spacing: 16) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    SectionTitle(title: "小组件与卡片", systemName: "rectangle.3.group")
                    Text("选择真正需要的内容，灵动岛会按固定尺寸从左向右排列。")
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: AppSpacing.lg)

                Text("已启用 \(enabledHomeWidgetCount) / \(homeWidgets.count)")
                    .font(AppTypography.control)
                    .foregroundStyle(AppColor.accent)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(height: 28)
                    .background(AppColor.accentSoft, in: Capsule(style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    ForEach(homeWidgets) { widget in
                        WidgetOptionCard(
                            widget: widget,
                            isEnabled: isWidgetEffectivelyEnabled(widget),
                            isProUnlocked: licenseManager.isProUnlocked,
                            onToggle: {
                                guard !widget.requiresPro || licenseManager.isProUnlocked else {
                                    presentProActivation(for: widget)
                                    return
                                }
                                withAnimation(.easeOut(duration: 0.16)) {
                                    model.toggleWidget(widget)
                                }
                            },
                            onSettings: {
                                if widget == .imageCard {
                                    chooseImageCardSource()
                                } else if let page = widget.settingsPage {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        model.selectedSettingsPage = page
                                    }
                                }
                            }
                        )
                        .frame(width: 204, height: 148)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
    }

    private var moduleOrderSection: some View {
        let modules = IslandShellLayout.visibleModules(settings: settings)

        return SettingsSectionCard(
            title: "卡片顺序",
            subtitle: "上下拖动已启用的卡片，对应灵动岛从左到右的顺序。"
        ) {
            if modules.isEmpty {
                Text("启用卡片后即可调整顺序。")
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
            }

            ForEach(modules) { module in
                ModuleOrderRow(module: module) { source in
                    moveModule(source, to: module)
                } onStep: { step in
                    let current = IslandShellLayout.visibleModules(settings: settings)
                    guard let index = current.firstIndex(of: module),
                          current.indices.contains(index + step) else { return }
                    moveModule(module, to: current[index + step])
                }
            }
        }
    }

    private func moveModule(_ source: IslandPanelModule, to target: IslandPanelModule) {
        var modules = IslandShellLayout.visibleModules(settings: settings)
        guard let from = modules.firstIndex(of: source),
              let to = modules.firstIndex(of: target), from != to else { return }

        modules.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion)) {
            IslandShellLayout.saveVisibleModuleOrder(modules, settings: settings)
        }
    }

    private var homeWidgets: [SettingsWidget] {
        [.mirror, .imageCard, .todo, .deviceInfo, .weather, .music, .quickApps, .shortcuts]
    }

    private var enabledHomeWidgetCount: Int {
        homeWidgets.filter(isWidgetEffectivelyEnabled).count
    }

    private func isWidgetEffectivelyEnabled(_ widget: SettingsWidget) -> Bool {
        model.enabledWidgets.contains(widget)
            && (!widget.requiresPro || licenseManager.isProUnlocked)
    }

    private func chooseImageCardSource() {
        let panel = NSOpenPanel()
        panel.title = "选择一张图片或图片文件夹"
        panel.message = "选择文件夹后，灵动岛会循环展示其中的图片。"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            model.imageCardPath = url.path
            model.imageCardBookmarkData = ImageCardSourceAccess.bookmarkData(for: url) ?? Data()
            model.enabledWidgets.insert(.imageCard)
        }
    }

    private func presentProActivation(for widget: SettingsWidget) {
        licenseManager.resetError()
        withAnimation(AppMotion.resolved(AppMotion.settingsPage, reduceMotion: reduceMotion)) {
            pendingProWidget = widget
            isShowingProActivation = true
        }
    }

    private func presentLicenseActivation() {
        licenseManager.resetError()
        withAnimation(AppMotion.resolved(AppMotion.settingsPage, reduceMotion: reduceMotion)) {
            pendingProWidget = nil
            isShowingProActivation = true
        }
    }

    private func completeProActivation() {
        withAnimation(AppMotion.resolved(AppMotion.settingsStandard, reduceMotion: reduceMotion)) {
            if let pendingProWidget {
                model.enabledWidgets.insert(pendingProWidget)
            }
            pendingProWidget = nil
            isShowingProActivation = false
        }
    }

    private func dismissProActivation() {
        withAnimation(AppMotion.resolved(AppMotion.settingsQuick, reduceMotion: reduceMotion)) {
            pendingProWidget = nil
            isShowingProActivation = false
        }
    }

}

private struct FeedbackMailSheet: View {
    let onClose: () -> Void

    private let supportEmail = "lujunfeng.lucky@foxmail.com"

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
                    .buttonStyle(AppButtonStyle(role: .secondary))
                    .frame(width: 128)

                Button {
                    openFeedbackMail()
                    onClose()
                } label: {
                    Label("发送邮件", systemImage: "paperplane.fill")
                }
                .buttonStyle(AppButtonStyle(role: .primary))
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
        let subject = "NookFlow 问题反馈"
        let body = """
        您好，我想反馈 NookFlow 使用中的问题或建议：

        问题描述：

        复现步骤：
        1.
        2.
        3.

        期望效果：

        设备与版本：
        - NookFlow: \(appVersion) (\(build))
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
        .appSurface(.elevated, radius: AppRadius.largeCard)
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

private struct SideIconPickerSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    withAnimation(AppMotion.resolved(AppMotion.quick, reduceMotion: reduceMotion)) {
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
        .background {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(isHovering ? AppColor.controlFillHover : .clear)
        }
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                .fill(AppColor.islandBackground)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? AppColor.accent : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: .black.opacity(0.06),
                    radius: 3,
                    x: 0,
                    y: 2
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

private struct ModuleOrderRow: View {
    private static let dragType = UTType(exportedAs: "cn.luckysoft.nookflow.module-order", conformingTo: .data)

    let module: IslandPanelModule
    let onDropModule: (IslandPanelModule) -> Void
    let onStep: (Int) -> Void
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: module.systemName)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 20)
            Text(module.title)
                .font(AppTypography.control)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(AppColor.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(height: 36)
        .background(isDropTarget ? AppColor.accentSoft : AppColor.controlFill, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onDrag {
            let provider = NSItemProvider()
            let payload = Data(module.rawValue.utf8)
            provider.registerDataRepresentation(for: Self.dragType, visibility: .ownProcess) { completion in
                completion(payload, nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [Self.dragType], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(for: Self.dragType) { data, _ in
                guard let data, let rawValue = String(data: data, encoding: .utf8),
                      let source = IslandPanelModule(rawValue: rawValue) else { return }
                Task { @MainActor in onDropModule(source) }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("上移")) { onStep(-1) }
        .accessibilityAction(named: Text("下移")) { onStep(1) }
    }
}

private struct WidgetOptionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let widget: SettingsWidget
    let isEnabled: Bool
    let isProUnlocked: Bool
    let onToggle: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top) {
                Image(systemName: widget.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isEnabled ? accent : AppColor.textTertiary)
                    .frame(width: 36, height: 36)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(isEnabled ? accent.opacity(0.12) : AppColor.controlFill)
                    }

                Spacer()

                if widget.requiresPro {
                    WidgetProBadge(isUnlocked: isProUnlocked)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(widget.title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text(widget.subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                if widget.settingsPage != nil || widget == .imageCard {
                    Button(action: onSettings) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(widget == .imageCard ? "选择来源" : "设置")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                        .buttonStyle(.plain)
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.accent)
                }

                Spacer()

                Toggle(widget.title, isOn: Binding(get: { isEnabled }, set: { _ in onToggle() }))
                    .toggleStyle(AppSwitchToggleStyle())
                    .labelsHidden()
            }
        }
        .padding(AppSpacing.md)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                .fill(
                    isEnabled
                        ? LinearGradient(
                            colors: [accent.opacity(0.04), Color.white.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color.white.opacity(0.84), Color.white.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                        .stroke(
                            isEnabled ? accent.opacity(0.14) : AppColor.border,
                            lineWidth: isEnabled ? 1 : 0.7
                        )
                }
                .shadow(
                    color: Color.black.opacity(isHovering ? 0.045 : 0.025),
                    radius: 7,
                    y: 3
                )
        }
        .onHover { isHovering = $0 }
        .animation(
            AppMotion.resolved(AppMotion.settingsQuick, reduceMotion: reduceMotion),
            value: isHovering
        )
        .animation(
            AppMotion.resolved(AppMotion.settingsStandard, reduceMotion: reduceMotion),
            value: isEnabled
        )
        .accessibilityElement(children: .contain)
    }

    private var accent: Color {
        switch widget {
        case .mirror: Color(red: 0.18, green: 0.68, blue: 0.66)
        case .imageCard: Color(red: 0.49, green: 0.36, blue: 0.92)
        case .todo: Color(red: 0.93, green: 0.48, blue: 0.22)
        case .deviceInfo: Color(red: 0.16, green: 0.58, blue: 0.86)
        case .weather: Color(red: 0.18, green: 0.54, blue: 0.94)
        case .music: Color(red: 0.94, green: 0.25, blue: 0.43)
        case .quickApps: Color(red: 0.20, green: 0.64, blue: 0.43)
        case .shortcuts: AppColor.accent
        default: AppColor.accent
        }
    }
}

private struct WidgetProBadge: View {
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isUnlocked ? "sparkles" : "lock.fill")
                .font(.system(size: 9, weight: .bold))
            Text("PRO")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isUnlocked ? AppColor.accent : Color(red: 0.28, green: 0.45, blue: 0.88))
        .padding(.horizontal, 9)
        .frame(height: 23)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.94, blue: 1.0),
                            Color(red: 0.95, green: 0.91, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
                }
                .shadow(color: AppColor.accent.opacity(0.12), radius: 5, y: 2)
        }
        .accessibilityLabel(isUnlocked ? "Pro 已激活" : "Pro 功能")
    }
}

private enum SettingsMusicSupportedApp: CaseIterable, Identifiable {
    case appleMusic
    case spotify
    case qqMusic
    case netEaseMusic

    var id: String { bundleIdentifier }

    var title: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .qqMusic: "QQ音乐"
        case .netEaseMusic: "网易云音乐"
        }
    }

    var bundleIdentifier: String {
        bundleIdentifiers[0]
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .appleMusic: ["com.apple.Music"]
        case .spotify: ["com.spotify.client"]
        case .qqMusic: ["com.tencent.QQMusicMac"]
        case .netEaseMusic: ["com.netease.163music", "com.netease.163music.mac", "com.netease.cloudmusic"]
        }
    }

    var imageResource: (name: String, extension: String)? {
        switch self {
        case .appleMusic: ("music", "png")
        case .spotify: ("spotify", "png")
        case .qqMusic, .netEaseMusic: nil
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        case .qqMusic: "q.circle.fill"
        case .netEaseMusic: "waveform.circle.fill"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .appleMusic: Color(red: 0.98, green: 0.22, blue: 0.36)
        case .spotify: Color(red: 0.11, green: 0.72, blue: 0.28)
        case .qqMusic: Color(red: 0.98, green: 0.78, blue: 0.10)
        case .netEaseMusic: Color(red: 0.90, green: 0.10, blue: 0.12)
        }
    }

    var icon: NSImage? {
        if self == .netEaseMusic, let icon = AppCachedImageAssets.netEaseMusicIcon {
            return icon
        }
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

            Text("兼容")
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
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
    var isEnabled = true
    var showsDivider = true

    var body: some View {
        AppSettingsToggleRow(
            icon: nil,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsDivider: showsDivider,
            isOn: $isOn
        )
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
