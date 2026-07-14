import AppKit
import SwiftUI

struct QuickAppsSettingsView: View {

    @ObservedObject private var store = QuickAppsStore.shared
    @StateObject private var applicationsProvider = ApplicationsProvider()
    @State private var searchText = ""
    @State private var currentPage = 0
    @State private var draggedItemID: UUID?
    @State private var dragSourceIndex: Int?
    @State private var dragTargetVisualIndex: Int?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragPageTurnCandidate: QuickAppDragPageDirection?
    @State private var dragPageTurnCandidateStartDate = Date.distantPast
    @State private var lastDragPageTurnDate = Date.distantPast

    private let appColumns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: AppSpacing.sm, alignment: .top)
    ]
    private let previewColumns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 6)
    private let previewPageGap: CGFloat = 12
    private let previewPageHeight: CGFloat = 88
    private let previewCellHeight: CGFloat = 58
    private let previewIconSize: CGFloat = 26
    private static let previewCoordinateSpaceName = "quickAppsSelectedPreviewArea"
    private static let dragStartThreshold: CGFloat = 4
    private static let dragPageTurnDelay: TimeInterval = 0.25
    private static let dragPageTurnCooldown: TimeInterval = 0.45

    private var pageCount: Int {
        max(1, Int(ceil(Double(store.items.count) / Double(QuickAppsStore.pageSize))))
    }

    private var selectedPaths: Set<String> {
        Set(store.items.map(\.applicationPath))
    }

    private var filteredApplications: [ApplicationItem] {
        let source = applicationsProvider.applications.filter { $0.kind == .application }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var draggedItem: QuickAppItem? {
        guard let draggedItemID else { return nil }
        return store.items.first { $0.id == draggedItemID }
    }

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: 1120) {
            PageHeaderView(
                title: "应用管理",
                subtitle: "把常用应用放进灵动岛，并按你的使用习惯调整顺序。",
                icon: "square.grid.2x2"
            ) {
                Button("清空已选") {
                    withAnimation(AppMotion.standard) {
                        store.clearAll()
                        currentPage = 0
                    }
                }
                .buttonStyle(AppButtonStyle(role: .secondary))
                .disabled(store.items.isEmpty)
            }
        } content: {
            overviewCard
            selectedAppsCard
            appPickerCard
        }
        .onAppear {
            applicationsProvider.load()
        }
        .onChange(of: store.items.count) { _, _ in
            currentPage = min(currentPage, pageCount - 1)
        }
    }

    private var overviewCard: some View {
        SettingsSectionCard(
            title: "添加概览",
            subtitle: "最多添加 \(QuickAppsStore.maxCount) 个应用，每页显示 \(QuickAppsStore.pageSize) 个"
        ) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(store.items.isEmpty ? "还没有添加应用" : "\(store.items.count) 个应用已加入")
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .contentTransition(.numericText())

                    Text("灵动岛会按当前顺序分页显示。")
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: AppSpacing.md)

                HStack(spacing: AppSpacing.sm) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.controlFillHover)
                            Capsule()
                                .fill(AppColor.accent)
                                .frame(
                                    width: proxy.size.width * min(
                                        CGFloat(store.items.count) / CGFloat(QuickAppsStore.maxCount),
                                        1
                                    )
                                )
                        }
                    }
                    .frame(width: 72, height: 6)

                    Text("\(store.items.count)/\(QuickAppsStore.maxCount)")
                        .font(AppTypography.control)
                        .foregroundStyle(AppColor.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 64)
            .appSurface(.inset, radius: AppRadius.row)
            .animation(AppMotion.standard, value: store.items.count)
        }
    }

    private var selectedAppsCard: some View {
        SettingsSectionCard(
            title: "已添加到灵动岛",
            subtitle: "拖动调整顺序，点按移除",
            footer: "左右滑动或横向滚轮可以切换分页。"
        ) {
            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack {
                        HStack(spacing: previewPageGap) {
                            ForEach(0..<pageCount, id: \.self) { page in
                                selectedPreviewPage(page, pagerWidth: proxy.size.width)
                                    .frame(width: proxy.size.width)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                        .offset(x: -CGFloat(currentPage) * (proxy.size.width + previewPageGap))

                        if let item = draggedItem {
                            dragPreviewCell(item, width: previewCellWidth(for: proxy.size.width))
                                .position(dragLocation)
                                .allowsHitTesting(false)
                                .zIndex(10)
                        }
                    }
                    .coordinateSpace(name: Self.previewCoordinateSpaceName)
                }
                .padding(AppSpacing.sm)
                .frame(height: previewPageHeight)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onEnded { value in
                            handleHorizontalSwipe(value.translation.width)
                        }
                )
                .background {
                    HorizontalSwipeDetector(supportsAuxiliaryButtons: false) { direction in
                        switch direction {
                        case .left: goToNextPage()
                        case .right: goToPreviousPage()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if pageCount > 1 {
                    HStack(spacing: AppSpacing.sm) {
                        Button(action: goToPreviousPage) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: AppIconStyle.actionSize, weight: .semibold))
                        }
                        .buttonStyle(AppButtonStyle(role: .icon))
                        .disabled(currentPage == 0)

                        ForEach(0..<pageCount, id: \.self) { page in
                            Button {
                                withAnimation(previewPageAnimation) {
                                    currentPage = page
                                }
                            } label: {
                                Capsule()
                                    .fill(page == currentPage ? AppColor.accent : AppColor.controlFillHover)
                                    .frame(width: page == currentPage ? 14 : 6, height: 6)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: goToNextPage) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: AppIconStyle.actionSize, weight: .semibold))
                        }
                        .buttonStyle(AppButtonStyle(role: .icon))
                        .disabled(currentPage >= pageCount - 1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .appSurface(.inset, radius: AppRadius.row)
        }
    }

    private var appPickerCard: some View {
        SettingsSectionCard(
            title: "选择应用",
            subtitle: "点击加入或移除灵动岛"
        ) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                TextField("搜索应用...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                Text("\(filteredApplications.count)")
                    .font(AppTypography.control)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.controlFill)
                    }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: AppControlStyle.largeHeight)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .fill(AppColor.controlFill.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                            .stroke(AppColor.border, lineWidth: 1)
                    }
            }

            if applicationsProvider.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                LazyVGrid(columns: appColumns, spacing: AppSpacing.sm) {
                    ForEach(filteredApplications) { app in
                        applicationChoiceCard(app)
                    }
                }
            }
        }
    }

    private func selectedPreviewPage(_ page: Int, pagerWidth: CGFloat) -> some View {
        LazyVGrid(columns: previewColumns, spacing: AppSpacing.sm) {
            ForEach(0..<QuickAppsStore.pageSize, id: \.self) { index in
                let globalIndex = page * QuickAppsStore.pageSize + index

                if globalIndex < store.items.count {
                    selectedPreviewCell(
                        store.items[globalIndex],
                        globalIndex: globalIndex,
                        pagerWidth: pagerWidth
                    )
                } else {
                    emptyPreviewCell
                }
            }
        }
    }

    private func selectedPreviewCell(_ item: QuickAppItem, globalIndex: Int, pagerWidth: CGFloat) -> some View {
        quickAppPreviewCellContent(item)
            .opacity(draggedItemID == item.id ? 0.36 : 1)
            .onTapGesture {
                guard draggedItemID == nil else { return }

                withAnimation(AppMotion.standard) {
                    store.removeApp(id: item.id)
                }
            }
            .highPriorityGesture(
                DragGesture(
                    minimumDistance: Self.dragStartThreshold,
                    coordinateSpace: .named(Self.previewCoordinateSpaceName)
                )
                .onChanged { value in
                    updateQuickAppDrag(
                        item: item,
                        globalIndex: globalIndex,
                        location: value.location,
                        pagerWidth: pagerWidth
                    )
                }
                .onEnded { value in
                    endQuickAppDrag(location: value.location, pagerWidth: pagerWidth)
                }
            )
    }

    private var emptyPreviewCell: some View {
        RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
            .fill(AppColor.controlFill.opacity(0.55))
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: AppIconStyle.actionSize, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary.opacity(0.7))
            }
            .frame(height: 64)
    }

    private func applicationChoiceCard(_ app: ApplicationItem) -> some View {
        let isSelected = selectedPaths.contains(app.url.path)
        let isDisabled = !isSelected && store.items.count >= QuickAppsStore.maxCount

        return Button {
            withAnimation(AppMotion.standard) {
                if let item = store.items.first(where: { $0.applicationPath == app.url.path }) {
                    store.removeApp(id: item.id)
                } else {
                    _ = store.addApp(at: app.url)
                    currentPage = pageCount - 1
                }
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                RoundedRectangle(cornerRadius: AppRadius.capsule, style: .continuous)
                    .fill(isSelected ? AppColor.accent : Color.clear)
                    .frame(width: 3, height: 28)

                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(app.name)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(isSelected ? "已添加到灵动岛，点一下移除" : "点一下添加到灵动岛")
                        .font(AppTypography.supporting)
                        .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: AppIconStyle.actionSize, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .fill(isSelected ? AppColor.accentSoft : AppColor.controlFill.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                            .stroke(isSelected ? AppColor.accentBorder : AppColor.border, lineWidth: 1)
                    }
            }
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func quickAppPreviewCellContent(_ item: QuickAppItem) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(nsImage: store.icon(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: previewIconSize, height: previewIconSize)
            Text(item.name)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .frame(height: previewCellHeight)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                .fill(AppColor.solidSurface.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 1)
                }
        }
    }

    private func dragPreviewCell(_ item: QuickAppItem, width: CGFloat) -> some View {
        quickAppPreviewCellContent(item)
            .frame(width: width)
            .scaleEffect(1.035)
            .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)
    }

    private func previewCellWidth(for pagerWidth: CGFloat) -> CGFloat {
        let totalColumnSpacing = AppSpacing.sm * CGFloat(max(0, QuickAppsStore.pageSize - 1))
        return max(1, (pagerWidth - totalColumnSpacing) / CGFloat(QuickAppsStore.pageSize))
    }

    private func updateQuickAppDrag(
        item: QuickAppItem,
        globalIndex: Int,
        location: CGPoint,
        pagerWidth: CGFloat
    ) {
        if draggedItemID == nil {
            draggedItemID = item.id
            dragSourceIndex = globalIndex
            dragTargetVisualIndex = globalIndex
            dragPageTurnCandidate = nil
            dragPageTurnCandidateStartDate = .distantPast
            lastDragPageTurnDate = .distantPast
        }

        dragLocation = location
        dragTargetVisualIndex = hoveredItemIndex(for: location, pagerWidth: pagerWidth)
        updateDragPageTurn(location: location, pagerWidth: pagerWidth)
    }

    private func endQuickAppDrag(location: CGPoint, pagerWidth: CGFloat) {
        dragLocation = location
        dragTargetVisualIndex = hoveredItemIndex(for: location, pagerWidth: pagerWidth)
        commitQuickAppDrag()
    }

    private func commitQuickAppDrag() {
        defer { resetQuickAppDrag() }

        guard let draggedItemID,
              let sourceIndex = dragSourceIndex,
              sourceIndex < store.items.count else { return }

        guard let targetIndex = dragTargetVisualIndex,
              store.items.indices.contains(targetIndex),
              targetIndex != sourceIndex else { return }

        withAnimation(AppMotion.standard) {
            store.swapApp(id: draggedItemID, withIndex: targetIndex)
            currentPage = min(pageCount - 1, max(0, targetIndex / QuickAppsStore.pageSize))
        }
    }

    private func resetQuickAppDrag() {
        draggedItemID = nil
        dragSourceIndex = nil
        dragTargetVisualIndex = nil
        dragLocation = .zero
        dragPageTurnCandidate = nil
        dragPageTurnCandidateStartDate = .distantPast
        lastDragPageTurnDate = .distantPast
    }

    private func hoveredItemIndex(for location: CGPoint, pagerWidth: CGFloat) -> Int? {
        let cellWidth = previewCellWidth(for: pagerWidth)
        let pitch = cellWidth + AppSpacing.sm
        let x = min(max(location.x, 0), pagerWidth)
        let rawSlot = Int(floor(x / max(pitch, 1)))
        let localX = x - CGFloat(rawSlot) * pitch

        guard rawSlot >= 0,
              rawSlot < QuickAppsStore.pageSize,
              localX <= cellWidth else { return nil }

        let pageStart = currentPage * QuickAppsStore.pageSize
        let targetIndex = pageStart + rawSlot

        guard store.items.indices.contains(targetIndex) else { return nil }
        return targetIndex
    }

    private func updateDragPageTurn(location: CGPoint, pagerWidth: CGFloat) {
        guard let direction = dragPageTurnDirection(for: location, pagerWidth: pagerWidth),
              canTurnPage(direction) else {
            dragPageTurnCandidate = nil
            dragPageTurnCandidateStartDate = .distantPast
            return
        }

        guard dragPageTurnCandidate != direction else { return }

        dragPageTurnCandidate = direction
        dragPageTurnCandidateStartDate = Date()
        scheduleDragPageTurn(direction, pagerWidth: pagerWidth, startedAt: dragPageTurnCandidateStartDate)
    }

    private func dragPageTurnDirection(for location: CGPoint, pagerWidth: CGFloat) -> QuickAppDragPageDirection? {
        let triggerInset = previewCellWidth(for: pagerWidth) / 6

        if location.x <= triggerInset {
            return .previous
        } else if location.x >= pagerWidth - triggerInset {
            return .next
        }

        return nil
    }

    private func scheduleDragPageTurn(
        _ direction: QuickAppDragPageDirection,
        pagerWidth: CGFloat,
        startedAt: Date
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dragPageTurnDelay) {
            guard draggedItemID != nil,
                  dragPageTurnCandidate == direction,
                  dragPageTurnCandidateStartDate == startedAt else { return }

            turnDragPage(direction, pagerWidth: pagerWidth)
        }
    }

    private func turnDragPage(_ direction: QuickAppDragPageDirection, pagerWidth: CGFloat) {
        let now = Date()
        guard canTurnPage(direction),
              now.timeIntervalSince(lastDragPageTurnDate) >= Self.dragPageTurnCooldown else { return }

        lastDragPageTurnDate = now

        withAnimation(previewPageAnimation) {
            currentPage += direction.offset
        }

        dragTargetVisualIndex = hoveredItemIndex(for: dragLocation, pagerWidth: pagerWidth)
        dragPageTurnCandidate = nil
        dragPageTurnCandidateStartDate = .distantPast

        if dragPageTurnDirection(for: dragLocation, pagerWidth: pagerWidth) == direction,
           canTurnPage(direction) {
            dragPageTurnCandidate = direction
            dragPageTurnCandidateStartDate = Date()
            scheduleDragPageTurn(direction, pagerWidth: pagerWidth, startedAt: dragPageTurnCandidateStartDate)
        }
    }

    private func handleHorizontalSwipe(_ translation: CGFloat) {
        guard abs(translation) > 28 else { return }
        if translation < 0 {
            goToNextPage()
        } else {
            goToPreviousPage()
        }
    }

    private func goToNextPage() {
        guard currentPage < pageCount - 1 else { return }
        withAnimation(previewPageAnimation) {
            currentPage += 1
        }
    }

    private func goToPreviousPage() {
        guard currentPage > 0 else { return }
        withAnimation(previewPageAnimation) {
            currentPage -= 1
        }
    }

    private func canTurnPage(_ direction: QuickAppDragPageDirection) -> Bool {
        switch direction {
        case .previous:
            return currentPage > 0
        case .next:
            return currentPage < pageCount - 1
        }
    }

    private var previewPageAnimation: Animation {
        .smooth(duration: QuickAppsSettingsPageTiming.pageTurnDuration, extraBounce: 0)
    }
}

private enum QuickAppDragPageDirection {
    case previous
    case next

    var offset: Int {
        switch self {
        case .previous:
            return -1
        case .next:
            return 1
        }
    }
}

private enum QuickAppsSettingsPageTiming {
    static var pageTurnDuration: TimeInterval {
        let fps = currentRefreshRate
        let duration = 20.0 / fps
        return min(0.34, max(0.28, duration))
    }

    private static var currentRefreshRate: TimeInterval {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        let fps = TimeInterval(screen?.maximumFramesPerSecond ?? 60)
        return min(240, max(30, fps > 0 ? fps : 60))
    }
}
