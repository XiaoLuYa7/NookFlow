import AppKit
import SwiftUI

struct NotchGeometry: Equatable {
    let hasNotch: Bool
    let cameraZoneWidth: CGFloat
    let sideWidth: CGFloat
    let totalWidth: CGFloat
    let height: CGFloat
}

@MainActor
enum NotchGeometryProvider {
    private static let fallbackCameraRegionWidth: CGFloat = 185

    static func cameraSafeRegionCenterX(for screen: NSScreen?) -> CGFloat? {
        guard let screen else { return nil }

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - leftArea.width - rightArea.width + 4

            guard notchWidth > 1 else { return nil }
            return screen.frame.minX + leftArea.width + notchWidth / 2
        }

        return nil
    }

    static func cameraSafeRegionSize(for screen: NSScreen?) -> CGSize? {
        guard let screen else { return nil }

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - leftArea.width - rightArea.width + 4
            let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let notchHeight = max(
                screen.safeAreaInsets.top,
                menuBarHeight,
                IslandDesignTokens.defaultCameraCapsuleSize.height
            )

            guard notchWidth > 1 else { return nil }
            return CGSize(width: ceil(notchWidth), height: ceil(notchHeight))
        }

        return nil
    }

    static func cameraRegionSize(for screen: NSScreen?) -> CGSize? {
        guard let safeRegion = cameraSafeRegionSize(for: screen) else { return nil }

        return CGSize(
            width: safeRegion.width + IslandDesignTokens.cameraSafeRegionVisualWidthCompensation,
            height: safeRegion.height
        )
    }

    static func cameraCapsuleSize(for screen: NSScreen?) -> CGSize? {
        cameraRegionSize(for: screen)
    }

    static func geometry(
        for screen: NSScreen?,
        capsuleWidth: CGFloat,
        capsuleHeight: CGFloat
    ) -> NotchGeometry {
        guard let screen else {
            return fallbackGeometry(width: capsuleWidth, height: capsuleHeight)
        }

        if let cameraCapsule = cameraCapsuleSize(for: screen) {
            let safeRegionWidth = min(max(1, cameraCapsule.width), capsuleWidth)
            let side = max(0, (capsuleWidth - safeRegionWidth) / 2)
            return NotchGeometry(
                hasNotch: true,
                cameraZoneWidth: safeRegionWidth,
                sideWidth: side,
                totalWidth: capsuleWidth,
                height: capsuleHeight
            )
        }

        return fallbackGeometry(width: capsuleWidth, height: capsuleHeight)
    }

    private static func fallbackGeometry(width: CGFloat, height: CGFloat) -> NotchGeometry {
        let cameraWidth = min(fallbackCameraRegionWidth, width)
        let sideWidth = max(0, (width - cameraWidth) / 2)

        return NotchGeometry(
            hasNotch: cameraWidth > 0,
            cameraZoneWidth: cameraWidth,
            sideWidth: sideWidth,
            totalWidth: width,
            height: height
        )
    }
}
