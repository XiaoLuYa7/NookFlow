import AppKit
import SwiftUI

struct HandCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.arrow.set()
                    isHovering = false
                }
            }
    }
}

extension View {
    func handCursor() -> some View {
        modifier(HandCursorModifier())
    }
}
