import AppKit
import SwiftUI

enum AppBrandAsset {
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        return NSApplication.shared.applicationIconImage
    }()
}

enum AppColor {
    static let pageBackground = Color(red: 0.965, green: 0.972, blue: 0.982)
    static let sidebarBackground = Color(red: 0.948, green: 0.957, blue: 0.971)
    static let elevatedSurface = Color.white.opacity(0.92)
    static let solidSurface = Color.white
    static let controlFill = Color.black.opacity(0.045)
    static let controlFillHover = Color.black.opacity(0.065)
    static let divider = Color.black.opacity(0.075)
    static let border = Color.black.opacity(0.085)

    static let textPrimary = Color.black.opacity(0.84)
    static let textSecondary = Color.black.opacity(0.58)
    static let textBody = Color.black.opacity(0.72)
    static let textTertiary = Color.black.opacity(0.42)
    static let textDisabled = Color.black.opacity(0.30)

    static let accent = Color(red: 0.31, green: 0.48, blue: 0.94)
    static let accentViolet = Color(red: 0.52, green: 0.42, blue: 0.92)
    static let accentSoft = Color(red: 0.90, green: 0.93, blue: 0.995)
    static let accentBorder = accent.opacity(0.24)
    static let positive = Color(red: 0.20, green: 0.63, blue: 0.39)
    static let warning = Color(red: 0.88, green: 0.55, blue: 0.12)
    static let destructive = Color(red: 0.82, green: 0.25, blue: 0.28)

    static let islandBackground = Color.black
    static let islandSurface = Color.white.opacity(0.09)
    static let islandSurfaceHover = Color.white.opacity(0.13)
    static let islandBorder = Color.white.opacity(0.12)
    static let islandTextPrimary = Color.white.opacity(0.92)
    static let islandTextSecondary = Color.white.opacity(0.58)

    static let accentGradient = LinearGradient(
        colors: [accent, accentViolet],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    static let pageHorizontal: CGFloat = 28
    static let pageVertical: CGFloat = 26
    static let section: CGFloat = 20
    static let rowHorizontal: CGFloat = 16
    static let rowVertical: CGFloat = 12
}

enum AppRadius {
    static let control: CGFloat = 8
    static let row: CGFloat = 10
    static let card: CGFloat = 14
    static let largeCard: CGFloat = 16
    static let panel: CGFloat = 20
    static let capsule: CGFloat = 999
}

enum AppTypography {
    static let pageTitle = Font.system(size: 26, weight: .bold)
    static let pageSubtitle = Font.system(size: 14, weight: .medium)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let rowTitle = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let supporting = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)
    static let control = Font.system(size: 13, weight: .semibold)
    static let badge = Font.system(size: 10, weight: .bold)

    static func pageTitle(_ preference: AppFontPreference) -> Font {
        preference.font(size: 26, weight: .bold)
    }

    static func pageSubtitle(_ preference: AppFontPreference) -> Font {
        preference.font(size: 14, weight: .medium)
    }

    static func sectionTitle(_ preference: AppFontPreference) -> Font {
        preference.font(size: 16, weight: .semibold)
    }

    static func rowTitle(_ preference: AppFontPreference) -> Font {
        preference.font(size: 14, weight: .semibold)
    }

    static func supporting(_ preference: AppFontPreference) -> Font {
        preference.font(size: 12, weight: .medium)
    }

    static func control(_ preference: AppFontPreference) -> Font {
        preference.font(size: 13, weight: .semibold)
    }

    static func badge(_ preference: AppFontPreference) -> Font {
        preference.font(size: 10, weight: .bold)
    }
}

private struct AppFontPreferenceKey: EnvironmentKey {
    static let defaultValue: AppFontPreference = .system
}

extension EnvironmentValues {
    var appFontPreference: AppFontPreference {
        get { self[AppFontPreferenceKey.self] }
        set { self[AppFontPreferenceKey.self] = newValue }
    }
}

struct AppShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let card = AppShadowStyle(
        color: .black.opacity(0.035),
        radius: 10,
        x: 0,
        y: 4
    )
    static let floating = AppShadowStyle(
        color: .black.opacity(0.10),
        radius: 16,
        x: 0,
        y: 8
    )
}

enum AppMotion {
    static let instant = Animation.easeOut(duration: 0.10)
    static let quick = Animation.easeOut(duration: 0.14)
    static let standard = Animation.easeInOut(duration: 0.18)
    static let page = Animation.smooth(duration: 0.24, extraBounce: 0)
    static let gentleSpring = Animation.spring(response: 0.30, dampingFraction: 0.86)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

enum AppIconStyle {
    static let sidebarSize: CGFloat = 16
    static let rowSize: CGFloat = 15
    static let actionSize: CGFloat = 14
    static let emptyStateSize: CGFloat = 26
    static let sidebarFrame: CGFloat = 24
    static let rowFrame: CGFloat = 30
}

enum AppControlStyle {
    static let compactHeight: CGFloat = 30
    static let regularHeight: CGFloat = 36
    static let largeHeight: CGFloat = 42
    static let iconButtonSize: CGFloat = 32
    static let disabledOpacity = 0.48
    static let pressedOpacity = 0.82
    static let pressedScale: CGFloat = 0.985
    static let hoverLift: CGFloat = -1
}

enum AppSurfaceKind {
    case elevated
    case inset
    case island
}

private struct AppSurfaceModifier: ViewModifier {
    let kind: AppSurfaceKind
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    }
                    .shadow(
                        color: kind == .elevated ? AppShadowStyle.card.color : .clear,
                        radius: kind == .elevated ? AppShadowStyle.card.radius : 0,
                        x: AppShadowStyle.card.x,
                        y: AppShadowStyle.card.y
                    )
            }
    }

    private var fill: Color {
        switch kind {
        case .elevated: AppColor.elevatedSurface
        case .inset: AppColor.controlFill
        case .island: AppColor.islandSurface
        }
    }

    private var border: Color {
        switch kind {
        case .elevated, .inset: AppColor.border
        case .island: AppColor.islandBorder
        }
    }
}

extension View {
    func appSurface(
        _ kind: AppSurfaceKind = .elevated,
        radius: CGFloat = AppRadius.card
    ) -> some View {
        modifier(AppSurfaceModifier(kind: kind, radius: radius))
    }

    func appShadow(_ style: AppShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

enum AppButtonRole {
    case primary
    case secondary
    case quiet
    case icon
}

struct AppButtonStyle: ButtonStyle {
    var role: AppButtonRole = .secondary
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        AppButtonStyleBody(
            configuration: configuration,
            role: role,
            isSelected: isSelected
        )
    }
}

struct AppSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        AppSwitchToggleBody(configuration: configuration)
    }
}

private struct AppSwitchToggleBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let configuration: ToggleStyle.Configuration

    var body: some View {
        Button {
            withAnimation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(configuration.isOn ? AppColor.accentBorder : AppColor.border, lineWidth: 1)
                    }

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            }
            .frame(width: 42, height: 24)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(AppSwitchButtonStyle())
        .opacity(isEnabled ? 1 : AppControlStyle.disabledOpacity)
        .onHover { isHovering = $0 }
        .animation(AppMotion.resolved(AppMotion.quick, reduceMotion: reduceMotion), value: isHovering)
    }

    private var trackColor: Color {
        if configuration.isOn {
            return AppColor.accent.opacity(isHovering ? 0.92 : 1)
        }
        return isHovering ? AppColor.controlFillHover : Color.black.opacity(0.12)
    }
}

private struct AppSwitchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AppControlStyle.pressedScale : 1)
            .opacity(configuration.isPressed ? AppControlStyle.pressedOpacity : 1)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }
}

private struct AppButtonStyleBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appFontPreference) private var fontPreference
    @State private var isHovering = false

    let configuration: ButtonStyle.Configuration
    let role: AppButtonRole
    let isSelected: Bool

    var body: some View {
        configuration.label
            .font(AppTypography.control(fontPreference))
            .foregroundStyle(foreground)
            .padding(.horizontal, role == .icon ? 0 : AppSpacing.lg)
            .frame(
                minWidth: role == .icon ? AppControlStyle.iconButtonSize : nil,
                minHeight: role == .icon
                    ? AppControlStyle.iconButtonSize
                    : AppControlStyle.regularHeight
            )
            .background {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? AppControlStyle.pressedScale : 1)
            .offset(y: isHovering && !configuration.isPressed ? AppControlStyle.hoverLift : 0)
            .opacity(isEnabled ? 1 : AppControlStyle.disabledOpacity)
            .onHover { isHovering = $0 }
            .animation(AppMotion.resolved(.easeOut(duration: 0.12), reduceMotion: reduceMotion), value: isHovering)
            .animation(AppMotion.resolved(AppMotion.instant, reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch role {
        case .primary: .white
        case .secondary, .quiet, .icon: isSelected ? AppColor.accent : AppColor.textBody
        }
    }

    private var background: Color {
        if role == .primary {
            return AppColor.accent.opacity(configuration.isPressed ? AppControlStyle.pressedOpacity : 1)
        }
        if isSelected {
            return AppColor.accentSoft
        }
        if isHovering {
            return AppColor.controlFillHover
        }
        return role == .secondary ? AppColor.controlFill : .clear
    }

    private var border: Color {
        if isSelected { return AppColor.accentBorder }
        return role == .secondary ? AppColor.border : .clear
    }
}
