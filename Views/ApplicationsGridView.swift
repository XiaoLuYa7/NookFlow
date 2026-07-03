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
    @StateObject private var autoScrollController = EdgeAutoScrollController()

    @State private var searchText = ""
    @State private var selectedFilter: ApplicationFilter = .all
    @State private var selectedSort: ApplicationSortOption = .name
    @State private var revealedItemIDs = Set<ApplicationItem.ID>()
    @State private var revealGeneration = 0
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

    private static let gridTopPadding: CGFloat = 6
    private static let gridBottomPadding: CGFloat = 18
    private static let cellWidth: CGFloat = 82
    private static let cellHeight: CGFloat = 84
    private static let gridConfiguration = AdaptiveGridConfiguration(
        minimumItemWidth: 84,
        maximumItemWidth: 116,
        horizontalSpacing: 14,
        verticalSpacing: 36,
        horizontalPadding: 24
    )
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
        Group {
            if provider.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    toolbar

                    GeometryReader { proxy in
                        ScrollView {
                            LazyVGrid(
                                columns: Self.gridConfiguration.columns,
                                alignment: .leading,
                                spacing: Self.gridConfiguration.verticalSpacing
                            ) {
                                ForEach(displayedItems) { item in
                                    itemCell(item)
                                        .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                            .animation(Self.gridReflowAnimation, value: visibleItemIDs)
                            .animation(Self.dragReorderAnimation, value: displayedItemIDs)
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

                            if visibleItems.isEmpty {
                                emptyState
                            }
                        }
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
        }
        .onAppear {
            provider.load()
            revealItemsAfterChange(from: [], to: visibleItemIDs)
        }
        .onChange(of: visibleItemIDs) { oldIDs, newIDs in
            revealItemsAfterChange(from: oldIDs, to: newIDs)
            if isDraggingItem,
               let sourceID = dragSourceItem?.id,
               !newIDs.contains(sourceID) {
                cancelDrag()
            }
        }
        .onDisappear {
            cancelDrag()
            isSearchFocused = false
            NSCursor.arrow.set()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            searchField

            categoryMenu

            sortMenu
        }
        .padding(.horizontal, Self.gridConfiguration.horizontalPadding)
        .padding(.top, 8)
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
        } label: {
            toolbarMenuLabel(
                systemName: selectedFilter.systemName,
                title: selectedFilter.title
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))

            ZStack(alignment: .leading) {
                if searchText.isEmpty {
                    Text("Search...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.42))
                        .allowsHitTesting(false)
                }

                TextField("", text: $searchText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }

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
        .frame(width: 240, height: 34)
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
                    Label(option.title, systemImage: option.systemName)
                }
            }
        } label: {
            toolbarMenuLabel(
                systemName: selectedSort.systemName,
                title: selectedSort.title
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private func toolbarMenuLabel(systemName: String, title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var visibleItems: [ApplicationItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let filteredItems = provider.applications
            .filter { item in
                selectedFilter.matches(item.kind)
                    && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
            }

        if provider.hasManualOrder,
           query.isEmpty,
           selectedFilter == .all {
            return filteredItems
        }

        return filteredItems.sorted(by: sortItems)
    }

    private var visibleItemIDs: [ApplicationItem.ID] {
        visibleItems.map(\.id)
    }

    private var displayedItems: [ApplicationItem] {
        guard isDraggingItem,
              let sourceIdx = dragSourceIndex,
              let targetIdx = dropTargetIndex,
              visibleItems.indices.contains(sourceIdx),
              targetIdx >= 0,
              targetIdx <= visibleItems.count,
              sourceIdx != targetIdx else {
            return visibleItems
        }

        var items = visibleItems
        let sourceItem = items.remove(at: sourceIdx)
        let insertionIndex = min(targetIdx, items.count)
        items.insert(sourceItem, at: insertionIndex)
        return items
    }

    private var displayedItemIDs: [ApplicationItem.ID] {
        displayedItems.map(\.id)
    }

    private var emptyState: some View {
        Text("没有匹配项目")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(IslandDesignTokens.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var gridMetrics: AdaptiveGridMetrics {
        Self.gridConfiguration.metrics(for: gridFrameInArea.width)
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
        guard let index = displayedItems.firstIndex(where: { $0.id == item.id }) else { return nil }
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

    private func itemCellContent(_ item: ApplicationItem) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: Self.cellWidth)
        }
    }

    private func itemCell(_ item: ApplicationItem) -> some View {
        let isRevealed = revealedItemIDs.contains(item.id)
        let itemIndex = visibleItems.firstIndex(of: item)
        let isSource = isDraggingItem && dragSourceItem?.id == item.id

        return itemCellContent(item)
        .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            isSearchFocused = false
            NSWorkspace.shared.open(item.url)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragStartThreshold, coordinateSpace: .named("applicationsGridArea"))
                .onChanged { value in
                    if !isDraggingItem {
                        guard let idx = itemIndex else { return }
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
        .handCursor()
        .help(item.name)
        .opacity(isRevealed ? (isSource ? 0 : 1) : 0)
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

        scheduleReveal(for: visibleItems, staggered: shouldStagger)
    }

    private func scheduleReveal(for items: [ApplicationItem], staggered: Bool) {
        let itemIDs = items.map(\.id)
        let visibleIDSet = Set(itemIDs)
        revealGeneration += 1
        let generation = revealGeneration

        withAnimation(Self.cellExitAnimation) {
            revealedItemIDs.formIntersection(visibleIDSet)
        }

        guard staggered else {
            withAnimation(Self.cellRevealAnimation) {
                revealedItemIDs.formUnion(visibleIDSet)
            }
            return
        }

        for (index, id) in itemIDs.enumerated() where !revealedItemIDs.contains(id) {
            let delay = min(Double(index) * Self.revealStagger, Self.maxRevealDelay)

            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard revealGeneration == generation else { return }

                withAnimation(Self.cellRevealAnimation) {
                    _ = revealedItemIDs.insert(id)
                }
            }
        }
    }

    private func sortItems(_ left: ApplicationItem, _ right: ApplicationItem) -> Bool {
        switch selectedSort {
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
