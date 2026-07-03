import SwiftUI

struct AdaptiveGridConfiguration {
    let minimumItemWidth: CGFloat
    let maximumItemWidth: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let horizontalPadding: CGFloat

    var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumItemWidth, maximum: maximumItemWidth),
                spacing: horizontalSpacing,
                alignment: .top
            )
        ]
    }

    func metrics(for containerWidth: CGFloat) -> AdaptiveGridMetrics {
        let availableWidth = max(1, containerWidth - horizontalPadding * 2)
        let columnCount = max(
            1,
            Int((availableWidth + horizontalSpacing) / (minimumItemWidth + horizontalSpacing))
        )
        let totalSpacing = horizontalSpacing * CGFloat(max(0, columnCount - 1))
        let columnWidth = max(1, (availableWidth - totalSpacing) / CGFloat(columnCount))

        return AdaptiveGridMetrics(
            columnCount: columnCount,
            columnWidth: columnWidth,
            columnStride: columnWidth + horizontalSpacing
        )
    }
}

struct AdaptiveGridMetrics {
    let columnCount: Int
    let columnWidth: CGFloat
    let columnStride: CGFloat
}

enum IslandDesignTokens {
    static let appName = "L-Nook"
    static let compactName = "L-Nook"

    static let compactSize = CGSize(width: 96, height: 42)
    static let defaultCompactCapsuleSize = CGSize(width: 300, height: 24)
    static let defaultCameraCapsuleSize = CGSize(width: 96, height: 24)
    static let compactCapsuleHorizontalExtension: CGFloat = 64
    static let compactStatusCapsuleMaximumWidth: CGFloat = 360
    static let compactStatusCapsuleMaximumScreenRatio: CGFloat = 0.74
    static let cameraSafeRegionVisualWidthCompensation: CGFloat = 4
    static let compactLyricsCapsuleHorizontalExtension: CGFloat = 150
    static let compactLyricsCapsuleMinimumWidth: CGFloat = 460
    static let compactLyricsCapsuleMaximumScreenRatio: CGFloat = 0.62
    static let compactShellCornerRadius: CGFloat = 10
    static let defaultExpandedSize = CGSize(width: 900, height: 240)
    static let expandedSize = defaultExpandedSize
    static let windowSize = CGSize(width: defaultExpandedSize.width + 40, height: defaultExpandedSize.height + 40)
    static let cameraHoverSize = defaultCompactCapsuleSize
    static let cameraCollapseScaleX: CGFloat = 0.08
    static let cameraCollapseScaleY: CGFloat = 0.12
    static let shellSeedHeight: CGFloat = 66
    static let shellSeedWidthRatio: CGFloat = 0.48
    static let compactHoverWidthScale: CGFloat = 1.08
    static let compactHoverHeightScale: CGFloat = 1.04
    static let compactHoverPreviewDuration: TimeInterval = 0.12
    static let compactHoverHoldDuration: TimeInterval = 0.30
    static let compactHoverRestoreDuration: TimeInterval = 0.15

    static let compactCornerRadius: CGFloat = 21
    static let expandedCornerRadius: CGFloat = 34
    static let compactShoulderWidth: CGFloat = 30
    static let compactShoulderDepth: CGFloat = 10
    static let compactSideInset: CGFloat = 10
    static let expandedShoulderWidth: CGFloat = 56
    static let expandedShoulderDepth: CGFloat = 17
    static let expandedSideInset: CGFloat = 10
    static let expandedBottomCornerRadius: CGFloat = 20
    static let expandedPadding: CGFloat = 24
    static let expandedTopBarControlHeight: CGFloat = 30
    static let expandedTopBarTopPadding: CGFloat = 0
    static let expandedTopBarHeightReduction: CGFloat = 20
    static let pinButtonSize: CGFloat = 38
    static let externalPinButtonTrailingOverlap: CGFloat = 8
    static let externalPinButtonBottomOverlap: CGFloat = 8

    static let panelColor = AppColor.islandBackground
    static let moduleSurface = AppColor.islandSurface
    static let moduleSurfaceHover = AppColor.islandSurfaceHover
    static let moduleBorder = AppColor.islandBorder
    static let primaryText = AppColor.islandTextPrimary
    static let secondaryText = AppColor.islandTextSecondary
    static let iconColor = Color.white.opacity(0.76)

    static let applicationsExpandedHeight: CGFloat = 500
    static let filesExpandedHeight: CGFloat = 500
    static let applicationsWindowVerticalPadding: CGFloat = 40
    static let moduleHeightCompressionRatio: CGFloat = 0.82
    static let fourColumnsMinimumExpandedHeight: CGFloat = 195
    static let fourColumnsMaximumExpandedHeight: CGFloat = 240
    static let mediaModuleMinimumWidthWeight: CGFloat = 1.18
    static let mediaModuleMaximumWidthWeight: CGFloat = 1.30
    static let shortcutsModuleWidthWeight: CGFloat = 0.96

    static func mediaModuleWidthWeight(for islandHeight: CGFloat) -> CGFloat {
        let range = max(1, fourColumnsMaximumExpandedHeight - fourColumnsMinimumExpandedHeight)
        let progress = min(max((islandHeight - fourColumnsMinimumExpandedHeight) / range, 0), 1)
        return mediaModuleMinimumWidthWeight
            + (mediaModuleMaximumWidthWeight - mediaModuleMinimumWidthWeight) * progress
    }

    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.82, blendDuration: 0.08)
    static let quickSpring = Animation.spring(response: 0.32, dampingFraction: 0.84, blendDuration: 0.05)

    /// One compositor-driven curve for shell resizing, page fading and tab selection.
    /// SwiftUI evaluates it against the active display, so ProMotion screens are not
    /// artificially limited to a fixed timer frequency.
    static let tabSwitchDuration: TimeInterval = 0.40
    static let tabSwitchAnimation = Animation.smooth(duration: tabSwitchDuration, extraBounce: 0)
    static let tabReturnHomeDuration: TimeInterval = 0.44
    static let tabReturnHomeAnimation = Animation.smooth(
        duration: tabReturnHomeDuration,
        extraBounce: 0
    )
    static let pageFadeOutAnimation = Animation.easeOut(duration: 0.07)
    static let pageFadeInAnimation = Animation.easeOut(duration: 0.16)
    static let pageSwapDelay: TimeInterval = 0.065

    static let shellOpenMinimumDuration: TimeInterval = 0.52
    static let shellOpenMaximumDuration: TimeInterval = 0.82
    static let shellCloseMinimumDuration: TimeInterval = 0.34
    static let shellCloseMaximumDuration: TimeInterval = 0.58
    static let shellOpenInitialDelay: TimeInterval = 0.08
    static let shellOpenPrimaryWidthOvershoot: CGFloat = 1.08
    static let shellOpenPrimaryHeightOvershoot: CGFloat = 1.06
    static let shellOpenUndershootScale: CGFloat = 0.97
    static let shellOpenToExpandedDuration: TimeInterval = 0.28
    static let shellOpenPrimaryOvershootDuration: TimeInterval = 0.10
    static let shellOpenUndershootDuration: TimeInterval = 0.32
    static let shellOpenFinalSettleDuration: TimeInterval = 0.30
    static let shellOpenContentRevealLead: TimeInterval = 0.08
    static let shellOpenContentRevealDelay: TimeInterval = shellOpenToExpandedDuration
        + shellOpenPrimaryOvershootDuration
        + shellOpenUndershootDuration
        - shellOpenContentRevealLead
    static let shellOpenKeyframeDuration: TimeInterval = shellOpenToExpandedDuration
        + shellOpenPrimaryOvershootDuration
        + shellOpenUndershootDuration
        + shellOpenFinalSettleDuration
    /// Fast response at the start, followed by a long, gentle settle into the camera pill.
    static func shellCloseAnimation(duration: TimeInterval) -> Animation {
        .timingCurve(0.28, 0.46, 0.32, 1, duration: duration)
    }
    static let primaryContentRevealDuration: TimeInterval = shellOpenFinalSettleDuration
    static let secondaryContentRevealDuration: TimeInterval = 0.20
    static let secondaryContentRevealDelay: TimeInterval = 0.04
    static let contentHideDuration: TimeInterval = 0.13
    static let compactContentRevealDuration: TimeInterval = 0.10
    static let reduceMotionOpenDuration: TimeInterval = 0.18
    static let reduceMotionCloseDuration: TimeInterval = 0.16

    struct ShellOpenTiming {
        let toExpanded: TimeInterval
        let overshoot: TimeInterval
        let undershoot: TimeInterval
        let settle: TimeInterval

        var total: TimeInterval {
            toExpanded + overshoot + undershoot + settle
        }

        var contentRevealDelay: TimeInterval {
            max(0, toExpanded + overshoot + undershoot - min(0.08, settle * 0.34))
        }
    }

    static func shellOpenTiming(setting: Double) -> ShellOpenTiming {
        let total = mappedDuration(
            setting,
            minimum: shellOpenMinimumDuration,
            maximum: shellOpenMaximumDuration
        )
        return ShellOpenTiming(
            toExpanded: total * 0.44,
            overshoot: total * 0.09,
            undershoot: total * 0.18,
            settle: total * 0.29
        )
    }

    static func shellOpenDuration(setting: Double) -> TimeInterval {
        shellOpenTiming(setting: setting).total
    }

    static func shellCloseDuration(setting: Double) -> TimeInterval {
        mappedDuration(
            setting,
            minimum: shellCloseMinimumDuration,
            maximum: shellCloseMaximumDuration
        )
    }

    private static func mappedDuration(
        _ setting: Double,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        let progress = min(max((setting - 0.34) / (0.68 - 0.34), 0), 1)
        return minimum + (maximum - minimum) * progress
    }
}
