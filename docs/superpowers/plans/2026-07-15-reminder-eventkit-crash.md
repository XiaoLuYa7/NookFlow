# Reminder EventKit Crash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop duplicate multi-store EventKit reminder searches that trigger an internal `NSMutableArray` nil insertion exception.

**Architecture:** Reuse one shared `EKEventStore`, query all reminder calendars once, and filter completion state in Swift. Remove redundant summary fetches from the island todo workflow while retaining existing write operations and cancellation behavior.

**Tech Stack:** Swift, SwiftUI, EventKit, XCTest, SwiftPM, Xcode

## Global Constraints

- Do not launch NookFlow.
- Do not change reminder write semantics or user data.
- Keep EventKit queries asynchronous and cancellable.
- Add no polling, timers, or third-party dependencies.
- Run focused tests rather than the full regression suite.

---

### Task 1: Lock the safe EventKit query contract

**Files:**
- Modify: `Tests/RegressionTests.swift`

- [x] Require exactly one `EKEventStore()` construction in `ReminderProvider.swift`.
- [x] Require `predicateForReminders(in:)` with explicit reminder calendars.
- [x] Reject separate incomplete and completed predicate queries in the synchronization section.
- [x] Reject `reminderProvider.start()` in the island refresh path.
- [x] Run the focused test and verify it fails against the current implementation.

### Task 2: Consolidate reminder queries

**Files:**
- Modify: `Models/ReminderProvider.swift`
- Modify: `Views/ExpandedIslandView.swift`

- [x] Replace the instance and temporary stores with one shared store.
- [x] Add one all-reminders fetch helper using explicit reminder calendars.
- [x] Filter completion state after the fetch.
- [x] Suppress summary refreshes for todo-specific write methods.
- [x] Remove the redundant island `start()` call.
- [x] Run the focused test and verify it passes.

### Task 3: Verify

- [x] Run a Debug Xcode build without launching NookFlow.
- [x] Run `git diff --check` and inspect the focused diff.
