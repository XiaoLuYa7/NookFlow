# Remove Tutorial Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completely remove the island tutorial hint feature and its persisted settings without affecting other island behavior.

**Architecture:** Delete the feature vertically from settings UI, settings state, persistence, and island runtime rendering. A focused source-contract test locks the absence of all feature symbols and user-facing copy.

**Tech Stack:** Swift, SwiftUI, XCTest, SwiftPM, Xcode

## Global Constraints

- Do not launch NookFlow.
- Do not change unrelated settings, island transitions, pinning, or module behavior.
- Do not add migration work for legacy `UserDefaults`; old values remain inert.
- Run only the focused regression test and a Debug build.

---

### Task 1: Lock the removal contract

**Files:**
- Modify: `Tests/RegressionTests.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: source files under `Models/` and `Views/`.
- Produces: `TutorialHintRemovalContractTests.testTutorialHintFeatureIsCompletelyRemoved()`.

- [x] **Step 1: Add the failing source-contract test**

```swift
final class TutorialHintRemovalContractTests: XCTestCase {
    func testTutorialHintFeatureIsCompletelyRemoved() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: root.appendingPathComponent("Models/IslandSettings.swift"),
            encoding: .utf8
        )
        let generalSettings = try String(
            contentsOf: root.appendingPathComponent("Views/GeneralSettingsView.swift"),
            encoding: .utf8
        )
        let islandRoot = try String(
            contentsOf: root.appendingPathComponent("Views/IslandRootView.swift"),
            encoding: .utf8
        )

        for source in [settings, generalSettings, islandRoot] {
            XCTAssertFalse(source.contains("TutorialHint"))
            XCTAssertFalse(source.contains("tutorialHint"))
            XCTAssertFalse(source.contains("教学引导提示"))
        }
        XCTAssertFalse(settings.contains("hasShownTutorialHint"))
        XCTAssertFalse(islandRoot.contains("功能提示"))
    }
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/NookFlowSwiftPMCache \
CLANG_MODULE_CACHE_PATH=/private/tmp/NookFlowClangCache \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift test --filter TutorialHintRemovalContractTests/testTutorialHintFeatureIsCompletelyRemoved
```

Expected: FAIL because the current source still contains `TutorialHintPolicy`, tutorial settings copy, and the island tutorial overlay.

### Task 2: Remove settings and runtime implementation

**Files:**
- Modify: `Models/IslandSettings.swift`
- Modify: `Views/GeneralSettingsView.swift`
- Modify: `Views/IslandRootView.swift`
- Test: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: the removal contract from Task 1.
- Produces: settings and island runtime with no tutorial feature symbols, tasks, or UI.

- [x] **Step 1: Remove tutorial settings state and persistence**

Delete from `Models/IslandSettings.swift`:

```swift
enum TutorialHintPolicy: String, CaseIterable, Identifiable { ... }
@Published var tutorialHintPolicy: TutorialHintPolicy { ... }
@Published private(set) var hasShownTutorialHint: Bool
tutorialHintPolicy = TutorialHintPolicy(...) ?? .once
hasShownTutorialHint = ...
tutorialHintPolicy = .once
hasShownTutorialHint = false
save(hasShownTutorialHint, for: Keys.hasShownTutorialHint)
static let tutorialHintPolicy = "settings.tutorialHintPolicy"
static let hasShownTutorialHint = "settings.hasShownTutorialHint"
func markTutorialHintShown() { ... }
```

- [x] **Step 2: Remove the General Settings row**

Delete this `SettingsSegmentedRow` from `Views/GeneralSettingsView.swift`:

```swift
SettingsSegmentedRow(
    icon: nil,
    title: "教学引导提示",
    subtitle: "控制灵动岛下方功能提示的显示策略",
    options: TutorialHintPolicy.allCases,
    optionTitle: \TutorialHintPolicy.title,
    selection: $settings.tutorialHintPolicy
)
```

- [x] **Step 3: Remove island tutorial runtime code**

Delete from `Views/IslandRootView.swift`:

```swift
@State private var isTutorialHintVisible = false
updateTutorialHintVisibility()
.onChange(of: settings.tutorialHintPolicy) { ... }
tutorialHintOverlay(canvasSize: canvasSize)
private func tutorialHintOverlay(canvasSize: CGSize) -> some View { ... }
private func updateTutorialHintVisibility() { ... }
private func setTutorialHintVisible(_ visible: Bool) { ... }
private struct IslandTutorialHintView: View { ... }
```

Keep the existing `externalPinButtonOverlay`, presentation-phase refresh, shell layout, and other runtime providers unchanged.

- [x] **Step 4: Run the focused test and verify GREEN**

Run the Task 1 command again.

Expected: PASS with one executed test and zero failures.

### Task 3: Compile and inspect

**Files:**
- Inspect: `Models/IslandSettings.swift`
- Inspect: `Views/GeneralSettingsView.swift`
- Inspect: `Views/IslandRootView.swift`
- Inspect: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: completed source removal.
- Produces: compile and diff evidence only.

- [x] **Step 1: Build the macOS app without launching it**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -quiet -project NookFlow.xcodeproj -scheme NookFlow \
-configuration Debug -derivedDataPath /private/tmp/NookFlowDerivedData build
```

Expected: exit code 0.

- [x] **Step 2: Check formatting and remaining feature references**

```bash
git diff --check
rg -n "TutorialHint|tutorialHint|教学引导提示|功能提示" \
Models/IslandSettings.swift Views/GeneralSettingsView.swift Views/IslandRootView.swift
```

Expected: `git diff --check` exits 0 and `rg` returns no matches.
