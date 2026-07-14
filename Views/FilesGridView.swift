import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FilesGridView: View {

    @ObservedObject var provider: FileDataProvider
    @StateObject private var externalDragController = ExternalFileDragController()
    @StateObject private var autoScrollController = EdgeAutoScrollController()
    @StateObject private var revealScheduler = GridRevealScheduler()
    @State private var previewFile: StagingFileItem?
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var hasAnimatedInitialLoad = false
    @State private var selectedFileIDs = Set<StagingFileItem.ID>()
    @State private var isAirDropTargeted = false
    @State private var hasShownFileContent = false
    @State private var directoryContentOpacity = 0.0
    @State private var isDirectoryTransitioning = false
    @State private var directoryTransitionTask: Task<Void, Never>?
    @State private var fileOperationError: String?

    // Drag state
    @State private var isDraggingFile = false
    @State private var dragSourceFile: StagingFileItem?
    @State private var dragSourceIndex: Int?
    @State private var dropTargetIndex: Int?
    @State private var moveToFolderTargetID: StagingFileItem.ID?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragSourceFrame: CGRect = .zero
    @State private var lastDragLocationRenderTime: CFTimeInterval = 0
    @State private var gridAreaSize: CGSize = .zero
    @State private var gridFrameInArea: CGRect = .zero
    @FocusState private var isSearchFocused: Bool

    private static let gridTopPadding: CGFloat = 14
    private static let gridBottomPadding: CGFloat = 18
    private static let cellWidth: CGFloat = 92
    private static let cellHeight: CGFloat = 94
    private static let thumbSize: CGFloat = 44
    private static let airDropBorderWidth: CGFloat = 92
    private static let airDropBorderHeight: CGFloat = 94
    private static let gridConfiguration = AdaptiveGridConfiguration(
        minimumItemWidth: 96,
        maximumItemWidth: 132,
        horizontalSpacing: 14,
        verticalSpacing: 24,
        horizontalPadding: 30
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
    private static let selectionFeedbackAnimation = Animation.easeOut(duration: 0.045)
    private static let externalDragLaunchMargin: CGFloat = 28
    private static let externalDragTopAllowance: CGFloat = 68
    private static let folderCenterEnterInsetX: CGFloat = 22
    private static let folderCenterEnterInsetY: CGFloat = 24
    private static let folderCenterExitInsetX: CGFloat = 14
    private static let folderCenterExitInsetY: CGFloat = 16
    private static let directoryFadeOutDuration: TimeInterval = 0.12
    private static let directoryFadeInDuration: TimeInterval = 0.18
    private static let autoScrollSlowBand: CGFloat = 100
    private static let autoScrollMediumBand: CGFloat = 70
    private static let autoScrollFastBand: CGFloat = 30
    private static let autoScrollSlowVelocity: CGFloat = 180
    private static let autoScrollMediumVelocity: CGFloat = 420
    private static let autoScrollFastVelocity: CGFloat = 780

    var body: some View {
        Group {
            if provider.isLoading && !hasShownFileContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    toolbar

                    GeometryReader { proxy in
                        ScrollView {
                            LazyVGrid(
                                columns: Self.gridConfiguration.columns,
                                alignment: .leading,
                                spacing: Self.gridConfiguration.verticalSpacing
                            ) {
                                airDropCell
                                    .frame(maxWidth: .infinity, alignment: .top)

                                ForEach(displayedFiles) { file in
                                    fileCell(file)
                                        .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                            .animation(Self.gridReflowAnimation, value: visibleFileIDs)
                            .animation(Self.dragReorderAnimation, value: displayedFileIDs)
                            .padding(.horizontal, Self.gridConfiguration.horizontalPadding)
                            .padding(.top, Self.gridTopPadding)
                            .padding(.bottom, Self.gridBottomPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background {
                                ZStack {
                                    GeometryReader { gridGeo in
                                        Color.clear
                                            .onAppear {
                                                updateGridFrame(gridGeo.frame(in: .named("gridArea")))
                                            }
                                            .onChange(of: gridGeo.frame(in: .named("gridArea"))) { _, newFrame in
                                                updateGridFrame(newFrame)
                                            }
                                    }

                                    EdgeAutoScrollViewHost(controller: autoScrollController)
                                        .allowsHitTesting(false)
                                }
                            }

                            if visibleFiles.isEmpty && !provider.searchText.isEmpty {
                                emptySearchState
                            }
                        }
                        .opacity(directoryContentOpacity)
                        .background(
                            ExternalFileDragHost(controller: externalDragController)
                                .allowsHitTesting(false)
                        )
                        .onAppear {
                            gridAreaSize = proxy.size
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            gridAreaSize = newSize
                        }
                    }
                    .coordinateSpace(name: "gridArea")
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
            if !provider.files.isEmpty {
                hasShownFileContent = true
                directoryContentOpacity = 1
            }
            provider.load()
            revealFilesAfterChange(from: [], to: visibleFileIDs)
        }
        .onChange(of: visibleFileIDs) { oldIDs, newIDs in
            selectedFileIDs.formIntersection(Set(newIDs))
            revealFilesAfterChange(from: oldIDs, to: newIDs)
        }
        .onChange(of: provider.currentDirectory) { _, _ in
            selectedFileIDs.removeAll()
            cancelDrag()
        }
        .onChange(of: provider.isLoading) { _, isLoading in
            guard !isLoading else { return }

            hasShownFileContent = true
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeOut(duration: Self.directoryFadeInDuration)) {
                    directoryContentOpacity = 1
                }
                isDirectoryTransitioning = false
            }
        }
        .onDisappear {
            cleanupTransientState()
        }
        .alert(
            "文件操作失败",
            isPresented: Binding(
                get: { fileOperationError != nil },
                set: { if !$0 { fileOperationError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { fileOperationError = nil }
        } message: {
            Text(fileOperationError ?? "")
        }
        .overlay {
            if let file = previewFile {
                previewOverlay(file)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 760
            let spacing: CGFloat = isCompact ? 8 : 12
            let searchWidth: CGFloat = isCompact ? 132 : 230
            let categoryWidth: CGFloat = isCompact ? 40 : 74
            let sortWidth: CGFloat = isCompact ? 40 : 74
            let spacerWidth: CGFloat = isCompact ? 8 : 16
            let pathWidth = max(
                180,
                proxy.size.width - searchWidth - categoryWidth - sortWidth - spacing * 3 - spacerWidth
            )

            HStack(spacing: spacing) {
                breadcrumb(isCompact: isCompact)
                    .frame(width: pathWidth, height: 30, alignment: .leading)
                    .clipped()
                    .opacity(directoryContentOpacity)

                Spacer(minLength: spacerWidth)

                searchField(isCompact: isCompact)
                categoryMenu(showTitle: !isCompact)
                sortMenu(showTitle: !isCompact)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, Self.gridConfiguration.horizontalPadding)
        .padding(.top, 10)
    }

    private func breadcrumb(isCompact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isCompact ? 5 : 8) {
                    breadcrumbLabel(icon: "folder", text: "文稿", isCompact: isCompact, isClickable: false)
                    breadcrumbChevron
                    breadcrumbLabel(icon: "shippingbox", text: IslandDesignTokens.appName, isCompact: isCompact, isClickable: false)
                    breadcrumbChevron
                    breadcrumbButton(icon: "externaldrive.fill", text: "FileData", isCompact: isCompact, isActive: provider.pathSegments.isEmpty) {
                        navigateToDirectory(FileDataProvider.stagingDirectory)
                    }
                    .id("filedata")

                    ForEach(provider.pathSegments) { segment in
                        breadcrumbChevron
                        breadcrumbButton(icon: "folder.fill", text: segment.title, isCompact: isCompact, isActive: segment.url.standardizedFileURL.path == provider.currentDirectory.standardizedFileURL.path) {
                            navigateToDirectory(segment.url)
                        }
                        .id(segment.id)
                    }

                    Color.clear.frame(width: 1, height: 1)
                        .id("breadcrumbTrailing")
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("breadcrumbTrailing", anchor: .trailing)
                }
            }
            .onChange(of: provider.currentDirectory) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("breadcrumbTrailing", anchor: .trailing)
                    }
                }
            }
        }
        .frame(height: 30)
    }

    private var breadcrumbChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.3))
    }

    private func breadcrumbButton(
        icon: String,
        text: String,
        isCompact: Bool,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            breadcrumbLabel(icon: icon, text: text, isCompact: isCompact, isClickable: true, isActive: isActive)
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private func breadcrumbLabel(icon: String, text: String, isCompact: Bool, isClickable: Bool, isActive: Bool = false) -> some View {
        HStack(spacing: isCompact ? 5 : 6) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
            Text(text)
                .font(.system(size: isCompact ? 10 : 12, weight: isActive ? .bold : .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? Color.white : (isClickable ? Color.white.opacity(0.9) : Color.white.opacity(0.55)))
        .padding(.horizontal, isCompact ? 7 : 9)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.14 : 0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func searchField(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))

            ZStack(alignment: .leading) {
                if provider.searchText.isEmpty {
                    Text("Search...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.42))
                        .allowsHitTesting(false)
                }

                TextField("", text: $provider.searchText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
            }

            if !provider.searchText.isEmpty {
                Button(action: {
                    withAnimation(Self.gridReflowAnimation) {
                        provider.searchText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.38))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: isCompact ? 132 : 230, height: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            isSearchFocused = true
        }
        .onHover { hovering in
            if !hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private func categoryMenu(showTitle: Bool) -> some View {
        Menu {
            ForEach(FileCategory.allCases) { cat in
                Button {
                    withAnimation(Self.gridReflowAnimation) {
                        provider.category = cat
                    }
                } label: {
                    Label(cat.title, systemImage: cat.systemName)
                }
            }
        } label: {
            fileToolbarMenuLabel(
                systemName: provider.category.systemName,
                title: provider.category.title,
                showTitle: showTitle
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private func sortMenu(showTitle: Bool) -> some View {
        Menu {
            ForEach(FileSortOption.allCases) { opt in
                Button {
                    withAnimation(Self.gridReflowAnimation) {
                        provider.setSortOption(opt)
                    }
                } label: {
                    Label(opt.title, systemImage: opt.systemName)
                }
            }
        } label: {
            fileToolbarMenuLabel(
                systemName: provider.sortOption.systemName,
                title: provider.sortOption.title,
                showTitle: showTitle
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .handCursor()
    }

    private func fileToolbarMenuLabel(
        systemName: String,
        title: String,
        showTitle: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if showTitle {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, showTitle ? 12 : 0)
        .frame(width: showTitle ? nil : 40, height: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Visible files

    private var visibleFiles: [StagingFileItem] {
        provider.filteredFiles
    }

    private var visibleFileIDs: [StagingFileItem.ID] {
        visibleFiles.map(\.id)
    }

    private var displayedFiles: [StagingFileItem] {
        guard isDraggingFile,
              !isAirDropTargeted,
              moveToFolderTargetID == nil,
              let sourceIdx = dragSourceIndex,
              let targetIdx = dropTargetIndex,
              visibleFiles.indices.contains(sourceIdx),
              targetIdx >= 0,
              targetIdx <= visibleFiles.count,
              sourceIdx != targetIdx else {
            return visibleFiles
        }

        var files = visibleFiles
        let sourceFile = files.remove(at: sourceIdx)
        let insertionIndex = min(targetIdx, files.count)
        files.insert(sourceFile, at: insertionIndex)
        return files
    }

    private var displayedFileIDs: [StagingFileItem.ID] {
        displayedFiles.map(\.id)
    }

    // MARK: - Grid layout

    private var gridMetrics: AdaptiveGridMetrics {
        Self.gridConfiguration.metrics(for: gridFrameInArea.width)
    }

    private var currentColumnCount: Int {
        gridMetrics.columnCount
    }

    private var gridColumnWidth: CGFloat {
        gridMetrics.columnWidth
    }

    private var gridColumnStride: CGFloat {
        gridMetrics.columnStride
    }

    private var gridRowStride: CGFloat {
        Self.cellHeight + Self.gridConfiguration.verticalSpacing
    }

    private var airDropFrame: CGRect {
        gridCellFrame(atGridIndex: 0) ?? .zero
    }

    private func gridCellFrame(atGridIndex gridIndex: Int) -> CGRect? {
        guard gridFrameInArea.width > 0 else { return nil }

        let columnCount = currentColumnCount
        let column = gridIndex % columnCount
        let row = gridIndex / columnCount
        let x = gridFrameInArea.minX
            + Self.gridConfiguration.horizontalPadding
            + CGFloat(column) * gridColumnStride
            + (gridColumnWidth - Self.cellWidth) / 2
        let y = gridFrameInArea.minY
            + Self.gridTopPadding
            + CGFloat(row) * gridRowStride

        return CGRect(x: x, y: y, width: Self.cellWidth, height: Self.cellHeight)
    }

    private func fileFrame(at fileIndex: Int) -> CGRect? {
        guard fileIndex >= 0 else { return nil }
        return gridCellFrame(atGridIndex: fileIndex + 1)
    }

    private func fileFrame(for file: StagingFileItem) -> CGRect? {
        guard let index = displayedFiles.firstIndex(where: { $0.id == file.id }) else { return nil }
        return fileFrame(at: index)
    }

    private func unclampedFileIndex(from location: CGPoint) -> Int? {
        let gridLocalX = location.x - gridFrameInArea.minX - Self.gridConfiguration.horizontalPadding
        let gridLocalY = location.y - gridFrameInArea.minY - Self.gridTopPadding

        guard gridFrameInArea.width > 0, gridLocalX >= 0, gridLocalY >= 0 else { return nil }

        let columnCount = currentColumnCount
        let column = max(0, min(columnCount - 1, Int(gridLocalX / gridColumnStride)))
        let row = max(0, Int(gridLocalY / gridRowStride))
        let gridIndex = row * columnCount + column
        return gridIndex - 1
    }

    // MARK: - AirDrop cell

    private var airDropCell: some View {
        let borderColor = isAirDropTargeted ? Color.white.opacity(0.95) : Color.white.opacity(0.22)
        let borderWidth: CGFloat = isAirDropTargeted ? 2.0 : 1.6
        let iconScale: CGFloat = isAirDropTargeted ? 1.10 : 1.0
        let backgroundOpacity = isAirDropTargeted ? 0.08 : 0.0

        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 34, height: 34)

                Image(systemName: "wave.3.right")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.black.opacity(0.72))
            }
            .scaleEffect(iconScale)
            .padding(.top, 7)

            VStack(spacing: 1) {
                Text("隔空投送")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandDesignTokens.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("拖到这里发送")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .offset(y: 6)
        .frame(width: Self.airDropBorderWidth, height: Self.airDropBorderHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(backgroundOpacity))
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(lineWidth: borderWidth, lineCap: .round, lineJoin: .round, dash: [7, 5])
                )
        )
        .offset(y: -3)
        .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: isAirDropTargeted)
    }

    // MARK: - Empty search state

    private var emptySearchState: some View {
        Text("没有匹配文件")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(IslandDesignTokens.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - File cell

    private func fileCellContent(_ file: StagingFileItem, folderMoveHighlighted: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if folderMoveHighlighted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: Self.thumbSize + 18, height: Self.thumbSize + 16)
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                }

                fileThumbnail(file)
                    .scaleEffect(folderMoveHighlighted ? 1.10 : 1)
            }
            .frame(width: Self.thumbSize + 18, height: Self.thumbSize + 16)

            Text(file.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: Self.cellWidth)
        }
        .animation(Self.dragReorderAnimation, value: folderMoveHighlighted)
    }

    private func fileCell(_ file: StagingFileItem) -> some View {
        let isRevealed = revealScheduler.revealedIDs.contains(file.id)
        let isSelected = selectedFileIDs.contains(file.id)
        let fileIndex = visibleFiles.firstIndex(of: file)
        let isSource = isDraggingFile && dragSourceFile?.id == file.id
        let isFolderMoveTarget = moveToFolderTargetID == file.id

        return fileCellContent(file, folderMoveHighlighted: isFolderMoveTarget)
        .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2) {
            openFile(file)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("gridArea"))
                .onChanged { _ in
                    guard !isDraggingFile,
                          !externalDragController.isDragging else { return }
                    selectFile(file)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragStartThreshold, coordinateSpace: .named("gridArea"))
                .onChanged { value in
                    guard !externalDragController.isDragging else { return }

                    if !isDraggingFile {
                        guard let idx = fileIndex else { return }
                        clearSearchFocus()
                        isDraggingFile = true
                        dragSourceFile = file
                        dragSourceIndex = idx
                        dragSourceFrame = fileFrame(for: file) ?? CGRect(
                            x: value.startLocation.x - Self.cellWidth / 2,
                            y: value.startLocation.y - Self.cellHeight / 2,
                            width: Self.cellWidth,
                            height: Self.cellHeight
                        )
                        updateRenderedDragLocation(value.location, force: true)
                        selectedFileIDs = [file.id]
                    }
                    updateRenderedDragLocation(value.location)

                    if shouldStartExternalFileDrag(at: value.location),
                       externalDragController.startDragging(file) {
                        autoScrollController.stop()
                        cancelDrag()
                        return
                    }

                    isAirDropTargeted = airDropFrame.contains(value.location)

                    if !isAirDropTargeted {
                        if shouldPauseReorderForAutoScroll(at: value.location) {
                            clearFolderMoveTarget()
                        } else {
                            updateInternalDragTarget(at: value.location)
                        }
                    } else {
                        if dropTargetIndex != nil || moveToFolderTargetID != nil {
                            withAnimation(Self.dragReorderAnimation) {
                                dropTargetIndex = nil
                                moveToFolderTargetID = nil
                            }
                        }
                    }

                    updateAutoScrollForCurrentDrag(at: value.location)
                }
                .onEnded { value in
                    guard !externalDragController.isDragging else {
                        cancelDrag()
                        return
                    }
                    handleDragEnd(file: file, at: value.location)
                }
        )
        .help(file.name)
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
        .animation(Self.selectionFeedbackAnimation, value: isSelected)
        .animation(Self.dragReorderAnimation, value: isFolderMoveTarget)
        .animation(Self.dragReorderAnimation, value: isSource)
    }

    /// Calculate the drop target index from a gesture location in the gridArea coordinate space.
    private func calculateDropTarget(from location: CGPoint) -> Int? {
        let totalFiles = visibleFiles.count
        guard totalFiles > 0 else { return nil }
        guard let fileIndex = unclampedFileIndex(from: location) else { return nil }
        return max(0, min(totalFiles, fileIndex))
    }

    private func updateInternalDragTarget(at location: CGPoint) {
        let newTarget = calculateDropTarget(from: location)
        let centerFolderID = folderMoveTarget(at: location, candidate: folderCandidate(at: location))

        if let centerFolderID {
            if moveToFolderTargetID != centerFolderID || dropTargetIndex != nil {
                withAnimation(Self.dragReorderAnimation) {
                    moveToFolderTargetID = centerFolderID
                    dropTargetIndex = nil
                }
            }
            return
        }

        if moveToFolderTargetID != nil || dropTargetIndex != newTarget {
            withAnimation(Self.dragReorderAnimation) {
                moveToFolderTargetID = nil
                dropTargetIndex = newTarget
            }
        }
    }

    private func clearFolderMoveTarget() {
        guard moveToFolderTargetID != nil else { return }

        withAnimation(Self.dragReorderAnimation) {
            moveToFolderTargetID = nil
        }
    }

    private func shouldPauseReorderForAutoScroll(at location: CGPoint) -> Bool {
        guard gridAreaSize.height > 0 else { return false }

        let isTopZone = max(0, location.y) <= Self.autoScrollSlowBand
        let isBottomZone = max(0, gridAreaSize.height - location.y) <= Self.autoScrollSlowBand

        return (isTopZone && autoScrollController.canScrollUp)
            || (isBottomZone && autoScrollController.canScrollDown)
    }

    private func folderCandidate(at location: CGPoint) -> StagingFileItem? {
        guard let fileIndex = unclampedFileIndex(from: location),
              displayedFiles.indices.contains(fileIndex) else { return nil }

        let candidate = displayedFiles[fileIndex]
        guard canMove(dragSourceFile, into: candidate),
              let frame = fileFrame(at: fileIndex),
              frame.contains(location) else { return nil }

        return candidate
    }

    private func folderMoveTarget(at location: CGPoint, candidate: StagingFileItem?) -> StagingFileItem.ID? {
        if let activeID = moveToFolderTargetID,
           let activeFolder = visibleFiles.first(where: { $0.id == activeID }),
           canMove(dragSourceFile, into: activeFolder),
           let frame = fileFrame(for: activeFolder),
           folderCenterRect(for: frame, isActive: true).contains(location) {
            return activeID
        }

        guard let candidate,
              canMove(dragSourceFile, into: candidate),
              let frame = fileFrame(for: candidate),
              folderCenterRect(for: frame, isActive: false).contains(location) else {
            return nil
        }

        return candidate.id
    }

    private func folderCenterRect(for frame: CGRect, isActive: Bool) -> CGRect {
        frame.insetBy(
            dx: isActive ? Self.folderCenterExitInsetX : Self.folderCenterEnterInsetX,
            dy: isActive ? Self.folderCenterExitInsetY : Self.folderCenterEnterInsetY
        )
    }

    private func canMove(_ source: StagingFileItem?, into folder: StagingFileItem) -> Bool {
        guard let source,
              folder.isDirectory,
              source.id != folder.id else { return false }

        if source.isDirectory {
            let sourcePath = source.url.standardizedFileURL.path
            let folderPath = folder.url.standardizedFileURL.path
            guard folderPath != sourcePath,
                  !folderPath.hasPrefix(sourcePath + "/") else {
                return false
            }
        }

        return true
    }

    private func handleDragEnd(file: StagingFileItem, at location: CGPoint) {
        defer { cancelDrag() }

        guard isDraggingFile, let sourceIdx = dragSourceIndex else { return }

        guard gridFrameInArea.contains(location) || airDropFrame.contains(location) else {
            return
        }

        if isAirDropTargeted {
            let url = file.url
            shareViaAirDrop([url])
            return
        }

        let finalFolderID = folderMoveTarget(at: location, candidate: folderCandidate(at: location)) ?? moveToFolderTargetID
        if let folderID = finalFolderID,
           let folder = visibleFiles.first(where: { $0.id == folderID }) {
            Task { @MainActor in
                let result = await provider.moveFile(file, toFolder: folder)
                if let message = result.errorMessage {
                    fileOperationError = message
                }
            }
            return
        }

        let finalTargetIndex = calculateDropTarget(from: location) ?? dropTargetIndex
        if let targetIdx = finalTargetIndex, targetIdx != sourceIdx {
            guard sourceIdx < visibleFiles.count,
                  visibleFiles[sourceIdx].id == file.id else { return }
            provider.reorderFiles(from: sourceIdx, to: targetIdx)
        }
    }

    private func shouldStartExternalFileDrag(at location: CGPoint) -> Bool {
        guard gridAreaSize.width > 0, gridAreaSize.height > 0 else { return false }

        let margin = Self.externalDragLaunchMargin
        let externalLaunchRect = CGRect(
            x: -margin,
            y: -Self.externalDragTopAllowance,
            width: gridAreaSize.width + margin * 2,
            height: gridAreaSize.height + Self.externalDragTopAllowance + margin
        )

        return !externalLaunchRect.contains(location)
    }

    private func cancelDrag() {
        isDraggingFile = false
        dragSourceFile = nil
        dragSourceIndex = nil
        dropTargetIndex = nil
        moveToFolderTargetID = nil
        dragLocation = .zero
        dragSourceFrame = .zero
        lastDragLocationRenderTime = 0
        isAirDropTargeted = false
        autoScrollController.stop()
    }

    private func cleanupTransientState() {
        directoryTransitionTask?.cancel()
        directoryTransitionTask = nil
        revealScheduler.cancel()
        cancelDrag()
        closePreview()
        isSearchFocused = false
    }

    // MARK: - Drag preview

    @ViewBuilder
    private var dragSourceGhostOverlay: some View {
        if isDraggingFile, let file = dragSourceFile, !dragSourceFrame.isEmpty {
            let ghostFrame = fileFrame(for: file) ?? dragSourceFrame
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.46))
                    .frame(width: Self.cellWidth, height: Self.cellHeight)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    .frame(width: Self.cellWidth, height: Self.cellHeight)

                fileCellContent(file)
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
            .animation(.easeOut(duration: 0.10), value: isDraggingFile)
            .animation(Self.dragReorderAnimation, value: ghostFrame)
        }
    }

    @ViewBuilder
    private var dragPreviewOverlay: some View {
        if isDraggingFile, let file = dragSourceFile {
            let previewX = dragLocation.x
            let previewY = dragLocation.y

            fileCellContent(file)
                .frame(width: Self.cellWidth, height: Self.cellHeight, alignment: .top)
                .position(x: previewX, y: previewY)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.10), value: isDraggingFile)
        }
    }

    private func updateAutoScrollForCurrentDrag(at location: CGPoint) {
        guard isDraggingFile,
              !externalDragController.isDragging,
              !isAirDropTargeted else {
            autoScrollController.stop()
            return
        }

        autoScrollController.updateEdgeAutoScroll(
            dragLocation: location,
            viewportHeight: gridAreaSize.height,
            slowBand: Self.autoScrollSlowBand,
            mediumBand: Self.autoScrollMediumBand,
            fastBand: Self.autoScrollFastBand,
            slowVelocity: Self.autoScrollSlowVelocity,
            mediumVelocity: Self.autoScrollMediumVelocity,
            fastVelocity: Self.autoScrollFastVelocity
        )
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

    private func selectFile(_ file: StagingFileItem) {
        clearSearchFocus()

        guard selectedFileIDs != [file.id] else { return }

        withAnimation(Self.selectionFeedbackAnimation) {
            selectedFileIDs = [file.id]
        }
    }

    private func clearSearchFocus(resetCursor: Bool = true) {
        guard isSearchFocused else { return }

        isSearchFocused = false

        DispatchQueue.main.async {
            if let textWindow = NSApp.windows.first(where: { $0.firstResponder is NSText }) {
                textWindow.makeFirstResponder(nil)
            } else {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }

            if resetCursor {
                NSCursor.arrow.set()
            }
        }
    }

    private func openFile(_ file: StagingFileItem) {
        selectFile(file)

        if file.isDirectory {
            navigateToDirectory(file.url)
            return
        }

        if file.isPreviewable {
            loadPreview(for: file)
        } else {
            NSWorkspace.shared.open(file.url)
        }
    }

    private func navigateToDirectory(_ url: URL) {
        let target = url.standardizedFileURL
        guard target != provider.currentDirectory.standardizedFileURL else { return }

        directoryTransitionTask?.cancel()
        isDirectoryTransitioning = true
        cancelDrag()

        withAnimation(.easeOut(duration: Self.directoryFadeOutDuration)) {
            directoryContentOpacity = 0
        }

        directoryTransitionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.directoryFadeOutDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            provider.goToDirectory(target)
        }
    }

    private func shareViaAirDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let airDropService = NSSharingService(named: .sendViaAirDrop) {
            airDropService.perform(withItems: urls)
        } else {
            openAirDrop()
        }
    }

    private func openAirDrop() {
        let airDropURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        if FileManager.default.fileExists(atPath: airDropURL.path) {
            NSWorkspace.shared.open(airDropURL)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }
    }

    // MARK: - Cell animation

    private func revealFilesAfterChange(from oldIDs: [StagingFileItem.ID], to newIDs: [StagingFileItem.ID]) {
        let shouldStagger = !hasAnimatedInitialLoad && oldIDs.isEmpty && !newIDs.isEmpty
        if shouldStagger {
            hasAnimatedInitialLoad = true
        }

        revealScheduler.schedule(
            ids: visibleFiles.map(\.id),
            staggered: shouldStagger,
            revealAnimation: Self.cellRevealAnimation,
            exitAnimation: Self.cellExitAnimation,
            staggerDelay: Self.revealStagger,
            maximumDelay: Self.maxRevealDelay
        )
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func fileThumbnail(_ file: StagingFileItem) -> some View {
        if let thumb = file.thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFill()
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(nsImage: file.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Self.thumbSize, height: Self.thumbSize)
        }
    }

    // MARK: - Preview overlay

    private func previewOverlay(_ file: StagingFileItem) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        closePreview()
                    }
                }

            VStack(spacing: 12) {
                HStack {
                    Text(file.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Button(action: { NSWorkspace.shared.open(file.url) }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中打开")

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            closePreview()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text(file.kind)
                    Spacer()
                    Text(file.sizeText)
                    Spacer()
                    Text(file.dateText)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(width: 420, height: 320)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            )
            .shadow(color: .black.opacity(0.5), radius: 24)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: previewFile != nil)
    }

    // MARK: - Preview loading

    private func loadPreview(for file: StagingFileItem) {
        previewTask?.cancel()
        previewFile = file
        previewImage = nil

        previewTask = Task { @MainActor in
            let image = await ThreadSafeImageCache.shared.preview(
                for: file.url,
                targetSize: NSSize(width: 388, height: 260)
            )
            guard AsyncResultIdentity.matches(
                currentID: previewFile?.id,
                requestedID: file.id,
                isCancelled: Task.isCancelled
            ) else { return }

            withAnimation(.easeOut(duration: 0.15)) {
                previewImage = image
            }
            previewTask = nil
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewFile = nil
        previewImage = nil
    }
}

private struct ExternalFileDragHost: NSViewRepresentable {
    let controller: ExternalFileDragController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        controller.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if controller.hostView !== nsView {
            controller.hostView = nsView
        }
    }
}

struct EdgeAutoScrollViewHost: NSViewRepresentable {
    let controller: EdgeAutoScrollController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            controller.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            controller.attach(to: nsView)
        }
    }
}

final class EdgeAutoScrollController: ObservableObject {
    private enum ScrollDirection {
        case up
        case down
    }

    private weak var scrollView: NSScrollView?
    private weak var hostView: NSView?
    private var timer: Timer?
    private var velocity: CGFloat = 0
    private var direction: ScrollDirection = .up
    private var lastTickTime = CACurrentMediaTime()

    var canScrollUp: Bool {
        !isAtTop
    }

    var canScrollDown: Bool {
        !isAtBottom
    }

    deinit {
        stop()
    }

    func attach(to hostView: NSView) {
        self.hostView = hostView

        if let scrollView = findScrollView(from: hostView) {
            self.scrollView = scrollView
            return
        }

        DispatchQueue.main.async { [weak self, weak hostView] in
            guard let self, let hostView else { return }
            self.scrollView = self.findScrollView(from: hostView)
        }
    }

    func updateEdgeAutoScroll(
        dragLocation: CGPoint,
        viewportHeight: CGFloat,
        slowBand: CGFloat,
        mediumBand: CGFloat,
        fastBand: CGFloat,
        slowVelocity: CGFloat,
        mediumVelocity: CGFloat,
        fastVelocity: CGFloat
    ) {
        guard viewportHeight > 0 else {
            stop()
            return
        }

        let distanceFromTop = max(0, dragLocation.y)
        let distanceFromBottom = max(0, viewportHeight - dragLocation.y)
        let edgeDistance: CGFloat

        if distanceFromTop <= slowBand, !isAtTop {
            direction = .up
            edgeDistance = distanceFromTop
        } else if distanceFromBottom <= slowBand, !isAtBottom {
            direction = .down
            edgeDistance = distanceFromBottom
        } else {
            stop()
            return
        }

        if edgeDistance <= fastBand {
            velocity = fastVelocity
        } else if edgeDistance <= mediumBand {
            velocity = mediumVelocity
        } else {
            velocity = slowVelocity
        }

        startTimerIfNeeded()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        velocity = 0
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }

        lastTickTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: DisplayRefreshTiming.frameInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        let now = CACurrentMediaTime()
        let elapsed = min(0.05, max(0, now - lastTickTime))
        lastTickTime = now

        guard velocity > 0 else {
            stop()
            return
        }

        let didScroll: Bool
        switch direction {
        case .up:
            didScroll = scrollUp(by: velocity * CGFloat(elapsed))
        case .down:
            didScroll = scrollDown(by: velocity * CGFloat(elapsed))
        }

        if !didScroll {
            stop()
        }
    }

    private var isAtTop: Bool {
        refreshScrollViewIfNeeded()

        guard let scrollView,
              let documentView = scrollView.documentView else { return true }

        let clipView = scrollView.contentView
        let maxOffsetY = max(0, documentView.bounds.height - clipView.bounds.height)

        if documentView.isFlipped {
            return clipView.bounds.origin.y <= 0.5
        }

        return clipView.bounds.origin.y >= maxOffsetY - 0.5
    }

    private var isAtBottom: Bool {
        refreshScrollViewIfNeeded()

        guard let scrollView,
              let documentView = scrollView.documentView else { return true }

        let clipView = scrollView.contentView
        let maxOffsetY = max(0, documentView.bounds.height - clipView.bounds.height)

        if documentView.isFlipped {
            return clipView.bounds.origin.y >= maxOffsetY - 0.5
        }

        return clipView.bounds.origin.y <= 0.5
    }

    @discardableResult
    private func scrollUp(by distance: CGFloat) -> Bool {
        refreshScrollViewIfNeeded()

        guard let scrollView,
              let documentView = scrollView.documentView else { return false }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let maxOffsetY = max(0, documentView.bounds.height - clipView.bounds.height)
        let nextY: CGFloat

        if documentView.isFlipped {
            guard currentOrigin.y > 0.5 else { return false }
            nextY = max(0, currentOrigin.y - distance)
        } else {
            guard currentOrigin.y < maxOffsetY - 0.5 else { return false }
            nextY = min(maxOffsetY, currentOrigin.y + distance)
        }

        guard abs(nextY - currentOrigin.y) > 0.1 else { return false }

        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    @discardableResult
    private func scrollDown(by distance: CGFloat) -> Bool {
        refreshScrollViewIfNeeded()

        guard let scrollView,
              let documentView = scrollView.documentView else { return false }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        let maxOffsetY = max(0, documentView.bounds.height - clipView.bounds.height)
        let nextY: CGFloat

        if documentView.isFlipped {
            guard currentOrigin.y < maxOffsetY - 0.5 else { return false }
            nextY = min(maxOffsetY, currentOrigin.y + distance)
        } else {
            guard currentOrigin.y > 0.5 else { return false }
            nextY = max(0, currentOrigin.y - distance)
        }

        guard abs(nextY - currentOrigin.y) > 0.1 else { return false }

        clipView.scroll(to: NSPoint(x: currentOrigin.x, y: nextY))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func refreshScrollViewIfNeeded() {
        guard scrollView == nil, let hostView else { return }
        scrollView = findScrollView(from: hostView)
    }

    private func findScrollView(from hostView: NSView) -> NSScrollView? {
        hostView.enclosingScrollView
            ?? hostView.firstAncestor(of: NSScrollView.self)
            ?? hostView.firstDescendant(of: NSScrollView.self)
    }
}

enum DisplayRefreshTiming {
    static var frameInterval: CFTimeInterval {
        1.0 / currentRefreshRate
    }

    private static var currentRefreshRate: CFTimeInterval {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        let fps = CFTimeInterval(screen?.maximumFramesPerSecond ?? 60)
        return min(240, max(30, fps > 0 ? fps : 60))
    }
}

private final class ExternalFileDragController: NSObject, ObservableObject, NSDraggingSource {
    static let internalFileDragType = NSPasteboard.PasteboardType("com.personal.dynamicnook.folder-file-url")

    weak var hostView: NSView?
    @Published private(set) var isDragging = false

    @discardableResult
    func startDragging(_ file: StagingFileItem) -> Bool {
        guard !isDragging,
              let hostView,
              let event = NSApp.currentEvent else {
            return false
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(file.url.absoluteString, forType: .fileURL)
        pasteboardItem.setString(file.url.absoluteString, forType: .URL)
        pasteboardItem.setString(file.name, forType: .string)
        pasteboardItem.setPropertyList(
            [file.url.path],
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )
        pasteboardItem.setString(file.id, forType: Self.internalFileDragType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let location = hostView.convert(event.locationInWindow, from: nil)
        let iconSize = NSSize(width: 44, height: 44)
        let frame = NSRect(
            x: location.x - iconSize.width / 2,
            y: location.y - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        draggingItem.setDraggingFrame(frame, contents: dragImage(for: file, size: iconSize))

        isDragging = true
        let session = hostView.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.draggingFormation = NSDraggingFormation.none
        session.animatesToStartingPositionsOnCancelOrFail = false
        return true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func dragImage(for file: StagingFileItem, size: NSSize) -> NSImage {
        let source = file.thumbnail ?? file.icon
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        image.unlockFocus()
        return image
    }
}

private extension NSView {
    func firstAncestor<T: NSView>(of type: T.Type) -> T? {
        var current = superview
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }

    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
