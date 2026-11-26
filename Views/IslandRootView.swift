import Combine
import SwiftUI

struct IslandRootView: View {

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: IslandSettings
    @ObservedObject private var licenseManager = LicenseManager.shared
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
    @StateObject private var applicationsProvider = ApplicationsProvider()
    @StateObject private var fileProvider = FileDataProvider()
    @StateObject private var moduleDragController = ModuleDragController()
    @StateObject private var reminderProvider = ReminderProvider()
    @State private var visibleHomeModules: Set<IslandPanelModule> = []
    @State private var currentSnapshot: PlaybackSnapshot = .idle
    @State private var currentLyricText: String?
    @State private var nextLyricText: String?
    @State private var currentLyricTiming: EstimatedLyricLine?
    @State private var nextLyricTiming: EstimatedLyricLine?
    @State private var compactSingingLineIndex: Int?
    @State private var compactLyricKey = 0
    @State private var compactLyricLoadingDotCount = 1
    @State private var compactLyricLoadingTask: Task<Void, Never>?
    @State private var foregroundPrompt: ForegroundAppPrompt?
    @State private var foregroundPromptRevealProgress: Double = 0
    @State private var foregroundPromptTask: Task<Void, Never>?
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
        }
        .onChange(of: accessibilityReduceMotion) { _, enabled in
            viewModel.setReduceMotionEnabled(enabled)
        }
        .onChange(of: licenseManager.state) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactLyric(index: viewModel.lyricsProvider.capsuleLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onReceive(viewModel.playbackProvider.$snapshot) { snapshot in
            currentSnapshot = snapshot
            viewModel.lyricsProvider.update(for: snapshot, trackID: nil)
            updateCompactLyric(index: viewModel.lyricsProvider.capsuleLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onReceive(viewModel.lyricsProvider.$capsuleLineIndex) { index in
            updateCompactLyric(index: index)
            updateCompactCapsuleMode()
        }
        .onReceive(viewModel.lyricsProvider.$lyrics) { _ in
            updateCompactLyric(index: viewModel.lyricsProvider.capsuleLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onReceive(viewModel.lyricsProvider.$estimatedTimeline) { timeline in
            updateCompactLyric(index: viewModel.lyricsProvider.capsuleLineIndex, timeline: timeline)
        }
        .onReceive(viewModel.lyricsProvider.$displayState) { state in
            if !state.isLoading {
                compactLyricLoadingDotCount = 1
            }
            updateCompactLyric(index: viewModel.lyricsProvider.capsuleLineIndex)
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onChange(of: settings.compactLeftSideIcon) { oldValue, newValue in
            handleSystemSideSelectionChange(oldValue: oldValue, newValue: newValue)
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.compactRightSideIcon) { oldValue, newValue in
            handleSystemSideSelectionChange(oldValue: oldValue, newValue: newValue)
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.showCustomCompactIcons) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
        }
        .onChange(of: settings.showMusicLyrics) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
            configureCompactLyricLoadingTask()
        }
        .onChange(of: settings.lyricsPresentationMode) { _, _ in
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
        .onChange(of: viewModel.presentationPhase) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: viewModel.isExpandedRuntimeActive) { _, _ in
            refreshRuntimeProviders()
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
        .onChange(of: settings.allowQQMusicAccess) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
        }
        .onChange(of: settings.allowNetEaseMusicAccess) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
        }
        .onChange(of: visibleHomeModules) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showWeatherModule) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showDeviceInfoModule) { _, _ in
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showMediaModule) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
        }
        .onChange(of: settings.showDesktopLyrics) { _, _ in
            viewModel.playbackProvider.updateAccessConfiguration(from: settings)
            refreshRuntimeProviders()
            updateCompactCapsuleMode()
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
        ZStack(alignment: .top) {
            animatedFileDropChooserSurface
            .opacity(viewModel.isFileDropChooserVisible ? 1 : 0)
            .allowsHitTesting(viewModel.isFileDropChooserVisible)

            standardAnimatedIslandShell(
                rendersShellChrome: !viewModel.isFileDropChooserVisible
            )
            .opacity(
                viewModel.isFileDropChooserVisible
                    ? viewModel.fileDropSourceShellOpacity
                    : 1
            )
            .allowsHitTesting(!viewModel.isFileDropChooserVisible)
        }
    }

    private var animatedFileDropChooserSurface: some View {
        let canvasSize = viewModel.fileDropShellCanvasSize
        let fillColor = settings.islandBackgroundStyle == .solid
            ? IslandDesignTokens.panelColor
            : Color.black.opacity(0.78)

        return ZStack(alignment: .top) {
            IslandOpeningKeyframeAnimator(
                initialValue: .collapsed,
                trigger: viewModel.fileDropOpeningAnimationTrigger,
                timing: IslandDesignTokens.fileDropShellOpenTiming(
                    setting: settings.openSpeed
                ),
                bounce: settings.bounceLevel
            ) { keyframeState in
                let shellSize = viewModel.usesFileDropOpeningKeyframes
                    ? fileDropShellSize(animationState: keyframeState)
                    : viewModel.fileDropShellSize
                let morphProgress = viewModel.usesFileDropOpeningKeyframes
                    ? fileDropShellMorphProgress(animationState: keyframeState)
                    : viewModel.fileDropShellMorphProgress

                FileDropShellSurface(
                    compactCapsuleSize: viewModel.compactCapsuleSize,
                    shellSize: shellSize,
                    canvasSize: canvasSize,
                    shellMorphProgress: morphProgress,
                    fillColor: fillColor
                )
            }

            FileDropChooserContentSurface(
                hoverTarget: viewModel.fileDropHoverTarget,
                previewName: viewModel.fileDropPreviewName,
                canvasSize: canvasSize,
                contentOpacity: viewModel.fileDropContentOpacity,
                visibleItemCount: viewModel.fileDropVisibleItemCount,
                reduceMotion: viewModel.reduceMotionEnabled,
                selectedTopTab: viewModel.selectedTopTab,
                isPinned: viewModel.isPinned,
                showsPinButton: settings.showPinButton,
                onSelectTab: viewModel.selectTopTab,
                onTogglePin: viewModel.togglePin,
                onOpenSettings: onOpenSettings
            )
        }
        .frame(
            width: IslandFileDropLayout.windowSize(for: canvasSize).width,
            height: IslandFileDropLayout.windowSize(for: canvasSize).height,
            alignment: .top
        )
    }

    private func standardAnimatedIslandShell(rendersShellChrome: Bool) -> some View {
        IslandOpeningKeyframeAnimator(
            initialValue: viewModel.openingKeyframeStartState,
            trigger: viewModel.openingAnimationTrigger,
            timing: IslandDesignTokens.shellOpenTiming(setting: settings.openSpeed),
            bounce: settings.bounceLevel
        ) { keyframeState in
            islandShell(
                animationState: viewModel.usesOpeningKeyframes
                    ? keyframeState
                    : viewModel.shellAnimationState,
                rendersShellChrome: rendersShellChrome
            )
        }
    }

    private func fileDropShellSize(animationState: IslandShellAnimationState) -> CGSize {
        let source = viewModel.fileDropOpeningSourceSize
        let target = IslandFileDropLayout.size
        return CGSize(
            width: source.width + (target.width - source.width) * animationState.widthProgress,
            height: source.height + (target.height - source.height) * animationState.heightProgress
        )
    }

    private func fileDropShellMorphProgress(
        animationState: IslandShellAnimationState
    ) -> CGFloat {
        let source = viewModel.fileDropOpeningSourceMorphProgress
        return source + (1 - source) * animationState.morphProgress
    }

    private func islandShell(
        animationState: IslandShellAnimationState,
        rendersShellChrome: Bool
    ) -> some View {
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
            if rendersShellChrome {
                compactHoverLeakGuard
            }

            ZStack(alignment: .top) {
                CompactCapsuleContentView(
                    mode: viewModel.compactContentMode,
                    geometry: viewModel.notchGeometry,
                    snapshot: currentSnapshot,
                    currentLyricText: currentLyricText,
                    nextLyricText: nextLyricText,
                    currentLyricTiming: currentLyricTiming,
                    showsTrackName: false,
                    showsLyrics: isMusicProActive && settings.showMusicLyrics,
                    leftSideIcon: resolvedCompactSideIcon(settings.compactLeftSideIcon),
                    rightSideIcon: resolvedCompactSideIcon(settings.compactRightSideIcon),
                    sideStatusContext: sideStatusContext,
                    foregroundPromptDisplayMode: settings.foregroundAppPromptDisplayMode,
                    foregroundPrompt: foregroundPrompt,
                    lyricFontSize: CGFloat(settings.capsuleLyricsFontSize),
                    nextLyricTiming: nextLyricTiming,
                    activeLyricSourceIndex: compactSingingLineIndex,
                    foregroundPromptRevealProgress: foregroundPromptRevealProgress,
                    isContentVisible: viewModel.presentationPhase == .collapsed
                        && compactContentOpacity > 0.01
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
                        runtimeIsActive: viewModel.enablesLiveServices && viewModel.isExpandedRuntimeActive,
                        contentRevealProgress: viewModel.contentRevealProgress,
                        secondaryContentRevealProgress: viewModel.secondaryContentRevealProgress,
                        settings: settings,
                        weatherProvider: weatherProvider,
                        deviceInfoProvider: deviceInfoProvider,
                        applicationsProvider: applicationsProvider,
                        fileProvider: fileProvider,
                        dragController: moduleDragController,
                        reminderProvider: reminderProvider,
                        onOpenSettings: onOpenSettings,
                        onOpenTodoSettings: onOpenTodoSettings,
                        onOpenFeedback: onOpenFeedback,
                        onVisibleModulesChanged: {
                            visibleHomeModules = $0.intersection([.weather, .deviceInfo])
                        }
                    )
                    .environmentObject(settings)
                    .opacity(expandedContentOpacity)
                    .allowsHitTesting(
                        viewModel.presentationPhase == .loadingContent
                            || viewModel.presentationPhase == .expanded
                    )
                }
            }
            .frame(
                width: canvasSize.width,
                height: canvasSize.height + overflowHeight,
                alignment: .top
            )
            .background {
                shape.fill(rendersShellChrome ? shellFillColor : Color.clear)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(rendersShellChrome ? shellFillColor : Color.clear)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .islandShellBounds(shape, clipsToShape: !allowsContentOverflow)
            .shadow(
                color: !rendersShellChrome || viewModel.presentationPhase == .collapsingShell
                    ? .clear
                    : .black.opacity(0.18),
                radius: !rendersShellChrome || viewModel.presentationPhase == .collapsingShell
                    ? 0
                    : 8,
                y: !rendersShellChrome || viewModel.presentationPhase == .collapsingShell
                    ? 0
                    : 3
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
        }
        .frame(
            width: canvasSize.width + 40,
            height: canvasSize.height
                + IslandDesignTokens.applicationsWindowVerticalPadding
                + overflowHeight,
            alignment: .top
        )
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
        guard viewModel.enablesLiveServices else { return }
        let compactIcons = settings.showCustomCompactIcons
            ? [
                resolvedCompactSideIcon(settings.compactLeftSideIcon),
                resolvedCompactSideIcon(settings.compactRightSideIcon)
            ]
            : []
        let isExpanded = viewModel.isExpandedRuntimeActive

        let needsWeatherForCapsule = compactIcons.contains(where: Self.usesWeatherData)
        let needsWeather = needsWeatherForCapsule
            || (settings.showWeatherModule && isExpanded && visibleHomeModules.contains(.weather))
        if needsWeather {
            weatherProvider.start(reuseRecentSnapshot: !needsWeatherForCapsule)
        } else {
            weatherProvider.stop()
        }

        let needsDeviceInfo = compactIcons.contains(where: Self.usesDeviceInfo)
            || (settings.showDeviceInfoModule && isExpanded && visibleHomeModules.contains(.deviceInfo))
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

        let needsPlayback = isMusicProActive
            && (settings.showMediaModule && isExpanded
                || settings.showMusicLyrics
                || settings.showDesktopLyrics
                || compactIcons.contains(.music))
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
                    viewModel.compactCapsuleSize.width
                        * IslandDesignTokens.compactHoverWidthScale
                ),
                height: max(
                    size.height,
                    viewModel.compactCapsuleSize.height * IslandDesignTokens.compactHoverHeightScale
                )
            )
        }

        if viewModel.presentationPhase == .expandingShell
            || viewModel.presentationPhase == .loadingContent {
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

    private func updateCompactLyric(index: Int?, timeline: [EstimatedLyricLine]? = nil) {
        guard isMusicProActive else {
            clearCompactLyric()
            return
        }
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
        compactSingingLineIndex = index
        guard let pair = CompactLyricPair.resolve(at: index, in: lyrics) else {
            updateCompactLyricStatusText()
            return
        }
        let timings = timeline ?? viewModel.lyricsProvider.estimatedTimeline
        let text = CompactLyricPair.displayText(for: lyrics[pair.leftIndex])
        let nextText = pair.rightIndex.map { CompactLyricPair.displayText(for: lyrics[$0]) }
        let timing = timings.first { $0.sourceIndex == pair.leftIndex }
        let rightTiming = pair.rightIndex.flatMap { index in timings.first { $0.sourceIndex == index } }
        if text != currentLyricText || nextText != nextLyricText
            || timing != currentLyricTiming || rightTiming != nextLyricTiming {
            currentLyricText = text
            nextLyricText = nextText
            currentLyricTiming = timing
            nextLyricTiming = rightTiming
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

        let displayElapsedMS = max(0, currentSnapshot.elapsed) * 1000
        return lyrics.lastIndex { line in
            line.startTimeMS <= displayElapsedMS
        }
    }

    private func updateCompactLyricStatusText() {
        let text: String?
        if viewModel.lyricsProvider.displayState.isLoading {
            text = compactLyricLoadingText
        } else {
            text = viewModel.lyricsProvider.displayState.placeholderText
        }

        if text != currentLyricText
            || nextLyricText != nil
            || currentLyricTiming != nil {
            currentLyricText = text
            nextLyricText = nil
            currentLyricTiming = nil
            nextLyricTiming = nil
            compactSingingLineIndex = nil
            compactLyricKey += 1
        }
    }

    private func updateCompactLyricLoadingStatusIfNeeded() {
        guard isMusicProActive,
              settings.showMusicLyrics,
              currentSnapshot.isLive,
              viewModel.lyricsProvider.displayState.isLoading,
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
        let shouldRun = isMusicProActive
            && settings.showMusicLyrics
            && currentSnapshot.isLive
            && viewModel.lyricsProvider.displayState.isLoading
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
            || currentLyricTiming != nil {
            currentLyricText = nil
            nextLyricText = nil
            currentLyricTiming = nil
            nextLyricTiming = nil
            compactSingingLineIndex = nil
            compactLyricKey += 1
        }
    }

    private func updateCompactCapsuleMode(animatedForForegroundPrompt: Bool = false) {
        let presentation = CompactMusicPresentation.resolve(
            showsTrackName: false,
            showsLyrics: isMusicProActive && settings.showMusicLyrics,
            track: CompactMusicTrackSnapshot(
                isLive: currentSnapshot.isLive,
                title: currentSnapshot.title,
                artist: currentSnapshot.artist
            ),
            currentLyric: currentLyricText,
            nextLyric: nextLyricText
        )
        let mode: CompactCapsuleContentMode

        if isMusicProActive,
           settings.showDesktopLyrics,
           settings.lyricsPresentationMode == .menuBar {
            mode = .camera
        } else if presentation != nil {
            mode = .lyrics
        } else if foregroundPrompt != nil {
            mode = .status
        } else if settings.showCustomCompactIcons
            && (resolvedCompactSideIcon(settings.compactLeftSideIcon) != .none
                || resolvedCompactSideIcon(settings.compactRightSideIcon) != .none) {
            mode = .status
        } else {
            mode = .camera
        }

        if animatedForForegroundPrompt {
            withAnimation(foregroundPromptShellAnimation(isOpening: foregroundPrompt != nil)) {
                viewModel.updateCompactContentMode(mode)
            }
        } else {
            viewModel.updateCompactContentMode(mode)
        }
    }

    private var isMusicProActive: Bool {
        licenseManager.isProUnlocked
    }

    private func resolvedCompactSideIcon(_ icon: SettingsHomeSideIcon) -> SettingsHomeSideIcon {
        guard settings.showCustomCompactIcons else { return .none }
        if icon == .music, !isMusicProActive {
            return .none
        }
        return icon
    }

    private func handleForegroundPrompt(_ prompt: ForegroundAppPrompt?) {
        guard settings.foregroundAppLinkEnabled, let prompt else { return }
        let isAlreadyPresented = foregroundPrompt != nil
        foregroundPromptTask?.cancel()
        foregroundPrompt = prompt
        if isAlreadyPresented {
            if foregroundPromptRevealProgress < 1 {
                withAnimation(foregroundPromptContentRevealAnimation) {
                    foregroundPromptRevealProgress = 1
                }
            }
            scheduleForegroundPromptClearIfNeeded()
        } else {
            foregroundPromptRevealProgress = 0
            updateCompactCapsuleMode(animatedForForegroundPrompt: true)
            scheduleForegroundPromptClearIfNeeded(revealContent: true)
        }
    }

    private func scheduleForegroundPromptClearIfNeeded(revealContent: Bool = false) {
        foregroundPromptTask?.cancel()
        guard foregroundPrompt != nil else { return }

        let delay = min(max(settings.foregroundHoldDuration, 0.5), 2.0)
        foregroundPromptTask = Task { @MainActor in
            let revealDelay = revealContent && !accessibilityReduceMotion
                ? IslandDesignTokens.foregroundPromptContentRevealDelay
                : 0
            if revealDelay > 0 {
                await sleepForForegroundPrompt(seconds: revealDelay)
                guard !Task.isCancelled else { return }
            }

            if revealContent {
                withAnimation(foregroundPromptContentRevealAnimation) {
                    foregroundPromptRevealProgress = 1
                }
            }

            await sleepForForegroundPrompt(seconds: max(0, delay - revealDelay))
            guard !Task.isCancelled else { return }
            await dismissForegroundPromptContent()
            guard !Task.isCancelled else { return }
            foregroundPromptTask = nil
        }
    }

    private func clearForegroundPrompt() {
        foregroundPromptTask?.cancel()
        guard foregroundPrompt != nil else {
            foregroundPromptTask = nil
            return
        }

        foregroundPromptTask = Task { @MainActor in
            await dismissForegroundPromptContent()
            guard !Task.isCancelled else { return }
            foregroundPromptTask = nil
        }
    }

    private func dismissForegroundPromptContent() async {
        withAnimation(foregroundPromptContentHideAnimation) {
            foregroundPromptRevealProgress = 0
        }
        await sleepForForegroundPrompt(
            seconds: accessibilityReduceMotion
                ? 0.08
                : IslandDesignTokens.foregroundPromptContentHideDuration
        )
        guard !Task.isCancelled else { return }

        foregroundPrompt = nil
        updateCompactCapsuleMode(animatedForForegroundPrompt: true)
    }

    private func sleepForForegroundPrompt(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func foregroundPromptShellAnimation(isOpening: Bool) -> Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: isOpening ? 0.14 : 0.12)
        }
        return isOpening
            ? IslandDesignTokens.foregroundPromptShellOpenAnimation
            : IslandDesignTokens.foregroundPromptShellCloseAnimation
    }

    private var foregroundPromptContentRevealAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.10)
            : IslandDesignTokens.foregroundPromptContentRevealAnimation
    }

    private var foregroundPromptContentHideAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.08)
            : IslandDesignTokens.foregroundPromptContentHideAnimation
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

/// One shared physical timeline for both the normal island and the file-drop
/// chooser. Keeping the keyframes in one place prevents the two openings from
/// drifting apart as motion settings evolve.
private struct IslandOpeningKeyframeAnimator<Content: View>: View {
    let initialValue: IslandShellAnimationState
    let trigger: Int
    let timing: IslandDesignTokens.ShellOpenTiming
    let bounce: IslandBounceLevel
    let content: (IslandShellAnimationState) -> Content

    init(
        initialValue: IslandShellAnimationState,
        trigger: Int,
        timing: IslandDesignTokens.ShellOpenTiming,
        bounce: IslandBounceLevel,
        @ViewBuilder content: @escaping (IslandShellAnimationState) -> Content
    ) {
        self.initialValue = initialValue
        self.trigger = trigger
        self.timing = timing
        self.bounce = bounce
        self.content = content
    }

    var body: some View {
        let widthLaunchVelocity = max(
            0,
            (1 - initialValue.widthProgress) / timing.widthMotionResponse
        ) * 0.10
        let heightLaunchVelocity = max(
            0,
            (1 - initialValue.heightProgress) / timing.motionResponse
        ) * 0.08

        // A single under-damped spring owns each axis from launch to rest.
        // The damping ratio is derived from the configured peak overshoot, so
        // the shell crosses its final size with continuous velocity and loses
        // energy naturally instead of stopping at stitched keyframe boundaries.
        let widthSpring = Spring(
            response: timing.widthMotionResponse,
            dampingRatio: springDampingRatio(
                forConfiguredOvershoot: bounce.widthOvershoot
            )
        )
        let heightSpring = Spring(
            response: timing.motionResponse,
            dampingRatio: springDampingRatio(
                forConfiguredOvershoot: bounce.heightOvershoot
            )
        )
        let morphSpring = Spring(
            settlingDuration: timing.morphDuration,
            dampingRatio: 1
        )

        KeyframeAnimator(
            initialValue: initialValue,
            trigger: trigger
        ) { keyframeState in
            content(keyframeState)
        } keyframes: { _ in
            KeyframeTrack(\.widthProgress) {
                SpringKeyframe(
                    1,
                    duration: timing.total,
                    spring: widthSpring,
                    startVelocity: widthLaunchVelocity
                )
            }
            KeyframeTrack(\.heightProgress) {
                SpringKeyframe(
                    1,
                    duration: timing.total,
                    spring: heightSpring,
                    startVelocity: heightLaunchVelocity
                )
            }
            KeyframeTrack(\.morphProgress) {
                SpringKeyframe(
                    1,
                    duration: timing.morphDuration,
                    spring: morphSpring
                )
                LinearKeyframe(
                    1,
                    duration: timing.total - timing.morphDuration
                )
            }
        }
    }

    private func springDampingRatio(
        forConfiguredOvershoot overshoot: CGFloat
    ) -> Double {
        let amplitude = Double(max(0, overshoot - 1))
        guard amplitude > 0.0001 else { return 1 }

        // Invert the standard second-order step-response overshoot equation:
        // Mₚ = exp(-ζπ / √(1-ζ²)). This preserves the user-facing bounce
        // levels while letting one physical spring generate the full motion.
        let logarithm = log(min(amplitude, 0.20))
        return -logarithm / sqrt(Double.pi * Double.pi + logarithm * logarithm)
    }
}

/// A purpose-built drag destination. It is intentionally independent of the
/// Files page so external drags do not wake its grid, providers, or layout.
private struct FileDropShellSurface: View {
    let compactCapsuleSize: CGSize
    let shellSize: CGSize
    let canvasSize: CGSize
    let shellMorphProgress: CGFloat
    let fillColor: Color

    var body: some View {
        let metrics = IslandShellLayout.shellShapeMetrics(
            shellSize: shellSize,
            compactSize: compactCapsuleSize,
            morphProgress: shellMorphProgress
        )
        let shellShape = DynamicIslandShape(
            shoulderWidth: metrics.shoulderWidth,
            shoulderDepth: metrics.shoulderDepth,
            sideInset: metrics.sideInset,
            bottomCornerRadius: metrics.bottomCornerRadius,
            visibleSize: shellSize
        )

        let windowCanvasSize = IslandFileDropLayout.windowSize(for: canvasSize)

        shellShape
            .fill(fillColor)
            .frame(width: shellSize.width, height: shellSize.height)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(fillColor)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .frame(
                width: windowCanvasSize.width,
                height: windowCanvasSize.height,
                alignment: .top
            )
    }
}

private struct FileDropChooserContentSurface: View {
    let hoverTarget: IslandFileDropTarget?
    let previewName: String?
    let canvasSize: CGSize
    let contentOpacity: Double
    let visibleItemCount: Int
    let reduceMotion: Bool
    let selectedTopTab: IslandTopTab
    let isPinned: Bool
    let showsPinButton: Bool
    let onSelectTab: (IslandTopTab) -> Void
    let onTogglePin: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let windowCanvasSize = IslandFileDropLayout.windowSize(for: canvasSize)
        let finalShellShape = DynamicIslandShape(
            shoulderWidth: IslandDesignTokens.expandedShoulderWidth,
            shoulderDepth: IslandDesignTokens.expandedShoulderDepth,
            sideInset: IslandDesignTokens.expandedSideInset,
            bottomCornerRadius: IslandDesignTokens.expandedBottomCornerRadius,
            visibleSize: IslandFileDropLayout.size
        )

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(IslandTopTab.allCases) { tab in
                        TopTabButton(
                            tab: tab,
                            isSelected: selectedTopTab == tab,
                            action: { onSelectTab(tab) }
                        )
                    }
                    Spacer(minLength: 0)

                    if showsPinButton {
                        PinButton(isPinned: isPinned, action: onTogglePin)
                    }
                    Button(action: onOpenSettings) {
                        SettingsButtonLabel()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
                    .help("设置")
                }
                .frame(height: IslandDesignTokens.expandedTopBarControlHeight)
                .padding(.leading, IslandFileDropLayout.topBarLeadingPadding)
                .padding(.trailing, IslandFileDropLayout.topBarTrailingPadding)
                .islandContentMaterialized(
                    isVisible: visibleItemCount > 0,
                    reduceMotion: reduceMotion
                )
                .allowsHitTesting(visibleItemCount > 0)

                HStack(spacing: IslandFileDropLayout.spacing) {
                    destination(
                        target: .staging,
                        symbol: "tray.and.arrow.down",
                        title: "存入文稿",
                        visualIndex: 1
                    )

                    destination(
                        target: .airDrop,
                        symbol: "airdrop",
                        title: "隔空投送",
                        visualIndex: 2
                    )
                }
                .padding(.horizontal, IslandFileDropLayout.horizontalPadding)
                .padding(.top, IslandFileDropLayout.destinationsTopInset
                    - IslandDesignTokens.expandedTopBarControlHeight)

                Spacer(minLength: 0)
            }
            .frame(
                width: IslandFileDropLayout.size.width,
                height: IslandFileDropLayout.size.height,
                alignment: .top
            )
            .clipShape(finalShellShape)
        }
        .frame(
            width: windowCanvasSize.width,
            height: windowCanvasSize.height,
            alignment: .top
        )
        .opacity(contentOpacity)
    }

    private func destination(
        target: IslandFileDropTarget,
        symbol: String,
        title: String,
        visualIndex: Int
    ) -> some View {
        let isActive = hoverTarget == target

        return VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: target == .staging ? 27 : 25, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.58))
                .shadow(color: Color.white.opacity(isActive ? 0.16 : 0), radius: 6)

            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.76))

            if let previewName, isActive {
                Text(previewName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.88)))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: IslandFileDropLayout.destinationHeight)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.13 : 0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isActive ? Color.white.opacity(0.92) : Color.white.opacity(0.34),
                    style: StrokeStyle(lineWidth: isActive ? 3 : 2, dash: [9, 7])
                )
        }
        .scaleEffect(isActive ? 1.018 : 1)
        .animation(.spring(response: 0.20, dampingFraction: 0.82), value: isActive)
        .islandContentMaterialized(
            isVisible: visualIndex < visibleItemCount,
            reduceMotion: reduceMotion
        )
        .allowsHitTesting(visualIndex < visibleItemCount)
    }
}

struct IslandContentMaterializationModifier: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0.11)
            .blur(radius: reduceMotion || isVisible ? 0 : 3)
            .scaleEffect(
                reduceMotion || isVisible ? 1 : 0.985,
                anchor: .center
            )
            .offset(y: reduceMotion || isVisible ? 0 : 4)
            .brightness(reduceMotion || isVisible ? 0 : -0.08)
    }
}

extension View {
    func islandContentMaterialized(
        isVisible: Bool,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            IslandContentMaterializationModifier(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            )
        )
    }
}
