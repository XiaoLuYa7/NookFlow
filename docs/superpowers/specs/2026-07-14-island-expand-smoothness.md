# Island Expand Smoothness Design

## Goal

Eliminate the visible hitch in the final rebound of the dynamic-island opening animation without shortening the configured animation, increasing refresh frequency, or keeping background work alive while the island is collapsed.

## Root Cause

The final shell settle currently overlaps with several expensive operations:

- The expanded view mounts a large module tree at the start of opening.
- The root view starts weather, device, and playback providers as soon as the phase is no longer collapsed.
- The expanded view starts calendar, reminders, todo synchronization, and image loading from `onAppear`.
- The final content reveal applies blur, scale, opacity, and offset to the full panel and again to individual cards.
- Moving to `.expanded` triggers another provider refresh and forced todo synchronization.

These operations compete with SwiftUI's final keyframe layout and compositing work.

## Design

### Separate visual readiness from runtime readiness

`shouldMountExpandedContent` continues to control when expanded views exist and participate in the visual reveal. A new `isExpandedRuntimeActive` state controls when data providers and asynchronous content loading may run.

The runtime state becomes active only after the shell and content animations have fully settled, followed by one short cancellable handoff delay. Collapse, interrupted opening, and a new presentation generation cancel the pending activation immediately.

### Keep the final settle compositor-friendly

The opening reveal uses opacity and a small vertical offset only. Opening-specific blur and scale effects are removed from the whole expanded panel and individual module cards. Existing hover, playback, drag, and interaction animations are unchanged.

### Avoid duplicate activation work

Weather, device, playback, calendar, reminders, todo synchronization, and image loading consult runtime readiness. The transition to `.expanded` no longer performs a second unconditional provider refresh on the same visual completion frame.

### Lifecycle

- Collapsed: expanded runtime inactive; expanded-only providers stopped.
- Expanding/revealing: expanded content may be mounted for visual continuity; runtime remains inactive.
- Settled expanded: runtime activates after a cancellable one-shot delay.
- Hiding/collapsing/interrupted: pending activation is cancelled and expanded-only providers stop.

## Scope

Modify only:

- `Models/IslandViewModel.swift`
- `Views/IslandRootView.swift`
- `Views/ExpandedIslandView.swift`
- `Views/IslandDesignTokens.swift`
- `Tests/RegressionTests.swift`

No card sizing, module behavior, animation speed preference, polling interval, window dimensions, or application startup behavior changes.

## Verification

- Regression contract verifies runtime activation is separate from visual mounting and cancellable.
- Regression contract verifies opening reveal no longer uses blur/scale effects.
- Full SwiftPM regression suite passes.
- Debug Xcode build succeeds.
- NookFlow is not launched during verification.
