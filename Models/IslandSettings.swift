import AppKit
import ServiceManagement
import SwiftUI

enum IslandLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }
}

enum AppFontPreference: String, CaseIterable, Identifiable {
    case system
    case rounded

    var id: String { rawValue }
    var title: String { self == .system ? "系统字体" : "圆润字体" }
    var fontDesign: Font.Design { self == .system ? .default : .rounded }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: fontDesign)
    }

    var sampleText: String {
        switch self {
        case .system: "灵动岛提醒 24°"
        case .rounded: "灵动岛提醒 24°"
        }
    }

    var note: String {
        switch self {
        case .system: "使用 macOS 默认字体，中文边缘更利落。"
        case .rounded: "圆润字体主要让数字、英文和符号更柔和，中文变化会比较轻。"
        }
    }
}

enum IslandBounceLevel: String, CaseIterable, Identifiable {
    case subtle
    case standard
    case lively

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: "克制"
        case .standard: "自然"
        case .lively: "轻弹"
        }
    }

    var dampingFraction: Double {
        switch self {
        case .subtle: 0.97
        case .standard: 0.91
        case .lively: 0.86
        }
    }

    var widthOvershoot: CGFloat {
        switch self {
        case .subtle: 1.008
        case .standard: 1.022
        case .lively: 1.038
        }
    }

    var heightOvershoot: CGFloat {
        switch self {
        case .subtle: 1.005
        case .standard: 1.014
        case .lively: 1.024
        }
    }

    var undershootScale: CGFloat {
        switch self {
        case .subtle: 0.998
        case .standard: 0.991
        case .lively: 0.984
        }
    }
}

enum IslandExpansionMode: String, CaseIterable, Identifiable {
    case click
    case hover

    var id: String { rawValue }
    var title: String { self == .click ? "点击展开" : "悬浮展开" }
}

enum TutorialHintPolicy: String, CaseIterable, Identifiable {
    case once
    case always
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "一次"
        case .always: "持续"
        case .off: "关闭"
        }
    }
}

enum ForegroundAppPromptDisplayMode: String, CaseIterable, Identifiable {
    case applicationName
    case memoryUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationName: "应用名称"
        case .memoryUsage: "内存占用"
        }
    }
}

enum TrackpadFeedbackMode: String, CaseIterable, Identifiable {
    case off
    case single
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "关闭"
        case .single: "单次"
        case .continuous: "连续"
        }
    }
}

@MainActor
enum TrackpadHapticFeedback {
    static func perform(_ mode: TrackpadFeedbackMode) {
        guard mode != .off else { return }

        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(.alignment, performanceTime: .now)

        guard mode == .continuous else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            performer.perform(.levelChange, performanceTime: .now)
        }
    }
}

enum IslandBackgroundStyle: String, CaseIterable, Identifiable {
    case solid
    case glass

    var id: String { rawValue }
    var title: String { self == .solid ? "深色纯净" : "柔和玻璃" }
}

enum IslandDisplayStrategy: String, CaseIterable, Identifiable {
    case builtIn
    case main
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "仅内建屏"
        case .main: "仅主屏"
        case .all: "所有屏幕"
        }
    }
}

enum DesktopLyricsPosition: String, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    func title(language: IslandLanguage) -> String {
        switch (language, self) {
        case (.chinese, .topLeft): "左上角"
        case (.chinese, .topCenter): "顶部居中"
        case (.chinese, .topRight): "右上角"
        case (.chinese, .bottomLeft): "左下角"
        case (.chinese, .bottomCenter): "底部居中"
        case (.chinese, .bottomRight): "右下角"
        case (.english, .topLeft): "Top Left"
        case (.english, .topCenter): "Top Center"
        case (.english, .topRight): "Top Right"
        case (.english, .bottomLeft): "Bottom Left"
        case (.english, .bottomCenter): "Bottom Center"
        case (.english, .bottomRight): "Bottom Right"
        }
    }
}

enum DesktopLyricsColorMode: String, CaseIterable, Identifiable {
    case automatic
    case lightText
    case darkText

    var id: String { rawValue }

    func title(language: IslandLanguage) -> String {
        switch (language, self) {
        case (.chinese, .automatic): "自动"
        case (.chinese, .lightText): "浅色文字"
        case (.chinese, .darkText): "深色文字"
        case (.english, .automatic): "Automatic"
        case (.english, .lightText): "Light text"
        case (.english, .darkText): "Dark text"
        }
    }
}

enum CalendarStyle: String, CaseIterable, Identifiable {
    case weeklySchedule
    case monthlyGrid
    case dotMatrix

    var id: String { rawValue }

    func title(language: IslandLanguage) -> String {
        switch (language, self) {
        case (.chinese, .weeklySchedule): "周视图"
        case (.chinese, .monthlyGrid): "月视图"
        case (.chinese, .dotMatrix): "点阵视图"
        case (.english, .weeklySchedule): "Weekly"
        case (.english, .monthlyGrid): "Monthly"
        case (.english, .dotMatrix): "Dot Matrix"
        }
    }
}

@MainActor
final class IslandSettings: ObservableObject {

    @Published var fontPreference: AppFontPreference {
        didSet { save(fontPreference.rawValue, for: Keys.fontPreference) }
    }

    @Published var isIslandEnabled: Bool {
        didSet { save(isIslandEnabled, for: Keys.isIslandEnabled) }
    }

    @Published var showCustomCompactIcons: Bool {
        didSet { save(showCustomCompactIcons, for: Keys.showCustomCompactIcons) }
    }

    @Published var language: IslandLanguage {
        didSet { save(language.rawValue, for: Keys.language) }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    @Published var hideMenuBar: Bool {
        didSet {
            save(hideMenuBar, for: Keys.hideMenuBar)
            applyPresentationOptions()
        }
    }

    @Published var showPinButton: Bool {
        didSet { save(showPinButton, for: Keys.showPinButton) }
    }

    @Published var hideInFullscreen: Bool {
        didSet { save(hideInFullscreen, for: Keys.hideInFullscreen) }
    }

    @Published var bounceLevel: IslandBounceLevel {
        didSet { save(bounceLevel.rawValue, for: Keys.bounceLevel) }
    }

    @Published var expansionMode: IslandExpansionMode {
        didSet { save(expansionMode.rawValue, for: Keys.expansionMode) }
    }

    @Published var hoverExpansionDelay: Double {
        didSet { save(hoverExpansionDelay, for: Keys.hoverExpansionDelay) }
    }

    @Published var tutorialHintPolicy: TutorialHintPolicy {
        didSet { save(tutorialHintPolicy.rawValue, for: Keys.tutorialHintPolicy) }
    }

    @Published private(set) var hasShownTutorialHint: Bool

    @Published var foregroundAppLinkEnabled: Bool {
        didSet { save(foregroundAppLinkEnabled, for: Keys.foregroundAppLinkEnabled) }
    }

    @Published var foregroundAppPromptDisplayMode: ForegroundAppPromptDisplayMode {
        didSet { save(foregroundAppPromptDisplayMode.rawValue, for: Keys.foregroundAppPromptDisplayMode) }
    }

    @Published var foregroundHoldDuration: Double {
        didSet { save(foregroundHoldDuration, for: Keys.foregroundHoldDuration) }
    }

    @Published var trackpadFeedbackMode: TrackpadFeedbackMode {
        didSet { save(trackpadFeedbackMode.rawValue, for: Keys.trackpadFeedbackMode) }
    }

    @Published var islandBackgroundStyle: IslandBackgroundStyle {
        didSet { save(islandBackgroundStyle.rawValue, for: Keys.islandBackgroundStyle) }
    }

    @Published var displayStrategy: IslandDisplayStrategy {
        didSet { save(displayStrategy.rawValue, for: Keys.displayStrategy) }
    }

    @Published var showWeatherModule: Bool {
        didSet { save(showWeatherModule, for: Keys.showWeatherModule) }
    }

    @Published var showCalendarModule: Bool {
        didSet { save(showCalendarModule, for: Keys.showCalendarModule) }
    }

    @Published var calendarStyle: CalendarStyle {
        didSet { save(calendarStyle.rawValue, for: Keys.calendarStyle) }
    }

    @Published var showTodoModule: Bool {
        didSet { save(showTodoModule, for: Keys.showTodoModule) }
    }

    @Published var showMediaModule: Bool {
        didSet { save(showMediaModule, for: Keys.showMediaModule) }
    }

    @Published var showMusicTrackName: Bool {
        didSet { save(showMusicTrackName, for: Keys.showMusicTrackName) }
    }

    @Published var showMusicLyrics: Bool {
        didSet { save(showMusicLyrics, for: Keys.showMusicLyrics) }
    }

    @Published var allowAppleMusicAccess: Bool {
        didSet { save(allowAppleMusicAccess, for: Keys.allowAppleMusicAccess) }
    }

    @Published var allowSpotifyAccess: Bool {
        didSet { save(allowSpotifyAccess, for: Keys.allowSpotifyAccess) }
    }

    @Published var showDesktopLyrics: Bool {
        didSet { save(showDesktopLyrics, for: Keys.showDesktopLyrics) }
    }

    @Published var desktopLyricsPosition: DesktopLyricsPosition {
        didSet { save(desktopLyricsPosition.rawValue, for: Keys.desktopLyricsPosition) }
    }

    @Published var desktopLyricsInteractionEnabled: Bool {
        didSet { save(desktopLyricsInteractionEnabled, for: Keys.desktopLyricsInteractionEnabled) }
    }

    @Published var desktopLyricsColorMode: DesktopLyricsColorMode {
        didSet { save(desktopLyricsColorMode.rawValue, for: Keys.desktopLyricsColorMode) }
    }

    @Published var showQuickAppsModule: Bool {
        didSet { save(showQuickAppsModule, for: Keys.showQuickAppsModule) }
    }

    @Published var showShortcutsModule: Bool {
        didSet { save(showShortcutsModule, for: Keys.showShortcutsModule) }
    }

    @Published var showImageCardModule: Bool {
        didSet { save(showImageCardModule, for: Keys.showImageCardModule) }
    }

    @Published var showDeviceInfoModule: Bool {
        didSet { save(showDeviceInfoModule, for: Keys.showDeviceInfoModule) }
    }

    @Published var imageCardPath: String {
        didSet { save(imageCardPath, for: Keys.imageCardPath) }
    }

    @Published var quickAppsSettingsTrigger: Bool = false
    @Published var shortcutsSettingsTrigger: Bool = false

    @Published var openSpeed: Double {
        didSet { save(openSpeed, for: Keys.openSpeed) }
    }

    @Published var closeSpeed: Double {
        didSet { save(closeSpeed, for: Keys.closeSpeed) }
    }

    @Published var closeDelay: Double {
        didSet { save(closeDelay, for: Keys.closeDelay) }
    }

    @Published private(set) var islandWidth: Double
    @Published private(set) var islandHeight: Double

    @Published var moduleOrder: [String] {
        didSet { save(moduleOrder, for: Keys.moduleOrder) }
    }

    @Published var compactLeftSideIcon: SettingsHomeSideIcon {
        didSet { save(compactLeftSideIcon.rawValue, for: Keys.compactLeftSideIcon) }
    }

    @Published var compactRightSideIcon: SettingsHomeSideIcon {
        didSet { save(compactRightSideIcon.rawValue, for: Keys.compactRightSideIcon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        fontPreference = AppFontPreference(
            rawValue: defaults.string(forKey: Keys.fontPreference) ?? ""
        ) ?? .system
        isIslandEnabled = defaults.object(forKey: Keys.isIslandEnabled) as? Bool ?? true
        showCustomCompactIcons = defaults.object(forKey: Keys.showCustomCompactIcons) as? Bool ?? true
        let savedLanguage = defaults.string(forKey: Keys.language)
        language = IslandLanguage(rawValue: savedLanguage ?? "") ?? .chinese
        let systemLaunchAtLoginEnabled = Self.isLaunchAtLoginEnabled
        launchAtLogin = systemLaunchAtLoginEnabled
        launchAtLoginError = nil
        defaults.set(systemLaunchAtLoginEnabled, forKey: Keys.launchAtLogin)
        hideMenuBar = defaults.object(forKey: Keys.hideMenuBar) as? Bool ?? false
        showPinButton = defaults.object(forKey: Keys.showPinButton) as? Bool ?? true
        hideInFullscreen = defaults.object(forKey: Keys.hideInFullscreen) as? Bool ?? true
        bounceLevel = IslandBounceLevel(
            rawValue: defaults.string(forKey: Keys.bounceLevel) ?? ""
        ) ?? .standard
        expansionMode = IslandExpansionMode(
            rawValue: defaults.string(forKey: Keys.expansionMode) ?? ""
        ) ?? .hover
        hoverExpansionDelay = defaults.object(forKey: Keys.hoverExpansionDelay) as? Double ?? 0.42
        tutorialHintPolicy = TutorialHintPolicy(
            rawValue: defaults.string(forKey: Keys.tutorialHintPolicy) ?? ""
        ) ?? .once
        hasShownTutorialHint = defaults.object(forKey: Keys.hasShownTutorialHint) as? Bool ?? false
        foregroundAppLinkEnabled = defaults.object(forKey: Keys.foregroundAppLinkEnabled) as? Bool ?? false
        foregroundAppPromptDisplayMode = ForegroundAppPromptDisplayMode(
            rawValue: defaults.string(forKey: Keys.foregroundAppPromptDisplayMode) ?? ""
        ) ?? .applicationName
        foregroundHoldDuration = defaults.object(forKey: Keys.foregroundHoldDuration) as? Double ?? 1.0
        trackpadFeedbackMode = TrackpadFeedbackMode(
            rawValue: defaults.string(forKey: Keys.trackpadFeedbackMode) ?? ""
        ) ?? .single
        islandBackgroundStyle = IslandBackgroundStyle(
            rawValue: defaults.string(forKey: Keys.islandBackgroundStyle) ?? ""
        ) ?? .solid
        displayStrategy = IslandDisplayStrategy(
            rawValue: defaults.string(forKey: Keys.displayStrategy) ?? ""
        ) ?? .main
        showWeatherModule = defaults.object(forKey: Keys.showWeatherModule) as? Bool ?? true
        showCalendarModule = defaults.object(forKey: Keys.showCalendarModule) as? Bool ?? true
        calendarStyle = CalendarStyle(
            rawValue: defaults.string(forKey: Keys.calendarStyle) ?? ""
        ) ?? .weeklySchedule
        showTodoModule = defaults.object(forKey: Keys.showTodoModule) as? Bool ?? true
        showMediaModule = defaults.object(forKey: Keys.showMediaModule) as? Bool ?? true
        showMusicTrackName = defaults.object(forKey: Keys.showMusicTrackName) as? Bool ?? true
        showMusicLyrics = defaults.object(forKey: Keys.showMusicLyrics) as? Bool ?? true
        allowAppleMusicAccess = defaults.object(forKey: Keys.allowAppleMusicAccess) as? Bool ?? true
        allowSpotifyAccess = defaults.object(forKey: Keys.allowSpotifyAccess) as? Bool ?? false
        showDesktopLyrics = defaults.object(forKey: Keys.showDesktopLyrics) as? Bool ?? true
        desktopLyricsPosition = DesktopLyricsPosition(
            rawValue: defaults.string(forKey: Keys.desktopLyricsPosition) ?? ""
        ) ?? .bottomLeft
        desktopLyricsInteractionEnabled = defaults.object(forKey: Keys.desktopLyricsInteractionEnabled) as? Bool ?? false
        desktopLyricsColorMode = DesktopLyricsColorMode(
            rawValue: defaults.string(forKey: Keys.desktopLyricsColorMode) ?? ""
        ) ?? .automatic
        showQuickAppsModule = defaults.object(forKey: Keys.showQuickAppsModule) as? Bool ?? true
        showShortcutsModule = defaults.object(forKey: Keys.showShortcutsModule) as? Bool ?? true
        showImageCardModule = defaults.object(forKey: Keys.showImageCardModule) as? Bool ?? true
        showDeviceInfoModule = defaults.object(forKey: Keys.showDeviceInfoModule) as? Bool ?? true
        imageCardPath = defaults.string(forKey: Keys.imageCardPath) ?? ""
        openSpeed = defaults.object(forKey: Keys.openSpeed) as? Double ?? 0.50
        closeSpeed = defaults.object(forKey: Keys.closeSpeed) as? Double ?? 0.50
        closeDelay = defaults.object(forKey: Keys.closeDelay) as? Double ?? 0
        islandWidth = Double(IslandDesignTokens.defaultExpandedSize.width)
        islandHeight = Double(IslandDesignTokens.defaultExpandedSize.height)
        moduleOrder = defaults.stringArray(forKey: Keys.moduleOrder) ?? []
        let savedLeftSideIcon = SettingsHomeSideIcon(
            rawValue: defaults.string(forKey: Keys.compactLeftSideIcon) ?? ""
        ) ?? .weather
        let savedRightSideIcon = SettingsHomeSideIcon(
            rawValue: defaults.string(forKey: Keys.compactRightSideIcon) ?? ""
        ) ?? .battery
        compactLeftSideIcon = Self.supportedSideIcon(savedLeftSideIcon, fallback: .weather)
        compactRightSideIcon = Self.supportedSideIcon(savedRightSideIcon, fallback: .battery)

        defaults.removeObject(forKey: Keys.islandWidth)
        defaults.removeObject(forKey: Keys.islandHeight)
        defaults.removeObject(forKey: "settings.hideDock")

        applyPresentationOptions()
    }

    private static func supportedSideIcon(
        _ icon: SettingsHomeSideIcon,
        fallback: SettingsHomeSideIcon
    ) -> SettingsHomeSideIcon {
        SettingsHomeSideIcon.sideOptions.contains(icon) ? icon : fallback
    }

    var islandSize: CGSize {
        CGSize(width: islandWidth, height: islandHeight)
    }


    var windowSize: CGSize {
        CGSize(width: islandWidth + 40, height: islandHeight + 40)
    }

    var springAnimation: Animation {
        .spring(response: openSpeed, dampingFraction: bounceLevel.dampingFraction, blendDuration: 0.06)
    }

    var closeSpringAnimation: Animation {
        .spring(response: closeSpeed, dampingFraction: bounceLevel.dampingFraction, blendDuration: 0.06)
    }

    func resetGeneralSettings() {
        fontPreference = .system
        language = .chinese
        hideMenuBar = false
        setLaunchAtLogin(false)
        isIslandEnabled = true
        showCustomCompactIcons = true
        islandWidth = Double(IslandDesignTokens.defaultExpandedSize.width)
        islandHeight = Double(IslandDesignTokens.defaultExpandedSize.height)
        openSpeed = 0.50
        closeSpeed = 0.50
        bounceLevel = .standard
        expansionMode = .hover
        hoverExpansionDelay = 0.42
        tutorialHintPolicy = .once
        hasShownTutorialHint = false
        save(hasShownTutorialHint, for: Keys.hasShownTutorialHint)
        showPinButton = true
        foregroundAppLinkEnabled = false
        foregroundAppPromptDisplayMode = .applicationName
        foregroundHoldDuration = 1.0
        trackpadFeedbackMode = .single
        islandBackgroundStyle = .solid
        hideInFullscreen = true
        displayStrategy = .main
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let fontPreference = "settings.fontPreference"
        static let isIslandEnabled = "settings.isIslandEnabled"
        static let showCustomCompactIcons = "settings.showCustomCompactIcons"
        static let language = "settings.language"
        static let launchAtLogin = "settings.launchAtLogin"
        static let hideMenuBar = "settings.hideMenuBar"
        static let showPinButton = "settings.showPinButton"
        static let hideInFullscreen = "settings.hideInFullscreen"
        static let bounceLevel = "settings.bounceLevel"
        static let expansionMode = "settings.expansionMode"
        static let hoverExpansionDelay = "settings.hoverExpansionDelay"
        static let tutorialHintPolicy = "settings.tutorialHintPolicy"
        static let hasShownTutorialHint = "settings.hasShownTutorialHint"
        static let foregroundAppLinkEnabled = "settings.foregroundAppLinkEnabled"
        static let foregroundAppPromptDisplayMode = "settings.foregroundAppPromptDisplayMode"
        static let foregroundHoldDuration = "settings.foregroundHoldDuration"
        static let trackpadFeedbackMode = "settings.trackpadFeedbackMode"
        static let islandBackgroundStyle = "settings.islandBackgroundStyle"
        static let displayStrategy = "settings.displayStrategy"
        static let showWeatherModule = "settings.showWeatherModule"
        static let showCalendarModule = "settings.showCalendarModule"
        static let calendarStyle = "settings.calendarStyle"
        static let showTodoModule = "settings.showTodoModule"
        static let showMediaModule = "settings.showMediaModule"
        static let showMusicTrackName = "settings.showMusicTrackName"
        static let showMusicLyrics = "settings.showMusicLyrics"
        static let allowAppleMusicAccess = "settings.allowAppleMusicAccess"
        static let allowSpotifyAccess = "settings.allowSpotifyAccess"
        static let showDesktopLyrics = "settings.showDesktopLyrics"
        static let desktopLyricsPosition = "settings.desktopLyricsPosition"
        static let desktopLyricsInteractionEnabled = "settings.desktopLyricsInteractionEnabled"
        static let desktopLyricsColorMode = "settings.desktopLyricsColorMode"
        static let showQuickAppsModule = "settings.showQuickAppsModule"
        static let showShortcutsModule = "settings.showShortcutsModule"
        static let showImageCardModule = "settings.showImageCardModule"
        static let showDeviceInfoModule = "settings.showDeviceInfoModule"
        static let imageCardPath = "settings.imageCardPath"
        static let openSpeed = "settings.openSpeed"
        static let closeSpeed = "settings.closeSpeed"
        static let closeDelay = "settings.closeDelay"
        static let islandWidth = "settings.islandWidth"
        static let islandHeight = "settings.islandHeight"
        static let moduleOrder = "settings.moduleOrder"
        static let compactLeftSideIcon = "settings.compactLeftSideIcon"
        static let compactRightSideIcon = "settings.compactRightSideIcon"
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }

    func markTutorialHintShown() {
        guard !hasShownTutorialHint else { return }
        hasShownTutorialHint = true
        save(hasShownTutorialHint, for: Keys.hasShownTutorialHint)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            synchronizeLaunchAtLoginStatus()
            if SMAppService.mainApp.status == .requiresApproval {
                launchAtLoginError = "请在系统设置的登录项中允许 NookFlow。"
            }
        } catch {
            synchronizeLaunchAtLoginStatus()
            launchAtLoginError = "无法更新开机启动设置：\(error.localizedDescription)"
            NSLog("IslandSettings: failed to update launch-at-login: \(error)")
        }
    }

    private func synchronizeLaunchAtLoginStatus() {
        launchAtLogin = Self.isLaunchAtLoginEnabled
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
    }

    private static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func applyPresentationOptions() {
        NSApp.presentationOptions = hideMenuBar ? [.autoHideMenuBar] : []
    }
}
