# Island Animation Pace Design

## Goal

Make the fast expansion and collapse preset less abrupt while keeping three clearly ordered pace choices.

## Pace Values

- Slow (`舒缓`): keep `0.68`.
- Balanced (`适中`): use `0.59`, halfway between the old slow and balanced values.
- Fast (`轻快`): use `0.50`, the old balanced value.

## State Mapping

- Values at or above `0.635` map to slow.
- Values at or below `0.545` map to fast.
- Intermediate values map to balanced.
- Fresh installs and reset-to-default use `0.59` so the settings UI remains on balanced.
- Persisted legacy fast values of `0.36` migrate once to `0.50`; other stored values remain unchanged.

## Scope

- Apply the same value to opening and closing speed.
- Do not change keyframe structure, bounce values, reduced-motion behavior, or animation duration mapping.
- Add no timers, tasks, polling, or additional refresh work.

## Verification

- Add a focused source-contract regression test for preset values, thresholds, and defaults.
- Run only the focused test and a Debug Xcode build without launching NookFlow.
