import AppKit
import SwiftUI

struct QuickAppsCardView: View {

    @ObservedObject private var store = QuickAppsStore.shared
    @EnvironmentObject private var settings: IslandSettings
    @State private var unavailableAlertItem: QuickAppItem?
    @State private var currentPage = 0

    let wheelTarget: PageSwipeDetector.WheelTarget
    let acceptsPagingEvents: Bool

    private let columnSpacing: CGFloat = 14
    private let rowSpacing: CGFloat = 14
    private let maximumIconSize: CGFloat = 36
    private let pageHeight: CGFloat = 94
    private let pageGap: CGFloat = 4
    private let pageHorizontalInset: CGFloat = 8
    private var columnCount: Int { settings.quickAppsColumnCount.rawValue }
    private var pageSize: Int { settings.quickAppsColumnCount.pageSize }
    private var pageCount: Int {
        let visibleSlotCount = min(
            QuickAppsStore.maxCount,
            max(store.items.count + (store.items.count < QuickAppsStore.maxCount ? 1 : 0), pageSize)
        )
        return max(1, Int(ceil(Double(visibleSlotCount) / Double(pageSize))))
    }

    var body: some View {
        HStack(spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    VStack(spacing: pageGap) {
                        ForEach(0..<pageCount, id: \.self) { page in
                            pageView(page)
                                .frame(width: proxy.size.width, height: pageHeight)
                                .allowsHitTesting(page == currentPage)
                                .accessibilityHidden(page != currentPage)
                        }
                    }
                    .offset(y: -CGFloat(currentPage) * (pageHeight + pageGap))
                }
                .frame(width: proxy.size.width, height: pageHeight, alignment: .top)
                .compositingGroup()
                .mask {
                    Rectangle()
                        .frame(width: proxy.size.width, height: pageHeight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: pageHeight)
            .clipped()
            .animation(pageAnimation, value: currentPage)

            if pageCount > 1 {
                VStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        Button {
                            selectPage(page)
                        } label: {
                            Circle()
                                .fill(page == currentPage ? Color.white.opacity(0.82) : Color.white.opacity(0.24))
                                .frame(width: 4.5, height: 4.5)
                                .frame(width: 14, height: 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("第 \(page + 1) 页")
                        .accessibilityAddTraits(page == currentPage ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .overlay {
            if acceptsPagingEvents {
                PageSwipeDetector(axis: .vertical, wheelTarget: wheelTarget) { direction in
                    switch direction {
                    case .next: selectPage(currentPage + 1)
                    case .previous: selectPage(currentPage - 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: store.items.count) { _, _ in
            currentPage = min(currentPage, pageCount - 1)
        }
        .onChange(of: settings.quickAppsColumnCount) { _, _ in
            currentPage = min(currentPage, pageCount - 1)
        }
        .alert(
            "应用不可用",
            isPresented: Binding(
                get: { unavailableAlertItem != nil },
                set: { if !$0 { unavailableAlertItem = nil } }
            )
        ) {
            Button("确定", role: .cancel) { unavailableAlertItem = nil }
        } message: {
            if let item = unavailableAlertItem {
                Text("\"\(item.name)\" 已被移动或删除，请在设置中重新选择或移除。")
            }
        }
    }

    private func pageIndexes(for page: Int) -> [Int] {
        let start = page * pageSize
        return Array(start..<(start + pageSize))
    }

    private func pageView(_ page: Int) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - pageHorizontalInset * 2)
            let totalColumnSpacing = columnSpacing * CGFloat(max(0, columnCount - 1))
            let cellWidth = max(1, (contentWidth - totalColumnSpacing) / CGFloat(columnCount))
            let cellHeight = (pageHeight - rowSpacing) / 2
            let iconSize = min(maximumIconSize, cellWidth, cellHeight)
            let indexes = pageIndexes(for: page)
            let rows = stride(from: 0, to: indexes.count, by: columnCount).map { start in
                Array(indexes[start..<min(start + columnCount, indexes.count)])
            }

            VStack(spacing: rowSpacing) {
                ForEach(0..<rows.count, id: \.self) { row in
                    HStack(spacing: columnSpacing) {
                        ForEach(rows[row], id: \.self) { index in
                            slotView(for: index, iconSize: iconSize)
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
            .frame(width: contentWidth, height: pageHeight, alignment: .center)
            .padding(.horizontal, pageHorizontalInset)
        }
    }

    @ViewBuilder
    private func slotView(for index: Int, iconSize: CGFloat) -> some View {
        if index < store.items.count {
            appCell(item: store.items[index], iconSize: iconSize)
        } else if index == store.items.count && store.items.count < QuickAppsStore.maxCount {
            addButton(iconSize: iconSize)
        } else {
            Color.clear
        }
    }

    private func selectPage(_ page: Int) {
        guard (0..<pageCount).contains(page), currentPage != page else { return }
        TrackpadHapticFeedback.perform(settings.trackpadFeedbackMode)
        withAnimation(pageAnimation) {
            currentPage = page
        }
    }

    private var pageAnimation: Animation {
        .smooth(duration: QuickAppsPageTiming.pageTurnDuration, extraBounce: 0)
    }

    // MARK: - App Cell

    private func appCell(item: QuickAppItem, iconSize: CGFloat) -> some View {
        let available = store.isAppAvailable(item)

        return Button {
            if available {
                ApplicationLauncher.launch(item)
            } else {
                unavailableAlertItem = item
            }
        } label: {
            VStack(spacing: 0) {
                if available {
                    Image(nsImage: store.icon(for: item))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "questionmark.app.fill")
                        .font(.system(size: iconSize * 0.76))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .frame(width: iconSize, height: iconSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Button

    private func addButton(iconSize: CGFloat) -> some View {
        Button {
            openQuickAppsSettings()
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: iconSize * 0.76))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .frame(width: iconSize, height: iconSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .help("打开应用设置")
    }

    private func openQuickAppsSettings() {
        settings.quickAppsSettingsTrigger = false
        DispatchQueue.main.async {
            settings.quickAppsSettingsTrigger = true
        }
    }
}

private enum QuickAppsPageTiming {
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

enum PageSwipeDirection {
    case next
    case previous
}

struct PageSwipeDetector: NSViewRepresentable {
    var axis: Axis = .horizontal
    var supportsAuxiliaryButtons = true
    var threshold: CGFloat = 18
    var wheelTarget: WheelTarget?
    var onSwipe: (PageSwipeDirection) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.supportsAuxiliaryButtons = supportsAuxiliaryButtons
        view.axis = axis
        view.threshold = threshold
        view.onSwipe = onSwipe
        wheelTarget?.view = view
        view.wheelTarget = wheelTarget
        return view
    }

    func updateNSView(_ nsView: SwipeView, context: Context) {
        nsView.onSwipe = onSwipe
        nsView.supportsAuxiliaryButtons = supportsAuxiliaryButtons
        nsView.axis = axis
        nsView.threshold = threshold
    }

    static func dismantleNSView(_ view: SwipeView, coordinator: ()) {
        if view.wheelTarget?.view === view { view.wheelTarget?.view = nil }
        view.stopMonitoring()
    }

    @MainActor
    final class WheelTarget {
        fileprivate weak var view: SwipeView?

        func contains(_ event: NSEvent) -> Bool {
            view?.isEventInsideCard(event) == true
        }
    }

    final class SwipeView: NSView {
        var onSwipe: ((PageSwipeDirection) -> Void)?
        var supportsAuxiliaryButtons = true
        var axis: Axis = .horizontal
        var threshold: CGFloat = 18
        weak var wheelTarget: WheelTarget?
        private var lastWheelPageTime: TimeInterval = -.infinity
        private var lastWheelDirection: PageSwipeDirection?
        private var scrollAxis: Axis?
        private var accumulatedDelta: CGFloat = 0
        private var hasTriggeredSwipe = false
        private var localMonitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        deinit {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window == nil {
                stopMonitoring()
            } else if localMonitor == nil {
                let eventTypes: NSEvent.EventTypeMask = supportsAuxiliaryButtons
                    ? [.scrollWheel, .otherMouseDown]
                    : .scrollWheel
                localMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: eventTypes
                ) { [weak self] event in
                    guard let self else { return event }
                    return self.handleLocalEvent(event)
                }
            }
        }

        fileprivate func stopMonitoring() {
            guard let localMonitor else { return }
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .scrollWheel:
                return handleScroll(event)
            case .otherMouseDown:
                guard supportsAuxiliaryButtons, isEventInsideCard(event) else { return event }
                return handleAuxiliaryMouseButton(event)
            default:
                return event
            }
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard event.window === window else { return event }
            if axis == .vertical, !event.hasPreciseScrollingDeltas {
                guard isEventInsideCard(event),
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
                let direction: PageSwipeDirection = event.scrollingDeltaY > 0 ? .previous : .next
                // Coalesce a fast flick while allowing an immediate change of direction.
                if direction != lastWheelDirection || event.timestamp - lastWheelPageTime >= 0.24 {
                    lastWheelDirection = direction
                    lastWheelPageTime = event.timestamp
                    onSwipe?(direction)
                }
                return nil
            }

            let startsGesture = event.phase.contains(.began) || event.phase.contains(.mayBegin)
            if startsGesture || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                scrollAxis = nil
                accumulatedDelta = 0
                hasTriggeredSwipe = false
                if !isEventInsideCard(event) {
                    scrollAxis = axis == .vertical ? .horizontal : .vertical
                }
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) || !event.momentumPhase.isEmpty {
                return scrollAxis == axis ? nil : event
            }

            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY
            if scrollAxis == nil {
                guard isEventInsideCard(event), max(abs(horizontal), abs(vertical)) > 1 else { return event }
                scrollAxis = abs(horizontal) >= abs(vertical) ? .horizontal : .vertical
            }
            guard scrollAxis == axis else { return event }

            if !hasTriggeredSwipe {
                accumulatedDelta += axis == .horizontal ? horizontal : vertical
                if abs(accumulatedDelta) >= threshold {
                    hasTriggeredSwipe = true
                    onSwipe?(accumulatedDelta > 0 ? .previous : .next)
                }
            }

            return nil
        }

        fileprivate func isEventInsideCard(_ event: NSEvent) -> Bool {
            guard let window, event.window === window else { return false }
            let point = convert(event.locationInWindow, from: nil)
            return visibleRect.contains(point)
        }

        private func handleAuxiliaryMouseButton(_ event: NSEvent) -> NSEvent? {
            switch event.buttonNumber {
            case 3:
                onSwipe?(.previous)
                return nil
            case 4:
                onSwipe?(.next)
                return nil
            default:
                return event
            }
        }
    }
}
