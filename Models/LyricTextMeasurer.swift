import AppKit

enum LyricTextMeasurer {

    private static let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    private static let attributes: [NSAttributedString.Key: Any] = [.font: font]
    private static var cache: [String: CGFloat] = [:]
    private static let maxCacheSize = 128

    static func width(of text: String) -> CGFloat {
        if let cached = cache[text] { return cached }
        let size = (text as NSString).size(withAttributes: attributes)
        let w = ceil(size.width)
        if cache.count >= maxCacheSize { cache.removeAll() }
        cache[text] = w
        return w
    }

    static func invalidate() { cache.removeAll() }
}
