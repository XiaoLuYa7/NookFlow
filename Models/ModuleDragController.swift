import SwiftUI

/// Manages drag-to-reorder state for the module card row.
///
/// Architecture: the dragged card is hidden at its source slot; remaining cards
/// rearrange in real-time to fill the gap and show the insertion point.
/// A floating preview overlay follows the cursor independently of the layout.
///
/// State is split so that continuous drag offset updates don't trigger card relayout;
/// only `targetIndex` changes cause the card grid to re-render.
@MainActor
final class ModuleDragController: ObservableObject {

    // MARK: - Constants

    static let longPressDuration: TimeInterval = 0.4
    static let dragMinDistance: CGFloat = 0
    static let rearrangeAnimation = Animation.easeOut(duration: 0.25)
    static let dropAnimation = Animation.spring(response: 0.30, dampingFraction: 0.88, blendDuration: 0.04)

    // MARK: - State (split to minimize re-render scope)

    /// Set once at drag start. Cards use this only for source opacity.
    @Published private(set) var isDragging = false
    @Published private(set) var sourceIndex: Int?

    /// Only changes when cursor crosses a midpoint threshold — triggers card rearrange.
    @Published private(set) var targetIndex: Int?

    /// Continuous — but only the preview overlay reads this.
    @Published private(set) var dragOffset: CGSize = .zero

    /// Set to true during the snap-to-slot animation after drop.
    @Published private(set) var isDropping = false

    /// Begin the drop snap animation toward the given target offset.
    func beginDropAnimation(targetOffset: CGFloat) {
        dropTargetOffset = targetOffset
        isDropping = true
    }
    /// The x-offset (top-leading) where the preview should animate to on drop.
    @Published var dropTargetOffset: CGFloat = 0

    // MARK: - Captured at drag start (not published, no re-render)

    private var sourceOrigin: CGPoint = .zero
    private var midXs: [CGFloat] = []
    private var widths: [CGFloat] = []

    // MARK: - Public API

    var isActive: Bool { isDragging }

    func startDrag(sourceIndex: Int, sourceOrigin: CGPoint, midXs: [CGFloat], widths: [CGFloat]) {
        isDragging = true
        isDropping = false
        self.sourceIndex = sourceIndex
        self.sourceOrigin = sourceOrigin
        self.midXs = midXs
        self.widths = widths
        targetIndex = sourceIndex
        dragOffset = .zero
        dropTargetOffset = 0
    }

    /// Called on every drag movement. Only updates `dragOffset` and
    /// recomputes `targetIndex` when crossing a midpoint with hysteresis.
    func updateDrag(translation: CGSize) {
        dragOffset = translation

        let cursorX = sourceOrigin.x + translation.width
        let newTarget = computeTargetIndex(cursorX: cursorX)
        if newTarget != targetIndex {
            withAnimation(Self.rearrangeAnimation) {
                targetIndex = newTarget
            }
        }
    }

    /// Cursor position in container space (source center + drag offset).
    var cursorPosition: CGPoint {
        CGPoint(
            x: sourceOrigin.x + dragOffset.width,
            y: sourceOrigin.y + dragOffset.height
        )
    }

    /// Width of the dragged card.
    var sourceWidth: CGFloat {
        guard let idx = sourceIndex, widths.indices.contains(idx) else { return 0 }
        return widths[idx]
    }

    /// Computes the layout for a rearranged card order based on current targetIndex.
    /// The dragged card is removed from the list and inserted at the target position.
    func rearrangedLayout<T>(modules: [T], containerWidth: CGFloat, spacing: CGFloat, widthFor: (T) -> CGFloat) -> (offsets: [CGFloat], widths: [CGFloat]) {
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
        isDragging = false
        isDropping = false
        sourceIndex = nil
        targetIndex = nil
        dragOffset = .zero
        dropTargetOffset = 0
        sourceOrigin = .zero
        midXs = []
        widths = []
    }

    // MARK: - Target Detection with Hysteresis

    private func computeTargetIndex(cursorX: CGFloat) -> Int {
        let count = midXs.count
        guard count > 0 else { return 0 }

        // Hysteresis: use a wider zone around the current target to prevent flickering.
        // Only switch when the cursor clearly crosses the midpoint between adjacent cards.
        let current = targetIndex ?? 0

        for (index, midX) in midXs.enumerated() {
            if index == current {
                // For the current target, use the adjacent boundary with hysteresis
                let prevBoundary: CGFloat = index > 0 ? (midXs[index - 1] + midX) / 2 : -CGFloat.infinity
                let nextBoundary: CGFloat = index < count - 1 ? (midX + midXs[index + 1]) / 2 : CGFloat.infinity

                if cursorX < prevBoundary {
                    return index - 1
                } else if cursorX >= nextBoundary {
                    // Will be caught by next iteration
                    continue
                } else {
                    return index
                }
            }

            // For non-current indices, check if cursor is in their zone
            let prevBoundary: CGFloat = index > 0 ? (midXs[index - 1] + midX) / 2 : -CGFloat.infinity
            let nextBoundary: CGFloat = index < count - 1 ? (midX + midXs[index + 1]) / 2 : CGFloat.infinity

            if cursorX >= prevBoundary && cursorX < nextBoundary {
                return index
            }
        }

        // Cursor is past the last card
        return count
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
