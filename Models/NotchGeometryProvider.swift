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

    // CGWindow bounds use a top-left origin; AppKit display frames use a bottom-left origin.
    static func windowServerScreenRect(for frame: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }

    static func floatingPanelRect(size: CGSize, screenFrame: CGRect, visibleFrame: CGRect,
                                  scale: CGFloat, horizontalPosition: Double, topInset: Double, anchorHeight: CGFloat? = nil) -> CGRect {
        let scale = max(1, scale)
        let width = ceil(size.width * scale) / scale
        let height = ceil(size.height * scale) / scale
        let halfWidth = min(width / 2, screenFrame.width / 2)
        let desiredCenter = screenFrame.minX + screenFrame.width * min(1, max(0, horizontalPosition))
        let center = min(screenFrame.maxX - halfWidth, max(screenFrame.minX + halfWidth, desiredCenter))
        // Workbench height changes must not move the capsule anchor. Oversized content may extend below the display.
        let inset = min(max(0, topInset), max(0, visibleFrame.height - (anchorHeight ?? height)))
        return CGRect(x: round((center - width / 2) * scale) / scale,
                      y: round((visibleFrame.maxY - inset - height) * scale) / scale,
                      width: width, height: height)
    }

    static func cameraSafeRegionCenterX(for screen: NSScreen?) -> CGFloat? {
        cameraSafeRegionRect(for: screen)?.midX
    }

    static func cameraSafeRegionSize(for screen: NSScreen?) -> CGSize? {
        cameraSafeRegionRect(for: screen)?.size
    }

    static func cameraSafeRegionRect(for screen: NSScreen?) -> CGRect? {
        guard let screen else { return nil }

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            return measuredCameraSafeRegion(
                leftArea: leftArea,
                rightArea: rightArea,
                safeAreaTopInset: screen.safeAreaInsets.top,
                menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY),
                backingScaleFactor: screen.backingScaleFactor
            )
        }

        return nil
    }

    static func measuredCameraSafeRegion(
        leftArea: CGRect,
        rightArea: CGRect,
        safeAreaTopInset: CGFloat,
        menuBarHeight: CGFloat,
        backingScaleFactor: CGFloat
    ) -> CGRect? {
        let scale = max(1, backingScaleFactor)
        let leftEdge = round(leftArea.maxX * scale) / scale
        let rightEdge = round(rightArea.minX * scale) / scale
        let notchWidth = rightEdge - leftEdge
        guard notchWidth > 1 else { return nil }

        let measuredHeight = max(
            max(safeAreaTopInset, menuBarHeight),
            max(
                leftArea.height,
                max(rightArea.height, IslandDesignTokens.defaultCameraCapsuleSize.height)
            )
        )
        let notchHeight = ceil(measuredHeight * scale) / scale

        return CGRect(
            x: leftEdge,
            y: 0,
            width: notchWidth,
            height: notchHeight
        )
    }

    static func cameraRegionSize(for screen: NSScreen?) -> CGSize? {
        cameraSafeRegionSize(for: screen)
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
        let cameraWidth: CGFloat = 0
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


extension NSScreen {
    var nookFlowDisplayID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
