import AppKit
import SwiftUI

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
    @Binding var selection: SettingsPage
    @Binding var isCollapsed: Bool

    private let pages: [SettingsPage] = [
        .home,
        .todo,
        .music,
        .quickApps,
        .shortcuts,
        .notifications,
        .general,
        .about
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(pages) { page in
                        SidebarItemView(
                            title: page.title,
                            systemName: page.icon,
                            isSelected: selection == page,
                            isCollapsed: isCollapsed
                        ) {
                            withAnimation(AppMotion.standard) {
                                selection = page
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.sm)
            }
            .scrollIndicators(.never)

            collapseButton
                .padding(AppSpacing.sm)
        }
        .frame(width: isCollapsed ? 56 : 160)
        .background(AppColor.sidebarBackground)
        .animation(AppMotion.page, value: isCollapsed)
    }

    private var brand: some View {
        HStack(spacing: AppSpacing.md) {
            Image(nsImage: AppBrandAsset.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("L-Nook")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("偏好设置")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xxl)
        .padding(.bottom, AppSpacing.lg)
    }

    private var collapseButton: some View {
        SidebarItemView(
            title: isCollapsed ? "展开边栏" : "收起边栏",
            systemName: "sidebar.left",
            isSelected: false,
            isCollapsed: isCollapsed
        ) {
            isCollapsed.toggle()
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                Image(systemName: systemName)
                    .font(.system(size: AppIconStyle.sidebarSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44, height: AppControlStyle.largeHeight, alignment: .center)

                if !isCollapsed {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .lineLimit(1)
                        .padding(.leading, AppSpacing.xs)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AppControlStyle.largeHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .fill(background)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                                .stroke(AppColor.accentBorder, lineWidth: 1)
                        }
                    }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AppColor.accentGradient)
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
