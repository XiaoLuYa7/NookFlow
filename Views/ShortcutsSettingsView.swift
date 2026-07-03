import SwiftUI

@MainActor
final class ShortcutSettingsViewModel: ObservableObject {
    @Published private(set) var shortcuts: [ShortcutItem]
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private let store: ShortcutsStore
    private let maxPinnedCount = ShortcutsStore.slotCount

    init(store: ShortcutsStore? = nil) {
        self.store = store ?? ShortcutsStore.shared
        self.shortcuts = []
    }

    var pinnedShortcuts: [ShortcutItem] {
        shortcuts
            .filter(\.isPinnedToIsland)
            .sorted { $0.order < $1.order }
    }

    var pinnedCount: Int {
        pinnedShortcuts.count
    }

    var pinnedNamesText: String {
        let names = pinnedShortcuts.map(\.name)
        return names.isEmpty ? "还没有快捷指令显示在灵动岛里" : names.joined(separator: "、")
    }

    var countText: String {
        "\(pinnedCount)/\(maxPinnedCount)"
    }

    func syncFromStore() {
        syncPinnedStateFromStore()
    }

    func togglePinned(_ shortcut: ShortcutItem) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        guard shortcut.shortcutIdentifier == shortcut.id.uuidString else {
            statusMessage = "该快捷指令不是有效的系统快捷指令"
            return
        }

        if shortcuts[index].isPinnedToIsland {
            withAnimation(.easeInOut(duration: 0.18)) {
                shortcuts[index].isPinnedToIsland = false
                shortcuts[index].order = 0
            }
            persistPinnedShortcuts()
            statusMessage = "已从灵动岛移除“\(shortcut.name)”"
            return
        }

        guard pinnedCount < maxPinnedCount else {
            statusMessage = "已选满 \(maxPinnedCount) 个，请先移出一个"
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            shortcuts[index].isPinnedToIsland = true
            shortcuts[index].order = nextPinnedOrder()
        }
        persistPinnedShortcuts()
        statusMessage = "已加入灵动岛：“\(shortcut.name)”"
    }

    func run(_ shortcut: ShortcutItem) {
        guard shortcut.canRun else {
            statusMessage = "“\(shortcut.name)”暂不可运行"
            return
        }

        store.run(shortcut)
        statusMessage = "正在运行“\(shortcut.name)”"
    }

    func isRunning(_ shortcut: ShortcutItem) -> Bool {
        store.isRunning(shortcut)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "正在刷新快捷指令"

        Task { [weak self] in
            guard let self else { return }
            let result = await store.fetchAvailableShortcuts()

            switch result {
            case .success(let fetchedShortcuts):
                shortcuts = fetchedShortcuts.enumerated().map { index, item in
                    ShortcutItem(
                        id: item.id,
                        name: item.name,
                        detailText: item.detailText.isEmpty ? "来自系统快捷指令" : item.detailText,
                        isPinnedToIsland: false,
                        canRun: item.canRun,
                        order: index,
                        shortcutIdentifier: item.shortcutIdentifier
                    )
                }
                _ = store.reconcileSlots(with: shortcuts)
                syncPinnedStateFromStore()
                statusMessage = fetchedShortcuts.isEmpty
                    ? "未找到快捷指令，请先在系统快捷指令 App 中创建快捷指令"
                    : "已刷新 \(shortcuts.count) 个快捷指令"

            case .failure(let error):
                statusMessage = error.message.isEmpty ? "刷新失败，已保留当前列表" : error.message
            }

            isLoading = false
        }
    }

    func detailText(for shortcut: ShortcutItem) -> String {
        if shortcut.isPinnedToIsland {
            return "已在灵动岛显示，点整行可移除"
        }
        if pinnedCount >= maxPinnedCount {
            return "已选满 \(maxPinnedCount) 个，请先移出一个"
        }
        return shortcut.detailText.isEmpty ? "点整行可加入灵动岛" : shortcut.detailText
    }

    func canAdd(_ shortcut: ShortcutItem) -> Bool {
        shortcut.isPinnedToIsland || pinnedCount < maxPinnedCount
    }

    private func syncPinnedStateFromStore() {
        let savedSlots = store.slots
            .enumerated()
            .compactMap { slot, item -> (slot: Int, item: ShortcutItem)? in
                guard let item else { return nil }
                return (slot, item)
            }

        var mergedShortcuts = shortcuts.map { shortcut in
            var shortcut = shortcut
            shortcut.isPinnedToIsland = false
            return shortcut
        }

        for savedSlot in savedSlots {
            var savedItem = savedSlot.item
            savedItem.isPinnedToIsland = true
            savedItem.order = savedSlot.slot

            if let exactIndex = mergedShortcuts.firstIndex(where: { $0.id == savedItem.id }) {
                mergedShortcuts[exactIndex] = savedItem
            }
        }

        shortcuts = mergedShortcuts
    }

    private func persistPinnedShortcuts() {
        let pinned = pinnedShortcuts

        for slot in 0..<maxPinnedCount {
            if slot < pinned.count {
                store.setShortcut(pinned[slot], at: slot)
            } else {
                store.clearSlot(slot)
            }
        }
    }

    private func nextPinnedOrder() -> Int {
        (pinnedShortcuts.map(\.order).max() ?? -1) + 1
    }

}

struct ShortcutsSettingsView: View {
    @StateObject private var viewModel = ShortcutSettingsViewModel()

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: ShortcutSettingsStyle.contentMaxWidth) {
            PageHeaderView(
                title: "快捷指令",
                subtitle: "点击整行加入或移除，右侧按钮可以直接运行。",
                icon: "bolt.fill"
            ) {
                Button(action: viewModel.refresh) {
                    Label(viewModel.isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AppButtonStyle(role: .secondary))
                .disabled(viewModel.isLoading)
            }
        } content: {
            SettingsSectionCard(
                title: "灵动岛中的快捷指令",
                subtitle: "最多保留两个最常用操作",
                footer: "建议只保留 1 到 2 个常用操作，灵动岛会更清爽。"
            ) {
                ShortcutIslandSummaryCard(
                    pinnedCount: viewModel.pinnedCount,
                    maxCount: ShortcutsStore.slotCount,
                    pinnedNamesText: viewModel.pinnedNamesText
                )
            }

            SettingsSectionCard(
                title: "可用的快捷指令",
                subtitle: "已选中项目会以柔和的蓝紫色标记"
            ) {
                ShortcutListContainerView(
                    shortcuts: viewModel.shortcuts,
                    viewModel: viewModel
                )
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(AppTypography.supporting)
                    .foregroundStyle(ShortcutSettingsStyle.secondaryText)
                    .transition(.opacity)
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

struct ShortcutIslandSummaryCard: View {
    let pinnedCount: Int
    let maxCount: Int
    let pinnedNamesText: String

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("灵动岛席位")
                    .font(AppTypography.caption)
                    .foregroundStyle(ShortcutSettingsStyle.secondaryText)

                Text(pinnedCount == 0 ? "还没有固定快捷指令" : "\(pinnedCount) 个快捷指令已固定")
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(ShortcutSettingsStyle.primaryText)
                    .contentTransition(.numericText())

                Text(pinnedNamesText)
                    .font(AppTypography.supporting)
                    .foregroundStyle(ShortcutSettingsStyle.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: AppSpacing.md)

            HStack(alignment: .center, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<maxCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index < pinnedCount ? AppColor.accent : AppColor.controlFillHover)
                            .frame(width: 18, height: 6)
                    }
                }

                Text("\(pinnedCount)/\(maxCount)")
                    .font(AppTypography.control)
                    .foregroundStyle(ShortcutSettingsStyle.countText)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 64)
        .appSurface(.inset, radius: AppRadius.row)
        .animation(AppMotion.standard, value: pinnedCount)
    }
}

struct ShortcutListContainerView: View {
    let shortcuts: [ShortcutItem]
    @ObservedObject var viewModel: ShortcutSettingsViewModel

    var body: some View {
        Group {
            if shortcuts.isEmpty, !viewModel.isLoading {
                EmptyStateView(
                    icon: "bolt.slash",
                    title: "未找到快捷指令",
                    message: "请先在系统快捷指令 App 中创建快捷指令。"
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(shortcuts) { shortcut in
                        ShortcutRowView(
                            shortcut: shortcut,
                            detailText: viewModel.detailText(for: shortcut),
                            isRunning: viewModel.isRunning(shortcut),
                            canAdd: viewModel.canAdd(shortcut),
                            onToggle: { viewModel.togglePinned(shortcut) },
                            onRun: { viewModel.run(shortcut) }
                        )

                        if shortcut.id != shortcuts.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                                .overlay(ShortcutSettingsStyle.divider)
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.xs)
    }
}

struct ShortcutRowView: View {
    let shortcut: ShortcutItem
    let detailText: String
    let isRunning: Bool
    let canAdd: Bool
    let onToggle: () -> Void
    let onRun: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: AppRadius.capsule, style: .continuous)
                .fill(shortcut.isPinnedToIsland ? AppColor.accent : Color.clear)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(shortcut.name)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text(detailText)
                    .font(AppTypography.supporting)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: AppSpacing.md)

            if shortcut.isPinnedToIsland {
                Text("已加入")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColor.accent)
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.accentSoft)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(AppColor.accentBorder, lineWidth: 1)
                            }
                    }
            }

            ShortcutRunButton(
                title: isRunning ? "运行中" : "运行",
                isEnabled: shortcut.canRun && !isRunning,
                action: onRun
            )
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(minHeight: 62)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(rowBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                        .stroke(shortcut.isPinnedToIsland ? AppColor.accentBorder : Color.clear, lineWidth: 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous))
        .opacity(canAdd ? 1 : 0.64)
        .onTapGesture(perform: onToggle)
        .onHover { hovering in
            isHovering = hovering
        }
        .handCursor()
        .animation(AppMotion.standard, value: shortcut.isPinnedToIsland)
        .animation(AppMotion.quick, value: isHovering)
    }

    private var rowBackground: Color {
        if shortcut.isPinnedToIsland {
            return ShortcutSettingsStyle.selectedRowBackground
        }
        if isHovering && canAdd {
            return ShortcutSettingsStyle.hoverRowBackground
        }
        return .clear
    }

    private var titleColor: Color {
        canAdd ? ShortcutSettingsStyle.primaryText : ShortcutSettingsStyle.primaryText.opacity(0.58)
    }

    private var subtitleColor: Color {
        canAdd ? ShortcutSettingsStyle.secondaryText : ShortcutSettingsStyle.secondaryText.opacity(0.58)
    }
}

struct ShortcutRunButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.control)
                .foregroundStyle(ShortcutSettingsStyle.runButtonText.opacity(isEnabled ? 1 : 0.52))
                .padding(.horizontal, AppSpacing.md)
                .frame(height: AppControlStyle.compactHeight)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(ShortcutSettingsStyle.runButtonBackground.opacity(isEnabled ? 1 : 0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .stroke(AppColor.border, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .handCursor()
    }
}

private enum ShortcutSettingsStyle {
    static let pageBackground = AppColor.pageBackground
    static let cardBackground = AppColor.elevatedSurface
    static let selectedRowBackground = AppColor.accentSoft
    static let hoverRowBackground = AppColor.controlFillHover
    static let runButtonBackground = AppColor.controlFill
    static let blue = AppColor.accent
    static let primaryText = AppColor.textPrimary
    static let secondaryText = AppColor.textSecondary
    static let sectionTitle = AppColor.textTertiary
    static let countText = AppColor.textSecondary
    static let runButtonText = AppColor.textSecondary
    static let divider = AppColor.divider
    static let cardRadius = AppRadius.largeCard
    static let sectionSpacing = AppSpacing.section
    static let contentMaxWidth: CGFloat = 1040
}
