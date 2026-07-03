import SwiftUI

struct CompactCapsuleContentView: View {
    let mode: CompactCapsuleContentMode
    let geometry: NotchGeometry
    let snapshot: PlaybackSnapshot
    let currentLyricText: String?
    let nextLyricText: String?
    let currentLyricStartTimeMS: TimeInterval?
    let nextLyricStartTimeMS: TimeInterval?
    let showsTrackName: Bool
    let showsLyrics: Bool
    let leftSideIcon: SettingsHomeSideIcon
    let rightSideIcon: SettingsHomeSideIcon
    let sideStatusContext: SideStatusContext
    let foregroundPromptDisplayMode: ForegroundAppPromptDisplayMode
    let foregroundPrompt: ForegroundAppPrompt?
    var statusContentScale: CGFloat = 1

    @State private var anchorDate = Date()
    @State private var anchorElapsed: TimeInterval = 0

    var body: some View {
        Group {
            switch mode {
            case .camera:
                Color.clear
            case .status:
                sideZoneLayout {
                    if let foregroundPrompt {
                        foregroundPromptLeft(foregroundPrompt)
                    } else {
                        sideStatus(leftSideIcon)
                            .scaleEffect(statusContentScale)
                    }
                } right: {
                    if let foregroundPrompt {
                        foregroundPromptRight(foregroundPrompt)
                    } else {
                        sideStatus(rightSideIcon)
                            .scaleEffect(statusContentScale)
                    }
                }
            case .lyrics:
                sideZoneLayout(placement: .lyrics) {
                    adaptiveStatusText(
                        primary: presentation?.leftText ?? "",
                        fallback: presentation?.leftFallbackText ?? ""
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                } right: {
                    SyncedCompactLyricText(
                        text: presentation?.rightText ?? "",
                        anchorDate: anchorDate,
                        anchorElapsed: anchorElapsed,
                        isPlaying: snapshot.state == .playing,
                        lineStartTimeMS: syncedRightTextStartTimeMS,
                        nextLineStartTimeMS: syncedRightTextNextStartTimeMS
                    )
                }
            }
        }
        .frame(width: geometry.totalWidth, height: geometry.height)
        .onAppear {
            resetTimelineAnchor()
        }
        .onChange(of: snapshot.elapsed) { _, _ in
            resetTimelineAnchor()
        }
        .onChange(of: snapshot.state) { _, _ in
            resetTimelineAnchor()
        }
        .onChange(of: currentLyricText) { _, _ in
            resetTimelineAnchor()
        }
    }

    @ViewBuilder
    private func foregroundPromptLeft(_ prompt: ForegroundAppPrompt) -> some View {
        switch foregroundPromptDisplayMode {
        case .applicationName:
            foregroundAppIcon(prompt)
        case .memoryUsage:
            foregroundMemoryLabel()
        }
    }

    @ViewBuilder
    private func foregroundPromptRight(_ prompt: ForegroundAppPrompt) -> some View {
        switch foregroundPromptDisplayMode {
        case .applicationName:
            foregroundAppName(prompt)
        case .memoryUsage:
            foregroundMemoryValue(prompt)
        }
    }

    private func foregroundAppIcon(_ prompt: ForegroundAppPrompt) -> some View {
        promptSlot {
            if let icon = prompt.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.90))
            }
        }
    }

    private func foregroundAppName(_ prompt: ForegroundAppPrompt) -> some View {
        promptSlot {
            CompactPromptMarqueeText(
                text: prompt.appName,
                font: .system(size: 9.4, weight: .semibold, design: .rounded),
                foregroundColor: Color.white.opacity(0.90)
            )
        }
    }

    private func foregroundMemoryLabel() -> some View {
        promptSlot {
            Text("内存")
                .font(.system(size: 8.6, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.26, green: 0.73, blue: 1.0))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func foregroundMemoryValue(_ prompt: ForegroundAppPrompt) -> some View {
        promptSlot {
            Text(prompt.memoryText)
                .font(.system(size: 8.6, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
    }

    private func promptSlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 2)
        .scaleEffect(statusContentScale)
    }

    private var cameraWidth: CGFloat {
        max(0, geometry.cameraZoneWidth)
    }

    private var sideWidth: CGFloat {
        max(0, geometry.sideWidth)
    }

    private var presentation: CompactMusicPresentation? {
        CompactMusicPresentation.resolve(
            showsTrackName: showsTrackName,
            showsLyrics: showsLyrics,
            track: CompactMusicTrackSnapshot(
                isLive: snapshot.isLive,
                title: snapshot.title,
                artist: snapshot.artist
            ),
            currentLyric: currentLyricText,
            nextLyric: nextLyricText
        )
    }

    private var syncedRightTextStartTimeMS: TimeInterval? {
        guard showsTrackName, showsLyrics else { return nil }
        return currentLyricStartTimeMS
    }

    private var syncedRightTextNextStartTimeMS: TimeInterval? {
        guard showsTrackName, showsLyrics else { return nil }
        return nextLyricStartTimeMS
    }

    private func resetTimelineAnchor() {
        anchorDate = Date()
        anchorElapsed = snapshot.elapsed
    }

    private func sideZoneLayout<Left: View, Right: View>(
        placement: SideZonePlacement = .centered,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        let leftAlignment: Alignment
        let rightAlignment: Alignment
        switch placement {
        case .centered:
            leftAlignment = .center
            rightAlignment = .center
        case .lyrics:
            leftAlignment = .center
            rightAlignment = .center
        case .notchAdjacent:
            leftAlignment = .trailing
            rightAlignment = .leading
        }
        let leftRegion = sideRegion(.left, placement: placement)
        let rightRegion = sideRegion(.right, placement: placement)

        return ZStack {
            left()
                .frame(width: leftRegion.width, height: geometry.height, alignment: leftAlignment)
                .position(x: leftRegion.midX, y: geometry.height / 2)

            Color.clear
                .frame(width: cameraWidth, height: geometry.height)
                .position(x: geometry.totalWidth / 2, y: geometry.height / 2)

            right()
                .frame(width: rightRegion.width, height: geometry.height, alignment: rightAlignment)
                .position(x: rightRegion.midX, y: geometry.height / 2)
        }
        .frame(width: geometry.totalWidth, height: geometry.height)
        .clipped()
    }

    private enum SideZonePlacement {
        case centered
        case lyrics
        case notchAdjacent
    }

    private enum SideZone {
        case left
        case right
    }

    private struct SideRegion {
        let minX: CGFloat
        let maxX: CGFloat

        var width: CGFloat {
            max(1, maxX - minX)
        }

        var midX: CGFloat {
            (minX + maxX) / 2
        }
    }

    private func sideRegion(
        _ side: SideZone,
        placement: SideZonePlacement
    ) -> SideRegion {
        let notchLeftX = geometry.totalWidth / 2 - cameraWidth / 2
        let notchRightX = geometry.totalWidth / 2 + cameraWidth / 2

        switch placement {
        case .centered:
            let outerInset = statusOuterContentInset
            switch side {
            case .left:
                return normalizedRegion(
                    minX: outerInset,
                    maxX: notchLeftX
                )
            case .right:
                return normalizedRegion(
                    minX: notchRightX,
                    maxX: geometry.totalWidth - outerInset
                )
            }
        case .lyrics:
            let outerInset = lyricsOuterContentInset
            switch side {
            case .left:
                return normalizedRegion(minX: outerInset, maxX: notchLeftX)
            case .right:
                return normalizedRegion(minX: notchRightX, maxX: geometry.totalWidth - outerInset)
            }
        case .notchAdjacent:
            switch side {
            case .left:
                return normalizedRegion(minX: 0, maxX: notchLeftX)
            case .right:
                return normalizedRegion(minX: notchRightX, maxX: geometry.totalWidth)
            }
        }
    }

    private func normalizedRegion(minX: CGFloat, maxX: CGFloat) -> SideRegion {
        let clampedMinX = min(max(0, minX), geometry.totalWidth)
        let clampedMaxX = min(max(clampedMinX + 1, maxX), geometry.totalWidth)
        return SideRegion(minX: clampedMinX, maxX: clampedMaxX)
    }

    private var visibleOuterSideInset: CGFloat {
        max(
            0,
            min(
                max(0, sideWidth - 1),
                min(IslandDesignTokens.compactSideInset, geometry.totalWidth / 4)
            )
        )
    }

    private var statusOuterContentInset: CGFloat {
        max(
            visibleOuterSideInset,
            min(
                max(0, sideWidth - 1),
                sideWidth * 0.26
            )
        )
    }


    private var lyricsOuterContentInset: CGFloat {
        min(max(0, sideWidth - 1), 14)
    }

    @ViewBuilder
    private func adaptiveStatusText(primary: String, fallback: String) -> some View {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFallback = !trimmedFallback.isEmpty && trimmedFallback != trimmedPrimary
        let truncationText = hasFallback ? trimmedFallback : trimmedPrimary

        ViewThatFits(in: .horizontal) {
            statusText(trimmedPrimary)
                .fixedSize(horizontal: true, vertical: false)

            if hasFallback {
                statusText(trimmedFallback)
                    .fixedSize(horizontal: true, vertical: false)
            }

            statusText(truncationText)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.80))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func sideStatus(_ item: SettingsHomeSideIcon) -> some View {
        if item == .none || !item.isVisible(context: sideStatusContext) {
            Color.clear
        } else if item == .network {
            VStack(alignment: .leading, spacing: 0) {
                networkLine(
                    systemName: "arrow.up",
                    value: compactSpeedText(sideStatusContext.deviceInfo.uploadBytesPerSecond),
                    color: Color(red: 0.30, green: 0.93, blue: 0.42)
                )
                networkLine(
                    systemName: "arrow.down",
                    value: compactSpeedText(sideStatusContext.deviceInfo.downloadBytesPerSecond),
                    color: item.accentColor
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if item == .cpu || item == .memory || item == .disk {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Text(compactUsageTitle(for: item))
                        .font(.system(size: 6.8, weight: .bold, design: .rounded))
                        .foregroundStyle(item.accentColor)
                    Text(item.statusText(context: sideStatusContext))
                        .font(.system(size: 8.2, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(item.accentColor)
                            .frame(width: max(4, proxy.size.width * compactUsageProgress(for: item)))
                    }
                }
                .frame(width: 34, height: 2.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(spacing: 5) {
                Image(systemName: item.icon(context: sideStatusContext))
                    .font(.system(size: 11.2, weight: .heavy))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.accentColor)
                    .frame(width: 13, height: 13)
                    .shadow(color: item.accentColor.opacity(0.42), radius: 2.2)
                Text(item.statusText(context: sideStatusContext))
                    .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .layoutPriority(1)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func compactUsageTitle(for item: SettingsHomeSideIcon) -> String {
        switch item {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .disk: "DSK"
        default: ""
        }
    }

    private func compactUsageProgress(for item: SettingsHomeSideIcon) -> Double {
        let text = item.statusText(context: sideStatusContext).replacingOccurrences(of: "%", with: "")
        return min(max((Double(text) ?? 0) / 100, 0), 1)
    }

    private func networkLine(systemName: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 7.4, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 8)
            Text(value)
                .font(.system(size: 7.8, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func compactSpeedText(_ bytesPerSecond: UInt64) -> String {
        let value = Double(bytesPerSecond)
        if value >= 1_000_000_000 {
            return String(format: "%.1fG/s", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM/s", value / 1_000_000)
        }
        return String(format: "%.0fK/s", value / 1_000)
    }
}

private struct CompactPromptMarqueeText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let font: Font
    let foregroundColor: Color

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false
    @State private var animationToken = UUID()

    private let gap: CGFloat = 18
    private let speed: CGFloat = 18
    private let overflowTolerance: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let canScroll = !reduceMotion && textWidth > availableWidth + overflowTolerance

            ZStack(alignment: .leading) {
                if canScroll {
                    HStack(spacing: gap) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .offset(x: isAnimating ? -(textWidth + gap) : 0)
                } else {
                    Text(text)
                        .font(font)
                        .foregroundStyle(foregroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .frame(width: availableWidth, alignment: .center)
                }

                marqueeLabel
                    .opacity(0)
                    .background {
                        GeometryReader { textProxy in
                            Color.clear
                                .preference(
                                    key: CompactPromptTextWidthKey.self,
                                    value: textProxy.size.width
                                )
                        }
                    }
            }
            .frame(width: availableWidth, height: proxy.size.height, alignment: .leading)
            .clipped()
            .mask {
                if canScroll {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.14),
                            .init(color: .black, location: 0.86),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Rectangle()
                }
            }
            .onPreferenceChange(CompactPromptTextWidthKey.self) { width in
                textWidth = width
                restartMarquee(canScroll: !reduceMotion && width > availableWidth + overflowTolerance)
            }
            .onAppear {
                containerWidth = availableWidth
                restartMarquee(canScroll: canScroll)
            }
            .onChange(of: availableWidth) { _, width in
                containerWidth = width
                restartMarquee(canScroll: !reduceMotion && textWidth > width + overflowTolerance)
            }
            .onChange(of: text) { _, _ in
                restartMarquee(canScroll: canScroll)
            }
            .onChange(of: reduceMotion) { _, _ in
                restartMarquee(canScroll: canScroll)
            }
            .onDisappear {
                animationToken = UUID()
            }
        }
        .frame(height: 14)
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func restartMarquee(canScroll: Bool) {
        animationToken = UUID()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isAnimating = false
        }

        guard canScroll, textWidth > 0 else { return }

        let token = animationToken
        let distance = textWidth + gap
        let duration = max(2.4, Double(distance / speed))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard token == animationToken else { return }
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

private struct CompactPromptTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SyncedCompactLyricText: View {
    let text: String
    let anchorDate: Date
    let anchorElapsed: TimeInterval
    let isPlaying: Bool
    let lineStartTimeMS: TimeInterval?
    let nextLineStartTimeMS: TimeInterval?

    var body: some View {
        GeometryReader { proxy in
            let viewWidth = max(1, proxy.size.width)
            let textWidth = LyricTextMeasurer.width(of: text)
            let distance = max(0, textWidth - viewWidth)
            let endRevealInset = endRevealInset(viewWidth: viewWidth, textWidth: textWidth)

            TimelineView(.animation) { timeline in
                let progress = scrollProgress(at: timeline.date)

                progressCompactLyricText(progress: progress, textWidth: textWidth)
                    .frame(width: textWidth, alignment: .leading)
                    .offset(
                        x: lyricOffset(
                            viewWidth: viewWidth,
                            textWidth: textWidth,
                            endRevealInset: endRevealInset,
                            progress: progress
                        )
                    )
            }
            .frame(
                width: viewWidth,
                height: proxy.size.height,
                alignment: distance > 0 ? .leading : .center
            )
            .mask {
                if distance > 0 {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.82), location: 0),
                            .init(color: .black, location: 0.10),
                            .init(color: .black, location: 0.90),
                            .init(color: .black.opacity(0.18), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                } else {
                    Color.black
                }
            }
            .clipped()
        }
    }

    private func progressCompactLyricText(progress: Double, textWidth: CGFloat) -> some View {
        let revealedWidth = max(0, textWidth * CGFloat(progress))

        return ZStack(alignment: .leading) {
            compactLyricText(color: Color.white.opacity(0.84))
            compactLyricText(color: Color(red: 0.20, green: 0.88, blue: 0.48))
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                            .frame(width: revealedWidth)
                        Spacer(minLength: 0)
                    }
                }
        }
    }

    private func compactLyricText(color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func endRevealInset(viewWidth: CGFloat, textWidth: CGFloat) -> CGFloat {
        let overflow = max(0, textWidth - viewWidth)
        guard overflow > 0 else { return 0 }
        return min(18, max(10, viewWidth * 0.10))
    }

    private func lyricOffset(
        viewWidth: CGFloat,
        textWidth: CGFloat,
        endRevealInset: CGFloat,
        progress: Double
    ) -> CGFloat {
        let overflow = max(0, textWidth - viewWidth)
        guard overflow > 0 else { return 0 }
        return -(overflow + endRevealInset) * CGFloat(progress)
    }

    private func scrollProgress(at date: Date) -> Double {
        guard !text.isEmpty, let lineStartTimeMS else {
            return 0
        }

        let elapsed = isPlaying
            ? anchorElapsed + date.timeIntervalSince(anchorDate)
            : anchorElapsed
        let elapsedMS = elapsed * 1000 + lyricProgressLeadTimeMS
        let progress = (elapsedMS - lineStartTimeMS) / progressDurationMS(from: lineStartTimeMS)
        return min(max(progress, 0), 1)
    }

    private var lyricProgressLeadTimeMS: TimeInterval {
        300
    }

    private func progressDurationMS(from lineStartTimeMS: TimeInterval) -> TimeInterval {
        let nextGap = max(1000, (nextLineStartTimeMS ?? lineStartTimeMS + 4500) - lineStartTimeMS)
        let visibleCharacterCount = max(1, text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }.count)
        let estimatedSingingDuration = max(TimeInterval(visibleCharacterCount) * 260 + 900, 1900)
        let intervalAwareDuration = max(estimatedSingingDuration, nextGap * 0.55)
        return min(nextGap, min(intervalAwareDuration, 6500))
    }
}
