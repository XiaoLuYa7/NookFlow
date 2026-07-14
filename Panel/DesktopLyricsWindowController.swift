import AppKit
import Combine
import CoreGraphics
import SwiftUI

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

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
    private var panel: DesktopLyricsPanel?
    private var cancellables = Set<AnyCancellable>()
    private var dragStartOrigin: NSPoint?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

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
        startMouseTracking()
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
        stopMouseTracking()
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

        if snapshot.isLive, settings.showDesktopLyrics {
            panel.orderFrontRegardless()
            timelineController.setWindowVisibility(panel.isVisible && panel.alphaValue > 0)
        } else {
            dragStartOrigin = nil
            timelineController.isHoverHidden = false
            panel.orderOut(nil)
            timelineController.setWindowVisibility(false)
        }
    }

    private func applyInteractionState(_ isEnabled: Bool) {
        timelineController.isInteractionEnabled = isEnabled
        if !isEnabled {
            dragStartOrigin = nil
        }
        updatePointerHoverState()
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

    private func startMouseTracking() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.updatePointerHoverState()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePointerHoverState()
            }
        }
    }

    private func stopMouseTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updatePointerHoverState() {
        guard let panel, panel.isVisible else {
            timelineController.isHoverHidden = false
            return
        }

        // Edit mode keeps the lyrics interactive so the panel remains draggable.
        let shouldHide = !settings.desktopLyricsInteractionEnabled
            && panel.frame.contains(NSEvent.mouseLocation)
        if timelineController.isHoverHidden != shouldHide {
            timelineController.isHoverHidden = shouldHide
        }
        panel.ignoresMouseEvents = shouldHide || !settings.desktopLyricsInteractionEnabled
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
    let startTimeMS: TimeInterval
    let nextStartTimeMS: TimeInterval?
}

@MainActor
private final class LyricsTimelineController: ObservableObject {
    @Published private(set) var lyrics: [DesktopLyricEntry] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isLoading = false
    @Published private(set) var statusText = ""
    @Published private(set) var contentWidth: CGFloat = 180
    @Published private(set) var playbackAnchorDate = Date()
    @Published private(set) var playbackAnchorElapsed: TimeInterval = 0
    @Published private(set) var playbackIsPlaying = false
    @Published private(set) var windowIsVisible = false
    @Published var windowPosition: CGPoint = .zero
    @Published var isInteractionEnabled = false
    @Published var isHoverHidden = false

    private let playbackProvider: PlaybackProvider
    private let lyricsProvider: LyricsProvider
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

        lyricsProvider.$lyrics
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines in
                self?.rebuildLyrics(from: lines)
            }
            .store(in: &cancellables)

        lyricsProvider.$desktopPresentationLineIndex
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sourceIndex in
                self?.updateCurrentIndex(sourceIndex: sourceIndex)
            }
            .store(in: &cancellables)

        lyricsProvider.$isLoading
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        lyricsProvider.$statusText
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: &$statusText)
    }

    func stop() {
        cancellables.removeAll()
        windowIsVisible = false
    }

    func setWindowVisibility(_ isVisible: Bool) {
        guard windowIsVisible != isVisible else { return }
        windowIsVisible = isVisible
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
        playbackAnchorDate = Date()
        playbackAnchorElapsed = snapshot.elapsed
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
            guard !text.isEmpty else { return nil }
            let nextStart = lines.indices.contains(index + 1) ? lines[index + 1].startTimeMS : nil
            return DesktopLyricEntry(
                id: line.id,
                sourceIndex: index,
                text: text,
                startTimeMS: line.startTimeMS,
                nextStartTimeMS: nextStart
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
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let maximumTextWidth = lyrics[lowerBound..<upperBound].reduce(CGFloat.zero) { result, entry in
            let width = (entry.text as NSString).size(withAttributes: [.font: font]).width
            return max(result, ceil(width))
        }

        // 12pt text background padding and 24pt transparent outer breathing room.
        contentWidth = max(80, maximumTextWidth + 36)
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
    let isPlayed: Bool
    let backgroundOpacity: Double
    let strokeOpacity: Double

    init(distance: Int, isPlayed: Bool) {
        self.isPlayed = isPlayed

        switch distance {
        case 0:
            opacity = 1
            blurRadius = 0
            scale = 1
            fontSize = 15
            fontWeight = .semibold
            shadowStrength = 0.9
            isCurrent = true
            backgroundOpacity = 0.82
            strokeOpacity = 0.38
        case 1:
            opacity = isPlayed ? 0.84 : 0.78
            blurRadius = 0.15
            scale = 0.97
            fontSize = 15
            fontWeight = .medium
            shadowStrength = isPlayed ? 0.58 : 0.48
            isCurrent = false
            backgroundOpacity = isPlayed ? 0.52 : 0.58
            strokeOpacity = isPlayed ? 0.20 : 0.24
        case 2:
            opacity = isPlayed ? 0.62 : 0.50
            blurRadius = 0.45
            scale = 0.95
            fontSize = 15
            fontWeight = .regular
            shadowStrength = isPlayed ? 0.40 : 0.30
            isCurrent = false
            backgroundOpacity = isPlayed ? 0.34 : 0.30
            strokeOpacity = 0.12
        default:
            opacity = isPlayed ? 0.40 : 0.28
            blurRadius = 0.85
            scale = 0.95
            fontSize = 15
            fontWeight = .regular
            shadowStrength = isPlayed ? 0.28 : 0.18
            isCurrent = false
            backgroundOpacity = isPlayed ? 0.20 : 0.16
            strokeOpacity = 0.08
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
            if timeline.isLoading {
                lyricsPlaceholder("正在加载歌词...")
            } else if timeline.lyrics.isEmpty {
                lyricsPlaceholder(timeline.statusText.isEmpty ? "暂无歌词" : timeline.statusText)
            } else {
                LyricsStackView(timeline: timeline, appearance: appearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(timeline.isHoverHidden ? 0 : 1)
        .animation(.easeOut(duration: 0.08), value: timeline.isHoverHidden)
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

    private func lyricsPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(palette.foreground.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.readabilityBackground.opacity(0.78))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(palette.readabilityStroke.opacity(0.42), lineWidth: 0.8)
                    }
            }
            .shadow(
                color: palette.shadowBase.opacity(palette.shadowOpacity),
                radius: palette.shadowRadius,
                x: 0,
                y: 1
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
    @State private var listOffset: CGFloat = 0
    @State private var contentOpacity = 1.0
    @State private var jumpTask: Task<Void, Never>?

    private let anchorRatio: CGFloat = 0.44
    private let horizontalPadding: CGFloat = 12
    private let scrollAnimation = Animation.spring(
        response: 0.52,
        dampingFraction: 0.9,
        blendDuration: 0.12
    )
    private let styleAnimation = Animation.easeInOut(duration: 0.28)

    var body: some View {
        GeometryReader { proxy in
            let anchorY = proxy.size.height * anchorRatio
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
                        style: LyricsVisualStyle(distance: distance, isPlayed: relativeIndex < 0),
                        palette: DesktopLyricsPalette(usesDarkText: appearance.usesDarkText),
                        playbackAnchorDate: timeline.playbackAnchorDate,
                        playbackAnchorElapsed: timeline.playbackAnchorElapsed,
                        isPlaying: timeline.playbackIsPlaying,
                        isVisible: timeline.windowIsVisible && !timeline.isHoverHidden
                    )
                    .frame(
                        width: max(0, proxy.size.width - horizontalPadding * 2),
                        height: timeline.fixedLineHeight,
                        alignment: .leading
                    )
                    .clipped()
                    .animation(styleAnimation, value: timeline.currentIndex)
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
            .opacity(contentOpacity)
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
        .onDisappear {
            jumpTask?.cancel()
            jumpTask = nil
        }
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
        jumpTask?.cancel()
        jumpTask = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            listOffset = targetOffset(
                for: timeline.currentIndex,
                anchorY: anchorY,
                topPadding: topPadding
            )
            contentOpacity = 1
        }
    }

    private func transition(from oldIndex: Int?, to newIndex: Int?, anchorY: CGFloat, topPadding: CGFloat) {
        jumpTask?.cancel()
        jumpTask = nil

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

        if distance <= 3 {
            if contentOpacity != 1 {
                withAnimation(.easeIn(duration: 0.12)) {
                    contentOpacity = 1
                }
            }
            withAnimation(scrollAnimation) {
                listOffset = target
            }
            return
        }

        jumpTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.09)) {
                contentOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                listOffset = target
            }

            withAnimation(.easeIn(duration: 0.14)) {
                contentOpacity = 1
            }
            jumpTask = nil
        }
    }
}

private struct LyricLineView: View {
    let entry: DesktopLyricEntry
    let style: LyricsVisualStyle
    let palette: DesktopLyricsPalette
    let playbackAnchorDate: Date
    let playbackAnchorElapsed: TimeInterval
    let isPlaying: Bool
    let isVisible: Bool

    var body: some View {
        let effectiveShadowOpacity = palette.shadowOpacity * style.shadowStrength

        Group {
            if needsContinuousTimeline {
                TimelineView(.animation) { timeline in
                    lyricText(progress: playbackProgress(at: timeline.date))
                }
            } else {
                lyricText(progress: style.isCurrent ? playbackProgress(at: Date()) : 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.readabilityBackground.opacity(style.backgroundOpacity))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.readabilityStroke.opacity(style.strokeOpacity), lineWidth: 0.7)
                }
        }
        .overlay {
            if style.isCurrent {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.progressForeground.opacity(0.24), lineWidth: 0.8)
            }
        }
        .opacity(style.opacity)
        .blur(radius: style.blurRadius)
        .scaleEffect(style.scale, anchor: .leading)
        .shadow(
            color: palette.shadowBase.opacity(effectiveShadowOpacity),
            radius: palette.shadowRadius,
            x: 0,
            y: 1
        )
    }

    private var needsContinuousTimeline: Bool {
        TimelineRefreshPolicy.shouldUseContinuousLyricTimeline(
            LyricTimelineState(
                isVisible: isVisible,
                isPlaying: isPlaying,
                hasContent: !entry.text.isEmpty,
                needsScrolling: style.isCurrent && playbackProgress(at: Date()) < 1,
                isTransitioning: false
            )
        )
    }

    private func lyricText(progress: Double) -> some View {
        let textWidth = desktopTextWidth
        let revealedWidth = max(0, textWidth * CGFloat(progress))

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
        Text(entry.text)
            .font(.system(size: style.fontSize, weight: style.fontWeight, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var desktopTextWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: style.fontSize, weight: .semibold)
        return ceil((entry.text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func playbackProgress(at date: Date) -> Double {
        let elapsed = isPlaying
            ? playbackAnchorElapsed + date.timeIntervalSince(playbackAnchorDate)
            : playbackAnchorElapsed
        let elapsedMS = elapsed * 1000 + lyricProgressLeadTimeMS
        let progress = (elapsedMS - entry.startTimeMS) / progressDurationMS
        return min(max(progress, 0), 1)
    }

    private var lyricProgressLeadTimeMS: TimeInterval {
        300
    }

    private var progressDurationMS: TimeInterval {
        let nextGap = max(1000, (entry.nextStartTimeMS ?? entry.startTimeMS + 4500) - entry.startTimeMS)
        let visibleCharacterCount = max(1, entry.text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.count)
        let estimatedSingingDuration = max(TimeInterval(visibleCharacterCount) * 260 + 900, 1900)
        let intervalAwareDuration = max(estimatedSingingDuration, nextGap * 0.55)
        return min(nextGap, min(intervalAwareDuration, 6500))
    }
}

private struct DesktopLyricsPalette {
    let foreground: Color
    let progressForeground: Color
    let readabilityBackground: Color
    let readabilityStroke: Color
    let shadowBase: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat

    init(usesDarkText: Bool) {
        if usesDarkText {
            foreground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
            progressForeground = Color(red: 0.05, green: 0.56, blue: 0.24)
            readabilityBackground = Color.white
            readabilityStroke = Color.black
            shadowBase = .black
            shadowOpacity = 0.18
            shadowRadius = 2
        } else {
            foreground = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
            progressForeground = Color(red: 0.20, green: 0.88, blue: 0.48)
            readabilityBackground = Color.black
            readabilityStroke = Color.white
            shadowBase = .black
            shadowOpacity = 0.50
            shadowRadius = 3
        }
    }
}
