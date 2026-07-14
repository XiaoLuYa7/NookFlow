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
            Rectangle()
                .fill(AppColor.divider)
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColor.pageBackground)
    }
}

struct SidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
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
                                    withAnimation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion)) {
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
        .frame(width: isCollapsed ? 60 : 208)
        .background {
            AppColor.sidebarBackground
                .overlay(Color.white.opacity(0.16))
        }
        .animation(AppMotion.resolved(AppMotion.page, reduceMotion: reduceMotion), value: isCollapsed)
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
                        .font(.system(size: 18, weight: .bold))
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
            withAnimation(AppMotion.quick) {
                areLabelsVisible = false
            }
            collapseAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled, requestedCollapsed else { return }
                withAnimation(AppMotion.page) {
                    isCollapsed = true
                }
            }
        } else {
            withAnimation(AppMotion.page) {
                isCollapsed = false
            }
            collapseAnimationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, !requestedCollapsed else { return }
                withAnimation(AppMotion.quick) {
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
                    .font(.system(size: AppIconStyle.sidebarSize, weight: .semibold))
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
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                                .stroke(AppColor.accentBorder.opacity(0.9), lineWidth: 1)
                        }
                    }
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
        .buttonStyle(.plain)
        .help(isCollapsed ? title : "")
        .onHover { isHovering = $0 }
        .animation(AppMotion.resolved(AppMotion.quick, reduceMotion: reduceMotion), value: isHovering)
        .animation(AppMotion.resolved(AppMotion.standard, reduceMotion: reduceMotion), value: isSelected)
    }

    private var background: Color {
        if isSelected { return AppColor.accentSoft }
        if isHovering { return AppColor.controlFillHover }
        return .clear
    }
}
