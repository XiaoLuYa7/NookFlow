import AppKit
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class IslandWindowController: NSObject {

    private var panel: IslandPanel?
    private let settings = IslandSettings()
    private lazy var viewModel = IslandViewModel(settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)
    private lazy var desktopLyricsWindowController = DesktopLyricsWindowController(
        playbackProvider: viewModel.playbackProvider,
        lyricsProvider: viewModel.lyricsProvider,
        settings: settings
    )
    private var trackingView: IslandTrackingView?
    private var cancellables = Set<AnyCancellable>()
    private var tabPanelFrameSettlementTask: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var didShowUnsupportedHardwareAlert = false
    private var hasActiveExternalInteractiveFrame = false
    private var externalInteractionDismissGraceDeadline: Date?
    private let externalInteractionDismissGraceDelay: TimeInterval = 0.85

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        let localMouseMonitor = localMouseMonitor
        let globalMouseMonitor = globalMouseMonitor
        Task { @MainActor in
            if let localMouseMonitor {
                NSEvent.removeMonitor(localMouseMonitor)
            }
            if let globalMouseMonitor {
                NSEvent.removeMonitor(globalMouseMonitor)
            }
        }
        cancellables.removeAll()
        tabPanelFrameSettlementTask?.cancel()
        let trackingView = trackingView
        let panel = panel
        Task { @MainActor in
            trackingView?.clearHandlers()
            trackingView?.removeFromSuperview()
            panel?.contentView = nil
            panel?.close()
        }
    }

    func setup() {
        guard updateCompactCapsuleMetrics() else {
            showUnsupportedHardwareAlert()
            return
        }
        createPanelIfNeeded()
        positionPanel()
        applyPanelVisibility()
        observeSettings()
        installPointerMonitors()
        desktopLyricsWindowController.setup()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSWindow.didChangeScreenNotification,
            object: panel
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceVisibilityDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceVisibilityDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func showSettingsFromDock() {
        if settingsWindowController.bringToFrontIfVisible() {
            return
        }
        openSettingsWindow(page: .home, presentFeedback: false)
    }

    func bringSettingsToFrontIfVisible() {
        _ = settingsWindowController.bringToFrontIfVisible()
    }

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        let rect = panelEnvelopeRect()
        let panel = IslandPanel(contentRect: rect)

        let rootView = IslandRootView(
            viewModel: viewModel,
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.openSettingsFromIsland()
            },
            onOpenTodoSettings: { [weak self] in
                self?.openTodoSettingsFromIsland()
            },
            onOpenFeedback: { [weak self] in
                self?.openFeedbackFromIsland()
            }
        )
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.shouldReceiveMouseEvents = { [weak self] in
            self?.isPointerInsidePanel == true
        }
        hostingView.frame = NSRect(origin: .zero, size: rect.size)
        hostingView.autoresizingMask = [.width, .height]

        let trackingView = IslandTrackingView(frame: hostingView.bounds)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.compactCapsuleSize = viewModel.compactCapsuleSize
        trackingView.expandedShellSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: viewModel.selectedTopTab
        )
        trackingView.onMouseInsideChanged = { [weak self] isInside in
            self?.handleMouseInsideChanged(isInside)
        }
        trackingView.onCameraAreaHoverChanged = { [weak self] isHovering in
            self?.viewModel.updateCameraHover(isHovering)
        }
        trackingView.onFileDragChanged = { [weak self] isActive, target, previewName in
            guard let self else { return }
            if isActive {
                self.setPanelFrame(for: .expanded)
                if !self.viewModel.isFileDropChooserVisible {
                    self.viewModel.beginFileDrop(previewName: previewName)
                }
                self.viewModel.updateFileDropTarget(target)
            } else {
                self.viewModel.endFileDrop()
            }
        }
        trackingView.onFileDrop = { [weak self] urls, target in
            guard let self, let target else { return false }
            self.viewModel.endFileDrop()

            switch target {
            case .staging:
                let viewModel = self.viewModel
                Task { @MainActor in
                    let importResult = await Task.detached(priority: .userInitiated) {
                        FileDataProvider.importFilesToStaging(urls)
                    }.value
                    if importResult.importedAny {
                        viewModel.notifyFileDataChanged()
                    }
                    if let message = importResult.failureMessage {
                        InAppNotificationWindowController.shared.show(
                            InAppNotificationPayload(
                                title: "文件导入失败",
                                message: message,
                                kind: .general
                            )
                        )
                    }
                }
                return true
            case .airDrop:
                self.shareViaAirDrop(urls)
                return true
            }
        }

        let containerView = NSView(frame: NSRect(origin: .zero, size: rect.size))
        containerView.autoresizingMask = [.width, .height]
        hostingView.frame = containerView.bounds
        containerView.addSubview(hostingView)
        containerView.addSubview(trackingView)
        panel.contentView = containerView

        self.panel = panel
        self.trackingView = trackingView
    }

    private func positionPanel() {
        setPanelFrameToCurrentEnvelope(display: true)
    }

    private func setPanelFrame(for mode: IslandMode, display: Bool = false) {
        setPanelFrameToCurrentEnvelope(display: display)
    }

    private func setPanelFrameToCurrentEnvelope(
        display: Bool = false,
        selectedTopTab: IslandTopTab? = nil
    ) {
        guard panel != nil else { return }
        tabPanelFrameSettlementTask?.cancel()
        tabPanelFrameSettlementTask = nil

        trackingView?.expandedShellSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: selectedTopTab ?? viewModel.selectedTopTab
        )

        let targetRect = panelEnvelopeRect(selectedTopTab: selectedTopTab)
        applyPanelFrame(targetRect, display: display)
    }

    private func preparePanelFrameForTabTransition(to tab: IslandTopTab) {
        guard let panel else { return }

        tabPanelFrameSettlementTask?.cancel()

        let targetSize = panelEnvelopeSize(selectedTopTab: tab)
        let envelopeSize = CGSize(
            width: max(panel.frame.width, targetSize.width),
            height: max(panel.frame.height, targetSize.height)
        )
        let envelopeRect = panelRect(for: envelopeSize)
        let targetRect = panelRect(for: targetSize)

        // Keep AppKit's transparent host large enough for both pages, while SwiftUI
        // performs the visible shell transition. Continuously resizing NSPanel would
        // otherwise force every hidden grid to relayout on every animation frame.
        applyPanelFrame(envelopeRect, display: false)

        tabPanelFrameSettlementTask = Task { @MainActor [weak self] in
            let duration = tab == .home
                ? IslandDesignTokens.tabReturnHomeDuration
                : IslandDesignTokens.tabSwitchDuration
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard let self,
                  !Task.isCancelled,
                  self.viewModel.mode == .expanded,
                  !self.viewModel.isCollapsing,
                  self.viewModel.selectedTopTab == tab
            else {
                return
            }

            self.applyPanelFrame(targetRect, display: false)
            self.reconcilePointerHoverState()
        }
    }

    private func applyPanelFrame(_ rect: NSRect, display: Bool) {
        guard let panel else { return }
        if panel.frame != rect {
            panel.setFrame(rect, display: display)
        }

        panel.contentView?.setFrameSize(rect.size)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func handleMouseInsideChanged(_ isInside: Bool) {
        if isInside, isPointerInsidePanel {
            viewModel.cancelCollapse()
            return
        }

        if viewModel.mode == .compact {
            updateCompactHoverState(at: NSEvent.mouseLocation)
            return
        }

        collapseImmediatelyIfPointerOutsidePanel()
    }

    private func panelRect(for mode: IslandMode) -> NSRect {
        panelRect(for: panelSize(for: mode))
    }

    private func panelEnvelopeRect(selectedTopTab: IslandTopTab? = nil) -> NSRect {
        panelRect(for: panelEnvelopeSize(selectedTopTab: selectedTopTab))
    }

    private func panelEnvelopeSize(selectedTopTab: IslandTopTab? = nil) -> CGSize {
        let tab = selectedTopTab ?? viewModel.selectedTopTab
        let expandedEnvelope = IslandShellLayout.openingWindowEnvelopeSize(
            settings: settings,
            selectedTopTab: tab
        )
        let expandedOverflowHeight = viewModel.presentationPhase == .collapsed
            ? 0
            : viewModel.expandedContentOverflowHeight
        let compactEnvelope = CGSize(
            width: viewModel.compactCapsuleSize.width * IslandDesignTokens.compactHoverWidthScale + 40,
            height: viewModel.compactCapsuleSize.height * IslandDesignTokens.compactHoverHeightScale
                + IslandDesignTokens.applicationsWindowVerticalPadding
        )

        return CGSize(
            width: max(expandedEnvelope.width, compactEnvelope.width),
            height: max(expandedEnvelope.height + expandedOverflowHeight, compactEnvelope.height)
        )
    }

    private func panelRect(for size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }

        let screenFrame = screen.frame
        let scale = max(1, screen.backingScaleFactor)
        let width = ceil(size.width * scale) / scale
        let height = ceil(size.height * scale) / scale
        let centerX = NotchGeometryProvider.cameraSafeRegionCenterX(for: screen)
            ?? screenFrame.midX
        let x = round((centerX - width / 2) * scale) / scale
        let y = round((screenFrame.maxY - height) * scale) / scale

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var compactCapsuleHitRect: NSRect {
        visualShellRect(for: viewModel.compactCapsuleSize)
    }

    private func visualShellRect(for size: CGSize) -> NSRect {
        let hostRect = panel?.frame ?? panelEnvelopeRect()
        return NSRect(
            x: hostRect.midX - size.width / 2,
            y: hostRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func panelSize(for mode: IslandMode) -> CGSize {
        switch mode {
        case .compact:
            return viewModel.compactCapsuleSize
        case .expanded:
            return IslandShellLayout.windowSize(
                settings: settings,
                selectedTopTab: viewModel.selectedTopTab
            )
        }
    }

    @discardableResult
    private func updateCompactCapsuleMetrics() -> Bool {
        let screen = panel?.screen ?? NSScreen.main
        guard let metrics = compactCapsuleMetrics(for: screen) else {
            return false
        }

        viewModel.updateCompactCapsuleSizes(
            camera: metrics.camera,
            status: metrics.status,
            lyrics: metrics.lyrics
        )
        trackingView?.compactCapsuleSize = viewModel.compactCapsuleSize

        let geometry = NotchGeometryProvider.geometry(
            for: screen,
            capsuleWidth: viewModel.compactCapsuleSize.width,
            capsuleHeight: viewModel.compactCapsuleSize.height
        )
        viewModel.updateNotchGeometry(geometry)
        return true
    }

    private func compactCapsuleMetrics(
        for screen: NSScreen?
    ) -> (camera: CGSize, status: CGSize, lyrics: CGSize)? {
        guard let screen,
              let cameraCapsule = NotchGeometryProvider.cameraCapsuleSize(for: screen)
        else {
            return nil
        }

        let cameraWidth = max(1, cameraCapsule.width)
        let height = max(1, cameraCapsule.height)
        let minimumStatusWidth = max(
            180,
            cameraWidth + IslandDesignTokens.compactCapsuleHorizontalExtension * 2
        )
        let maximumStatusWidth = max(
            minimumStatusWidth,
            screen.frame.width * IslandDesignTokens.compactStatusCapsuleMaximumScreenRatio
        )
        let statusWidth = min(minimumStatusWidth, maximumStatusWidth)

        let lyricWidth = compactLyricsWidth(
            cameraWidth: cameraWidth,
            screenWidth: screen.frame.width
        )

        return (
            CGSize(width: ceil(cameraWidth), height: ceil(height)),
            CGSize(width: ceil(statusWidth), height: ceil(height)),
            CGSize(width: ceil(lyricWidth), height: ceil(height))
        )
    }

    private func compactLyricsWidth(cameraWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let maximumWidth = screenWidth * IslandDesignTokens.compactLyricsCapsuleMaximumScreenRatio
        let defaultWidth = min(
            max(
                IslandDesignTokens.compactLyricsCapsuleMinimumWidth,
                cameraWidth + IslandDesignTokens.compactLyricsCapsuleHorizontalExtension * 2
            ),
            maximumWidth
        )

        guard settings.showMusicLyrics,
              !settings.showMusicTrackName
        else {
            return defaultWidth
        }

        let snapshot = viewModel.playbackProvider.snapshot
        guard snapshot.isLive else { return defaultWidth }

        let titleWidth = compactMusicTextWidth(snapshot.title)
        let artistWidth = compactMusicTextWidth(snapshot.artist)
        let sideTextWidth = max(titleWidth, artistWidth)
        guard sideTextWidth > 0 else { return defaultWidth }

        let measuredWidth = cameraWidth + (sideTextWidth + 20) * 2
        let minimumWidth = max(
            180,
            cameraWidth + IslandDesignTokens.compactCapsuleHorizontalExtension * 2
        )

        return min(max(minimumWidth, measuredWidth), maximumWidth)
    }

    private func compactMusicTextWidth(_ text: String) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        ]
        return ceil((trimmed as NSString).size(withAttributes: attributes).width)
    }

    private func showUnsupportedHardwareAlert() {
        guard !didShowUnsupportedHardwareAlert else { return }
        didShowUnsupportedHardwareAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "当前设备暂不支持 NookFlow"
        alert.informativeText = "NookFlow 需要带顶部摄像头刘海区域的 Mac。当前屏幕没有可识别的摄像头区域，因此不会显示灵动岛胶囊。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func collapseImmediatelyIfPointerOutsidePanel() {
        if isPointerInsidePanel {
            viewModel.cancelCollapse()
            externalInteractionDismissGraceDeadline = nil
        } else {
            viewModel.scheduleCollapse(delay: pointerExitCollapseDelay())
        }
    }

    private func pointerExitCollapseDelay() -> TimeInterval {
        guard let deadline = externalInteractionDismissGraceDeadline else {
            return 0
        }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            externalInteractionDismissGraceDeadline = nil
            return 0
        }

        return remaining
    }

    private func reconcilePointerHoverState() {
        guard viewModel.mode == .expanded, !viewModel.isCollapsing else { return }

        if isPointerInsidePanel {
            viewModel.cancelCollapse()
        } else {
            collapseImmediatelyIfPointerOutsidePanel()
        }
    }

    private var isPointerInsidePanel: Bool {
        let mouseLocation = NSEvent.mouseLocation
        if viewModel.presentationPhase == .collapsed {
            return compactCapsuleContains(mouseLocation)
        }

        if let externalInteractiveFrame = viewModel.externalInteractiveFrame,
           externalInteractiveFrame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
            return true
        }

        if viewModel.expandedContentOverflowHeight > 0,
           let panel,
           panel.frame.insetBy(dx: -2, dy: -2).contains(mouseLocation) {
            return true
        }

        return currentInteractiveShellRect
            .insetBy(dx: -2, dy: -2)
            .contains(mouseLocation)
    }

    private var currentInteractiveShellRect: NSRect {
        switch viewModel.presentationPhase {
        case .collapsed:
            return compactCapsuleHitRect
        case .expandingShell, .revealingContent:
            return interactiveShellRect(
                for: IslandShellLayout.openingEnvelopeSize(
                    settings: settings,
                    selectedTopTab: viewModel.selectedTopTab
                )
            )
        case .expanded, .hidingContent, .collapsingShell:
            let contentSize = viewModel.tabTransitionCanvasSize
                ?? IslandShellLayout.contentSize(
                    settings: settings,
                    selectedTopTab: viewModel.selectedTopTab
                )
            return interactiveShellRect(for: contentSize)
        }
    }

    private func interactiveShellRect(for size: CGSize) -> NSRect {
        let shellRect = visualShellRect(for: size)
        let overflowHeight = viewModel.presentationPhase == .collapsed
            ? 0
            : viewModel.expandedContentOverflowHeight
        let interactiveRect = overflowHeight > 0
            ? NSRect(
                x: shellRect.minX,
                y: shellRect.minY - overflowHeight,
                width: shellRect.width,
                height: shellRect.height + overflowHeight
            )
            : shellRect
        guard settings.showPinButton else { return interactiveRect }
        return interactiveRect.union(externalPinButtonHitRect(attachedTo: shellRect))
    }

    private func externalPinButtonHitRect(attachedTo shellRect: NSRect) -> NSRect {
        let hitPadding: CGFloat = 4
        let size = IslandDesignTokens.pinButtonSize + hitPadding * 2
        let center = NSPoint(
            x: shellRect.maxX - IslandDesignTokens.externalPinButtonTrailingOverlap,
            y: shellRect.minY + IslandDesignTokens.externalPinButtonBottomOverlap
        )

        return NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
    }

    private func installPointerMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.handlePointerMoved(at: NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.handlePointerMoved(at: NSEvent.mouseLocation)
        }
    }

    private func removePointerMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateCompactHoverState(at globalPoint: NSPoint) {
        guard viewModel.presentationPhase == .collapsed else { return }
        viewModel.updateCameraHover(compactCapsuleContains(globalPoint))
    }

    private func handlePointerMoved(at globalPoint: NSPoint) {
        if viewModel.presentationPhase == .collapsed {
            updateCompactHoverState(at: globalPoint)
        } else {
            reconcilePointerHoverState()
        }
    }

    private func compactCapsuleContains(_ globalPoint: NSPoint) -> Bool {
        let rect = compactCapsuleHitRect
        guard rect.contains(globalPoint) else { return false }

        let metrics = IslandShellLayout.shellShapeMetrics(
            shellSize: rect.size,
            compactSize: viewModel.compactCapsuleSize,
            morphProgress: 0
        )
        let shape = DynamicIslandShape(
            shoulderWidth: metrics.shoulderWidth,
            shoulderDepth: metrics.shoulderDepth,
            sideInset: metrics.sideInset,
            bottomCornerRadius: metrics.bottomCornerRadius,
            visibleSize: rect.size
        )

        return shape.path(in: rect).contains(globalPoint)
    }

    private func observeSettings() {
        settings.$isIslandEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPanelVisibility()
            }
            .store(in: &cancellables)

        settings.$islandWidth
            .combineLatest(settings.$islandHeight)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.viewModel.isCollapsing else { return }
                self.setPanelFrame(for: self.viewModel.mode)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$showWeatherModule,
            settings.$showCalendarModule,
            settings.$showTodoModule,
            settings.$showMediaModule
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            guard !self.viewModel.isCollapsing else { return }
            self.setPanelFrame(for: self.viewModel.mode)
        }
        .store(in: &cancellables)

        settings.$showQuickAppsModule
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.viewModel.isCollapsing else { return }
                self.setPanelFrame(for: self.viewModel.mode)
            }
            .store(in: &cancellables)

        settings.$showShortcutsModule
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard !self.viewModel.isCollapsing else { return }
                self.setPanelFrame(for: self.viewModel.mode)
            }
            .store(in: &cancellables)

        viewModel.$presentationPhase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self else { return }

                switch phase {
                case .expandingShell:
                    self.setPanelFrameToCurrentEnvelope()
                case .collapsed:
                    self.setPanelFrameToCurrentEnvelope()
                case .expanded:
                    self.setPanelFrameToCurrentEnvelope()
                    self.reconcilePointerHoverState()
                case .revealingContent, .hidingContent, .collapsingShell:
                    break
                }
            }
            .store(in: &cancellables)

        viewModel.$expandedContentOverflowHeight
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self,
                      self.viewModel.presentationPhase != .collapsed
                else { return }
                self.setPanelFrameToCurrentEnvelope(display: true)
            }
            .store(in: &cancellables)

        viewModel.$externalInteractiveFrame
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                if frame != nil {
                    self.hasActiveExternalInteractiveFrame = true
                    self.externalInteractionDismissGraceDeadline = nil
                    self.viewModel.cancelCollapse()
                } else if self.hasActiveExternalInteractiveFrame {
                    self.hasActiveExternalInteractiveFrame = false
                    self.externalInteractionDismissGraceDeadline = Date()
                        .addingTimeInterval(self.externalInteractionDismissGraceDelay)
                    self.collapseImmediatelyIfPointerOutsidePanel()
                }
            }
            .store(in: &cancellables)

        viewModel.$hoverPhase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                guard let self,
                      self.viewModel.presentationPhase == .collapsed
                else { return }
                self.updateCompactHoverState(at: NSEvent.mouseLocation)
            }
            .store(in: &cancellables)

        viewModel.$compactCapsuleSize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self else { return }
                self.trackingView?.compactCapsuleSize = size

                let geometry = NotchGeometryProvider.geometry(
                    for: self.panel?.screen ?? NSScreen.main,
                    capsuleWidth: size.width,
                    capsuleHeight: size.height
                )
                self.viewModel.updateNotchGeometry(geometry)

                self.setPanelFrameToCurrentEnvelope()
                self.updateCompactHoverState(at: NSEvent.mouseLocation)
            }
            .store(in: &cancellables)

        viewModel.$selectedTopTab
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tab in
                guard let self,
                      self.viewModel.mode == .expanded,
                      !self.viewModel.isCollapsing
                else {
                    return
                }
                self.trackingView?.expandedShellSize = IslandShellLayout.contentSize(
                    settings: self.settings,
                    selectedTopTab: tab
                )
                self.preparePanelFrameForTabTransition(to: tab)
            }
            .store(in: &cancellables)

        settings.$hideInFullscreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPanelVisibility()
            }
            .store(in: &cancellables)

        settings.$quickAppsSettingsTrigger
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settings.quickAppsSettingsTrigger = false
                self.openSettingsWindow(page: .quickApps, presentFeedback: false)
            }
            .store(in: &cancellables)

        settings.$shortcutsSettingsTrigger
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settings.shortcutsSettingsTrigger = false
                self.openSettingsWindow(page: .shortcuts, presentFeedback: false)
            }
            .store(in: &cancellables)
    }

    @objc private func screenParametersDidChange() {
        guard updateCompactCapsuleMetrics() else {
            viewModel.collapse()
            panel?.orderOut(nil)
            showUnsupportedHardwareAlert()
            return
        }
        positionPanel()
        applyPanelVisibility()
    }

    @objc private func workspaceVisibilityDidChange() {
        applyPanelVisibility()
    }

    private func applyPanelVisibility() {
        guard let panel else { return }
        applyPanelCollectionBehavior()

        guard settings.isIslandEnabled else {
            viewModel.collapse()
            panel.orderOut(nil)
            return
        }

        if settings.hideInFullscreen, isFullscreenAppActive() {
            viewModel.collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func applyPanelCollectionBehavior() {
        guard let panel else { return }

        panel.level = .mainMenu + 3
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]
        if !settings.hideInFullscreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior
    }

    private func isFullscreenAppActive() -> Bool {
        guard let screen = NSScreen.main,
              let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return false
        }

        let screenFrame = screen.frame
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == activeApp.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = cgFloat(from: bounds["X"]),
                  let y = cgFloat(from: bounds["Y"]),
                  let width = cgFloat(from: bounds["Width"]),
                  let height = cgFloat(from: bounds["Height"])
            else {
                return false
            }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)
            return abs(windowFrame.width - screenFrame.width) < 4
                && abs(windowFrame.height - screenFrame.height) < 4
                && abs(windowFrame.minX - screenFrame.minX) < 4
                && abs(windowFrame.minY - screenFrame.minY) < 4
        }
    }

    private func cgFloat(from value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? NSNumber {
            return CGFloat(truncating: value)
        }
        return nil
    }

    private func openAirDrop() {
        let airDropURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        if FileManager.default.fileExists(atPath: airDropURL.path) {
            NSWorkspace.shared.open(airDropURL)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }
    }

    private func shareViaAirDrop(_ urls: [URL]) {
        if let airDropService = NSSharingService(named: .sendViaAirDrop) {
            airDropService.perform(withItems: urls)
        } else {
            openAirDrop()
        }
    }

    private func openSettingsFromIsland() {
        openSettingsWindow(page: .home, presentFeedback: false)
    }

    private func openTodoSettingsFromIsland() {
        openSettingsWindow(page: .todo, presentFeedback: false)
    }

    private func openFeedbackFromIsland() {
        openSettingsWindow(page: .about, presentFeedback: true)
    }

    private func openSettingsWindow(page: SettingsPage, presentFeedback: Bool) {
        viewModel.cancelCollapse()

        // The island is a non-activating status-bar panel. Deferring the settings
        // window presentation to the next main-loop turn prevents AppKit from
        // swallowing makeKey/orderFront while the custom island menu is closing.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.settingsWindowController.show(page: page, presentFeedback: presentFeedback)
        }
    }
}

private final class IslandTrackingView: NSView {
    private static let internalFileDragType = NSPasteboard.PasteboardType("com.personal.dynamicnook.folder-file-url")

    var onMouseInsideChanged: ((Bool) -> Void)?
    var onCameraAreaHoverChanged: ((Bool) -> Void)?
    var onFileDragChanged: ((Bool, IslandFileDropTarget?, String?) -> Void)?
    var onFileDrop: (([URL], IslandFileDropTarget?) -> Bool)?
    var compactCapsuleSize = IslandDesignTokens.defaultCompactCapsuleSize
    var expandedShellSize = CGSize(width: 900, height: 260)

    private var trackingArea: NSTrackingArea?
    private var isFileDropActive = false
    private var isCameraAreaHovered = false

    deinit {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        unregisterDraggedTypes()
        clearHandlers()
    }

    func clearHandlers() {
        onMouseInsideChanged = nil
        onCameraAreaHoverChanged = nil
        onFileDragChanged = nil
        onFileDrop = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseInsideChanged?(true)
        updateCameraHoverState(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateCameraHoverState(for: event)
        onMouseInsideChanged?(false)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCameraHoverState(for: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDrop(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDrop(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isFileDropActive = false
        onFileDragChanged?(false, nil, nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isInternalFileDrag(sender) else {
            isFileDropActive = false
            onFileDragChanged?(false, nil, nil)
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        let target = fileDropTarget(for: point)
        let urls = fileURLs(from: sender)

        isFileDropActive = false
        guard !urls.isEmpty else {
            onFileDragChanged?(false, nil, nil)
            return false
        }

        let didDrop = onFileDrop?(urls, target) ?? false
        if !didDrop {
            onFileDragChanged?(false, nil, nil)
        }

        return didDrop
    }

    private func updateFileDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isInternalFileDrag(sender) else {
            isFileDropActive = false
            onFileDragChanged?(false, nil, nil)
            return []
        }

        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return [] }

        let point = convert(sender.draggingLocation, from: nil)
        let shouldActivate = isFileDropActive || compactCapsuleContains(point) || fileDropTarget(for: point) != nil
        guard shouldActivate else { return [] }

        isFileDropActive = true
        onFileDragChanged?(true, fileDropTarget(for: point), previewName(for: urls))
        return .copy
    }

    private func isInternalFileDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(Self.internalFileDragType) == true
    }

    private func updateCameraHoverState(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let isHovering = compactCapsuleContains(point)
        guard isCameraAreaHovered != isHovering else { return }
        isCameraAreaHovered = isHovering
        onCameraAreaHoverChanged?(isHovering)
    }

    private var compactCapsuleHitRect: NSRect {
        return NSRect(
            x: bounds.midX - compactCapsuleSize.width / 2,
            y: bounds.maxY - compactCapsuleSize.height,
            width: compactCapsuleSize.width,
            height: compactCapsuleSize.height
        )
    }

    private func compactCapsuleContains(_ point: NSPoint) -> Bool {
        let rect = compactCapsuleHitRect
        guard rect.contains(point) else { return false }

        let metrics = IslandShellLayout.shellShapeMetrics(
            shellSize: rect.size,
            compactSize: compactCapsuleSize,
            morphProgress: 0
        )
        let shape = DynamicIslandShape(
            shoulderWidth: metrics.shoulderWidth,
            shoulderDepth: metrics.shoulderDepth,
            sideInset: metrics.sideInset,
            bottomCornerRadius: metrics.bottomCornerRadius,
            visibleSize: rect.size
        )

        return shape.path(in: rect).contains(point)
    }

    private var expandedShellRect: NSRect {
        NSRect(
            x: bounds.midX - expandedShellSize.width / 2,
            y: bounds.maxY - expandedShellSize.height,
            width: expandedShellSize.width,
            height: expandedShellSize.height
        )
    }

    private func fileDropTarget(for point: NSPoint) -> IslandFileDropTarget? {
        let shellRect = expandedShellRect
        guard shellRect.width >= 520,
              shellRect.height >= 240,
              shellRect.contains(point)
        else { return nil }

        let localPoint = NSPoint(
            x: point.x - shellRect.minX,
            y: point.y - shellRect.minY
        )

        let horizontalPadding: CGFloat = 72
        let spacing: CGFloat = 22
        let zoneHeight: CGFloat = 170
        let topOffset: CGFloat = 108
        let zoneWidth = max(1, (shellRect.width - horizontalPadding * 2 - spacing) / 2)
        let y = shellRect.height - topOffset - zoneHeight
        let stagingRect = NSRect(
            x: horizontalPadding,
            y: y,
            width: zoneWidth,
            height: zoneHeight
        )
        let airDropRect = NSRect(
            x: horizontalPadding + zoneWidth + spacing,
            y: y,
            width: zoneWidth,
            height: zoneHeight
        )

        if stagingRect.contains(localPoint) {
            return .staging
        }
        if airDropRect.contains(localPoint) {
            return .airDrop
        }
        return nil
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        return sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { ($0 as? URL) ?? ($0 as? NSURL)?.absoluteURL } ?? []
    }

    private func previewName(for urls: [URL]) -> String? {
        if urls.count == 1 {
            return urls[0].lastPathComponent
        }
        return "\(urls.count) 个项目"
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var shouldReceiveMouseEvents: (() -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldReceiveMouseEvents?() == true else {
            return nil
        }
        return super.hitTest(point) ?? self
    }
}
