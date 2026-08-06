import AppKit
import CoreText

enum LyricTextDesign: String, Hashable {
    case standard
    case rounded
}

struct LyricUnitLayout: Equatable {
    let range: Range<Int>
    let minX: CGFloat
    let width: CGFloat
}

struct LyricTextLayout: Equatable {
    let totalWidth: CGFloat
    let units: [LyricUnitLayout]

    func revealedWidth(
        at playbackTime: TimeInterval,
        for line: EstimatedLyricLine
    ) -> CGFloat {
        let reveal = line.revealState(at: playbackTime)
        guard !reveal.isComplete else { return totalWidth }

        var completedWidth: CGFloat = 0
        for unit in units {
            if unit.range.upperBound <= reveal.completedUTF16Offset {
                completedWidth = max(completedWidth, unit.minX + unit.width)
            }
        }

        guard let activeRange = reveal.activeUnitRange,
              let activeLayout = units.first(where: { $0.range == activeRange }) else {
            return min(max(completedWidth, 0), totalWidth)
        }

        let activeWidth = activeLayout.minX
            + activeLayout.width * CGFloat(reveal.activeUnitProgress)
        return min(max(max(completedWidth, activeWidth), 0), totalWidth)
    }
}

enum LyricTextMeasurer {

    private static let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    private static let attributes: [NSAttributedString.Key: Any] = [.font: font]
    private static var cache: [String: CGFloat] = [:]
    private static var layoutCache: [LayoutCacheKey: LyricTextLayout] = [:]
    private static let maxCacheSize = 128

    static func width(of text: String) -> CGFloat {
        if let cached = cache[text] { return cached }
        let size = (text as NSString).size(withAttributes: attributes)
        let w = ceil(size.width)
        if cache.count >= maxCacheSize { cache.removeAll() }
        cache[text] = w
        return w
    }

    static func systemFont(
        size: CGFloat,
        weight: NSFont.Weight,
        design: LyricTextDesign
    ) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard design == .rounded,
              let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    static func layout(
        for line: EstimatedLyricLine,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        design: LyricTextDesign
    ) -> LyricTextLayout {
        let font = systemFont(size: fontSize, weight: weight, design: design)
        let key = LayoutCacheKey(
            text: line.text,
            fontName: font.fontName,
            fontSize: font.pointSize,
            ranges: line.units.map(\.range)
        )
        if let cached = layoutCache[key] {
            return cached
        }

        let attributed = NSAttributedString(
            string: line.text,
            attributes: [.font: font]
        )
        let textLine = CTLineCreateWithAttributedString(attributed)
        let totalWidth = max(1, ceil(CGFloat(CTLineGetTypographicBounds(
            textLine,
            nil,
            nil,
            nil
        ))))
        let unitLayouts = line.units.map { unit in
            let minX = CTLineGetOffsetForStringIndex(
                textLine,
                unit.range.lowerBound,
                nil
            )
            let maxX = CTLineGetOffsetForStringIndex(
                textLine,
                unit.range.upperBound,
                nil
            )
            return LyricUnitLayout(
                range: unit.range,
                minX: minX,
                width: max(0, maxX - minX)
            )
        }
        let layout = LyricTextLayout(totalWidth: totalWidth, units: unitLayouts)

        if layoutCache.count >= maxCacheSize {
            layoutCache.removeAll(keepingCapacity: true)
        }
        layoutCache[key] = layout
        return layout
    }

    static func invalidate() {
        cache.removeAll()
        layoutCache.removeAll()
    }

    private struct LayoutCacheKey: Hashable {
        let text: String
        let fontName: String
        let fontSize: CGFloat
        let ranges: [Range<Int>]
    }
}
