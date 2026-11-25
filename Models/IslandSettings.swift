import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum ImageCardSourceAccess {
    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveURL(path: String, bookmarkData: Data) -> URL? {
        if !bookmarkData.isEmpty {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPath.isEmpty ? nil : URL(fileURLWithPath: trimmedPath)
    }

    nonisolated static func imageURLs(in sourceURL: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]
        guard let values = try? sourceURL.resourceValues(forKeys: keys) else { return [] }

        if values.isDirectory == true {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )) ?? []

            return urls
                .filter { url in
                    guard let values = try? url.resourceValues(forKeys: keys),
                          values.isRegularFile == true else { return false }
                    return values.contentType?.conforms(to: .image) == true
                }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
        }

        return values.contentType?.conforms(to: .image) == true ? [sourceURL] : []
    }
}

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

    /// Resource languages used by AppKit and embedded frameworks such as Sparkle.
    var resourceLanguagePreferences: [String] {
        switch self {
        case .chinese: ["zh-Hans"]
        case .english: ["en"]
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

enum QuickAppsColumnCount: Int, CaseIterable, Identifiable {
    case two = 2
    case three = 3

    var id: Int { rawValue }
    var title: String { "\(rawValue) 列" }
    var pageSize: Int { rawValue * 2 }
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
        case .subtle: 1.012
        case .standard: 1.028
        case .lively: 1.047
        }
    }

    var heightOvershoot: CGFloat {
        switch self {
        case .subtle: 1.008
        case .standard: 1.019
        case .lively: 1.034
        }
    }

}

enum IslandExpansionMode: String, CaseIterable, Identifiable {
    case click
    case hover

    var id: String { rawValue }
    var title: String { self == .click ? "点击展开" : "悬浮展开" }
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

enum LyricsPresentationMode: String, CaseIterable, Identifiable {
    case capsule
    case desktop
    case menuBar

    var id: String { rawValue }

    func title(language: IslandLanguage) -> String {
        switch (language, self) {
        case (.chinese, .capsule): "胶囊歌词"
        case (.chinese, .desktop): "桌面展示"
        case (.chinese, .menuBar): "菜单栏展示"
        case (.english, .capsule): "Capsule"
        case (.english, .desktop): "Desktop"
        case (.english, .menuBar): "Menu Bar"
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
        didSet {
            save(language.rawValue, for: Keys.language)
            applyResourceLanguagePreference()
        }
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

    @Published var foregroundAppLinkEnabled: Bool {
        didSet { save(foregroundAppLinkEnabled, for: Keys.foregroundAppLinkEnabled) }
    }

    @Published var foregroundAppPromptDisplayMode: ForegroundAppPromptDisplayMode {
        didSet { save(foregroundAppPromptDisplayMode.rawValue, for: Keys.foregroundAppPromptDisplayMode) }
    }

    @Published var foregroundHoldDuration: Double {
        didSet {
            let clampedValue = min(max(foregroundHoldDuration, 0.5), 2.0)
            if foregroundHoldDuration != clampedValue {
                foregroundHoldDuration = clampedValue
                return
            }
            save(foregroundHoldDuration, for: Keys.foregroundHoldDuration)
        }
    }

    @Published var trackpadFeedbackMode: TrackpadFeedbackMode {
        didSet { save(trackpadFeedbackMode.rawValue, for: Keys.trackpadFeedbackMode) }
    }

    @Published var islandBackgroundStyle: IslandBackgroundStyle {
        didSet { save(islandBackgroundStyle.rawValue, for: Keys.islandBackgroundStyle) }
    }

    @Published var preferredDisplayID: String {
        didSet { save(preferredDisplayID, for: "settings.preferredDisplayID") }
    }
    @Published var floatingHorizontalPosition: Double {
        didSet { save(floatingHorizontalPosition, for: "settings.floatingHorizontalPosition") }
    }
    @Published var floatingTopInset: Double {
        didSet { save(floatingTopInset, for: "settings.floatingTopInset") }
    }

    @Published var displayStrategy: IslandDisplayStrategy {
        didSet { save(displayStrategy.rawValue, for: Keys.displayStrategy) }
    }

    @Published var showWeatherModule: Bool {
        didSet { save(showWeatherModule, for: Keys.showWeatherModule) }
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

    @Published var allowQQMusicAccess: Bool {
        didSet { save(allowQQMusicAccess, for: Keys.allowQQMusicAccess) }
    }

    @Published var allowNetEaseMusicAccess: Bool {
        didSet { save(allowNetEaseMusicAccess, for: Keys.allowNetEaseMusicAccess) }
    }

    @Published var showDesktopLyrics: Bool {
        didSet {
            save(showDesktopLyrics, for: Keys.showDesktopLyrics)
            synchronizeLyricsPresentation()
        }
    }

    @Published var lyricsPresentationMode: LyricsPresentationMode {
        didSet {
            save(lyricsPresentationMode.rawValue, for: Keys.lyricsPresentationMode)
            synchronizeLyricsPresentation()
        }
    }

    @Published var capsuleLyricsWidth: Double {
        didSet {
            let value = CapsuleLyricsLayout.clampedWidth(capsuleLyricsWidth)
            if capsuleLyricsWidth != value { capsuleLyricsWidth = value }
            save(capsuleLyricsWidth, for: Keys.capsuleLyricsWidth)
        }
    }

    @Published var capsuleLyricsFontSize: Double {
        didSet {
            let value = CapsuleLyricsLayout.clampedFontSize(capsuleLyricsFontSize)
            if capsuleLyricsFontSize != value { capsuleLyricsFontSize = value }
            save(capsuleLyricsFontSize, for: Keys.capsuleLyricsFontSize)
        }
    }

    @Published var menuBarLyricsWidth: Double {
        didSet {
            let clampedValue = min(max(menuBarLyricsWidth, 100), 200)
            if menuBarLyricsWidth != clampedValue {
                menuBarLyricsWidth = clampedValue
                return
            }
            save(menuBarLyricsWidth, for: Keys.menuBarLyricsWidth)
        }
    }

    @Published var menuBarLyricsShowsPlaybackControls: Bool {
        didSet {
            save(
                menuBarLyricsShowsPlaybackControls,
                for: Keys.menuBarLyricsShowsPlaybackControls
            )
        }
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

    @Published var quickAppsColumnCount: QuickAppsColumnCount {
        didSet { save(quickAppsColumnCount.rawValue, for: Keys.quickAppsColumnCount) }
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

    @Published var showMirrorModule: Bool {
        didSet { save(showMirrorModule, for: Keys.showMirrorModule) }
    }

    @Published var imageCardPath: String {
        didSet { save(imageCardPath, for: Keys.imageCardPath) }
    }

    @Published var imageCardBookmarkData: Data {
        didSet { save(imageCardBookmarkData, for: Keys.imageCardBookmarkData) }
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
        let resolvedLanguage = IslandLanguage(rawValue: savedLanguage ?? "") ?? .chinese
        language = resolvedLanguage
        Self.applyResourceLanguagePreference(resolvedLanguage, to: defaults)
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
        foregroundAppLinkEnabled = defaults.object(forKey: Keys.foregroundAppLinkEnabled) as? Bool ?? false
        foregroundAppPromptDisplayMode = ForegroundAppPromptDisplayMode(
            rawValue: defaults.string(forKey: Keys.foregroundAppPromptDisplayMode) ?? ""
        ) ?? .applicationName
        let savedForegroundHoldDuration =
            defaults.object(forKey: Keys.foregroundHoldDuration) as? Double ?? 1.0
        foregroundHoldDuration = min(max(savedForegroundHoldDuration, 0.5), 2.0)
        trackpadFeedbackMode = TrackpadFeedbackMode(
            rawValue: defaults.string(forKey: Keys.trackpadFeedbackMode) ?? ""
        ) ?? .single
        islandBackgroundStyle = IslandBackgroundStyle(
            rawValue: defaults.string(forKey: Keys.islandBackgroundStyle) ?? ""
        ) ?? .solid
        preferredDisplayID = defaults.string(forKey: "settings.preferredDisplayID") ?? ""
        floatingHorizontalPosition = min(1, max(0, defaults.object(forKey: "settings.floatingHorizontalPosition") as? Double ?? 0.5))
        floatingTopInset = min(200, max(0, defaults.object(forKey: "settings.floatingTopInset") as? Double ?? 12))
        displayStrategy = IslandDisplayStrategy(
            rawValue: defaults.string(forKey: Keys.displayStrategy) ?? ""
        ) ?? .main
        showWeatherModule = defaults.object(forKey: Keys.showWeatherModule) as? Bool ?? true
        showTodoModule = defaults.object(forKey: Keys.showTodoModule) as? Bool ?? false
        showMediaModule = defaults.object(forKey: Keys.showMediaModule) as? Bool ?? false
        showMusicTrackName = defaults.object(forKey: Keys.showMusicTrackName) as? Bool ?? true
        let legacyCapsuleLyricsEnabled =
            defaults.object(forKey: Keys.showMusicLyrics) as? Bool
        showMusicLyrics = legacyCapsuleLyricsEnabled ?? false
        allowAppleMusicAccess = defaults.object(forKey: Keys.allowAppleMusicAccess) as? Bool ?? true
        allowSpotifyAccess = defaults.object(forKey: Keys.allowSpotifyAccess) as? Bool ?? false
        allowQQMusicAccess = defaults.object(forKey: Keys.allowQQMusicAccess) as? Bool ?? false
        allowNetEaseMusicAccess = defaults.object(forKey: Keys.allowNetEaseMusicAccess) as? Bool ?? false
        let legacyDesktopLyricsEnabled =
            defaults.object(forKey: Keys.showDesktopLyrics) as? Bool
        showDesktopLyrics = legacyDesktopLyricsEnabled == true
            || legacyCapsuleLyricsEnabled == true
        if let storedMode = LyricsPresentationMode(
            rawValue: defaults.string(forKey: Keys.lyricsPresentationMode) ?? ""
        ) {
            lyricsPresentationMode = storedMode
        } else {
            lyricsPresentationMode = legacyDesktopLyricsEnabled == true ? .desktop : .capsule
        }
        capsuleLyricsWidth = CapsuleLyricsLayout.clampedWidth(
            defaults.object(forKey: Keys.capsuleLyricsWidth) as? Double ?? CapsuleLyricsLayout.defaultWidth
        )
        capsuleLyricsFontSize = CapsuleLyricsLayout.clampedFontSize(
            defaults.object(forKey: Keys.capsuleLyricsFontSize) as? Double ?? CapsuleLyricsLayout.defaultFontSize
        )
        menuBarLyricsWidth = min(
            max(defaults.object(forKey: Keys.menuBarLyricsWidth) as? Double ?? 220, 100),
            200
        )
        menuBarLyricsShowsPlaybackControls =
            defaults.object(forKey: Keys.menuBarLyricsShowsPlaybackControls) as? Bool ?? true
        desktopLyricsPosition = DesktopLyricsPosition(
            rawValue: defaults.string(forKey: Keys.desktopLyricsPosition) ?? ""
        ) ?? .bottomLeft
        desktopLyricsInteractionEnabled = defaults.object(forKey: Keys.desktopLyricsInteractionEnabled) as? Bool ?? false
        desktopLyricsColorMode = DesktopLyricsColorMode(
            rawValue: defaults.string(forKey: Keys.desktopLyricsColorMode) ?? ""
        ) ?? .automatic
        showQuickAppsModule = defaults.object(forKey: Keys.showQuickAppsModule) as? Bool ?? false
        quickAppsColumnCount = QuickAppsColumnCount(
            rawValue: defaults.object(forKey: Keys.quickAppsColumnCount) as? Int ?? 2
        ) ?? .two
        showShortcutsModule = defaults.object(forKey: Keys.showShortcutsModule) as? Bool ?? false
        showImageCardModule = defaults.object(forKey: Keys.showImageCardModule) as? Bool ?? true
        showDeviceInfoModule = defaults.object(forKey: Keys.showDeviceInfoModule) as? Bool ?? true
        showMirrorModule = defaults.object(forKey: Keys.showMirrorModule) as? Bool ?? false
        imageCardPath = defaults.string(forKey: Keys.imageCardPath) ?? ""
        imageCardBookmarkData = defaults.data(forKey: Keys.imageCardBookmarkData) ?? Data()
        let storedOpenSpeed = defaults.object(forKey: Keys.openSpeed) as? Double ?? 0.59
        let storedCloseSpeed = defaults.object(forKey: Keys.closeSpeed) as? Double ?? 0.59
        openSpeed = Self.migratedAnimationSpeed(storedOpenSpeed)
        closeSpeed = Self.migratedAnimationSpeed(storedCloseSpeed)
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

        synchronizeLyricsPresentation()
        applyPresentationOptions()
    }

    private func synchronizeLyricsPresentation() {
        let shouldShowCapsuleLyrics =
            showDesktopLyrics && lyricsPresentationMode == .capsule
        if showMusicLyrics != shouldShowCapsuleLyrics {
            showMusicLyrics = shouldShowCapsuleLyrics
        }
    }

    private func applyResourceLanguagePreference() {
        Self.applyResourceLanguagePreference(language, to: defaults)
    }

    private static func applyResourceLanguagePreference(
        _ language: IslandLanguage,
        to defaults: UserDefaults
    ) {
        defaults.set(language.resourceLanguagePreferences, forKey: "AppleLanguages")
    }

    private static func migratedAnimationSpeed(_ value: Double) -> Double {
        abs(value - 0.36) < 0.0001 ? 0.50 : value
    }

    private static func supportedSideIcon(
        _ icon: SettingsHomeSideIcon,
        fallback: SettingsHomeSideIcon
    ) -> SettingsHomeSideIcon {
        SettingsHomeSideIcon.sideOptions.contains(icon) ? icon : fallback
    }

    // Test-window overrides are never persisted to user preferences.
    @Published var simulationExpandedSize: CGSize?

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
        openSpeed = 0.59
        closeSpeed = 0.59
        bounceLevel = .standard
        expansionMode = .hover
        hoverExpansionDelay = 0.42
        showPinButton = true
        foregroundAppLinkEnabled = false
        foregroundAppPromptDisplayMode = .applicationName
        foregroundHoldDuration = 1.0
        trackpadFeedbackMode = .single
        islandBackgroundStyle = .solid
        hideInFullscreen = true
        preferredDisplayID = ""
        floatingHorizontalPosition = 0.5
        floatingTopInset = 12
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
        static let foregroundAppLinkEnabled = "settings.foregroundAppLinkEnabled"
        static let foregroundAppPromptDisplayMode = "settings.foregroundAppPromptDisplayMode"
        static let foregroundHoldDuration = "settings.foregroundHoldDuration"
        static let trackpadFeedbackMode = "settings.trackpadFeedbackMode"
        static let islandBackgroundStyle = "settings.islandBackgroundStyle"
        static let displayStrategy = "settings.displayStrategy"
        static let showWeatherModule = "settings.showWeatherModule"
        static let showTodoModule = "settings.showTodoModule"
        static let showMediaModule = "settings.showMediaModule"
        static let showMusicTrackName = "settings.showMusicTrackName"
        static let showMusicLyrics = "settings.showMusicLyrics"
        static let allowAppleMusicAccess = "settings.allowAppleMusicAccess"
        static let allowSpotifyAccess = "settings.allowSpotifyAccess"
        static let allowQQMusicAccess = "settings.allowQQMusicAccess"
        static let allowNetEaseMusicAccess = "settings.allowNetEaseMusicAccess"
        static let showDesktopLyrics = "settings.showDesktopLyrics"
        static let lyricsPresentationMode = "settings.lyricsPresentationMode"
        static let capsuleLyricsWidth = "settings.capsuleLyricsWidth"
        static let capsuleLyricsFontSize = "settings.capsuleLyricsFontSize"
        static let menuBarLyricsWidth = "settings.menuBarLyricsWidth"
        static let menuBarLyricsShowsPlaybackControls =
            "settings.menuBarLyricsShowsPlaybackControls"
        static let desktopLyricsPosition = "settings.desktopLyricsPosition"
        static let desktopLyricsInteractionEnabled = "settings.desktopLyricsInteractionEnabled"
        static let desktopLyricsColorMode = "settings.desktopLyricsColorMode"
        static let showQuickAppsModule = "settings.showQuickAppsModule"
        static let quickAppsColumnCount = "settings.quickAppsColumnCount"
        static let showShortcutsModule = "settings.showShortcutsModule"
        static let showImageCardModule = "settings.showImageCardModule"
        static let showDeviceInfoModule = "settings.showDeviceInfoModule"
        static let showMirrorModule = "settings.showMirrorModule"
        static let imageCardPath = "settings.imageCardPath"
        static let imageCardBookmarkData = "settings.imageCardBookmarkData"
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
