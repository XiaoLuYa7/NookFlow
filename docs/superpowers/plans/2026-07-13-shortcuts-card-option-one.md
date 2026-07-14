# Shortcut Card Option One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the selected compact NookFlow shortcut card with a count header, semantic blue command icons, and a dashed add row.

**Architecture:** Keep shortcut execution and persistence in `ShortcutsStore`. Limit visual changes to `ShortcutsCardView` and suppress the shared module header for shortcuts so the selected card can own its title and configured count.

**Tech Stack:** SwiftUI, SF Symbols, XCTest source-contract regression tests.

## Global Constraints

- Do not change shortcut execution, persistence, slot count, or module width.
- Do not fetch or cache system shortcut icons.
- Use deterministic name-based SF Symbol fallback and the existing NookFlow blue accent.
- Do not launch NookFlow during verification.

---

### Task 1: Compact Shortcut Card

**Files:**
- Modify: `Views/ShortcutsCardView.swift`
- Modify: `Views/ExpandedIslandView.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: `ShortcutsStore.slots`, `ShortcutsStore.run(_:)`, `ShortcutsStore.isRunning(_:)`, and `IslandSettings.shortcutsSettingsTrigger`.
- Produces: `ShortcutsCardView` with a local count header, semantic symbol resolver, compact command rows, and dashed add rows.

- [x] **Step 1: Write the failing visual contract test**

  Assert that the source contains the selected header count, semantic symbol lookup, dashed add-row stroke, and no random color palette.

- [x] **Step 2: Run the focused test and verify RED**

  Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter ShortcutsCardPresentationContractTests`

  Expected: the new assertions fail against the old random-gradient pill implementation.

- [x] **Step 3: Implement the selected card**

  Replace the two random-gradient capsules with a local header, compact configured rows, and dashed empty rows. Resolve the SF Symbol from stable name keywords and fall back to `bolt.fill`.

- [x] **Step 4: Verify GREEN and build**

  Run the focused test, the complete Swift test suite, `git diff --check`, and an Xcode Debug build using a `/private/tmp` DerivedData path.
