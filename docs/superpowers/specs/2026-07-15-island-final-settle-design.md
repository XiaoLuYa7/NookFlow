# Island Final Settle Design

## Goal

Reduce the visible displacement and speed variation of the final opening rebound so the island settles smoothly without changing the main expansion pace or the closing animation.

## Root Cause

The final keyframe currently moves from `IslandBounceLevel.undershootScale` back to `1.0`. Its duration is always 29% of the total opening duration, so the final settle varies from roughly 0.16 seconds to 0.24 seconds across speed presets. The lively preset also starts the final settle at `0.984`, which produces about 14 points of width movement on a 900-point island.

## Design

- Keep the existing four opening phases and keyframe animator.
- Map the final settle independently to a narrow `0.18...0.22` second range.
- Preserve the existing total opening duration by distributing the remaining time across the first three phases in their current relative proportions.
- Reduce final undershoot scales to:
  - subtle: `0.999`
  - standard: `0.996`
  - lively: `0.993`
- Do not change primary overshoot values, speed preset values, closing animation, content reveal, runtime activation, or reduced-motion behavior.

## Performance

The change only adjusts existing keyframe constants and timing calculations. It adds no timers, tasks, polling, view refreshes, or allocations during animation.

## Verification

- Add regression coverage for the reduced undershoot values.
- Add regression coverage for the independent final-settle duration range and preserved total duration.
- Run the focused regression test, the full SwiftPM suite, and a Debug Xcode build without launching NookFlow.
