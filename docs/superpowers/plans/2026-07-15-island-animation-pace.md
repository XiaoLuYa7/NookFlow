# Island Animation Pace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the overly fast animation preset with the old balanced speed and move the balanced preset halfway toward slow.

**Architecture:** Keep the existing `GeneralAnimationPace` binding and persisted `openSpeed`/`closeSpeed` properties. Update only the three preset responses, their reverse-mapping thresholds, and balanced defaults.

**Tech Stack:** SwiftUI, XCTest, SwiftPM, Xcode

## Global Constraints

- Do not launch NookFlow.
- Keep the three existing labels and option order.
- Apply identical values to opening and closing speed.
- Do not change animation keyframes or bounce parameters.
- Run focused tests rather than the full regression suite.

---

### Task 1: Lock the new pace mapping

**Files:**
- Modify: `Tests/RegressionTests.swift`

- [x] Add a test requiring responses `0.68`, `0.59`, and `0.50`.
- [x] Require reverse thresholds `0.635` and `0.545`.
- [x] Require initialization and reset defaults to use `0.59`.
- [x] Run the focused test and verify it fails against the old values.

### Task 2: Update pace values and defaults

**Files:**
- Modify: `Views/GeneralSettingsView.swift`
- Modify: `Models/IslandSettings.swift`

- [x] Update balanced and fast response values.
- [x] Update reverse-mapping thresholds.
- [x] Update fresh-install and reset defaults for opening and closing speed.
- [x] Migrate persisted legacy fast values from `0.36` to `0.50` during initialization.
- [x] Run the focused test and verify it passes.

### Task 3: Verify

- [x] Run a Debug Xcode build without launching NookFlow.
- [x] Run `git diff --check` and inspect the focused diff.
