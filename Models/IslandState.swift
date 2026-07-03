import Combine
import CoreAudio
import AppKit
import Darwin
import Foundation
import IOKit.ps
import SwiftUI

struct BatterySnapshot {
    var percent: Int?
    var isCharging: Bool

    static let unknown = BatterySnapshot(percent: nil, isCharging: false)
}

@MainActor
final class BatteryProvider: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot = .unknown

    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        snapshot = Self.readSnapshot()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static func readSnapshot() -> BatterySnapshot {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return .unknown
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }

            guard
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int,
                max > 0
            else {
                continue
            }

            let state = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = state == kIOPSACPowerValue
            let percent = Int((Double(current) / Double(max) * 100).rounded()).clamped(to: 0...100)
            return BatterySnapshot(percent: percent, isCharging: isCharging)
        }

        return .unknown
    }
}

struct SideStatusContext {
    var playback: PlaybackSnapshot = .idle
    var weather: WeatherSnapshot = .placeholder
    var deviceInfo: DeviceInfoSnapshot = .placeholder
    var battery: BatterySnapshot = .unknown
    var isMuted = false

    static let preview = SideStatusContext()
}

struct ForegroundAppPrompt: Equatable {
    var appName: String
    var memoryText: String
    var icon: NSImage?

    static func == (lhs: ForegroundAppPrompt, rhs: ForegroundAppPrompt) -> Bool {
        lhs.appName == rhs.appName && lhs.memoryText == rhs.memoryText
    }
}

@MainActor
final class ForegroundAppProvider: ObservableObject {
    @Published private(set) var prompt: ForegroundAppPrompt?

    private var observer: NSObjectProtocol?

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }

            Task { @MainActor in
                self?.updatePrompt(for: app)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        prompt = nil
    }

    private func updatePrompt(for app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        prompt = ForegroundAppPrompt(
            appName: app.localizedName ?? app.bundleIdentifier ?? "应用",
            memoryText: Self.memoryText(for: app.processIdentifier),
            icon: app.icon
        )
    }

    private static func memoryText(for pid: pid_t) -> String {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) { rebound in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, rebound, Int32(size))
            }
        }

        guard result == Int32(size), info.pti_resident_size > 0 else {
            return "--"
        }

        let bytes = Double(info.pti_resident_size)
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", bytes / 1_073_741_824)
        }
        return String(format: "%.0f MB", bytes / 1_048_576)
    }
}

/// Two visual modes for the island: pill (compact) or card (expanded).
enum IslandMode: Equatable {
    case compact
    case expanded
}

enum CompactCapsuleContentMode: Equatable {
    /// Only covers the physical camera/notch area.
    case camera
    /// Adds the current compact side extensions for lightweight status text.
    case status
    /// Uses a wider compact shell for song information and live lyrics.
    case lyrics
}

enum SettingsHomeSideIcon: String, CaseIterable, Identifiable {
    case weather
    case battery
    case wind
    case windDirection
    case sunrise
    case sunset
    case date
    case lunar
    case calendar
    case clock
    case weekday
    case temperatureRange
    case humidity
    case music
    case network
    case dayProgress
    case weekProgress
    case monthProgress
    case quarterProgress
    case yearProgress
    case cpu
    case memory
    case disk
    case mute
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: "天气"
        case .battery: "电池"
        case .wind: "风速"
        case .windDirection: "风向"
        case .sunrise: "日出"
        case .sunset: "日落"
        case .date: "日期"
        case .lunar: "农历"
        case .calendar: "明日"
        case .clock: "时钟"
        case .weekday: "星期"
        case .temperatureRange: "温度范围"
        case .humidity: "湿度"
        case .music: "音乐"
        case .network: "网速"
        case .dayProgress: "日进度"
        case .weekProgress: "周进度"
        case .monthProgress: "月进度"
        case .quarterProgress: "季进度"
        case .yearProgress: "年进度"
        case .cpu: "处理器"
        case .memory: "内存"
        case .disk: "磁盘"
        case .mute: "静音"
        case .none: "无"
        }
    }

    var icon: String {
        switch self {
        case .weather: "cloud.fill"
        case .battery: "battery.75percent"
        case .wind: "wind"
        case .windDirection: "location.north.fill"
        case .sunrise: "sunrise.fill"
        case .sunset: "sunset.fill"
        case .date: "calendar"
        case .lunar: "moon.stars.fill"
        case .calendar: "calendar"
        case .clock: "clock.fill"
        case .weekday: "textformat"
        case .temperatureRange: "thermometer.medium"
        case .humidity: "drop.fill"
        case .music: "music.note"
        case .network: "arrow.up.arrow.down"
        case .dayProgress: "sun.max.fill"
        case .weekProgress: "calendar.day.timeline.left"
        case .monthProgress: "calendar.badge.clock"
        case .quarterProgress: "chart.pie.fill"
        case .yearProgress: "circle.dashed"
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .disk: "internaldrive.fill"
        case .mute: "speaker.slash.fill"
        case .none: "nosign"
        }
    }

    func icon(context: SideStatusContext) -> String {
        guard self == .weather else { return icon }
        let symbolName = context.weather.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return symbolName.isEmpty ? icon : symbolName
    }

    func isVisible(context: SideStatusContext) -> Bool {
        switch self {
        case .mute:
            context.isMuted
        default:
            true
        }
    }

    var accentColor: Color {
        switch self {
        case .weather, .sunrise, .sunset:
            Color(red: 1.00, green: 0.78, blue: 0.12)
        case .temperatureRange:
            Color(red: 1.00, green: 0.34, blue: 0.26)
        case .humidity:
            Color(red: 0.56, green: 0.66, blue: 1.00)
        case .wind, .windDirection:
            Color(red: 0.12, green: 0.86, blue: 0.96)
        case .battery:
            Color(red: 0.30, green: 0.93, blue: 0.42)
        case .network:
            Color(red: 0.18, green: 0.58, blue: 1.00)
        case .date, .calendar, .weekday:
            Color(red: 1.00, green: 0.28, blue: 0.36)
        case .lunar, .clock:
            Color(red: 0.74, green: 0.54, blue: 1.00)
        case .music:
            Color(red: 1.00, green: 0.30, blue: 0.58)
        case .dayProgress:
            Color(red: 1.00, green: 0.56, blue: 0.14)
        case .weekProgress:
            Color(red: 0.34, green: 0.86, blue: 0.52)
        case .monthProgress:
            Color(red: 0.25, green: 0.62, blue: 1.00)
        case .quarterProgress:
            Color(red: 1.00, green: 0.78, blue: 0.12)
        case .yearProgress:
            Color(red: 0.92, green: 0.38, blue: 1.00)
        case .cpu, .memory, .disk:
            Color(red: 0.36, green: 0.78, blue: 1.00)
        case .mute:
            Color(red: 1.00, green: 0.46, blue: 0.46)
        case .none:
            Color.white.opacity(0.36)
        }
    }

    var previewText: String {
        statusText()
    }

    func statusText(
        referenceDate date: Date = Date(),
        context: SideStatusContext = .preview
    ) -> String {
        switch self {
        case .weather: context.weather.temperatureText
        case .battery: context.battery.percent.map { "\($0)%" } ?? "--%"
        case .wind: context.weather.windSpeed.map { "\(Int($0.rounded()))m/s" } ?? "--m/s"
        case .windDirection: "西北风"
        case .sunrise: "06:12"
        case .sunset: "19:34"
        case .date: Self.monthDayText(for: date)
        case .lunar: Self.lunarDayText(for: date)
        case .calendar: Self.monthDayText(for: Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date)
        case .clock: Self.timeText(for: date)
        case .weekday: Self.weekdayText(for: date)
        case .temperatureRange: context.weather.dailyForecasts.first?.temperatureRangeText.replacingOccurrences(of: "/", with: "-") ?? "--°"
        case .humidity: context.weather.humidity.map { "\($0)%" } ?? "--%"
        case .music: Self.musicText(from: context.playback)
        case .network:
            "↑\(Self.speedText(context.deviceInfo.uploadBytesPerSecond)) ↓\(Self.speedText(context.deviceInfo.downloadBytesPerSecond))"
        case .dayProgress: Self.dayProgressText(for: date)
        case .weekProgress: Self.componentProgressText(for: date, component: .weekOfYear)
        case .monthProgress: Self.componentProgressText(for: date, component: .month)
        case .quarterProgress: Self.quarterProgressText(for: date)
        case .yearProgress: Self.componentProgressText(for: date, component: .year)
        case .cpu: "\(context.deviceInfo.cpuPercent)%"
        case .memory: "\(context.deviceInfo.memoryPercent)%"
        case .disk: "\(context.deviceInfo.diskPercent)%"
        case .mute: "静音"
        case .none: "无"
        }
    }

    private static func musicText(from playback: PlaybackSnapshot?) -> String {
        guard let playback, playback.isLive else { return "暂无播放" }

        let title = playback.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let appName = playback.appName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty, title != PlaybackSnapshot.idle.title {
            return title
        }

        return appName.isEmpty ? "播放中" : appName
    }

    private static func timeText(for date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return timeFormatter.string(from: date)
    }

    private static func speedText(_ bytesPerSecond: UInt64) -> String {
        let value = Double(bytesPerSecond)
        if value >= 1_000_000_000 {
            return String(format: "%.1fG", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: value >= 100_000_000 ? "%.0fM" : "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: value >= 100_000 ? "%.0fK" : "%.1fK", value / 1_000)
        }
        return "0K"
    }

    private static func monthDayText(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)/\(components.day ?? 1)"
    }

    private static func weekdayText(for date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return weekdayFormatter.string(from: date)
    }

    private static let formatterLock = NSLock()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static func lunarDayText(for date: Date) -> String {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return "农历" }

        let monthNames = [
            "正", "二", "三", "四", "五", "六",
            "七", "八", "九", "十", "冬", "腊"
        ]
        let names = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        guard monthNames.indices.contains(month - 1) else { return "农历" }
        guard names.indices.contains(day - 1) else { return "农历" }
        return "\(monthNames[month - 1])/\(names[day - 1])"
    }

    private static func dayProgressText(for date: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return "0%" }
        return progressText(start: start, end: end, date: date)
    }

    private static func componentProgressText(
        for date: Date,
        component: Calendar.Component
    ) -> String {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: component, for: date) else { return "0%" }
        return progressText(start: interval.start, end: interval.end, date: date)
    }

    private static func quarterProgressText(for date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        var components = calendar.dateComponents([.year], from: date)
        components.month = quarterStartMonth
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard
            let start = calendar.date(from: components),
            let end = calendar.date(byAdding: .month, value: 3, to: start)
        else {
            return "0%"
        }

        return progressText(start: start, end: end, date: date)
    }

    private static func progressText(start: Date, end: Date, date: Date) -> String {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return "0%" }
        let elapsed = min(max(date.timeIntervalSince(start), 0), total)
        return "\(Int((elapsed / total * 100).rounded()))%"
    }

    static let sideOptions: [SettingsHomeSideIcon] = [
        .weather, .battery, .wind, .windDirection, .sunrise, .sunset,
        .date, .lunar, .clock, .weekday, .temperatureRange, .humidity,
        .music, .network, .dayProgress, .weekProgress, .monthProgress,
        .quarterProgress, .yearProgress, .cpu, .memory, .disk,
        .none
    ]

    static let leftOptions = sideOptions
    static let rightOptions = sideOptions
}

struct SystemStatusSnapshot {
    var isMuted: Bool

    static let inactive = SystemStatusSnapshot(isMuted: false)
}

@MainActor
final class SystemStatusProvider: ObservableObject {
    @Published private(set) var snapshot = SystemStatusSnapshot.inactive

    private var timer: Timer?

    deinit {
        timer?.invalidate()
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        snapshot = SystemStatusSnapshot(
            isMuted: AudioMuteBridge.isMuted
        )
    }

    func setMuted(_ muted: Bool) {
        AudioMuteBridge.setMuted(muted)
        refresh()
    }

}

private enum AudioMuteBridge {
    static var isMuted: Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice else { return }
        var address = muteAddress
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return
        }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Explicit presentation phases keep shell geometry and content visibility from
/// racing each other during interrupted open/close transitions.
enum IslandPresentationPhase: Equatable {
    case collapsed
    case expandingShell
    case revealingContent
    case expanded
    case hidingContent
    case collapsingShell

    var mode: IslandMode {
        self == .collapsed ? .compact : .expanded
    }

    var isCollapsing: Bool {
        self == .hidingContent || self == .collapsingShell
    }

    var keepsExpandedHost: Bool {
        self != .collapsed
    }
}

/// Camera-hot-zone interaction is independent from the full island presentation.
/// Keeping it explicit prevents mouse-move events from restarting preview timers.
enum IslandHoverPhase: Equatable {
    case idle
    case preview
    case waiting
    case expanded
    case collapsing
}

/// Explicit presentation stages surrounding the compositor-driven shell timeline.
/// The shell itself passes through its overshoot and undershoot in one keyframe run.
enum IslandOpeningMotionPhase: Equatable {
    case collapsed
    case opening
    case primarySettled
    case undershoot
    case expanded
    case closing
}

/// Independent shell channels let the island grow down before it finishes
/// spreading horizontally, while all geometry still belongs to one Shape.
struct IslandShellAnimationState: Equatable {
    var widthProgress: CGFloat
    var heightProgress: CGFloat
    var morphProgress: CGFloat

    static let collapsed = IslandShellAnimationState(
        widthProgress: 0,
        heightProgress: 0,
        morphProgress: 0
    )

    static let expanded = IslandShellAnimationState(
        widthProgress: 1,
        heightProgress: 1,
        morphProgress: 1
    )

    func clamped() -> IslandShellAnimationState {
        IslandShellAnimationState(
            widthProgress: min(
                max(widthProgress, 0),
                IslandDesignTokens.shellOpenPrimaryWidthOvershoot
            ),
            heightProgress: min(
                max(heightProgress, 0),
                IslandDesignTokens.shellOpenPrimaryHeightOvershoot
            ),
            morphProgress: min(max(morphProgress, 0), 1)
        )
    }
}

enum IslandFileDropTarget: Equatable {
    case staging
    case airDrop
}
