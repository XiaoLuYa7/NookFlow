import SwiftUI

struct PageHeaderView<Actions: View>: View {
    @Environment(\.appFontPreference) private var fontPreference
    let title: String
    let subtitle: String?
    let icon: String?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.xl) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 34, height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .fill(AppColor.accentSoft)
                        }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.pageTitle(fontPreference))
                        .foregroundStyle(AppColor.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(AppTypography.pageSubtitle(fontPreference))
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: AppSpacing.lg)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PageHeaderView where Actions == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

struct SettingsPageScaffold<Header: View, Content: View, Footer: View>: View {
    private let horizontalPadding: CGFloat = 22
    private let verticalPadding: CGFloat = 20
    private let sectionSpacing: CGFloat = 16
    let contentMaxWidth: CGFloat
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        contentMaxWidth: CGFloat = 1040,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.contentMaxWidth = contentMaxWidth
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, horizontalPadding)
                .padding(.top, verticalPadding)
                .padding(.bottom, AppSpacing.lg)
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                    content
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, AppSpacing.xxl)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColor.pageBackground)
    }
}

extension SettingsPageScaffold where Footer == EmptyView {
    init(
        contentMaxWidth: CGFloat = 1040,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            contentMaxWidth: contentMaxWidth,
            header: header,
            content: content,
            footer: { EmptyView() }
        )
    }
}

struct SettingsSectionCard<Content: View>: View {
    @Environment(\.appFontPreference) private var fontPreference
    let title: String?
    let subtitle: String?
    let footer: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    if let title {
                        Text(title)
                            .font(AppTypography.sectionTitle(fontPreference))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.supporting(fontPreference))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            content

            if let footer {
                Text(footer)
                    .font(AppTypography.supporting(fontPreference))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.elevated, radius: AppRadius.largeCard)
    }
}

struct SettingsRow<Accessory: View>: View {
    @Environment(\.appFontPreference) private var fontPreference
    @State private var isHovering = false
    let icon: String?
    let title: String
    let subtitle: String?
    let isEnabled: Bool
    let showsDivider: Bool
    @ViewBuilder let accessory: Accessory

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        isEnabled: Bool = true,
        showsDivider: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
        self.showsDivider = showsDivider
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                horizontalLayout
                verticalLayout
            }
            .padding(.horizontal, AppSpacing.rowHorizontal)
            .padding(.vertical, AppSpacing.rowVertical)
            .frame(minHeight: 58)

            if showsDivider {
                Rectangle()
                    .fill(AppColor.divider)
                    .frame(height: 1)
                    .padding(.leading, icon == nil ? AppSpacing.rowHorizontal : 58)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(isHovering && isEnabled ? AppColor.controlFill.opacity(0.65) : .clear)
        }
        .opacity(isEnabled ? 1 : AppControlStyle.disabledOpacity)
        .allowsHitTesting(isEnabled)
        .onHover { isHovering = $0 }
        .animation(AppMotion.quick, value: isHovering)
    }

    private var horizontalLayout: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            label
            Spacer(minLength: AppSpacing.xl)
            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            label
            accessory
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var label: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: AppIconStyle.rowFrame, height: AppIconStyle.rowFrame)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.controlFill)
                    }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.rowTitle(fontPreference))
                    .foregroundStyle(AppColor.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTypography.supporting(fontPreference))
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct AppSettingsToggleRow: View {
    let icon: String?
    let title: String
    let subtitle: String?
    var isEnabled = true
    var showsDivider = true
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsDivider: showsDivider
        ) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(AppSwitchToggleStyle())
        }
    }
}

struct SettingsActionRow: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let actionTitle: String
    var isEnabled = true
    var showsDivider = true
    var role: AppButtonRole = .secondary
    let action: () -> Void

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsDivider: showsDivider
        ) {
            Button(actionTitle, action: action)
                .buttonStyle(AppButtonStyle(role: role))
        }
    }
}

struct SettingsSegmentedRow<Option: Hashable>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let options: [Option]
    let optionTitle: (Option) -> String
    var isEnabled = true
    var showsDivider = true
    @Binding var selection: Option

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsDivider: showsDivider
        ) {
            PillSegmentedControl(
                options: options,
                selection: $selection,
                title: optionTitle
            )
        }
    }
}

struct SettingsSliderRow: View {
    @Environment(\.appFontPreference) private var fontPreference
    let icon: String?
    let title: String
    let subtitle: String?
    let range: ClosedRange<Double>
    let step: Double
    let valueText: (Double) -> String
    var isEnabled = true
    var showsDivider = true
    @Binding var value: Double

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        isEnabled: Bool = true,
        showsDivider: Bool = true,
        valueText: @escaping (Double) -> String
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.isEnabled = isEnabled
        self.showsDivider = showsDivider
        self.valueText = valueText
    }

    var body: some View {
        SettingsRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            isEnabled: isEnabled,
            showsDivider: showsDivider
        ) {
            HStack(spacing: AppSpacing.md) {
                Slider(value: $value, in: range, step: step)
                    .tint(AppColor.accent)
                    .frame(width: 210)

                Text(valueText(value))
                    .font(AppTypography.control(fontPreference).monospacedDigit())
                    .foregroundStyle(AppColor.textBody)
                    .frame(minWidth: 54, alignment: .trailing)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(height: AppControlStyle.compactHeight)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.controlFill)
                    }
            }
        }
    }
}

struct SectionFooterHint: View {
    @Environment(\.appFontPreference) private var fontPreference
    let text: String
    var icon = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
            Text(text)
                .font(AppTypography.supporting(fontPreference))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, AppSpacing.xs)
    }
}

struct PillSegmentedControl<Option: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .lineLimit(1)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(height: AppControlStyle.compactHeight)
                }
                .buttonStyle(AppButtonStyle(role: .quiet, isSelected: selection == option))
            }
        }
        .padding(AppSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(AppColor.controlFill)
        }
    }
}

struct SettingsMultiSelectGrid<Option: Identifiable & Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let icon: ((Option) -> String?)?
    @Binding var selection: Set<Option>

    init(
        options: [Option],
        selection: Binding<Set<Option>>,
        title: @escaping (Option) -> String,
        icon: ((Option) -> String?)? = nil
    ) {
        self.options = options
        self._selection = selection
        self.title = title
        self.icon = icon
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: AppSpacing.sm)],
            spacing: AppSpacing.sm
        ) {
            ForEach(options) { option in
                let isSelected = selection.contains(option)
                Button {
                    if isSelected {
                        selection.remove(option)
                    } else {
                        selection.insert(option)
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if let iconName = icon?(option) {
                            Image(systemName: iconName)
                        }
                        Text(title(option))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(AppButtonStyle(role: .secondary, isSelected: isSelected))
            }
        }
    }
}

struct ProBadge: View {
    @Environment(\.appFontPreference) private var fontPreference
    var title = "PRO"

    var body: some View {
        Text(title)
            .font(AppTypography.badge(fontPreference))
            .foregroundStyle(AppColor.accent)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 20)
            .background {
                Capsule(style: .continuous)
                    .fill(AppColor.accentSoft)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(AppColor.accentBorder, lineWidth: 1)
                    }
            }
    }
}

struct EmptyStateView<Actions: View>: View {
    @Environment(\.appFontPreference) private var fontPreference
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    init(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: AppIconStyle.emptyStateSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 52, height: 52)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(AppColor.controlFill)
                }

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.sectionTitle(fontPreference))
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppTypography.supporting(fontPreference))
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            actions
        }
        .padding(AppSpacing.xxxl)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}
