import AppKit
import SwiftUI

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
        case .balanced: 0.50
        case .fast: 0.36
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
    @StateObject private var model = GeneralSettingsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            SettingsPageScaffold(contentMaxWidth: 980) {
                PageHeaderView(
                    title: "通用设置",
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
            }

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

            SettingsSegmentedRow(
                icon: nil,
                title: "教学引导提示",
                subtitle: "控制灵动岛下方功能提示的显示策略",
                options: TutorialHintPolicy.allCases,
                optionTitle: \TutorialHintPolicy.title,
                selection: $settings.tutorialHintPolicy
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
                in: 0.5...5.0,
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
        GeneralSettingsGroup(
            icon: "display.2",
            title: "多屏显示",
            subtitle: "选择最适合当前桌面布局的显示位置。",
            footer: "屏幕布局变化后会在下一次窗口定位时应用所选策略。"
        ) {
            SettingsSegmentedRow(
                icon: nil,
                title: "灵动岛显示策略",
                subtitle: "选择灵动岛在哪些屏幕上显示",
                options: IslandDisplayStrategy.allCases,
                optionTitle: \IslandDisplayStrategy.title,
                showsDivider: false,
                selection: $settings.displayStrategy
            )
        }
    }

    private var animationPaceBinding: Binding<GeneralAnimationPace> {
        Binding(
            get: {
                if settings.openSpeed >= 0.59 { return .slow }
                if settings.openSpeed <= 0.42 { return .fast }
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
