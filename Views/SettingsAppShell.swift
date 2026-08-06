import AppKit
import SwiftUI

struct SettingsNavigationGroup: Identifiable {
    let id: String
    let pages: [SettingsPage]
}

struct AppShellView<Sidebar: View, Content: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let content: Content

    init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        self.sidebar = sidebar()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .zIndex(1)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(AppColor.divider)
                        .frame(width: 1)
                }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColor.pageBackground)
    }
}

struct SidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: SettingsPage
    @Binding var isCollapsed: Bool
    @State private var areLabelsVisible = true
    @State private var requestedCollapsed = false
    @State private var collapseAnimationTask: Task<Void, Never>?

    private let navigationGroups: [SettingsNavigationGroup] = [
        SettingsNavigationGroup(id: "core", pages: [.home, .todo, .music, .quickApps]),
        SettingsNavigationGroup(id: "automation", pages: [.shortcuts, .notifications]),
        SettingsNavigationGroup(id: "system", pages: [.general, .about])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(navigationGroups) { group in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(group.pages) { page in
                                SidebarItemView(
                                    title: page.title,
                                    systemName: page.icon,
                                    isSelected: selection == page,
                                    isCollapsed: isCollapsed,
                                    showsTitle: areLabelsVisible
                                ) {
                                    withAnimation(AppMotion.resolved(AppMotion.settingsStandard, reduceMotion: reduceMotion)) {
                                        selection = page
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.md)
            }
            .scrollIndicators(.never)

            collapseButton
                .padding(AppSpacing.sm)
        }
        .frame(width: isCollapsed ? 60 : 184)
        .background {
            if reduceTransparency {
                AppColor.sidebarBackground
            } else {
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(AppColor.sidebarBackground.opacity(0.46))
            }
        }
        .animation(AppMotion.resolved(AppMotion.settingsPage, reduceMotion: reduceMotion), value: isCollapsed)
        .onAppear {
            requestedCollapsed = isCollapsed
            areLabelsVisible = !isCollapsed
        }
        .onDisappear {
            collapseAnimationTask?.cancel()
            collapseAnimationTask = nil
        }
    }

    private var brand: some View {
        HStack(spacing: AppSpacing.md) {
            AppBrandIconView(size: 38)

            if areLabelsVisible {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("NookFlow")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("偏好设置")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
        .padding(.horizontal, isCollapsed ? 0 : AppSpacing.xl)
        .padding(.top, 30)
        .padding(.bottom, AppSpacing.xl)
    }

    private var collapseButton: some View {
        SidebarItemView(
            title: isCollapsed ? "展开边栏" : "收起边栏",
            systemName: "sidebar.left",
            isSelected: false,
            isCollapsed: isCollapsed,
            showsTitle: areLabelsVisible
        ) {
            toggleSidebar()
        }
    }

    private func toggleSidebar() {
        collapseAnimationTask?.cancel()
        requestedCollapsed.toggle()

        if reduceMotion {
            isCollapsed = requestedCollapsed
            areLabelsVisible = !requestedCollapsed
            return
        }

        if requestedCollapsed {
            withAnimation(AppMotion.settingsQuick) {
                areLabelsVisible = false
            }
            collapseAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, requestedCollapsed else { return }
                withAnimation(AppMotion.settingsPage) {
                    isCollapsed = true
                }
            }
        } else {
            withAnimation(AppMotion.settingsPage) {
                isCollapsed = false
            }
            collapseAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, !requestedCollapsed else { return }
                withAnimation(AppMotion.settingsQuick) {
                    areLabelsVisible = true
                }
            }
        }
    }
}

struct SidebarItemView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let title: String
    let systemName: String
    let isSelected: Bool
    let isCollapsed: Bool
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                Image(systemName: systemName)
                    .font(.system(size: AppIconStyle.sidebarSize, weight: isSelected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 38, height: AppControlStyle.largeHeight, alignment: .center)

                if showsTitle {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .lineLimit(1)
                        .padding(.leading, AppSpacing.sm)
                        .transition(.opacity)
                }

                if !isCollapsed {
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? AppColor.accent : AppColor.textBody)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .frame(height: AppControlStyle.largeHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .fill(background)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AppColor.accent)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous))
        }
        .buttonStyle(SidebarPressButtonStyle())
        .help(isCollapsed ? title : "")
        .onHover { isHovering = $0 }
        .animation(AppMotion.resolved(AppMotion.settingsQuick, reduceMotion: reduceMotion), value: isHovering)
        .animation(AppMotion.resolved(AppMotion.settingsStandard, reduceMotion: reduceMotion), value: isSelected)
    }

    private var background: Color {
        if isSelected { return AppColor.accentSoft }
        if isHovering { return AppColor.controlFillHover }
        return .clear
    }
}

private struct SidebarPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                AppMotion.resolved(AppMotion.settingsPress, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
