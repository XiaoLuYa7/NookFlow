import SwiftUI

struct PinButton: View {

    let isPinned: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isPinned
                        ? AppColor.accent.opacity(0.96)
                        : Color.white.opacity(0.88)
                )
                .frame(width: IslandDesignTokens.pinButtonSize, height: IslandDesignTokens.pinButtonSize)
                .background {
                    Circle()
                        .fill(pinBackground)
                }
                .overlay {
                    Circle()
                        .stroke(pinBorder, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1)
        .onHover { isHovering = $0 }
        .animation(AppMotion.quick, value: isHovering)
        .animation(AppMotion.standard, value: isPinned)
        .help(isPinned ? "Unpin expanded island" : "Pin expanded island")
    }

    private var pinBackground: Color {
        if isPinned {
            return Color(red: 0.24, green: 0.26, blue: 0.30).opacity(isHovering ? 0.94 : 0.88)
        }
        return Color(red: 0.29, green: 0.30, blue: 0.34).opacity(isHovering ? 0.88 : 0.78)
    }

    private var pinBorder: Color {
        isPinned
            ? AppColor.accent.opacity(0.62)
            : Color.white.opacity(isHovering ? 0.34 : 0.22)
    }
}
