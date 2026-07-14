import SwiftUI

@MainActor
enum IslandShellLayout {
    static let moduleCardLayoutSpacing: CGFloat = 6

    static func visibleModules(settings: IslandSettings) -> [IslandPanelModule] {
        let saved = settings.moduleOrder.compactMap { IslandPanelModule(rawValue: $0) }
        let defaults = IslandPanelModule.allCases
        let missing = defaults.filter { !saved.contains($0) }
        let order = saved.isEmpty ? defaults : saved + missing

        return order.filter { module in
            switch module {
            case .weather:    settings.showWeatherModule
            case .calendar:   settings.showCalendarModule
            case .todo:       settings.showTodoModule
            case .media:      settings.showMediaModule
            case .quickApps:  settings.showQuickAppsModule
            case .shortcuts:  settings.showShortcutsModule
            case .imageCard:  settings.showImageCardModule
            case .deviceInfo: settings.showDeviceInfoModule
            }
        }
    }

    static func effectiveIslandSize(settings: IslandSettings) -> CGSize {
        CGSize(
            width: effectiveIslandWidth(settings: settings),
            height: effectiveIslandHeight(settings: settings)
        )
    }

    static func effectiveIslandHeight(settings: IslandSettings) -> CGFloat {
        let compressedHeight = settings.islandSize.height * IslandDesignTokens.moduleHeightCompressionRatio
        let height = min(
            max(compressedHeight, IslandDesignTokens.fourColumnsMinimumExpandedHeight),
            IslandDesignTokens.fourColumnsMaximumExpandedHeight
        )
        return max(1, height - IslandDesignTokens.expandedTopBarHeightReduction - 10)
    }

    static func effectiveIslandWidth(settings: IslandSettings) -> CGFloat {
        let modules = visibleModules(settings: settings)
        guard !modules.isEmpty else {
            return settings.islandSize.width
        }

        let spacing = moduleCardLayoutSpacing
        let baseCount = max(1, modules.filter { $0 != .shortcuts }.count)
        let baseGridWidth = max(1, settings.islandSize.width - IslandDesignTokens.expandedPadding * 2)
        let baseCardWidth = max(0, (baseGridWidth - spacing * CGFloat(baseCount - 1)) / CGFloat(baseCount))
        let totalWeight = modules.reduce(CGFloat(0)) { partial, module in
            partial + moduleWidthWeight(module, referenceHeight: moduleLayoutReferenceHeight(settings: settings))
        }
        let totalSpacing = spacing * CGFloat(max(0, modules.count - 1))
        let minimumWidthUnit = modules.reduce(CGFloat(0)) { current, module in
            let weight = moduleWidthWeight(
                module,
                referenceHeight: moduleLayoutReferenceHeight(settings: settings)
            )
            return max(current, moduleMinimumWidth(module) / max(weight, 0.01))
        }
        let minimumContentWidth = minimumWidthUnit * totalWeight
            + totalSpacing
            + IslandDesignTokens.expandedPadding * 2
        let weightedContentWidth = baseCardWidth * totalWeight
            + totalSpacing
            + IslandDesignTokens.expandedPadding * 2

        return max(weightedContentWidth, minimumContentWidth)
    }

    static func contentSize(settings: IslandSettings, selectedTopTab: IslandTopTab) -> CGSize {
        let unifiedWidth = effectiveIslandWidth(settings: settings)

        switch selectedTopTab {
        case .applications:
            return CGSize(
                width: unifiedWidth,
                height: IslandDesignTokens.applicationsExpandedHeight
            )
        case .files:
            return CGSize(
                width: unifiedWidth,
                height: IslandDesignTokens.filesExpandedHeight
            )
        case .home:
            return CGSize(
                width: unifiedWidth,
                height: effectiveIslandHeight(settings: settings)
            )
        }
    }

    static func windowSize(settings: IslandSettings, selectedTopTab: IslandTopTab) -> CGSize {
        let size = contentSize(settings: settings, selectedTopTab: selectedTopTab)
        return CGSize(
            width: size.width + 40,
            height: size.height + IslandDesignTokens.applicationsWindowVerticalPadding
        )
    }

    static func openingEnvelopeSize(
        settings: IslandSettings,
        selectedTopTab: IslandTopTab
    ) -> CGSize {
        let content = contentSize(settings: settings, selectedTopTab: selectedTopTab)
        return CGSize(
            width: content.width * IslandDesignTokens.shellOpenPrimaryWidthOvershoot,
            height: content.height * IslandDesignTokens.shellOpenPrimaryHeightOvershoot
        )
    }

    static func openingWindowEnvelopeSize(
        settings: IslandSettings,
        selectedTopTab: IslandTopTab
    ) -> CGSize {
        let envelope = openingEnvelopeSize(
            settings: settings,
            selectedTopTab: selectedTopTab
        )
        return CGSize(
            width: envelope.width + 40,
            height: envelope.height + IslandDesignTokens.applicationsWindowVerticalPadding
        )
    }

    static func shellSize(
        settings: IslandSettings,
        selectedTopTab: IslandTopTab,
        compactSize: CGSize,
        compactScaleX: CGFloat,
        compactScaleY: CGFloat,
        animationState: IslandShellAnimationState,
        isCompact: Bool
    ) -> CGSize {
        let content = contentSize(settings: settings, selectedTopTab: selectedTopTab)
        let state = animationState.clamped()
        let hoverScaleX = isCompact ? compactScaleX : 1
        let hoverScaleY = isCompact ? compactScaleY : 1

        return CGSize(
            width: shellDimension(
                compact: compactSize.width,
                expanded: content.width,
                progress: state.widthProgress
            ) * hoverScaleX,
            height: shellDimension(
                compact: compactSize.height,
                expanded: content.height,
                progress: state.heightProgress
            ) * hoverScaleY
        )
    }

    static func progressForCompactScale(
        compact: CGFloat,
        expanded: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let range = expanded - compact
        guard abs(range) > 0.001 else { return 0 }
        return compact * (scale - 1) / range
    }

    static func progressForExpandedScale(
        compact: CGFloat,
        expanded: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let range = expanded - compact
        guard abs(range) > 0.001 else { return scale }
        return (expanded * scale - compact) / range
    }

    static func shellSeedState(
        settings: IslandSettings,
        selectedTopTab: IslandTopTab,
        compactSize: CGSize
    ) -> IslandShellAnimationState {
        let content = contentSize(settings: settings, selectedTopTab: selectedTopTab)
        let heightRange = max(1, content.height - compactSize.height)
        let targetHeight = min(
            content.height,
            max(compactSize.height, IslandDesignTokens.shellSeedHeight)
        )

        return IslandShellAnimationState(
            widthProgress: IslandDesignTokens.shellSeedWidthRatio,
            heightProgress: clamped((targetHeight - compactSize.height) / heightRange),
            morphProgress: 0.38
        )
    }

    static func shellShapeMetrics(
        shellSize: CGSize,
        compactSize: CGSize,
        morphProgress: CGFloat
    ) -> (
        shoulderWidth: CGFloat,
        shoulderDepth: CGFloat,
        sideInset: CGFloat,
        bottomCornerRadius: CGFloat
    ) {
        let progress = clamped(morphProgress)
        // The lower corners begin below the compact shoulder, so their usable
        // vertical radius is the remaining body height rather than half of the
        // full capsule height. Keeping this value in the same interpolation as
        // the expanded radius avoids a clipped-looking handoff during morphing.
        let compactBodyHeight = max(
            1,
            compactSize.height - IslandDesignTokens.compactShoulderDepth
        )
        let compactRadius = min(
            compactBodyHeight,
            IslandDesignTokens.compactShellCornerRadius
        )
        let bottomRadius = interpolate(
            compactRadius,
            IslandDesignTokens.expandedBottomCornerRadius,
            progress
        )
        let shoulderWidth = interpolate(
            min(IslandDesignTokens.compactShoulderWidth, compactSize.width / 4),
            IslandDesignTokens.expandedShoulderWidth,
            progress
        )
        let shoulderDepth = interpolate(
            min(IslandDesignTokens.compactShoulderDepth, compactSize.height * 0.44),
            IslandDesignTokens.expandedShoulderDepth,
            progress
        )
        let sideInset = interpolate(
            IslandDesignTokens.compactSideInset,
            IslandDesignTokens.expandedSideInset,
            progress
        )

        return (
            shoulderWidth: min(max(0, shoulderWidth), shellSize.width / 3),
            shoulderDepth: min(max(0, shoulderDepth), shellSize.height * 0.55),
            sideInset: min(max(0, sideInset), shellSize.width / 4),
            bottomCornerRadius: min(shellSize.height / 2, max(1, bottomRadius))
        )
    }

    static func moduleWidthWeight(_ module: IslandPanelModule, referenceHeight: CGFloat) -> CGFloat {
        switch module {
        case .weather:
            return 1.03
        case .media:
            return IslandDesignTokens.mediaModuleWidthWeight(for: referenceHeight)
        case .calendar:
            return 1.2
        case .todo:
            return 0.92
        case .quickApps:
            return IslandDesignTokens.quickAppsModuleWidthWeight
        case .shortcuts:
            return IslandDesignTokens.shortcutsModuleWidthWeight
        case .imageCard:
            return 0.68
        case .deviceInfo:
            return IslandDesignTokens.deviceInfoModuleWidthWeight
        }
    }

    private static func moduleMinimumWidth(_ module: IslandPanelModule) -> CGFloat {
        switch module {
        case .calendar:
            return 174
        case .weather:
            return 150
        case .media:
            return 190
        case .quickApps:
            return 140
        case .shortcuts:
            return 136
        case .imageCard:
            return 104
        case .deviceInfo:
            return 168
        case .todo:
            return 188
        }
    }

    static func moduleLayoutReferenceHeight(settings: IslandSettings) -> CGFloat {
        effectiveIslandHeight(settings: settings) + IslandDesignTokens.expandedTopBarHeightReduction
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    private static func shellDimension(
        compact: CGFloat,
        expanded: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        guard progress > 1 else {
            return interpolate(compact, expanded, progress)
        }
        return expanded * progress
    }
}

struct DynamicIslandShape: InsettableShape {
    var shoulderWidth: CGFloat
    var shoulderDepth: CGFloat
    var sideInset: CGFloat
    var bottomCornerRadius: CGFloat
    var visibleSize: CGSize
    var insetAmount: CGFloat = 0

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<
            AnimatablePair<CGFloat, CGFloat>,
            AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>
        >
    > {
        get {
            AnimatablePair(
                AnimatablePair(shoulderWidth, shoulderDepth),
                AnimatablePair(
                    AnimatablePair(sideInset, bottomCornerRadius),
                    AnimatablePair(
                        AnimatablePair(
                            visibleSize.width,
                            visibleSize.height
                        ),
                        insetAmount
                    )
                )
            )
        }
        set {
            shoulderWidth = newValue.first.first
            shoulderDepth = newValue.first.second
            sideInset = newValue.second.first.first
            bottomCornerRadius = newValue.second.first.second
            visibleSize = CGSize(
                width: max(1, newValue.second.second.first.first),
                height: max(1, newValue.second.second.first.second)
            )
            insetAmount = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let availableRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let width = min(max(1, visibleSize.width), availableRect.width)
        let height = min(max(1, visibleSize.height), availableRect.height)
        let rect = CGRect(
            x: availableRect.midX - width / 2,
            y: availableRect.minY,
            width: width,
            height: height
        )
        let shoulderWidth = min(max(0, shoulderWidth), rect.width / 3)
        let shoulderDepth = min(max(0, shoulderDepth), rect.height * 0.55)
        let sideInset = min(max(0, sideInset), rect.width / 4)
        let shoulderInset = min(sideInset, shoulderWidth)
        let bodyMinX = rect.minX + shoulderInset
        let bodyMaxX = rect.maxX - shoulderInset
        let bodyWidth = max(1, bodyMaxX - bodyMinX)
        let bottomRadius = min(max(0, bottomCornerRadius), bodyWidth / 2, rect.height - shoulderDepth)
        let curve = 0.5522847498
        let shoulderEndY = rect.minY + shoulderDepth
        let verticalHandle = shoulderDepth * 0.46
        let topHandle = shoulderInset * 0.72

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: bodyMaxX, y: shoulderEndY),
            control1: CGPoint(x: rect.maxX - topHandle, y: rect.minY),
            control2: CGPoint(x: bodyMaxX, y: shoulderEndY - verticalHandle)
        )
        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - bottomRadius))
        path.addCurve(
            to: CGPoint(x: bodyMaxX - bottomRadius, y: rect.maxY),
            control1: CGPoint(x: bodyMaxX, y: rect.maxY - bottomRadius + bottomRadius * curve),
            control2: CGPoint(x: bodyMaxX - bottomRadius + bottomRadius * curve, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + bottomRadius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - bottomRadius),
            control1: CGPoint(x: bodyMinX + bottomRadius - bottomRadius * curve, y: rect.maxY),
            control2: CGPoint(x: bodyMinX, y: rect.maxY - bottomRadius + bottomRadius * curve)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: shoulderEndY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: bodyMinX, y: shoulderEndY - verticalHandle),
            control2: CGPoint(x: rect.minX + topHandle, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> DynamicIslandShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
