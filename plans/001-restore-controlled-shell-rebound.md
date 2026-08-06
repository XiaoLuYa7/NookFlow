# 001 — Restore a controlled shell rebound

- **Status**: DONE
- **Commit**: 1f9cf38
- **Severity**: MEDIUM
- **Category**: Easing & duration; Physicality & origin; Cohesion & tokens
- **Estimated scope**: 4 files, about 70 lines

## Problem

The opening shell currently moves from one large overshoot directly back to the
expanded size. That removed the small below-target correction which made the
island feel elastic. Both tracks also finish the peak with zero velocity and
then spend the entire correction budget returning monotonically, so the large
shape appears to hang at its maximum size instead of breathing into place.

```swift
// Views/IslandRootView.swift:200 — current width track
KeyframeTrack(\.widthProgress) {
    CubicKeyframe(
        bounce.widthOvershoot,
        duration: timing.widthExpansion,
        startVelocity: widthLaunchVelocity,
        endVelocity: 0
    )
    CubicKeyframe(
        1,
        duration: timing.widthSettle,
        startVelocity: 0,
        endVelocity: 0
    )
}
```

The product setting still promises an end-of-motion micro-rebound, so the
current two-keyframe motion no longer matches the control's meaning.

```swift
// Views/GeneralSettingsView.swift:184 — current product wording
subtitle: "控制动画结束时的微回弹，保持形体稳定和克制",
```

The regression contract explicitly forbids the intended rebound and would
reject its restoration.

```swift
// Tests/RegressionTests.swift:1455 — current contract
XCTAssertFalse(settings.contains("undershootScale"))
XCTAssertFalse(rootView.contains("undershootWidthProgress"))
XCTAssertFalse(rootView.contains("undershootHeightProgress"))
```

## Target

Use five spatial states without restoring the old pause at the target size:

1. Current compact or hover-preview geometry.
2. Direct overshoot; do not insert a `1.0` waypoint before it.
3. One very small undershoot below `1.0`.
4. One smaller overshoot which carries the rebound's inertia.
5. Final settle at exactly `1.0`.

Restore the repository's previous, already-tuned undershoot levels exactly:

```swift
// Models/IslandSettings.swift — target
var undershootScale: CGFloat {
    switch self {
    case .subtle: 0.999
    case .standard: 0.996
    case .lively: 0.993
    }
}
```

Reduce the overshoot so the rebound reads as a small breath instead of a large
window-scale jump:

```swift
// Models/IslandSettings.swift — target
// width:  subtle 1.015, standard 1.035, lively 1.055
// height: subtle 1.010, standard 1.025, lively 1.040
// settling overshoot: subtle 1.002, standard 1.005, lively 1.008
```

Use explicit phase durations so reaching the first peak is deliberate, crossing
the target is quick, and the smaller final oscillation decays slowly:

```swift
// Views/IslandDesignTokens.swift — target timing model
struct ShellOpenTiming {
    let expansion: TimeInterval
    let rebound: TimeInterval
    let recovery: TimeInterval
    let settle: TimeInterval

    var total: TimeInterval { expansion + rebound + recovery + settle }
    var widthExpansion: TimeInterval { expansion * 0.92 }
    var widthSettle: TimeInterval { total - widthExpansion - rebound - recovery }
    var contentRevealDelay: TimeInterval { expansion + rebound + recovery * 0.55 }
}

// Phase duration ranges
// expansion: 0.30...0.38
// rebound:  0.09...0.12
// recovery: 0.17...0.21
// settle:   0.14...0.18
```

For the default `openSpeed` of `0.59`, the phases are approximately `0.36s`,
`0.11s`, `0.20s`, and `0.17s`.

The target keyframe tracks are:

```swift
// Views/IslandRootView.swift — target
let undershootWidthProgress = bounce.undershootScale
let undershootHeightProgress = bounce.undershootScale
let settlingOvershootWidthProgress = bounce.settlingOvershootScale
let settlingOvershootHeightProgress = bounce.settlingOvershootScale

KeyframeTrack(\.widthProgress) {
    CubicKeyframe(
        bounce.widthOvershoot,
        duration: timing.widthExpansion,
        startVelocity: widthLaunchVelocity,
        endVelocity: 0
    )
    CubicKeyframe(
        undershootWidthProgress,
        duration: timing.rebound,
        startVelocity: 0,
        endVelocity: 0
    )
    CubicKeyframe(
        settlingOvershootWidthProgress,
        duration: timing.recovery,
        startVelocity: 0,
        endVelocity: 0
    )
    CubicKeyframe(
        1,
        duration: timing.widthSettle,
        startVelocity: 0,
        endVelocity: 0
    )
}

KeyframeTrack(\.heightProgress) {
    CubicKeyframe(
        bounce.heightOvershoot,
        duration: timing.expansion,
        startVelocity: heightLaunchVelocity,
        endVelocity: 0
    )
    CubicKeyframe(
        undershootHeightProgress,
        duration: timing.rebound,
        startVelocity: 0,
        endVelocity: 0
    )
    CubicKeyframe(
        settlingOvershootHeightProgress,
        duration: timing.recovery,
        startVelocity: 0,
        endVelocity: 0
    )
    CubicKeyframe(
        1,
        duration: timing.settle,
        startVelocity: 0,
        endVelocity: 0
    )
}
```

Do not change the reduced-motion branch. It must continue to use the direct
`.smooth(..., extraBounce: 0)` path without overshoot or undershoot.

## Repo conventions to follow

- Motion durations and geometry limits live in
  `Views/IslandDesignTokens.swift`; do not hard-code durations in the view.
- User-selectable motion personality lives in `IslandBounceLevel` in
  `Models/IslandSettings.swift`.
- `Views/IslandRootView.swift:190` already uses one compositor-driven
  `KeyframeAnimator` with independent width, height, and morph tracks.
- `Models/IslandViewModel.swift:577` is the existing interrupt/reduced-motion
  escape path and must remain unchanged.

## Steps

1. In `Models/IslandSettings.swift`, restore `undershootScale` with the exact
   `.999`, `.996`, and `.993` values shown above. Reduce width overshoot to
   `1.015 / 1.035 / 1.055` and height overshoot to
   `1.010 / 1.025 / 1.040`; add the smaller settling overshoot values shown
   above.
2. In `Views/IslandDesignTokens.swift`, give `ShellOpenTiming` explicit
   expansion, rebound, recovery, and settle durations using the listed ranges.
3. In `Views/IslandRootView.swift`, add the below-target correction and smaller
   settling-overshoot keyframes to both size tracks. Preserve direct
   compact-to-overshoot travel, the `0.92` width lead, and the existing morph
   track.
4. In `Tests/RegressionTests.swift`, rename
   `testOpeningUsesMomentumPhasesAndDecayingSettle`. Assert the phase durations,
   both overshoot levels, four size keyframes per axis, and an unchanged
   reduced-motion direct path.

## Boundaries

- Do NOT restore the old `1.0 -> overshoot` pair; the first size waypoint must
  remain the overshoot value.
- Do NOT change compact hover animation, close animation, content reveal
  durations, window geometry behavior, or drag-and-drop presentation.
- Do NOT change the reduced-motion path.
- Do NOT add timers, display links, polling, dependencies, or new view state.
- Do NOT touch unrelated existing worktree changes.
- If the code has drifted from commit `1f9cf38` or the excerpts above, stop and
  report the conflict instead of improvising.

## Verification

- **Mechanical**:
  - Run `git diff --check`; expect no output and exit code `0`.
  - Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project /Users/lucky/Projects/Personal/NookFlow/NookFlow.xcodeproj -scheme NookFlow -configuration Debug -derivedDataPath /private/tmp/NookFlowDerivedData build`; expect `BUILD SUCCEEDED`.
  - Run `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --scratch-path /private/tmp/NookFlowSwiftBuildXcode --filter IslandExpansionSmoothnessContractTests`; expect all selected tests to pass.
- **Feel check**:
  - Record the island opening at 60 fps and compare it frame-by-frame with
    `/Users/lucky/Movies/Videos/Jietu20260612-164301-HD.mp4`.
  - At 25% playback speed, confirm the shell travels directly past the target,
    crosses just below it once, and returns once. There must be no pause at the
    target before overshoot and no second oscillation after final settle.
  - Confirm width peaks before height, producing one restrained squash-and-
    stretch beat instead of uniform scaling.
  - Trigger collapse during every phase. The shell must retarget from its
    current geometry without snapping to the beginning of the open animation.
  - Test `克制`, `自然`, and `轻弹`: all three must share the same rhythm while
    only rebound amplitude changes.
  - Enable macOS Reduce Motion. Opening must use the direct smooth transition
    with no overshoot or undershoot, while opacity feedback remains.
- **Done when**: normal motion has exactly one overshoot, one micro-undershoot,
  and one final settle; reduced motion has none; no extra layout loop or
  long-lived task is introduced.
