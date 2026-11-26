import AppKit
import SwiftUI

@MainActor
final class ModuleDragPreviewPosition: ObservableObject {
    @Published fileprivate(set) var centerX: CGFloat = 0
}

@MainActor
final class ModuleDragController: ObservableObject {
    static let longPressDuration: TimeInterval = 0.27
    static let rearrangeAnimation = Animation.easeOut(duration: 0.22)
    private static let edgeWidth: CGFloat = 48
    private static let maximumScrollSpeed: CGFloat = 820

    @Published private(set) var sourceIndex: Int?
    @Published private(set) var targetIndex: Int?
    let previewPosition = ModuleDragPreviewPosition()

    private weak var scrollView: NSScrollView?
    private var edgeScrollTimer: Timer?
    private var lastScrollTick: TimeInterval = 0
    private var pointerPosition: CGPoint = .zero
    private var pointerToCardCenter: CGFloat = 0
    private var midXs: [CGFloat] = []
    private var viewportSize: CGSize = .zero
    private var reduceMotion = false

    var isDragging: Bool { sourceIndex != nil }

    deinit {
        edgeScrollTimer?.invalidate()
    }

    func attachScrollView(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
    }

    func detachScrollView(_ scrollView: NSScrollView) {
        guard self.scrollView === scrollView else { return }
        self.scrollView = nil
        reset()
    }

    func startDrag(
        sourceIndex: Int,
        sourceCenterX: CGFloat,
        startLocation: CGPoint,
        midXs: [CGFloat],
        viewportSize: CGSize,
        reduceMotion: Bool
    ) {
        self.midXs = midXs
        self.viewportSize = viewportSize
        self.reduceMotion = reduceMotion
        let scrollOffset = scrollView?.documentVisibleRect.minX ?? 0
        pointerToCardCenter = sourceCenterX - startLocation.x - scrollOffset
        pointerPosition = startLocation
        previewPosition.centerX = sourceCenterX
        targetIndex = sourceIndex
        self.sourceIndex = sourceIndex
    }

    func updateDrag(location: CGPoint) {
        guard isDragging else { return }
        pointerPosition = location
        updateDragPosition()
        updateEdgeScrolling()
    }

    /// The pointer is in viewport coordinates. Add the actual scroll offset so
    /// a stationary pointer can keep moving the insertion point as cards scroll.
    private func updateDragPosition() {
        let contentX = pointerPosition.x + (scrollView?.documentVisibleRect.minX ?? 0)
        let centerX = contentX + pointerToCardCenter
        let nextIndex = midXs.indices.dropLast().first { index in
            centerX < (midXs[index] + midXs[index + 1]) / 2
        } ?? max(0, midXs.count - 1)

        if previewPosition.centerX != centerX { previewPosition.centerX = centerX }
        if nextIndex != targetIndex {
            withAnimation(reduceMotion ? nil : Self.rearrangeAnimation) {
                targetIndex = nextIndex
            }
        }
    }

    private var edgeScrollVelocity: CGFloat {
        let edgeWidth = min(Self.edgeWidth, viewportSize.width / 2)
        guard edgeWidth > 0,
              (0...viewportSize.width).contains(pointerPosition.x),
              (0...viewportSize.height).contains(pointerPosition.y) else { return 0 }

        let leading = max(0, 1 - pointerPosition.x / edgeWidth)
        let trailing = max(0, 1 - (viewportSize.width - pointerPosition.x) / edgeWidth)
        let strength = trailing - leading
        guard strength != 0 else { return 0 }

        let minimumSpeed: CGFloat = 45
        let speed = minimumSpeed + (Self.maximumScrollSpeed - minimumSpeed) * strength * strength
        return strength < 0 ? -speed : speed
    }

    private func updateEdgeScrolling() {
        let velocity = edgeScrollVelocity
        guard let scrollView, scrollView.window?.isVisible == true,
              canScroll(scrollView, velocity: velocity) else {
            stopEdgeScrolling()
            return
        }
        guard edgeScrollTimer == nil else { return }

        lastScrollTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceEdgeScrolling() }
        }
        edgeScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceEdgeScrolling() {
        let velocity = edgeScrollVelocity
        guard isDragging, NSEvent.pressedMouseButtons & 1 != 0,
              let scrollView, scrollView.window?.isVisible == true,
              canScroll(scrollView, velocity: velocity) else {
            stopEdgeScrolling()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(now - lastScrollTick, 0.05)
        lastScrollTick = now
        Self.scroll(scrollView, by: velocity * elapsed)
        updateDragPosition()
        if !canScroll(scrollView, velocity: velocity) {
            stopEdgeScrolling()
        }
    }

    func stopEdgeScrolling() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
    }

    private func canScroll(_ scrollView: NSScrollView, velocity: CGFloat) -> Bool {
        let clip = scrollView.contentView
        let offset = clip.bounds.minX
        if velocity < 0 { return offset > clip.documentRect.minX }
        if velocity > 0 { return offset < clip.documentRect.maxX - clip.bounds.width }
        return false
    }

    static func scroll(_ scrollView: NSScrollView, by delta: CGFloat) {
        let clip = scrollView.contentView
        let document = clip.documentRect
        let maximum = max(document.minX, document.maxX - clip.bounds.width)
        let origin = clip.bounds.origin
        let x = min(max(origin.x + delta, document.minX), maximum)
        guard x != origin.x else { return }

        clip.scroll(to: CGPoint(x: x, y: origin.y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Computes the layout for a rearranged card order based on current targetIndex.
    /// The dragged card is removed from the list and inserted at the target position.
    func rearrangedLayout<T>(modules: [T], spacing: CGFloat, widthFor: (T) -> CGFloat) -> (offsets: [CGFloat], widths: [CGFloat]) {
        guard let source = sourceIndex, let target = targetIndex else {
            return normalLayout(modules: modules, spacing: spacing, widthFor: widthFor)
        }

        guard modules.indices.contains(source),
              target >= 0,
              target <= modules.count else {
            return normalLayout(modules: modules, spacing: spacing, widthFor: widthFor)
        }

        // Build virtual order: remove dragged card from source, then validate the
        // insertion point against the shortened array.
        var virtualOrder = Array(modules.enumerated())
        let draggedItem = virtualOrder.remove(at: source)
        let insertionIndex = min(target, virtualOrder.count)
        guard insertionIndex >= 0, insertionIndex <= virtualOrder.count else {
            return normalLayout(modules: modules, spacing: spacing, widthFor: widthFor)
        }
        virtualOrder.insert(draggedItem, at: insertionIndex)

        // Compute layout for the virtual order
        var virtualOffsets: [CGFloat] = []
        var virtualWidths: [CGFloat] = []
        var x: CGFloat = 0
        for (_, module) in virtualOrder {
            let w = widthFor(module)
            virtualOffsets.append(x)
            virtualWidths.append(w)
            x += w + spacing
        }

        // Map back to original indices
        var offsets = Array(repeating: CGFloat(0), count: modules.count)
        var widthsArr = Array(repeating: CGFloat(0), count: modules.count)
        for (virtualIdx, (originalIdx, _)) in virtualOrder.enumerated() {
            offsets[originalIdx] = virtualOffsets[virtualIdx]
            widthsArr[originalIdx] = virtualWidths[virtualIdx]
        }

        return (offsets, widthsArr)
    }

    /// Returns the final reordered array if a real move happened, else nil.
    func commitDrop<T>(_ modules: [T]) -> [T]? {
        guard let source = sourceIndex,
              let target = targetIndex,
              source != target,
              modules.indices.contains(source),
              target >= 0,
              target <= modules.count else {
            return nil
        }

        var result = modules
        let item = result.remove(at: source)
        let insertion = min(target, result.count)
        result.insert(item, at: insertion)
        return result
    }

    func reset() {
        stopEdgeScrolling()
        sourceIndex = nil
        targetIndex = nil
        midXs = []
    }

    private func normalLayout<T>(modules: [T], spacing: CGFloat, widthFor: (T) -> CGFloat) -> (offsets: [CGFloat], widths: [CGFloat]) {
        var offsets: [CGFloat] = []
        var widths: [CGFloat] = []
        var x: CGFloat = 0
        for module in modules {
            let w = widthFor(module)
            offsets.append(x)
            widths.append(w)
            x += w + spacing
        }
        return (offsets, widths)
    }
}
