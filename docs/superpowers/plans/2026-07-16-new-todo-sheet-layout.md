# New Todo Sheet Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the settings new-todo sheet visually match the approved reference and preserve category/priority exactly like the island creation flow.

**Architecture:** Extend the existing `TodoTaskDraft` instead of introducing a second settings-only model. Reuse `TodoCategory`, `TodoPriority`, reminder tag serialization, and `TodoDateTimeInputParser`; use controlled numeric fields for date/time and a sheet-scoped AppKit event monitor to resign text-field focus on outside clicks.

**Tech Stack:** Swift 6, SwiftUI, EventKit, XCTest

## Global Constraints

- Keep the sheet width at `520pt`.
- Do not change the island new-todo UI.
- Do not launch NookFlow.
- Run focused verification only.

---

### Task 1: Preserve task attributes through creation

**Files:**
- Modify: `Models/TodoViewModel.swift`
- Modify: `Views/TodoView.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Produces: `TodoTaskDraft.category: TodoCategory`
- Produces: `TodoTaskDraft.priority: TodoPriority`
- Produces: `TodoTaskDraft.reminderCreationRequest.tagsText`

- [ ] Add a failing focused test for draft fields, local task creation, and reminder tag serialization.
- [ ] Run the focused test and confirm it fails because the fields and tags are absent.
- [ ] Add the two defaulted draft fields, pass them into `TodoTask`, and serialize non-empty tag values.
- [ ] Run the focused test and confirm it passes.

### Task 2: Recompose the sheet layout

**Files:**
- Modify: `Views/TodoView.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: `TodoCategory.allCases`, `TodoPriority.allCases`
- Produces: `taskAttributesSection`, full-width schedule rows, inline time presets

- [ ] Replace the obsolete compact-layout contract with a failing contract for the approved layout.
- [ ] Run the focused test and confirm it fails on the old two-column schedule.
- [ ] Add the task attributes section and replace `compactSchedulePanel` with two `sheetRow` schedule rows.
- [ ] Move preset buttons into the time row and conditionally expose custom hour/minute selectors.
- [ ] Run the focused contract, source lint, and Debug build without launching the app.

### Task 3: Replace long menus and fix custom-time focus

**Files:**
- Modify: `Views/TodoView.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: `TodoDateTimeInputParser.digitsOnly`, `parseDate`, and `parseTime`
- Produces: compact year/month/day fields, inline hour/minute fields, and `OutsideTextFieldFocusDismissal`

- [ ] Update the focused layout contract to reject `selectionMenu` and the system compact time `DatePicker`.
- [ ] Run the contract and confirm it fails against the old menu and picker implementation.
- [ ] Add numeric date and custom-time fields without reformatting valid edits.
- [ ] Add a local mouse-down monitor that resigns an active `NSTextField` only when clicking outside it, and remove the monitor when the sheet disappears.
- [ ] Run the focused contract, source lint, and Debug build without launching the app.
