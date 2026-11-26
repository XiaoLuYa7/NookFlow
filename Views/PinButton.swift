import SwiftUI

struct PinButton: View {
    let isPinned: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "lock.fill" : "lock.open")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isPinned ? AppColor.accent : Color.white.opacity(isHovering ? 0.95 : 0.72))
                .frame(width: 28, height: 24)
                .background(Color.white.opacity(isPinned || isHovering ? 0.09 : 0), in: Capsule())
                .frame(height: IslandDesignTokens.expandedTopBarControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .handCursor()
        .animation(AppMotion.quick, value: isHovering)
        .help(isPinned ? "取消固定展开" : "固定展开")
        .accessibilityLabel(isPinned ? "取消固定展开" : "固定展开")
    }
}
