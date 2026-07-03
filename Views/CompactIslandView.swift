import SwiftUI

struct CompactIslandView: View {

    let namespace: Namespace.ID
    let onTap: () -> Void

    var body: some View {
        let shape = DynamicIslandShape(
            shoulderWidth: IslandDesignTokens.compactShoulderWidth,
            shoulderDepth: IslandDesignTokens.compactShoulderDepth,
            sideInset: IslandDesignTokens.compactSideInset,
            bottomCornerRadius: IslandDesignTokens.compactCornerRadius,
            visibleSize: IslandDesignTokens.compactSize
        )

        HStack(spacing: 7) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandDesignTokens.iconColor)

            Text(IslandDesignTokens.compactName)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(IslandDesignTokens.primaryText)
                .lineLimit(1)
        }
        .frame(width: IslandDesignTokens.compactSize.width, height: IslandDesignTokens.compactSize.height)
        .background {
            shape
                .fill(IslandDesignTokens.panelColor)
                .matchedGeometryEffect(id: "islandBackground", in: namespace)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
    }
}
