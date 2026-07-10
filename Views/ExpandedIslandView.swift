import AppKit
import Darwin
import SwiftUI

struct ExpandedIslandView: View {

    @ObservedObject var viewModel: IslandViewModel
    let isContentReady: Bool
    let contentRevealProgress: Double
    let secondaryContentRevealProgress: Double
    @ObservedObject var settings: IslandSettings
    let onOpenSettings: () -> Void
    let onOpenTodoSettings: () -> Void
    let onOpenFeedback: () -> Void

    @StateObject private var applicationsProvider = ApplicationsProvider()
    @StateObject private var fileProvider = FileDataProvider()
    @StateObject private var weatherProvider = WeatherProvider()
    @StateObject private var deviceInfoProvider = DeviceInfoProvider()
    @StateObject private var dragController = ModuleDragController()
    @StateObject private var calendarProvider = CalendarProvider()
    @StateObject private var reminderProvider = ReminderProvider()
    @State private var todoSyncTask: Task<Void, Never>?
    @State private var isScrubbingPlayback = false
    @State private var calendarWeekOffset = 0
    @State private var calendarMonthOffset = 0
    @State private var selectedCalendarDate: Date?

    // Playback + Lyrics state synced via onReceive
    @State private var currentSnapshot: PlaybackSnapshot = .idle
    @State private var playbackDiagnosticText = ""
    @State private var lyricsData: [LyricLine] = []
    @State private var lyricsCurrentIndex: Int?
    @State private var lyricsIsLoading = false
    @State private var lyricsStatusText = ""

    @State private var playbackScrubProgress = 0.0
    @State private var containerFrame: CGRect = .zero
    @State private var isSettingsMenuPresented = false
    @State private var imageCardImage: NSImage?
    @State private var imageCardImagePath = ""
    @State private var imageCardLoadTask: Task<Void, Never>?

    var body: some View {
        panelSurface
            .overlay(alignment: .topTrailing) {
                settingsActionMenu
            }
            .overlay {
                if viewModel.isFileDropChooserVisible {
                    FileDropChoiceOverlay(
                        hoverTarget: viewModel.fileDropHoverTarget,
                        previewName: viewModel.fileDropPreviewName
                    )
                    .opacity(contentRevealProgress)
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(
                width: transitionHostSize.width,
                height: transitionHostSize.height + viewModel.expandedContentOverflowHeight,
                alignment: .top
            )
            .onAppear {
                startContentProvidersIfNeeded()
                loadImageCardIfNeeded()
            }
            .onChange(of: isContentReady) { _, ready in
                if ready {
                    startContentProvidersIfNeeded()
                    loadImageCardIfNeeded()
                }
            }
            .onChange(of: viewModel.presentationPhase) { _, phase in
                if phase == .expanded || phase == .collapsed {
                    resetCalendarSelectionToToday()
                }

                if phase == .expanded {
                    startContentProvidersIfNeeded()
                    syncTodoTasksIfNeeded(force: true)
                } else if phase == .collapsed {
                    stopContentProviders()
                }
            }
            .onChange(of: settings.calendarStyle) { _, _ in
                resetCalendarSelectionToToday()
            }
            .onChange(of: settings.imageCardPath) { _, _ in
                loadImageCardIfNeeded()
            }
            .onChange(of: viewModel.fileDataRefreshToken) { _, _ in
                fileProvider.load()
            }
            .onReceive(viewModel.lyricsProvider.$lyrics) { lyrics in
                lyricsData = lyrics
            }
            .onReceive(viewModel.lyricsProvider.$currentLineIndex) { index in
                lyricsCurrentIndex = index
            }
            .onReceive(viewModel.lyricsProvider.$isLoading) { loading in
                lyricsIsLoading = loading
            }
            .onReceive(viewModel.lyricsProvider.$statusText) { text in
                lyricsStatusText = text
            }
            .onReceive(viewModel.playbackProvider.$snapshot) { snapshot in
                currentSnapshot = snapshot
            }
            .onReceive(viewModel.playbackProvider.$diagnosticText) { text in
                playbackDiagnosticText = text
            }
            .onChange(of: viewModel.presentationPhase) { _, phase in
                if phase != .expanded {
                    isSettingsMenuPresented = false
                }
            }
            .onDisappear {
                closeTodoFloatingPanel()
                stopContentProviders()
                isSettingsMenuPresented = false
                todoSyncTask?.cancel()
                todoSyncTask = nil
                imageCardLoadTask?.cancel()
                imageCardLoadTask = nil
            }
    }

    private var panelSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(topBar, progress: secondaryContentRevealProgress, offset: -2)
            if viewModel.selectedTopTab == .home {
                selectedPageContent
            } else {
                reveal(selectedPageContent, progress: contentRevealProgress, offset: -4)
            }

            Spacer(minLength: 0)
        }
        .frame(
            width: contentSize.width,
            height: contentSize.height + viewModel.expandedContentOverflowHeight,
            alignment: .topLeading
        )
        .frame(
            width: shellCanvasSize.width,
            height: shellCanvasSize.height + viewModel.expandedContentOverflowHeight,
            alignment: .top
        )
        .animation(nil, value: viewModel.selectedTopTab)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSettingsMenuPresented {
                withAnimation(.easeOut(duration: 0.12)) {
                    isSettingsMenuPresented = false
                }
            }
        }
    }

    private var selectedPageContent: some View {
        Group {
            switch viewModel.selectedTopTab {
            case .home:
                stablePage(moduleGrid, tab: .home)
            case .applications:
                stablePage(ApplicationsGridView(provider: applicationsProvider), tab: .applications)
            case .files:
                stablePage(FilesGridView(provider: fileProvider), tab: .files)
            }
        }
        .frame(
            width: transitionContentHostSize.width,
            height: transitionContentHostSize.height + viewModel.expandedContentOverflowHeight,
            alignment: .topLeading
        )
    }

    private func stablePage<Content: View>(_ content: Content, tab: IslandTopTab) -> some View {
        let size = pageContentSize(for: tab)

        return content
            .frame(
                width: size.width,
                height: size.height + viewModel.expandedContentOverflowHeight,
                alignment: .topLeading
            )
            .opacity(viewModel.selectedTopTab == tab ? 1 : 0)
            .allowsHitTesting(viewModel.selectedTopTab == tab)
            .accessibilityHidden(viewModel.selectedTopTab != tab)
    }

    private func pageContentSize(for tab: IslandTopTab) -> CGSize {
        let size = IslandShellLayout.contentSize(settings: settings, selectedTopTab: tab)
        return CGSize(
            width: size.width,
            height: max(1, size.height - IslandDesignTokens.expandedTopBarControlHeight)
        )
    }

    private var transitionHostSize: CGSize {
        IslandTopTab.allCases
            .map { IslandShellLayout.windowSize(settings: settings, selectedTopTab: $0) }
            .reduce(.zero) { current, size in
                CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
            }
    }

    private var transitionContentHostSize: CGSize {
        IslandTopTab.allCases
            .map(pageContentSize)
            .reduce(.zero) { current, size in
                CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
            }
    }

    private var shellCanvasSize: CGSize {
        viewModel.tabTransitionCanvasSize ?? contentSize
    }

    private func reveal<Content: View>(
        _ content: Content,
        progress: Double,
        offset: CGFloat
    ) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        let isClosing = viewModel.presentationPhase.isCollapsing
        let visualScale = viewModel.reduceMotionEnabled || isClosing
            ? 1
            : 0.97 + 0.03 * clampedProgress

        return content
            .opacity(clampedProgress)
            .scaleEffect(visualScale, anchor: .top)
            .blur(
                radius: viewModel.reduceMotionEnabled || isClosing
                    ? 0
                    : CGFloat(1 - clampedProgress) * 4
            )
            .offset(
                y: viewModel.reduceMotionEnabled
                    ? 0
                    : offset * CGFloat(1 - clampedProgress)
            )
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(IslandTopTab.allCases) { tab in
                    topTabButton(tab)
                }
            }
            .offset(x: 10)

            Spacer()

            settingsButton
                .offset(x: -10)
        }
        .frame(height: IslandDesignTokens.expandedTopBarControlHeight, alignment: .center)
        .padding(.top, IslandDesignTokens.expandedTopBarTopPadding)
        .padding(.horizontal, 22)
    }

    private var contentSize: CGSize {
        IslandShellLayout.contentSize(settings: settings, selectedTopTab: viewModel.selectedTopTab)
    }

    private var windowSize: CGSize {
        IslandShellLayout.windowSize(settings: settings, selectedTopTab: viewModel.selectedTopTab)
    }

    private var effectiveIslandSize: CGSize {
        IslandShellLayout.effectiveIslandSize(settings: settings)
    }

    private var effectiveIslandWidth: CGFloat {
        IslandShellLayout.effectiveIslandWidth(settings: settings)
    }

    private var effectiveIslandHeight: CGFloat {
        IslandShellLayout.effectiveIslandHeight(settings: settings)
    }

    private func topTabButton(_ tab: IslandTopTab) -> some View {
        TopTabButton(
            tab: tab,
            isSelected: viewModel.selectedTopTab == tab,
            action: { viewModel.selectTopTab(tab) }
        )
    }

    private var settingsButton: some View {
        HoverIconButton(systemName: "gearshape.fill", help: "Settings") {
            withAnimation(.easeOut(duration: 0.14)) {
                isSettingsMenuPresented.toggle()
            }
        }
    }

    @ViewBuilder
    private var settingsActionMenu: some View {
        if isSettingsMenuPresented {
            VStack(alignment: .leading, spacing: 0) {
                settingsActionButton("打开设置") {
                    closeSettingsActionMenu()
                    Task { @MainActor in
                        await Task.yield()
                        onOpenSettings()
                    }
                }

                settingsActionButton("问题反馈") {
                    closeSettingsActionMenu()
                    Task { @MainActor in
                        await Task.yield()
                        onOpenFeedback()
                    }
                }

                settingsActionButton("退出 APP") {
                    closeSettingsActionMenu()
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 6)
            .frame(width: 112, alignment: .center)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            }
            .padding(.top, IslandDesignTokens.expandedTopBarTopPadding + 32)
            .padding(.trailing, 30)
            .transition(.opacity.combined(with: .offset(y: -3)))
            .zIndex(40)
        }
    }

    private func settingsActionButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 30)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeSettingsActionMenu() {
        withAnimation(.easeOut(duration: 0.10)) {
            isSettingsMenuPresented = false
        }
    }

    private func closeTodoFloatingPanel() {
        TodoFloatingPanelPresenter.shared.close()
        handleTodoFloatingFrameChange(nil)
    }

    private func handleTodoFloatingFrameChange(_ frame: CGRect?) {
        viewModel.setExternalInteractiveFrame(frame)
    }

    private var moduleGrid: some View {
        Group {
            if visibleModules.isEmpty {
                emptyModulesView
            } else {
                weightedModuleRow
            }
        }
        .padding(.horizontal, IslandDesignTokens.expandedPadding)
        .padding(.top, 0)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var weightedModuleRow: some View {
        let modules = visibleModules

        return GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let layout = currentDragLayout(modules: modules, containerWidth: containerWidth)

            ZStack(alignment: .topLeading) {
                // Cards — rearranged positions during drag; source card hidden.
                // No .animation() modifier here — card rearrangement is animated
                // explicitly via withAnimation in ModuleDragController.updateDrag().
                ForEach(Array(modules.enumerated()), id: \.element) { idx, module in
                    let backgroundProgress = moduleBackgroundRevealProgress(
                        index: idx
                    )
                    let contentProgress = moduleContentRevealProgress(
                        index: idx,
                        count: modules.count
                    )
                    moduleCard(
                        module,
                        backgroundProgress: backgroundProgress,
                        contentProgress: contentProgress
                    )
                        .frame(width: layout.widths[idx], height: moduleCardHeight, alignment: .topLeading)
                        .offset(x: layout.offsets[idx])
                        .opacity(
                            dragController.isDragging && dragController.sourceIndex == idx
                                ? 0
                                : 1
                        )
                        .simultaneousGesture(moduleCardDragGesture(
                            cardIndex: idx,
                            cardOrigin: CGPoint(
                                x: layout.midXs[idx],
                                y: moduleCardHeight / 2
                            ),
                            layout: layout,
                            containerWidth: containerWidth
                        ))
                }

                // Drag preview — isolated from the card layout above.
                // Uses .id() for stable identity so SwiftUI never re-creates it mid-drag.
                // Position is always computed from the raw cursor, never from layout offsets.
                dragPreview(modules: modules, containerWidth: containerWidth)
            }
            .frame(width: containerWidth, height: moduleCardHeight, alignment: .topLeading)
            .background {
                GeometryReader { containerGeo in
                    Color.clear
                        .onAppear {
                            containerFrame = containerGeo.frame(in: .named("moduleRow"))
                        }
                        .onChange(of: containerGeo.frame(in: .named("moduleRow"))) { _, newFrame in
                            containerFrame = newFrame
                        }
                }
            }
        }
        .frame(height: moduleCardHeight)
        .coordinateSpace(name: "moduleRow")
        .onChange(of: visibleModules) { _, _ in
            if dragController.isActive { dragController.reset() }
        }
    }

    private func moduleBackgroundRevealProgress(index: Int) -> Double {
        moduleRevealProgress(index: index, phaseDelay: 0)
    }

    private func moduleContentRevealProgress(index: Int, count: Int) -> Double {
        guard count > 1 else {
            return moduleRevealProgress(index: index, phaseDelay: 0.08)
        }

        return moduleRevealProgress(index: index, phaseDelay: 0.08)
    }

    private func moduleRevealProgress(index: Int, phaseDelay: TimeInterval) -> Double {
        guard isContentReady else { return 0 }

        let revealDuration = max(IslandDesignTokens.primaryContentRevealDuration, 0.01)
        let itemDelay = min(Double(index) * 0.03, 0.18)
        let animationDuration = 0.22
        let start = min((itemDelay + phaseDelay) / revealDuration, 0.92)
        let activeDuration = max(0.01, min(animationDuration / revealDuration, 1 - start))
        return min(max((contentRevealProgress - start) / activeDuration, 0), 1)
    }

    private func startContentProvidersIfNeeded() {
        guard isContentReady else { return }
        weatherProvider.start()
        deviceInfoProvider.start()
        calendarProvider.start()
        reminderProvider.start()
        syncTodoTasksIfNeeded()
    }

    private func stopContentProviders() {
        weatherProvider.stop()
        deviceInfoProvider.stop()
        calendarProvider.stop()
        reminderProvider.stop()
        todoSyncTask?.cancel()
        todoSyncTask = nil
    }

    private func syncTodoTasksIfNeeded(force: Bool = false) {
        guard force || viewModel.todoTasks.isEmpty else { return }
        guard todoSyncTask == nil else { return }

        todoSyncTask = Task { @MainActor in
            let tasks = await reminderProvider.loadTodoTasksForSync(includeCompleted: true)
            if !Task.isCancelled {
                viewModel.setTodoTasks(tasks)
            }
            todoSyncTask = nil
        }
    }

    /// The floating preview card that follows the cursor during drag.
    /// Extracted into its own builder to isolate it from the card layout's animation scope.
    @ViewBuilder
    private func dragPreview(modules: [IslandPanelModule], containerWidth: CGFloat) -> some View {
        if dragController.isDragging,
           let srcIdx = dragController.sourceIndex,
           modules.indices.contains(srcIdx) {

            let w = dragController.sourceWidth
            let dropping = dragController.isDropping
            let dropOffset = dragController.dropTargetOffset
            let cursor = dragController.cursorPosition
            let previewX = dropping
                ? dropOffset + w / 2
                : min(max(cursor.x, w / 2), containerWidth - w / 2)

            moduleCard(modules[srcIdx])
                .frame(width: w, height: moduleCardHeight, alignment: .topLeading)
                .scaleEffect(1.04)
                .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                .position(x: previewX, y: moduleCardHeight / 2)
                .allowsHitTesting(false)
                .zIndex(1)
                .id("drag-preview-\(srcIdx)")
                .animation(nil, value: dragController.targetIndex)
                .animation(nil, value: dragController.dragOffset)
        }
    }

    // MARK: - Module Layout

    private struct ModuleLayout {
        let offsets: [CGFloat]
        let widths: [CGFloat]
        let midXs: [CGFloat]
    }

    private var moduleCardLayoutSpacing: CGFloat {
        IslandShellLayout.moduleCardLayoutSpacing
    }

    private func computeModuleLayout(
        modules: [IslandPanelModule],
        containerWidth: CGFloat
    ) -> ModuleLayout {
        let spacing = moduleCardLayoutSpacing
        let totalSpacing = spacing * CGFloat(max(0, modules.count - 1))
        let availableWidth = max(1, containerWidth - totalSpacing)
        let totalWeight = modules.reduce(CGFloat(0)) { $0 + moduleWidthWeight($1) }

        var offsets: [CGFloat] = []
        var widths: [CGFloat] = []
        var midXs: [CGFloat] = []
        var x: CGFloat = 0

        for module in modules {
            let w = availableWidth * moduleWidthWeight(module) / max(totalWeight, 1)
            offsets.append(x)
            widths.append(w)
            midXs.append(x + w / 2)
            x += w + spacing
        }

        return ModuleLayout(offsets: offsets, widths: widths, midXs: midXs)
    }

    /// Returns the layout to use: rearranged during drag, normal otherwise.
    private func currentDragLayout(
        modules: [IslandPanelModule],
        containerWidth: CGFloat
    ) -> ModuleLayout {
        guard dragController.isActive else {
            return computeModuleLayout(modules: modules, containerWidth: containerWidth)
        }

        let spacing = moduleCardLayoutSpacing
        let totalSpacing = spacing * CGFloat(max(0, modules.count - 1))
        let availableWidth = max(1, containerWidth - totalSpacing)
        let totalWeight = modules.reduce(CGFloat(0)) { $0 + moduleWidthWeight($1) }

        let result = dragController.rearrangedLayout(
            modules: modules,
            containerWidth: containerWidth,
            spacing: spacing
        ) { module in
            availableWidth * moduleWidthWeight(module) / max(totalWeight, 1)
        }

        var midXs: [CGFloat] = []
        for i in modules.indices {
            midXs.append(result.offsets[i] + result.widths[i] / 2)
        }

        return ModuleLayout(offsets: result.offsets, widths: result.widths, midXs: midXs)
    }

    // MARK: - Module Drag Gesture

    private func moduleCardDragGesture(
        cardIndex: Int,
        cardOrigin: CGPoint,
        layout: ModuleLayout,
        containerWidth: CGFloat
    ) -> some Gesture {
        LongPressGesture(minimumDuration: ModuleDragController.longPressDuration)
            .sequenced(before: DragGesture(minimumDistance: ModuleDragController.dragMinDistance))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    guard let drag else { return }
                    if !dragController.isActive {
                        dragController.startDrag(
                            sourceIndex: cardIndex,
                            sourceOrigin: cardOrigin,
                            midXs: layout.midXs,
                            widths: layout.widths
                        )
                    } else {
                        let translation = CGSize(
                            width: drag.translation.width,
                            height: drag.translation.height
                        )
                        dragController.updateDrag(translation: translation)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                handleModuleDrop(modules: visibleModules)
            }
    }

    private func handleModuleDrop(modules: [IslandPanelModule]) {
        // Compute the final layout to determine where the preview should snap
        let spacing: CGFloat = 6
        let containerWidth = containerFrame.width > 0 ? containerFrame.width : 900
        let totalSpacing = spacing * CGFloat(max(0, modules.count - 1))
        let availableWidth = max(1, containerWidth - totalSpacing)
        let totalWeight = modules.reduce(CGFloat(0)) { $0 + moduleWidthWeight($1) }

        let finalLayout = dragController.rearrangedLayout(
            modules: modules,
            containerWidth: containerWidth,
            spacing: spacing
        ) { module in
            availableWidth * moduleWidthWeight(module) / max(totalWeight, 1)
        }

        // Determine the snap target x-offset (top-leading)
        let snapTargetX: CGFloat
        if let srcIdx = dragController.sourceIndex {
            snapTargetX = finalLayout.offsets[srcIdx]
        } else {
            snapTargetX = 0
        }

        // Animate preview to the target slot
        withAnimation(ModuleDragController.dropAnimation) {
            dragController.beginDropAnimation(targetOffset: snapTargetX)
        }

        // Commit the reorder if a real move happened
        if let reordered = dragController.commitDrop(modules) {
            settings.moduleOrder = reordered.map(\.rawValue)
        }

        // Reset after the snap animation completes
        let controller = dragController
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            controller.reset()
        }
    }

    private func moduleWidthWeight(_ module: IslandPanelModule) -> CGFloat {
        IslandShellLayout.moduleWidthWeight(
            module,
            referenceHeight: IslandShellLayout.moduleLayoutReferenceHeight(settings: settings)
        )
    }

    private var visibleModules: [IslandPanelModule] {
        IslandShellLayout.visibleModules(settings: settings)
    }

    private var moduleCardHeight: CGFloat {
        max(104, effectiveIslandHeight - 38)
    }

    private var isTallModuleCard: Bool {
        moduleCardHeight >= 150
    }

    private var isVeryTallModuleCard: Bool {
        moduleCardHeight >= 210
    }

    private var moduleFooterFont: Font {
        .system(size: 9, weight: .semibold, design: .rounded)
    }

    private var emptyModulesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No modules enabled")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.primaryText)

            Text("Open Settings to choose what appears here.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(IslandDesignTokens.secondaryText)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: moduleCardHeight, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                .fill(IslandDesignTokens.moduleSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.largeCard, style: .continuous)
                        .stroke(IslandDesignTokens.moduleBorder, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func moduleCard(
        _ module: IslandPanelModule,
        backgroundProgress: Double = 1,
        contentProgress: Double = 1
    ) -> some View {
        let cornerRadius = module == .todo ? TodoScheduleCardMetrics.cornerRadius : AppRadius.largeCard
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let backgroundProgress = min(max(backgroundProgress, 0), 1)
        let contentProgress = min(max(contentProgress, 0), 1)

        ZStack(alignment: .topLeading) {
            moduleCardBackground(module)
                .opacity(backgroundProgress)
                .blur(radius: CGFloat(1 - backgroundProgress) * 2)

            VStack(alignment: .leading, spacing: moduleCardSpacing(for: module)) {
                if shouldShowModuleHeader(for: module) {
                    moduleHeader(module)
                }

                switch module {
                case .weather:
                    weatherModuleContent
                case .calendar:
                    calendarModuleContent
                case .todo:
                    todoModuleContent
                case .media:
                    mediaModuleContent
                case .quickApps:
                    quickAppsModuleContent
                case .shortcuts:
                    shortcutsModuleContent
                case .imageCard:
                    imageCardModuleContent
                case .deviceInfo:
                    deviceInfoModuleContent
                }
            }
            .padding(.horizontal, moduleCardHorizontalPadding(for: module))
            .padding(.vertical, moduleCardVerticalPadding(for: module))
            .frame(
                maxWidth: .infinity,
                minHeight: moduleCardHeight,
                maxHeight: moduleCardHeight,
                alignment: .topLeading
            )
            .opacity(contentProgress)
            .blur(radius: CGFloat(1 - contentProgress) * 1.5)
            .offset(y: CGFloat(1 - contentProgress) * 2)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: moduleCardHeight,
            maxHeight: moduleCardHeight,
            alignment: .topLeading
        )
        .scaleEffect(0.985 + CGFloat(backgroundProgress) * 0.015, anchor: .center)
        .offset(y: CGFloat(1 - backgroundProgress) * 5)
        .overlay {
            if module == .weather {
                weatherCardBorder(shape)
            } else if module == .todo {
                todoScheduleCardBorder(shape)
            } else {
                shape
                    .stroke(IslandDesignTokens.moduleBorder, lineWidth: 1)
            }
        }
        .moduleCardClip(shape, isEnabled: true)
    }

    private func weatherCardBorder(_ shape: RoundedRectangle) -> some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.34),
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.85
            )
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.65), lineWidth: 2)
                    .blendMode(.overlay)
            }
    }

    private func todoScheduleCardBorder(_ shape: RoundedRectangle) -> some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Color.white.opacity(0.055),
                        Color.white.opacity(0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.9
            )
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.52), lineWidth: 2)
                    .blendMode(.overlay)
            }
    }

    private func shouldShowModuleHeader(for module: IslandPanelModule) -> Bool {
        if module == .weather || module == .todo {
            return false
        }

        return module != .media
            && module != .calendar
            && module != .quickApps
            && module != .imageCard
            && module != .deviceInfo
    }

    private var shortcutsModuleContent: some View {
        ShortcutsCardView()
    }

    @ViewBuilder
    private var imageCardModuleContent: some View {
        GeometryReader { proxy in
            let rotationDegrees: CGFloat = 12
            let rotationRadians = rotationDegrees * .pi / 180
            let rotationSine = sin(rotationRadians)
            let rotationCosine = cos(rotationRadians)
            let visualWidthRatio = 1 + rotationSine
            let visualHeightRatio = rotationSine + rotationCosine
            let cardSide = min(
                proxy.size.width * 0.96 / visualWidthRatio,
                proxy.size.height * 0.88 / visualHeightRatio
            ) + 2
            let visualWidth = cardSide * visualWidthRatio
            let visualHeight = cardSide * visualHeightRatio
            let visualOffsetX = cardSide * rotationSine
            let visualOffsetY = cardSide * (visualHeightRatio - 1)
            let cornerRadius = min(28, cardSide * 0.18)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.20, blue: 0.20))
                        .frame(width: cardSide, height: cardSide)

                    if let image = imageCardImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardSide, height: cardSide)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .rotationEffect(.degrees(-rotationDegrees), anchor: .bottomLeading)
                            .shadow(color: .black.opacity(0.34), radius: 10, x: 4, y: 7)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: cardSide, height: cardSide)
                            .overlay {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.48))
                            }
                            .rotationEffect(.degrees(-rotationDegrees), anchor: .bottomLeading)
                            .shadow(color: .black.opacity(0.26), radius: 9, x: 5, y: 7)
                    }
                }
                .offset(x: visualOffsetX, y: visualOffsetY)
            }
            .frame(width: visualWidth, height: visualHeight, alignment: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .offset(x: -2, y: 2)
        }
    }

    private func loadImageCardIfNeeded() {
        guard isContentReady else { return }

        let path = settings.imageCardPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            imageCardLoadTask?.cancel()
            imageCardLoadTask = nil
            imageCardImagePath = ""
            imageCardImage = nil
            return
        }

        guard path != imageCardImagePath || imageCardImage == nil else { return }

        imageCardLoadTask?.cancel()
        imageCardImagePath = path
        imageCardImage = nil
        let url = URL(fileURLWithPath: path)

        imageCardLoadTask = Task { @MainActor in
            let exists = await Task.detached(priority: .utility) {
                FileManager.default.fileExists(atPath: path)
            }.value
            guard exists, !Task.isCancelled else {
                if imageCardImagePath == path {
                    imageCardImage = nil
                    imageCardLoadTask = nil
                }
                return
            }

            let image = await ThreadSafeImageCache.shared.preview(
                for: url,
                targetSize: NSSize(width: 320, height: 320)
            )
            guard !Task.isCancelled,
                  imageCardImagePath == path,
                  settings.imageCardPath.trimmingCharacters(in: .whitespacesAndNewlines) == path else {
                return
            }

            imageCardImage = image
            imageCardLoadTask = nil
        }
    }

    private var deviceInfoModuleContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                deviceMetricColumn(
                    value: "\(deviceInfoProvider.snapshot.cpuPercent)%",
                    label: "CPU",
                    systemName: "waveform.path.ecg"
                )
                deviceMetricColumn(
                    value: "\(deviceInfoProvider.snapshot.memoryPercent)%",
                    label: "RAM",
                    systemName: "chart.bar.fill"
                )
                deviceMetricColumn(
                    value: "\(deviceInfoProvider.snapshot.diskPercent)%",
                    label: "DISK",
                    systemName: "internaldrive"
                )
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                FinderGlyph()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(deviceInfoProvider.snapshot.usedDiskText) / \(deviceInfoProvider.snapshot.totalDiskText)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("macOS 存储空间")
                        .font(.system(size: 8.6, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .lineLimit(1)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            Capsule()
                                .fill(AppColor.accent)
                                .frame(
                                    width: max(
                                        3,
                                        proxy.size.width
                                            * CGFloat(min(max(deviceInfoProvider.snapshot.diskPercent, 0), 100))
                                            / 100
                                    )
                                )
                        }
                    }
                    .frame(height: 3)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deviceMetricColumn(value: String, label: String, systemName: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.accent)

            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 8.2, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func moduleCardBackground(_ module: IslandPanelModule) -> some View {
        let cornerRadius: CGFloat = 16
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if module == .imageCard || module == .deviceInfo {
            Color.clear
        } else if module == .weather {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.055, green: 0.057, blue: 0.064).opacity(0.96),
                            Color.black.opacity(0.94),
                            Color(red: 0.020, green: 0.023, blue: 0.029).opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.025),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 170
                            )
                        )
                }
                .overlay(alignment: .bottomLeading) {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.66, blue: 1.0).opacity(0.11),
                                    Color.clear
                                ],
                                center: .bottomLeading,
                                startRadius: 0,
                                endRadius: 130
                            )
                        )
                }
                .overlay(alignment: .trailing) {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.55, blue: 0.12).opacity(0.08),
                                    Color.clear
                                ],
                                center: .trailing,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                }
        } else if module == .todo {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.036, blue: 0.040).opacity(0.96),
                            Color.black.opacity(0.92),
                            Color(red: 0.015, green: 0.016, blue: 0.019).opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.025),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 190
                            )
                        )
                }
                .overlay(alignment: .bottomTrailing) {
                    shape
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.10),
                                    Color.clear
                                ],
                                center: .bottomTrailing,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                }
        } else {
            shape
                .fill(Color.black.opacity(0.72))
        }
    }

    private func moduleCardSpacing(for module: IslandPanelModule) -> CGFloat {
        if module == .media {
            return 4
        }

        if module == .calendar {
            return 2
        }

        if module == .todo {
            return 0
        }

        return 5
    }

    private func moduleCardHorizontalPadding(for module: IslandPanelModule) -> CGFloat {
        if module == .weather {
            return 12
        }

        if module == .todo {
            return TodoScheduleCardMetrics.horizontalPadding
        }

        if module == .media {
            return 3
        }

        if module == .shortcuts {
            return 10
        }

        if module == .quickApps {
            return 12
        }

        if module == .imageCard {
            return 0
        }

        if module == .deviceInfo {
            return 0
        }

        guard module == .calendar else {
            return 14
        }

        return 5
    }

    private func moduleCardVerticalPadding(for module: IslandPanelModule) -> CGFloat {
        if module == .media {
            return 5
        }

        if module == .weather {
            return 12
        }

        if module == .todo {
            return TodoScheduleCardMetrics.verticalPadding
        }

        if module == .quickApps {
            return 8
        }

        if module == .imageCard || module == .deviceInfo {
            return 0
        }

        if module == .calendar {
            return 6
        }

        return 8
    }

    private func moduleHeader(_ module: IslandPanelModule) -> some View {
        HStack(spacing: 7) {
            Image(systemName: module.systemName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(IslandDesignTokens.iconColor)
                .frame(width: 14)

            Text(module.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.secondaryText)

            Spacer(minLength: 0)

            if module == .todo {
                todoAddButton
            }
        }
    }

    private var todoAddButton: some View {
        Button(action: presentNewReminderDialog) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .frame(width: 20, height: 20)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.075))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .help("新增待办")
    }

    private func presentNewReminderDialog() {
        NewReminderPanelPresenter.shared.present(
            islandHeight: windowSize.height,
            onAdd: { [reminderProvider] request in
                reminderProvider.addReminder(request: request)
            }
        )
    }

    private func createTodoFromCard(_ draft: TodoCardCreateDraft) {
        Task { @MainActor in
            _ = await reminderProvider.createTodoReminder(request: draft.reminderCreationRequest)
            let tasks = await reminderProvider.loadTodoTasksForSync(includeCompleted: true)
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.setTodoTasks(tasks)
            }
        }
    }

    private func completeTodoFromCard(_ item: TodoSchedulePreviewItem) {
        guard let identifier = item.reminderIdentifier else { return }

        Task { @MainActor in
            guard await reminderProvider.completeTodoReminder(identifier: identifier) else { return }
            let tasks = await reminderProvider.loadTodoTasksForSync(includeCompleted: true)
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.setTodoTasks(tasks)
            }
        }
    }

    private func restoreTodoFromCard(_ item: TodoSchedulePreviewItem) {
        guard let identifier = item.reminderIdentifier else { return }

        Task { @MainActor in
            guard await reminderProvider.restoreTodoReminder(identifier: identifier) else { return }
            let tasks = await reminderProvider.loadTodoTasksForSync(includeCompleted: true)
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.setTodoTasks(tasks)
            }
        }
    }

    private func deleteTodoFromCard(_ item: TodoSchedulePreviewItem) {
        guard let identifier = item.reminderIdentifier else { return }

        Task { @MainActor in
            guard await reminderProvider.deleteTodoReminder(identifier: identifier) else { return }
            let tasks = await reminderProvider.loadTodoTasksForSync(includeCompleted: true)
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.setTodoTasks(tasks)
            }
        }
    }

    private var quickAppsModuleContent: some View {
        QuickAppsCardView()
    }

    private var weatherModuleContent: some View {
        let weather = weatherProvider.snapshot

        return WeatherCardView(
            weather: weather,
            apparentTemperature: apparentTemperatureValue(for: weather),
            humidity: humidityValue(for: weather)
        )
        .help(weather.detail)
    }

    private func compactWeatherModuleContent(_ weather: WeatherSnapshot) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isCompact = size.width < 176 || size.height < 122
            let temperatureSize = min(
                isCompact ? 43 : 49,
                max(36, size.height * 0.43)
            )
            let symbolSize = min(
                size.width * (isCompact ? 0.44 : 0.50),
                size.height * (isCompact ? 0.54 : 0.62)
            )
            let symbolCenterX = size.width - symbolSize * 0.46
            let symbolCenterY = size.height * (isCompact ? 0.38 : 0.40)
            let textColumnWidth = max(82, size.width * 0.58)
            let conditionWidth = min(54, max(34, size.width * 0.17))
            let conditionCenterX = min(
                symbolCenterX - symbolSize * 0.62,
                size.width * (isCompact ? 0.52 : 0.50)
            )
            let conditionCenterY = symbolCenterY + symbolSize * 0.03

            ZStack(alignment: .topLeading) {
                weatherPremiumSymbol(weather, size: symbolSize)
                    .frame(width: symbolSize, height: symbolSize)
                    .position(x: symbolCenterX, y: symbolCenterY)

                weatherConditionLabel(weather.condition, isCompact: isCompact)
                    .frame(width: conditionWidth, alignment: .center)
                    .position(x: conditionCenterX, y: conditionCenterY)

                VStack(alignment: .leading, spacing: 0) {
                    weatherPremiumLocation(weather)
                        .frame(width: textColumnWidth, alignment: .leading)

                    Spacer(minLength: isCompact ? 6 : 8)

                    Text(weather.temperatureText)
                        .font(.system(size: temperatureSize, weight: .thin, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.98))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .shadow(color: .white.opacity(0.10), radius: 8)
                        .frame(width: size.width * 0.46, alignment: .leading)

                    Spacer(minLength: isCompact ? 7 : 9)

                    weatherPremiumMetrics(weather, isCompact: isCompact, availableWidth: size.width)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weatherPremiumLocation(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "location.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.62))

            Text(weather.locationName)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func weatherConditionLabel(_ condition: String, isCompact: Bool) -> some View {
        Text(condition)
            .font(.system(size: isCompact ? 12 : 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
    }

    private func weatherPremiumSymbol(_ weather: WeatherSnapshot, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(weatherGlowColor(for: weather).opacity(weather.isLive ? 0.24 : 0.10))
                .frame(width: size * 0.82, height: size * 0.82)
                .blur(radius: size * 0.22)

            Image(systemName: weather.symbolName)
                .font(.system(size: size * 0.78, weight: .semibold))
                .symbolRenderingMode(weather.isLive ? .multicolor : .hierarchical)
                .foregroundStyle(Color.white.opacity(weather.isLive ? 1 : 0.58))
                .shadow(
                    color: weatherGlowColor(for: weather).opacity(weather.isLive ? 0.30 : 0.08),
                    radius: size * 0.18,
                    y: size * 0.04
                )
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.18), value: weather.symbolName)
        }
        .drawingGroup()
    }

    private func weatherPremiumMetrics(
        _ weather: WeatherSnapshot,
        isCompact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        let spacing: CGFloat = isCompact ? 6 : 10
        let itemWidth = max(1, (availableWidth - spacing) / 2)

        return HStack(spacing: spacing) {
            weatherPremiumMetric(
                systemName: "thermometer.medium",
                label: "体感",
                value: apparentTemperatureValue(for: weather),
                isCompact: isCompact
            )
            .frame(width: itemWidth, alignment: .leading)

            weatherPremiumMetric(
                systemName: "drop",
                label: "湿度",
                value: humidityValue(for: weather),
                isCompact: isCompact
            )
            .frame(width: itemWidth, alignment: .leading)
        }
        .frame(width: availableWidth, alignment: .leading)
    }

    private func weatherPremiumMetric(
        systemName: String,
        label: String,
        value: String,
        isCompact: Bool
    ) -> some View {
        HStack(spacing: isCompact ? 4 : 6) {
            Image(systemName: systemName)
                .font(.system(size: isCompact ? 9.8 : 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.84))
                .frame(width: isCompact ? 22 : 24, height: isCompact ? 22 : 24)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.075))
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                        }
                }

            weatherPremiumMetricText(label: label, value: value, isCompact: isCompact)
            .lineLimit(1)
            .minimumScaleFactor(isCompact ? 0.58 : 0.64)
            .allowsTightening(true)
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weatherPremiumMetricText(
        label: String,
        value: String,
        isCompact: Bool
    ) -> Text {
        var labelPart = AttributedString(label + " ")
        labelPart.font = .system(size: isCompact ? 8.7 : 9.5, weight: .medium, design: .rounded)
        labelPart.foregroundColor = Color.white.opacity(0.54)

        var valuePart = AttributedString(value)
        valuePart.font = .system(size: isCompact ? 11.8 : 13.2, weight: .medium, design: .rounded)
        valuePart.foregroundColor = Color.white.opacity(0.82)

        labelPart.append(valuePart)
        return Text(labelPart).monospacedDigit()
    }

    private func weatherGlowColor(for weather: WeatherSnapshot) -> Color {
        let symbol = weather.symbolName
        if symbol.contains("sun") {
            return Color(red: 1.0, green: 0.68, blue: 0.20)
        }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("sleet") {
            return Color(red: 0.38, green: 0.62, blue: 1.0)
        }
        if symbol.contains("snow") {
            return Color(red: 0.72, green: 0.90, blue: 1.0)
        }
        if symbol.contains("bolt") {
            return Color(red: 0.98, green: 0.72, blue: 0.25)
        }
        return Color.white
    }

    private func weatherCompactHeader(_ weather: WeatherSnapshot) -> some View {
        Text(weather.locationName)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.90))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.trailing, 28)
    }

    @ViewBuilder
    private func weatherCompactStatusIcon(_ weather: WeatherSnapshot) -> some View {
        Image(systemName: weather.symbolName)
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(weatherAccentColor.opacity(weather.isLive ? 1 : 0.62))
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeOut(duration: 0.18), value: weather.symbolName)
    }

    private func weatherCompactCurrent(_ weather: WeatherSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(weather.temperatureText)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.98))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(weather.condition)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.70))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func weatherCompactForecasts(_ weather: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(compactWeatherForecasts(for: weather)) { forecast in
                weatherMiniForecastColumn(forecast)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func weatherCompactMetrics(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            weatherMetricItem(
                systemName: "thermometer.medium",
                text: apparentTemperatureText(for: weather)
            )

            Spacer(minLength: 8)

            weatherMetricItem(
                systemName: "drop",
                text: humidityText(for: weather)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func weatherReferenceLayout(_ weather: WeatherSnapshot, designSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: designSize.width - 24, height: 1)
                .position(x: designSize.width / 2, y: 66)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: designSize.width - 24, height: 1)
                .position(x: designSize.width / 2, y: 136)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 49)
                .position(x: designSize.width / 3, y: 103)

            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(width: 1, height: 49)
                .position(x: designSize.width * 2 / 3, y: 103)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(weather.locationName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: weather.symbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            weatherAccentColor.opacity(weather.isLive ? 1 : 0.62)
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeOut(duration: 0.18), value: weather.symbolName)
                }
                .frame(width: designSize.width - 30)

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(weather.temperatureText)
                        .font(.system(size: 48, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.98))
                        .lineLimit(1)

                    Text(weather.condition)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                }
            }
            .frame(width: designSize.width - 30, height: 62, alignment: .topLeading)
            .position(x: designSize.width / 2, y: 35)

            HStack(alignment: .center, spacing: 0) {
                ForEach(compactWeatherForecasts(for: weather)) { forecast in
                    weatherReferenceForecastColumn(forecast)
                        .frame(width: designSize.width / 3)
                }
            }
            .frame(width: designSize.width, height: 62)
            .position(x: designSize.width / 2, y: 101)

            HStack(spacing: 22) {
                weatherReferenceMetricItem(
                    systemName: "thermometer.medium",
                    text: apparentTemperatureText(for: weather)
                )

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 14)

                weatherReferenceMetricItem(
                    systemName: "drop",
                    text: humidityText(for: weather)
                )
            }
            .frame(width: designSize.width - 20, height: 22)
            .position(x: designSize.width / 2, y: 154)
        }
        .clipped()
    }

    private func compactWeatherForecasts(for weather: WeatherSnapshot) -> [WeatherDailySummary] {
        if !weather.dailyForecasts.isEmpty {
            return Array(weather.dailyForecasts.prefix(3))
        }

        let fallbackRange: String
        if let temperature = weather.temperature {
            let rounded = Int(temperature.rounded())
            fallbackRange = "\(rounded - 2)/\(rounded + 2)°"
        } else {
            fallbackRange = "--/--°"
        }

        return [
            WeatherDailySummary(id: "today", title: "今天", symbolName: weather.symbolName, temperatureRangeText: fallbackRange),
            WeatherDailySummary(id: "tomorrow", title: "明天", symbolName: weather.symbolName, temperatureRangeText: fallbackRange),
            WeatherDailySummary(id: "weekend", title: "周六", symbolName: weather.symbolName, temperatureRangeText: fallbackRange)
        ]
    }

    private func compactWeatherForecastColumn(_ forecast: WeatherDailySummary) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(forecast.title)
                .font(.system(size: weatherForecastTitleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)

            Image(systemName: forecast.symbolName)
                .font(.system(size: weatherForecastIconSize, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .frame(height: weatherForecastIconSize + 1, alignment: .center)

            weatherForecastTemperatureText(forecast.temperatureRangeText)
        }
        .frame(height: weatherForecastColumnHeight)
    }

    private func weatherMiniForecastColumn(_ forecast: WeatherDailySummary) -> some View {
        VStack(alignment: .center, spacing: 1.5) {
            Text(forecast.title)
                .font(.system(size: 9.7, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 17.5, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .frame(height: 18, alignment: .center)

            weatherMiniForecastTemperatureText(forecast.temperatureRangeText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func weatherMiniForecastTemperatureText(_ range: String) -> some View {
        let parts = weatherTemperatureRangeParts(range)

        return (Text(parts.low.replacingOccurrences(of: "°", with: ""))
            .foregroundColor(Color.white.opacity(0.86))
            + Text(" / ").foregroundColor(Color.white.opacity(0.42))
            + Text(parts.high).foregroundColor(weatherAccentColor))
        .font(.system(size: 10.6, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .allowsTightening(true)
    }

    private func weatherReferenceForecastColumn(_ forecast: WeatherDailySummary) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Text(forecast.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .frame(height: 23)

            weatherReferenceForecastTemperatureText(forecast.temperatureRangeText)
        }
    }

    private func weatherReferenceForecastTemperatureText(_ range: String) -> some View {
        let parts = weatherTemperatureRangeParts(range)

        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.low)
                .foregroundStyle(Color.white.opacity(0.86))

            Text("/")
                .foregroundStyle(Color.white.opacity(0.45))

            Text(parts.high)
                .foregroundStyle(weatherAccentColor)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }

    private func weatherReferenceMetricItem(systemName: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(weatherAccentColor)

            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
        }
    }

    private var weatherAccentColor: Color {
        Color(red: 1.0, green: 0.45, blue: 0.41)
    }

    private var weatherLocationFontSize: CGFloat {
        moduleCardHeight < 112 ? 10 : 10.5
    }

    private var weatherTemperatureFontSize: CGFloat {
        moduleCardHeight < 112 ? 25 : 27
    }

    private var weatherConditionFontSize: CGFloat {
        moduleCardHeight < 112 ? 11 : 12
    }

    private var weatherHeaderIconSize: CGFloat {
        moduleCardHeight < 112 ? 15 : 16
    }

    private var weatherForecastTitleFontSize: CGFloat {
        moduleCardHeight < 112 ? 8.5 : 9
    }

    private var weatherForecastIconSize: CGFloat {
        moduleCardHeight < 112 ? 14 : 16
    }

    private var weatherForecastTemperatureFontSize: CGFloat {
        moduleCardHeight < 112 ? 8.5 : 9
    }

    private var weatherForecastColumnHeight: CGFloat {
        moduleCardHeight < 112 ? 35 : 39
    }

    private var weatherForecastSpacing: CGFloat {
        moduleCardHeight < 112 ? 5 : 7
    }

    private var weatherCardSpacing: CGFloat {
        moduleCardHeight < 112 ? 2 : 3
    }

    private var weatherMetricRowHeight: CGFloat {
        moduleCardHeight < 112 ? 12 : 13
    }

    private var weatherMetricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.13))
            .frame(width: 1, height: 10)
    }

    private var weatherDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.095))
            .frame(height: 1)
    }

    private func weatherMetricItem(systemName: String, text: String) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: systemName)
                .font(.system(size: 10.2, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(weatherAccentColor)

            Text(text)
                .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func weatherForecastTemperatureText(_ range: String) -> some View {
        let parts = weatherTemperatureRangeParts(range)

        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.low)
                .foregroundStyle(Color.white.opacity(0.88))

            Text("/")
                .foregroundStyle(Color.white.opacity(0.45))

            Text(parts.high)
                .foregroundStyle(weatherAccentColor)
        }
        .font(.system(size: weatherForecastTemperatureFontSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func weatherTemperatureRangeParts(_ range: String) -> (low: String, high: String) {
        let normalized = range.replacingOccurrences(of: "°", with: "")
        let parts = normalized.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return (range, "--°")
        }

        return ("\(parts[0])°", "\(parts[1])°")
    }

    private func apparentTemperatureText(for weather: WeatherSnapshot) -> String {
        guard let apparentTemperature = weather.apparentTemperature else {
            return "体感 --°"
        }

        return "体感 \(Int(apparentTemperature.rounded()))°"
    }

    private func apparentTemperatureValue(for weather: WeatherSnapshot) -> String {
        guard let apparentTemperature = weather.apparentTemperature else {
            return "--°"
        }

        return "\(Int(apparentTemperature.rounded()))°"
    }

    private func humidityText(for weather: WeatherSnapshot) -> String {
        guard let humidity = weather.humidity else {
            return "湿度 --%"
        }

        return "湿度 \(humidity)%"
    }

    private func humidityValue(for weather: WeatherSnapshot) -> String {
        guard let humidity = weather.humidity else {
            return "--%"
        }

        return "\(humidity)%"
    }

    private func wideWeatherModuleContent(_ weather: WeatherSnapshot) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(weather.locationName)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weather.temperatureText)
                        .font(.system(size: 42, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.97))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(weather.condition)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                HStack(spacing: 7) {
                    Text(primaryForecastRange(for: weather))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)

                    Text(weather.isLive ? "空气优" : "更新中")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background {
                            Capsule()
                                .fill(Color.black.opacity(0.18))
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 9) {
                ForEach(compactWeatherForecasts(for: weather)) { forecast in
                    wideWeatherForecastColumn(forecast)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func primaryForecastRange(for weather: WeatherSnapshot) -> String {
        compactWeatherForecasts(for: weather).first?.temperatureRangeText ?? "--/--°"
    }

    private func wideWeatherForecastColumn(_ forecast: WeatherDailySummary) -> some View {
        VStack(spacing: 2) {
            Text(forecast.title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)

            Image(systemName: forecast.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.multicolor)
                .frame(height: 20)

            Text(forecast.temperatureRangeText)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarModuleContent: some View {
        let calendar = calendarProvider.snapshot

        switch settings.calendarStyle {
        case .weeklySchedule:
            return AnyView(calendarWeekContent(calendar))
        case .monthlyGrid:
            return AnyView(calendarMonthContent(calendar))
        case .dotMatrix:
            return AnyView(calendarDotMatrixContent(calendar))
        }
    }

    private func calendarWeekContent(_ calendar: CalendarSnapshot) -> some View {
        let today = Date()
        let days = calendarWeekDays(for: today, offset: calendarWeekOffset)
        let fallbackDate = days.indices.contains(3) ? days[3].date : today
        let weekSelectedDate = selectedCalendarDate.flatMap { selectedDate in
            days.contains { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) } ? selectedDate : nil
        }
        let selectedDate = weekSelectedDate
            ?? days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })?.date
            ?? fallbackDate
        let titleDate = selectedDate

        return ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: calendarWeekVerticalSpacing) {
                HStack(alignment: .center, spacing: 6) {
                    Text(monthTitle(for: titleDate))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.29))
                        .padding(.leading, calendarTextLeadingInset)

                    Text(weekdayTitle(for: titleDate))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))

                    Spacer(minLength: 0)

                    calendarWeekButton(systemName: "chevron.left") {
                        withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                            calendarWeekOffset -= 1
                            selectedCalendarDate = nil
                        }
                    }

                    calendarWeekButton(systemName: "chevron.right") {
                        withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                            calendarWeekOffset += 1
                            selectedCalendarDate = nil
                        }
                    }
                }
                .frame(height: 18)

                HStack(spacing: calendarWeekGridSpacing) {
                    ForEach(days) { day in
                        Text(day.weekday)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(width: calendarWeekColumnWidth, alignment: .center)
                    }
                }
                .frame(width: calendarWeekGridWidth, alignment: .leading)
                .frame(height: 10)

                HStack(spacing: calendarWeekGridSpacing) {
                    ForEach(days) { day in
                        calendarWeekDayCell(day, selectedDate: selectedDate)
                            .frame(width: calendarWeekColumnWidth, alignment: .center)
                    }
                }
                .frame(width: calendarWeekGridWidth, alignment: .leading)
                .frame(height: 22)

                calendarSchedule(calendar, for: selectedDate)
                    .frame(height: 28, alignment: .topLeading)
                    .padding(.leading, calendarTextLeadingInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("\(monthDayTitle(for: selectedDate))·\(lunarDateTitle(for: selectedDate))")
                .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 14, alignment: .leading)
                .padding(.leading, calendarTextLeadingInset)
                .padding(.bottom, 1)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        .help(calendar.statusText)
    }

    private var calendarWeekVerticalSpacing: CGFloat {
        moduleCardHeight < 112 ? 4 : 6
    }

    private var calendarWeekColumnWidth: CGFloat {
        moduleCardHeight < 112 ? 20 : 21
    }

    private var calendarWeekGridSpacing: CGFloat {
        1
    }

    private var calendarWeekGridWidth: CGFloat {
        calendarWeekColumnWidth * 7 + calendarWeekGridSpacing * 6
    }

    private var calendarTextLeadingInset: CGFloat {
        6
    }

    private func resetCalendarSelectionToToday() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            calendarWeekOffset = 0
            calendarMonthOffset = 0
            selectedCalendarDate = nil
        }
    }

    private func calendarWeekButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 14, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(systemName == "chevron.left" ? "上一周" : "下一周")
    }

    private func calendarWeekDayCell(_ day: CalendarWeekDay, selectedDate: Date) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
        let isTodayMarker = day.isToday && !isSelected

        return Button {
            withAnimation(.smooth(duration: 0.16, extraBounce: 0)) {
                selectedCalendarDate = day.date
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.14, blue: 0.17))
                            .shadow(color: Color.red.opacity(0.22), radius: 4, y: 1)
                            .frame(width: 18, height: 18)
                    } else if isTodayMarker {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.14, blue: 0.17).opacity(0.16))
                            .overlay {
                                Circle()
                                    .stroke(Color(red: 1, green: 0.27, blue: 0.29).opacity(0.55), lineWidth: 1)
                            }
                            .frame(width: 18, height: 18)
                    }

                    Text("\(day.day)")
                        .font(.system(size: isSelected ? 11.5 : 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.82))
                        .monospacedDigit()
                }
                .frame(width: 19, height: 18)

                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.52) : Color.clear)
                    .frame(width: 11, height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func calendarSchedule(_ calendar: CalendarSnapshot, for date: Date) -> some View {
        let events = Array(calendarEvents(in: calendar, for: date).prefix(2))

        return VStack(alignment: .leading, spacing: 2) {
            if events.isEmpty {
                Text(calendar.isAuthorized ? "暂无日程" : calendar.statusText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(calendarAccentColor(event.calendarColorHex))
                            .frame(width: 4, height: 4)

                        Text("\(event.timeText)  \(event.title)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .frame(height: 13, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func calendarEvents(in calendar: CalendarSnapshot, for date: Date) -> [CalendarEventSummary] {
        let key = CalendarSnapshot.dayKey(for: date)
        return calendar.eventsByDay[key] ?? []
    }

    private func calendarWeekDays(for date: Date, offset: Int) -> [CalendarWeekDay] {
        let systemCalendar = Calendar.current
        let startOfCurrentWeek = systemCalendar.startOfWeek(for: date)
        let startOfTargetWeek = systemCalendar.date(
            byAdding: .day,
            value: offset * 7,
            to: startOfCurrentWeek
        ) ?? startOfCurrentWeek

        return (0..<7).compactMap { index in
            guard let dayDate = systemCalendar.date(byAdding: .day, value: index, to: startOfTargetWeek) else {
                return nil
            }

            let day = systemCalendar.component(.day, from: dayDate)
            return CalendarWeekDay(
                id: dayDate.timeIntervalSinceReferenceDate,
                date: dayDate,
                weekday: calendarWeekdayTitles[index],
                day: day,
                isToday: systemCalendar.isDate(dayDate, inSameDayAs: date)
            )
        }
    }

    private func calendarMonthContent(_ calendar: CalendarSnapshot) -> some View {
        let today = Date()
        let displayedMonth = calendarDisplayedMonth(for: today)
        let days = calendarMonthDays(for: displayedMonth)
        let selectedDate = selectedCalendarDate.flatMap { date in
            Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) ? date : nil
        } ?? calendarDefaultDate(in: displayedMonth, today: today)

        return GeometryReader { proxy in
            let rowCount = CGFloat(max(1, days.count / 7))
            let headerHeight: CGFloat = 18
            let weekdayHeight: CGFloat = 12
            let sectionSpacing: CGFloat = 6
            let rowSpacing: CGFloat = 1
            let contentWidth = max(1, proxy.size.width - calendarTextLeadingInset * 2)
            let firstColumnTextInset = max(0, contentWidth / 14 - 9.5 / 2)
            let availableGridHeight = max(
                1,
                proxy.size.height - headerHeight - weekdayHeight - sectionSpacing
            )
            let rowHeight = min(
                19,
                max(10, (availableGridHeight - rowSpacing * max(0, rowCount - 1)) / rowCount)
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    Color.clear
                        .frame(width: firstColumnTextInset, height: 1)

                    Text(monthDayTitle(for: selectedDate))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.29))

                    Text(weekdayTitle(for: selectedDate))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))

                    Spacer(minLength: 0)

                    calendarMonthNavigation
                }
                .frame(height: headerHeight)

                Spacer()
                    .frame(height: 3)

                HStack(spacing: 0) {
                    ForEach(calendarWeekdayTitles, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.46))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: weekdayHeight)

                Spacer()
                    .frame(height: 3)

                LazyVGrid(columns: calendarDayColumns, spacing: rowSpacing) {
                    ForEach(days) { day in
                        calendarMonthStyleDayCell(
                            day,
                            selectedDate: selectedDate,
                            height: rowHeight
                        )
                    }
                }
            }
            .padding(.horizontal, calendarTextLeadingInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .help(calendar.statusText)
    }

    private func calendarDotMatrixContent(_ calendar: CalendarSnapshot) -> some View {
        let today = Date()
        let displayedMonth = calendarDisplayedMonth(for: today)
        let days = calendarMonthDays(for: displayedMonth)
        let selectedDate = selectedCalendarDate.flatMap { date in
            Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) ? date : nil
        } ?? calendarDefaultDate(in: displayedMonth, today: today)

        return GeometryReader { proxy in
            let rowCount = CGFloat(max(1, days.count / 7))
            let headerHeight: CGFloat = 18
            let weekdayHeight: CGFloat = 11
            let footerHeight: CGFloat = 14
            let verticalSpacing: CGFloat = 4
            let contentWidth = max(1, proxy.size.width - calendarTextLeadingInset * 2)
            let firstColumnTextInset = max(0, contentWidth / 14 - 9 / 2)
            let availableGridHeight = max(
                1,
                proxy.size.height - headerHeight - weekdayHeight - footerHeight - verticalSpacing * 3
            )
            let rowHeight = max(7, availableGridHeight / rowCount)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    Color.clear
                        .frame(width: firstColumnTextInset, height: 1)

                    Text(monthTitle(for: displayedMonth))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.29))

                    Spacer(minLength: 0)

                    calendarMonthNavigation
                }
                .frame(height: headerHeight)

                Spacer().frame(height: verticalSpacing)

                HStack(spacing: 0) {
                    ForEach(calendarWeekdayTitles, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: weekdayHeight)

                Spacer().frame(height: verticalSpacing)

                LazyVGrid(columns: calendarDayColumns, spacing: 0) {
                    ForEach(days) { day in
                        calendarDotDayCell(day, selectedDate: selectedDate, height: rowHeight)
                    }
                }

                Spacer(minLength: verticalSpacing)

                Text("\(dayTitle(for: selectedDate)) · \(weekdayTitle(for: selectedDate)) · \(lunarDateTitle(for: selectedDate))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .frame(height: footerHeight, alignment: .leading)
                    .padding(.leading, firstColumnTextInset)
            }
            .padding(.horizontal, calendarTextLeadingInset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .help(calendar.statusText)
    }

    private var calendarMonthNavigation: some View {
        HStack(spacing: 2) {
            calendarWeekButton(systemName: "chevron.left") {
                moveCalendarMonth(by: -1)
            }

            calendarWeekButton(systemName: "chevron.right") {
                moveCalendarMonth(by: 1)
            }
        }
    }

    private func moveCalendarMonth(by delta: Int) {
        withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
            let preferredDay = Calendar.current.component(.day, from: selectedCalendarDate ?? Date())
            calendarMonthOffset += delta
            let targetMonth = calendarDisplayedMonth(for: Date())
            selectedCalendarDate = calendarDate(in: targetMonth, preferredDay: preferredDay)
        }
    }

    private func calendarDisplayedMonth(for today: Date) -> Date {
        let calendar = Calendar.current
        let currentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today
        return calendar.date(byAdding: .month, value: calendarMonthOffset, to: currentMonth) ?? currentMonth
    }

    private func calendarDefaultDate(in displayedMonth: Date, today: Date) -> Date {
        if Calendar.current.isDate(displayedMonth, equalTo: today, toGranularity: .month) {
            return today
        }
        return calendarDate(in: displayedMonth, preferredDay: Calendar.current.component(.day, from: today))
    }

    private func calendarDate(in month: Date, preferredDay: Int) -> Date {
        let calendar = Calendar.current
        let dayRange = calendar.range(of: .day, in: .month, for: month)
        let day = min(max(1, preferredDay), dayRange?.count ?? 1)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        return calendar.date(from: components) ?? month
    }

    private var calendarWeekdayTitles: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var calendarDayColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .center), count: 7)
    }

    private var compactWeatherForecastFontSize: CGFloat {
        8
    }

    private var compactWeatherForecastFont: Font {
        .system(size: compactWeatherForecastFontSize, weight: .bold, design: .rounded)
    }

    private var compactWeatherForecastLeadingOffset: CGFloat {
        0
    }

    private func calendarMonthStyleDayCell(
        _ day: CalendarMonthDay,
        selectedDate: Date,
        height: CGFloat
    ) -> some View {
        let isSelected = day.date.map {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        } ?? false
        let circleSize = min(19, max(14, height + 3))

        return Button {
            guard let date = day.date else { return }
            withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                selectedCalendarDate = date
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color(red: 0.94, green: 0.10, blue: 0.13))
                        .shadow(color: Color.red.opacity(0.18), radius: 3, y: 1)
                        .frame(width: circleSize, height: circleSize)
                }

                if let number = day.day {
                    Text("\(number)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.82))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.date == nil)
    }

    private func calendarDotDayCell(
        _ day: CalendarMonthDay,
        selectedDate: Date,
        height: CGFloat
    ) -> some View {
        let isSelected = day.date.map {
            Calendar.current.isDate($0, inSameDayAs: selectedDate)
        } ?? false

        return Button {
            guard let date = day.date else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                selectedCalendarDate = date
            }
        } label: {
            ZStack {
                if day.date != nil {
                    Circle()
                        .fill(isSelected ? Color(red: 1, green: 0.24, blue: 0.28) : Color.white.opacity(0.56))
                        .frame(width: isSelected ? 9 : 4, height: isSelected ? 9 : 4)

                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 3, height: 3)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.date == nil)
    }

    private func calendarScheduleFooter(_ calendar: CalendarSnapshot, isCompact: Bool) -> some View {
        let displayEvents = Array(calendar.events.prefix(2))
        let reservedHeight: CGFloat? = isCompact ? 23 : nil

        return VStack(alignment: .leading, spacing: isCompact ? 1 : 3) {
            if displayEvents.isEmpty {
                calendarEmptyScheduleRow(calendar, isCompact: isCompact)
            } else {
                ForEach(displayEvents) { event in
                    calendarFooterEventRow(event, isCompact: isCompact)
                }
            }
        }
        .padding(.top, isCompact ? 2 : 1)
        .frame(height: reservedHeight, alignment: .bottom)
    }

    private func calendarHorizontalSchedule(_ calendar: CalendarSnapshot) -> some View {
        let displayEvents = Array(calendar.events.prefix(3))

        return VStack(alignment: .leading, spacing: 8) {
            Text("今日日程")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.secondaryText)

            if displayEvents.isEmpty {
                calendarEmptyScheduleRow(calendar, isCompact: false)
            } else {
                ForEach(displayEvents) { event in
                    calendarFooterEventRow(event, isCompact: false)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func calendarFooterEventRow(_ event: CalendarEventSummary, isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 6 : 5) {
            Circle()
                .fill(calendarAccentColor(event.calendarColorHex))
                .frame(width: isCompact ? 4 : 4, height: isCompact ? 4 : 4)

            Text("\(event.timeText)  \(event.title)")
                .font(moduleFooterFont)
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 11 : 13, alignment: .leading)
    }

    private func calendarEmptyScheduleRow(_ calendar: CalendarSnapshot, isCompact: Bool) -> some View {
        let emptyText = calendar.isAuthorized ? "今日没有日程" : calendar.statusText

        return HStack(spacing: isCompact ? 6 : 5) {
            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: isCompact ? 4 : 4, height: isCompact ? 4 : 4)

            Text(emptyText)
                .font(moduleFooterFont)
                .foregroundStyle(IslandDesignTokens.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 11 : 13, alignment: .leading)
    }

    private func calendarMonthDays(for date: Date) -> [CalendarMonthDay] {
        let systemCalendar = Calendar.current
        let todayComponents = systemCalendar.dateComponents([.year, .month, .day], from: date)
        guard
            let firstDayOfMonth = systemCalendar.date(from: systemCalendar.dateComponents([.year, .month], from: date)),
            let dayRange = systemCalendar.range(of: .day, in: .month, for: firstDayOfMonth)
        else {
            return []
        }

        let leadingBlankCount = max(0, systemCalendar.component(.weekday, from: firstDayOfMonth) - 1)
        let monthKey = CalendarSnapshot.dayKey(for: firstDayOfMonth)
        var days = (0..<leadingBlankCount).map { index in
            CalendarMonthDay(id: "\(monthKey)-leading-\(index)", date: nil, day: nil, isToday: false)
        }

        for day in dayRange {
            let date = systemCalendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)
            let isToday = todayComponents.day == day
            days.append(
                CalendarMonthDay(
                    id: "\(monthKey)-day-\(day)",
                    date: date,
                    day: day,
                    isToday: isToday
                )
            )
        }

        while days.count % 7 != 0 {
            days.append(
                CalendarMonthDay(
                    id: "\(monthKey)-trailing-\(days.count)",
                    date: nil,
                    day: nil,
                    isToday: false
                )
            )
        }

        return days
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    private func monthDayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d日"
        return formatter.string(from: date)
    }

    private func weekdayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func lunarDateTitle(for date: Date) -> String {
        let calendar = Calendar(identifier: .chinese)
        let components = calendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = components.month, let day = components.day else {
            return "农历"
        }

        let leapPrefix = components.isLeapMonth == true ? "闰" : ""
        return "\(leapPrefix)\(lunarMonthName(month))\(lunarDayName(day))"
    }

    private func lunarMonthName(_ month: Int) -> String {
        let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        guard names.indices.contains(month - 1) else {
            return "农历"
        }

        return names[month - 1]
    }

    private func lunarDayName(_ day: Int) -> String {
        let names = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        guard names.indices.contains(day - 1) else {
            return ""
        }

        return names[day - 1]
    }

    private func calendarDefaultContent(_ calendar: CalendarSnapshot) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.dayTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(IslandDesignTokens.secondaryText)

                Text(calendar.dateTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandDesignTokens.primaryText)
            }
            .frame(minWidth: 58, alignment: .leading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                if calendar.events.isEmpty {
                    Text(calendar.statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(IslandDesignTokens.secondaryText)
                        .lineLimit(1)
                } else {
                    ForEach(calendar.events.prefix(2)) { event in
                        calendarEventRow(event, isDense: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(calendar.statusText)
    }

    private func calendarEventRow(_ event: CalendarEventSummary, isDense: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(calendarAccentColor(event.calendarColorHex))
                .frame(width: isDense ? 4 : 5, height: isDense ? 4 : 5)

            Text(event.timeText)
                .font(.system(size: isDense ? 9 : 10, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.secondaryText)
                .frame(width: isDense ? 34 : 30, alignment: .leading)

            Text(event.title)
                .font(.system(size: isDense ? 10 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(1)

            if isDense {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: isDense ? .infinity : nil, minHeight: isDense ? 14 : nil, alignment: .leading)
    }

    private var todoModuleContent: some View {
        TodoScheduleCardView(
            tasks: viewModel.todoTasks,
            onCreate: createTodoFromCard,
            onComplete: completeTodoFromCard,
            onRestore: restoreTodoFromCard,
            onDelete: deleteTodoFromCard,
            onExternalInteractiveFrameChange: handleTodoFloatingFrameChange,
            allowsFloatingContent: viewModel.presentationPhase == .expanded && viewModel.selectedTopTab == .home,
            onOpenSettings: onOpenTodoSettings
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help("日程待办")
    }

    private var todoDisplayLimit: Int {
        if isVeryTallModuleCard {
            return 5
        }

        return isTallModuleCard ? 4 : 2
    }

    private func todoLine(_ reminder: ReminderItemSummary) -> some View {
        HStack(spacing: 6) {
            TodoCompletionButton {
                reminderProvider.completeReminder(reminder)
            }
            .padding(.leading, 2)

            Text(reminder.title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(reminder.dueText)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(reminder.isOverdue ? Color.white.opacity(0.88) : IslandDesignTokens.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
    }

    private var mediaModuleContent: some View {
        let playback = currentSnapshot
        let displayedProgress = displayedPlaybackProgress(playback)

        return MusicLyricsPlaybackCard(
            playback: playback,
            diagnosticText: playbackDiagnosticText,
            lyricText: currentMediaLyricText(for: playback),
            progress: displayedProgress,
            availableHeight: moduleCardHeight - moduleCardVerticalPadding(for: .media) * 2,
            showsTrackName: settings.showMusicTrackName,
            showsLyrics: settings.showMusicLyrics,
            onScrubStarted: {
                beginPlaybackScrub(ifNeeded: playback)
            },
            onScrubChanged: { progress in
                playbackScrubProgress = progress
            },
            onScrubEnded: { progress in
                finishPlaybackScrub(at: progress)
            },
            onPrevious: {
                viewModel.playbackProvider.previousTrack()
            },
            onTogglePlayback: {
                viewModel.playbackProvider.togglePlayback()
            },
            onNext: {
                viewModel.playbackProvider.nextTrack()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .help(playback.isLive ? "\(playback.title) · \(playback.detail)" : "未检测到已开启的音乐应用播放")
    }

    private func currentMediaLyricText(for playback: PlaybackSnapshot) -> String {
        if !playback.isLive {
            return "未检测到已开启的音乐应用播放"
        }

        let entries = lyricsData.enumerated().compactMap { index, line -> (Int, String)? in
            let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = words.isEmpty ? translation : words
            return text.isEmpty ? nil : (index, text)
        }

        if let currentIndex = lyricsCurrentIndex {
            if let exact = entries.first(where: { $0.0 == currentIndex }) {
                return exact.1
            }
            if let next = entries.first(where: { $0.0 > currentIndex }) {
                return next.1
            }
            if let previous = entries.last(where: { $0.0 < currentIndex }) {
                return previous.1
            }
        } else if let first = entries.first {
            return first.1
        }

        if lyricsIsLoading {
            return "正在同步歌词..."
        }

        if !lyricsStatusText.isEmpty {
            return lyricsStatusText
        }

        return playback.state == .paused ? "播放已暂停" : "正在同步歌词..."
    }

    private func mediaInfoControlsRow(_ playback: PlaybackSnapshot) -> some View {
        HStack(alignment: .center, spacing: 7) {
            PlaybackArtworkTile(source: playback.artworkSource, isLive: playback.isLive, size: mediaArtworkSize)

            Text(playback.appName)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            playbackControlCluster(playback)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediaProgressRow(playback: PlaybackSnapshot, displayedProgress: Double) -> some View {
        HStack(spacing: 7) {
            Text(playback.elapsedText(for: displayedProgress))
                .frame(width: 34, alignment: .leading)

            playbackProgressScrubber(playback)
                .frame(maxWidth: .infinity)

            Text(playback.durationText)
                .frame(width: 34, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(IslandDesignTokens.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mediaTrackTitleRow(_ playback: PlaybackSnapshot) -> some View {
        Text(playback.title)
            .font(moduleFooterFont)
            .foregroundStyle(IslandDesignTokens.primaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaArtworkSize: CGFloat {
        if isTallModuleCard {
            return 44
        }

        return moduleCardHeight < 86 ? 26 : 34
    }

    private var mediaRowSpacing: CGFloat {
        if isTallModuleCard {
            return 8
        }

        return moduleCardHeight < 86 ? 3 : 5
    }

    private var mediaScrubReleaseDelay: Double {
        0.42
    }

    private func beginPlaybackScrub(ifNeeded playback: PlaybackSnapshot) {
        if !isScrubbingPlayback {
            playbackScrubProgress = playback.progress
            isScrubbingPlayback = true
        }
    }

    private func finishPlaybackScrub(at progress: Double) {
        let clampedProgress = min(max(progress, 0), 1)
        playbackScrubProgress = clampedProgress
        viewModel.playbackProvider.seek(to: clampedProgress, refreshAfterSeek: true)

        let duration = currentSnapshot.duration
        if duration > 0 {
            viewModel.lyricsProvider.seek(to: duration * clampedProgress)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + mediaScrubReleaseDelay) {
            if abs(playbackScrubProgress - clampedProgress) < 0.000_1 {
                isScrubbingPlayback = false
            }
        }
    }

    private func displayedPlaybackProgress(_ playback: PlaybackSnapshot) -> Double {
        isScrubbingPlayback ? playbackScrubProgress : playback.progress
    }

    private func playbackProgressScrubber(_ playback: PlaybackSnapshot) -> some View {
        PlaybackProgressScrubber(
            progress: displayedPlaybackProgress(playback),
            isEnabled: playback.canSeek,
            onScrubStarted: {
                beginPlaybackScrub(ifNeeded: playback)
            },
            onScrubChanged: { progress in
                playbackScrubProgress = progress
            },
            onScrubEnded: { progress in
                finishPlaybackScrub(at: progress)
            }
        )
    }

    private func playbackToggleButton(_ playback: PlaybackSnapshot) -> some View {
        Button(action: {
            viewModel.playbackProvider.togglePlayback()
        }) {
            Image(systemName: playback.state.controlSymbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .frame(width: 20, height: 20)
                .background {
                    Circle()
                        .fill(Color.white.opacity(playback.isLive ? 0.10 : 0.055))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playback.state == .playing ? "暂停播放" : "播放")
    }

    private func playbackControlCluster(_ playback: PlaybackSnapshot) -> some View {
        HStack(spacing: 4) {
            playbackTransportButton("backward.fill", help: "上一首", isEnabled: playback.isLive) {
                viewModel.playbackProvider.previousTrack()
            }

            playbackToggleButton(playback)

            playbackTransportButton("forward.fill", help: "下一首", isEnabled: playback.isLive) {
                viewModel.playbackProvider.nextTrack()
            }
        }
    }

    private func playbackTransportButton(
        _ systemName: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .frame(width: 18, height: 18)
                .background {
                    Circle()
                        .fill(Color.white.opacity(isEnabled ? 0.075 : 0.035))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(help)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        HoverIconButton(systemName: systemName, help: help, action: action)
    }

    private func imageButton(
        _ imageName: String,
        fallbackSystemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HoverImageButton(
            imageName: imageName,
            fallbackSystemName: fallbackSystemName,
            help: help,
            action: action
        )
    }

    private func calendarAccentColor(_ hex: String?) -> Color {
        guard
            let hex,
            let color = NSColor(hexString: hex)
        else {
            return Color.white.opacity(0.52)
        }

        return Color(nsColor: color).opacity(0.88)
    }
}

private enum WeatherCardMetrics {
    static let cornerRadius: CGFloat = 16
    static let contentInset: CGFloat = 0
    static let locationIconSize: CGFloat = 10.5
    static let locationFontSize: CGFloat = 10.8
    static let conditionFontSize: CGFloat = 14
    static let chipHeight: CGFloat = 27
    static let chipSpacing: CGFloat = 7
    static let chipCornerRadius: CGFloat = 14
    static let iconAreaAspectRatio: CGFloat = 145.6 / 104.8
    static let temperatureWidthRatio: CGFloat = 0.48
}

private struct WeatherCardView: View {
    let weather: WeatherSnapshot
    let apparentTemperature: String
    let humidity: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isCompact = size.width < 156 || size.height < 108
            let topHeight: CGFloat = isCompact ? 17 : 18
            let chipHeight: CGFloat = isCompact ? 25 : WeatherCardMetrics.chipHeight
            let bodyTopGap: CGFloat = isCompact ? 4 : 6
            let metricsTopGap: CGFloat = isCompact ? 6 : 8
            let mainContentLift: CGFloat = isCompact ? 2 : 3
            let bottomReserve: CGFloat = isCompact ? 3 : 4
            let middleHeight = max(52, size.height - topHeight - bodyTopGap - metricsTopGap - chipHeight - bottomReserve)
            let temperatureSize = min(
                isCompact ? 42 : 48,
                max(36, middleHeight * 0.72)
            )
            let iconSize = min(
                size.width * (isCompact ? 0.50 : 0.52),
                middleHeight * (isCompact ? 1.18 : 1.24)
            )

            VStack(alignment: .leading, spacing: 0) {
                locationRow
                    .frame(maxWidth: size.width * 0.64, alignment: .leading)
                    .frame(height: topHeight, alignment: .topLeading)

                Color.clear
                    .frame(height: bodyTopGap)

                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: isCompact ? 0 : 1) {
                        Text(weather.temperatureText)
                            .font(.system(size: temperatureSize, weight: .thin, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.98))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .monospacedDigit()
                            .shadow(color: .white.opacity(0.10), radius: 8)

                        Text(weather.condition)
                            .font(.system(size: isCompact ? 12.2 : 13.4, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                    }
                    .frame(width: size.width * 0.45, height: middleHeight, alignment: .center)

                    Spacer(minLength: 0)

                    WeatherMainIconView(
                        symbolName: weather.symbolName,
                        condition: weather.condition
                    )
                        .frame(width: iconSize, height: iconSize)
                        .offset(x: isCompact ? 4 : 5, y: isCompact ? -1 : -2)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: middleHeight, alignment: .center)
                .offset(y: -mainContentLift)

                Color.clear
                    .frame(height: metricsTopGap)

                HStack(spacing: WeatherCardMetrics.chipSpacing) {
                    WeatherInfoChipView(
                        systemName: "thermometer.medium",
                        label: "体感",
                        value: apparentTemperature,
                        isCompact: isCompact
                    )

                    WeatherInfoChipView(
                        systemName: "drop",
                        label: "湿度",
                        value: humidity,
                        isCompact: isCompact
                    )
                }
                .frame(height: chipHeight)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "location.fill")
                .font(.system(size: WeatherCardMetrics.locationIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.62))

            Text(weather.locationName)
                .font(.system(size: WeatherCardMetrics.locationFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

private enum WeatherCardIconKind: Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case sleet
    case snow
    case thunderstorm
    case unavailable

    init(symbolName: String, condition: String) {
        let source = "\(symbolName) \(condition)"

        if source.contains("bolt") || source.contains("雷") {
            self = .thunderstorm
        } else if source.contains("heavyrain") || source.contains("阵雨") {
            self = .heavyRain
        } else if source.contains("drizzle") || source.contains("毛毛雨") {
            self = .drizzle
        } else if source.contains("sleet") || source.contains("冻雨") {
            self = .sleet
        } else if source.contains("rain") || source.contains("雨") {
            self = .rain
        } else if source.contains("snow") || source.contains("雪") {
            self = .snow
        } else if source.contains("fog") || source.contains("雾") {
            self = .fog
        } else if source.contains("cloud.sun") || source.contains("少云") || source.contains("多云") {
            self = .partlyCloudy
        } else if source.contains("sun") || source.contains("晴") {
            self = .clear
        } else if source.contains("cloud") || source.contains("阴") {
            self = .cloudy
        } else {
            self = .unavailable
        }
    }
}

private struct WeatherMainIconView: View {
    let symbolName: String
    let condition: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kind: WeatherCardIconKind {
        WeatherCardIconKind(symbolName: symbolName, condition: condition)
    }

    var body: some View {
        Group {
            if reduceMotion {
                iconFrame(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    iconFrame(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: kind)
    }

    private func iconFrame(phase: TimeInterval) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            iconContent(side: side, phase: phase)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func iconContent(side: CGFloat, phase: TimeInterval) -> some View {
        switch kind {
        case .clear:
            clearIcon(side: side, phase: phase)
        case .partlyCloudy:
            partlyCloudyIcon(side: side, phase: phase)
        case .cloudy:
            cloudyIcon(side: side, phase: phase)
        case .fog:
            fogIcon(side: side, phase: phase)
        case .drizzle:
            drizzleIcon(side: side, phase: phase)
        case .rain:
            rainIcon(side: side, phase: phase)
        case .heavyRain:
            heavyRainIcon(side: side, phase: phase)
        case .sleet:
            sleetIcon(side: side, phase: phase)
        case .snow:
            snowIcon(side: side, phase: phase)
        case .thunderstorm:
            thunderstormIcon(side: side, phase: phase)
        case .unavailable:
            cloudyIcon(side: side, phase: phase)
        }
    }

    private func clearIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            sun(
                side: side,
                center: CGPoint(x: side * 0.50, y: side * 0.50),
                diameter: side * 0.56,
                rayCount: 8,
                phase: phase,
                rotationSpeed: 2.6
            )
        }
        .frame(width: side, height: side)
    }

    private func partlyCloudyIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            sun(
                side: side,
                center: CGPoint(x: side * 0.64, y: side * 0.40),
                diameter: side * 0.50,
                rayCount: 7,
                phase: phase,
                rotationSpeed: 1.9
            )

            cloud(width: side * 0.76, height: side * 0.42)
                .position(
                    x: side * 0.42 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.018),
                    y: side * 0.64
                )
        }
        .frame(width: side, height: side)
    }

    private func cloudyIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            cloud(width: side * 0.54, height: side * 0.31)
                .opacity(0.70)
                .position(
                    x: side * 0.64 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.018),
                    y: side * 0.42
                )

            cloud(width: side * 0.78, height: side * 0.43)
                .position(
                    x: side * 0.48 + cloudDrift(phase: phase, index: 1, amplitude: side * 0.014),
                    y: side * 0.58
                )
        }
        .frame(width: side, height: side)
    }

    private func fogIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            cloud(width: side * 0.72, height: side * 0.40)
                .opacity(0.86)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.012),
                    y: side * 0.43
                )

            fogBands(side: side, phase: phase)
        }
        .frame(width: side, height: side)
    }

    private func drizzleIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            cloud(width: side * 0.74, height: side * 0.41)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.010),
                    y: side * 0.42
                )

            rainDrops(
                side: side,
                count: 3,
                yStart: side * 0.66,
                length: side * 0.10,
                width: side * 0.025,
                opacity: 0.68,
                phase: phase,
                duration: 1.60,
                fallDistance: side * 0.14
            )
        }
        .frame(width: side, height: side)
    }

    private func rainIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            cloud(width: side * 0.76, height: side * 0.42)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.011),
                    y: side * 0.42
                )

            rainDrops(
                side: side,
                count: 4,
                yStart: side * 0.66,
                length: side * 0.16,
                width: side * 0.034,
                opacity: 0.82,
                phase: phase,
                duration: 1.10,
                fallDistance: side * 0.20
            )
        }
        .frame(width: side, height: side)
    }

    private func heavyRainIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            stormCloud(width: side * 0.78, height: side * 0.43)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.008),
                    y: side * 0.40
                )

            rainDrops(
                side: side,
                count: 5,
                yStart: side * 0.64,
                length: side * 0.20,
                width: side * 0.04,
                opacity: 0.92,
                phase: phase,
                duration: 0.82,
                fallDistance: side * 0.26
            )
        }
        .frame(width: side, height: side)
    }

    private func sleetIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            stormCloud(width: side * 0.76, height: side * 0.42)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.010),
                    y: side * 0.41
                )

            rainDrops(
                side: side,
                count: 2,
                yStart: side * 0.66,
                length: side * 0.15,
                width: side * 0.034,
                opacity: 0.78,
                phase: phase,
                duration: 1.12,
                fallDistance: side * 0.18
            )

            snowflakes(side: side, count: 2, yStart: side * 0.70, phase: phase)
        }
        .frame(width: side, height: side)
    }

    private func snowIcon(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            cloud(width: side * 0.76, height: side * 0.42)
                .opacity(0.92)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.010),
                    y: side * 0.41
                )

            snowflakes(side: side, count: 4, yStart: side * 0.66, phase: phase)
        }
        .frame(width: side, height: side)
    }

    private func thunderstormIcon(side: CGFloat, phase: TimeInterval) -> some View {
        let flash = lightningFlash(phase: phase)

        return ZStack {
            stormCloud(width: side * 0.78, height: side * 0.43)
                .brightness(flash * 0.08)
                .position(
                    x: side * 0.50 + cloudDrift(phase: phase, index: 0, amplitude: side * 0.008),
                    y: side * 0.39
                )

            lightningBolt(side: side)
                .opacity(0.72 + flash * 0.28)
                .scaleEffect(1 + flash * 0.05, anchor: .center)

            rainDrops(
                side: side,
                count: 3,
                yStart: side * 0.68,
                length: side * 0.16,
                width: side * 0.034,
                opacity: 0.72,
                phase: phase,
                duration: 0.92,
                fallDistance: side * 0.20
            )
        }
        .frame(width: side, height: side)
    }

    private func sun(
        side: CGFloat,
        center: CGPoint,
        diameter: CGFloat,
        rayCount: Int,
        phase: TimeInterval,
        rotationSpeed: Double
    ) -> some View {
        let pulse = 1 + CGFloat(sin(phase * 1.15)) * 0.035
        let rayRotation = Angle.degrees(phase * rotationSpeed)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.70, blue: 0.18).opacity(0.26),
                            Color(red: 1.0, green: 0.46, blue: 0.08).opacity(0.10),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: diameter * 0.20,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter * 2.05 * pulse, height: diameter * 2.05 * pulse)
                .position(center)

            ForEach(0..<rayCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(sunRayGradient)
                    .frame(width: max(2.5, diameter * 0.10), height: diameter * 0.36)
                    .offset(y: -diameter * 0.86)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(rayCount)))
                    .position(center)
                    .shadow(color: Color(red: 1.0, green: 0.58, blue: 0.10).opacity(0.26), radius: 3)
            }
            .rotationEffect(rayRotation, anchor: UnitPoint(x: center.x / side, y: center.y / side))

            Circle()
                .fill(sunGradient)
                .frame(width: diameter * pulse, height: diameter * pulse)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.36), lineWidth: 0.9)
                        .blur(radius: 0.4)
                }
                .shadow(color: Color(red: 1.0, green: 0.58, blue: 0.10).opacity(0.34), radius: side * 0.08)
                .position(center)
        }
        .frame(width: side, height: side)
    }

    private func cloud(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(cloudGradient)
                .frame(width: width * 0.82, height: height * 0.50)
                .position(x: width * 0.48, y: height * 0.68)

            Circle()
                .fill(cloudGradient)
                .frame(width: height * 0.72, height: height * 0.72)
                .position(x: width * 0.25, y: height * 0.57)

            Circle()
                .fill(cloudGradient)
                .frame(width: height * 0.94, height: height * 0.94)
                .position(x: width * 0.47, y: height * 0.43)

            Circle()
                .fill(cloudGradient)
                .frame(width: height * 0.62, height: height * 0.62)
                .position(x: width * 0.68, y: height * 0.58)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(Color(red: 0.54, green: 0.78, blue: 1.0).opacity(0.26))
                .frame(width: width * 0.64, height: 1.2)
                .offset(y: -height * 0.07)
        }
        .compositingGroup()
    }

    private func stormCloud(width: CGFloat, height: CGFloat) -> some View {
        cloud(width: width, height: height)
            .saturation(0.70)
            .brightness(-0.10)
    }

    private func rainDrops(
        side: CGFloat,
        count: Int,
        yStart: CGFloat,
        length: CGFloat,
        width: CGFloat,
        opacity: Double,
        phase: TimeInterval,
        duration: TimeInterval,
        fallDistance: CGFloat
    ) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let progress = animationProgress(
                    phase: phase,
                    duration: duration,
                    offset: Double(index) * 0.27
                )
                let fade = sin(progress * .pi)
                let baseX = rainDropX(index: index, count: count, side: side)
                let baseY = yStart + (index.isMultiple(of: 2) ? 0 : side * 0.045)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(opacity * (0.42 + 0.58 * fade)),
                                Color(red: 0.28, green: 0.68, blue: 1.0).opacity(opacity * (0.42 + 0.58 * fade))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: length)
                    .rotationEffect(.degrees(13))
                    .position(
                        x: baseX + CGFloat(progress) * side * 0.035,
                        y: baseY + CGFloat(progress) * fallDistance
                    )
                    .shadow(color: Color(red: 0.28, green: 0.68, blue: 1.0).opacity(0.20), radius: 2)
            }
        }
        .frame(width: side, height: side)
    }

    private func snowflakes(side: CGFloat, count: Int, yStart: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let progress = animationProgress(
                    phase: phase,
                    duration: 3.2 + Double(index % 2) * 0.7,
                    offset: Double(index) * 0.21
                )
                let sway = sin(phase * 1.25 + Double(index) * 1.8)
                let fade = sin(progress * .pi)
                let baseY = yStart + CGFloat(index % 2) * side * 0.10

                Image(systemName: "snowflake")
                    .font(.system(size: side * (index.isMultiple(of: 2) ? 0.10 : 0.13), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.83, green: 0.96, blue: 1.0).opacity(0.42 + 0.50 * fade))
                    .rotationEffect(.degrees(phase * (index.isMultiple(of: 2) ? 16 : -12)))
                    .position(
                        x: snowflakeX(index: index, count: count, side: side) + CGFloat(sway) * side * 0.035,
                        y: baseY + CGFloat(progress) * side * 0.18
                    )
                    .shadow(color: Color(red: 0.45, green: 0.78, blue: 1.0).opacity(0.18), radius: 2)
            }
        }
        .frame(width: side, height: side)
    }

    private func fogBands(side: CGFloat, phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let drift = sin(phase * 0.62 + Double(index) * 1.4)
                let opacityPulse = 0.78 + 0.22 * sin(phase * 0.80 + Double(index))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.70 * opacityPulse),
                                Color(red: 0.62, green: 0.78, blue: 0.92).opacity(0.38 * opacityPulse)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: side * (0.58 - CGFloat(index) * 0.08), height: side * 0.032)
                    .position(
                        x: side * 0.50 + CGFloat(drift) * side * 0.055,
                        y: side * (0.63 + CGFloat(index) * 0.095)
                    )
            }
        }
        .frame(width: side, height: side)
    }

    private func lightningBolt(side: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: side * 0.52, y: side * 0.47))
            path.addLine(to: CGPoint(x: side * 0.42, y: side * 0.70))
            path.addLine(to: CGPoint(x: side * 0.55, y: side * 0.68))
            path.addLine(to: CGPoint(x: side * 0.49, y: side * 0.88))
            path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.60))
            path.addLine(to: CGPoint(x: side * 0.57, y: side * 0.62))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.34),
                    Color(red: 1.0, green: 0.58, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .shadow(color: Color(red: 1.0, green: 0.68, blue: 0.10).opacity(0.34), radius: 3)
        .frame(width: side, height: side)
    }

    private func rainDropX(index: Int, count: Int, side: CGFloat) -> CGFloat {
        let start: CGFloat = count >= 5 ? 0.25 : (count == 2 ? 0.40 : 0.34)
        let step: CGFloat = count >= 5 ? 0.12 : (count == 2 ? 0.20 : 0.15)
        return side * (start + CGFloat(index) * step)
    }

    private func snowflakeX(index: Int, count: Int, side: CGFloat) -> CGFloat {
        let start: CGFloat = count <= 2 ? 0.43 : 0.30
        let step: CGFloat = count <= 2 ? 0.20 : 0.14
        return side * (start + CGFloat(index) * step)
    }

    private func cloudDrift(phase: TimeInterval, index: Int, amplitude: CGFloat) -> CGFloat {
        CGFloat(sin(phase * 0.72 + Double(index) * 1.65)) * amplitude
    }

    private func animationProgress(
        phase: TimeInterval,
        duration: TimeInterval,
        offset: TimeInterval
    ) -> Double {
        let value = (phase / duration + offset).truncatingRemainder(dividingBy: 1)
        return value >= 0 ? value : value + 1
    }

    private func lightningFlash(phase: TimeInterval) -> CGFloat {
        let progress = animationProgress(phase: phase, duration: 2.35, offset: 0)
        guard progress < 0.16 else { return 0 }
        let primary = max(0, 1 - abs(progress - 0.04) / 0.04)
        let secondary = max(0, 0.72 - abs(progress - 0.11) / 0.035)
        return CGFloat(max(primary, secondary))
    }

    private var sunGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.95, blue: 0.46),
                Color(red: 1.0, green: 0.78, blue: 0.12),
                Color(red: 1.0, green: 0.43, blue: 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sunRayGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.88, blue: 0.28),
                Color(red: 1.0, green: 0.60, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cloudGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.98),
                Color(red: 0.94, green: 0.95, blue: 0.94).opacity(0.94),
                Color(red: 0.72, green: 0.84, blue: 0.98).opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct WeatherInfoChipView: View {
    let systemName: String
    let label: String
    let value: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 3 : 4) {
            Image(systemName: systemName)
                .font(.system(size: isCompact ? 9.5 : 10.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(width: isCompact ? 21 : 23, height: isCompact ? 21 : 23)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        }
                }

            chipText
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .layoutPriority(1)
        }
        .padding(.leading, isCompact ? 1 : 2)
        .padding(.trailing, isCompact ? 4 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var chipText: Text {
        var labelPart = AttributedString(label + " ")
        labelPart.font = .system(size: isCompact ? 8.4 : 9, weight: .medium, design: .rounded)
        labelPart.foregroundColor = Color.white.opacity(0.52)

        var valuePart = AttributedString(value)
        valuePart.font = .system(size: isCompact ? 11.1 : 12.2, weight: .semibold, design: .rounded)
        valuePart.foregroundColor = Color.white.opacity(0.82)

        labelPart.append(valuePart)
        return Text(labelPart).monospacedDigit()
    }
}

private enum TodoScheduleCardMetrics {
    static let cornerRadius: CGFloat = 22
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 12
    static let headerSpacing: CGFloat = 5
    static let dateItemWidth: CGFloat = 32
    static let dateItemHeight: CGFloat = 38
    static let moreButtonSize: CGFloat = 24
    static let rowSpacing: CGFloat = 6
    static let selectedBlue = Color(red: 0.06, green: 0.43, blue: 1.0)
    static let moreMenuWidth: CGFloat = 114
    static let moreMenuHeight: CGFloat = 240
    static let floatingPanelTopOffset: CGFloat = 32
    static let floatingContentBottomInset: CGFloat = 18
}

private struct TodoDateOption: Identifiable, Equatable {
    let date: Date
    let weekday: String
    let day: String
    let isSelected: Bool

    var id: Date { date }
}

private enum TodoCardPanel: Identifiable {
    case create
    case all
    case completed
    case sort
    case settings

    var id: String {
        switch self {
        case .create: "create"
        case .all: "all"
        case .completed: "completed"
        case .sort: "sort"
        case .settings: "settings"
        }
    }
}

private struct TodoCardCreateDraft: Equatable {
    var title = ""
    var date: Date
    var hasTime = false
    var time: Date
    var category: TodoCategory = .none
    var priority: TodoPriority = .normal
    var note = ""
    var hasReminder = false

    init(date: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: date)
        self.date = day
        self.time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var reminderCreationRequest: ReminderCreationRequest {
        let tags = [category.tagText, priority.tagText]
            .compactMap { $0 }
            .joined(separator: " ")

        return ReminderCreationRequest(
            title: title,
            notes: note,
            hasDueDate: true,
            dueDate: date,
            hasDueTime: hasTime,
            dueTime: time,
            hasAlarm: hasReminder,
            location: "",
            tagsText: tags
        )
    }
}

private struct TodoScheduleCardView: View {
    @State private var selectedDate: Date
    @State private var showTodayOnly = false
    @State private var isMoreButtonPressed = false
    @State private var currentCardHeight: CGFloat = 0
    @State private var currentCardWidth: CGFloat = 0
    @State private var moreButtonScreenFrame: CGRect?

    @AppStorage(TodoCardStorageKeys.sortMode) private var sortModeRaw = TodoSortMode.timeAsc.rawValue
    @AppStorage(TodoCardStorageKeys.showDateSelector) private var showDateSelector = true
    @AppStorage(TodoCardStorageKeys.showTime) private var showTime = true
    @AppStorage(TodoCardStorageKeys.showCategory) private var showCategory = true
    @AppStorage(TodoCardStorageKeys.showCompleted) private var showCompleted = false
    @AppStorage(TodoCardStorageKeys.maxVisibleItems) private var maxVisibleItems = 2
    @AppStorage(TodoCardStorageKeys.defaultRange) private var defaultRangeRaw = TodoDefaultRange.selectedDate.rawValue
    @AppStorage(TodoCardStorageKeys.highlightColor) private var highlightColorRaw = TodoHighlightColor.blue.rawValue
    @AppStorage(TodoCardStorageKeys.useCompactMode) private var useCompactMode = false
    @AppStorage(TodoCardStorageKeys.showEdgeGlow) private var showEdgeGlow = true
    @AppStorage(TodoCardStorageKeys.showReminderBadge) private var showReminderBadge = true
    @AppStorage(TodoCardStorageKeys.dueSoonMinutes) private var dueSoonMinutes = 15

    private let calendar: Calendar
    private let tasks: [TodoTask]
    private let onCreate: (TodoCardCreateDraft) -> Void
    private let onComplete: (TodoSchedulePreviewItem) -> Void
    private let onRestore: (TodoSchedulePreviewItem) -> Void
    private let onDelete: (TodoSchedulePreviewItem) -> Void
    private let onExternalInteractiveFrameChange: (CGRect?) -> Void
    private let allowsFloatingContent: Bool
    private let onOpenSettings: () -> Void

    init(
        tasks: [TodoTask],
        calendar: Calendar = .current,
        onCreate: @escaping (TodoCardCreateDraft) -> Void,
        onComplete: @escaping (TodoSchedulePreviewItem) -> Void,
        onRestore: @escaping (TodoSchedulePreviewItem) -> Void,
        onDelete: @escaping (TodoSchedulePreviewItem) -> Void,
        onExternalInteractiveFrameChange: @escaping (CGRect?) -> Void,
        allowsFloatingContent: Bool,
        onOpenSettings: @escaping () -> Void
    ) {
        var configuredCalendar = calendar
        configuredCalendar.locale = Locale(identifier: "zh_CN")
        let today = configuredCalendar.startOfDay(for: Date())

        self.calendar = configuredCalendar
        self.tasks = tasks
        self.onCreate = onCreate
        self.onComplete = onComplete
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onExternalInteractiveFrameChange = onExternalInteractiveFrameChange
        self.allowsFloatingContent = allowsFloatingContent
        self.onOpenSettings = onOpenSettings
        _selectedDate = State(initialValue: today)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isCompact = useCompactMode || size.height < 105
            let isNarrow = size.width < 248
            let dateOptions = dateOptions()
            let items = selectedTodos()
            let maxItems = max(1, min(maxVisibleItems, isCompact ? 2 : 4))
            let accent = accentColor

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: isCompact ? 9 : 12) {
                    HStack(alignment: .top, spacing: isNarrow ? 4 : TodoScheduleCardMetrics.headerSpacing) {
                        Text(monthTitle(for: effectiveSelectedDate))
                            .font(.system(size: isCompact ? 20 : (isNarrow ? 21 : 23), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.96))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .frame(width: isCompact ? 32 : (isNarrow ? 36 : 40), alignment: .leading)
                            .shadow(color: .white.opacity(0.06), radius: 6, y: 1)

                        if showDateSelector {
                            TodoDateSelectorView(
                                dates: dateOptions,
                                selectedDate: effectiveSelectedDate,
                                isCompact: isCompact,
                                isNarrow: isNarrow,
                                accentColor: accent,
                                onSelect: selectDate
                            )
                            .layoutPriority(1)
                        }

                        moreButton(isCompact: isCompact, isNarrow: isNarrow)
                    }

                    TodoListPreviewView(
                        items: items,
                        isCompact: isCompact,
                        maxVisibleItems: maxItems,
                        showTime: showTime,
                        showCategory: showCategory,
                        accentColor: accent,
                        todayFooterText: showTodayOnly ? "今日还有 \(items.count) 项" : nil,
                        onComplete: onComplete
                    )
                    .id(dayIdentifier(for: effectiveSelectedDate) + "-\(showTodayOnly)-\(sortMode.rawValue)-\(showCompleted)")
                    .transition(.opacity.combined(with: .offset(y: 4)))
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .animation(.easeOut(duration: 0.18), value: dayIdentifier(for: effectiveSelectedDate))
                .animation(.easeOut(duration: 0.18), value: showTodayOnly)
                .animation(.easeOut(duration: 0.18), value: sortModeRaw)

            }
            .onAppear {
                currentCardHeight = size.height
                currentCardWidth = size.width
            }
            .onChange(of: size.height) { _, newHeight in
                currentCardHeight = newHeight
            }
            .onChange(of: size.width) { _, newWidth in
                currentCardWidth = newWidth
            }
            .onChange(of: allowsFloatingContent) { _, allowsFloatingContent in
                if !allowsFloatingContent {
                    TodoFloatingPanelPresenter.shared.close()
                    onExternalInteractiveFrameChange(nil)
                }
            }
            .onDisappear {
                TodoFloatingPanelPresenter.shared.close()
                onExternalInteractiveFrameChange(nil)
            }
        }
    }

    private var settings: TodoCardSettings {
        TodoCardSettings(
            showDateSelector: showDateSelector,
            showTime: showTime,
            showCategory: showCategory,
            showCompleted: showCompleted,
            maxVisibleItems: maxVisibleItems,
            defaultRange: defaultRange,
            sortMode: sortMode,
            highlightColor: highlightColor,
            useCompactMode: useCompactMode,
            showEdgeGlow: showEdgeGlow,
            showReminderBadge: showReminderBadge,
            dueSoonMinutes: dueSoonMinutes
        )
    }

    private var sortMode: TodoSortMode {
        TodoSortMode(rawValue: sortModeRaw) ?? .timeAsc
    }

    private var defaultRange: TodoDefaultRange {
        TodoDefaultRange(rawValue: defaultRangeRaw) ?? .selectedDate
    }

    private var highlightColor: TodoHighlightColor {
        TodoHighlightColor(rawValue: highlightColorRaw) ?? .blue
    }

    private var effectiveSelectedDate: Date {
        if showTodayOnly || defaultRange == .today {
            return calendar.startOfDay(for: Date())
        }
        return selectedDate
    }

    private var accentColor: Color {
        switch highlightColor {
        case .blue: TodoScheduleCardMetrics.selectedBlue
        case .purple: Color(red: 0.60, green: 0.39, blue: 1.0)
        case .orange: Color(red: 1.0, green: 0.55, blue: 0.18)
        case .green: Color(red: 0.26, green: 0.78, blue: 0.50)
        }
    }

    private func moreButton(isCompact: Bool, isNarrow: Bool) -> some View {
        Button {
            guard allowsFloatingContent else { return }
            if TodoFloatingPanelPresenter.shared.isPresented {
                closeFloatingMenu()
                return
            }

            isMoreButtonPressed = true
            presentFloatingMenu(anchor: fixedMenuAnchor())
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                isMoreButtonPressed = false
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: isCompact ? 11.5 : (isNarrow ? 12.5 : 13.5), weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
                .frame(
                    width: isCompact ? 23 : (isNarrow ? 23 : TodoScheduleCardMetrics.moreButtonSize),
                    height: isCompact ? 23 : (isNarrow ? 23 : TodoScheduleCardMetrics.moreButtonSize)
                )
                .background {
                    ZStack {
                        ScreenFrameReporter { frame in
                            moreButtonScreenFrame = frame
                        }
                        .allowsHitTesting(false)

                        Circle()
                            .fill(Color.white.opacity(0.014))
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                            }
                            .shadow(color: accentColor.opacity(showEdgeGlow ? 0.24 : 0), radius: 8, y: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isMoreButtonPressed ? 0.94 : 1)
        .handCursor()
        .help("更多待办操作")
    }

    private func fixedMenuAnchor() -> NSPoint {
        guard let frame = moreButtonScreenFrame,
              frame.width > 0,
              frame.height > 0
        else {
            return NSEvent.mouseLocation
        }

        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func presentFloatingMenu(anchor: NSPoint) {
        TodoFloatingPanelPresenter.shared.present(
            anchor: anchor,
            tasks: tasks,
            selectedDate: effectiveSelectedDate,
            showTodayOnly: showTodayOnly,
            calendar: calendar,
            cardSize: CGSize(width: currentCardWidth, height: currentCardHeight),
            onCreate: onCreate,
            onComplete: onComplete,
            onRestore: onRestore,
            onDelete: onDelete,
            onTodayOnlyChanged: { isEnabled in
                withAnimation(.easeOut(duration: 0.16)) {
                    showTodayOnly = isEnabled
                }
            },
            onExternalFrameChange: onExternalInteractiveFrameChange,
            onOpenSettings: onOpenSettings
        )
    }

    private func closeFloatingMenu() {
        TodoFloatingPanelPresenter.shared.close()
        onExternalInteractiveFrameChange(nil)
    }

    private func selectDate(_ date: Date) {
        guard !showTodayOnly else { return }
        let day = calendar.startOfDay(for: date)
        guard !calendar.isDate(day, inSameDayAs: selectedDate) else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            selectedDate = day
        }
    }

    private func dateOptions() -> [TodoDateOption] {
        (-45...90).compactMap { offset in
            guard let date = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: Date())
            ) else {
                return nil
            }

            return TodoDateOption(
                date: date,
                weekday: weekdayTitle(for: date),
                day: "\(calendar.component(.day, from: date))",
                isSelected: calendar.isDate(date, inSameDayAs: effectiveSelectedDate)
            )
        }
    }

    private func selectedTodos() -> [TodoSchedulePreviewItem] {
        TodoSchedulePreviewItem.items(
            from: tasks,
            selectedDate: selectedDate,
            today: Date(),
            showTodayOnly: showTodayOnly || defaultRange == .today,
            showCompleted: settings.showCompleted,
            sortMode: sortMode,
            calendar: calendar
        )
    }

    private func monthTitle(for date: Date) -> String {
        "\(calendar.component(.month, from: date))月"
    }

    private func weekdayTitle(for date: Date) -> String {
        let titles = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = calendar.component(.weekday, from: date)
        guard titles.indices.contains(weekday - 1) else {
            return "周"
        }

        return titles[weekday - 1]
    }

    private func dayIdentifier(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct ScreenFrameReporter: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ScreenFrameReportingView {
        let view = ScreenFrameReportingView()
        view.onFrameChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScreenFrameReportingView, context: Context) {
        nsView.onFrameChange = onChange
        nsView.scheduleReport()
    }
}

private final class ScreenFrameReportingView: NSView {
    var onFrameChange: ((CGRect) -> Void)?

    private var windowObserver: NSObjectProtocol?
    private var lastReportedFrame = CGRect.null

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
            self.windowObserver = nil
        }

        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleReport()
            }
        }

        scheduleReport()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        scheduleReport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleReport()
    }

    override func layout() {
        super.layout()
        scheduleReport()
    }

    func scheduleReport() {
        DispatchQueue.main.async { [weak self] in
            self?.reportFrameIfNeeded()
        }
    }

    private func reportFrameIfNeeded() {
        guard let window else { return }

        let rectInWindow = convert(bounds, to: nil)
        let screenFrame = window.convertToScreen(rectInWindow)
        guard screenFrame != lastReportedFrame else { return }

        lastReportedFrame = screenFrame
        onFrameChange?(screenFrame)
    }
}

private final class TodoFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class TodoFloatingHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keepBackgroundClear()
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    override func layout() {
        super.layout()
        keepBackgroundClear()
    }

    private func keepBackgroundClear() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
private final class TodoFloatingPanelPresenter: NSObject, NSWindowDelegate {
    static let shared = TodoFloatingPanelPresenter()

    private var panel: TodoFloatingPanel?
    private var anchor: NSPoint = .zero
    private var onExternalFrameChange: ((CGRect?) -> Void)?
    private var requestedFrame: NSRect?

    var isPresented: Bool {
        panel != nil
    }

    func present(
        anchor: NSPoint,
        tasks: [TodoTask],
        selectedDate: Date,
        showTodayOnly: Bool,
        calendar: Calendar,
        cardSize: CGSize,
        onCreate: @escaping (TodoCardCreateDraft) -> Void,
        onComplete: @escaping (TodoSchedulePreviewItem) -> Void,
        onRestore: @escaping (TodoSchedulePreviewItem) -> Void,
        onDelete: @escaping (TodoSchedulePreviewItem) -> Void,
        onTodayOnlyChanged: @escaping (Bool) -> Void,
        onExternalFrameChange: @escaping (CGRect?) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.anchor = anchor
        requestedFrame = nil
        self.onExternalFrameChange?(nil)
        self.onExternalFrameChange = onExternalFrameChange

        let initialSize = CGSize(
            width: TodoScheduleCardMetrics.moreMenuWidth,
            height: TodoScheduleCardMetrics.moreMenuHeight
        )
        let activePanel = self.panel ?? makePanel(size: initialSize)
        self.panel = activePanel

        let rootView = TodoFloatingPanelRootView(
            tasks: tasks,
            selectedDate: selectedDate,
            showTodayOnly: showTodayOnly,
            calendar: calendar,
            cardSize: cardSize,
            onCreate: { [weak self] draft in
                onCreate(draft)
                self?.close()
            },
            onComplete: onComplete,
            onRestore: onRestore,
            onDelete: onDelete,
            onTodayOnlyChanged: onTodayOnlyChanged,
            onClose: { [weak self] in
                self?.close()
            },
            onOpenSettings: onOpenSettings,
            onSizeChange: { [weak self] size, animated in
                self?.resize(to: size, animated: animated)
            }
        )
        let hostingView = TodoFloatingHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        activePanel.contentView = hostingView

        resize(to: initialSize, animated: false)
        activePanel.orderFrontRegardless()
    }

    func close() {
        guard let closingPanel = panel else {
            requestedFrame = nil
            onExternalFrameChange = nil
            return
        }

        let frameChange = onExternalFrameChange
        panel = nil
        requestedFrame = nil
        onExternalFrameChange = nil
        closingPanel.delegate = nil

        frameChange?(nil)
        closingPanel.orderOut(nil)

        // Releasing the hosting view while one of its buttons is still handling
        // the mouse event can leave AppKit's tracking cycle in an invalid state.
        // Finish teardown on the next main-loop turn instead.
        DispatchQueue.main.async {
            closingPanel.contentView = nil
            closingPanel.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let currentPanel = panel,
              let closingPanel = notification.object as? NSPanel,
              closingPanel === currentPanel else { return }
        clearPanelIfNeeded(closingPanel)
    }

    private func clearPanelIfNeeded(_ closingPanel: NSPanel) {
        guard let currentPanel = panel,
              closingPanel === currentPanel else { return }

        let frameChange = onExternalFrameChange
        closingPanel.delegate = nil
        panel = nil
        requestedFrame = nil
        onExternalFrameChange = nil
        frameChange?(nil)

        DispatchQueue.main.async {
            closingPanel.contentView = nil
        }
    }

    private func makePanel(size: CGSize) -> TodoFloatingPanel {
        let panel = TodoFloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .mainMenu + 4
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.delegate = self
        return panel
    }

    private func resize(to size: CGSize, animated _: Bool) {
        guard let panel else { return }
        let normalizedSize = CGSize(
            width: max(1, ceil(size.width)),
            height: max(1, ceil(size.height))
        )
        let frame = frame(for: normalizedSize)

        if let requestedFrame, requestedFrame.equalTo(frame) {
            onExternalFrameChange?(frame)
            return
        }

        self.requestedFrame = frame

        guard !panel.frame.equalTo(frame) else {
            onExternalFrameChange?(frame)
            return
        }

        panel.setFrame(frame, display: true)
        onExternalFrameChange?(frame)
    }

    private func frame(for size: CGSize) -> NSRect {
        let margin: CGFloat = 10
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(origin: anchor, size: size)
        }

        var x = anchor.x - size.width + 18
        var y = anchor.y - size.height - 12
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - size.width - margin)
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - size.height - margin)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private struct TodoFloatingPanelRootView: View {
    let tasks: [TodoTask]
    let selectedDate: Date
    let calendar: Calendar
    let cardSize: CGSize
    let onCreate: (TodoCardCreateDraft) -> Void
    let onComplete: (TodoSchedulePreviewItem) -> Void
    let onRestore: (TodoSchedulePreviewItem) -> Void
    let onDelete: (TodoSchedulePreviewItem) -> Void
    let onTodayOnlyChanged: (Bool) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onSizeChange: (CGSize, Bool) -> Void

    @State private var showTodayOnly: Bool
    @State private var activePanel: TodoCardPanel?
    @State private var createDraft: TodoCardCreateDraft

    @AppStorage(TodoCardStorageKeys.sortMode) private var sortModeRaw = TodoSortMode.timeAsc.rawValue
    @AppStorage(TodoCardStorageKeys.showDateSelector) private var showDateSelector = true
    @AppStorage(TodoCardStorageKeys.showTime) private var showTime = true
    @AppStorage(TodoCardStorageKeys.showCategory) private var showCategory = true
    @AppStorage(TodoCardStorageKeys.showCompleted) private var showCompleted = false
    @AppStorage(TodoCardStorageKeys.maxVisibleItems) private var maxVisibleItems = 2
    @AppStorage(TodoCardStorageKeys.defaultRange) private var defaultRangeRaw = TodoDefaultRange.selectedDate.rawValue
    @AppStorage(TodoCardStorageKeys.highlightColor) private var highlightColorRaw = TodoHighlightColor.blue.rawValue
    @AppStorage(TodoCardStorageKeys.useCompactMode) private var useCompactMode = false
    @AppStorage(TodoCardStorageKeys.showEdgeGlow) private var showEdgeGlow = true
    @AppStorage(TodoCardStorageKeys.showReminderBadge) private var showReminderBadge = true
    @AppStorage(TodoCardStorageKeys.dueSoonMinutes) private var dueSoonMinutes = 15

    init(
        tasks: [TodoTask],
        selectedDate: Date,
        showTodayOnly: Bool,
        calendar: Calendar,
        cardSize: CGSize,
        onCreate: @escaping (TodoCardCreateDraft) -> Void,
        onComplete: @escaping (TodoSchedulePreviewItem) -> Void,
        onRestore: @escaping (TodoSchedulePreviewItem) -> Void,
        onDelete: @escaping (TodoSchedulePreviewItem) -> Void,
        onTodayOnlyChanged: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSizeChange: @escaping (CGSize, Bool) -> Void
    ) {
        self.tasks = tasks
        self.selectedDate = selectedDate
        self.calendar = calendar
        self.cardSize = cardSize
        self.onCreate = onCreate
        self.onComplete = onComplete
        self.onRestore = onRestore
        self.onDelete = onDelete
        self.onTodayOnlyChanged = onTodayOnlyChanged
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onSizeChange = onSizeChange
        _showTodayOnly = State(initialValue: showTodayOnly)
        _createDraft = State(initialValue: TodoCardCreateDraft(date: selectedDate, calendar: calendar))
    }

    var body: some View {
        let size = contentSize

        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            .tint(TodoScheduleCardMetrics.selectedBlue)
            .onAppear {
                onSizeChange(size, false)
            }
            .onChange(of: activePanel?.id) { _, _ in
                onSizeChange(contentSize, false)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let activePanel {
            todoPanel(activePanel)
                .transition(panelContentTransition)
        } else {
            TodoMoreMenuView(
                showTodayOnly: showTodayOnly,
                onCreate: openCreatePanel,
                onAll: { openPanel(.all) },
                onTodayOnly: toggleTodayOnly,
                onCompleted: { openPanel(.completed) },
                onSort: { openPanel(.sort) },
                onSettings: { openPanel(.settings) }
            )
            .transition(panelContentTransition)
        }
    }

    private var contentSize: CGSize {
        contentSize(for: activePanel)
    }

    private var panelContentTransition: AnyTransition {
        .identity
    }

    private func contentSize(for panel: TodoCardPanel?) -> CGSize {
        if let panel {
            return CGSize(width: panelWidth, height: panelHeight(for: panel))
        }

        return CGSize(
            width: TodoScheduleCardMetrics.moreMenuWidth,
            height: TodoScheduleCardMetrics.moreMenuHeight
        )
    }

    private var panelWidth: CGFloat {
        max(236, min(360, max(cardSize.width - 4, TodoScheduleCardMetrics.moreMenuWidth)))
    }

    private var sortMode: TodoSortMode {
        TodoSortMode(rawValue: sortModeRaw) ?? .timeAsc
    }

    private var highlightColor: TodoHighlightColor {
        TodoHighlightColor(rawValue: highlightColorRaw) ?? .blue
    }

    private var accentColor: Color {
        switch highlightColor {
        case .blue: TodoScheduleCardMetrics.selectedBlue
        case .purple: Color(red: 0.60, green: 0.39, blue: 1.0)
        case .orange: Color(red: 1.0, green: 0.55, blue: 0.18)
        case .green: Color(red: 0.26, green: 0.78, blue: 0.50)
        }
    }

    @ViewBuilder
    private func todoPanel(_ panel: TodoCardPanel) -> some View {
        switch panel {
        case .create:
            TodoCreateSheetView(
                draft: $createDraft,
                accentColor: accentColor,
                onCancel: onClose,
                onSave: onCreate
            )
        case .all:
            TodoAllListView(
                items: allTodos(),
                accentColor: accentColor,
                onClose: onClose,
                onToggleComplete: onComplete
            )
        case .completed:
            TodoCompletedListView(
                items: completedTodos(),
                accentColor: accentColor,
                onClose: onClose,
                onRestore: onRestore,
                onDelete: onDelete
            )
        case .sort:
            TodoSortMenuView(
                selectedMode: sortMode,
                accentColor: accentColor,
                onSelect: { mode in
                    sortModeRaw = mode.rawValue
                    onClose()
                },
                onClose: onClose
            )
        case .settings:
            TodoCardSettingsView(
                showDateSelector: $showDateSelector,
                showTime: $showTime,
                showCategory: $showCategory,
                showCompleted: $showCompleted,
                maxVisibleItems: $maxVisibleItems,
                defaultRangeRaw: $defaultRangeRaw,
                sortModeRaw: $sortModeRaw,
                highlightColorRaw: $highlightColorRaw,
                useCompactMode: $useCompactMode,
                showEdgeGlow: $showEdgeGlow,
                showReminderBadge: $showReminderBadge,
                dueSoonMinutes: $dueSoonMinutes,
                accentColor: accentColor,
                onClose: onClose,
                onOpenFullSettings: onOpenSettings
            )
        }
    }

    private func panelHeight(for panel: TodoCardPanel) -> CGFloat {
        let cardHeight = max(104, cardSize.height)
        switch panel {
        case .create:
            return max(360, min(390, cardHeight + 210))
        case .all:
            return max(300, min(430, cardHeight + 210))
        case .completed:
            return max(250, min(360, cardHeight + 160))
        case .sort:
            return 268
        case .settings:
            return max(330, min(480, cardHeight + 250))
        }
    }

    private func openCreatePanel() {
        createDraft = TodoCardCreateDraft(date: selectedDate, calendar: calendar)
        openPanel(.create)
    }

    private func openPanel(_ panel: TodoCardPanel) {
        onSizeChange(contentSize(for: panel), false)

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activePanel = panel
        }
    }

    private func toggleTodayOnly() {
        let newValue = !showTodayOnly
        showTodayOnly = newValue
        onTodayOnlyChanged(newValue)
        onClose()
    }

    private func allTodos() -> [TodoSchedulePreviewItem] {
        sortedTasks(tasks.filter { showCompleted || !$0.isCompleted })
            .map { TodoSchedulePreviewItem(task: $0, calendar: calendar) }
    }

    private func completedTodos() -> [TodoSchedulePreviewItem] {
        tasks
            .completedTodoTasks(sortMode: sortMode, calendar: calendar)
            .map { TodoSchedulePreviewItem(task: $0, calendar: calendar) }
    }

    private func sortedTasks(_ source: [TodoTask]) -> [TodoTask] {
        source.sorted { lhs, rhs in
            if !calendar.isDate(lhs.date, inSameDayAs: rhs.date) {
                return lhs.date < rhs.date
            }

            switch sortMode {
            case .timeAsc:
                return (lhs.dueTime ?? lhs.date) < (rhs.dueTime ?? rhs.date)
        case .timeDesc:
            return (lhs.dueTime ?? lhs.date) > (rhs.dueTime ?? rhs.date)
        case .priority:
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return (lhs.dueTime ?? lhs.date) < (rhs.dueTime ?? rhs.date)
        case .createdAt:
            return lhs.createdAt < rhs.createdAt
        }
    }
}
}

private struct TodoDateSelectorView: View {
    let dates: [TodoDateOption]
    let selectedDate: Date
    let isCompact: Bool
    let isNarrow: Bool
    let accentColor: Color
    let onSelect: (Date) -> Void
    @State private var scrollPosition: Date?

    init(
        dates: [TodoDateOption],
        selectedDate: Date,
        isCompact: Bool,
        isNarrow: Bool,
        accentColor: Color,
        onSelect: @escaping (Date) -> Void
    ) {
        self.dates = dates
        self.selectedDate = selectedDate
        self.isCompact = isCompact
        self.isNarrow = isNarrow
        self.accentColor = accentColor
        self.onSelect = onSelect

        let selectedIndex = dates.firstIndex(where: \.isSelected)
        let startIndex = selectedIndex.map { max(dates.startIndex, $0 - 1) }
        _scrollPosition = State(initialValue: startIndex.map { dates[$0].id })
    }

    private var visibleWindowStartDayID: Date? {
        guard let selectedIndex = dates.firstIndex(where: \.isSelected) else { return nil }
        let startIndex = max(dates.startIndex, selectedIndex - 1)
        return dates[startIndex].id
    }

    var body: some View {
        let spacing: CGFloat = isCompact ? 3 : (isNarrow ? 3 : 4)
        let metrics = HorizontalDateStripMetrics(
            visibleItemCount: isNarrow ? 3 : 4,
            spacing: spacing
        )

        GeometryReader { proxy in
            let itemWidth = metrics.itemWidth(for: proxy.size.width)

            ScrollView(.horizontal) {
                LazyHStack(spacing: spacing) {
                    ForEach(dates) { item in
                        dateButton(item)
                            .frame(width: itemWidth)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrollPosition, anchor: .leading)
            .onChange(of: selectedDate) { _, _ in
                withAnimation(.smooth(duration: 0.18, extraBounce: 0)) {
                    scrollPosition = visibleWindowStartDayID
                }
            }
        }
        .frame(height: isCompact ? 28 : (isNarrow ? 30 : 32))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
    }

    private func dateButton(_ item: TodoDateOption) -> some View {
        Button {
            onSelect(item.date)
        } label: {
            HStack(spacing: isCompact ? 2 : 3) {
                Text(item.weekday)
                    .font(.system(size: isCompact ? 8.4 : (isNarrow ? 9 : 9.6), weight: .semibold, design: .rounded))
                    .foregroundStyle(weekdayColor(isSelected: item.isSelected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(item.day)
                    .font(.system(size: isCompact ? 15.5 : (isNarrow ? 17 : 18), weight: .bold, design: .rounded))
                    .foregroundStyle(dayColor(isSelected: item.isSelected))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .shadow(
                        color: item.isSelected ? accentColor.opacity(0.24) : .clear,
                        radius: 5,
                        y: 1
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(accentColor.opacity(item.isSelected ? 0.62 : 0))
                    .frame(width: isCompact ? 12 : 15, height: 2)
                    .blur(radius: item.isSelected ? 3 : 0)
                    .opacity(item.isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private func weekdayColor(isSelected: Bool) -> Color {
        isSelected ? Color.white.opacity(0.93) : Color.white.opacity(0.25)
    }

    private func dayColor(isSelected: Bool) -> Color {
        isSelected ? accentColor : Color.white.opacity(0.32)
    }
}

private struct TodoMoreMenuView: View {
    let showTodayOnly: Bool
    let onCreate: () -> Void
    let onAll: () -> Void
    let onTodayOnly: () -> Void
    let onCompleted: () -> Void
    let onSort: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TodoMoreMenuRow(icon: "plus.circle.fill", title: "新建待办", action: onCreate)
            TodoMoreMenuRow(icon: "list.bullet.rectangle", title: "查看全部", action: onAll)
            TodoMoreMenuRow(icon: "sun.max.fill", title: "仅看今日", trailingIcon: showTodayOnly ? "checkmark" : nil, action: onTodayOnly)

            TodoMenuDivider()

            TodoMoreMenuRow(icon: "checkmark.circle.fill", title: "已完成事项", action: onCompleted)
            TodoMoreMenuRow(icon: "arrow.up.arrow.down.circle.fill", title: "排序方式", action: onSort)
            TodoMoreMenuRow(icon: "slider.horizontal.3", title: "卡片设置", action: onSettings)
        }
        .padding(5)
        .todoGlassPanel(cornerRadius: 18, edgeGlow: true, castsShadow: false)
    }
}

private struct TodoMoreMenuRow: View {
    let icon: String
    let title: String
    var trailingIcon: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(TodoScheduleCardMetrics.selectedBlue.opacity(0.92))
                    .frame(width: 13)

                Text(title)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Spacer(minLength: 2)

                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(TodoScheduleCardMetrics.selectedBlue)
                }
            }
            .frame(height: 34)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.08 : 0.018))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .handCursor()
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct TodoMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }
}

private struct TodoCreateSheetView: View {
    @Binding var draft: TodoCardCreateDraft
    let accentColor: Color
    let onCancel: () -> Void
    let onSave: (TodoCardCreateDraft) -> Void

    @FocusState private var titleFocused: Bool
    @State private var isDateCalendarPresented = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader(title: "新建待办", subtitle: "添加到当前日期", onClose: onCancel)

                TextField("输入待办标题", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(TodoRoundedFieldBackground(isActive: titleFocused, accentColor: accentColor))
                    .focused($titleFocused)

                HStack(spacing: 8) {
                    TodoDateField(
                        date: $draft.date,
                        isCalendarPresented: $isDateCalendarPresented,
                        accentColor: accentColor
                    )

                    Toggle("启用时间", isOn: $draft.hasTime)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .frame(width: 16, height: 28)
                        .help("启用时间")

                    Group {
                        if draft.hasTime {
                            DatePicker("时间", selection: $draft.time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .colorScheme(.dark)
                                .tint(accentColor)
                        } else {
                            Text("时间")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                    }
                    .frame(width: 64, height: 28, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TodoInlinePicker(title: "分组", selection: $draft.category, values: TodoCategory.allCases)
                    TodoInlinePicker(title: "优先级", selection: $draft.priority, values: TodoPriority.allCases)
                }

                TextField("备注，可选", text: $draft.note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .lineLimit(2, reservesSpace: true)
                    .frame(height: 56, alignment: .topLeading)
                    .background(TodoRoundedFieldBackground(isActive: false, accentColor: accentColor))

                Toggle("保存时提醒", isOn: $draft.hasReminder)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))

                HStack(spacing: 8) {
                    Button("取消", action: onCancel)
                        .buttonStyle(TodoPanelButtonStyle(role: .secondary, accentColor: accentColor))
                    Button("保存") { onSave(draft) }
                        .buttonStyle(TodoPanelButtonStyle(role: .primary, accentColor: accentColor))
                        .disabled(!draft.canSave)
                }
            }

            if isDateCalendarPresented {
                TodoDarkCalendarPopover(
                    selectedDate: $draft.date,
                    isPresented: $isDateCalendarPresented,
                    accentColor: accentColor
                )
                .frame(width: 152)
                .offset(x: 0, y: 146)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                .zIndex(2)
            }
        }
        .padding(14)
        .todoGlassPanel(cornerRadius: 22, edgeGlow: true, castsShadow: false)
        .task {
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            titleFocused = true
        }
    }
}

private struct TodoDateField: View {
    @Binding var date: Date
    @Binding var isCalendarPresented: Bool
    let accentColor: Color

    @State private var isFocused = false
    @State private var dateText = ""

    var body: some View {
        HStack(spacing: 2) {
            TodoDateInputField(
                text: $dateText,
                isFocused: $isFocused,
                onCommit: commitDateText
            )
                .padding(.leading, 7)
                .frame(width: 84, height: 32)

            Button {
                commitDateText()
                withAnimation(.smooth(duration: 0.16, extraBounce: 0)) {
                    isCalendarPresented.toggle()
                }
            } label: {
                Image(systemName: isCalendarPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(width: 20, height: 28)
            }
            .buttonStyle(.plain)
            .handCursor()
        }
        .frame(width: 112, height: 34)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isDateActive ? 0.105 : 0.075))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isDateActive
                                ? accentColor.opacity(0.52)
                                : Color.white.opacity(0.09),
                            lineWidth: 0.8
                        )
                }
        }
        .onAppear {
            syncDateText()
        }
        .onChange(of: date) { _, _ in
            syncDateText()
        }
    }

    private var isDateActive: Bool {
        isFocused || isCalendarPresented
    }

    private static func dateText(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d/%02d/%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func syncDateText() {
        let nextText = Self.dateText(for: date)
        guard dateText != nextText else { return }
        dateText = nextText
    }

    private func commitDateText() {
        guard let parsedDate = Self.parseDate(from: dateText) else {
            syncDateText()
            return
        }

        let normalizedDate = Calendar.current.startOfDay(for: parsedDate)
        if !Calendar.current.isDate(normalizedDate, inSameDayAs: date) {
            date = normalizedDate
        } else {
            syncDateText()
        }
    }

    private static func parseDate(from text: String) -> Date? {
        let digits = text.filter(\.isNumber)
        guard digits.count == 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2))
        else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = .current

        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day
        else {
            return nil
        }

        return date
    }
}

private struct TodoDateInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        field.textColor = NSColor.white.withAlphaComponent(0.90)
        field.alignment = .left
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.delegate = context.coordinator
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        field.textColor = NSColor.white.withAlphaComponent(0.90)

        guard field.currentEditor() == nil else { return }
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoDateInputField

        init(parent: TodoDateInputField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
            parent.onCommit()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let textView = field.currentEditor() as? NSTextView
            else { return }

            let rawText = textView.string
            let rawSelection = textView.selectedRange()
            let digitsBeforeCursor = TodoDateInputFormatter.digitCount(
                in: rawText,
                before: rawSelection.location
            )
            let formattedText = TodoDateInputFormatter.formattedDateInput(from: rawText)
            let cursorLocation = TodoDateInputFormatter.cursorLocation(
                afterDigitCount: digitsBeforeCursor,
                in: formattedText
            )

            if rawText != formattedText {
                textView.string = formattedText
                field.stringValue = formattedText
                textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
            }

            if parent.text != formattedText {
                parent.text = formattedText
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            parent.onCommit()
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

private enum TodoDateInputFormatter {
    static func digitCount(in text: String, before offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        let nsText = text as NSString
        let safeOffset = min(offset, nsText.length)
        return nsText.substring(to: safeOffset).filter(\.isNumber).count
    }

    static func formattedDateInput(from text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(8))
        guard !digits.isEmpty else { return "" }
        guard digits.count > 4 else { return digits }

        let year = String(digits.prefix(4))
        let month = String(digits.dropFirst(4).prefix(2))
        guard digits.count > 6 else { return "\(year)/\(month)" }

        let day = String(digits.dropFirst(6).prefix(2))
        return "\(year)/\(month)/\(day)"
    }

    static func cursorLocation(afterDigitCount digitCount: Int, in formattedText: String) -> Int {
        guard digitCount > 0 else { return 0 }

        var seenDigits = 0
        for (offset, character) in formattedText.enumerated() {
            if character.isNumber {
                seenDigits += 1
                if seenDigits == digitCount {
                    return offset + 1
                }
            }
        }

        return formattedText.count
    }
}

private struct TodoDarkCalendarPopover: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    let accentColor: Color

    @State private var displayedMonth = Date()
    @State private var monthSlideDirection = 1

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    Text(monthTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .id(monthPageID)
                        .transition(monthSlideTransition)
                }
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .clipped()

                calendarStepButton(systemName: "chevron.left") {
                    changeMonth(by: -1)
                }

                calendarStepButton(systemName: "chevron.right") {
                    changeMonth(by: 1)
                }
            }

            ZStack(alignment: .top) {
                monthPage
                    .id(monthPageID)
                    .transition(monthSlideTransition)
            }
            .frame(height: calendarPageHeight)
            .clipped()
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.050, green: 0.055, blue: 0.064),
                            Color(red: 0.014, green: 0.016, blue: 0.020)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.16),
                                    accentColor.opacity(0.24),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
        }
        .onAppear {
            displayedMonth = monthStart(for: selectedDate)
        }
    }

    private var monthPage: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 7),
                spacing: 1.5
            ) {
                ForEach(calendarDays) { day in
                    dayButton(day)
                }
            }
        }
    }

    private var monthTitle: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 1)月"
    }

    private var monthPageID: String {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(components.year ?? 0)-\(components.month ?? 1)"
    }

    private var monthSlideTransition: AnyTransition {
        let insertionEdge: Edge = monthSlideDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = monthSlideDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var calendarDays: [TodoCalendarDay] {
        let monthStart = monthStart(for: displayedMonth)
        let weekday = calendar.component(.weekday, from: monthStart)
        let firstGridDate = calendar.date(
            byAdding: .day,
            value: -(weekday - 1),
            to: monthStart
        ) ?? monthStart

        return (0..<(calendarWeekCount * 7)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstGridDate) else {
                return nil
            }

            return TodoCalendarDay(
                date: date,
                isCurrentMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    private var calendarWeekCount: Int {
        let monthStart = monthStart(for: displayedMonth)
        let leadingDayCount = calendar.component(.weekday, from: monthStart) - 1
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        return min(6, max(4, (leadingDayCount + dayCount + 6) / 7))
    }

    private var calendarPageHeight: CGFloat {
        let dayRowHeight: CGFloat = 16
        let gridSpacing: CGFloat = 1.5
        let weekdayAndSectionHeight: CGFloat = 14
        return weekdayAndSectionHeight
            + CGFloat(calendarWeekCount) * dayRowHeight
            + CGFloat(max(0, calendarWeekCount - 1)) * gridSpacing
    }

    private func dayButton(_ day: TodoCalendarDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day.date)

        return Button {
            selectedDate = calendar.startOfDay(for: day.date)
            withAnimation(.easeOut(duration: 0.12)) {
                isPresented = false
            }
        } label: {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.system(size: 8.8, weight: isSelected ? .bold : .semibold, design: .rounded))
                .foregroundStyle(dayTextColor(day: day, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(0.90) : Color.white.opacity(isToday ? 0.075 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isToday && !isSelected ? accentColor.opacity(0.32) : .clear, lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private func calendarStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.70))
                .frame(width: 18, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    private func dayTextColor(day: TodoCalendarDay, isSelected: Bool) -> Color {
        if isSelected { return Color.white.opacity(0.96) }
        return day.isCurrentMonth ? Color.white.opacity(0.84) : Color.white.opacity(0.24)
    }

    private func changeMonth(by offset: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }

        monthSlideDirection = offset > 0 ? 1 : -1
        withAnimation(.smooth(duration: 0.20, extraBounce: 0)) {
            displayedMonth = monthStart(for: nextMonth)
        }
    }

    private func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

private struct TodoCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool

    var id: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct TodoAllListView: View {
    let items: [TodoSchedulePreviewItem]
    let accentColor: Color
    let onClose: () -> Void
    let onToggleComplete: (TodoSchedulePreviewItem) -> Void

    @State private var query = ""
    @State private var showsCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "全部待办", subtitle: "\(filteredItems.count) 项", onClose: onClose)

            HStack(spacing: 8) {
                Label("搜索", systemImage: "magnifyingglass")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
                TextField("搜索待办", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(TodoRoundedFieldBackground(isActive: false, accentColor: accentColor))

            TodoStatusSegmentedControl(showsCompleted: $showsCompleted, accentColor: accentColor)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedItems, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.38))
                            ForEach(group.items) { item in
                                TodoFullListRow(item: item, accentColor: accentColor, onToggleComplete: onToggleComplete)
                            }
                        }
                    }

                    if filteredItems.isEmpty {
                        TodoPanelEmptyState(title: showsCompleted ? "暂无已完成事项" : "暂无待办")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .todoGlassPanel(cornerRadius: 22, edgeGlow: true, castsShadow: false)
    }

    private var filteredItems: [TodoSchedulePreviewItem] {
        items.filter { item in
            item.isCompleted == showsCompleted
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query))
        }
    }

    private var groupedItems: [(title: String, items: [TodoSchedulePreviewItem])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        let buckets: [(String, (TodoSchedulePreviewItem) -> Bool)] = [
            ("今天", { calendar.isDate($0.date, inSameDayAs: today) }),
            ("明天", { calendar.isDate($0.date, inSameDayAs: tomorrow) }),
            ("本周", { item in
                guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return false }
                return week.contains(item.date) && !calendar.isDate(item.date, inSameDayAs: today) && !calendar.isDate(item.date, inSameDayAs: tomorrow)
            }),
            ("之后", { item in
                guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return true }
                return item.date >= week.end
            })
        ]

        return buckets.compactMap { bucket in
            let groupItems = filteredItems.filter(bucket.1)
            return groupItems.isEmpty ? nil : (bucket.0, groupItems)
        }
    }
}

private struct TodoStatusSegmentedControl: View {
    @Binding var showsCompleted: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("状态")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))

            HStack(spacing: 2) {
                statusButton(title: "未完成", isCompleted: false)
                statusButton(title: "已完成", isCompleted: true)
            }
            .padding(3)
            .frame(maxWidth: 252)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.055), lineWidth: 0.7)
                    }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func statusButton(title: String, isCompleted: Bool) -> some View {
        let isSelected = showsCompleted == isCompleted

        return Button {
            guard showsCompleted != isCompleted else { return }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showsCompleted = isCompleted
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.white.opacity(0.96) : Color.white.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? accentColor.opacity(0.78) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .handCursor()
    }
}

private struct TodoCompletedListView: View {
    let items: [TodoSchedulePreviewItem]
    let accentColor: Color
    let onClose: () -> Void
    let onRestore: (TodoSchedulePreviewItem) -> Void
    let onDelete: (TodoSchedulePreviewItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "已完成事项", subtitle: "\(items.count) 项", onClose: onClose)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.58))
                                    .lineLimit(1)
                                Text(item.time.isEmpty ? "已完成" : item.time)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.30))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Button("恢复") { onRestore(item) }
                                    .buttonStyle(TodoPanelCompactButtonStyle(role: .secondary, accentColor: accentColor))
                                    .frame(width: 52)
                                Button("删除") { onDelete(item) }
                                    .buttonStyle(TodoPanelCompactButtonStyle(role: .danger, accentColor: accentColor))
                                    .frame(width: 52)
                            }
                            .frame(width: 112, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(TodoListRowBackground())
                    }

                    if items.isEmpty {
                        TodoPanelEmptyState(title: "暂无已完成事项")
                    }
                }
            }
        }
        .padding(14)
        .todoGlassPanel(cornerRadius: 22, edgeGlow: true, castsShadow: false)
    }
}

private struct TodoSortMenuView: View {
    let selectedMode: TodoSortMode
    let accentColor: Color
    let onSelect: (TodoSortMode) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelHeader(title: "排序方式", subtitle: "点击后立即生效", onClose: onClose)

            VStack(spacing: 4) {
                ForEach(TodoSortMode.allCases, id: \.self) { mode in
                    Button { onSelect(mode) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: sortIcon(for: mode))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(mode == selectedMode ? accentColor : Color.white.opacity(0.44))
                                .frame(width: 16)
                            Text(mode.title)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(mode == selectedMode ? 0.92 : 0.66))
                            Spacer()
                            if mode == selectedMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(accentColor)
                            }
                        }
                        .frame(height: 38)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(mode == selectedMode ? accentColor.opacity(0.13) : Color.white.opacity(0.018))
                        }
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
            }
        }
        .padding(14)
        .todoGlassPanel(cornerRadius: 22, edgeGlow: true, castsShadow: false)
    }

    private func sortIcon(for mode: TodoSortMode) -> String {
        switch mode {
        case .timeAsc: "clock.arrow.circlepath"
        case .timeDesc: "clock.badge.checkmark"
        case .priority: "exclamationmark.triangle.fill"
        case .createdAt: "calendar.badge.clock"
        }
    }
}

private struct TodoCardSettingsView: View {
    @Binding var showDateSelector: Bool
    @Binding var showTime: Bool
    @Binding var showCategory: Bool
    @Binding var showCompleted: Bool
    @Binding var maxVisibleItems: Int
    @Binding var defaultRangeRaw: String
    @Binding var sortModeRaw: String
    @Binding var highlightColorRaw: String
    @Binding var useCompactMode: Bool
    @Binding var showEdgeGlow: Bool
    @Binding var showReminderBadge: Bool
    @Binding var dueSoonMinutes: Int

    let accentColor: Color
    let onClose: () -> Void
    let onOpenFullSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "卡片设置", subtitle: "显示、筛选、排序与视觉", onClose: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSection("显示设置") {
                        TodoSettingsToggle(title: "显示日期选择器", isOn: $showDateSelector, accentColor: accentColor)
                        TodoSettingsToggle(title: "显示时间", isOn: $showTime, accentColor: accentColor)
                        TodoSettingsToggle(title: "显示标签", isOn: $showCategory, accentColor: accentColor)
                        TodoSettingsToggle(title: "显示已完成事项", isOn: $showCompleted, accentColor: accentColor)
                        Stepper("最大显示数量：\(maxVisibleItems)", value: $maxVisibleItems, in: 1...4)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.70))
                    }

                    settingsSection("筛选设置") {
                        TodoRawPicker<TodoDefaultRange>(title: "默认显示范围", selection: $defaultRangeRaw, values: TodoDefaultRange.allCases)
                    }

                    settingsSection("排序设置") {
                        TodoRawPicker<TodoSortMode>(title: "默认排序方式", selection: $sortModeRaw, values: TodoSortMode.allCases)
                    }

                    settingsSection("视觉设置") {
                        TodoRawPicker<TodoHighlightColor>(title: "高亮颜色", selection: $highlightColorRaw, values: TodoHighlightColor.allCases)
                        TodoSettingsToggle(title: "边缘光", isOn: $showEdgeGlow, accentColor: accentColor)
                        TodoSettingsToggle(title: "紧凑模式", isOn: $useCompactMode, accentColor: accentColor)
                    }

                    settingsSection("提醒设置") {
                        TodoSettingsToggle(title: "显示提醒标识", isOn: $showReminderBadge, accentColor: accentColor)
                        Picker("即将到期", selection: $dueSoonMinutes) {
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                            Text("30 分钟").tag(30)
                            Text("1 小时").tag(60)
                        }
                        .colorScheme(.dark)
                        .tint(accentColor)
                    }
                }
            }

            Button("打开完整设置") {
                onClose()
                onOpenFullSettings()
            }
            .buttonStyle(TodoPanelCompactButtonStyle(role: .secondary, accentColor: accentColor))
        }
        .padding(14)
        .todoGlassPanel(cornerRadius: 22, edgeGlow: true, castsShadow: false)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.36))
            content()
        }
        .padding(10)
        .background(TodoListRowBackground())
    }
}

private struct TodoRawPicker<Value>: View where Value: RawRepresentable & CaseIterable & Hashable, Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: String
    let values: Value.AllCases

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value.rawValue
                    } label: {
                        HStack {
                            Text(displayTitle(for: value))
                            if value.rawValue == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .frame(width: 132, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.045), lineWidth: 0.7)
                        }
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .focusable(false)
            .handCursor()
        }
    }

    private var selectedTitle: String {
        guard let value = values.first(where: { $0.rawValue == selection }) else {
            return selection
        }

        return displayTitle(for: value)
    }

    private func displayTitle(for value: Value) -> String {
        if let mode = value as? TodoSortMode { return mode.title }
        if let range = value as? TodoDefaultRange { return range.title }
        if let color = value as? TodoHighlightColor { return color.title }
        return value.rawValue
    }
}

private struct TodoSettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
    let accentColor: Color

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(TodoAccentSwitchToggleStyle(accentColor: accentColor))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.70))
    }
}

private struct TodoAccentSwitchToggleStyle: ToggleStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? accentColor.opacity(0.82) : Color.white.opacity(0.12))
                        .overlay {
                            Capsule()
                                .stroke(configuration.isOn ? accentColor.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 0.7)
                        }

                    Circle()
                        .fill(Color.white.opacity(configuration.isOn ? 0.96 : 0.76))
                        .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
                .frame(width: 44, height: 24)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .handCursor()
        }
    }
}

private struct TodoInlinePicker<Value>: View where Value: CaseIterable & Hashable, Value.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Value
    let values: Value.AllCases

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))

            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        HStack {
                            Text(displayTitle(for: value))
                            if value == selection {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(displayTitle(for: selection))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 70)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                }
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .focusable(false)
            .handCursor()
        }
        .frame(maxWidth: .infinity)
    }

    private func displayTitle(for value: Value) -> String {
        if let category = value as? TodoCategory { return category.title }
        if let priority = value as? TodoPriority { return priority.title }
        return String(describing: value)
    }
}

private struct TodoListPreviewView: View {
    let items: [TodoSchedulePreviewItem]
    let isCompact: Bool
    let maxVisibleItems: Int
    let showTime: Bool
    let showCategory: Bool
    let accentColor: Color
    let todayFooterText: String?
    let onComplete: (TodoSchedulePreviewItem) -> Void

    private var displayLimit: Int {
        max(1, maxVisibleItems)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : TodoScheduleCardMetrics.rowSpacing) {
            if items.isEmpty {
                Text("暂无已安排待办")
                    .font(.system(size: isCompact ? 12.5 : 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .padding(.top, isCompact ? 1 : 5)
            } else {
                ForEach(items.prefix(displayLimit)) { item in
                    TodoListPreviewRow(
                        item: item,
                        isCompact: isCompact,
                        showTime: showTime,
                        showCategory: showCategory,
                        accentColor: accentColor,
                        onComplete: onComplete
                    )
                    .transition(.opacity.combined(with: .offset(y: 5)))
                }

                let remainingCount = max(0, items.count - displayLimit)
                if let todayFooterText {
                    Text(todayFooterText)
                        .font(.system(size: isCompact ? 8.5 : 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor.opacity(0.78))
                        .lineLimit(1)
                        .padding(.top, isCompact ? 0 : 1)
                } else if remainingCount > 0 {
                    Text("还有 \(remainingCount) 项")
                        .font(.system(size: isCompact ? 8.5 : 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor.opacity(0.78))
                        .lineLimit(1)
                        .padding(.top, isCompact ? 0 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodoListPreviewRow: View {
    let item: TodoSchedulePreviewItem
    let isCompact: Bool
    let showTime: Bool
    let showCategory: Bool
    let accentColor: Color
    let onComplete: (TodoSchedulePreviewItem) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 6 : 8) {
            Button { onComplete(item) } label: {
                ZStack {
                    Circle()
                        .fill(item.isCompleted ? Color.white.opacity(0.16) : accentColor.opacity(0.82))
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(item.isCompleted ? 0.24 : 0.18), lineWidth: 0.7)
                        }
                    if item.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: isCompact ? 5.8 : 6.4, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.70))
                    }
                }
                .frame(width: isCompact ? 12 : 14, height: isCompact ? 12 : 14)
            }
            .buttonStyle(.plain)
            .handCursor()
            .disabled(item.isCompleted)

            Text(item.title)
                .font(.system(size: isCompact ? 10.5 : 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(item.isCompleted ? 0.42 : 0.86))
                .lineLimit(1)
                .strikethrough(item.isCompleted, color: Color.white.opacity(0.30))
                .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if showTime, !item.time.isEmpty {
                    Text(item.time)
                }
                if showCategory, item.category != .none {
                    Text(item.category.title)
                }
                if item.priority != .normal {
                    Text(item.priority.title)
                        .foregroundStyle(accentColor.opacity(0.72))
                }
            }
            .font(.system(size: isCompact ? 8.5 : 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(item.isCompleted ? 0.25 : 0.50))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 20 : 24, alignment: .leading)
    }
}

private struct TodoFullListRow: View {
    let item: TodoSchedulePreviewItem
    let accentColor: Color
    let onToggleComplete: (TodoSchedulePreviewItem) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button { onToggleComplete(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.white.opacity(0.42) : accentColor)
            }
            .buttonStyle(.plain)
            .handCursor()
            .disabled(item.isCompleted)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(item.isCompleted ? 0.44 : 0.86))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !item.time.isEmpty { Text(item.time) }
                    if item.category != .none { Text(item.category.title) }
                    if item.priority != .normal { Text(item.priority.title) }
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.22))
        }
        .padding(10)
        .background(TodoListRowBackground())
    }
}

private struct TodoPanelEmptyState: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.34))
            .frame(maxWidth: .infinity, minHeight: 70)
    }
}

private func panelHeader(title: String, subtitle: String, onClose: @escaping () -> Void) -> some View {
    HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.36))
        }
        Spacer()
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

private struct TodoRoundedFieldBackground: View {
    let isActive: Bool
    let accentColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? accentColor.opacity(0.45) : Color.white.opacity(0.09), lineWidth: 0.8)
            }
    }
}

private struct TodoListRowBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
            }
    }
}

private struct TodoPanelButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
        case danger
    }

    let role: Role
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(role == .primary ? Color.white.opacity(0.95) : Color.white.opacity(0.76))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fillColor.opacity(configuration.isPressed ? 0.72 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var fillColor: Color {
        switch role {
        case .primary: accentColor.opacity(0.72)
        case .secondary: Color.white.opacity(0.075)
        case .danger: Color.red.opacity(0.34)
        }
    }
}

private struct TodoPanelCompactButtonStyle: ButtonStyle {
    let role: TodoPanelButtonStyle.Role
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.76))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fillColor.opacity(configuration.isPressed ? 0.72 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var fillColor: Color {
        switch role {
        case .primary: accentColor.opacity(0.72)
        case .secondary: Color.white.opacity(0.070)
        case .danger: Color.red.opacity(0.30)
        }
    }
}

private struct TodoGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let edgeGlow: Bool
    let castsShadow: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.030, green: 0.033, blue: 0.038),
                                Color(red: 0.006, green: 0.007, blue: 0.010)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        TodoScheduleCardMetrics.selectedBlue.opacity(edgeGlow ? 0.24 : 0.06),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.9
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(castsShadow ? 0.42 : 0),
                        radius: castsShadow ? 18 : 0,
                        y: castsShadow ? 10 : 0
                    )
                    .shadow(
                        color: TodoScheduleCardMetrics.selectedBlue.opacity(castsShadow && edgeGlow ? 0.16 : 0),
                        radius: castsShadow ? 16 : 0,
                        y: castsShadow ? 2 : 0
                    )
            }
    }
}

private struct ModuleCardClipModifier: ViewModifier {
    let shape: RoundedRectangle
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .clipShape(shape)
                .clipped()
        } else {
            content
        }
    }
}

private extension View {
    func moduleCardClip(_ shape: RoundedRectangle, isEnabled: Bool) -> some View {
        modifier(ModuleCardClipModifier(shape: shape, isEnabled: isEnabled))
    }

    func todoGlassPanel(cornerRadius: CGFloat, edgeGlow: Bool, castsShadow: Bool = true) -> some View {
        modifier(TodoGlassPanelModifier(cornerRadius: cornerRadius, edgeGlow: edgeGlow, castsShadow: castsShadow))
    }
}

struct DeviceInfoSnapshot: Sendable {
    var cpuPercent: Int
    var memoryPercent: Int
    var diskPercent: Int
    var usedDiskText: String
    var totalDiskText: String
    var uploadBytesPerSecond: UInt64
    var downloadBytesPerSecond: UInt64

    static let placeholder = DeviceInfoSnapshot(
        cpuPercent: 0,
        memoryPercent: 0,
        diskPercent: 0,
        usedDiskText: "--",
        totalDiskText: "--",
        uploadBytesPerSecond: 0,
        downloadBytesPerSecond: 0
    )
}

private struct DeviceInfoCPUCoreLoad: Sendable {
    var user: UInt64
    var system: UInt64
    var nice: UInt64
    var idle: UInt64
}

private struct DeviceInfoNetworkSample: Sendable {
    var received: UInt64
    var sent: UInt64
    var date: Date
}

private struct DeviceInfoSampleState: Sendable {
    var cpuLoads: [DeviceInfoCPUCoreLoad] = []
    var networkSample: DeviceInfoNetworkSample?
}

@MainActor
final class DeviceInfoProvider: ObservableObject {
    @Published private(set) var snapshot = DeviceInfoSnapshot.placeholder

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var sampleState = DeviceInfoSampleState()

    deinit {
        timer?.invalidate()
        refreshTask?.cancel()
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        sampleState = DeviceInfoSampleState()
    }

    func refresh() {
        guard refreshTask == nil else { return }

        let previousSnapshot = snapshot
        let state = sampleState
        refreshTask = Task { @MainActor in
            let result = await Task.detached(priority: .utility) {
                DeviceInfoProvider.makeSnapshot(previousSnapshot: previousSnapshot, state: state)
            }.value

            guard !Task.isCancelled else { return }
            snapshot = result.snapshot
            sampleState = result.state
            refreshTask = nil
        }
    }

    nonisolated private static func makeSnapshot(
        previousSnapshot: DeviceInfoSnapshot,
        state: DeviceInfoSampleState
    ) -> (snapshot: DeviceInfoSnapshot, state: DeviceInfoSampleState) {
        var nextState = state
        let cpu = cpuUsagePercent(previousLoads: state.cpuLoads, fallback: previousSnapshot.cpuPercent)
        nextState.cpuLoads = cpu.loads

        let disk = diskUsage(fallback: previousSnapshot)
        let network = networkSpeed(
            previousSample: state.networkSample,
            fallbackUpload: previousSnapshot.uploadBytesPerSecond,
            fallbackDownload: previousSnapshot.downloadBytesPerSecond
        )
        nextState.networkSample = network.sample

        let snapshot = DeviceInfoSnapshot(
            cpuPercent: cpu.percent,
            memoryPercent: memoryUsagePercent(fallback: previousSnapshot.memoryPercent),
            diskPercent: disk.percent,
            usedDiskText: disk.used,
            totalDiskText: disk.total,
            uploadBytesPerSecond: network.upload,
            downloadBytesPerSecond: network.download
        )

        return (snapshot, nextState)
    }

    nonisolated private static func cpuUsagePercent(
        previousLoads: [DeviceInfoCPUCoreLoad],
        fallback: Int
    ) -> (percent: Int, loads: [DeviceInfoCPUCoreLoad]) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return (fallback, previousLoads)
        }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let currentLoads = (0..<Int(cpuCount)).map { cpu in
            let offset = Int(CPU_STATE_MAX) * cpu
            return DeviceInfoCPUCoreLoad(
                user: unsignedCounter(cpuInfo[offset + Int(CPU_STATE_USER)]),
                system: unsignedCounter(cpuInfo[offset + Int(CPU_STATE_SYSTEM)]),
                nice: unsignedCounter(cpuInfo[offset + Int(CPU_STATE_NICE)]),
                idle: unsignedCounter(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            )
        }

        guard previousLoads.count == currentLoads.count else {
            return (fallback, currentLoads)
        }

        var totalUsage: Double = 0
        for index in currentLoads.indices {
            let current = currentLoads[index]
            let previous = previousLoads[index]
            let user = Double(counterDelta(current.user, previous.user))
            let system = Double(counterDelta(current.system, previous.system))
            let nice = Double(counterDelta(current.nice, previous.nice))
            let idle = Double(counterDelta(current.idle, previous.idle))
            let total = user + system + nice + idle
            if total > 0 {
                totalUsage += (total - idle) / total
            }
        }

        let average = totalUsage / Double(max(1, currentLoads.count))
        return (Int((average * 100).rounded()).clamped(to: 0...100), currentLoads)
    }

    nonisolated private static func memoryUsagePercent(fallback: Int) -> Int {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64()

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return fallback }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        guard total > 0 else { return fallback }
        let reclaimablePages = UInt64(stats.free_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.speculative_count)
        let reclaimable = min(total, reclaimablePages * pageSize)
        let used = total - reclaimable
        return Int((Double(used) / Double(total) * 100).rounded()).clamped(to: 0...100)
    }

    nonisolated private static func networkSpeed(
        previousSample: DeviceInfoNetworkSample?,
        fallbackUpload: UInt64,
        fallbackDownload: UInt64
    ) -> (upload: UInt64, download: UInt64, sample: DeviceInfoNetworkSample?) {
        guard let totals = networkByteTotals() else {
            return (fallbackUpload, fallbackDownload, previousSample)
        }

        let now = Date()
        let nextSample = DeviceInfoNetworkSample(received: totals.received, sent: totals.sent, date: now)

        guard let previousSample else { return (0, 0, nextSample) }
        let elapsed = now.timeIntervalSince(previousSample.date)
        guard elapsed > 0 else { return (0, 0, nextSample) }

        let receivedDelta = totals.received >= previousSample.received
            ? totals.received - previousSample.received
            : 0
        let sentDelta = totals.sent >= previousSample.sent
            ? totals.sent - previousSample.sent
            : 0
        return (
            UInt64((Double(sentDelta) / elapsed).rounded()),
            UInt64((Double(receivedDelta) / elapsed).rounded()),
            nextSample
        )
    }

    nonisolated private static func networkByteTotals() -> (received: UInt64, sent: UInt64)? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var address: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = address {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let isActive = (interface.ifa_flags & UInt32(IFF_UP)) != 0
            let isLinkLayer = interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)

            if isActive, isLinkLayer, name.hasPrefix("en"), let data = interface.ifa_data {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(counters.ifi_ibytes)
                sent += UInt64(counters.ifi_obytes)
            }
            address = interface.ifa_next
        }

        return (received, sent)
    }

    nonisolated private static func diskUsage(fallback: DeviceInfoSnapshot) -> (percent: Int, used: String, total: String) {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            )
            let available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            guard total > 0 else { return (fallback.diskPercent, fallback.usedDiskText, fallback.totalDiskText) }

            let used = total > available ? total - available : 0
            let percent = Int((Double(used) / Double(total) * 100).rounded()).clamped(to: 0...100)
            return (percent, formattedBytes(used), formattedBytes(total))
        } catch {
            return (fallback.diskPercent, fallback.usedDiskText, fallback.totalDiskText)
        }
    }

    nonisolated private static func formattedBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 999 {
            let tb = gb / 1000
            return tb >= 10 ? "\(Int(tb.rounded()))T" : String(format: "%.1fT", tb)
        }

        return "\(Int(gb.rounded()))G"
    }

    nonisolated private static func unsignedCounter(_ value: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }

    nonisolated private static func counterDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum IslandPanelModule: String, CaseIterable, Identifiable {
    case weather
    case calendar
    case todo
    case media
    case quickApps
    case shortcuts
    case imageCard
    case deviceInfo

    var id: Self { self }

    var title: String {
        switch self {
        case .weather: "天气"
        case .calendar: "日历"
        case .todo: "待办"
        case .media: "播放"
        case .quickApps: "快捷应用"
        case .shortcuts: "快捷指令"
        case .imageCard: "图片卡片"
        case .deviceInfo: "设备信息"
        }
    }

    var systemName: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .calendar: "calendar"
        case .todo: "checklist"
        case .media: "waveform"
        case .quickApps: "square.grid.3x2"
        case .shortcuts: "arrow.down.circle.fill"
        case .imageCard: "photo"
        case .deviceInfo: "desktopcomputer"
        }
    }
}

enum AppCachedImageAssets {
    static let finderIcon: NSImage? = Bundle.main
        .path(forResource: "finder_icon", ofType: "png")
        .flatMap(NSImage.init(contentsOfFile:))
}

private struct FinderGlyph: View {
    var body: some View {
        if let image = AppCachedImageAssets.finderIcon {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.cyan)
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Path { path in
                    path.move(to: CGPoint(x: 21, y: 7))
                    path.addLine(to: CGPoint(x: 21, y: 35))
                    path.move(to: CGPoint(x: 9, y: 22))
                    path.addQuadCurve(to: CGPoint(x: 21, y: 27), control: CGPoint(x: 15, y: 29))
                    path.addQuadCurve(to: CGPoint(x: 33, y: 22), control: CGPoint(x: 27, y: 29))
                }
                .stroke(Color.black.opacity(0.76), lineWidth: 1.4)
            }
        }
    }
}

private struct CalendarMonthDay: Identifiable {
    let id: String
    let date: Date?
    let day: Int?
    let isToday: Bool
}

private struct CalendarWeekDay: Identifiable {
    let id: TimeInterval
    let date: Date
    let weekday: String
    let day: Int
    let isToday: Bool
}

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let startOfDay = startOfDay(for: date)
        let weekday = component(.weekday, from: startOfDay)
        return self.date(byAdding: .day, value: 1 - weekday, to: startOfDay) ?? startOfDay
    }
}

enum IslandTopTab: CaseIterable, Identifiable {
    case home
    case applications
    case files

    var id: Self { self }

    var title: String {
        switch self {
        case .home: IslandDesignTokens.appName
        case .applications: "应用程序"
        case .files: "文件"
        }
    }

    var imageName: String? {
        switch self {
        case .home: nil
        case .applications: "application"
        case .files: "folder"
        }
    }

    var fallbackSystemName: String {
        switch self {
        case .home: "circle.grid.2x2.fill"
        case .applications: "app.fill"
        case .files: "folder.fill"
        }
    }
}

private struct TopTabButton: View {
    let tab: IslandTopTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            tabContent
                .frame(height: IslandDesignTokens.expandedTopBarControlHeight)
                .padding(.horizontal, horizontalPadding)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .handCursor()
        .animation(IslandDesignTokens.tabSwitchAnimation, value: isSelected)
        .animation(AppMotion.quick, value: isHovering)
        .help(tab.title)
    }

    private var horizontalPadding: CGFloat {
        tab == .home ? 18 : 8
    }

    @ViewBuilder
    private var tabContent: some View {
        if tab == .home {
            Text(tab.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : Color.white.opacity(isHovering ? 0.76 : 0.48)
                )
                .shadow(
                    color: Color.white.opacity(isSelected ? 0.14 : 0),
                    radius: isSelected ? 3 : 0
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else if let imageName = tab.imageName, let image = BundleImageLoader.image(named: imageName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .brightness(isSelected ? 0.16 : (isHovering ? 0.06 : -0.10))
                .saturation(isSelected ? 1.06 : (isHovering ? 0.90 : 0.62))
                .opacity(isSelected ? 1 : (isHovering ? 0.82 : 0.48))
                .shadow(
                    color: Color.white.opacity(isSelected ? 0.12 : 0),
                    radius: isSelected ? 4 : 0
                )
        } else {
            Image(systemName: tab.fallbackSystemName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : Color.white.opacity(isHovering ? 0.76 : 0.48)
                )
                .shadow(
                    color: Color.white.opacity(isSelected ? 0.14 : 0),
                    radius: isSelected ? 3 : 0
                )
        }
    }
}

private struct TodoCompletionButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(isHovering ? 0.70 : 0.38), lineWidth: 1.25)

                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isHovering ? 0.92 : 0))
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .handCursor()
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("完成待办")
    }
}

private struct MusicLyricsPlaybackCard: View {
    let playback: PlaybackSnapshot
    let diagnosticText: String
    let lyricText: String
    let progress: Double
    let availableHeight: CGFloat
    let showsTrackName: Bool
    let showsLyrics: Bool
    let onScrubStarted: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void

    private var titleFontSize: CGFloat {
        min(16, max(13, availableHeight / 8.8))
    }

    private var artistFontSize: CGFloat {
        min(11.5, max(9.5, availableHeight / 14.5))
    }

    private var timeFontSize: CGFloat {
        min(9.5, max(8, availableHeight / 18.0))
    }

    private var lyricFontSize: CGFloat {
        min(11.8, max(10.2, availableHeight / 14.5))
    }

    private var informationHeight: CGFloat {
        let titleHeight = ceil(titleFontSize * 1.24)
        let artistHeight = ceil(artistFontSize * 1.24)
        let lyricHeight = ceil(lyricFontSize * 1.28)
        let controlsHeight: CGFloat = 26
        let progressHeight: CGFloat = 8
        let timeHeight = ceil(timeFontSize * 1.25)
        let fixedSpacing: CGFloat = 3 + 5 + 4 + 2
        return titleHeight + artistHeight + lyricHeight
            + controlsHeight + progressHeight + timeHeight + fixedSpacing
    }

    private func cardHeight(for containerWidth: CGFloat) -> CGFloat {
        let heightBound = max(100, availableHeight - 2)
        let widthBound = max(100, containerWidth * 0.40)
        return min(informationHeight, min(heightBound, widthBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let height = cardHeight(for: proxy.size.width)
            cardContent(cardHeight: height, containerWidth: proxy.size.width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardContent(cardHeight: CGFloat, containerWidth: CGFloat) -> some View {
        if !playback.isLive {
            MusicIdleLaunchCard(
                availableHeight: availableHeight,
                diagnosticText: diagnosticText
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let artworkSize = max(1, cardHeight - 2)
            let contentSpacing: CGFloat = 11
            let availableInformationWidth = max(1, containerWidth - artworkSize - contentSpacing)
            let preferredInformationWidth = availableInformationWidth * 0.82
            let informationWidth = min(
                availableInformationWidth,
                min(max(190, preferredInformationWidth), 286)
            )

            HStack(alignment: .top, spacing: contentSpacing) {
                Button(action: onTogglePlayback) {
                    MusicArtworkCover(
                        source: playback.artworkSource,
                        appName: playback.appName,
                        state: playback.state,
                        isLive: playback.isLive,
                        width: artworkSize,
                        height: artworkSize
                    )
                }
                .buttonStyle(.plain)
                .handCursor()
                .help(playback.state == .playing ? "暂停播放" : "播放")

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        MarqueeText(
                            text: showsTrackName ? playback.title : playback.appName,
                            font: .system(size: max(1, titleFontSize - 1), weight: .bold, design: .rounded),
                            color: Color.white.opacity(playback.isLive ? 0.96 : 0.55),
                            speed: 28,
                            startDelay: 1.5,
                            endDelay: 1.5
                        )
                        .frame(maxWidth: .infinity, minHeight: ceil(titleFontSize * 1.24), alignment: .leading)
                        .layoutPriority(1)

                        MusicPlaybackStateGlyph(playback: playback)
                            .frame(width: 17, height: 14)
                            .fixedSize()
                            .offset(y: -4)
                    }

                    Text(artistText)
                        .font(.system(size: artistFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 3)

                    if showsLyrics {
                        MusicLyricMarqueeText(
                            text: lyricText,
                            fontSize: lyricFontSize,
                            color: Color.white.opacity(0.78)
                        )
                            .frame(maxWidth: .infinity, minHeight: ceil(lyricFontSize * 1.28), alignment: .leading)
                            .padding(.top, 5)
                    }

                    HStack(spacing: 0) {
                        MusicTransportIconButton(
                            systemName: "backward.fill",
                            help: "上一首",
                            isEnabled: playback.isLive,
                            size: 24,
                            iconSize: 10,
                            showsBackground: false,
                            action: onPrevious
                        )
                        .frame(maxWidth: .infinity)

                        MusicTransportIconButton(
                            systemName: playback.state.controlSymbolName,
                            help: playback.state == .playing ? "暂停播放" : "播放",
                            isEnabled: true,
                            size: 26,
                            iconSize: 11,
                            showsBackground: false,
                            action: onTogglePlayback
                        )
                        .frame(maxWidth: .infinity)

                        MusicTransportIconButton(
                            systemName: "forward.fill",
                            help: "下一首",
                            isEnabled: playback.isLive,
                            size: 24,
                            iconSize: 10,
                            showsBackground: false,
                            action: onNext
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    MusicProgressScrubber(
                        progress: progress,
                        isEnabled: playback.canSeek,
                        onScrubStarted: onScrubStarted,
                        onScrubChanged: onScrubChanged,
                        onScrubEnded: onScrubEnded
                    )
                    .frame(height: 8)

                    HStack {
                        Text(playback.elapsedText(for: progress))
                        Spacer(minLength: 8)
                        Text(playback.durationText)
                    }
                    .font(.system(size: timeFontSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.62))
                    .padding(.top, 2)
                }
                .frame(width: informationWidth, height: cardHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var artistText: String {
        if !playback.artist.isEmpty {
            return playback.artist
        }

        return playback.detail
    }
}

private struct MusicIdleLaunchCard: View {
    let availableHeight: CGFloat
    let diagnosticText: String

    private var titleFontSize: CGFloat {
        min(18, max(14, availableHeight / 8.2))
    }

    private var subtitleFontSize: CGFloat {
        min(20, max(15, availableHeight / 7.0))
    }

    private var iconSize: CGFloat {
        min(62, max(44, availableHeight * 0.36))
    }

    private var verticalSpacing: CGFloat {
        min(18, max(10, availableHeight / 12.0))
    }

    var body: some View {
        VStack(spacing: verticalSpacing) {
            VStack(spacing: 3) {
                Text("换个心情")
                    .font(.system(size: titleFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("从一首歌开始")
                    .font(.system(size: subtitleFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: min(14, max(8, iconSize * 0.22))) {
                ForEach(MusicLaunchTarget.allCases) { target in
                    MusicLaunchAppIconButton(target: target, size: iconSize)
                }
            }

            #if DEBUG
            if !diagnosticText.isEmpty {
                Text(diagnosticText)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum MusicLaunchTarget: CaseIterable, Identifiable {
    case music
    case spotify

    var id: String { title }

    var title: String {
        switch self {
        case .music: "音乐"
        case .spotify: "Spotify"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .music:
            ["com.apple.Music"]
        case .spotify:
            ["com.spotify.client"]
        }
    }

    var imageResource: (name: String, extension: String)? {
        switch self {
        case .music: ("music", "png")
        case .spotify: ("spotify", "png")
        }
    }

    var fallbackSymbolName: String {
        switch self {
        case .music: "music.note"
        case .spotify: "dot.radiowaves.left.and.right"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .music: Color(red: 0.98, green: 0.22, blue: 0.36)
        case .spotify: Color(red: 0.11, green: 0.72, blue: 0.28)
        }
    }

    var icon: NSImage? {
        if let installedIcon = bundleIdentifiers.compactMap(installedAppIcon).first {
            return installedIcon
        }

        guard let resource = imageResource else { return nil }
        guard let url = Bundle.main.url(
            forResource: resource.name,
            withExtension: resource.extension
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private func installedAppIcon(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func open() -> Bool {
        for bundleIdentifier in bundleIdentifiers {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return true
        }

        return false
    }
}

private struct MusicLaunchAppIconButton: View {
    let target: MusicLaunchTarget
    let size: CGFloat
    @State private var isShowingMissingAppAlert = false

    private var iconContentSize: CGFloat {
        floor(size - 2)
    }

    var body: some View {
        Button {
            guard target.open() else {
                isShowingMissingAppAlert = true
                return
            }
        } label: {
            Group {
                if let icon = target.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: iconContentSize, height: iconContentSize)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(target.fallbackColor)
                        .overlay {
                            Image(systemName: target.fallbackSymbolName)
                                .font(.system(size: size * 0.46, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: size, height: size)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 2.5, y: 1.5)
        }
        .buttonStyle(.plain)
        .handCursor()
        .help("打开 \(target.title)")
        .alert("当前应用不存在", isPresented: $isShowingMissingAppAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("未在当前系统中找到 \(target.title)。")
        }
    }
}

private struct MusicLyricMarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let color: Color

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: horizontalOffset)
                .background {
                    GeometryReader { textProxy in
                        Color.clear
                            .preference(key: MusicLyricTextWidthKey.self, value: textProxy.size.width)
                    }
                }
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.22), value: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    updateContainerWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, width in
                    updateContainerWidth(width)
                }
        }
        .clipped()
        .onPreferenceChange(MusicLyricTextWidthKey.self) { width in
            guard abs(textWidth - width) > 0.5 else { return }
            textWidth = width
            restartScrolling()
        }
        .onChange(of: text) { _, _ in
            restartScrolling()
        }
        .onDisappear {
            scrollTask?.cancel()
            scrollTask = nil
        }
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard abs(containerWidth - width) > 0.5 else { return }
        containerWidth = width
        restartScrolling()
    }

    private func restartScrolling() {
        scrollTask?.cancel()
        scrollTask = nil

        withAnimation(.none) {
            horizontalOffset = 0
        }

        let overflow = max(0, textWidth - containerWidth)
        guard overflow > 2 else { return }

        let duration = min(9, max(3.2, Double(overflow / 18)))
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.linear(duration: duration)) {
                horizontalOffset = -overflow
            }
        }
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: CGFloat
    let startDelay: TimeInterval
    let endDelay: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isActivelyScrolling = false
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: horizontalOffset)
                .background {
                    GeometryReader { textProxy in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: textProxy.size.width
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    updateContainerWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, width in
                    updateContainerWidth(width)
                }
        }
        .mask {
            if isActivelyScrolling {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.035),
                        .init(color: .white, location: 0.965),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Rectangle().fill(.white)
            }
        }
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { width in
            guard abs(textWidth - width) > 0.5 else { return }
            textWidth = width
            restartScrolling()
        }
        .onChange(of: text) { _, _ in
            restartScrolling()
        }
        .onChange(of: reduceMotion) { _, _ in
            restartScrolling()
        }
        .onDisappear {
            cancelScrolling(reset: false)
        }
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard abs(containerWidth - width) > 0.5 else { return }
        containerWidth = width
        restartScrolling()
    }

    private func restartScrolling() {
        cancelScrolling(reset: true)

        let overflow = max(0, textWidth - containerWidth)
        guard overflow > 1, !reduceMotion else { return }

        let scrollingDuration = max(2.2, Double(overflow / max(speed, 1)))
        scrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(startDelay))
                guard !Task.isCancelled else { return }

                isActivelyScrolling = true
                withAnimation(.linear(duration: scrollingDuration)) {
                    horizontalOffset = -overflow
                }

                try? await Task.sleep(for: .seconds(scrollingDuration + endDelay))
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: scrollingDuration)) {
                    horizontalOffset = 0
                }
                try? await Task.sleep(for: .seconds(scrollingDuration))
                guard !Task.isCancelled else { return }
                isActivelyScrolling = false
            }
        }
    }

    private func cancelScrolling(reset: Bool) {
        scrollTask?.cancel()
        scrollTask = nil
        guard reset else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            horizontalOffset = 0
            isActivelyScrolling = false
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MusicLyricTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MusicTransportControls: View {
    let playback: PlaybackSnapshot
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            MusicTransportIconButton(
                systemName: "backward.fill",
                help: "上一首",
                isEnabled: playback.isLive,
                size: 20,
                iconSize: 8,
                action: onPrevious
            )

            MusicTransportIconButton(
                systemName: playback.state.controlSymbolName,
                help: playback.state == .playing ? "暂停播放" : "播放",
                isEnabled: true,
                size: 23,
                iconSize: 9,
                action: onTogglePlayback
            )

            MusicTransportIconButton(
                systemName: "forward.fill",
                help: "下一首",
                isEnabled: playback.isLive,
                size: 20,
                iconSize: 8,
                action: onNext
            )
        }
    }
}

private struct MusicPlaybackStateGlyph: View {
    let playback: PlaybackSnapshot

    var body: some View {
        TimelineView(.animation(paused: playback.state != .playing)) { timeline in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(barOpacity(for: index)))
                        .frame(width: 2.5, height: 13)
                        .scaleEffect(
                            x: 1,
                            y: barScale(for: index, at: timeline.date),
                            anchor: .bottom
                        )
                }
            }
            .frame(width: 17, height: 14, alignment: .bottom)
        }
        .opacity(playback.isLive ? 1 : 0.38)
        .animation(.easeOut(duration: 0.20), value: playback.state)
        .help(playback.state.title)
    }

    private func barScale(for index: Int, at date: Date) -> CGFloat {
        guard playback.state == .playing else {
            return staticBarScale(for: index)
        }

        let time = date.timeIntervalSinceReferenceDate
        let frequencies = [2.35, 1.85, 2.65]
        let phaseOffsets = [0.0, 1.75, 3.55]
        let minimumScales: [CGFloat] = [0.28, 0.38, 0.24]
        let amplitudes: [CGFloat] = [0.62, 0.58, 0.68]
        let wave = (sin(time * frequencies[index] * .pi * 2 + phaseOffsets[index]) + 1) / 2
        let softenedWave = CGFloat(0.5 - cos(wave * .pi) / 2)
        return minimumScales[index] + amplitudes[index] * softenedWave
    }

    private func staticBarScale(for index: Int) -> CGFloat {
        switch index {
        case 0: return 0.38
        case 1: return 0.62
        default: return 0.46
        }
    }

    private func barOpacity(for index: Int) -> Double {
        guard playback.isLive else {
            return 0.38
        }

        if playback.state == .paused {
            return index == 1 ? 0.72 : 0.48
        }

        return index == 1 ? 0.88 : 0.68
    }
}

private struct MusicTransportIconButton: View {
    let systemName: String
    let help: String
    let isEnabled: Bool
    let size: CGFloat
    let iconSize: CGFloat
    var showsBackground = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(isEnabled ? 0.94 : 0.34))
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(Color.white.opacity(backgroundOpacity))
                        .opacity(showsBackground ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .scaleEffect(isHovering && isEnabled ? 1.05 : 1)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .help(help)
    }

    private var backgroundOpacity: Double {
        if !isEnabled {
            return 0.035
        }

        return isHovering ? 0.16 : 0.09
    }
}

private struct MusicArtworkCover: View {
    let source: PlaybackArtworkSource?
    let appName: String
    let state: PlaybackState
    let isLive: Bool
    let width: CGFloat
    let height: CGFloat

    private var cornerRadius: CGFloat {
        max(14, min(width, height) * 0.18)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isLive ? 0.10 : 0.055))

            artworkContent
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)

            playerAppBadge
                .offset(x: 5, y: 5)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var artworkContent: some View {
        switch source {
        case .file(let url, let version):
            AsyncPlaybackArtworkImage(
                source: .file(url, version: version),
                width: width,
                height: height
            ) {
                placeholder
            }
        case .imageData(let data, let id):
            AsyncPlaybackArtworkImage(
                source: .imageData(data, id: id),
                width: width,
                height: height
            ) {
                placeholder
            }
        case .remote(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                default:
                    placeholder
                }
            }
            .frame(width: width, height: height)
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(isLive ? 0.16 : 0.08),
                    Color.white.opacity(isLive ? 0.06 : 0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "music.note")
                .font(.system(size: min(width, height) * 0.28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(isLive ? 0.72 : 0.34))
        }
        .frame(width: width, height: height)
    }

    private var playerAppBadge: some View {
        let badgeSize = max(22, min(width, height) * 0.25)

        return Group {
            if let icon = MusicPlayerAppIcon.icon(for: appName) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: badgeSize * 0.24, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.10, blue: 0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: badgeSize * 0.46, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: badgeSize, height: badgeSize)
        .clipShape(RoundedRectangle(cornerRadius: badgeSize * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: badgeSize * 0.24, style: .continuous)
                .stroke(Color.black.opacity(0.24), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.26), radius: 2, y: 1)
    }
}

private enum MusicPlayerAppIcon {
    static func icon(for appName: String) -> NSImage? {
        let normalized = appName.lowercased()
        let bundleIdentifier: String?

        if normalized.contains("spotify") {
            bundleIdentifier = "com.spotify.client"
        } else if normalized.contains("music") || normalized.contains("音乐") {
            bundleIdentifier = "com.apple.Music"
        } else {
            bundleIdentifier = nil
        }

        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct MusicLyricWindowView: View {
    let lyrics: [LyricLine]
    let currentIndex: Int?
    let statusText: String
    let isLoading: Bool
    let fontSize: CGFloat

    private var displayEntries: [MusicLyricWindowEntry] {
        lyrics.enumerated().compactMap { index, line in
            let text = lyricText(for: line)
            guard !text.isEmpty else { return nil }

            return MusicLyricWindowEntry(
                sourceIndex: index,
                line: line,
                text: text
            )
        }
    }

    private var resolvedCurrentIndex: Int? {
        guard !displayEntries.isEmpty else { return nil }

        guard let currentIndex else {
            return 0
        }

        if let exact = displayEntries.firstIndex(where: { $0.sourceIndex == currentIndex }) {
            return exact
        }

        if let next = displayEntries.firstIndex(where: { $0.sourceIndex > currentIndex }) {
            return next
        }

        return displayEntries.indices.last
    }

    private var rows: [MusicLyricWindowRow] {
        guard let currentIndex = resolvedCurrentIndex else { return [] }

        return [-1, 0, 1].compactMap { relative in
            let index = currentIndex + relative
            guard displayEntries.indices.contains(index) else { return nil }
            let entry = displayEntries[index]

            return MusicLyricWindowRow(
                id: "\(entry.sourceIndex)-\(entry.line.id)",
                text: entry.text,
                relative: relative
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isLoading {
                    MusicLyricLoadingPlaceholder()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .transition(.opacity)
                } else if rows.isEmpty {
                    Text(statusText)
                        .font(.system(size: max(10, fontSize - 0.5), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .transition(.opacity)
                } else {
                    lyricRows(in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .clipped()
        }
        .animation(.easeInOut(duration: 0.48), value: resolvedCurrentIndex)
        .animation(.easeOut(duration: 0.22), value: isLoading)
    }

    private func lyricRows(in size: CGSize) -> some View {
        let rowStep = max(fontSize + 5, size.height / 3.18)

        return ZStack {
            ForEach(rows) { row in
                Text(row.text)
                    .font(.system(
                        size: row.relative == 0 ? fontSize : max(8.4, fontSize - 1.1),
                        weight: row.relative == 0 ? .bold : .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(color(for: row.relative).opacity(opacity(for: row.relative)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: size.width, height: rowStep, alignment: .center)
                    .scaleEffect(row.relative == 0 ? 1 : 0.94)
                    .blur(radius: row.relative == 0 ? 0 : 0.35)
                    .offset(y: CGFloat(row.relative) * rowStep)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 10)),
                            removal: .opacity.combined(with: .offset(y: -10))
                        )
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
    }

    private func color(for relative: Int) -> Color {
        Color.white
    }

    private func opacity(for relative: Int) -> Double {
        switch relative {
        case 0:
            return 0.94
        case -1:
            return 0.38
        default:
            return 0.48
        }
    }

    private func lyricText(for line: LyricLine) -> String {
        let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            return words
        }

        return line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct MusicLyricWindowEntry {
    let sourceIndex: Int
    let line: LyricLine
    let text: String
}

private struct MusicLyricWindowRow: Identifiable {
    let id: String
    let text: String
    let relative: Int
}

private struct MusicLyricLoadingPlaceholder: View {
    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: index == 1 ? 18 : 12, height: 4)
                    .scaleEffect(isBreathing ? 1.0 : 0.72, anchor: .center)
                    .opacity(isBreathing ? 0.78 : 0.24)
                    .animation(
                        .easeInOut(duration: 0.82)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.14),
                        value: isBreathing
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .onAppear {
            isBreathing = true
        }
    }
}

private struct MusicProgressScrubber: View {
    let progress: Double
    let isEnabled: Bool
    let onScrubStarted: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var localProgress: Double?
    @State private var isDragging = false
    @State private var isHovering = false

    private var displayProgress: Double {
        clamped(localProgress ?? progress)
    }

    var body: some View {
        GeometryReader { proxy in
            progressBody(width: proxy.size.width)
        }
        .frame(height: 10)
        .opacity(isEnabled ? 1 : 0.56)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
    }

    private func progressBody(width: CGFloat) -> some View {
        let safeWidth = max(width, 1)
        let filledWidth = safeWidth * CGFloat(displayProgress)
        let knobSize: CGFloat = isDragging ? 8 : 6
        let knobX = min(max(filledWidth - knobSize / 2, 0), max(safeWidth - knobSize, 0))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.13))
                .frame(height: 2.5)

            Capsule()
                .fill(Color.white.opacity(isEnabled ? 0.86 : 0.30))
                .frame(width: max(filledWidth, displayProgress > 0 ? 4 : 0), height: 2.5)

            Circle()
                .fill(Color.white.opacity(isEnabled ? 0.96 : 0.44))
                .frame(width: knobSize, height: knobSize)
                .opacity(knobOpacity)
                .scaleEffect(isDragging ? 1.08 : 1)
                .offset(x: knobX)
        }
        .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10, alignment: .center)
        .contentShape(Rectangle())
        .animation(isDragging ? .easeOut(duration: 0.08) : .linear(duration: 1.9), value: displayProgress)
        .animation(.easeOut(duration: 0.14), value: isDragging)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else { return }
                    if !isDragging {
                        isDragging = true
                        onScrubStarted()
                    }

                    let newProgress = progressValue(for: value.location.x, width: safeWidth)
                    localProgress = newProgress
                    onScrubChanged(newProgress)
                }
                .onEnded { value in
                    guard isEnabled else { return }
                    let newProgress = progressValue(for: value.location.x, width: safeWidth)
                    localProgress = newProgress
                    isDragging = false
                    onScrubEnded(newProgress)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        if !isDragging {
                            localProgress = nil
                        }
                    }
                }
        )
    }

    private var knobOpacity: Double {
        if isDragging {
            return 0.94
        }

        return isHovering ? 0.58 : 0.10
    }

    private func progressValue(for locationX: CGFloat, width: CGFloat) -> Double {
        clamped(Double(locationX / max(width, 1)))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct PlaybackArtworkTile: View {
    let source: PlaybackArtworkSource?
    let isLive: Bool
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isLive ? 0.10 : 0.055))

            artworkContent
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        switch source {
        case .file(let url, let version):
            AsyncPlaybackArtworkImage(
                source: .file(url, version: version),
                width: size,
                height: size
            ) {
                placeholder
            }
        case .imageData(let data, let id):
            AsyncPlaybackArtworkImage(
                source: .imageData(data, id: id),
                width: size,
                height: size
            ) {
                placeholder
            }
        case .remote(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.white.opacity(isLive ? 0.74 : 0.36))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AsyncPlaybackArtworkImage<Placeholder: View>: View {
    let source: PlaybackArtworkSource?
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var placeholder: Placeholder

    @State private var image: NSImage?
    @State private var loadedKey = ""
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: cacheKey) { _, _ in
            loadImageIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var cacheKey: String {
        switch source {
        case .file(let url, let version):
            return PlaybackArtworkImageCache.cacheKey(for: url, version: version)
        case .imageData(_, let id):
            return PlaybackArtworkImageCache.cacheKey(forDataID: id)
        case .remote, nil:
            return ""
        }
    }

    private func loadImageIfNeeded() {
        let key = cacheKey
        guard !key.isEmpty else {
            loadTask?.cancel()
            loadTask = nil
            loadedKey = ""
            image = nil
            return
        }

        if loadedKey == key, image != nil {
            return
        }

        loadTask?.cancel()
        loadedKey = key

        if let cached = cachedImage() {
            image = cached
            loadTask = nil
            return
        }

        image = nil
        let source = source
        loadTask = Task { @MainActor in
            let loadedImage = await Task.detached(priority: .utility) { () -> NSImage? in
                switch source {
                case .file(let url, let version):
                    return PlaybackArtworkImageCache.shared.loadImage(for: url, version: version)
                case .imageData(let data, let id):
                    return PlaybackArtworkImageCache.shared.loadImage(for: data, id: id)
                case .remote, nil:
                    return nil
                }
            }.value

            guard !Task.isCancelled, cacheKey == key else { return }
            image = loadedImage
            loadTask = nil
        }
    }

    private func cachedImage() -> NSImage? {
        switch source {
        case .file(let url, let version):
            return PlaybackArtworkImageCache.shared.cachedImage(for: url, version: version)
        case .imageData(_, let id):
            return PlaybackArtworkImageCache.shared.cachedImage(forDataID: id)
        case .remote, nil:
            return nil
        }
    }
}

private final class PlaybackArtworkImageCache {
    static let shared = PlaybackArtworkImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 12
    }

    static func cacheKey(for url: URL, version: TimeInterval) -> String {
        "\(url.path)#\(version)"
    }

    static func cacheKey(forDataID id: String) -> String {
        "data#\(id)"
    }

    func cachedImage(for url: URL, version: TimeInterval) -> NSImage? {
        cache.object(forKey: Self.cacheKey(for: url, version: version) as NSString)
    }

    func cachedImage(forDataID id: String) -> NSImage? {
        cache.object(forKey: Self.cacheKey(forDataID: id) as NSString)
    }

    func loadImage(for url: URL, version: TimeInterval) -> NSImage? {
        let key = Self.cacheKey(for: url, version: version) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard
            let data = try? Data(contentsOf: url),
            !data.isEmpty,
            let image = NSImage(data: data)
        else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func loadImage(for data: Data, id: String) -> NSImage? {
        let key = Self.cacheKey(forDataID: id) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
}

private struct PlaybackProgressScrubber: View {
    let progress: Double
    let isEnabled: Bool
    let onScrubStarted: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    @State private var localProgress: Double?
    @State private var isDragging = false

    private var displayProgress: Double {
        clamped(localProgress ?? progress)
    }

    var body: some View {
        GeometryReader { proxy in
            progressBody(width: proxy.size.width)
        }
        .frame(height: 14)
        .opacity(isEnabled ? 1 : 0.58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
    }

    private func progressBody(width: CGFloat) -> some View {
        let safeWidth = max(width, 1)
        let knobWidth: CGFloat = 22
        let filledWidth = safeWidth * CGFloat(displayProgress)
        let knobOffset = min(max(filledWidth - knobWidth / 2, 0), max(safeWidth - knobWidth, 0))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(height: 4)

            Capsule()
                .fill(Color.white.opacity(isEnabled ? 0.78 : 0.26))
                .frame(width: max(filledWidth, displayProgress > 0 ? 5 : 0), height: 4)

            Capsule()
                .fill(Color.white.opacity(isEnabled ? 0.96 : 0.48))
                .frame(width: knobWidth, height: 10)
                .shadow(color: Color.black.opacity(isEnabled ? 0.22 : 0), radius: 4, x: 0, y: 2)
                .offset(x: knobOffset)
        }
        .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .center)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else { return }
                    if !isDragging {
                        isDragging = true
                        onScrubStarted()
                    }

                    let newProgress = progressValue(for: value.location.x, width: safeWidth)
                    localProgress = newProgress
                    onScrubChanged(newProgress)
                }
                .onEnded { value in
                    guard isEnabled else { return }
                    let newProgress = progressValue(for: value.location.x, width: safeWidth)
                    localProgress = newProgress
                    isDragging = false
                    onScrubEnded(newProgress)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        if !isDragging {
                            localProgress = nil
                        }
                    }
                }
        )
    }

    private func progressValue(for locationX: CGFloat, width: CGFloat) -> Double {
        clamped(Double(locationX / max(width, 1)))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct HoverImageButton: View {
    let imageName: String
    let fallbackSystemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            iconContent
                .frame(width: 26, height: 26)
                .brightness(isHovering ? 0.22 : 0)
                .saturation(isHovering ? 1.08 : 0.96)
                .opacity(isHovering ? 1 : 0.76)
                .shadow(color: Color.white.opacity(isHovering ? 0.14 : 0), radius: isHovering ? 5 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .handCursor()
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let image = BundleImageLoader.image(named: imageName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IslandDesignTokens.iconColor)
        }
    }
}

private struct HoverIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(isHovering ? 0.95 : 0.72))
                .brightness(isHovering ? 0.18 : 0)
                .shadow(color: Color.white.opacity(isHovering ? 0.16 : 0), radius: isHovering ? 5 : 0)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .handCursor()
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }
}

private struct FileDropChoiceOverlay: View {
    let hoverTarget: IslandFileDropTarget?
    let previewName: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                dropCard(
                    target: .staging,
                    systemName: "tray.and.arrow.down",
                    title: "存放文稿"
                )

                dropCard(
                    target: .airDrop,
                    systemName: "airdrop",
                    title: "隔空投送"
                )
            }
            .padding(.top, 108)
            .padding(.horizontal, 72)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.18))
        .allowsHitTesting(false)
    }

    private func dropCard(
        target: IslandFileDropTarget,
        systemName: String,
        title: String
    ) -> some View {
        let isActive = hoverTarget == target

        return VStack(spacing: 16) {
            Image(systemName: systemName)
                .font(.system(size: target == .staging ? 56 : 50, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.58))
                .shadow(color: Color.white.opacity(isActive ? 0.22 : 0), radius: 10)

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.76))

            if let previewName, target == hoverTarget {
                Text(previewName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.88)))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.13 : 0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isActive ? Color.white.opacity(0.92) : Color.white.opacity(0.34),
                    style: StrokeStyle(lineWidth: isActive ? 3 : 2, dash: [9, 7])
                )
        }
        .scaleEffect(isActive ? 1.018 : 1)
        .animation(.spring(response: 0.20, dampingFraction: 0.82), value: isActive)
    }
}

private enum BundleImageLoader {
    static func image(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }

        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private final class NewReminderEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class NewReminderPanelPresenter: NSObject, NSWindowDelegate {
    static let shared = NewReminderPanelPresenter()

    private var panel: NewReminderEditorPanel?
    private var onAdd: ((ReminderCreationRequest) -> Void)?
    private var lastIslandHeight: CGFloat = IslandDesignTokens.windowSize.height

    func present(islandHeight: CGFloat, onAdd: @escaping (ReminderCreationRequest) -> Void) {
        self.onAdd = onAdd
        lastIslandHeight = islandHeight

        if let panel {
            bringToFront(panel)
            return
        }

        let draft = NewReminderDraft()
        let panel = NewReminderEditorPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: NewReminderPanelView.panelSize.width,
                height: NewReminderPanelView.panelSize.height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let hostingView = NSHostingView(
            rootView:
                NewReminderPanelView(
                    draft: draft,
                    onCancel: { [weak self] in
                        self?.close()
                    },
                    onAdd: { [weak self] request in
                        self?.onAdd?(request)
                        self?.close()
                    }
                )
        )
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: NewReminderPanelView.panelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        self.panel = panel
        bringToFront(panel)
    }

    func windowWillClose(_ notification: Notification) {
        guard let currentPanel = panel,
              let closingPanel = notification.object as? NSPanel,
              closingPanel === currentPanel else { return }
        panel?.delegate = nil
        panel?.contentView = nil
        panel = nil
        onAdd = nil
    }

    private func close() {
        panel?.close()
    }

    private func bringToFront(_ panel: NSPanel) {
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 18
        let lowerBound = visibleFrame.minY + margin
        let upperBound = visibleFrame.maxY - panel.frame.height - margin
        let belowIslandY = screenFrame.maxY - lastIslandHeight - panel.frame.height - margin
        let y = min(max(belowIslandY, lowerBound), upperBound)
        let x = min(
            max(visibleFrame.midX - panel.frame.width / 2, visibleFrame.minX + margin),
            visibleFrame.maxX - panel.frame.width - margin
        )

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
