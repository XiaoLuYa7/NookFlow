# Remove Calendar Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the standalone EventKit calendar card and its Home customization setting while preserving every todo-card setting and date-selection behavior.

**Architecture:** Delete the calendar card vertically from provider through persistence, island rendering, layout, Home customization, permissions, tests, and project membership. Keep reminder EventKit access and all todo/reminder date UI untouched; stale saved `calendar` module-order values are ignored by existing enum decoding.

**Tech Stack:** Swift 6, SwiftUI, AppKit, EventKit reminders, XCTest, Xcode project files.

## Global Constraints

- Do not change todo-card rendering, todo settings, reminder synchronization, date pickers, or calendar popovers.
- Keep `ReminderProvider` and EventKit reminder permission behavior.
- Keep ordinary `Calendar.current` date calculations outside the removed card.
- Do not launch NookFlow during verification.
- Run only focused tests, source-contract lint, and one Debug build.

---

### Task 1: Lock the Removal Boundary With a Focused Contract Test

**Files:**
- Modify: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: repository source files resolved from the test target.
- Produces: `CalendarCardRemovalContractTests` proving calendar-card code is absent and todo date UI remains present.

- [ ] **Step 1: Add a failing source-contract test**

Add assertions that `Models/CalendarProvider.swift` exists before removal, then invert the production expectations: project and production files must not contain `CalendarProvider`, `showCalendarModule`, `calendarStyle`, `IslandPanelModule.calendar`, or `NSCalendarsFullAccessUsageDescription`. Also assert `ReminderInlineCalendarPicker` and `TodoDarkCalendarPopover` remain.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/NookFlowSwiftPMCache \
CLANG_MODULE_CACHE_PATH=/private/tmp/NookFlowClangCache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter CalendarCardRemovalContractTests
```

Expected: FAIL because standalone calendar-card sources and settings still exist.

### Task 2: Remove Calendar Data, Persistence, and Permission Surface

**Files:**
- Delete: `Models/CalendarProvider.swift`
- Modify: `Models/IslandSettings.swift`
- Modify: `NookFlow.xcodeproj/project.pbxproj`
- Modify: `Views/AboutView.swift`
- Modify: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: `IslandSettings` and Xcode source membership.
- Produces: no calendar event provider, calendar-card settings, calendar permission usage string, or obsolete snapshot tests.

- [ ] **Step 1: Delete provider and obsolete tests**

Delete `CalendarProvider`, `CalendarSnapshot`, `CalendarEventSummary`, and tests that directly exercise those removed types. Preserve `ReminderEventKitQueryContractTests` and `Models/ReminderProvider.swift`.

- [ ] **Step 2: Remove calendar-card persistence**

Remove `CalendarStyle`, `showCalendarModule`, `calendarStyle`, their `UserDefaults` keys, initialization, reset behavior, and saves. Do not migrate or rewrite `moduleOrder`; unknown raw values already decode away.

- [ ] **Step 3: Remove project and privacy declarations**

Remove all `CalendarProvider.swift` PBX references and both `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` entries. Rewrite About privacy copy to describe reminders only while retaining EventKit in the Apple-framework list because reminders still use it.

### Task 3: Remove Calendar Rendering and Home Customization

**Files:**
- Modify: `Views/ExpandedIslandView.swift`
- Modify: `Views/IslandShellLayout.swift`
- Modify: `Panel/IslandWindowController.swift`
- Modify: `Views/SettingsRootView.swift`

**Interfaces:**
- Consumes: remaining `IslandPanelModule` and `SettingsWidget` cases.
- Produces: island and Home customization flows with no standalone calendar option, provider lifecycle, preview, width rule, or rendering branch.

- [ ] **Step 1: Remove island calendar lifecycle and UI**

Delete calendar provider/state, provider start-stop hooks, setting observers, module switch cases, calendar-specific sizing, all calendar-card subviews/helpers, and the `IslandPanelModule.calendar` case. Before deleting helper structs/extensions, confirm they have no non-card callers.

- [ ] **Step 2: Remove layout and window subscriptions**

Delete calendar visibility/width branches from `IslandShellLayout` and remove `$showCalendarModule` from the window controller's settings observation chain without changing remaining publisher behavior.

- [ ] **Step 3: Remove only the Home calendar option**

Delete `SettingsWidget.calendar`, its enabled-state synchronization, preview mapping/content/thumbnail, and available-widget entry. Keep the “自定义首页” control and every remaining widget unchanged.

### Task 4: Update Contracts and Verify the Focused Surface

**Files:**
- Modify: `scripts/source_contract_lint.sh`
- Modify: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: completed production deletion.
- Produces: automated protection against restoring the removed calendar card or accidentally deleting todo date UI.

- [ ] **Step 1: Replace the obsolete source contract**

Remove the requirement that `showCalendarModule` starts a provider. Add forbidden checks for `CalendarProvider`, `showCalendarModule`, `calendarStyle`, calendar permission text, and the calendar module case; add positive checks for `ReminderInlineCalendarPicker` and `TodoDarkCalendarPopover`.

- [ ] **Step 2: Run focused GREEN verification**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/NookFlowSwiftPMCache \
CLANG_MODULE_CACHE_PATH=/private/tmp/NookFlowClangCache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter CalendarCardRemovalContractTests
./scripts/source_contract_lint.sh
```

Expected: focused test and source-contract lint pass.

- [ ] **Step 3: Build without launching the app**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -quiet \
  -project NookFlow.xcodeproj \
  -scheme NookFlow \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/NookFlowCalendarRemovalDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: exit code 0 and a built NookFlow executable. Do not run or open it.

- [ ] **Step 4: Inspect the scoped diff**

Run:

```bash
git diff --check
rg -n "CalendarProvider|showCalendarModule|calendarStyle|NSCalendarsFullAccessUsageDescription" Models Views Panel NookFlow.xcodeproj/project.pbxproj
rg -n "ReminderInlineCalendarPicker|TodoDarkCalendarPopover|showTodoModule" Views Models
```

Expected: no removed calendar-card symbols; todo date UI and todo module settings remain.
