import AppKit
import Combine
import CoreGraphics
import SwiftUI

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    var passesMouseEventsThrough = false

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        passesMouseEventsThrough ? nil : super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
final class DesktopLyricsWindowController: NSObject {
    private let playbackProvider: PlaybackProvider
    private let lyricsProvider: LyricsProvider
    private let settings: IslandSettings
    private let timelineController: LyricsTimelineController
    private let appearanceController = DesktopLyricsAppearanceController()
    private lazy var menuBarLyricsController = MenuBarLyricsController(
        playbackProvider: playbackProvider,
        lyricsProvider: lyricsProvider,
        settings: settings
    )
    private var panel: DesktopLyricsPanel?
    private var cancellables = Set<AnyCancellable>()
    private var dragStartOrigin: NSPoint?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?

    private let defaultPanelSize = CGSize(width: 180, height: 260)
    private let screenMargin: CGFloat = 28
    private let savedOriginXKey = "desktopLyrics.windowOrigin.x"
    private let savedOriginYKey = "desktopLyrics.windowOrigin.y"

    init(
        playbackProvider: PlaybackProvider,
        lyricsProvider: LyricsProvider,
        settings: IslandSettings
    ) {
        self.playbackProvider = playbackProvider
        self.lyricsProvider = lyricsProvider
        self.settings = settings
        timelineController = LyricsTimelineController(
            playbackProvider: playbackProvider,
            lyricsProvider: lyricsProvider
        )
        super.init()
    }

    func setup() {
        guard panel == nil else { return }

        let panel = DesktopLyricsPanel(
            contentRect: NSRect(origin: .zero, size: defaultPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        let hostingView = TransparentHostingView(
            rootView: DesktopLyricsView(
                timeline: timelineController,
                appearance: appearanceController,
                onDragChanged: { [weak self] translation in
                    self?.movePanel(translation: translation)
                },
                onDragEnded: { [weak self] in
                    self?.finishMovingPanel()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        self.panel = panel
        timelineController.start()
        appearanceController.setMode(settings.desktopLyricsColorMode)
        positionPanel(restoringSavedOrigin: true)
        observeState()
        applyInteractionState(settings.desktopLyricsInteractionEnabled)
        updateVisibility(for: playbackProvider.snapshot)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
        stopPointerTracking()
        menuBarLyricsController.close()
        timelineController.setWindowVisibility(false)
        timelineController.stop()
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    private func observeState() {
        playbackProvider.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.updateVisibility(for: snapshot)
            }
            .store(in: &cancellables)

        settings.$showDesktopLyrics
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateVisibility(for: self.playbackProvider.snapshot)
            }
            .store(in: &cancellables)

        settings.$lyricsPresentationMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateVisibility(for: self.playbackProvider.snapshot)
            }
            .store(in: &cancellables)

        LicenseManager.shared.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateVisibility(for: self.playbackProvider.snapshot)
            }
            .store(in: &cancellables)

        settings.$menuBarLyricsWidth
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.menuBarLyricsController.updateLayout()
            }
            .store(in: &cancellables)

        settings.$menuBarLyricsShowsPlaybackControls
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.menuBarLyricsController.updateLayout()
            }
            .store(in: &cancellables)

        settings.$desktopLyricsPosition
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearSavedOrigin()
                self?.positionPanel(restoringSavedOrigin: false)
            }
            .store(in: &cancellables)

        settings.$desktopLyricsInteractionEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyInteractionState(isEnabled)
            }
            .store(in: &cancellables)

        settings.$desktopLyricsColorMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.appearanceController.setMode(mode)
            }
            .store(in: &cancellables)

        timelineController.$contentWidth
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] width in
                self?.resizePanel(to: width)
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(for snapshot: PlaybackSnapshot) {
        guard let panel else { return }

        guard LicenseManager.shared.isProUnlocked,
              snapshot.isLive,
              settings.showDesktopLyrics else {
            dragStartOrigin = nil
            stopPointerTracking()
            timelineController.setPointerHovering(false)
            panel.orderOut(nil)
            menuBarLyricsController.hide()
            timelineController.setWindowVisibility(false)
            return
        }

        switch settings.lyricsPresentationMode {
        case .capsule:
            dragStartOrigin = nil
            stopPointerTracking()
            timelineController.setPointerHovering(false)
            panel.orderOut(nil)
            menuBarLyricsController.hide()
            timelineController.setWindowVisibility(false)
        case .desktop:
            menuBarLyricsController.hide()
            panel.orderFrontRegardless()
            if settings.desktopLyricsInteractionEnabled {
                stopPointerTracking()
                timelineController.setPointerHovering(false)
            } else {
                startPointerTracking()
            }
            updatePointerHoverState()
        case .menuBar:
            dragStartOrigin = nil
            stopPointerTracking()
            timelineController.setPointerHovering(false)
            panel.orderOut(nil)
            menuBarLyricsController.show()
            timelineController.setWindowVisibility(false)
        }
    }

    private func applyInteractionState(_ isEnabled: Bool) {
        timelineController.isInteractionEnabled = isEnabled
        if !isEnabled {
            dragStartOrigin = nil
        }
        panel?.ignoresMouseEvents = !isEnabled

        if isEnabled {
            stopPointerTracking()
            timelineController.setPointerHovering(false)
        } else if panel?.isVisible == true, settings.lyricsPresentationMode == .desktop {
            startPointerTracking()
        }
        updatePointerHoverState()
    }

    private func startPointerTracking() {
        guard localPointerMonitor == nil, globalPointerMonitor == nil else {
            updatePointerHoverState()
            return
        }

        localPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updatePointerHoverState()
            }
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePointerHoverState()
            }
        }
        updatePointerHoverState()
    }

    private func stopPointerTracking() {
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
    }

    private func updatePointerHoverState() {
        guard let panel,
              panel.isVisible,
              settings.lyricsPresentationMode == .desktop
        else {
            timelineController.setPointerHovering(false)
            return
        }
        guard !settings.desktopLyricsInteractionEnabled else {
            timelineController.setPointerHovering(false)
            timelineController.setWindowVisibility(panel.alphaValue > 0)
            return
        }

        let isHovering = desktopLyricsHoverRegion(in: panel)
            .contains(NSEvent.mouseLocation)
        timelineController.setPointerHovering(isHovering)
        timelineController.setWindowVisibility(panel.alphaValue > 0 && !isHovering)
    }

    private func desktopLyricsHoverRegion(in panel: NSPanel) -> NSRect {
        let height = min(
            panel.frame.height,
            CGFloat(timelineController.visibleLineCount)
                * timelineController.fixedLineHeight
        )
        let centerY = panel.frame.minY
            + panel.frame.height * (1 - timelineController.anchorRatio)
        return NSRect(
            x: panel.frame.minX,
            y: centerY - height / 2,
            width: panel.frame.width,
            height: height
        )
    }

    private func positionPanel(restoringSavedOrigin: Bool) {
        guard let panel else { return }

        let size = panel.frame.size
        let origin: NSPoint
        if restoringSavedOrigin, let savedOrigin = savedOrigin() {
            origin = clampedOrigin(savedOrigin, for: size)
        } else {
            origin = defaultOrigin(for: settings.desktopLyricsPosition, size: size)
        }

        panel.setFrameOrigin(origin)
        timelineController.windowPosition = origin
        updatePointerHoverState()
    }

    private func defaultOrigin(for position: DesktopLyricsPosition, size: CGSize) -> NSPoint {
        let frame = preferredScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x: CGFloat
        let y: CGFloat

        switch position {
        case .topLeft:
            x = frame.minX + screenMargin
            y = frame.maxY - size.height - screenMargin
        case .topCenter:
            x = frame.midX - size.width / 2
            y = frame.maxY - size.height - screenMargin
        case .topRight:
            x = frame.maxX - size.width - screenMargin
            y = frame.maxY - size.height - screenMargin
        case .bottomLeft:
            x = frame.minX + screenMargin
            y = frame.minY + screenMargin
        case .bottomCenter:
            x = frame.midX - size.width / 2
            y = frame.minY + screenMargin
        case .bottomRight:
            x = frame.maxX - size.width - screenMargin
            y = frame.minY + screenMargin
        }

        return NSPoint(x: x, y: y)
    }

    private func resizePanel(to requestedWidth: CGFloat) {
        guard let panel else { return }

        let visibleFrame = panel.screen?.visibleFrame ?? preferredScreen?.visibleFrame
        let maximumWidth = max(120, (visibleFrame?.width ?? requestedWidth) - screenMargin * 2)
        let width = min(max(80, requestedWidth), maximumWidth)
        guard abs(panel.frame.width - width) > 0.5 else { return }

        let oldFrame = panel.frame
        var origin = oldFrame.origin
        switch settings.desktopLyricsPosition {
        case .topCenter, .bottomCenter:
            origin.x = oldFrame.midX - width / 2
        case .topRight, .bottomRight:
            origin.x = oldFrame.maxX - width
        case .topLeft, .bottomLeft:
            break
        }

        let targetFrame = NSRect(
            origin: clampedOrigin(origin, for: CGSize(width: width, height: oldFrame.height)),
            size: CGSize(width: width, height: oldFrame.height)
        )
        panel.setFrame(targetFrame, display: true)
        timelineController.windowPosition = targetFrame.origin
        updatePointerHoverState()
    }

    private func movePanel(translation: CGSize) {
        guard timelineController.isInteractionEnabled, let panel else { return }

        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let dragStartOrigin else { return }

        let proposed = NSPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        )
        let origin = clampedOrigin(proposed, for: panel.frame.size)
        panel.setFrameOrigin(origin)
        timelineController.windowPosition = origin
    }

    private func finishMovingPanel() {
        guard timelineController.isInteractionEnabled, let panel else { return }
        dragStartOrigin = nil
        saveOrigin(panel.frame.origin)
    }

    private func clampedOrigin(_ origin: NSPoint, for size: CGSize) -> NSPoint {
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(NSRect(origin: origin, size: size)) })
            ?? preferredScreen
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return origin }

        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - size.width),
            y: min(max(origin.y, frame.minY), frame.maxY - size.height)
        )
    }

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: savedOriginXKey) != nil,
              defaults.object(forKey: savedOriginYKey) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: savedOriginXKey),
            y: defaults.double(forKey: savedOriginYKey)
        )
    }

    private func saveOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: savedOriginXKey)
        defaults.set(origin.y, forKey: savedOriginYKey)
    }

    private func clearSavedOrigin() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: savedOriginXKey)
        defaults.removeObject(forKey: savedOriginYKey)
    }

    private var preferredScreen: NSScreen? {
        panel?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
    }

    @objc private func screenParametersDidChange() {
        positionPanel(restoringSavedOrigin: true)
    }
}

private final class DesktopLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum MenuBarLyricsLayout {
    static let minimumLyricsWidth: CGFloat = 100
    static let maximumLyricsWidth: CGFloat = 200
    static let maximumDisplayedWidthWithControls: CGFloat = 220
    static let playbackControlsWidth: CGFloat = 73
    static let horizontalPadding: CGFloat = 8

    static func lyricsWidth(_ value: Double) -> CGFloat {
        min(max(CGFloat(value), minimumLyricsWidth), maximumLyricsWidth)
    }

    static func maximumDisplayedWidth(
        showsPlaybackControls: Bool
    ) -> CGFloat {
        showsPlaybackControls
            ? maximumDisplayedWidthWithControls
            : maximumLyricsWidth
    }

    static func effectiveLyricsWidth(
        _ value: Double,
        showsPlaybackControls: Bool
    ) -> CGFloat {
        let controlsWidth = showsPlaybackControls ? playbackControlsWidth : 0
        return min(
            lyricsWidth(value),
            maximumDisplayedWidth(showsPlaybackControls: showsPlaybackControls)
                - controlsWidth
        )
    }

    static func totalWidth(lyricsWidth: Double, showsPlaybackControls: Bool) -> CGFloat {
        displayedWidth(
            lyricsWidth: lyricsWidth,
            showsPlaybackControls: showsPlaybackControls
        ) + horizontalPadding
    }

    /// Width presented to the user. Playback controls are part of the visible
    /// menu-bar content, while the outer safety padding remains an implementation detail.
    static func displayedWidth(
        lyricsWidth: Double,
        showsPlaybackControls: Bool
    ) -> CGFloat {
        effectiveLyricsWidth(
            lyricsWidth,
            showsPlaybackControls: showsPlaybackControls
        )
            + (showsPlaybackControls ? playbackControlsWidth : 0)
    }

    static func displayedWidthRange(
        showsPlaybackControls: Bool
    ) -> ClosedRange<Double> {
        let minimum = displayedWidth(
            lyricsWidth: Double(minimumLyricsWidth),
            showsPlaybackControls: showsPlaybackControls
        )
        let maximum = maximumDisplayedWidth(
            showsPlaybackControls: showsPlaybackControls
        )
        return Double(minimum)...Double(maximum)
    }

    static func preferredLyricsWidth(
        fromDisplayedWidth displayedWidth: Double,
        showsPlaybackControls: Bool
    ) -> Double {
        let controlsWidth = showsPlaybackControls ? playbackControlsWidth : 0
        return Double(lyricsWidth(displayedWidth - Double(controlsWidth)))
    }
}

@MainActor
private final class MenuBarLyricsController: NSObject {
    private let playbackProvider: PlaybackProvider
    private let lyricsProvider: LyricsProvider
    private let settings: IslandSettings
    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<MenuBarLyricsView>?
    private var playbackControlsMouseMonitor: Any?

    init(
        playbackProvider: PlaybackProvider,
        lyricsProvider: LyricsProvider,
        settings: IslandSettings
    ) {
        self.playbackProvider = playbackProvider
        self.lyricsProvider = lyricsProvider
        self.settings = settings
        super.init()
    }

    func show() {
        if statusItem == nil {
            createStatusItem()
        } else if let statusItem {
            statusItem.isVisible = true
            if hostingView == nil, let button = statusItem.button {
                attachHostingView(to: button)
            }
        }
        updateLayout()
    }

    func hide() {
        removePlaybackControlsMouseMonitor()
        hostingView?.removeFromSuperview()
        hostingView = nil
        statusItem?.isVisible = false
    }

    func close() {
        hide()
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func updateLayout() {
        guard let statusItem else { return }
        statusItem.length = MenuBarLyricsLayout.totalWidth(
            lyricsWidth: settings.menuBarLyricsWidth,
            showsPlaybackControls: settings.menuBarLyricsShowsPlaybackControls
        )
        if let button = statusItem.button {
            hostingView?.frame = button.bounds
            updatePlaybackControlsMouseMonitor(for: button)
        }
    }

    private func createStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(
            withLength: MenuBarLyricsLayout.totalWidth(
                lyricsWidth: settings.menuBarLyricsWidth,
                showsPlaybackControls: settings.menuBarLyricsShowsPlaybackControls
            )
        )
        guard let button = statusItem.button else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return
        }

        button.title = ""
        button.image = nil
        button.toolTip = "NookFlow 菜单栏歌词"
        if let buttonCell = button.cell as? NSButtonCell {
            buttonCell.highlightsBy = []
            buttonCell.showsStateBy = []
        }
        statusItem.isVisible = true
        self.statusItem = statusItem
        attachHostingView(to: button)
    }

    private func attachHostingView(to button: NSStatusBarButton) {
        let hostingView = TransparentHostingView(
            rootView: MenuBarLyricsView(
                playbackProvider: playbackProvider,
                lyricsProvider: lyricsProvider,
                settings: settings
            )
        )
        hostingView.frame = button.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        button.addSubview(hostingView)
        self.hostingView = hostingView
        updatePlaybackControlsMouseMonitor(for: button)
    }

    private func updatePlaybackControlsMouseMonitor(for button: NSStatusBarButton) {
        guard settings.menuBarLyricsShowsPlaybackControls else {
            removePlaybackControlsMouseMonitor()
            return
        }
        guard playbackControlsMouseMonitor == nil else { return }

        playbackControlsMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self, weak button] event in
            guard let self, let button else { return event }
            return self.handlePlaybackControlsMouseEvent(
                event,
                at: NSEvent.mouseLocation,
                in: button
            )
                ? nil
                : event
        }
    }

    private func removePlaybackControlsMouseMonitor() {
        guard let playbackControlsMouseMonitor else { return }
        NSEvent.removeMonitor(playbackControlsMouseMonitor)
        self.playbackControlsMouseMonitor = nil
    }

    private func handlePlaybackControlsMouseEvent(
        _ event: NSEvent,
        at screenLocation: NSPoint,
        in button: NSStatusBarButton
    ) -> Bool {
        guard statusItem?.isVisible == true,
              settings.menuBarLyricsShowsPlaybackControls,
              let window = button.window
        else {
            return false
        }

        let buttonRect = window.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let controlsRect = NSRect(
            x: buttonRect.maxX
                - MenuBarLyricsLayout.horizontalPadding / 2
                - MenuBarLyricsLayout.playbackControlsWidth,
            y: buttonRect.minY,
            width: MenuBarLyricsLayout.playbackControlsWidth,
            height: buttonRect.height
        )
        guard controlsRect.contains(screenLocation) else { return false }
        guard event.type == .leftMouseDown else { return true }

        let localX = screenLocation.x - controlsRect.minX
        let index = min(
            2,
            max(0, Int(localX / (controlsRect.width / 3)))
        )
        switch index {
        case 0:
            playbackProvider.previousTrack()
        case 1:
            playbackProvider.togglePlayback()
        default:
            playbackProvider.nextTrack()
        }
        return true
    }
}

private struct MenuBarLyricsView: View {
    @ObservedObject var playbackProvider: PlaybackProvider
    @ObservedObject var lyricsProvider: LyricsProvider
    @ObservedObject var settings: IslandSettings

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playbackAnchor = PlaybackTimeAnchor.anchored(
        to: 0,
        isPlaying: false
    )

    var body: some View {
        HStack(spacing: 6) {
            timedLyricLabel

            if settings.menuBarLyricsShowsPlaybackControls {
                Rectangle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 1, height: 12)

                playbackControlIcon(
                    systemName: "backward.end.fill",
                    help: "上一首",
                    action: playbackProvider.previousTrack
                )
                playbackControlIcon(
                    systemName: playbackProvider.snapshot.state == .playing
                        ? "pause.fill"
                        : "play.fill",
                    help: playbackProvider.snapshot.state == .playing ? "暂停" : "播放",
                    action: playbackProvider.togglePlayback
                )
                playbackControlIcon(
                    systemName: "forward.end.fill",
                    help: "下一首",
                    action: playbackProvider.nextTrack
                )
            }
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .onAppear(perform: resetPlaybackAnchor)
        .onChange(of: playbackProvider.snapshot.elapsed) { _, _ in
            resetPlaybackAnchor()
        }
        .onChange(of: playbackProvider.snapshot.state) { _, _ in
            resetPlaybackAnchor()
        }
    }

    @ViewBuilder
    private var timedLyricLabel: some View {
        let presentation = lyricPresentation
        ZStack(alignment: .leading) {
            TimelineView(
                .animation(paused: !needsContinuousTimeline(for: presentation))
            ) { _ in
                lyricLabel(presentation, playbackTime: effectivePlaybackTime)
            }
            .id(presentation.identity)
            .transition(.opacity)
        }
        .animation(lineTransitionAnimation, value: presentation.identity)
    }

    private func lyricLabel(
        _ presentation: MenuBarLyricPresentation,
        playbackTime: TimeInterval
    ) -> some View {
        let width = MenuBarLyricsLayout.effectiveLyricsWidth(
            settings.menuBarLyricsWidth,
            showsPlaybackControls: settings.menuBarLyricsShowsPlaybackControls
        )
        let textLayout = presentation.timing.map {
            LyricTextMeasurer.layout(
                for: $0,
                fontSize: 13,
                weight: .medium,
                design: .standard
            )
        }
        let textWidth = textLayout?.totalWidth ?? measuredWidth(of: presentation.text)
        let overflow = max(0, textWidth - width)
        let revealedWidth = presentation.timing.flatMap { timing in
            textLayout?.revealedWidth(at: playbackTime, for: timing)
        } ?? 0
        let playbackProgress = textWidth > 0
            ? min(max(Double(revealedWidth / textWidth), 0), 1)
            : 0
        let textOffset = overflow > 0
            ? -overflow * scrollingProgress(from: playbackProgress)
            : (width - textWidth) / 2

        return ZStack(alignment: .leading) {
            menuBarLyricText(presentation.text, color: .primary)
            menuBarLyricText(presentation.text, color: sungLyricColor)
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: revealedWidth)
                        Spacer(minLength: 0)
                    }
                }
        }
        .frame(width: textWidth, alignment: .leading)
        .offset(x: textOffset)
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask {
            if overflow > 0 {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black, location: 0.05),
                        .init(color: .black, location: 0.93),
                        .init(color: .black.opacity(0.20), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Rectangle()
            }
        }
    }

    private func menuBarLyricText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var lyricPresentation: MenuBarLyricPresentation {
        let sourceIndex = lyricsProvider.desktopPresentationLineIndex
            ?? lyricsProvider.currentLineIndex
        if let sourceIndex, lyricsProvider.lyrics.indices.contains(sourceIndex) {
            let line = lyricsProvider.lyrics[sourceIndex]
            let timing = lyricsProvider.estimatedLine(at: sourceIndex)
            let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = line.translation?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !words.isEmpty {
                return MenuBarLyricPresentation(
                    identity: line.id.uuidString,
                    text: words,
                    timing: timing
                )
            }
            if !translation.isEmpty {
                return MenuBarLyricPresentation(
                    identity: line.id.uuidString,
                    text: translation,
                    timing: timing
                )
            }
        }

        if lyricsProvider.displayState.isLoading {
            return MenuBarLyricPresentation(
                identity: "status.loading",
                text: "正在加载歌词…"
            )
        }
        return MenuBarLyricPresentation(
            identity: "status.unavailable",
            text: "暂无歌词"
        )
    }

    private func needsContinuousTimeline(for presentation: MenuBarLyricPresentation) -> Bool {
        return TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: true,
                isPlaying: playbackProvider.snapshot.state == .playing,
                hasContent: presentation.timing != nil,
                needsScrolling: false,
                needsProgressAnimation: presentation.timing.map {
                    effectivePlaybackTime < $0.vocalEndTime
                } ?? false,
                isTransitioning: false
            )
        )
    }

    private var effectivePlaybackTime: TimeInterval {
        playbackAnchor.estimatedTime() + LyricPlaybackTiming.revealOffset
    }

    private var lineTransitionAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.08)
            : .easeOut(duration: 0.16)
    }

    private func measuredWidth(of text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return max(1, ceil((text as NSString).size(withAttributes: [.font: font]).width))
    }

    private func scrollingProgress(from playbackProgress: Double) -> CGFloat {
        let delayedProgress = (playbackProgress - 0.08) / 0.84
        return CGFloat(min(max(delayedProgress, 0), 1))
    }

    private var sungLyricColor: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.88, blue: 0.48)
            : Color(red: 0.05, green: 0.56, blue: 0.24)
    }

    private func resetPlaybackAnchor() {
        playbackAnchor = PlaybackTimeAnchor.anchored(
            to: playbackProvider.snapshot.elapsed,
            isPlaying: playbackProvider.snapshot.state == .playing
        )
    }

    private func playbackControlIcon(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
                .foregroundStyle(.primary.opacity(0.82))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
    }
}

private struct MenuBarLyricPresentation {
    let identity: String
    let text: String
    let timing: EstimatedLyricLine?

    init(
        identity: String,
        text: String,
        timing: EstimatedLyricLine? = nil
    ) {
        self.identity = identity
        self.text = text
        self.timing = timing
    }
}

@MainActor
private final class DesktopLyricsAppearanceController: ObservableObject {
    @Published private(set) var usesDarkText = false

    private var mode: DesktopLyricsColorMode = .automatic

    func setMode(_ mode: DesktopLyricsColorMode) {
        self.mode = mode
        switch mode {
        case .automatic:
            setDarkText(false)
        case .lightText:
            setDarkText(false)
        case .darkText:
            setDarkText(true)
        }
    }

    private func setDarkText(_ useDarkText: Bool) {
        guard usesDarkText != useDarkText else { return }
        withAnimation(.easeInOut(duration: 0.20)) {
            usesDarkText = useDarkText
        }
    }
}

private struct DesktopLyricEntry: Identifiable, Equatable {
    let id: UUID
    let sourceIndex: Int
    let text: String
    let timing: EstimatedLyricLine
}

@MainActor
private final class LyricsTimelineController: ObservableObject {
    @Published private(set) var lyrics: [DesktopLyricEntry] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var displayState: LyricsDisplayState = .idle
    @Published private(set) var contentWidth: CGFloat = 180
    @Published private(set) var playbackAnchor = PlaybackTimeAnchor.anchored(
        to: 0,
        isPlaying: false
    )
    @Published private(set) var playbackIsPlaying = false
    @Published private(set) var windowIsVisible = false
    @Published private(set) var isPointerHovering = false
    @Published var windowPosition: CGPoint = .zero
    @Published var isInteractionEnabled = false

    private let playbackProvider: PlaybackProvider
    private let lyricsProvider: LyricsProvider
    let visibleLineCount = 5
    let anchorRatio: CGFloat = 0.5
    let fixedLineHeight: CGFloat = 36
    let rowSpacing: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    private var trackIdentity = ""

    init(
        playbackProvider: PlaybackProvider,
        lyricsProvider: LyricsProvider
    ) {
        self.playbackProvider = playbackProvider
        self.lyricsProvider = lyricsProvider
    }

    func start() {
        guard cancellables.isEmpty else { return }

        playbackProvider.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handlePlayback(snapshot)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            lyricsProvider.$lyrics.removeDuplicates(),
            lyricsProvider.$estimatedTimeline.removeDuplicates()
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pair in
                self?.rebuildLyrics(from: pair.0)
            }
            .store(in: &cancellables)

        lyricsProvider.$desktopPresentationLineIndex
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceIndex in
                self?.updateCurrentIndex(sourceIndex: sourceIndex)
            }
            .store(in: &cancellables)

        lyricsProvider.$displayState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: &$displayState)
    }

    func stop() {
        cancellables.removeAll()
        windowIsVisible = false
    }

    func setWindowVisibility(_ isVisible: Bool) {
        guard windowIsVisible != isVisible else { return }
        windowIsVisible = isVisible
    }

    func setPointerHovering(_ isHovering: Bool) {
        guard isPointerHovering != isHovering else { return }
        isPointerHovering = isHovering
    }

    func documentCenterY(for index: Int) -> CGFloat {
        guard lyrics.indices.contains(index) else { return 0 }
        return fixedLineHeight / 2 + CGFloat(index) * (fixedLineHeight + rowSpacing)
    }

    var documentHeight: CGFloat {
        guard !lyrics.isEmpty else { return 0 }
        return CGFloat(lyrics.count) * fixedLineHeight
            + CGFloat(max(0, lyrics.count - 1)) * rowSpacing
    }

    private func handlePlayback(_ snapshot: PlaybackSnapshot) {
        playbackAnchor = PlaybackTimeAnchor.anchored(
            to: snapshot.elapsed,
            isPlaying: snapshot.state == .playing
        )
        playbackIsPlaying = snapshot.state == .playing

        let identity = snapshot.isLive
            ? [snapshot.appName, snapshot.title, snapshot.artist, snapshot.album].joined(separator: "|")
            : ""

        guard identity != trackIdentity else { return }
        trackIdentity = identity
        currentIndex = nil
        updateContentWidth()
    }

    private func rebuildLyrics(from lines: [LyricLine]) {
        lyrics = lines.enumerated().compactMap { index, line in
            let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = words.isEmpty ? translation : words
            guard !text.isEmpty,
                  let timing = lyricsProvider.estimatedLine(at: index) else {
                return nil
            }
            return DesktopLyricEntry(
                id: line.id,
                sourceIndex: index,
                text: text,
                timing: timing
            )
        }

        let mappedIndex = mappedEntryIndex(for: lyricsProvider.desktopPresentationLineIndex)
            ?? mappedEntryIndex(for: lyricsProvider.currentLineIndex)
        currentIndex = mappedIndex
        updateContentWidth()
    }

    private func updateCurrentIndex(sourceIndex: Int?) {
        let nextIndex = mappedEntryIndex(for: sourceIndex)
        guard nextIndex != currentIndex else { return }
        currentIndex = nextIndex
        updateContentWidth()
    }

    private func mappedEntryIndex(for sourceIndex: Int?) -> Int? {
        guard let sourceIndex else { return nil }
        return lyrics.firstIndex(where: { $0.sourceIndex == sourceIndex })
            ?? lyrics.firstIndex(where: { $0.sourceIndex > sourceIndex })
            ?? lyrics.indices.last
    }

    private func updateContentWidth() {
        guard let currentIndex, !lyrics.isEmpty else {
            contentWidth = 180
            return
        }

        let lowerBound = max(0, currentIndex - 2)
        let upperBound = min(lyrics.count, currentIndex + 3)
        let baseFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded)
        let font = roundedDescriptor.flatMap {
            NSFont(descriptor: $0, size: baseFont.pointSize)
        } ?? baseFont
        let maximumTextWidth = lyrics[lowerBound..<upperBound].reduce(CGFloat.zero) { result, entry in
            let width = (entry.text as NSString).size(withAttributes: [.font: font]).width
            return max(result, ceil(width))
        }

        // Reserve the row inset and the text contrast shadow without adding a visible surface.
        contentWidth = max(96, maximumTextWidth + 40)
    }
}

private struct LyricsVisualStyle {
    let opacity: Double
    let blurRadius: CGFloat
    let scale: CGFloat
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let shadowStrength: Double
    let isCurrent: Bool

    init(distance: Int) {
        switch distance {
        case 0:
            opacity = 1
            blurRadius = 0
            scale = 1
            fontSize = 17
            fontWeight = .semibold
            shadowStrength = 1
            isCurrent = true
        case 1:
            opacity = 0.68
            blurRadius = 0.45
            scale = 0.97
            fontSize = 14.5
            fontWeight = .medium
            shadowStrength = 0.76
            isCurrent = false
        case 2:
            opacity = 0.40
            blurRadius = 1.25
            scale = 0.97
            fontSize = 14.5
            fontWeight = .medium
            shadowStrength = 0.58
            isCurrent = false
        default:
            opacity = 0
            blurRadius = 1.25
            scale = 0.97
            fontSize = 14.5
            fontWeight = .medium
            shadowStrength = 0
            isCurrent = false
        }
    }
}

private struct DesktopLyricsView: View {
    @ObservedObject var timeline: LyricsTimelineController
    @ObservedObject var appearance: DesktopLyricsAppearanceController
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        Group {
            if timeline.displayState.isLoading {
                lyricsPlaceholder("正在加载歌词...", showsSurface: false)
            } else if timeline.lyrics.isEmpty {
                lyricsPlaceholder(timeline.displayState.placeholderText ?? "暂无歌词")
            } else {
                LyricsStackView(timeline: timeline, appearance: appearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(timeline.isPointerHovering ? 0 : 1)
        .animation(.easeOut(duration: 0.12), value: timeline.isPointerHovering)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    guard timeline.isInteractionEnabled else { return }
                    onDragChanged(value.translation)
                }
                .onEnded { _ in
                    guard timeline.isInteractionEnabled else { return }
                    onDragEnded()
                }
        )
    }

    private func lyricsPlaceholder(
        _ text: String,
        showsSurface: Bool = true
    ) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(palette.foreground.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if showsSurface {
                    DesktopLyricsFocusSurface(palette: palette)
                }
            }
            .shadow(
                color: showsSurface
                    ? Color.black.opacity(0.20)
                    : palette.contrastHalo.opacity(0.70),
                radius: showsSurface ? 5 : 1.8,
                x: 0,
                y: showsSurface ? 2 : 1
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeInOut(duration: 0.20), value: appearance.usesDarkText)
    }

    private var palette: DesktopLyricsPalette {
        DesktopLyricsPalette(usesDarkText: appearance.usesDarkText)
    }
}

private struct LyricsStackView: View {
    @ObservedObject var timeline: LyricsTimelineController
    @ObservedObject var appearance: DesktopLyricsAppearanceController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var listOffset: CGFloat = 0

    private let horizontalPadding: CGFloat = 12
    private let scrollAnimation = Animation.spring(
        response: 0.44,
        dampingFraction: 0.92,
        blendDuration: 0.10
    )

    var body: some View {
        GeometryReader { proxy in
            let anchorY = proxy.size.height * timeline.anchorRatio
            let topPadding = topPadding(containerHeight: proxy.size.height, anchorY: anchorY)
            let bottomPadding = bottomPadding(containerHeight: proxy.size.height, anchorY: anchorY)

            VStack(alignment: .leading, spacing: timeline.rowSpacing) {
                Color.clear
                    .frame(height: topPadding)

                ForEach(Array(timeline.lyrics.enumerated()), id: \.element.id) { index, entry in
                    let relativeIndex = timeline.currentIndex.map { index - $0 } ?? 3
                    let distance = abs(relativeIndex)

                    LyricLineView(
                        entry: entry,
                        style: LyricsVisualStyle(distance: distance),
                        palette: DesktopLyricsPalette(usesDarkText: appearance.usesDarkText),
                        playbackAnchor: timeline.playbackAnchor,
                        isPlaying: timeline.playbackIsPlaying,
                        isVisible: timeline.windowIsVisible
                    )
                    .frame(
                        width: max(0, proxy.size.width - horizontalPadding * 2),
                        height: timeline.fixedLineHeight,
                        alignment: .leading
                    )
                    .clipped()
                    .animation(lineStyleAnimation, value: timeline.currentIndex)
                }

                Color.clear
                    .frame(height: bottomPadding)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(
                width: proxy.size.width,
                height: max(proxy.size.height, timeline.documentHeight + topPadding + bottomPadding),
                alignment: .topLeading
            )
            .offset(y: listOffset)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .animation(.easeInOut(duration: 0.20), value: appearance.usesDarkText)
            .mask(lyricsFadeMask)
            .onAppear {
                resetPosition(anchorY: anchorY, topPadding: topPadding)
            }
            .onChange(of: timeline.currentIndex) { oldIndex, newIndex in
                transition(from: oldIndex, to: newIndex, anchorY: anchorY, topPadding: topPadding)
            }
            .onChange(of: timeline.lyrics) { _, _ in
                resetPosition(anchorY: anchorY, topPadding: topPadding)
            }
            .onChange(of: proxy.size) { _, _ in
                resetPosition(anchorY: anchorY, topPadding: topPadding)
            }
        }
        .clipped()
    }

    private var lineStyleAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : scrollAnimation
    }

    private var lyricsFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: 0.14),
                .init(color: .white, location: 0.84),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func topPadding(containerHeight: CGFloat, anchorY: CGFloat) -> CGFloat {
        max(0, anchorY - timeline.fixedLineHeight / 2)
    }

    private func bottomPadding(containerHeight: CGFloat, anchorY: CGFloat) -> CGFloat {
        max(0, containerHeight - anchorY - timeline.fixedLineHeight / 2)
    }

    private func targetOffset(for index: Int?, anchorY: CGFloat, topPadding: CGFloat) -> CGFloat {
        guard let index else { return 0 }
        return anchorY - (topPadding + timeline.documentCenterY(for: index))
    }

    private func resetPosition(anchorY: CGFloat, topPadding: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listOffset = targetOffset(
                for: timeline.currentIndex,
                anchorY: anchorY,
                topPadding: topPadding
            )
        }
    }

    private func transition(from oldIndex: Int?, to newIndex: Int?, anchorY: CGFloat, topPadding: CGFloat) {
        guard let newIndex else {
            resetPosition(anchorY: anchorY, topPadding: topPadding)
            return
        }

        guard let oldIndex else {
            resetPosition(anchorY: anchorY, topPadding: topPadding)
            return
        }

        let target = targetOffset(for: newIndex, anchorY: anchorY, topPadding: topPadding)
        let distance = abs(newIndex - oldIndex)

        if !reduceMotion, distance <= timeline.visibleLineCount {
            withAnimation(scrollAnimation) {
                listOffset = target
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listOffset = target
        }
    }
}

private struct LyricLineView: View {
    let entry: DesktopLyricEntry
    let style: LyricsVisualStyle
    let palette: DesktopLyricsPalette
    let playbackAnchor: PlaybackTimeAnchor
    let isPlaying: Bool
    let isVisible: Bool

    var body: some View {
        TimelineView(.animation(paused: !needsContinuousTimeline)) { _ in
            lyricText(
                playbackTime: style.isCurrent
                    ? effectivePlaybackTime
                    : entry.timing.lineStartTime
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .opacity(style.opacity)
        .blur(radius: style.blurRadius)
        .scaleEffect(style.scale, anchor: .leading)
    }

    private var needsContinuousTimeline: Bool {
        TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: isVisible,
                isPlaying: isPlaying,
                hasContent: !entry.text.isEmpty,
                needsScrolling: false,
                needsProgressAnimation: style.isCurrent
                    && effectivePlaybackTime < entry.timing.vocalEndTime,
                isTransitioning: false
            )
        )
    }

    private func lyricText(playbackTime: TimeInterval) -> some View {
        let layout = desktopTextLayout
        let revealedWidth = style.isCurrent
            ? layout.revealedWidth(at: playbackTime, for: entry.timing)
            : 0

        return ZStack(alignment: .leading) {
            lyricTextLayer(color: palette.foreground)
            lyricTextLayer(color: palette.progressForeground)
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: revealedWidth)
                        Spacer(minLength: 0)
                    }
                }
                .opacity(style.isCurrent ? 1 : 0)
        }
    }

    private func lyricTextLayer(color: Color) -> some View {
        let tightShadowStrength = style.isCurrent
            ? style.shadowStrength * 0.42
            : style.shadowStrength
        let diffuseShadowStrength = style.isCurrent
            ? style.shadowStrength * 0.16
            : style.shadowStrength * 0.42

        return Text(entry.text)
            .font(.system(size: style.fontSize, weight: style.fontWeight, design: .rounded))
            .foregroundStyle(color)
            .tracking(style.isCurrent ? -0.15 : 0)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .shadow(
                color: palette.contrastHalo.opacity(
                    palette.shadowOpacity * tightShadowStrength
                ),
                radius: style.isCurrent ? 0.7 : 1.05,
                x: 0,
                y: 0
            )
            .shadow(
                color: palette.contrastHalo.opacity(
                    palette.shadowOpacity * diffuseShadowStrength
                ),
                radius: style.isCurrent ? 1.8 : palette.shadowRadius,
                x: 0,
                y: 1
            )
    }

    private var desktopTextLayout: LyricTextLayout {
        LyricTextMeasurer.layout(
            for: entry.timing,
            fontSize: style.fontSize,
            weight: .semibold,
            design: .rounded
        )
    }

    private var effectivePlaybackTime: TimeInterval {
        playbackAnchor.estimatedTime() + LyricPlaybackTiming.revealOffset
    }
}

private struct DesktopLyricsFocusSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let palette: DesktopLyricsPalette

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(solidAccessibilityColor)
            } else if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(glassTint), in: shape)
            } else {
                legacyBackdropMaterial
            }
        }
        .overlay {
            shape.stroke(glassEdge, lineWidth: 0.8)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
    }

    private var glassTint: Color {
        palette.usesDarkText
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.22)
    }

    private var solidAccessibilityColor: Color {
        palette.usesDarkText
            ? Color(white: 0.92)
            : Color(white: 0.16)
    }

    private var glassEdge: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.68), location: 0),
                .init(color: Color.white.opacity(0.22), location: 0.46),
                .init(color: Color.black.opacity(0.18), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var legacyBackdropMaterial: some View {
        ZStack {
            DesktopLyricsBackdropMaterial(
                material: palette.usesDarkText ? .popover : .hudWindow,
                cornerRadius: 11
            )
            shape.fill(glassTint)
        }
        .clipShape(shape)
    }
}

private struct DesktopLyricsBackdropMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

private struct DesktopLyricsPalette {
    let usesDarkText: Bool
    let foreground: Color
    let progressForeground: Color
    let readabilityBackground: Color
    let readabilityStroke: Color
    let contrastHalo: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat

    init(usesDarkText: Bool) {
        self.usesDarkText = usesDarkText
        if usesDarkText {
            foreground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
            progressForeground = Color(red: 0.05, green: 0.48, blue: 0.18)
            readabilityBackground = Color.white
            readabilityStroke = Color.black
            contrastHalo = .white
            shadowOpacity = 0.84
            shadowRadius = 2.6
        } else {
            foreground = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
            progressForeground = Color(
                red: 48 / 255,
                green: 209 / 255,
                blue: 88 / 255
            )
            readabilityBackground = Color.black
            readabilityStroke = Color.white
            contrastHalo = .black
            shadowOpacity = 0.92
            shadowRadius = 3
        }
    }
}
