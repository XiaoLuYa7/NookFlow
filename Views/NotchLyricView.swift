import SwiftUI

struct NotchLyricView: View {
    let geometry: NotchGeometry
    let scale: CGFloat
    let snapshot: PlaybackSnapshot
    let currentLyricText: String?
    let nextLyricStartTimeMS: TimeInterval?

    @State private var scrollStartTime: Date?
    @State private var animatableOffset: CGFloat = 0

    var body: some View {
        Color.clear
        .frame(width: geometry.totalWidth, height: geometry.height)
        .scaleEffect(scale, anchor: .top)
        .overlay {
            if snapshot.isLive, let text = currentLyricText, !text.isEmpty {
                lyricContent(text: text)
            }
        }
        .onChange(of: currentLyricText) { _, _ in
            restartAnimation()
        }
    }

    // MARK: - Lyric Content

    @ViewBuilder
    private func lyricContent(text: String) -> some View {
        if geometry.hasNotch {
            notchLayout(text: text)
        } else {
            flatLayout(text: text)
        }
    }

    // MARK: - No Notch: Centered with edge fade

    private func flatLayout(text: String) -> some View {
        let textW = LyricTextMeasurer.width(of: text)
        let viewW = geometry.totalWidth - 20
        let needsScroll = textW > viewW

        return TimelineView(.animation) { timeline in
            let progress = currentProgress(at: timeline.date)

            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: needsScroll ? flatOffset(progress: progress, textW: textW, viewW: viewW) : 0)
                .opacity(needsScroll ? flatOpacity(progress: progress) : 1)
                .mask {
                    if needsScroll {
                        NotchLyricMask.flatMask(width: viewW)
                    } else {
                        Color.white
                    }
                }
        }
        .frame(width: viewW, height: geometry.height, alignment: .center)
        .padding(.horizontal, 10)
    }

    // MARK: - Notch: Dual-zone sliding

    private func notchLayout(text: String) -> some View {
        let textW = LyricTextMeasurer.width(of: text)
        let viewW = geometry.totalWidth - 20

        return TimelineView(.animation) { timeline in
            let progress = currentProgress(at: timeline.date)
            let offset = scrollOffset(progress: progress, textW: textW, viewW: viewW)
            let opacity = scrollOpacity(progress: progress)

            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
                .opacity(opacity)
                .mask { NotchLyricMask.notchMask(geometry: geometry) }
        }
        .frame(width: geometry.totalWidth, height: geometry.height)
        .clipped()
        .padding(.horizontal, 10)
    }

    // MARK: - Scroll Math (Notch)

    /// Start position: right edge of visible area + text shows from right.
    private var scrollStartX: CGFloat {
        geometry.totalWidth / 2
    }

    /// End position: text fully exited left.
    private func scrollEndX(textWidth: CGFloat) -> CGFloat {
        -(textWidth / 2 + geometry.totalWidth / 2)
    }

    /// Total distance from start to end.
    private func scrollDistance(textWidth: CGFloat) -> CGFloat {
        scrollStartX - scrollEndX(textWidth: textWidth)
    }

    /// Current offset based on animation progress.
    private func scrollOffset(progress: Double, textW: CGFloat, viewW: CGFloat) -> CGFloat {
        let startX = scrollStartX
        let endX = scrollEndX(textWidth: textW)
        return startX + (endX - startX) * progress
    }

    /// Fade in at start, fade out near end.
    private func scrollOpacity(progress: Double) -> Double {
        if progress < 0.08 { return progress / 0.08 }
        if progress > 0.92 { return (1.0 - progress) / 0.08 }
        return 1.0
    }

    // MARK: - Scroll Math (Flat / No Notch)

    private func flatOffset(progress: Double, textW: CGFloat, viewW: CGFloat) -> CGFloat {
        let startX = viewW / 2
        let endX = -(textW / 2 + viewW / 2)
        return startX + (endX - startX) * progress
    }

    private func flatOpacity(progress: Double) -> Double {
        if progress < 0.1 { return progress / 0.1 }
        if progress > 0.9 { return (1.0 - progress) / 0.1 }
        return 1.0
    }

    // MARK: - Time-Synced Progress

    private func currentProgress(at now: Date) -> Double {
        guard let start = scrollStartTime else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        let duration = scrollDuration()
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    private func scrollDuration() -> Double {
        guard let text = currentLyricText, !text.isEmpty else { return 2 }

        let textW = LyricTextMeasurer.width(of: text)
        let viewW = geometry.totalWidth - 20
        let distance = geometry.hasNotch
            ? scrollDistance(textWidth: textW)
            : textW + viewW

        // Use singing time if available
        if let nextStart = nextLyricStartTimeMS {
            let remaining = nextStart / 1000 - snapshot.elapsed
            if remaining > 0.5 {
                return max(1.5, remaining)
            }
        }

        // Fallback: proportional to distance (~40pt/s)
        return max(1.5, Double(distance) / 40.0)
    }

    // MARK: - Animation Control

    private func restartAnimation() {
        scrollStartTime = Date()
        animatableOffset = 1
    }
}
