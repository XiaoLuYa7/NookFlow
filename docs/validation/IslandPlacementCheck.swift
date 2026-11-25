// Compile alongside Models/NotchGeometryProvider.swift; no app windows or user files are touched.
import AppKit
import SwiftUI

enum IslandDesignTokens {
    static let defaultCameraCapsuleSize = CGSize(width: 185, height: 32)
}

@main
struct IslandPlacementCheck {
    @MainActor static func main() {
        let screen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: 100, width: 1920, height: 1056)
        for scale in [1.0, 2.0] {
            for position in [0.0, 0.5, 1.0] {
                let rect = NotchGeometryProvider.floatingPanelRect(size: CGSize(width: 1000, height: 400),
                    screenFrame: screen, visibleFrame: visible, scale: scale,
                    horizontalPosition: position, topInset: 12)
                precondition(rect.minX >= screen.minX && rect.maxX <= screen.maxX)
                precondition(rect.maxY == visible.maxY - 12)
                precondition(rect.minY >= visible.minY)
                let shorter = NotchGeometryProvider.floatingPanelRect(size: CGSize(width: 1000, height: 200),
                    screenFrame: screen, visibleFrame: visible, scale: scale,
                    horizontalPosition: position, topInset: 12)
                precondition(rect.midX == shorter.midX && rect.maxY == shorter.maxY)
            }
        }
        let shallow = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let clamped = NotchGeometryProvider.floatingPanelRect(size: CGSize(width: 800, height: 480),
            screenFrame: shallow, visibleFrame: shallow, scale: 2, horizontalPosition: 0.5, topInset: 200)
        precondition(clamped.minY == 0)
        let anchoredTall = NotchGeometryProvider.floatingPanelRect(size: CGSize(width: 800, height: 480),
            screenFrame: shallow, visibleFrame: shallow, scale: 2, horizontalPosition: 0.5, topInset: 200, anchorHeight: 36)
        let anchoredShort = NotchGeometryProvider.floatingPanelRect(size: CGSize(width: 800, height: 240),
            screenFrame: shallow, visibleFrame: shallow, scale: 2, horizontalPosition: 0.5, topInset: 200, anchorHeight: 36)
        precondition(anchoredTall.maxY == anchoredShort.maxY && anchoredTall.maxY == 300)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for external in [CGRect(x: -1920, y: 100, width: 1920, height: 1080),
                         CGRect(x: 0, y: 900, width: 1920, height: 1080),
                         CGRect(x: 0, y: -1080, width: 1920, height: 1080)] {
            let server = NotchGeometryProvider.windowServerScreenRect(for: external, primaryScreenFrame: primary)
            precondition(server.minX == external.minX && server.minY == primary.maxY - external.maxY)
            let restored = NotchGeometryProvider.windowServerScreenRect(for: server, primaryScreenFrame: primary)
            precondition(restored == external)
        }
        let fallback = NotchGeometryProvider.geometry(for: nil, capsuleWidth: 220, capsuleHeight: 36)
        precondition(!fallback.hasNotch && fallback.cameraZoneWidth == 0 && fallback.sideWidth == 110)
        print("PASS: negative screen origins, edge clamping, 1x/2x scaling, stable center/top anchor, vertical bounds, notch-free geometry")
    }
}
