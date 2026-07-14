import Combine
import SwiftUI

struct IslandRootView: View {

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    let onOpenSettings: () -> Void
    let onOpenTodoSettings: () -> Void
    let onOpenFeedback: () -> Void

    private var playbackProvider: PlaybackProvider { viewModel.playbackProvider }
    private var lyricsProvider: LyricsProvider { viewModel.lyricsProvider }

    @StateObject private var weatherProvider = WeatherProvider()
    @StateObject private var deviceInfoProvider = DeviceInfoProvider()
    @StateObject private var batteryProvider = BatteryProvider()
    @StateObject private var systemStatusProvider = SystemStatusProvider()
    @StateObject private var foregroundAppProvider = ForegroundAppProvider()
    @State private var currentSnapshot: PlaybackSnapshot = .idle
    @State private var currentLyricText: String?
    @State private var nextLyricText: String?
    @State private var currentLyricStartTimeMS: TimeInterval?
    @State private var nextLyricStartTimeMS: TimeInterval?
    @State private var compactLyricKey = 0
    @State private var compactLyricLoadingDotCount = 1
    @State private var compactLyricLoadingTask: Task<Void, Never>?
    @State private var foregroundPrompt: ForegroundAppPrompt?
    @State private var foregroundPromptTask: Task<Void, Never>?
    @State private var isTutorialHintVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.collapseFromOutsideInteraction()
                    }

                animatedIslandShell
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear {
            viewModel.setReduceMotionEnabled(accessibilityReduceMotion)
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
            updateTutorialHintVisibility()
        }
        .onChange(of: accessibilityReduceMotion) { _, enabled in
            viewModel.setReduceMotionEnabled(enabled)
        }
        .onReceive(viewModel.playbackProvider.$snapshot) { snapshot in
            currentSnapshot = snapshot
            viewModel.lyricsProvider.update(for: snapshot, trackID: nil)
            updateCompactLyric(index: viewModel.lyricsProvider.currentLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onReceive(viewModel.lyricsProvider.$currentLineIndex) { index in
            updateCompactLyric(index: index)
            updateCompactCapsuleMode()
        }
        .onReceive(viewModel.lyricsProvider.$lyrics) { _ in
            updateCompactLyric(index: viewModel.lyricsProvider.currentLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onReceive(viewModel.lyricsProvider.$statusText) { _ in
            updateCompactLyric(index: viewModel.lyricsProvider.currentLineIndex)
            updateCompactCapsuleMode()
        }
        .onReceive(viewModel.lyricsProvider.$isLoading) { isLoading in
            if !isLoading {
                compactLyricLoadingDotCount = 1
            }
            updateCompactLyric(index: viewModel.lyricsProvider.currentLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onChange(of: settings.compactLeftSideIcon) { oldValue, newValue in
            handleSystemSideSelectionChange(oldValue: oldValue, newValue: newValue)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.compactRightSideIcon) { oldValue, newValue in
            handleSystemSideSelectionChange(oldValue: oldValue, newValue: newValue)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.showCustomCompactIcons) { _, _ in
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.showMusicLyrics) { _, _ in
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.showMusicTrackName) { _, _ in
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.foregroundAppLinkEnabled) { _, enabled in
            if !enabled {
                clearForegroundPrompt()
            }
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.foregroundHoldDuration) { _, _ in
            scheduleForegroundPromptClearIfNeeded()
        }
        .onChange(of: settings.tutorialHintPolicy) { _, _ in
            updateTutorialHintVisibility()
        }
        .onChange(of: viewModel.presentationPhase) { _, _ in
            refreshRuntimeProviders()
            updateTutorialHintVisibility()
        }
        .onReceive(foregroundAppProvider.$prompt) { prompt in
            handleForegroundPrompt(prompt)
        }
        .onChange(of: settings.allowAppleMusicAccess) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
        }
        .onChange(of: settings.allowSpotifyAccess) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
        }
        .onChange(of: settings.showWeatherModule) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showDeviceInfoModule) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showMediaModule) { _, _ in
            refreshRuntimeProviders()
        }
        .onDisappear {
            viewModel.playbackProvider.stop()
            weatherProvider.stop()
            deviceInfoProvider.stop()
            batteryProvider.stop()
            systemStatusProvider.stop()
            foregroundAppProvider.stop()
            compactLyricLoadingTask?.cancel()
            compactLyricLoadingTask = nil
            foregroundPromptTask?.cancel()
            foregroundPromptTask = nil
        }
    }

    private var animatedIslandShell: some View {
        let timing = IslandDesignTokens.shellOpenTiming(setting: settings.openSpeed)
        let bounce = settings.bounceLevel
        let expandedSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: viewModel.selectedTopTab
        )
        let undershootWidthProgress = IslandShellLayout.progressForExpandedScale(
            compact: viewModel.compactCapsuleSize.width,
            expanded: expandedSize.width,
            scale: bounce.undershootScale
        )
        let undershootHeightProgress = IslandShellLayout.progressForExpandedScale(
            compact: viewModel.compactCapsuleSize.height,
            expanded: expandedSize.height,
            scale: bounce.undershootScale
        )
        let widthPassThroughVelocity = (
            bounce.widthOvershoot - 1
        ) / timing.overshoot * 0.62
        let heightPassThroughVelocity = (
            bounce.heightOvershoot - 1
        ) / timing.overshoot * 0.62
        let widthSettleVelocity = max(
            0,
            (1 - undershootWidthProgress)
                / timing.settle
        ) * 0.46
        let heightSettleVelocity = max(
            0,
            (1 - undershootHeightProgress)
                / timing.settle
        ) * 0.46

        return KeyframeAnimator(
            initialValue: viewModel.openingKeyframeStartState,
            trigger: viewModel.openingAnimationTrigger
        ) { keyframeState in
            islandShell(
                animationState: viewModel.usesOpeningKeyframes
                    ? keyframeState
                    : viewModel.shellAnimationState
            )
        } keyframes: { _ in
            KeyframeTrack(\.widthProgress) {
                CubicKeyframe(
                    1,
                    duration: timing.toExpanded,
                    startVelocity: 0,
                    endVelocity: widthPassThroughVelocity
                )
                CubicKeyframe(
                    bounce.widthOvershoot,
                    duration: timing.overshoot,
                    startVelocity: widthPassThroughVelocity,
                    endVelocity: 0
                )
                CubicKeyframe(
                    undershootWidthProgress,
                    duration: timing.undershoot,
                    startVelocity: 0,
                    endVelocity: widthSettleVelocity
                )
                CubicKeyframe(
                    1,
                    duration: timing.settle,
                    startVelocity: widthSettleVelocity,
                    endVelocity: 0
                )
            }
            KeyframeTrack(\.heightProgress) {
                CubicKeyframe(
                    1,
                    duration: timing.toExpanded,
                    startVelocity: 0,
                    endVelocity: heightPassThroughVelocity
                )
                CubicKeyframe(
                    bounce.heightOvershoot,
                    duration: timing.overshoot,
                    startVelocity: heightPassThroughVelocity,
                    endVelocity: 0
                )
                CubicKeyframe(
                    undershootHeightProgress,
                    duration: timing.undershoot,
                    startVelocity: 0,
                    endVelocity: heightSettleVelocity
                )
                CubicKeyframe(
                    1,
                    duration: timing.settle,
                    startVelocity: heightSettleVelocity,
                    endVelocity: 0
                )
            }
            KeyframeTrack(\.morphProgress) {
                CubicKeyframe(
                    1,
                    duration: timing.toExpanded
                )
                LinearKeyframe(
                    1,
                    duration: timing.total - timing.toExpanded
                )
            }
        }
    }

    private func islandShell(animationState: IslandShellAnimationState) -> some View {
        let size = shellSize(animationState: animationState)
        let canvasSize = shellCanvasSize
        let overflowHeight = viewModel.expandedContentOverflowHeight
        let allowsContentOverflow = overflowHeight > 0.5
        let metrics = shellShapeMetrics(animationState: animationState, shellSize: size)
        let shellFillColor = settings.islandBackgroundStyle == .solid
            ? IslandDesignTokens.panelColor
            : Color.black.opacity(0.78)
        let shape = DynamicIslandShape(
            shoulderWidth: metrics.shoulderWidth,
            shoulderDepth: metrics.shoulderDepth,
            sideInset: metrics.sideInset,
            bottomCornerRadius: metrics.bottomCornerRadius,
            visibleSize: size
        )

        return ZStack(alignment: .top) {
            compactHoverLeakGuard

            ZStack(alignment: .top) {
                CompactCapsuleContentView(
                    mode: viewModel.compactContentMode,
                    geometry: viewModel.notchGeometry,
                    snapshot: currentSnapshot,
                    currentLyricText: currentLyricText,
                    nextLyricText: nextLyricText,
                    currentLyricStartTimeMS: currentLyricStartTimeMS,
                    nextLyricStartTimeMS: nextLyricStartTimeMS,
                    showsTrackName: settings.showMusicTrackName,
                    showsLyrics: settings.showMusicLyrics,
                    leftSideIcon: settings.showCustomCompactIcons ? settings.compactLeftSideIcon : .none,
                    rightSideIcon: settings.showCustomCompactIcons ? settings.compactRightSideIcon : .none,
                    sideStatusContext: sideStatusContext,
                    foregroundPromptDisplayMode: settings.foregroundAppPromptDisplayMode,
                    foregroundPrompt: foregroundPrompt
                )
                .frame(
                    width: viewModel.compactCapsuleSize.width,
                    height: viewModel.compactCapsuleSize.height
                )
                .allowsHitTesting(false)
                .opacity(compactContentOpacity)

                if viewModel.shouldMountExpandedContent {
                    ExpandedIslandView(
                        viewModel: viewModel,
                        isContentReady: viewModel.shouldMountExpandedContent,
                        contentRevealProgress: viewModel.contentRevealProgress,
                        secondaryContentRevealProgress: viewModel.secondaryContentRevealProgress,
                        settings: settings,
                        weatherProvider: weatherProvider,
                        deviceInfoProvider: deviceInfoProvider,
                        onOpenSettings: onOpenSettings,
                        onOpenTodoSettings: onOpenTodoSettings,
                        onOpenFeedback: onOpenFeedback
                    )
                    .environmentObject(settings)
                    .opacity(expandedContentOpacity)
                    .allowsHitTesting(viewModel.presentationPhase == .expanded)
                }
            }
            .frame(
                width: canvasSize.width,
                height: canvasSize.height + overflowHeight,
                alignment: .top
            )
            .background {
                shape.fill(shellFillColor)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(shellFillColor)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .islandShellBounds(shape, clipsToShape: !allowsContentOverflow)
            .shadow(
                color: viewModel.presentationPhase == .collapsingShell
                    ? .clear
                    : .black.opacity(0.18),
                radius: viewModel.presentationPhase == .collapsingShell ? 0 : 8,
                y: viewModel.presentationPhase == .collapsingShell ? 0 : 3
            )
            .contextMenu {
                islandContextMenu
            }
            .offset(y: compactHoverCenteringOffset)
            .onTapGesture {
                guard settings.expansionMode == .click,
                      viewModel.presentationPhase == .collapsed
                else { return }
                viewModel.toggleExpandedByClick()
            }

            tutorialHintOverlay(canvasSize: canvasSize)
            externalPinButtonOverlay(canvasSize: canvasSize)
        }
        .frame(
            width: canvasSize.width + 40,
            height: canvasSize.height
                + IslandDesignTokens.applicationsWindowVerticalPadding
                + overflowHeight,
            alignment: .top
        )
    }

    @ViewBuilder
    private func externalPinButtonOverlay(canvasSize: CGSize) -> some View {
        if settings.showPinButton && viewModel.presentationPhase != .collapsed {
            PinButton(isPinned: viewModel.isPinned) {
                viewModel.togglePin()
            }
            .opacity(viewModel.secondaryContentRevealProgress)
            .position(
                x: 20 + canvasSize.width - IslandDesignTokens.externalPinButtonTrailingOverlap,
                y: canvasSize.height - IslandDesignTokens.externalPinButtonBottomOverlap
            )
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .zIndex(45)
        }
    }

    @ViewBuilder
    private func tutorialHintOverlay(canvasSize: CGSize) -> some View {
        if isTutorialHintVisible {
            IslandTutorialHintView(showsPinHint: settings.showPinButton)
                .frame(width: min(max(280, canvasSize.width - 80), 560))
                .opacity(viewModel.secondaryContentRevealProgress)
                .offset(y: canvasSize.height + 7)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(30)
        }
    }

    private var sideStatusContext: SideStatusContext {
        SideStatusContext(
            playback: currentSnapshot,
            weather: weatherProvider.snapshot,
            deviceInfo: deviceInfoProvider.snapshot,
            battery: batteryProvider.snapshot,
            isMuted: systemStatusProvider.snapshot.isMuted
        )
    }

    private func refreshRuntimeProviders() {
        let compactIcons = settings.showCustomCompactIcons
            ? [settings.compactLeftSideIcon, settings.compactRightSideIcon]
            : []
        let isExpanded = viewModel.presentationPhase != .collapsed

        let needsWeather = settings.showWeatherModule && isExpanded
            || compactIcons.contains(where: Self.usesWeatherData)
        if needsWeather {
            weatherProvider.start()
        } else {
            weatherProvider.stop()
        }

        let needsDeviceInfo = settings.showDeviceInfoModule && isExpanded
            || compactIcons.contains(where: Self.usesDeviceInfo)
        if needsDeviceInfo {
            deviceInfoProvider.start()
        } else {
            deviceInfoProvider.stop()
        }

        if compactIcons.contains(.battery) {
            batteryProvider.start()
        } else {
            batteryProvider.stop()
        }

        if compactIcons.contains(.mute) {
            systemStatusProvider.start()
        } else {
            systemStatusProvider.stop()
        }

        if settings.foregroundAppLinkEnabled {
            foregroundAppProvider.start()
        } else {
            foregroundAppProvider.stop()
        }

        let needsPlayback = settings.showMediaModule && isExpanded
            || settings.showMusicLyrics
            || settings.showMusicTrackName
            || compactIcons.contains(.music)
        if needsPlayback {
            viewModel.playbackProvider.start()
        } else {
            viewModel.playbackProvider.stop()
        }
    }

    private static func usesWeatherData(_ icon: SettingsHomeSideIcon) -> Bool {
        switch icon {
        case .weather, .wind, .temperatureRange, .humidity:
            true
        default:
            false
        }
    }

    private static func usesDeviceInfo(_ icon: SettingsHomeSideIcon) -> Bool {
        switch icon {
        case .network, .cpu, .memory, .disk:
            true
        default:
            false
        }
    }

    private func handleSystemSideSelectionChange(
        oldValue: SettingsHomeSideIcon,
        newValue: SettingsHomeSideIcon
    ) {
        if newValue == .mute {
            systemStatusProvider.setMuted(true)
        }
        if oldValue == .mute, newValue != .mute {
            let stillSelected = settings.compactLeftSideIcon == .mute
                || settings.compactRightSideIcon == .mute
            if !stillSelected {
                systemStatusProvider.setMuted(false)
            }
        }
    }

    @ViewBuilder
    private var islandContextMenu: some View {
        if viewModel.presentationPhase == .expanded {
            Button {
                viewModel.cancelCollapse()
                onOpenSettings()
            } label: {
                Label("打开设置", systemImage: "macwindow")
            }

            Button {
                viewModel.togglePin()
            } label: {
                Label(
                    viewModel.isPinned ? "取消固定展开" : "固定展开",
                    systemImage: viewModel.isPinned ? "lock.open" : "lock"
                )
            }

            Menu {
                ForEach(IslandLanguage.allCases) { language in
                    Button {
                        settings.language = language
                    } label: {
                        if settings.language == language {
                            Label(language.title, systemImage: "checkmark")
                        } else {
                            Text(language.title)
                        }
                    }
                }
            } label: {
                Label("选择语言", systemImage: "character")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出 NookFlow", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    private func shellSize(animationState: IslandShellAnimationState) -> CGSize {
        IslandShellLayout.shellSize(
            settings: settings,
            selectedTopTab: viewModel.selectedTopTab,
            compactSize: viewModel.compactCapsuleSize,
            compactScaleX: viewModel.compactCapsuleScaleX,
            compactScaleY: viewModel.compactCapsuleScaleY,
            animationState: animationState,
            isCompact: viewModel.presentationPhase == .collapsed
        )
    }

    private var shellCanvasSize: CGSize {
        guard viewModel.presentationPhase != .collapsed else {
            let size = shellSize(animationState: viewModel.shellAnimationState)
            guard viewModel.hoverPhase != .idle else { return size }

            return CGSize(
                width: max(
                    size.width,
                    viewModel.compactCapsuleSize.width * IslandDesignTokens.compactHoverWidthScale
                ),
                height: max(
                    size.height,
                    viewModel.compactCapsuleSize.height * IslandDesignTokens.compactHoverHeightScale
                )
            )
        }

        if viewModel.presentationPhase == .expandingShell
            || viewModel.presentationPhase == .revealingContent {
            return IslandShellLayout.openingEnvelopeSize(
                settings: settings,
                selectedTopTab: viewModel.selectedTopTab
            )
        }

        return viewModel.tabTransitionCanvasSize
            ?? IslandShellLayout.contentSize(
                settings: settings,
                selectedTopTab: viewModel.selectedTopTab
            )
    }

    @ViewBuilder
    private var compactHoverLeakGuard: some View {
        if compactHoverCenteringOffset > 0 {
            Rectangle()
                .fill(IslandDesignTokens.panelColor)
                .frame(height: compactHoverCenteringOffset + 1)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
    }

    private var compactHoverCenteringOffset: CGFloat {
        0
    }

    private func shellShapeMetrics(
        animationState: IslandShellAnimationState,
        shellSize: CGSize
    ) -> (
        shoulderWidth: CGFloat,
        shoulderDepth: CGFloat,
        sideInset: CGFloat,
        bottomCornerRadius: CGFloat
    ) {
        IslandShellLayout.shellShapeMetrics(
            shellSize: shellSize,
            compactSize: viewModel.compactCapsuleSize,
            morphProgress: animationState.morphProgress
        )
    }

    private var compactContentOpacity: Double {
        viewModel.compactContentRevealProgress
    }

    private var expandedContentOpacity: Double {
        viewModel.presentationPhase == .collapsed ? 0 : 1
    }

    private func updateCompactLyric(index: Int?) {
        let lyrics = viewModel.lyricsProvider.lyrics
        guard currentSnapshot.isLive else {
            clearCompactLyric()
            return
        }

        guard !lyrics.isEmpty,
              let index = resolvedCompactLyricIndex(requestedIndex: index, lyrics: lyrics) else {
            updateCompactLyricStatusText()
            return
        }
        let line = lyrics[index]
        let words = line.words.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = words.isEmpty ? (line.translation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : words

        let nextStart = lyrics.indices.contains(index + 1) ? lyrics[index + 1].startTimeMS : nil
        let nextText: String?
        if lyrics.indices.contains(index + 1) {
            let nextLine = lyrics[index + 1]
            let nextWords = nextLine.words.trimmingCharacters(in: .whitespacesAndNewlines)
            nextText = nextWords.isEmpty
                ? nextLine.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nextWords
        } else {
            nextText = nil
        }

        if text != currentLyricText
            || nextText != nextLyricText
            || line.startTimeMS != currentLyricStartTimeMS
            || nextStart != nextLyricStartTimeMS {
            currentLyricText = text
            nextLyricText = nextText
            currentLyricStartTimeMS = line.startTimeMS
            nextLyricStartTimeMS = nextStart
            compactLyricKey += 1
        }
    }

    private func resolvedCompactLyricIndex(
        requestedIndex: Int?,
        lyrics: [LyricLine]
    ) -> Int? {
        if let requestedIndex, lyrics.indices.contains(requestedIndex) {
            return requestedIndex
        }

        let displayElapsedMS = max(0, currentSnapshot.elapsed + 0.5) * 1000
        return lyrics.lastIndex { line in
            line.startTimeMS <= displayElapsedMS
        }
    }

    private func updateCompactLyricStatusText() {
        let statusText = viewModel.lyricsProvider.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String?
        if viewModel.lyricsProvider.isLoading {
            text = compactLyricLoadingText
        } else {
            text = statusText == "未找到歌词" ? statusText : nil
        }

        if text != currentLyricText
            || nextLyricText != nil
            || currentLyricStartTimeMS != nil
            || nextLyricStartTimeMS != nil {
            currentLyricText = text
            nextLyricText = nil
            currentLyricStartTimeMS = nil
            nextLyricStartTimeMS = nil
            compactLyricKey += 1
        }
    }

    private func updateCompactLyricLoadingStatusIfNeeded() {
        guard currentSnapshot.isLive,
              viewModel.lyricsProvider.isLoading,
              viewModel.lyricsProvider.lyrics.isEmpty else {
            compactLyricLoadingTask?.cancel()
            compactLyricLoadingTask = nil
            return
        }

        compactLyricLoadingDotCount = compactLyricLoadingDotCount >= 3
            ? 1
            : compactLyricLoadingDotCount + 1
        updateCompactLyricStatusText()
        updateCompactCapsuleMode()
    }

    private func configureCompactLyricLoadingTask() {
        let shouldRun = currentSnapshot.isLive
            && viewModel.lyricsProvider.isLoading
            && viewModel.lyricsProvider.lyrics.isEmpty

        guard shouldRun else {
            compactLyricLoadingTask?.cancel()
            compactLyricLoadingTask = nil
            return
        }

        guard compactLyricLoadingTask == nil else { return }
        compactLyricLoadingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                updateCompactLyricLoadingStatusIfNeeded()
            }
        }
    }

    private var compactLyricLoadingText: String {
        "正在加载歌词" + String(repeating: "·", count: compactLyricLoadingDotCount)
    }

    private func clearCompactLyric() {
        if currentLyricText != nil
            || nextLyricText != nil
            || currentLyricStartTimeMS != nil
            || nextLyricStartTimeMS != nil {
            currentLyricText = nil
            nextLyricText = nil
            currentLyricStartTimeMS = nil
            nextLyricStartTimeMS = nil
            compactLyricKey += 1
        }
    }

    private func updateCompactCapsuleMode() {
        let presentation = CompactMusicPresentation.resolve(
            showsTrackName: settings.showMusicTrackName,
            showsLyrics: settings.showMusicLyrics,
            track: CompactMusicTrackSnapshot(
                isLive: currentSnapshot.isLive,
                title: currentSnapshot.title,
                artist: currentSnapshot.artist
            ),
            currentLyric: currentLyricText,
            nextLyric: nextLyricText
        )
        let mode: CompactCapsuleContentMode

        if presentation != nil {
            mode = .lyrics
        } else if foregroundPrompt != nil {
            mode = .status
        } else if settings.showCustomCompactIcons
            && (settings.compactLeftSideIcon != .none || settings.compactRightSideIcon != .none) {
            mode = .status
        } else if currentSnapshot.isLive {
            mode = .status
        } else {
            mode = .camera
        }

        viewModel.updateCompactContentMode(mode)
    }

    private func handleForegroundPrompt(_ prompt: ForegroundAppPrompt?) {
        guard settings.foregroundAppLinkEnabled, let prompt else { return }
        foregroundPrompt = prompt
        scheduleForegroundPromptClearIfNeeded()
        updateCompactCapsuleMode()
    }

    private func scheduleForegroundPromptClearIfNeeded() {
        foregroundPromptTask?.cancel()
        guard foregroundPrompt != nil else { return }

        let delay = max(0.3, settings.foregroundHoldDuration)
        foregroundPromptTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            clearForegroundPrompt()
        }
    }

    private func clearForegroundPrompt() {
        foregroundPromptTask?.cancel()
        foregroundPromptTask = nil
        foregroundPrompt = nil
        updateCompactCapsuleMode()
    }

    private func updateTutorialHintVisibility() {
        guard viewModel.presentationPhase == .expanded else {
            setTutorialHintVisible(false)
            return
        }

        switch settings.tutorialHintPolicy {
        case .off:
            setTutorialHintVisible(false)
        case .always:
            setTutorialHintVisible(true)
        case .once:
            if !settings.hasShownTutorialHint || isTutorialHintVisible {
                setTutorialHintVisible(true)
                settings.markTutorialHintShown()
            } else {
                setTutorialHintVisible(false)
            }
        }
    }

    private func setTutorialHintVisible(_ visible: Bool) {
        guard isTutorialHintVisible != visible else { return }

        let animation: Animation = viewModel.reduceMotionEnabled
            ? .easeOut(duration: 0.01)
            : .easeOut(duration: 0.18)
        withAnimation(animation) {
            isTutorialHintVisible = visible
        }
    }
}

private struct IslandShellBoundsModifier<ShellShape: Shape>: ViewModifier {
    let shellShape: ShellShape
    let clipsToShape: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if clipsToShape {
            content
                .clipShape(shellShape)
                .contentShape(shellShape)
        } else {
            content
                .contentShape(Rectangle())
        }
    }
}

private extension View {
    func islandShellBounds<ShellShape: Shape>(
        _ shellShape: ShellShape,
        clipsToShape: Bool
    ) -> some View {
        modifier(IslandShellBoundsModifier(shellShape: shellShape, clipsToShape: clipsToShape))
    }
}

private struct IslandTutorialHintView: View {
    let showsPinHint: Bool

    @State private var tipIndex = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: currentTip.systemName)
                .font(.system(size: 10.5, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 14)

            Text(currentTip.text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .id(currentTip.id)
                .transition(.opacity.combined(with: .move(edge: .top)))

            Text("\(displayedTipIndex + 1)/\(tips.count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.56))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .allowsHitTesting(false)
        .task(id: tips.count) {
            guard tips.count > 1 else { return }
            tipIndex = min(tipIndex, tips.count - 1)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    tipIndex = (tipIndex + 1) % tips.count
                }
            }
        }
    }

    private var currentTip: TutorialHint {
        tips[displayedTipIndex]
    }

    private var displayedTipIndex: Int {
        guard !tips.isEmpty else { return 0 }
        return tipIndex % tips.count
    }

    private var tips: [TutorialHint] {
        var values = [
            TutorialHint(systemName: "rectangle.3.group", text: "顶部标签可以在主页、应用和文件之间切换"),
            TutorialHint(systemName: "tray.and.arrow.down", text: "把文件拖到岛上，可暂存或继续隔空投送"),
            TutorialHint(systemName: "gearshape", text: "右上角齿轮可以打开设置、反馈或退出应用"),
            TutorialHint(systemName: "slider.horizontal.3", text: "设置里可以自定义紧凑状态左右显示的信息"),
            TutorialHint(systemName: "music.note", text: "播放音乐时，可在紧凑状态显示歌曲名或歌词"),
            TutorialHint(systemName: "square.grid.2x2", text: "快捷应用模块适合放常用 App，一点就打开"),
            TutorialHint(systemName: "command", text: "快捷指令模块可以固定常用自动化流程"),
            TutorialHint(systemName: "chart.bar", text: "设备信息模块会显示 CPU、内存、磁盘和存储状态"),
            TutorialHint(systemName: "photo", text: "图片卡片可以放一张你喜欢的常驻图片"),
            TutorialHint(systemName: "calendar", text: "日历模块能快速查看日期、农历和近期安排")
        ]

        if showsPinHint {
            values.insert(
                TutorialHint(systemName: "lock", text: "右下角按钮可以固定展开，再点一次取消固定"),
                at: 2
            )
        }
        return values
    }

    private struct TutorialHint: Identifiable {
        let systemName: String
        let text: String

        var id: String { text }
    }
}
