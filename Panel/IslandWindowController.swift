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
    private var workspaceVisibilitySettlementTask: Task<Void, Never>?
    private var settingsPresentationTask: Task<Void, Never>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var didShowUnsupportedHardwareAlert = false
    private var hasActiveExternalInteractiveFrame = false
    private var externalInteractionDismissGraceDeadline: Date?
    private var tabTransitionPointerOrigin: NSPoint?
    private var tabTransitionPointerTargetRect: NSRect?
    private var isExternalFileDragSessionActive = false
    private var fileDropHoverSuppressionRect: NSRect?
    private var requiresFreshNotchHoverAfterFileDrop = false
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
        workspaceVisibilitySettlementTask?.cancel()
        settingsPresentationTask?.cancel()
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
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange),
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
            self?.handleCameraAreaHoverChanged(isHovering)
        }
        trackingView.onFileDragChanged = { [weak self] isActive, target, previewName in
            guard let self else { return }
            if isActive {
                self.viewModel.beginFileDrop(previewName: previewName)
                self.viewModel.updateFileDropTarget(target)
            } else {
                self.viewModel.finishFileDropInteraction()
            }
        }
        trackingView.onExternalFileDragSessionChanged = { [weak self] isActive in
            self?.handleExternalFileDragSessionChanged(isActive)
        }
        trackingView.shouldActivateFileDrop = { [weak self, weak trackingView] point in
            guard let self,
                  let trackingView,
                  let window = trackingView.window
            else { return false }

            let windowPoint = trackingView.convert(point, to: nil)
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            return self.fileDropActivationRect.contains(screenPoint)
        }
        trackingView.shouldRetainFileDropAfterExit = { [weak self] screenPoint in
            self?.fileDropActivationRect.contains(screenPoint) == true
        }
        trackingView.onFileDrop = { [weak self] urls, target in
            guard let self, let target else { return false }
            self.viewModel.finishFileDropInteraction()

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
        if viewModel.isFileDropChooserVisible {
            setPanelFrameForFileDropChooser(display: display)
            return
        }
        setPanelFrameToCurrentEnvelope(display: display)
    }

    private func setPanelFrameForFileDropChooser(display: Bool = false) {
        trackingView?.expandedShellSize = IslandFileDropLayout.size
        guard let panel else { return }

        let targetRect = panelRect(
            for: IslandFileDropLayout.windowSize(
                for: viewModel.fileDropShellCanvasSize
            )
        )
        let envelopeSize = CGSize(
            width: max(panel.frame.width, targetRect.width),
            height: max(panel.frame.height, targetRect.height)
        )
        // Keep the transparent host at its envelope for the whole drag. Shrinking
        // it at the end of the SwiftUI animation forced a second full layout pass
        // and produced the visible hitch reported during expanded-to-drop morphs.
        applyPanelFrame(
            panelRect(for: envelopeSize),
            display: display,
            layoutImmediately: false
        )
    }

    private func preparePanelFrameForFileDropRestoration(to tab: IslandTopTab) {
        guard let panel else { return }

        let targetSize = panelEnvelopeSize(selectedTopTab: tab)
        let envelopeSize = CGSize(
            width: max(panel.frame.width, targetSize.width),
            height: max(panel.frame.height, targetSize.height)
        )
        applyPanelFrame(panelRect(for: envelopeSize), display: false)
    }

    private func restoreExpandedShellTrackingSize() {
        trackingView?.expandedShellSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: viewModel.selectedTopTab
        )
    }

    private func setPanelFrameToCurrentEnvelope(
        display: Bool = false,
        selectedTopTab: IslandTopTab? = nil
    ) {
        guard panel != nil else { return }

        trackingView?.expandedShellSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: selectedTopTab ?? viewModel.selectedTopTab
        )

        let targetRect = panelEnvelopeRect(selectedTopTab: selectedTopTab)
        applyPanelFrame(targetRect, display: display)
    }

    private func preparePanelFrameForTabTransition(to tab: IslandTopTab) {
        guard let panel else { return }

        let targetSize = panelEnvelopeSize(selectedTopTab: tab)
        beginTabTransitionPointerOwnership(
            retaining: currentInteractiveShellRect,
            target: interactiveShellRect(
                for: IslandShellLayout.contentSize(
                    settings: settings,
                    selectedTopTab: tab
                )
            )
        )
        let envelopeSize = CGSize(
            width: max(panel.frame.width, targetSize.width),
            height: max(panel.frame.height, targetSize.height)
        )
        let envelopeRect = panelRect(for: envelopeSize)

        // The SwiftUI shell owns the visible size transition. Keep AppKit's
        // transparent host at the shared envelope until the island collapses;
        // shrinking it again at the same animation boundary races SwiftUI's
        // canvas settlement and produces an intermittent one-frame bounce.
        // IslandHostingView still passes events outside the visual shell through.
        applyPanelFrame(envelopeRect, display: false)
    }

    private func applyPanelFrame(
        _ rect: NSRect,
        display: Bool,
        layoutImmediately: Bool = true
    ) {
        guard let panel else { return }
        if panel.frame != rect {
            panel.setFrame(rect, display: display)
        }

        if layoutImmediately {
            panel.contentView?.setFrameSize(rect.size)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func handleMouseInsideChanged(_ isInside: Bool) {
        if viewModel.isFileDropChooserVisible {
            viewModel.cancelCollapse()
            return
        }

        if isExternalFileDragSessionActive || NSEvent.pressedMouseButtons != 0 {
            viewModel.cancelPendingCapsuleExpand()
            return
        }

        if shouldSuppressHoverAfterFileDrop(at: NSEvent.mouseLocation) {
            return
        }

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
        // Reserve one envelope for all workbench tabs so edge clamping cannot move the capsule on a tab switch.
        let expandedEnvelope = [IslandTopTab.home, .applications, .files].reduce(CGSize.zero) { size, tab in
            let candidate = IslandShellLayout.openingWindowEnvelopeSize(settings: settings, selectedTopTab: tab)
            return CGSize(width: max(size.width, candidate.width), height: max(size.height, candidate.height))
        }
        let expandedOverflowHeight = viewModel.presentationPhase == .collapsed
            ? 0
            : viewModel.expandedContentOverflowHeight
        let compactEnvelope = CGSize(
            width: viewModel.compactCapsuleSize.width
                * IslandDesignTokens.compactHoverWidthScale + 40,
            height: viewModel.compactCapsuleSize.height * IslandDesignTokens.compactHoverHeightScale
                + IslandDesignTokens.applicationsWindowVerticalPadding
        )
        let fileDropSourceSize = CGSize(
            width: viewModel.compactCapsuleSize.width
                * IslandDesignTokens.compactHoverWidthScale,
            height: viewModel.compactCapsuleSize.height
                * IslandDesignTokens.compactHoverHeightScale
        )
        let fileDropCanvas = IslandFileDropLayout.openingCanvasSize(
            from: fileDropSourceSize,
            bounce: settings.bounceLevel
        )
        let fileDropEnvelope = IslandFileDropLayout.windowSize(for: fileDropCanvas)

        return CGSize(
            width: max(
                max(expandedEnvelope.width, compactEnvelope.width),
                fileDropEnvelope.width
            ),
            height: max(
                max(
                    expandedEnvelope.height + expandedOverflowHeight,
                    compactEnvelope.height
                ),
                fileDropEnvelope.height
            )
        )
    }

    private var preferredScreen: NSScreen? {
        NSScreen.screens.first { !$0.nookFlowDisplayID.isEmpty && $0.nookFlowDisplayID == settings.preferredDisplayID }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func panelRect(for size: CGSize) -> NSRect {
        guard let screen = preferredScreen else { return NSRect(origin: .zero, size: size) }
        let scale = max(1, screen.backingScaleFactor)
        let width = ceil(size.width * scale) / scale
        let height = ceil(size.height * scale) / scale
        if let center = NotchGeometryProvider.cameraSafeRegionCenterX(for: screen) {
            let screenFrame = screen.frame
            let screenTop = ceil(screenFrame.maxY * scale) / scale
            let topEdgeBleed = IslandDesignTokens.shellTopEdgeBleedPhysicalPixels / scale
            let y = screenTop + topEdgeBleed - height
            return NSRect(x: round((center - width / 2) * scale) / scale,
                          y: y, width: width, height: height)
        }
        return NotchGeometryProvider.floatingPanelRect(size: size, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame, scale: scale,
            horizontalPosition: settings.floatingHorizontalPosition, topInset: settings.floatingTopInset,
            anchorHeight: viewModel.compactCapsuleSize.height)
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
        let screen = preferredScreen
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
        guard let screen else { return nil }
        guard let cameraCapsule = NotchGeometryProvider.cameraCapsuleSize(for: screen) else {
            let compact = CGSize(width: 220, height: 36)
            return (compact, compact, CGSize(width: compactLyricsWidth(cameraWidth: 0, screenWidth: screen.frame.width), height: 36))
        }

        let cameraWidth = max(1, cameraCapsule.width)
        // Reveal a restrained edge outside the system-reported camera gap.
        let cameraShellWidth = cameraWidth
            + IslandDesignTokens.compactCameraShellHorizontalExtension * 2
        let scale = max(1, screen.backingScaleFactor)
        // The host intentionally bleeds beyond the display edge. Add the same
        // physical amount to the compact shell so its visible bottom still
        // reaches the menu-bar boundary instead of ending two pixels early.
        let topEdgeBleed = IslandDesignTokens.shellTopEdgeBleedPhysicalPixels / scale
        let height = max(1, cameraCapsule.height + topEdgeBleed)
        let displayAlignedHeight = ceil(height * scale) / scale
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
            CGSize(width: ceil(cameraShellWidth), height: displayAlignedHeight),
            CGSize(width: ceil(statusWidth), height: displayAlignedHeight),
            CGSize(width: ceil(lyricWidth), height: displayAlignedHeight)
        )
    }

    private func compactLyricsWidth(cameraWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        CapsuleLyricsLayout.fittedWidth(
            settings.capsuleLyricsWidth, cameraWidth: cameraWidth,
            maximumWidth: screenWidth * IslandDesignTokens.compactLyricsCapsuleMaximumScreenRatio
        )
    }

    private func showUnsupportedHardwareAlert() {
        guard !didShowUnsupportedHardwareAlert else { return }
        didShowUnsupportedHardwareAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "未检测到可用显示器"
        alert.informativeText = "连接显示器后，NookFlow 会重新定位。宽刘海使用原有布局，无刘海屏幕使用悬浮胶囊。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func collapseImmediatelyIfPointerOutsidePanel() {
        if shouldRetainTabTransitionPointerOwnership(at: NSEvent.mouseLocation) {
            return
        }

        if isPointerInsidePanel {
            clearTabTransitionPointerOwnership()
            viewModel.cancelCollapse()
            externalInteractionDismissGraceDeadline = nil
        } else {
            viewModel.scheduleCollapse(delay: pointerExitCollapseDelay())
        }
    }

    /// A tab click can make the island narrower than the point that initiated
    /// the click. Preserve only a tapered intent corridor from that point into
    /// the new shell. This permits deliberate travel to the selected page while
    /// restoring ordinary dismissal as soon as the pointer heads elsewhere.
    private func beginTabTransitionPointerOwnership(
        retaining retentionRect: NSRect,
        target targetRect: NSRect
    ) {
        let hitPadding: CGFloat = 4
        let paddedRetentionRect = retentionRect.insetBy(dx: -hitPadding, dy: -hitPadding)
        let pointer = NSEvent.mouseLocation
        let paddedTargetRect = targetRect.insetBy(dx: -hitPadding, dy: -hitPadding)
        guard paddedRetentionRect.contains(pointer),
              !paddedTargetRect.contains(pointer)
        else {
            clearTabTransitionPointerOwnership()
            return
        }

        tabTransitionPointerOrigin = pointer
        tabTransitionPointerTargetRect = paddedTargetRect
        viewModel.cancelCollapse()
    }

    private func shouldRetainTabTransitionPointerOwnership(at point: NSPoint) -> Bool {
        guard let origin = tabTransitionPointerOrigin,
              let targetRect = tabTransitionPointerTargetRect
        else {
            return false
        }

        if targetRect.contains(point) {
            clearTabTransitionPointerOwnership()
            return false
        }

        guard tabTransitionIntentCorridorContains(
            point,
            origin: origin,
            targetRect: targetRect
        ) else {
            clearTabTransitionPointerOwnership()
            return false
        }

        viewModel.cancelCollapse()
        return true
    }

    private func tabTransitionIntentCorridorContains(
        _ point: NSPoint,
        origin: NSPoint,
        targetRect: NSRect
    ) -> Bool {
        let originPadding: CGFloat = 8

        if origin.x < targetRect.minX {
            return pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x, y: origin.y - originPadding),
                NSPoint(x: origin.x, y: origin.y + originPadding),
                NSPoint(x: targetRect.minX, y: targetRect.maxY)
            ) || pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x, y: origin.y - originPadding),
                NSPoint(x: targetRect.minX, y: targetRect.maxY),
                NSPoint(x: targetRect.minX, y: targetRect.minY)
            )
        }

        if origin.x > targetRect.maxX {
            return pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x, y: origin.y - originPadding),
                NSPoint(x: targetRect.maxX, y: targetRect.minY),
                NSPoint(x: targetRect.maxX, y: targetRect.maxY)
            ) || pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x, y: origin.y - originPadding),
                NSPoint(x: targetRect.maxX, y: targetRect.maxY),
                NSPoint(x: origin.x, y: origin.y + originPadding)
            )
        }

        if origin.y < targetRect.minY {
            return pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x - originPadding, y: origin.y),
                NSPoint(x: targetRect.minX, y: targetRect.minY),
                NSPoint(x: targetRect.maxX, y: targetRect.minY)
            ) || pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x - originPadding, y: origin.y),
                NSPoint(x: targetRect.maxX, y: targetRect.minY),
                NSPoint(x: origin.x + originPadding, y: origin.y)
            )
        }

        if origin.y > targetRect.maxY {
            return pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x - originPadding, y: origin.y),
                NSPoint(x: origin.x + originPadding, y: origin.y),
                NSPoint(x: targetRect.maxX, y: targetRect.maxY)
            ) || pointInTabTransitionTriangle(
                point,
                NSPoint(x: origin.x - originPadding, y: origin.y),
                NSPoint(x: targetRect.maxX, y: targetRect.maxY),
                NSPoint(x: targetRect.minX, y: targetRect.maxY)
            )
        }

        return false
    }

    private func pointInTabTransitionTriangle(
        _ point: NSPoint,
        _ first: NSPoint,
        _ second: NSPoint,
        _ third: NSPoint
    ) -> Bool {
        func signedArea(_ point1: NSPoint, _ point2: NSPoint, _ point3: NSPoint) -> CGFloat {
            (point1.x - point3.x) * (point2.y - point3.y)
                - (point2.x - point3.x) * (point1.y - point3.y)
        }

        let area1 = signedArea(point, first, second)
        let area2 = signedArea(point, second, third)
        let area3 = signedArea(point, third, first)
        let hasNegative = area1 < 0 || area2 < 0 || area3 < 0
        let hasPositive = area1 > 0 || area2 > 0 || area3 > 0
        return !(hasNegative && hasPositive)
    }

    private func clearTabTransitionPointerOwnership() {
        tabTransitionPointerOrigin = nil
        tabTransitionPointerTargetRect = nil
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
        if viewModel.isFileDropChooserVisible {
            let shellRect = visualShellRect(for: IslandFileDropLayout.size)
            return shellRect.union(externalPinButtonHitRect(attachedTo: shellRect))
        }

        switch viewModel.presentationPhase {
        case .collapsed:
            return compactCapsuleHitRect
        case .expandingShell, .loadingContent:
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

    private var fileDropActivationRect: NSRect {
        let interactiveRect = currentInteractiveShellRect
        guard viewModel.presentationPhase == .collapsed,
              !viewModel.isFileDropChooserVisible
        else {
            return interactiveRect
        }

        return NSRect(
            x: interactiveRect.minX - IslandFileDropLayout.compactActivationHorizontalPadding,
            y: interactiveRect.minY - IslandFileDropLayout.compactActivationBottomPadding,
            width: interactiveRect.width
                + IslandFileDropLayout.compactActivationHorizontalPadding * 2,
            height: interactiveRect.height
                + IslandFileDropLayout.compactActivationBottomPadding
        )
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
        let pinAnchorSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: viewModel.selectedTopTab
        )
        let pinAnchorRect = visualShellRect(for: pinAnchorSize)
        return interactiveRect.union(externalPinButtonHitRect(attachedTo: pinAnchorRect))
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
            matching: [.mouseMoved]
        ) { [weak self] event in
            self?.handlePointerMoved(at: NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved]
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
        guard !isExternalFileDragSessionActive,
              NSEvent.pressedMouseButtons == 0,
              !viewModel.isFileDropChooserVisible,
              !shouldSuppressHoverAfterFileDrop(at: globalPoint),
              viewModel.presentationPhase == .collapsed
        else { return }
        viewModel.updateCameraHover(compactCapsuleContains(globalPoint))
    }

    private func handleCameraAreaHoverChanged(_ isHovering: Bool) {
        guard !isExternalFileDragSessionActive,
              NSEvent.pressedMouseButtons == 0,
              !viewModel.isFileDropChooserVisible,
              !shouldSuppressHoverAfterFileDrop(at: NSEvent.mouseLocation)
        else {
            viewModel.cancelPendingCapsuleExpand()
            return
        }
        viewModel.updateCameraHover(isHovering)
    }

    private func handleExternalFileDragSessionChanged(_ isActive: Bool) {
        guard isExternalFileDragSessionActive != isActive else { return }
        isExternalFileDragSessionActive = isActive

        if isActive {
            workspaceVisibilitySettlementTask?.cancel()
            workspaceVisibilitySettlementTask = nil
            viewModel.cancelPendingCapsuleExpand()
        } else if !viewModel.isFileDropChooserVisible {
            schedulePanelVisibilityReconciliation(delay: 0.30)
        }
    }

    private func handlePointerMoved(at globalPoint: NSPoint) {
        guard !viewModel.isFileDropChooserVisible else {
            viewModel.cancelCollapse()
            return
        }

        guard !shouldSuppressHoverAfterFileDrop(
            at: globalPoint,
            allowsRelease: true
        ) else {
            return
        }

        if viewModel.presentationPhase == .collapsed {
            updateCompactHoverState(at: globalPoint)
        } else {
            reconcilePointerHoverState()
        }
    }

    private func shouldSuppressHoverAfterFileDrop(
        at globalPoint: NSPoint,
        allowsRelease: Bool = false
    ) -> Bool {
        guard requiresFreshNotchHoverAfterFileDrop else {
            return false
        }

        if let suppressionRect = fileDropHoverSuppressionRect,
           suppressionRect.contains(globalPoint) {
            return true
        }

        fileDropHoverSuppressionRect = nil

        guard allowsRelease,
              viewModel.presentationPhase == .collapsed,
              compactCapsuleContains(globalPoint)
        else {
            return true
        }

        requiresFreshNotchHoverAfterFileDrop = false
        return false
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
        settings.$capsuleLyricsWidth
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _ = self.updateCompactCapsuleMetrics()
                self.setPanelFrameToCurrentEnvelope()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(settings.$preferredDisplayID, settings.$floatingHorizontalPosition, settings.$floatingTopInset)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                _ = self.updateCompactCapsuleMetrics()
                self.positionPanel()
                self.applyPanelVisibility()
            }
            .store(in: &cancellables)

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

        Publishers.CombineLatest3(
            settings.$showWeatherModule,
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

        Publishers.CombineLatest3(
            settings.$showImageCardModule,
            settings.$showDeviceInfoModule,
            settings.$showMirrorModule
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            guard !self.viewModel.isCollapsing else { return }
            self.setPanelFrame(for: self.viewModel.mode)
        }
        .store(in: &cancellables)

        LicenseManager.shared.$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.viewModel.playbackProvider.updateAccessConfiguration(from: self.settings)
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
                    self.setPanelFrame(for: self.viewModel.mode)
                case .collapsed:
                    self.clearTabTransitionPointerOwnership()
                    self.restoreExpandedShellTrackingSize()
                    self.setPanelFrameToCurrentEnvelope()
                case .expanded:
                    self.setPanelFrame(for: self.viewModel.mode)
                    self.reconcilePointerHoverState()
                case .loadingContent, .hidingContent, .collapsingShell:
                    break
                }
            }
            .store(in: &cancellables)

        viewModel.$isFileDropChooserVisible
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    self.fileDropHoverSuppressionRect = nil
                    self.requiresFreshNotchHoverAfterFileDrop = false
                    // Mission Control can activate Dock and change Spaces while a
                    // file is held at the screen edge. Cancel any queued visibility
                    // scan so it cannot compete with the chooser's opening frames.
                    self.workspaceVisibilitySettlementTask?.cancel()
                    self.workspaceVisibilitySettlementTask = nil
                    // Resize the transparent host without forcing AppKit to draw
                    // the outgoing island before SwiftUI commits the chooser.
                    self.setPanelFrameForFileDropChooser(display: false)
                } else {
                    self.fileDropHoverSuppressionRect = self
                        .visualShellRect(for: IslandFileDropLayout.size)
                        .insetBy(dx: -8, dy: -8)
                    self.requiresFreshNotchHoverAfterFileDrop = true
                    self.viewModel.cancelPendingCapsuleExpand()
                    self.restoreExpandedShellTrackingSize()
                    self.setPanelFrameToCurrentEnvelope(display: false)
                    self.schedulePanelVisibilityReconciliation(delay: 0.30)
                }
            }
            .store(in: &cancellables)

        viewModel.$fileDropRestorationTarget
            .compactMap { $0 }
            .sink { [weak self] tab in
                self?.preparePanelFrameForFileDropRestoration(to: tab)
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
                    for: self.preferredScreen,
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
                      !self.viewModel.isFileDropChooserVisible,
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

    @objc private func activeSpaceDidChange() {
        // The notification is delivered while Mission Control is still settling.
        // Reordering a high-level panel or enumerating every on-screen window here
        // steals frames from the file-drop shell animation.
        guard !isExternalFileDragSessionActive,
              !viewModel.isFileDropChooserVisible
        else { return }
        schedulePanelVisibilityReconciliation(delay: 0.28)
    }

    @objc private func activeApplicationDidChange() {
        // Application activation can fire several times during a Space gesture.
        // Coalesce those events into a single visibility pass.
        guard !isExternalFileDragSessionActive,
              !viewModel.isFileDropChooserVisible
        else { return }
        schedulePanelVisibilityReconciliation(delay: 0.10)
    }

    private func schedulePanelVisibilityReconciliation(delay: TimeInterval) {
        workspaceVisibilitySettlementTask?.cancel()
        workspaceVisibilitySettlementTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(delay * 1_000_000_000)
                )
            }
            guard let self, !Task.isCancelled else { return }
            self.workspaceVisibilitySettlementTask = nil
            self.applyPanelVisibility()
        }
    }

    private func applyPanelVisibility() {
        guard let panel else { return }
        applyPanelCollectionBehavior()

        guard settings.isIslandEnabled else {
            viewModel.collapse()
            panel.orderOut(nil)
            return
        }

        if isExternalFileDragSessionActive || viewModel.isFileDropChooserVisible {
            // The panel was already visible for AppKit to accept this drag.
            // Keep the drag interaction responsive and avoid the synchronous
            // CGWindowListCopyWindowInfo scan until the chooser is dismissed.
            if !panel.isVisible || !panel.isOnActiveSpace {
                panel.orderFrontRegardless()
            }
            return
        }

        if settings.hideInFullscreen, isFullscreenAppActive() {
            viewModel.collapse()
            panel.orderOut(nil)
        } else if !panel.isVisible || !panel.isOnActiveSpace {
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
        if panel.collectionBehavior != behavior {
            panel.collectionBehavior = behavior
        }
    }

    private func isFullscreenAppActive() -> Bool {
        guard let screen = preferredScreen,
              let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return false
        }

        let screenFrame = NotchGeometryProvider.windowServerScreenRect(
            for: screen.frame, primaryScreenFrame: NSScreen.screens.first?.frame ?? screen.frame
        )
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
        settingsPresentationTask?.cancel()

        // The island is a non-activating status-bar panel. Deferring the settings
        // window presentation to the next main-loop turn prevents AppKit from
        // swallowing makeKey/orderFront while the custom island menu is closing.
        settingsPresentationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.settingsWindowController.show(page: page, presentFeedback: presentFeedback)
            self.settingsPresentationTask = nil
        }
    }
}

private final class IslandTrackingView: NSView {
    private static let internalFileDragType = NSPasteboard.PasteboardType("com.personal.dynamicnook.folder-file-url")

    var onMouseInsideChanged: ((Bool) -> Void)?
    var onCameraAreaHoverChanged: ((Bool) -> Void)?
    var onFileDragChanged: ((Bool, IslandFileDropTarget?, String?) -> Void)?
    var onExternalFileDragSessionChanged: ((Bool) -> Void)?
    var onFileDrop: (([URL], IslandFileDropTarget?) -> Bool)?
    var shouldActivateFileDrop: ((NSPoint) -> Bool)?
    var shouldRetainFileDropAfterExit: ((NSPoint) -> Bool)?
    var compactCapsuleSize = IslandDesignTokens.defaultCompactCapsuleSize
    var expandedShellSize = CGSize(width: 900, height: 260)

    private var trackingArea: NSTrackingArea?
    private var isFileDropActive = false
    private var isCameraAreaHovered = false
    private var fileDropExitWorkItem: DispatchWorkItem?
    private var activeExternalDragSequenceNumber: Int?
    private var activeExternalDragURLs: [URL] = []
    private var activeExternalDragPreviewName: String?

    deinit {
        fileDropExitWorkItem?.cancel()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        unregisterDraggedTypes()
        clearHandlers()
    }

    func clearHandlers() {
        fileDropExitWorkItem?.cancel()
        fileDropExitWorkItem = nil
        onMouseInsideChanged = nil
        onCameraAreaHoverChanged = nil
        onFileDragChanged = nil
        onExternalFileDragSessionChanged = nil
        onFileDrop = nil
        shouldActivateFileDrop = nil
        shouldRetainFileDropAfterExit = nil
        activeExternalDragSequenceNumber = nil
        activeExternalDragURLs.removeAll(keepingCapacity: false)
        activeExternalDragPreviewName = nil
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
        if let sender, isInternalFileDrag(sender) {
            cancelPendingFileDropExit()
            return
        }

        let exitPoint = draggingScreenPoint(from: sender)
        if isFileDropActive,
           shouldRetainFileDropAfterExit?(exitPoint) == true {
            cancelPendingFileDropExit()
            onFileDragChanged?(true, nil, activeExternalDragPreviewName)
            return
        }

        scheduleFileDropExit()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        finishExternalFileDragSession(notifyInteractionEnded: true)
    }

    override func updateDraggingItemsForDrag(_ sender: NSDraggingInfo?) {
        guard let sender,
              isFileDropActive,
              !isInternalFileDrag(sender)
        else { return }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let maximumPreviewY = bounds.maxY - IslandFileDropLayout.dragPreviewSafeTopInset

        sender.enumerateDraggingItems(
            options: [],
            for: self,
            classes: [NSURL.self],
            searchOptions: options
        ) { draggingItem, _, _ in
            var frame = draggingItem.draggingFrame
            guard frame.height > 0, frame.maxY > maximumPreviewY else { return }
            frame.origin.y -= frame.maxY - maximumPreviewY
            draggingItem.draggingFrame = frame
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        cancelPendingFileDropExit()
        guard !isInternalFileDrag(sender) else {
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        let target = fileDropTarget(for: point)
        let payload = externalFileDragPayload(from: sender)
        let urls = payload.urls

        isFileDropActive = false
        guard !urls.isEmpty else {
            onFileDragChanged?(false, nil, nil)
            finishExternalFileDragSession(notifyInteractionEnded: false)
            return false
        }

        let didDrop = onFileDrop?(urls, target) ?? false
        if !didDrop {
            onFileDragChanged?(false, nil, nil)
        }
        finishExternalFileDragSession(notifyInteractionEnded: false)

        return didDrop
    }

    private func updateFileDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        cancelPendingFileDropExit()
        guard !isInternalFileDrag(sender) else {
            return []
        }

        let payload = externalFileDragPayload(from: sender)
        let urls = payload.urls
        guard !urls.isEmpty else { return [] }

        let point = convert(sender.draggingLocation, from: nil)
        let shouldActivate = isFileDropActive
            || (shouldActivateFileDrop?(point) ?? compactCapsuleContains(point))
            || fileDropTarget(for: point) != nil
        guard shouldActivate else { return [] }

        let wasFileDropActive = isFileDropActive
        isFileDropActive = true
        if !wasFileDropActive {
            updateDraggingItemsForDrag(sender)
        }
        onFileDragChanged?(true, fileDropTarget(for: point), payload.previewName)
        return .copy
    }

    private func scheduleFileDropExit() {
        fileDropExitWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileDropExitWorkItem = nil
            self.finishExternalFileDragSession(notifyInteractionEnded: true)
        }
        fileDropExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + IslandFileDropLayout.transientExitGraceDuration,
            execute: workItem
        )
    }

    private func cancelPendingFileDropExit() {
        fileDropExitWorkItem?.cancel()
        fileDropExitWorkItem = nil
    }

    private func isInternalFileDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(Self.internalFileDragType) == true
    }

    private func draggingScreenPoint(from sender: NSDraggingInfo?) -> NSPoint {
        guard let sender, let window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: sender.draggingLocation)
    }

    private func externalFileDragPayload(
        from sender: NSDraggingInfo
    ) -> (urls: [URL], previewName: String?) {
        let sequenceNumber = sender.draggingSequenceNumber
        if activeExternalDragSequenceNumber == sequenceNumber {
            return (activeExternalDragURLs, activeExternalDragPreviewName)
        }

        let urls = fileURLs(from: sender)
        activeExternalDragSequenceNumber = sequenceNumber
        activeExternalDragURLs = urls
        activeExternalDragPreviewName = previewName(for: urls)
        if !urls.isEmpty {
            onExternalFileDragSessionChanged?(true)
        }
        return (urls, activeExternalDragPreviewName)
    }

    private func finishExternalFileDragSession(notifyInteractionEnded: Bool) {
        cancelPendingFileDropExit()
        let wasDropActive = isFileDropActive
        let hadExternalSession = !activeExternalDragURLs.isEmpty

        isFileDropActive = false
        activeExternalDragSequenceNumber = nil
        activeExternalDragURLs.removeAll(keepingCapacity: false)
        activeExternalDragPreviewName = nil

        if notifyInteractionEnded, wasDropActive {
            onFileDragChanged?(false, nil, nil)
        }
        if hadExternalSession {
            onExternalFileDragSessionChanged?(false)
        }
    }

    private func updateCameraHoverState(for event: NSEvent) {
        guard !isFileDropActive, NSEvent.pressedMouseButtons == 0 else {
            if isCameraAreaHovered {
                isCameraAreaHovered = false
                onCameraAreaHoverChanged?(false)
            }
            return
        }

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
        guard shellRect.width >= IslandFileDropLayout.size.width,
              shellRect.height >= IslandFileDropLayout.size.height,
              shellRect.contains(point)
        else { return nil }

        let localPoint = NSPoint(
            x: point.x - shellRect.minX,
            y: point.y - shellRect.minY
        )

        let horizontalPadding = IslandFileDropLayout.horizontalPadding
        let spacing = IslandFileDropLayout.spacing
        let zoneHeight = IslandFileDropLayout.destinationHeight
        let topOffset = IslandFileDropLayout.destinationsTopInset
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldReceiveMouseEvents?() == true else {
            return nil
        }
        return super.hitTest(point) ?? self
    }
}
