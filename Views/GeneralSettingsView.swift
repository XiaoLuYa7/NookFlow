import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum GeneralAnimationPace: String, CaseIterable, Identifiable {
    case slow
    case balanced
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: "舒缓"
        case .balanced: "适中"
        case .fast: "轻快"
        }
    }

    var response: Double {
        switch self {
        case .slow: 0.68
        case .balanced: 0.59
        case .fast: 0.50
        }
    }
}

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published var showsResetConfirmation = false

    func reset(_ settings: IslandSettings) {
        withAnimation(AppMotion.standard) {
            settings.resetGeneralSettings()
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: IslandSettings
    @State private var availableScreens = NSScreen.screens
    @StateObject private var model = GeneralSettingsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            SettingsPageScaffold(contentMaxWidth: 1120) {
                PageHeaderView(
                    title: "通用",
                    subtitle: "统一管理应用入口、灵动岛开关、外观与交互行为。",
                    icon: "gearshape.fill"
                ) {
                    Button("重置") {
                        model.showsResetConfirmation = true
                    }
                    .buttonStyle(AppButtonStyle(role: .quiet))
                }
            } content: {
                basicSection
                islandFoundationSection
                animationSection
                interactionSection
                realtimeSection
                trackpadSection
                appearanceSection
                displaySection
                GeneralSettingsGroup(icon: "testtube.2", title: "实验性适配", subtitle: "测试参数不代表真实硬件尺寸；系统原生区域尚未验证。") {
                    Button("打开灵动岛模拟窗口") { IslandSimulationWindowController.shared.show() }
                        .buttonStyle(AppButtonStyle())
                        .padding(AppSpacing.lg)
                }
            }

        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            availableScreens = NSScreen.screens
        }
        .alert("恢复通用设置？", isPresented: $model.showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) {
                model.reset(settings)
            }
        } message: {
            Text("通用设置会立即恢复为默认值，灵动岛尺寸、动画和交互方式也会同步更新。")
        }
    }

    private var basicSection: some View {
        GeneralSettingsGroup(
            icon: "slider.horizontal.3",
            title: "基础设置",
            subtitle: "管理应用的文字、语言与系统入口。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "字体选项",
                subtitle: "选择设置窗口使用的字体风格；中文差异较轻，数字和英文会更明显",
                options: AppFontPreference.allCases,
                optionTitle: \AppFontPreference.title,
                showsDivider: false,
                selection: $settings.fontPreference
            )

            FontPreferencePreview(preference: settings.fontPreference)
                .padding(.horizontal, AppSpacing.rowHorizontal)
                .padding(.bottom, AppSpacing.sm)

            Rectangle()
                .fill(AppColor.divider)
                .frame(height: 1)
                .padding(.leading, AppSpacing.rowHorizontal)

            SettingsSegmentedRow(
                icon: nil,
                title: "选择语言",
                subtitle: "语言设置将在应用重启后生效",
                options: IslandLanguage.allCases,
                optionTitle: { $0 == .chinese ? "简体中文" : $0.title },
                selection: $settings.language
            )

            AppSettingsToggleRow(
                icon: nil,
                title: "隐藏菜单栏图标",
                subtitle: "减少菜单栏占用，再次打开应用时直接进入设置窗口",
                isOn: $settings.hideMenuBar
            )

            AppSettingsToggleRow(
                icon: nil,
                title: "开机启动",
                subtitle: "登录 macOS 后自动启动应用",
                showsDivider: false,
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: settings.setLaunchAtLogin
                )
            )

            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(AppTypography.supporting)
                    .foregroundStyle(Color.red.opacity(0.82))
                    .padding(.horizontal, AppSpacing.md)
            }
        }
    }

    private var islandFoundationSection: some View {
        GeneralSettingsGroup(
            icon: "capsule",
            title: "灵动岛基础",
            subtitle: "控制主要入口及紧凑状态内容。"
        ) {
            AppSettingsToggleRow(
                icon: nil,
                title: "开启灵动岛",
                subtitle: "控制灵动岛窗口是否显示，并参与后续交互与通知展示",
                isOn: $settings.isIslandEnabled
            )

            AppSettingsToggleRow(
                icon: nil,
                title: "自选图标显示",
                subtitle: "在紧凑状态显示你挑选的左右图标",
                showsDivider: false,
                isOn: $settings.showCustomCompactIcons
            )
        }
    }

    private var animationSection: some View {
        GeneralSettingsGroup(
            icon: "waveform.path",
            title: "动画设置",
            subtitle: "统一控制展开、收起与落位时的节奏。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "展开 / 收缩速度",
                subtitle: "调整整体节奏，快慢都会保留自然的缓入和落位",
                options: GeneralAnimationPace.allCases,
                optionTitle: \GeneralAnimationPace.title,
                selection: animationPaceBinding
            )

            SettingsSegmentedRow(
                icon: nil,
                title: "弹动幅度",
                subtitle: "控制动画结束时的微回弹，保持形体稳定和克制",
                options: IslandBounceLevel.allCases,
                optionTitle: \IslandBounceLevel.title,
                showsDivider: false,
                selection: $settings.bounceLevel
            )
        }
    }

    private var interactionSection: some View {
        GeneralSettingsGroup(
            icon: "cursorarrow.motionlines",
            title: "交互行为",
            subtitle: "决定灵动岛如何响应指针与操作提示。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "灵动岛展开模式",
                subtitle: "选择通过点击或鼠标悬浮展开灵动岛",
                options: IslandExpansionMode.allCases,
                optionTitle: \IslandExpansionMode.title,
                selection: $settings.expansionMode
            )

            SettingsSliderRow(
                icon: nil,
                title: "悬停触发延迟",
                subtitle: "设置鼠标停留多久后自动展开",
                value: $settings.hoverExpansionDelay,
                in: 0.15...1.2,
                step: 0.05,
                isEnabled: settings.expansionMode == .hover,
                valueText: { String(format: "%.2f s", $0) }
            )

            AppSettingsToggleRow(
                icon: nil,
                title: "显示固定展开按钮",
                subtitle: "控制右下角锁定与解锁按钮是否显示",
                showsDivider: false,
                isOn: $settings.showPinButton
            )
        }
    }

    private var realtimeSection: some View {
        GeneralSettingsGroup(
            icon: "bolt.horizontal.circle",
            title: "前台应用提示",
            subtitle: "点击窗口、Dock 或 Cmd+Tab 切换前台应用时，临时显示应用状态。"
        ) {
            AppSettingsToggleRow(
                icon: nil,
                title: "切换应用时提示",
                subtitle: "前台应用变化时，临时显示你选择的应用状态",
                isOn: $settings.foregroundAppLinkEnabled
            )

            SettingsSegmentedRow(
                icon: nil,
                title: "提示内容",
                subtitle: "应用名称显示为左侧图标、右侧名称；内存占用显示为左侧内存、右侧大小",
                options: ForegroundAppPromptDisplayMode.allCases,
                optionTitle: \ForegroundAppPromptDisplayMode.title,
                isEnabled: settings.foregroundAppLinkEnabled,
                selection: $settings.foregroundAppPromptDisplayMode
            )

            SettingsSliderRow(
                icon: nil,
                title: "提示时长",
                subtitle: "临时提示停留多久后恢复你自定义的左右状态",
                value: $settings.foregroundHoldDuration,
                in: 0.5...2.0,
                step: 0.25,
                isEnabled: settings.foregroundAppLinkEnabled,
                showsDivider: false,
                valueText: { String(format: "%.2g s", $0) }
            )
        }
    }

    private var trackpadSection: some View {
        GeneralSettingsGroup(
            icon: "hand.tap",
            title: "触控板反馈",
            subtitle: "为关键操作提供克制的触觉确认。",
            footer: "仅限配备触控板的设备，无触控板设备不会产生反馈。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "震动反馈",
                subtitle: "在交互时通过触控板提供轻量操作反馈",
                options: TrackpadFeedbackMode.allCases,
                optionTitle: \TrackpadFeedbackMode.title,
                showsDivider: false,
                selection: $settings.trackpadFeedbackMode
            )
            .onChange(of: settings.trackpadFeedbackMode) { _, mode in
                TrackpadHapticFeedback.perform(mode)
            }
        }
    }

    private var appearanceSection: some View {
        GeneralSettingsGroup(
            icon: "circle.lefthalf.filled",
            title: "灵动岛外观",
            subtitle: "保持深色主体，同时调整表面质感和全屏行为。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "背景样式",
                subtitle: "切换纯净深色或更轻的半透明外观",
                options: IslandBackgroundStyle.allCases,
                optionTitle: \IslandBackgroundStyle.title,
                selection: $settings.islandBackgroundStyle
            )

            AppSettingsToggleRow(
                icon: nil,
                title: "全屏时隐藏",
                subtitle: "进入全屏模式后自动隐藏，减少画面遮挡",
                showsDivider: false,
                isOn: $settings.hideInFullscreen
            )
        }
    }

    private var displaySection: some View {
        GeneralSettingsGroup(icon: "display.2", title: "显示器与位置",
                             subtitle: "宽刘海保留现有布局；无刘海屏幕使用顶部悬浮胶囊。",
                             footer: "所选显示器断开时回退主屏。位置参数仅作用于无刘海屏幕；距离从可用区域顶部计算。") {
            SettingsRow(title: "显示器", subtitle: "保持一个工作台窗口，不在系统原生区域覆盖透明窗口") {
                Picker("显示器", selection: $settings.preferredDisplayID) {
                    Text("自动（主屏）").tag("")
                    ForEach(availableScreens, id: \.nookFlowDisplayID) { screen in
                        Text(screen.localizedName).tag(screen.nookFlowDisplayID)
                    }
                    if !settings.preferredDisplayID.isEmpty && !availableScreens.contains(where: { $0.nookFlowDisplayID == settings.preferredDisplayID }) {
                        Text("显示器已断开（使用主屏）").tag(settings.preferredDisplayID)
                    }
                }.labelsHidden().frame(width: 230)
            }
            SettingsSliderRow(icon: nil, title: "水平位置", subtitle: "展开内容始终围绕胶囊中心，靠近屏幕边缘时自动留出空间",
                value: $settings.floatingHorizontalPosition, in: 0...1, step: 0.01,
                valueText: { "\(Int($0 * 100))%" })
            SettingsSliderRow(icon: nil, title: "顶部距离", subtitle: "向下展开，保留菜单栏空间",
                value: $settings.floatingTopInset, in: 0...200, step: 1,
                valueText: { "\(Int($0)) pt" })
        }
    }

    private var animationPaceBinding: Binding<GeneralAnimationPace> {
        Binding(
            get: {
                if settings.openSpeed >= 0.635 { return .slow }
                if settings.openSpeed <= 0.545 { return .fast }
                return .balanced
            },
            set: { pace in
                settings.openSpeed = pace.response
                settings.closeSpeed = pace.response
            }
        )
    }

}

private struct FontPreferencePreview: View {
    let preference: AppFontPreference

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(AppFontPreference.allCases) { item in
                previewCard(for: item, isSelected: item == preference)
            }
        }
        .animation(AppMotion.standard, value: preference)
    }

    private func previewCard(for item: AppFontPreference, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(item.sampleText)
                .font(item.font(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? AppColor.textPrimary : AppColor.textSecondary)

            Text(item.note)
                .font(item.font(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(isSelected ? AppColor.accentSoft.opacity(0.78) : AppColor.controlFill.opacity(0.62))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                        .stroke(isSelected ? AppColor.accentBorder : Color.clear, lineWidth: 1)
                }
        }
    }
}

private struct GeneralSettingsGroup<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let footer: String?
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        SettingsSectionCard(
            title: title,
            subtitle: subtitle,
            footer: footer
        ) {
            content
        }
    }
}


@MainActor
private final class IslandSimulationWindowController: NSObject, NSWindowDelegate {
    static let shared = IslandSimulationWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "NookFlow · 灵动岛模拟（测试参数）"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: IslandSimulationView())
        window.minSize = NSSize(width: 900, height: 680)
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

@MainActor
private final class IslandSimulationSession: ObservableObject {
    let settings: IslandSettings
    let model: IslandViewModel
    private let suiteName = "NookFlow.Simulation.\(UUID().uuidString)"

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("settings.") {
            defaults.set(value, forKey: key)
        }
        settings = IslandSettings(defaults: defaults)
        settings.expansionMode = .hover
        settings.simulationExpandedSize = CGSize(width: 900, height: 320)
        model = IslandViewModel(settings: settings, enablesLiveServices: false)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

private struct IslandSimulationView: View {
    @StateObject private var session = IslandSimulationSession()
    @State private var capsuleWidth = 220.0
    @State private var capsuleHeight = 36.0
    @State private var topInset = 12.0
    @State private var scale = 0.8
    @State private var panelWidth = 900.0
    @State private var panelHeight = 320.0
    @State private var wideNotch = false
    @State private var isDragTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实验性适配 · 共用正式布局与动画，尺寸仅为测试参数")
                .font(.headline)
            Text("本版仅测试 NookFlow 自有窗口。实时采集与播放控制停用；拖入仅预演，文件页只读。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("模拟宽刘海", isOn: $wideNotch)
                Button("展开") { session.model.expand() }
                Button("收起") { session.model.collapse() }
                Button("首页工作台") { session.model.selectTopTab(.home); session.model.expand() }
                Button("文件工作台") { session.model.selectTopTab(.files); session.model.expand() }
            }
            HStack {
                control("胶囊宽", value: $capsuleWidth, range: 100...500)
                control("胶囊高", value: $capsuleHeight, range: 24...70)
                control("顶部距离", value: $topInset, range: 0...80)
            }
            HStack {
                control("显示缩放", value: $scale, range: 0.5...1.2)
                control("面板宽", value: $panelWidth, range: 600...1200)
                control("面板高", value: $panelHeight, range: 240...480)
            }
            IslandSimulationCanvas(model: session.model, settings: session.settings,
                                   topInset: topInset, scale: scale, isDragTargeted: $isDragTargeted)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .onAppear { updateGeometry() }
        .onChange(of: capsuleWidth) { _, _ in updateGeometry() }
        .onChange(of: capsuleHeight) { _, _ in updateGeometry() }
        .onChange(of: wideNotch) { _, _ in updateGeometry() }
        .onChange(of: panelWidth) { _, _ in updateGeometry() }
        .onChange(of: panelHeight) { _, _ in updateGeometry() }
        .onDisappear { session.model.collapse(); session.model.playbackProvider.stop() }
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text("\(title)：\(value.wrappedValue, specifier: "%.1f")").font(.caption).monospacedDigit()
            Slider(value: value, in: range)
        }
        .frame(maxWidth: .infinity)
    }

    private func updateGeometry() {
        let size = CGSize(width: capsuleWidth, height: capsuleHeight)
        session.settings.simulationExpandedSize = CGSize(width: panelWidth, height: panelHeight)
        session.model.updateCompactCapsuleSizes(camera: size, status: size, lyrics: size)
        session.model.updateNotchGeometry(NotchGeometry(hasNotch: wideNotch,
            cameraZoneWidth: wideNotch ? capsuleWidth * 0.45 : 0,
            sideWidth: wideNotch ? capsuleWidth * 0.275 : capsuleWidth / 2,
            totalWidth: capsuleWidth, height: capsuleHeight))
    }
}

private struct IslandSimulationCanvas: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var settings: IslandSettings
    let topInset: CGFloat
    let scale: CGFloat
    @Binding var isDragTargeted: Bool

    var body: some View {
        GeometryReader { proxy in
            let canvasWidth = max(1300, proxy.size.width / scale)
            let canvasHeight = max(600, proxy.size.height / scale)
            IslandRootView(viewModel: model, settings: settings,
                           onOpenSettings: {}, onOpenTodoSettings: {}, onOpenFeedback: {})
                .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
                .allowsHitTesting(model.selectedTopTab != .files)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let size = model.mode == .compact ? model.compactCapsuleSize
                            : IslandShellLayout.contentSize(settings: settings, selectedTopTab: model.selectedTopTab)
                        let inside = abs(point.x - canvasWidth / 2) <= size.width / 2 + 12
                            && point.y <= size.height + 24
                        if inside {
                            model.cancelCollapse()
                            model.updateCameraHover(true)
                        } else {
                            model.updateCameraHover(false)
                            model.scheduleCollapse()
                        }
                    case .ended:
                        model.updateCameraHover(false)
                        model.scheduleCollapse()
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { _ in
                    model.finishFileDropInteraction()
                    return true
                }
                .onChange(of: isDragTargeted) { _, targeted in
                    if targeted { model.beginFileDrop(previewName: "测试拖入（不导入）") }
                    else { model.finishFileDropInteraction() }
                }
                .scaleEffect(scale, anchor: .top)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .padding(.top, topInset)
        }
        .clipped()
    }
}
