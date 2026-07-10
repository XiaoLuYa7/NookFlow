import AppKit
import SwiftUI
import Combine

/// Central view-model for the island UI.
@MainActor
final class IslandViewModel: ObservableObject {

    @Published private(set) var presentationPhase: IslandPresentationPhase = .collapsed
    @Published private(set) var hoverPhase: IslandHoverPhase = .idle
    @Published var selectedTopTab: IslandTopTab = .home

    /// Set to `true` when the user explicitly tapped to pin the island open.
    /// While pinned, hover-exit does NOT trigger an auto-collapse.
    @Published private(set) var isPinned = false

    @Published var contentRevealProgress: Double = 0
    @Published var secondaryContentRevealProgress: Double = 0
    @Published var compactContentRevealProgress: Double = 1
    @Published var shellAnimationState: IslandShellAnimationState = .collapsed
    @Published var compactCapsuleSize = IslandDesignTokens.defaultCompactCapsuleSize
    @Published private(set) var compactContentMode: CompactCapsuleContentMode = .camera
    @Published var notchGeometry = NotchGeometry(
        hasNotch: false, cameraZoneWidth: 0, sideWidth: 150,
        totalWidth: 300, height: 24
    )
    @Published var compactCapsuleScaleX: CGFloat = 1
    @Published var compactCapsuleScaleY: CGFloat = 1
    @Published private(set) var openingMotionPhase: IslandOpeningMotionPhase = .collapsed
    @Published private(set) var openingAnimationTrigger = 0
    @Published private(set) var openingKeyframeStartState = IslandShellAnimationState.collapsed
    @Published private(set) var usesOpeningKeyframes = false
    @Published private(set) var shouldMountExpandedContent = false
    @Published private(set) var tabTransitionCanvasSize: CGSize?
    @Published var isFileDropChooserVisible = false
    @Published var fileDropHoverTarget: IslandFileDropTarget?
    @Published var fileDropPreviewName: String?
    @Published private(set) var fileDataRefreshToken = 0
    @Published private(set) var reduceMotionEnabled = false
    @Published private(set) var expandedContentOverflowHeight: CGFloat = 0
    @Published private(set) var externalInteractiveFrame: CGRect?
    @Published private(set) var todoTasks: [TodoTask] = []

    let playbackProvider: PlaybackProvider
    let lyricsProvider = LyricsProvider()

    // Collapse work-item that can be cancelled if the mouse re-enters.
    private var collapseWork: DispatchWorkItem?
    private var capsuleExpandTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    private var presentationGeneration = 0
    private var tabCanvasTask: Task<Void, Never>?
    private var isCameraHoverActive = false
    private var compactCameraCapsuleSize = IslandDesignTokens.defaultCameraCapsuleSize
    private var compactStatusCapsuleSize = IslandDesignTokens.defaultCompactCapsuleSize
    private var compactLyricsCapsuleSize = CGSize(
        width: IslandDesignTokens.compactLyricsCapsuleMinimumWidth,
        height: IslandDesignTokens.defaultCompactCapsuleSize.height
    )
    private let settings: IslandSettings

    init(settings: IslandSettings) {
        self.settings = settings
        playbackProvider = PlaybackProvider(settings: settings)
        compactContentMode = Self.initialCompactContentMode(settings: settings)
    }

    var mode: IslandMode { presentationPhase.mode }
    var isCollapsing: Bool { presentationPhase.isCollapsing }

    deinit {
        collapseWork?.cancel()
        capsuleExpandTask?.cancel()
        presentationTask?.cancel()
        tabCanvasTask?.cancel()
        playbackProvider.stop()
    }

    // MARK: - Actions

    func expand() {
        cancelCollapse()
        switch presentationPhase {
        case .expanded, .expandingShell, .revealingContent:
            return
        case .hidingContent:
            reverseContentReveal()
            return
        case .collapsingShell:
            beginShellExpansion(isReversing: true)
            return
        case .collapsed:
            break
        }

        let startsFromHoverPreview = hoverPhase == .preview || hoverPhase == .waiting
        capsuleExpandTask?.cancel()
        capsuleExpandTask = nil
        if startsFromHoverPreview {
            beginShellExpansion(startingFromHoverPreview: true)
            return
        }

        cancelPendingCapsuleExpand()
        capsuleExpandTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.shellOpenInitialDelay)
            guard let self, !Task.isCancelled, self.presentationPhase == .collapsed else { return }
            self.beginShellExpansion()
        }
    }

    func collapse() {
        guard presentationPhase != .collapsed,
              presentationPhase != .hidingContent,
              presentationPhase != .collapsingShell,
              !isPinned
        else { return }

        cancelCollapse()
        setExpandedContentOverflowHeight(0)
        cancelPendingCapsuleExpand()
        hoverPhase = .collapsing
        let wasShellExpanded = presentationPhase == .expanded || presentationPhase == .revealingContent
        let generation = cancelPresentationTask()
        tabCanvasTask?.cancel()
        tabCanvasTask = nil

        presentationPhase = .hidingContent
        openingMotionPhase = .closing
        let hideDuration = reduceMotionEnabled ? 0.08 : IslandDesignTokens.contentHideDuration
        withAnimation(.easeOut(duration: hideDuration)) {
            contentRevealProgress = 0
            secondaryContentRevealProgress = 0
        }

        let shellDuration = reduceMotionEnabled
            ? IslandDesignTokens.reduceMotionCloseDuration
            : IslandDesignTokens.shellCloseDuration(setting: settings.closeSpeed)
        presentationTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: hideDuration)
            guard let self,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .hidingContent
            else { return }

            self.presentationPhase = .collapsingShell

            // Closing must have one owner for the shell geometry. The previous reverse
            // sequence started a second animation before the first one had finished,
            // which forced SwiftUI to retarget the same Animatable values mid-flight and
            // produced a visible hitch near the compact state.
            let shellAnimation: Animation = self.reduceMotionEnabled || !wasShellExpanded
                ? .easeOut(duration: shellDuration)
                : IslandDesignTokens.shellCloseAnimation(duration: shellDuration)
            withAnimation(shellAnimation) {
                self.usesOpeningKeyframes = false
                self.shellAnimationState = .collapsed
            }
            await self.revealCompactContentNearCollapseEnd(
                shellDuration: shellDuration,
                generation: generation
            )

            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .collapsingShell
            else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.presentationPhase = .collapsed
                self.hoverPhase = .idle
                self.compactCapsuleScaleX = 1
                self.compactCapsuleScaleY = 1
                self.compactContentRevealProgress = 1
                self.shellAnimationState = .collapsed
                self.contentRevealProgress = 0
                self.secondaryContentRevealProgress = 0
                self.tabTransitionCanvasSize = nil
                self.openingMotionPhase = .collapsed
                self.openingKeyframeStartState = .collapsed
                self.usesOpeningKeyframes = false
                self.shouldMountExpandedContent = false
            }
        }
    }

    func toggleExpandedByClick() {
        if presentationPhase == .collapsed || presentationPhase.isCollapsing {
            expand()
        } else {
            performTrackpadFeedback()
            collapseFromOutsideInteraction()
        }
    }

    func collapseFromOutsideInteraction() {
        guard !isPinned else { return }
        collapse()
    }

    func togglePin() {
        performTrackpadFeedback()
        withAnimation(settings.springAnimation) {
            isPinned.toggle()
        }
        if isPinned {
            cancelPresentationTask()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentationPhase = .expanded
                openingMotionPhase = .expanded
                usesOpeningKeyframes = false
                contentRevealProgress = 1
                secondaryContentRevealProgress = 1
                compactContentRevealProgress = 0
                shellAnimationState = .expanded
                compactCapsuleScaleX = 1
                compactCapsuleScaleY = 1
                hoverPhase = .expanded
            }
            cancelCollapse()
        } else {
            scheduleCollapse()
        }
    }

    func selectTopTab(_ tab: IslandTopTab) {
        guard selectedTopTab != tab else { return }
        performTrackpadFeedback()
        tabCanvasTask?.cancel()
        setExpandedContentOverflowHeight(0)

        let animation = tab == .home
            ? IslandDesignTokens.tabReturnHomeAnimation
            : IslandDesignTokens.tabSwitchAnimation
        let fromSize = IslandShellLayout.contentSize(settings: settings, selectedTopTab: selectedTopTab)
        let toSize = IslandShellLayout.contentSize(settings: settings, selectedTopTab: tab)
        let canvasSize = CGSize(
            width: max(fromSize.width, toSize.width),
            height: max(fromSize.height, toSize.height)
        )

        var canvasTransaction = Transaction()
        canvasTransaction.disablesAnimations = true
        withTransaction(canvasTransaction) {
            tabTransitionCanvasSize = canvasSize
            contentRevealProgress = 0
        }

        withAnimation(animation) {
            selectedTopTab = tab
        }

        let duration = tab == .home
            ? IslandDesignTokens.tabReturnHomeDuration
            : IslandDesignTokens.tabSwitchDuration
        tabCanvasTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled, self.selectedTopTab == tab else { return }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.tabTransitionCanvasSize = nil
            }

            guard self.mode == .expanded, !self.isCollapsing else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.contentRevealProgress = 1
            }
        }
    }

    func updateCompactCapsuleSizes(
        camera: CGSize,
        status: CGSize,
        lyrics: CGSize
    ) {
        compactCameraCapsuleSize = camera
        compactStatusCapsuleSize = status
        compactLyricsCapsuleSize = lyrics
        applyCompactCapsuleSizeForCurrentMode()
    }

    func updateCompactContentMode(_ mode: CompactCapsuleContentMode) {
        guard compactContentMode != mode else { return }
        compactContentMode = mode
        applyCompactCapsuleSizeForCurrentMode()
    }

    func updateNotchGeometry(_ geometry: NotchGeometry) {
        guard notchGeometry != geometry else { return }
        notchGeometry = geometry
    }

    private func applyCompactCapsuleSizeForCurrentMode() {
        let size: CGSize
        switch compactContentMode {
        case .camera:
            size = compactCameraCapsuleSize
        case .status:
            size = compactStatusCapsuleSize
        case .lyrics:
            size = compactLyricsCapsuleSize
        }

        guard compactCapsuleSize != size else { return }
        compactCapsuleSize = size
    }

    private static func initialCompactContentMode(settings: IslandSettings) -> CompactCapsuleContentMode {
        let hasVisibleSideStatus = settings.showCustomCompactIcons
            && (settings.compactLeftSideIcon != .none || settings.compactRightSideIcon != .none)
        return hasVisibleSideStatus ? .status : .camera
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        guard reduceMotionEnabled != enabled else { return }
        reduceMotionEnabled = enabled
    }

    func updateCameraHover(_ isHovering: Bool) {
        guard isCameraHoverActive != isHovering else { return }
        isCameraHoverActive = isHovering

        if isHovering {
            beginCapsuleHoverPreviewIfNeeded()
        } else {
            restoreCapsuleAfterHoverExit()
        }
    }

    func cancelPendingCapsuleExpand() {
        isCameraHoverActive = false
        capsuleExpandTask?.cancel()
        capsuleExpandTask = nil
        guard mode == .compact else { return }

        restoreCapsuleAfterHoverExit()
    }

    private func beginCapsuleHoverPreviewIfNeeded() {
        guard settings.expansionMode == .hover else { return }
        guard presentationPhase == .collapsed else { return }

        switch hoverPhase {
        case .preview, .waiting, .expanded:
            return
        case .idle, .collapsing:
            break
        }

        capsuleExpandTask?.cancel()
        hoverPhase = .preview
        let previewAnimation = Animation.smooth(
            duration: IslandDesignTokens.compactHoverPreviewDuration,
            extraBounce: 0
        )
        withAnimation(previewAnimation) {
            compactCapsuleScaleX = IslandDesignTokens.compactHoverWidthScale
            compactCapsuleScaleY = IslandDesignTokens.compactHoverHeightScale
        }

        capsuleExpandTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.compactHoverPreviewDuration)
            guard let self,
                  !Task.isCancelled,
                  self.isCameraHoverActive,
                  self.presentationPhase == .collapsed,
                  self.hoverPhase == .preview
            else { return }

            self.hoverPhase = .waiting
            let remainingDelay = max(
                0,
                settings.hoverExpansionDelay - IslandDesignTokens.compactHoverPreviewDuration
            )
            await Self.sleep(seconds: remainingDelay)
            guard !Task.isCancelled,
                  self.isCameraHoverActive,
                  self.presentationPhase == .collapsed,
                  self.hoverPhase == .waiting
            else { return }

            self.capsuleExpandTask = nil
            self.beginShellExpansion(startingFromHoverPreview: true)
        }
    }

    private func restoreCapsuleAfterHoverExit() {
        capsuleExpandTask?.cancel()
        capsuleExpandTask = nil
        guard presentationPhase == .collapsed else { return }
        guard hoverPhase != .idle else { return }

        hoverPhase = .collapsing
        let restoreAnimation = Animation.smooth(
            duration: IslandDesignTokens.compactHoverRestoreDuration,
            extraBounce: 0
        )
        withAnimation(restoreAnimation) {
            compactCapsuleScaleX = 1
            compactCapsuleScaleY = 1
        }

        capsuleExpandTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.compactHoverRestoreDuration)
            guard let self,
                  !Task.isCancelled,
                  !self.isCameraHoverActive,
                  self.presentationPhase == .collapsed,
                  self.hoverPhase == .collapsing
            else { return }
            self.hoverPhase = .idle
            self.capsuleExpandTask = nil
        }
    }

    func beginFileDrop(previewName: String?) {
        cancelCollapse()
        cancelPendingCapsuleExpand()

        if mode == .expanded, !isCollapsing {
            let isChangingTab = selectedTopTab != .files
            selectTopTab(.files)
            fileDropPreviewName = previewName
            if !isChangingTab {
                contentRevealProgress = 1
                secondaryContentRevealProgress = 1
            }

            withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.04)) {
                isFileDropChooserVisible = true
            }
            return
        }

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            selectedTopTab = .files
            fileDropPreviewName = previewName
            isFileDropChooserVisible = true
            contentRevealProgress = 0
            secondaryContentRevealProgress = 0
            compactCapsuleScaleX = 1
            compactCapsuleScaleY = 1
        }

        beginShellExpansion(isReversing: presentationPhase.isCollapsing)
    }

    func updateFileDropTarget(_ target: IslandFileDropTarget?) {
        guard fileDropHoverTarget != target else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            fileDropHoverTarget = target
        }
    }

    func endFileDrop() {
        withAnimation(.easeOut(duration: 0.16)) {
            isFileDropChooserVisible = false
            fileDropHoverTarget = nil
            fileDropPreviewName = nil
        }
    }

    func notifyFileDataChanged() {
        fileDataRefreshToken += 1
    }

    func setExpandedContentOverflowHeight(_ height: CGFloat) {
        let normalizedHeight = max(0, ceil(height))
        guard abs(expandedContentOverflowHeight - normalizedHeight) > 0.5 else { return }
        expandedContentOverflowHeight = normalizedHeight
    }

    func setExternalInteractiveFrame(_ frame: CGRect?) {
        guard externalInteractiveFrame != frame else { return }
        externalInteractiveFrame = frame
    }

    func setTodoTasks(_ tasks: [TodoTask]) {
        guard todoTasks != tasks else { return }
        todoTasks = tasks
    }

    // MARK: - Hover-driven auto-collapse

    func scheduleCollapse(delay: TimeInterval? = nil) {
        guard presentationPhase != .collapsed,
              !presentationPhase.isCollapsing,
              !isPinned
        else { return }
        cancelCollapse()
        let effectiveDelay = delay ?? settings.closeDelay
        guard effectiveDelay > 0 else {
            collapse()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: work)
    }

    func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func beginShellExpansion(
        isReversing: Bool = false,
        startingFromHoverPreview: Bool = false
    ) {
        performTrackpadFeedback()
        let generation = cancelPresentationTask()
        capsuleExpandTask?.cancel()
        capsuleExpandTask = nil
        let keyframeStartState = startingFromHoverPreview
            ? hoverPreviewOpeningState()
            : .collapsed

        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            presentationPhase = .expandingShell
            hoverPhase = .expanded
            openingMotionPhase = .opening
            contentRevealProgress = 0
            secondaryContentRevealProgress = 0
            shouldMountExpandedContent = true
            compactCapsuleScaleX = 1
            compactCapsuleScaleY = 1
            openingKeyframeStartState = keyframeStartState
            if reduceMotionEnabled || isReversing {
                usesOpeningKeyframes = false
            } else {
                shellAnimationState = .expanded
                usesOpeningKeyframes = true
                openingAnimationTrigger &+= 1
            }
        }

        withAnimation(.easeOut(duration: 0.10)) {
            compactContentRevealProgress = 0
        }

        let shellDuration = reduceMotionEnabled
            ? IslandDesignTokens.reduceMotionOpenDuration
            : IslandDesignTokens.shellOpenDuration(setting: settings.openSpeed)
        let openTiming = IslandDesignTokens.shellOpenTiming(setting: settings.openSpeed)
        let primaryRevealDuration = reduceMotionEnabled
            ? 0.12
            : openTiming.settle
        let secondaryRevealDuration = reduceMotionEnabled
            ? 0.10
            : IslandDesignTokens.secondaryContentRevealDuration

        presentationTask = Task { @MainActor [weak self] in
            guard let self,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .expandingShell
            else { return }

            if self.reduceMotionEnabled || isReversing {
                let directOpenDuration = self.reduceMotionEnabled
                    ? shellDuration
                    : min(shellDuration, 0.30)
                withAnimation(.easeInOut(duration: directOpenDuration)) {
                    self.shellAnimationState = .expanded
                }
                await Self.sleep(seconds: directOpenDuration)
                guard self.isPresentationCurrent(generation),
                      self.presentationPhase == .expandingShell
                else { return }

                var settledTransaction = Transaction()
                settledTransaction.disablesAnimations = true
                withTransaction(settledTransaction) {
                    self.shellAnimationState = .expanded
                }
                self.shouldMountExpandedContent = true
                await Task.yield()
                guard self.isPresentationCurrent(generation),
                      self.presentationPhase == .expandingShell
                else { return }

                self.presentationPhase = .revealingContent
                withAnimation(.easeOut(duration: primaryRevealDuration)) {
                    self.contentRevealProgress = 1
                }

                await Self.sleep(seconds: IslandDesignTokens.secondaryContentRevealDelay)
                guard self.isPresentationCurrent(generation),
                      self.presentationPhase == .revealingContent
                else { return }

                withAnimation(.easeOut(duration: secondaryRevealDuration)) {
                    self.secondaryContentRevealProgress = 1
                }

                let elapsed = directOpenDuration + IslandDesignTokens.secondaryContentRevealDelay
                let contentCompletionTime = max(
                    directOpenDuration + primaryRevealDuration,
                    directOpenDuration
                        + IslandDesignTokens.secondaryContentRevealDelay
                        + secondaryRevealDuration
                )
                let completionTime = max(directOpenDuration, contentCompletionTime)
                await Self.sleep(seconds: max(0, completionTime - elapsed))
                guard self.isPresentationCurrent(generation),
                      self.presentationPhase == .revealingContent
                else { return }

                self.openingMotionPhase = .expanded
                self.presentationPhase = .expanded
                return
            }

            await Self.sleep(seconds: openTiming.contentRevealDelay)
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .expandingShell
            else { return }

            // The cards start just before the final 97% -> 100% settle to avoid
            // triggering all card work on the same frame as the shell's last turn.
            self.shouldMountExpandedContent = true
            await Task.yield()
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .expandingShell
            else { return }

            self.presentationPhase = .revealingContent
            withAnimation(.easeOut(duration: primaryRevealDuration)) {
                self.contentRevealProgress = 1
            }

            await Self.sleep(seconds: IslandDesignTokens.secondaryContentRevealDelay)
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .revealingContent
            else { return }

            withAnimation(.easeOut(duration: secondaryRevealDuration)) {
                self.secondaryContentRevealProgress = 1
            }

            let elapsed = openTiming.contentRevealDelay
                + IslandDesignTokens.secondaryContentRevealDelay
            let completionTime = max(
                openTiming.total,
                max(
                    openTiming.contentRevealDelay + primaryRevealDuration,
                    openTiming.contentRevealDelay
                        + IslandDesignTokens.secondaryContentRevealDelay
                        + secondaryRevealDuration
                )
            )
            await Self.sleep(seconds: max(0, completionTime - elapsed))
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .revealingContent
            else { return }

            self.usesOpeningKeyframes = false
            self.shellAnimationState = .expanded
            self.openingMotionPhase = .expanded
            self.presentationPhase = .expanded
        }
    }

    private func hoverPreviewOpeningState() -> IslandShellAnimationState {
        let expandedSize = IslandShellLayout.contentSize(
            settings: settings,
            selectedTopTab: selectedTopTab
        )
        return IslandShellAnimationState(
            widthProgress: IslandShellLayout.progressForCompactScale(
                compact: compactCapsuleSize.width,
                expanded: expandedSize.width,
                scale: IslandDesignTokens.compactHoverWidthScale
            ),
            heightProgress: IslandShellLayout.progressForCompactScale(
                compact: compactCapsuleSize.height,
                expanded: expandedSize.height,
                scale: IslandDesignTokens.compactHoverHeightScale
            ),
            morphProgress: 0
        )
    }

    private func reverseContentReveal() {
        let generation = cancelPresentationTask()
        shouldMountExpandedContent = true
        presentationPhase = .revealingContent
        openingMotionPhase = .expanded

        withAnimation(.easeOut(duration: IslandDesignTokens.primaryContentRevealDuration)) {
            contentRevealProgress = 1
            secondaryContentRevealProgress = 1
        }

        presentationTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.primaryContentRevealDuration)
            guard let self,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .revealingContent
            else { return }
            self.usesOpeningKeyframes = false
            self.shellAnimationState = .expanded
            self.presentationPhase = .expanded
        }
    }

    private func revealCompactContentNearCollapseEnd(
        shellDuration: TimeInterval,
        generation: Int
    ) async {
        let revealDuration = min(
            IslandDesignTokens.compactContentRevealDuration,
            shellDuration
        )
        await Self.sleep(seconds: max(0, shellDuration - revealDuration))
        guard isPresentationCurrent(generation) else { return }

        withAnimation(.easeOut(duration: revealDuration)) {
            compactContentRevealProgress = 1
        }
        await Self.sleep(seconds: revealDuration)
    }

    @discardableResult
    private func cancelPresentationTask() -> Int {
        presentationTask?.cancel()
        presentationTask = nil
        presentationGeneration &+= 1
        return presentationGeneration
    }

    private func isPresentationCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == presentationGeneration
    }

    private static func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func performTrackpadFeedback() {
        TrackpadHapticFeedback.perform(settings.trackpadFeedbackMode)
    }
}
