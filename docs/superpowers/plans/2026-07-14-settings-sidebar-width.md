# Settings Sidebar Width Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the expanded settings sidebar from 208pt to 184pt without changing its collapsed layout or animation sequence.

**Architecture:** Keep `SidebarView` as the sole owner of sidebar width and update only its expanded width constant. Extend the existing source-contract tests to prevent regressions.

**Tech Stack:** SwiftUI, XCTest, SwiftPM, Xcode

## Global Constraints

- Do not launch NookFlow.
- Keep collapsed width at 60pt.
- Do not change row height, typography, icons, window size, or collapse timing.
- Do not modify files unrelated to the settings sidebar.

---

### Task 1: Lock the target width

**Files:**
- Modify: `Tests/RegressionTests.swift`

- [x] Add a failing assertion requiring `.frame(width: isCollapsed ? 60 : 184)` and rejecting the old 208pt value.
- [x] Run `swift test --filter SettingsLayoutContractTests/testSidebarUsesCompactExpandedWidth` and verify it fails.

### Task 2: Reduce the expanded width

**Files:**
- Modify: `Views/SettingsAppShell.swift`

- [x] Change only the expanded sidebar width from 208pt to 184pt.
- [x] Run the focused test and verify it passes.

### Task 3: Verify

- [x] Run the full SwiftPM regression suite.
- [x] Run the Debug Xcode build without launching NookFlow.
- [x] Run `git diff --check` and inspect the final diff.
