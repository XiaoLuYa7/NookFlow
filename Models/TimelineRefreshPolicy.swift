import Foundation

struct LyricTimelineState: Equatable {
    var isVisible: Bool
    var isPlaying: Bool
    var hasContent: Bool
    var needsScrolling: Bool
    var needsProgressAnimation: Bool = false
    var isTransitioning: Bool
}

enum WeatherTimelineKind: Equatable {
    case staticIcon
    case animatedIcon
}

enum TimelineRefreshPolicy {
    static func shouldUseContinuousLyricTimeline(_ state: LyricTimelineState) -> Bool {
        state.isVisible
            && state.hasContent
            && (
                state.isTransitioning
                    || (state.isPlaying && (state.needsScrolling || state.needsProgressAnimation))
            )
    }

    static func shouldUseContinuousWeatherTimeline(
        kind: WeatherTimelineKind,
        reduceMotion: Bool
    ) -> Bool {
        !reduceMotion && kind == .animatedIcon
    }
}
