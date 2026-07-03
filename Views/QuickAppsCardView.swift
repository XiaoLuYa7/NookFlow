import AppKit
import SwiftUI

struct QuickAppsCardView: View {

    @ObservedObject private var store = QuickAppsStore.shared
    @EnvironmentObject private var settings: IslandSettings
    @State private var unavailableAlertItem: QuickAppItem?
    @State private var currentPage = 0

    private let columnSpacing: CGFloat = 10
    private let rowSpacing: CGFloat = 10
    private let iconSize: CGFloat = 42
    private let pageHeight: CGFloat = 94
    private let pageGap: CGFloat = 4
    private let pageHorizontalInset: CGFloat = 8
    private var pageCount: Int {
        let visibleSlotCount = min(
            QuickAppsStore.maxCount,
            max(store.items.count + (store.items.count < QuickAppsStore.maxCount ? 1 : 0), QuickAppsStore.pageSize)
        )
        return max(1, Int(ceil(Double(visibleSlotCount) / Double(QuickAppsStore.pageSize))))
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            GeometryReader { proxy in
                HStack(spacing: pageGap) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        pageView(page)
                            .frame(width: proxy.size.width, height: pageHeight)
                    }
                }
                .frame(width: proxy.size.width, height: pageHeight, alignment: .leading)
                .offset(x: -CGFloat(currentPage) * (proxy.size.width + pageGap))
            }
            .frame(maxWidth: .infinity)
            .frame(height: pageHeight)
            .clipped()
            .animation(pageAnimation, value: currentPage)

            if pageCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        Circle()
                            .fill(page == currentPage ? Color.white.opacity(0.82) : Color.white.opacity(0.24))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .overlay {
            HorizontalSwipeDetector { direction in
                switch direction {
                case .left: goToNextPage()
                case .right: goToPreviousPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .highPriorityGesture(horizontalPageDragGesture)
        .onChange(of: store.items.count) { _, _ in
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
        let start = page * QuickAppsStore.pageSize
        return Array(start..<(start + QuickAppsStore.pageSize))
    }

    private func pageView(_ page: Int) -> some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - pageHorizontalInset * 2)
            let cellWidth = max(1, (contentWidth - columnSpacing * 2) / 3)
            let cellHeight = max(iconSize, (pageHeight - rowSpacing) / 2)
            let indexes = pageIndexes(for: page)
            let rows = [
                Array(indexes.prefix(3)),
                Array(indexes.dropFirst(3).prefix(3))
            ]

            VStack(spacing: rowSpacing) {
                ForEach(0..<rows.count, id: \.self) { row in
                    HStack(spacing: columnSpacing) {
                        ForEach(rows[row], id: \.self) { index in
                            slotView(for: index)
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
    private func slotView(for index: Int) -> some View {
        if index < store.items.count {
            appCell(item: store.items[index])
        } else if index == store.items.count && store.items.count < QuickAppsStore.maxCount {
            addButton
        } else {
            Color.clear
        }
    }

    private func goToNextPage() {
        guard currentPage < pageCount - 1 else { return }
        TrackpadHapticFeedback.perform(settings.trackpadFeedbackMode)
        withAnimation(pageAnimation) {
            currentPage += 1
        }
    }

    private func goToPreviousPage() {
        guard currentPage > 0 else { return }
        TrackpadHapticFeedback.perform(settings.trackpadFeedbackMode)
        withAnimation(pageAnimation) {
            currentPage -= 1
        }
    }

    private var pageAnimation: Animation {
        .smooth(duration: QuickAppsPageTiming.pageTurnDuration, extraBounce: 0)
    }

    private var horizontalPageDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                guard abs(width) > abs(height), abs(width) > 28 else { return }

                if width < 0 {
                    goToNextPage()
                } else {
                    goToPreviousPage()
                }
            }
    }

    // MARK: - App Cell

    private func appCell(item: QuickAppItem) -> some View {
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
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "questionmark.app.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .frame(width: iconSize, height: iconSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            openQuickAppsSettings()
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
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

enum HorizontalSwipeDirection {
    case left
    case right
}

struct HorizontalSwipeDetector: NSViewRepresentable {
    var supportsAuxiliaryButtons = true
    var threshold: CGFloat = 18
    var onSwipe: (HorizontalSwipeDirection) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.supportsAuxiliaryButtons = supportsAuxiliaryButtons
        view.threshold = threshold
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ nsView: SwipeView, context: Context) {
        nsView.onSwipe = onSwipe
        nsView.supportsAuxiliaryButtons = supportsAuxiliaryButtons
        nsView.threshold = threshold
    }

    final class SwipeView: NSView {
        var onSwipe: ((HorizontalSwipeDirection) -> Void)?
        var supportsAuxiliaryButtons = true
        var threshold: CGFloat = 18
        private var accumulatedDeltaX: CGFloat = 0
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
                if let localMonitor {
                    NSEvent.removeMonitor(localMonitor)
                    self.localMonitor = nil
                }
            } else if localMonitor == nil {
                let eventTypes: NSEvent.EventTypeMask = supportsAuxiliaryButtons
                    ? [.scrollWheel, .otherMouseDown]
                    : .scrollWheel
                localMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: eventTypes
                ) { [weak self] event in
                    self?.handleLocalEvent(event) ?? event
                }
            }
        }

        private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
            guard isEventInsideCard(event) else { return event }

            switch event.type {
            case .scrollWheel:
                return handleTrackpadScroll(event)
            case .otherMouseDown:
                return supportsAuxiliaryButtons ? handleAuxiliaryMouseButton(event) : event
            default:
                return event
            }
        }

        private func handleTrackpadScroll(_ event: NSEvent) -> NSEvent? {
            let horizontal = event.scrollingDeltaX
            let vertical = event.scrollingDeltaY

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulatedDeltaX = 0
                hasTriggeredSwipe = false
            }

            if event.phase == .ended || event.momentumPhase == .ended {
                return nil
            }

            guard abs(horizontal) > abs(vertical), abs(horizontal) > 1 else {
                return event
            }

            if !hasTriggeredSwipe {
                accumulatedDeltaX += horizontal
                if abs(accumulatedDeltaX) >= threshold {
                    let direction: HorizontalSwipeDirection = accumulatedDeltaX > 0 ? .right : .left
                    hasTriggeredSwipe = true
                    accumulatedDeltaX = 0
                    onSwipe?(direction)
                }
            }

            return nil
        }

        private func isEventInsideCard(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            let point = convert(event.locationInWindow, from: nil)
            return bounds.insetBy(dx: -2, dy: -2).contains(point)
        }

        private func handleAuxiliaryMouseButton(_ event: NSEvent) -> NSEvent? {
            switch event.buttonNumber {
            case 3:
                onSwipe?(.right)
                return nil
            case 4:
                onSwipe?(.left)
                return nil
            default:
                return event
            }
        }

        override func scrollWheel(with event: NSEvent) {
            if handleTrackpadScroll(event) != nil {
                super.scrollWheel(with: event)
            }
        }

        override func otherMouseDown(with event: NSEvent) {
            if handleAuxiliaryMouseButton(event) != nil {
                super.otherMouseDown(with: event)
            }
        }
    }
}
