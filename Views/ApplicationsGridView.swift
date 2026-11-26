import AppKit
import Carbon.HIToolbox
import SwiftUI

private enum ApplicationFilter: String, CaseIterable, Identifiable {
    case all
    case folders
    case applications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "所有"
        case .folders: "文件夹"
        case .applications: "应用程序"
        }
    }

    var systemName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .folders: "folder"
        case .applications: "app.fill"
        }
    }

    func matches(_ kind: ApplicationItemKind) -> Bool {
        switch self {
        case .all: true
        case .folders: kind == .folder
        case .applications: kind == .application
        }
    }
}

struct ApplicationsGridView: View {

    @ObservedObject var provider: ApplicationsProvider
    let acceptsKeyboard: Bool
    let contentWidth: CGFloat
    @StateObject private var autoScrollController = EdgeAutoScrollController()
    @StateObject private var revealScheduler = GridRevealScheduler()

    @State private var searchText = ""
    @State private var selectedFilter: ApplicationFilter = .all
    @State private var showsHiddenApplications = false
    @State private var selectedSort: ApplicationSortOption = .recent
    @State private var usageScoreSnapshot: [ApplicationItem.ID: Double] = [:]
    @State private var keyboardSelection: ApplicationItem.ID?
    @State private var hasAnimatedInitialLoad = false
    @State private var isDraggingItem = false
    @State private var dragSourceItem: ApplicationItem?
    @State private var dragSourceIndex: Int?
    @State private var dropTargetIndex: Int?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragSourceFrame: CGRect = .zero
    @State private var lastDragLocationRenderTime: CFTimeInterval = 0
    @State private var gridAreaSize: CGSize = .zero
    @State private var gridFrameInArea: CGRect = .zero
    @FocusState private var isSearchFocused: Bool

    private static let toolbarTopPadding: CGFloat = 8
    private static let toolbarControlHeight: CGFloat = 34
    private static let toolbarGridSpacing: CGFloat = 12
    private static let gridTopPadding: CGFloat = 6
    private static let gridBottomPadding: CGFloat = 18
    private static let cellWidth: CGFloat = 82
    fileprivate static let iconSize: CGFloat = 46
    private static let cellHeight: CGFloat = 84
    private static let gridConfiguration = AdaptiveGridConfiguration(
        minimumItemWidth: 84,
        maximumItemWidth: 116,
        horizontalSpacing: 14,
        verticalSpacing: 18,
        horizontalPadding: 24
    )
    static var threeRowPageHeight: CGFloat {
        toolbarTopPadding + toolbarControlHeight + toolbarGridSpacing
            + gridTopPadding + 3 * cellHeight + 2 * gridConfiguration.verticalSpacing + gridBottomPadding
    }

    static func leadingIconInset(for width: CGFloat) -> CGFloat {
        gridConfiguration.horizontalPadding + (gridConfiguration.metrics(for: width).columnWidth - iconSize) / 2
    }

    private static let entryScale: CGFloat = 0.72
    private static let removalScale: CGFloat = 0.18
    private static let entryOffsetY: CGFloat = 10
    private static let revealStagger: TimeInterval = 0.018
    private static let maxRevealDelay: TimeInterval = 0.32
    private static let gridReflowAnimation = Animation.spring(response: 0.36, dampingFraction: 0.84, blendDuration: 0.04)
    private static let cellRevealAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0.02)
    private static let cellExitAnimation = Animation.easeInOut(duration: 0.18)
    private static let dragReorderAnimation = Animation.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.04)
    private static let dragSourceOpacity: Double = 0.42
    private static let dragStartThreshold: CGFloat = 4
    private static let dragRenderMinDistance: CGFloat = 8
    private static let geometryFrameEpsilon: CGFloat = 0.5
    private static let autoScrollSlowBand: CGFloat = 100
    private static let autoScrollMediumBand: CGFloat = 70
    private static let autoScrollFastBand: CGFloat = 30
    private static let autoScrollSlowVelocity: CGFloat = 180
    private static let autoScrollMediumVelocity: CGFloat = 420
    private static let autoScrollFastVelocity: CGFloat = 780

    var body: some View {
        let items = visibleItems
        let itemIDs = items.map(\.id)
        let duplicateNames = Set(Dictionary(grouping: items, by: { $0.name.folding(options: .caseInsensitive, locale: .current) })
            .filter { $0.value.count > 1 }.keys)
        let presentedItems = displayedItems(from: items)

        return ScrollViewReader { scrollProxy in
            VStack(alignment: .leading, spacing: Self.toolbarGridSpacing) {
                toolbar

                if provider.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { proxy in
                        ScrollView {
                            LazyVGrid(
                                columns: gridColumns,
                                alignment: .leading,
                                spacing: Self.gridConfiguration.verticalSpacing
                            ) {
                                ForEach(presentedItems) { item in
                                    itemCell(item, showsPath: duplicateNames.contains(item.name.folding(options: .caseInsensitive, locale: .current)))
                                        .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                            .animation(Self.gridReflowAnimation, value: itemIDs)
                            .animation(Self.dragReorderAnimation, value: presentedItems.map(\.id))
                            .padding(.horizontal, Self.gridConfiguration.horizontalPadding)
                            .padding(.top, Self.gridTopPadding)
                            .padding(.bottom, Self.gridBottomPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background {
                                ZStack {
                                    GeometryReader { gridGeo in
                                        Color.clear
                                            .onAppear {
                                                updateGridFrame(gridGeo.frame(in: .named("applicationsGridArea")))
                                            }
                                            .onChange(of: gridGeo.frame(in: .named("applicationsGridArea"))) { _, newFrame in
                                                updateGridFrame(newFrame)
                                            }
                                    }

                                    EdgeAutoScrollViewHost(controller: autoScrollController)
                                        .allowsHitTesting(false)
                                }
                            }

                            if items.isEmpty {
                                emptyState
                            }
                        }
                        .mask { gridEdgeMask(height: proxy.size.height) }
                        .onAppear {
                            gridAreaSize = proxy.size
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            gridAreaSize = newSize
                        }
                    }
                    .coordinateSpace(name: "applicationsGridArea")
                    .overlay {
                        ZStack {
                            dragSourceGhostOverlay
                            dragPreviewOverlay
                        }
                    }
                }
            }
            .background {
                ApplicationGridKeyboardCapture(
                    isEnabled: acceptsKeyboard,
                    onFocus: { isSearchFocused = true },
                    onKey: { handleKey($0, scrollProxy: scrollProxy) }
                )
            }
            .onChange(of: searchText) { _, _ in
                keyboardSelection = nil
            }
        }
        .onAppear {
            provider.load()
            usageScoreSnapshot = provider.usageScores()
            revealItemsAfterChange(from: [], to: itemIDs)
        }
        .onChange(of: itemIDs) { oldIDs, newIDs in
            revealItemsAfterChange(from: oldIDs, to: newIDs)
            if let keyboardSelection, !newIDs.contains(keyboardSelection) {
                self.keyboardSelection = nil
            }
            if isDraggingItem,
               let sourceID = dragSourceItem?.id,
               !newIDs.contains(sourceID) {
                cancelDrag()
            }
        }
        .onDisappear {
            provider.stopBrowsing()
            cancelDrag()
            revealScheduler.cancel()
            isSearchFocused = false
            NSCursor.arrow.set()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField

            Spacer(minLength: 8)

            categoryMenu

            sortMenu
        }
        .padding(.leading, Self.leadingIconInset(for: contentWidth))
        .padding(.trailing, Self.gridConfiguration.horizontalPadding)
        .padding(.top, Self.toolbarTopPadding)
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(ApplicationFilter.allCases) { filter in
                Button {
                    withAnimation(Self.gridReflowAnimation) {
                        selectedFilter = filter
                    }
                } label: {
                    Label(filter.title, systemImage: filter.systemName)
                }
            }
            Divider()
            Toggle("显示隐藏的应用", isOn: $showsHiddenApplications)
        } label: {
            toolbarMenuLabel(
                systemName: selectedFilter.systemName,
                title: selectedFilter.title
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))

            TextField(
                "搜索应用",
                text: $searchText,
                prompt: Text("搜索应用…").foregroundStyle(Color.white.opacity(0.42))
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .textFieldStyle(.plain)
            .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    withAnimation(Self.gridReflowAnimation) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                .buttonStyle(.plain)
                .handCursor()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 240)
        .frame(height: Self.toolbarControlHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            isSearchFocused = true
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ApplicationSortOption.allCases) { option in
                Button {
                    withAnimation(Self.gridReflowAnimation) {
                        selectedSort = option
                        provider.clearManualOrder()
                    }
                    if option == .size {
                        provider.loadSizesIfNeeded()
                    }
                } label: {
                    Label {
                        Text(option.title)
                    } icon: {
                        if option == .name {
                            Image(nsImage: SortNameIcon.image)
                        } else {
                            Image(systemName: option.systemName)
                        }
                    }
                }
            }
        } label: {
            toolbarMenuLabel(
                systemName: selectedSort.systemName,
                title: selectedSort.title,
                iconImage: selectedSort == .name ? SortNameIcon.image : nil
            )
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private func toolbarMenuLabel(systemName: String, title: String, iconImage: NSImage? = nil) -> some View {
        HStack(spacing: 7) {
            Group {
                if let iconImage {
                    Image(nsImage: iconImage).renderingMode(.template)
                } else {
                    Image(systemName: systemName)
                }
            }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .padding(.horizontal, 12)
        .frame(height: Self.toolbarControlHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func gridEdgeMask(height: CGFloat) -> some View {
        let fade = min(0.2, 18 / max(1, height))
        return LinearGradient(
            stops: [
                .init(color: gridFrameInArea.minY < -1 ? .clear : .white, location: 0),
                .init(color: .white, location: fade),
                .init(color: .white, location: 1 - fade),
                .init(color: gridFrameInArea.maxY > height + 1 ? .clear : .white, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func handleKey(_ keyCode: UInt16, scrollProxy: ScrollViewProxy) -> Bool {
        if keyCode == UInt16(kVK_Escape) {
            guard !searchText.isEmpty || keyboardSelection != nil else { return false }
            searchText = ""
            keyboardSelection = nil
            return true
        }

        let offset: Int
        switch keyCode {
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            let items = visibleItems
            if let item = items.first(where: { $0.id == keyboardSelection }) ?? items.first {
                open(item)
            }
            return true
        case UInt16(kVK_LeftArrow): offset = -1
        case UInt16(kVK_RightArrow): offset = 1
        case UInt16(kVK_DownArrow): offset = currentColumnCount
        case UInt16(kVK_UpArrow): offset = -currentColumnCount
        default: return false
        }

        let items = visibleItems
        guard !items.isEmpty else { return true }
        let selectionIndex = items.firstIndex { $0.id == keyboardSelection }
        let index = selectionIndex.map { min(max($0 + offset, 0), items.count - 1) } ?? 0
        let id = items[index].id
        keyboardSelection = id
        scrollProxy.scrollTo(id)
        return true
    }

    private func open(_ item: ApplicationItem) {
        if NSWorkspace.shared.open(item.url) {
            let fromSearch = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            provider.recordLaunch(item, fromSearch: fromSearch)
        }
    }

    private var visibleItems: [ApplicationItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filteredItems = provider.applications
            .filter { item in
                selectedFilter.matches(item.kind)
                    && (showsHiddenApplications || !provider.hiddenApplicationIdentities.contains(item.catalogIdentity))
                    && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
            }

        if provider.hasManualOrder,
           query.isEmpty,
           selectedFilter == .all {
            guard selectedSort == .recent, !provider.pinnedApplicationIDs.isEmpty else { return filteredItems }
            let pins = provider.pinnedApplicationIDs
            return filteredItems.filter { pins.contains($0.id) } + filteredItems.filter { !pins.contains($0.id) }
        }

        return filteredItems.sorted(by: sortItems)
    }

    private func displayedItems(from items: [ApplicationItem]) -> [ApplicationItem] {
        guard isDraggingItem,
              let sourceIdx = dragSourceIndex,
              let targetIdx = dropTargetIndex,
              items.indices.contains(sourceIdx),
              targetIdx >= 0,
              targetIdx <= items.count,
              sourceIdx != targetIdx else {
            return items
        }

        var reordered = items
        let sourceItem = reordered.remove(at: sourceIdx)
        reordered.insert(sourceItem, at: min(targetIdx, reordered.count))
        return reordered
    }

    private var emptyState: some View {
        Text("没有匹配项目")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(IslandDesignTokens.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var gridMetrics: AdaptiveGridMetrics {
        Self.gridConfiguration.metrics(for: contentWidth)
    }

    private var gridColumns: [GridItem] {
        let metrics = gridMetrics
        return Array(
            repeating: GridItem(.fixed(metrics.columnWidth), spacing: Self.gridConfiguration.horizontalSpacing, alignment: .top),
            count: metrics.columnCount
        )
    }

    private var currentColumnCount: Int {
        gridMetrics.columnCount
    }

    private var gridColumnWidth: CGFloat {
        gridMetrics.columnWidth
    }

    private var columnStride: CGFloat {
        gridMetrics.columnStride
    }

    private var rowStride: CGFloat {
        Self.cellHeight + Self.gridConfiguration.verticalSpacing
    }

    private func itemFrame(at index: Int) -> CGRect? {
        guard index >= 0, gridFrameInArea.width > 0 else { return nil }

        let columnCount = currentColumnCount
        let column = index % columnCount
        let row = index / columnCount
        let x = gridFrameInArea.minX
            + Self.gridConfiguration.horizontalPadding
            + CGFloat(column) * columnStride
            + (gridColumnWidth - Self.cellWidth) / 2
        let y = gridFrameInArea.minY
            + Self.gridTopPadding
            + CGFloat(row) * rowStride

        return CGRect(x: x, y: y, width: Self.cellWidth, height: Self.cellHeight)
    }

    private func itemFrame(for item: ApplicationItem) -> CGRect? {
        guard let index = displayedItems(from: visibleItems).firstIndex(where: { $0.id == item.id }) else { return nil }
        return itemFrame(at: index)
    }

    private func unclampedItemIndex(from location: CGPoint) -> Int? {
        let gridLocalX = location.x - gridFrameInArea.minX - Self.gridConfiguration.horizontalPadding
        let gridLocalY = location.y - gridFrameInArea.minY - Self.gridTopPadding

        guard gridFrameInArea.width > 0, gridLocalX >= 0, gridLocalY >= 0 else { return nil }

        let column = max(0, min(currentColumnCount - 1, Int(gridLocalX / columnStride)))
        let row = max(0, Int(gridLocalY / rowStride))
        return row * currentColumnCount + column
    }

    private func itemCellContent(
        _ item: ApplicationItem,
        isInteractive: Bool = false,
        showsPath: Bool = false
    ) -> some View {
        ApplicationGridCellContent(
            item: item,
            size: CGSize(width: Self.cellWidth, height: Self.cellHeight),
            isInteractive: isInteractive,
            isSelected: isInteractive && keyboardSelection == item.id,
            showsNameHelp: isInteractive && !showsPath
        )
    }

    private func itemCell(_ item: ApplicationItem, showsPath: Bool) -> some View {
        let isRevealed = revealScheduler.revealedIDs.contains(item.id)
        let isSource = isDraggingItem && dragSourceItem?.id == item.id
        let hidden = provider.hiddenApplicationIdentities.contains(item.catalogIdentity)

        return itemCellContent(item, isInteractive: !isDraggingItem, showsPath: showsPath)
        .modifier(ApplicationPathHelp(path: showsPath ? item.url.path : nil))
        .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            open(item)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragStartThreshold, coordinateSpace: .named("applicationsGridArea"))
                .onChanged { value in
                    if !isDraggingItem {
                        guard let idx = visibleItems.firstIndex(of: item) else { return }
                        isSearchFocused = false
                        isDraggingItem = true
                        dragSourceItem = item
                        dragSourceIndex = idx
                        dragSourceFrame = itemFrame(for: item) ?? CGRect(
                            x: value.startLocation.x - Self.cellWidth / 2,
                            y: value.startLocation.y - Self.cellHeight / 2,
                            width: Self.cellWidth,
                            height: Self.cellHeight
                        )
                        updateRenderedDragLocation(value.location, force: true)
                    }

                    updateRenderedDragLocation(value.location)

                    if shouldPauseReorderForAutoScroll(at: value.location) {
                        autoScrollController.updateEdgeAutoScroll(
                            dragLocation: value.location,
                            viewportHeight: gridAreaSize.height,
                            slowBand: Self.autoScrollSlowBand,
                            mediumBand: Self.autoScrollMediumBand,
                            fastBand: Self.autoScrollFastBand,
                            slowVelocity: Self.autoScrollSlowVelocity,
                            mediumVelocity: Self.autoScrollMediumVelocity,
                            fastVelocity: Self.autoScrollFastVelocity
                        )
                    } else {
                        autoScrollController.stop()
                        updateDragTarget(at: value.location)
                    }
                }
                .onEnded { value in
                    handleDragEnd(item: item, at: value.location)
                }
        )
        .contextMenu {
            if item.kind == .application {
                Button(provider.pinnedApplicationIDs.contains(item.id) ? "取消置顶" : "置顶") {
                    provider.togglePin(item)
                }
                Button(hidden ? "取消隐藏" : "隐藏此应用") {
                    provider.setHidden(!hidden, for: item)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if provider.pinnedApplicationIDs.contains(item.id) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .handCursor()
        .opacity(isRevealed && !isSource ? (hidden ? 0.55 : 1) : 0)
        .scaleEffect(isRevealed ? 1 : Self.entryScale)
        .offset(y: isRevealed ? 0 : Self.entryOffsetY)
        .transition(
            .asymmetric(
                insertion: .scale(scale: Self.entryScale).combined(with: .opacity),
                removal: .scale(scale: Self.removalScale).combined(with: .opacity)
            )
        )
        .animation(Self.cellRevealAnimation, value: isRevealed)
        .animation(Self.dragReorderAnimation, value: isSource)
    }

    private func calculateDropTarget(from location: CGPoint) -> Int? {
        let totalItems = visibleItems.count
        guard totalItems > 0 else { return nil }
        guard let targetIndex = unclampedItemIndex(from: location) else { return nil }
        return max(0, min(totalItems, targetIndex))
    }

    private func updateDragTarget(at location: CGPoint) {
        let newTarget = calculateDropTarget(from: location)
        guard dropTargetIndex != newTarget else { return }

        withAnimation(Self.dragReorderAnimation) {
            dropTargetIndex = newTarget
        }
    }

    private func shouldPauseReorderForAutoScroll(at location: CGPoint) -> Bool {
        guard gridAreaSize.height > 0 else { return false }

        let isTopZone = max(0, location.y) <= Self.autoScrollSlowBand
        let isBottomZone = max(0, gridAreaSize.height - location.y) <= Self.autoScrollSlowBand

        return (isTopZone && autoScrollController.canScrollUp)
            || (isBottomZone && autoScrollController.canScrollDown)
    }

    private func updateRenderedDragLocation(_ location: CGPoint, force: Bool = false) {
        let now = CACurrentMediaTime()
        let elapsed = now - lastDragLocationRenderTime
        let distance = hypot(location.x - dragLocation.x, location.y - dragLocation.y)

        guard force
                || lastDragLocationRenderTime == 0
                || elapsed >= DisplayRefreshTiming.frameInterval
                || distance >= Self.dragRenderMinDistance else {
            return
        }

        dragLocation = location
        lastDragLocationRenderTime = now
    }

    private func updateGridFrame(_ frame: CGRect) {
        guard !approximatelyEqual(gridFrameInArea, frame, tolerance: Self.geometryFrameEpsilon) else { return }
        gridFrameInArea = frame
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private func handleDragEnd(item: ApplicationItem, at location: CGPoint) {
        defer { cancelDrag() }

        guard isDraggingItem,
              let sourceIdx = dragSourceIndex,
              gridFrameInArea.contains(location),
              let targetIdx = calculateDropTarget(from: location) ?? dropTargetIndex,
              targetIdx != sourceIdx else { return }

        let itemsAtDrop = visibleItems
        guard sourceIdx < itemsAtDrop.count,
              itemsAtDrop[sourceIdx].id == item.id else { return }

        provider.reorderApplications(from: sourceIdx, to: targetIdx, visibleItems: itemsAtDrop)
    }

    private func cancelDrag() {
        isDraggingItem = false
        dragSourceItem = nil
        dragSourceIndex = nil
        dropTargetIndex = nil
        dragLocation = .zero
        dragSourceFrame = .zero
        lastDragLocationRenderTime = 0
        autoScrollController.stop()
    }

    @ViewBuilder
    private var dragSourceGhostOverlay: some View {
        if isDraggingItem, let item = dragSourceItem, !dragSourceFrame.isEmpty {
            let ghostFrame = itemFrame(for: item) ?? dragSourceFrame
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.46))
                    .frame(width: Self.cellWidth, height: Self.cellHeight)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    .frame(width: Self.cellWidth, height: Self.cellHeight)

                itemCellContent(item)
                    .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
                    .opacity(Self.dragSourceOpacity)
            }
            .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .center)
            .position(
                x: ghostFrame.midX,
                y: ghostFrame.midY
            )
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.10), value: isDraggingItem)
            .animation(Self.dragReorderAnimation, value: ghostFrame)
        }
    }

    @ViewBuilder
    private var dragPreviewOverlay: some View {
        if isDraggingItem, let item = dragSourceItem {
            itemCellContent(item)
                .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
                .position(x: dragLocation.x, y: dragLocation.y)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.10), value: isDraggingItem)
        }
    }

    private func revealItemsAfterChange(from oldIDs: [ApplicationItem.ID], to newIDs: [ApplicationItem.ID]) {
        let shouldStagger = !hasAnimatedInitialLoad && oldIDs.isEmpty && !newIDs.isEmpty
        if shouldStagger {
            hasAnimatedInitialLoad = true
        }

        revealScheduler.schedule(
            ids: newIDs,
            staggered: shouldStagger,
            revealAnimation: Self.cellRevealAnimation,
            exitAnimation: Self.cellExitAnimation,
            staggerDelay: Self.revealStagger,
            maximumDelay: Self.maxRevealDelay
        )
    }

    private func sortItems(_ left: ApplicationItem, _ right: ApplicationItem) -> Bool {
        switch selectedSort {
        case .recent:
            let leftPinned = provider.pinnedApplicationIDs.contains(left.id)
            let rightPinned = provider.pinnedApplicationIDs.contains(right.id)
            if leftPinned != rightPinned { return leftPinned }

            let leftScore = usageScoreSnapshot[left.id] ?? 0
            let rightScore = usageScoreSnapshot[right.id] ?? 0
            if leftScore != rightScore { return leftScore > rightScore }

            let leftIsSystem = left.url.path.hasPrefix("/System/")
            let rightIsSystem = right.url.path.hasPrefix("/System/")
            if leftIsSystem != rightIsSystem { return !leftIsSystem }

            let comparison = left.phoneticSortName.localizedStandardCompare(right.phoneticSortName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return compareNames(left, right)
        case .name:
            return compareNames(left, right)
        case .kind:
            if left.kind.sortRank != right.kind.sortRank {
                return left.kind.sortRank < right.kind.sortRank
            }
            return compareNames(left, right)
        case .creationDate:
            switch (left.creationDate, right.creationDate) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return compareNames(left, right)
            }
        case .size:
            let leftSize = left.size ?? -1
            let rightSize = right.size ?? -1
            if leftSize != rightSize {
                return leftSize > rightSize
            }
            return compareNames(left, right)
        }
    }

    private func compareNames(_ left: ApplicationItem, _ right: ApplicationItem) -> Bool {
        left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}

private struct ApplicationPathHelp: ViewModifier {
    let path: String?

    func body(content: Content) -> some View {
        if let path {
            content.help(path)
        } else {
            content
        }
    }
}

private struct ApplicationGridCellContent: View {
    let item: ApplicationItem
    let size: CGSize
    let isInteractive: Bool
    let isSelected: Bool
    let showsNameHelp: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let highlightsHover = isInteractive && isHovered
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: ApplicationsGridView.iconSize, height: ApplicationsGridView.iconSize)
                .scaleEffect(highlightsHover && !reduceMotion ? 1.04 : 1)

            ViewThatFits(in: .vertical) {
                Text(item.name)
                    .fixedSize(horizontal: false, vertical: true)
                if showsNameHelp {
                    Text(item.name)
                        .lineLimit(2)
                        .help(item.name)
                } else {
                    Text(item.name)
                        .lineLimit(2)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(IslandDesignTokens.primaryText)
            .multilineTextAlignment(.center)
            .frame(width: size.width, height: 26, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.15 : highlightsHover ? 0.08 : 0))
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: highlightsHover)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ApplicationGridKeyboardCapture: NSViewRepresentable {
    let isEnabled: Bool
    let onFocus: () -> Void
    let onKey: (UInt16) -> Bool

    func makeNSView(context: Context) -> KeyboardView { KeyboardView() }

    func updateNSView(_ view: KeyboardView, context: Context) {
        view.onFocus = onFocus
        view.onKey = onKey
        view.isEnabled = isEnabled
        view.updateCapture()
    }

    static func dismantleNSView(_ view: KeyboardView, coordinator: ()) {
        view.stopCapture()
    }

    final class KeyboardView: NSView {
        var isEnabled = false
        var onFocus: (() -> Void)?
        var onKey: ((UInt16) -> Bool)?
        private var monitor: Any?
        private weak var captureWindow: NSWindow?
        private var madeWindowKey = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateCapture()
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func updateCapture() {
            guard isEnabled, let window else {
                stopCapture()
                return
            }
            guard captureWindow !== window else { return }

            stopCapture()
            captureWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.captureWindow,
                      window.isKeyWindow, event.window === window,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
                return self.onKey?(event.keyCode) == true ? nil : event
            }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.isEnabled, self.captureWindow === window,
                      window.isVisible else { return }
                if !window.isKeyWindow {
                    window.makeKey()
                    self.madeWindowKey = window.isKeyWindow
                }
                self.onFocus?()
            }
        }

        func stopCapture() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if madeWindowKey, let captureWindow, captureWindow.isKeyWindow {
                captureWindow.resignKey()
            }
            madeWindowKey = false
            captureWindow = nil
        }
    }
}
