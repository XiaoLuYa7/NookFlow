import SwiftUI

enum NotchLyricMask {

    private static let fadeWidth: CGFloat = 10

    /// Dual-zone mask: left and right visible, camera center transparent.
    /// Gradient edges create natural fade in/out at zone boundaries.
    static func notchMask(geometry: NotchGeometry) -> some View {
        let total = geometry.totalWidth
        let fade = fadeWidth

        let r1 = max(0, (geometry.sideWidth - fade) / total)
        let r2 = min(1, geometry.sideWidth / total)
        let r3 = max(0, 1 - geometry.sideWidth / total)
        let r4 = min(1, 1 - (geometry.sideWidth - fade) / total)

        return LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: r1),
                .init(color: .clear, location: r2),
                .init(color: .clear, location: r3),
                .init(color: .white, location: r4),
                .init(color: .white, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Edge-fade mask for no-notch screen (fade at left/right edges only).
    static func flatMask(width: CGFloat) -> some View {
        let fade = fadeWidth
        let r = fade / max(width, 1)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white, location: r),
                .init(color: .white, location: 1 - r),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
