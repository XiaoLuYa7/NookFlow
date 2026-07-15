# Island Final Settle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the final opening rebound displacement and narrow its speed variation while preserving the existing overall opening duration.

**Architecture:** Keep the existing `KeyframeAnimator` and four-phase opening sequence. Change only the final undershoot constants and compute the final settle duration from a narrow independent range, then distribute the remaining total duration across the first three phases using their existing relative weights.

**Tech Stack:** SwiftUI, XCTest, SwiftPM, Xcode

## Global Constraints

- Do not launch NookFlow.
- Keep the total opening duration controlled by the existing speed setting.
- Keep primary overshoot, closing animation, content reveal, runtime activation, and reduced-motion behavior unchanged.
- Add no timers, polling, tasks, or per-frame calculations.
- Modify only animation timing/constants and their regression coverage.

---

### Task 1: Lock the reduced final settle behavior

**Files:**
- Modify: `Tests/RegressionTests.swift`

- [x] Add a failing test requiring undershoot scales `0.999`, `0.996`, and `0.993`.
- [x] Require independent settle bounds of `0.18` and `0.22` seconds.
- [x] Require the first three phase durations to use the remaining total duration.
- [x] Run the focused test and verify it fails for the old values and proportional settle timing.

### Task 2: Reduce displacement and narrow final-settle speed

**Files:**
- Modify: `Models/IslandSettings.swift`
- Modify: `Views/IslandDesignTokens.swift`

- [x] Replace only the three undershoot scales with the approved reduced values.
- [x] Add final-settle minimum and maximum duration constants.
- [x] Compute final settle from the independent range.
- [x] Allocate the remaining duration across the first three phases at the existing normalized ratio.
- [x] Run the focused test and verify it passes.

### Task 3: Verify

- [x] Run the focused SwiftPM regression test with the Xcode beta toolchain.
- [x] Run the Debug Xcode build without launching NookFlow.
- [x] Run `git diff --check` and inspect the final diff.
