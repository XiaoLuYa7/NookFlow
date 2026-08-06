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
    @Published private(set) var visibleCardCount = 0
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
    @Published private(set) var isExpandedRuntimeActive = false
    @Published private(set) var tabTransitionCanvasSize: CGSize?
    @Published var isFileDropChooserVisible = false
    @Published var fileDropHoverTarget: IslandFileDropTarget?
    @Published var fileDropPreviewName: String?
    @Published private(set) var fileDropShellSize = IslandFileDropLayout.size
    @Published private(set) var fileDropShellMorphProgress: CGFloat = 1
    @Published private(set) var fileDropOpeningSourceSize = IslandFileDropLayout.size
    @Published private(set) var fileDropOpeningSourceMorphProgress: CGFloat = 1
    @Published private(set) var fileDropShellCanvasSize = IslandFileDropLayout.size
    @Published private(set) var fileDropOpeningAnimationTrigger = 0
    @Published private(set) var usesFileDropOpeningKeyframes = false
    @Published private(set) var fileDropContentOpacity: Double = 1
    @Published private(set) var fileDropVisibleItemCount = 0
    @Published private(set) var fileDropSourceShellOpacity: Double = 0
    @Published private(set) var fileDropRestorationTarget: IslandTopTab?
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
    private var runtimeActivationTask: Task<Void, Never>?
    private var fileDropTransitionTask: Task<Void, Never>?
    private var isFileDropDismissing = false
    private var pendingFileDropDismissal = false
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
        runtimeActivationTask?.cancel()
        fileDropTransitionTask?.cancel()
        tabCanvasTask?.cancel()
        playbackProvider.stop()
    }

    // MARK: - Actions

    func expand() {
        guard !isFileDropChooserVisible else { return }
        cancelCollapse()
        switch presentationPhase {
        case .expanded, .expandingShell, .loadingContent:
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
        guard !isFileDropChooserVisible,
              presentationPhase != .collapsed,
              presentationPhase != .hidingContent,
              presentationPhase != .collapsingShell,
              !isPinned
        else { return }

        cancelCollapse()
        deactivateExpandedRuntime()
        setExpandedContentOverflowHeight(0)
        cancelPendingCapsuleExpand()
        hoverPhase = .collapsing
        let wasShellExpanded = presentationPhase == .expanded || presentationPhase == .loadingContent
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

            var hiddenTransaction = Transaction()
            hiddenTransaction.disablesAnimations = true
            withTransaction(hiddenTransaction) {
                self.visibleCardCount = 0
                self.presentationPhase = .collapsingShell
            }

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
                self.visibleCardCount = 0
                self.tabTransitionCanvasSize = nil
                self.openingMotionPhase = .collapsed
                self.openingKeyframeStartState = .collapsed
                self.usesOpeningKeyframes = false
                self.shouldMountExpandedContent = false
            }
        }
    }

    func toggleExpandedByClick() {
        guard !isFileDropChooserVisible else { return }
        if presentationPhase == .collapsed || presentationPhase.isCollapsing {
            expand()
        } else {
            performTrackpadFeedback()
            collapseFromOutsideInteraction()
        }
    }

    func collapseFromOutsideInteraction() {
        guard !isFileDropChooserVisible, !isPinned else { return }
        collapse()
    }

    func togglePin() {
        performTrackpadFeedback()
        withAnimation(settings.springAnimation) {
            isPinned.toggle()
        }
        if isPinned {
            if isFileDropChooserVisible {
                cancelCollapse()
                return
            }
            let generation = cancelPresentationTask()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                presentationPhase = .expanded
                openingMotionPhase = .expanded
                usesOpeningKeyframes = false
                contentRevealProgress = 1
                secondaryContentRevealProgress = 1
                visibleCardCount = expandedVisualItemCount
                compactContentRevealProgress = 0
                shellAnimationState = .expanded
                compactCapsuleScaleX = 1
                compactCapsuleScaleY = 1
                hoverPhase = .expanded
            }
            scheduleExpandedRuntimeActivation(generation: generation)
            cancelCollapse()
        } else if isFileDropChooserVisible {
            dismissFileDropChooser()
        } else {
            scheduleCollapse()
        }
    }

    func selectTopTab(_ tab: IslandTopTab) {
        if isFileDropChooserVisible {
            restoreIslandFromFileDrop(to: tab)
            return
        }
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
                self.secondaryContentRevealProgress = 1
                self.visibleCardCount = self.expandedVisualItemCount
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
        guard !isFileDropChooserVisible else {
            cancelPendingCapsuleExpand()
            return
        }
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
        withAnimation(IslandDesignTokens.compactHoverPreviewAnimation) {
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
        withAnimation(IslandDesignTokens.compactHoverRestoreAnimation) {
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
        cancelCapsuleHoverForFileDrop()
        fileDropPreviewName = previewName

        if isFileDropChooserVisible {
            pendingFileDropDismissal = false
            if isFileDropDismissing {
                resumeFileDropChooser()
            }
            return
        }
        guard fileDropTransitionTask == nil else { return }

        let startsExpanded = (
            presentationPhase == .expanded || presentationPhase == .loadingContent
        ) && !isCollapsing
        let compactSourceSize = CGSize(
            width: compactCapsuleSize.width * compactCapsuleScaleX,
            height: compactCapsuleSize.height * compactCapsuleScaleY
        )
        let sourceSize = startsExpanded
            ? tabTransitionCanvasSize
                ?? IslandShellLayout.contentSize(settings: settings, selectedTopTab: selectedTopTab)
            : compactSourceSize
        let sourceMorphProgress: CGFloat = startsExpanded ? 1 : 0
        let generation = cancelPresentationTask()
        tabCanvasTask?.cancel()
        tabCanvasTask = nil
        deactivateExpandedRuntime()
        setExpandedContentOverflowHeight(0)
        isFileDropDismissing = false

        // Take ownership in the same AppKit drag callback. Deferring this setup to
        // a Task allowed the regular hover expansion to render before the chooser.
        let preservesExpandedShell = startsExpanded && shouldMountExpandedContent
        var setupTransaction = Transaction()
        setupTransaction.disablesAnimations = true
        withTransaction(setupTransaction) {
            fileDropOpeningSourceSize = sourceSize
            fileDropOpeningSourceMorphProgress = sourceMorphProgress
            fileDropShellCanvasSize = IslandFileDropLayout.openingCanvasSize(
                from: sourceSize,
                bounce: settings.bounceLevel
            )
            fileDropShellSize = reduceMotionEnabled ? sourceSize : IslandFileDropLayout.size
            fileDropShellMorphProgress = reduceMotionEnabled ? sourceMorphProgress : 1
            fileDropContentOpacity = 0
            fileDropVisibleItemCount = 0
            fileDropSourceShellOpacity = preservesExpandedShell ? 1 : 0
            usesFileDropOpeningKeyframes = !reduceMotionEnabled
            if usesFileDropOpeningKeyframes {
                fileDropOpeningAnimationTrigger &+= 1
            }

            // Publish chooser ownership before changing presentationPhase. The
            // AppKit observer then grows only the chooser host, never the normal
            // expanded-island host for an intermediate frame.
            isFileDropChooserVisible = true
            presentationPhase = .expanded
            hoverPhase = .expanded
            compactCapsuleScaleX = 1
            compactCapsuleScaleY = 1
            compactContentRevealProgress = 0
            shellAnimationState = .expanded
            openingMotionPhase = .expanded
            openingKeyframeStartState = .expanded
            usesOpeningKeyframes = false
            if !preservesExpandedShell {
                shouldMountExpandedContent = false
            }
        }

        fileDropTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await Task.yield()
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                self.fileDropSourceShellOpacity = 0
            }

            let shellDuration = self.reduceMotionEnabled
                ? IslandDesignTokens.reduceMotionOpenDuration
                : IslandDesignTokens.fileDropShellOpenDuration(
                    setting: self.settings.openSpeed
                )
            if self.reduceMotionEnabled {
                withAnimation(.easeOut(duration: shellDuration)) {
                    self.fileDropShellSize = IslandFileDropLayout.size
                    self.fileDropShellMorphProgress = 1
                }
            }
            await Self.sleep(seconds: shellDuration)
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            var completionTransaction = Transaction()
            completionTransaction.disablesAnimations = true
            withTransaction(completionTransaction) {
                self.usesFileDropOpeningKeyframes = false
                self.fileDropShellSize = IslandFileDropLayout.size
                self.fileDropShellMorphProgress = 1
                self.shouldMountExpandedContent = false
                self.fileDropSourceShellOpacity = 0
            }

            if self.pendingFileDropDismissal {
                self.pendingFileDropDismissal = false
                self.fileDropTransitionTask = nil
                self.dismissFileDropChooser()
                return
            }

            guard await self.loadFileDropContent(generation: generation) else { return }
            self.fileDropTransitionTask = nil
        }
    }

    private func loadFileDropContent(generation: Int) async -> Bool {
        guard isPresentationCurrent(generation), isFileDropChooserVisible else {
            return false
        }

        var placeholderTransaction = Transaction()
        placeholderTransaction.disablesAnimations = true
        withTransaction(placeholderTransaction) {
            fileDropContentOpacity = 1
            fileDropVisibleItemCount = 0
        }

        await Self.sleep(
            seconds: reduceMotionEnabled ? 0.02 : IslandDesignTokens.contentLoadingDelay
        )
        guard isPresentationCurrent(generation), isFileDropChooserVisible else {
            return false
        }

        let itemCount = 3
        if reduceMotionEnabled {
            let duration = 0.12
            withAnimation(.easeOut(duration: duration)) {
                fileDropVisibleItemCount = itemCount
            }
            await Self.sleep(seconds: duration)
        } else {
            for item in 1...itemCount {
                guard isPresentationCurrent(generation), isFileDropChooserVisible else {
                    return false
                }
                withAnimation(
                    .spring(
                        response: 0.34,
                        dampingFraction: 0.88,
                        blendDuration: 0
                    )
                ) {
                    fileDropVisibleItemCount = item
                }
                if item < itemCount {
                    await Self.sleep(seconds: IslandDesignTokens.cardRevealInterval)
                }
            }
            await Self.sleep(seconds: IslandDesignTokens.cardRevealDuration)
        }

        return isPresentationCurrent(generation) && isFileDropChooserVisible
    }

    private func cancelCapsuleHoverForFileDrop() {
        isCameraHoverActive = false
        capsuleExpandTask?.cancel()
        capsuleExpandTask = nil
    }

    func updateFileDropTarget(_ target: IslandFileDropTarget?) {
        guard fileDropHoverTarget != target else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            fileDropHoverTarget = target
        }
    }

    func finishFileDropInteraction() {
        guard isFileDropChooserVisible || fileDropTransitionTask != nil else { return }
        cancelCollapse()
        withAnimation(.easeOut(duration: 0.12)) {
            fileDropHoverTarget = nil
            fileDropPreviewName = nil
        }
        guard !isPinned else { return }
        if usesFileDropOpeningKeyframes {
            // Do not switch a running KeyframeAnimator back to its logical target.
            // Let the fixed-canvas shell reach the resting frame, then collapse;
            // otherwise SwiftUI visibly jumps between two rectangular layouts.
            pendingFileDropDismissal = true
            return
        }
        dismissFileDropChooser()
    }

    private func dismissFileDropChooser() {
        guard !isFileDropDismissing else { return }

        if !isFileDropChooserVisible {
            fileDropTransitionTask?.cancel()
            fileDropTransitionTask = nil
            isFileDropDismissing = false
            pendingFileDropDismissal = false
            _ = cancelPresentationTask()
            return
        }

        fileDropTransitionTask?.cancel()
        fileDropTransitionTask = nil
        isFileDropDismissing = true
        pendingFileDropDismissal = false
        let generation = cancelPresentationTask()
        deactivateExpandedRuntime()
        setExpandedContentOverflowHeight(0)
        usesFileDropOpeningKeyframes = false

        fileDropTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            withAnimation(.easeOut(duration: IslandFileDropLayout.exitContentHideDuration)) {
                self.fileDropContentOpacity = 0
            }
            await Self.sleep(seconds: IslandFileDropLayout.exitContentHideDuration)
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            var hiddenContentTransaction = Transaction()
            hiddenContentTransaction.disablesAnimations = true
            withTransaction(hiddenContentTransaction) {
                self.fileDropVisibleItemCount = 0
            }

            let animation = self.reduceMotionEnabled
                ? Animation.easeOut(duration: 0.16)
                : Animation.smooth(duration: IslandFileDropLayout.exitDuration, extraBounce: 0)
            withAnimation(animation) {
                self.fileDropShellSize = self.compactCapsuleSize
                self.fileDropShellMorphProgress = 0
            }
            await Self.sleep(
                seconds: self.reduceMotionEnabled ? 0.16 : IslandFileDropLayout.exitDuration
            )
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            var completionTransaction = Transaction()
            completionTransaction.disablesAnimations = true
            withTransaction(completionTransaction) {
                self.presentationPhase = .collapsed
                self.hoverPhase = .idle
                self.compactContentRevealProgress = 1
                self.shellAnimationState = .collapsed
                self.openingMotionPhase = .collapsed
                self.openingKeyframeStartState = .collapsed
                self.usesOpeningKeyframes = false
                self.shouldMountExpandedContent = false
                self.contentRevealProgress = 0
                self.secondaryContentRevealProgress = 0
                self.visibleCardCount = 0
                self.tabTransitionCanvasSize = nil
                self.fileDropRestorationTarget = nil
                self.fileDropHoverTarget = nil
                self.fileDropPreviewName = nil
                self.fileDropVisibleItemCount = 0
                self.fileDropSourceShellOpacity = 0
                self.isFileDropChooserVisible = false
                self.pendingFileDropDismissal = false
            }

            self.isFileDropDismissing = false
            self.fileDropTransitionTask = nil
        }
    }

    private func resumeFileDropChooser() {
        guard isFileDropChooserVisible, isFileDropDismissing else { return }

        fileDropTransitionTask?.cancel()
        fileDropTransitionTask = nil
        isFileDropDismissing = false
        let generation = cancelPresentationTask()

        var resumeTransaction = Transaction()
        resumeTransaction.disablesAnimations = true
        withTransaction(resumeTransaction) {
            presentationPhase = .expanded
            hoverPhase = .expanded
            compactContentRevealProgress = 0
            shellAnimationState = .expanded
            openingMotionPhase = .expanded
            fileDropContentOpacity = 0
            fileDropVisibleItemCount = 0
            usesFileDropOpeningKeyframes = false
        }

        fileDropTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Retarget the same animatable values from their current presentation
            // state. Restarting the keyframe trigger here reset geometry to zero
            // and caused the intermittent block-to-block jump on re-entry.
            let shellDuration = self.reduceMotionEnabled
                ? IslandDesignTokens.reduceMotionOpenDuration
                : IslandDesignTokens.shellOpenDuration(setting: self.settings.openSpeed)
            let shellAnimation = self.reduceMotionEnabled
                ? Animation.easeOut(duration: shellDuration)
                : Animation.smooth(duration: shellDuration, extraBounce: 0)
            withAnimation(shellAnimation) {
                self.fileDropShellSize = IslandFileDropLayout.size
                self.fileDropShellMorphProgress = 1
            }
            await Self.sleep(seconds: shellDuration)
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }
            var completionTransaction = Transaction()
            completionTransaction.disablesAnimations = true
            withTransaction(completionTransaction) {
                self.usesFileDropOpeningKeyframes = false
                self.shouldMountExpandedContent = false
            }

            guard await self.loadFileDropContent(generation: generation) else { return }
            self.fileDropTransitionTask = nil
        }
    }

    private func restoreIslandFromFileDrop(to tab: IslandTopTab) {
        guard isFileDropChooserVisible else { return }

        performTrackpadFeedback()
        cancelCollapse()
        fileDropTransitionTask?.cancel()
        fileDropTransitionTask = nil
        isFileDropDismissing = false
        pendingFileDropDismissal = false
        usesFileDropOpeningKeyframes = false
        let generation = cancelPresentationTask()
        let targetSize = IslandShellLayout.contentSize(settings: settings, selectedTopTab: tab)

        var selectionTransaction = Transaction()
        selectionTransaction.disablesAnimations = true
        withTransaction(selectionTransaction) {
            selectedTopTab = tab
            fileDropHoverTarget = nil
            fileDropPreviewName = nil
            fileDropRestorationTarget = tab
        }

        fileDropTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }

            withAnimation(.easeOut(duration: IslandFileDropLayout.restoreContentHideDuration)) {
                self.fileDropContentOpacity = 0
            }
            await Self.sleep(seconds: IslandFileDropLayout.restoreContentHideDuration)
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            var hiddenContentTransaction = Transaction()
            hiddenContentTransaction.disablesAnimations = true
            withTransaction(hiddenContentTransaction) {
                self.fileDropVisibleItemCount = 0
            }

            let resizeAnimation = self.reduceMotionEnabled
                ? Animation.easeOut(duration: 0.18)
                : Animation.smooth(duration: IslandFileDropLayout.restoreDuration, extraBounce: 0)
            withAnimation(resizeAnimation) {
                self.fileDropShellSize = targetSize
                self.fileDropShellMorphProgress = 1
            }
            await Self.sleep(
                seconds: self.reduceMotionEnabled ? 0.18 : IslandFileDropLayout.restoreDuration
            )
            guard !Task.isCancelled, self.isPresentationCurrent(generation) else { return }

            var restoreTransaction = Transaction()
            restoreTransaction.disablesAnimations = true
            withTransaction(restoreTransaction) {
                self.presentationPhase = .expandingShell
                self.hoverPhase = .expanded
                self.compactContentRevealProgress = 0
                self.shellAnimationState = .expanded
                self.openingMotionPhase = .expanded
                self.openingKeyframeStartState = .expanded
                self.usesOpeningKeyframes = false
                self.shouldMountExpandedContent = true
                self.contentRevealProgress = 0
                self.secondaryContentRevealProgress = 0
                self.visibleCardCount = 0
                self.tabTransitionCanvasSize = nil
                self.fileDropRestorationTarget = nil
                self.fileDropSourceShellOpacity = 0
                self.isFileDropChooserVisible = false
            }

            guard await self.loadExpandedContent(generation: generation) else { return }
            self.finishExpandedPresentation(generation: generation)
            self.fileDropTransitionTask = nil
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
        guard !isFileDropChooserVisible,
              presentationPhase != .collapsed,
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
        deactivateExpandedRuntime()
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
            visibleCardCount = 0
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

        let shellTiming = IslandDesignTokens.shellOpenTiming(
            setting: settings.openSpeed
        )
        let shellDuration = reduceMotionEnabled
            ? IslandDesignTokens.reduceMotionOpenDuration
            : shellTiming.total

        presentationTask = Task { @MainActor [weak self] in
            guard let self,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .expandingShell
            else { return }

            if self.reduceMotionEnabled || isReversing {
                let directOpenDuration = shellDuration
                withAnimation(.smooth(duration: directOpenDuration, extraBounce: 0)) {
                    self.shellAnimationState = .expanded
                }
                await Self.sleep(seconds: directOpenDuration)

                guard self.isPresentationCurrent(generation),
                      self.presentationPhase == .expandingShell
                else { return }

                var settledTransaction = Transaction()
                settledTransaction.disablesAnimations = true
                withTransaction(settledTransaction) {
                    self.usesOpeningKeyframes = false
                    self.shellAnimationState = .expanded
                    self.openingMotionPhase = .expanded
                }

                guard await self.loadExpandedContent(generation: generation) else { return }
                self.finishExpandedPresentation(generation: generation)
                return
            }

            // Mount the stable final card layout when the shell enters its slow
            // recovery. The 80 ms content delay lets the first card materialize
            // just before the tiny final spring begins.
            await Self.sleep(seconds: shellTiming.expansion + shellTiming.rebound)
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .expandingShell
            else { return }

            async let contentLoaded = self.loadExpandedContent(generation: generation)

            await Self.sleep(seconds: shellTiming.recovery + shellTiming.settle)
            guard self.isPresentationCurrent(generation),
                  self.presentationPhase == .loadingContent
            else {
                _ = await contentLoaded
                return
            }

            var settledTransaction = Transaction()
            settledTransaction.disablesAnimations = true
            withTransaction(settledTransaction) {
                self.usesOpeningKeyframes = false
                self.shellAnimationState = .expanded
                self.openingMotionPhase = .expanded
            }
            guard await contentLoaded else { return }
            self.finishExpandedPresentation(generation: generation)
        }
    }

    private func loadExpandedContent(generation: Int) async -> Bool {
        guard isPresentationCurrent(generation),
              presentationPhase == .expandingShell
                || presentationPhase == .loadingContent
        else { return false }

        var placeholderTransaction = Transaction()
        placeholderTransaction.disablesAnimations = true
        withTransaction(placeholderTransaction) {
            presentationPhase = .loadingContent
            shouldMountExpandedContent = true
            contentRevealProgress = 1
            secondaryContentRevealProgress = 0
            visibleCardCount = 0
        }
        await Self.sleep(
            seconds: reduceMotionEnabled ? 0.02 : IslandDesignTokens.contentLoadingDelay
        )
        guard isPresentationCurrent(generation),
              presentationPhase == .loadingContent
        else { return false }

        let itemCount = expandedVisualItemCount
        if reduceMotionEnabled {
            let duration = 0.12
            withAnimation(.easeOut(duration: duration)) {
                secondaryContentRevealProgress = 1
                visibleCardCount = itemCount
            }
            await Self.sleep(seconds: duration)
        } else {
            for item in 1...itemCount {
                guard isPresentationCurrent(generation),
                      presentationPhase == .loadingContent
                else { return false }

                withAnimation(.smooth(duration: 0.26, extraBounce: 0)) {
                    visibleCardCount = item
                    if item == 1 {
                        secondaryContentRevealProgress = 1
                    }
                }
                if item < itemCount {
                    await Self.sleep(seconds: IslandDesignTokens.cardRevealInterval)
                }
            }
            await Self.sleep(seconds: IslandDesignTokens.cardRevealDuration)
        }

        return isPresentationCurrent(generation)
            && presentationPhase == .loadingContent
    }

    private var expandedVisualItemCount: Int {
        if selectedTopTab == .home {
            return 1 + max(
                1,
                IslandShellLayout.visibleModules(settings: settings).count
            )
        }
        return 2
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
        presentationPhase = .loadingContent
        openingMotionPhase = .expanded

        let animation = reduceMotionEnabled
            ? Animation.easeOut(duration: IslandDesignTokens.primaryContentRevealDuration)
            : Animation.smooth(
                duration: IslandDesignTokens.primaryContentRevealDuration,
                extraBounce: 0
            )
        withAnimation(animation) {
            contentRevealProgress = 1
            secondaryContentRevealProgress = 1
            visibleCardCount = expandedVisualItemCount
        }

        presentationTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.primaryContentRevealDuration)
            guard let self,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .loadingContent
            else { return }
            self.finishExpandedPresentation(generation: generation)
        }
    }

    private func finishExpandedPresentation(generation: Int) {
        guard isPresentationCurrent(generation) else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            usesOpeningKeyframes = false
            shellAnimationState = .expanded
            openingMotionPhase = .expanded
            presentationPhase = .expanded
        }
        scheduleExpandedRuntimeActivation(generation: generation)
    }

    private func scheduleExpandedRuntimeActivation(generation: Int) {
        runtimeActivationTask?.cancel()
        runtimeActivationTask = nil
        guard !isExpandedRuntimeActive else { return }

        runtimeActivationTask = Task { @MainActor [weak self] in
            await Self.sleep(seconds: IslandDesignTokens.expandedRuntimeActivationDelay)
            guard let self,
                  !Task.isCancelled,
                  self.isPresentationCurrent(generation),
                  self.presentationPhase == .loadingContent
                    || self.presentationPhase == .expanded
            else { return }

            self.isExpandedRuntimeActive = true
            self.runtimeActivationTask = nil
        }
    }

    private func deactivateExpandedRuntime() {
        runtimeActivationTask?.cancel()
        runtimeActivationTask = nil
        guard isExpandedRuntimeActive else { return }
        isExpandedRuntimeActive = false
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
