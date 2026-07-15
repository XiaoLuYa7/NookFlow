# Island Expand Smoothness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the final-rebound hitch during island expansion by separating visual animation from expanded-only runtime work and simplifying reveal effects.

**Architecture:** `IslandViewModel` owns a cancellable runtime-activation phase that begins only after presentation settles. `IslandRootView` and `ExpandedIslandView` use that state to gate providers and asynchronous loading, while the visual content remains mounted independently for continuous animation.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Combine, XCTest, Swift concurrency

## Global Constraints

- Do not launch NookFlow during verification.
- Do not shorten the configured opening animation or change card/window dimensions.
- Do not add polling, permanent prewarming, third-party dependencies, or unbounded caches.
- Cancel delayed activation and expanded-only work when opening is interrupted or the island collapses.
- Do not commit changes unless the user explicitly requests a commit.

---

### Task 1: Lock the expansion lifecycle contract

**Files:**
- Modify: `Tests/RegressionTests.swift`

**Interfaces:**
- Consumes: `IslandViewModel.isExpandedRuntimeActive`, `ExpandedIslandView.runtimeIsActive`
- Produces: `IslandExpansionSmoothnessContractTests`

- [x] **Step 1: Add failing source-contract tests**

Add assertions that require a dedicated runtime state, a cancellable activation task, runtime-gated providers, and reveal code without opening blur or scale.

- [x] **Step 2: Run the focused test and verify failure**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter IslandExpansionSmoothnessContractTests
```

Expected: failure because the runtime state and simplified reveal are not implemented yet.

### Task 2: Add cancellable post-animation runtime activation

**Files:**
- Modify: `Models/IslandViewModel.swift`
- Modify: `Views/IslandDesignTokens.swift`

**Interfaces:**
- Produces: `@Published private(set) var isExpandedRuntimeActive: Bool`
- Produces: `IslandDesignTokens.expandedRuntimeActivationDelay`

- [x] **Step 1: Add runtime state and task ownership**

Add one cancellable `Task<Void, Never>` to `IslandViewModel`. Reset runtime state synchronously when expansion begins or collapse starts, and cancel the task from `deinit` and presentation cancellation paths.

- [x] **Step 2: Activate only after visual settlement**

At the end of the successful presentation generation, commit final visual state in one animation-disabled transaction, then schedule runtime activation after the one-shot token delay. Before activation, verify the task is current, not cancelled, and the phase is still `.expanded`.

- [x] **Step 3: Run the focused regression test**

Run the Task 1 command and expect the lifecycle assertions to pass while view-gating assertions remain failing until Task 3.

### Task 3: Gate expanded-only providers and image work

**Files:**
- Modify: `Views/IslandRootView.swift`
- Modify: `Views/ExpandedIslandView.swift`

**Interfaces:**
- Consumes: `IslandViewModel.isExpandedRuntimeActive`
- Produces: `ExpandedIslandView.runtimeIsActive`

- [x] **Step 1: Gate root providers**

Use runtime readiness instead of `presentationPhase != .collapsed` for expanded-only weather, device, and playback needs. Preserve compact-icon and compact-lyrics requirements so compact functionality continues working.

- [x] **Step 2: Gate expanded content providers**

Pass runtime readiness into `ExpandedIslandView`. Start calendar, reminders, todo synchronization, file refresh, and image loading only when active. Stop/cancel them when it becomes inactive. Keep `isContentReady` dedicated to visual reveal calculations.

- [x] **Step 3: Remove duplicate settled-phase refresh**

Keep calendar selection reset behavior, but remove the unconditional forced provider refresh tied directly to `.expanded`; runtime activation becomes the single owner.

- [x] **Step 4: Run focused tests**

Run the Task 1 command and expect all runtime lifecycle assertions to pass.

### Task 4: Simplify final reveal compositing

**Files:**
- Modify: `Views/ExpandedIslandView.swift`

**Interfaces:**
- Consumes: existing `contentRevealProgress` and `secondaryContentRevealProgress`
- Produces: opacity/offset-only opening reveal

- [x] **Step 1: Remove whole-panel opening blur and scale**

Keep opacity and the existing small vertical offset in `reveal(_:progress:offset:)`. Preserve reduced-motion and closing behavior.

- [x] **Step 2: Remove per-card opening blur and scale**

Keep background/content opacity and small offsets. Do not alter drag preview, hover, playback, or pressed-state effects.

- [x] **Step 3: Run focused tests**

Run the Task 1 command and expect the reveal assertions to pass.

### Task 5: Verify lifecycle, build, and formatting

**Files:**
- Verify only: all modified files

**Interfaces:**
- Produces: test and build evidence

- [x] **Step 1: Run the full regression suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

Expected: all tests pass.

- [x] **Step 2: Build the Debug app without launching it**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project NookFlow.xcodeproj -scheme NookFlow -configuration Debug -derivedDataPath /private/tmp/NookFlowExpandSmoothnessDerivedData build
```

Expected: `BUILD SUCCEEDED`.

- [x] **Step 3: Check patch hygiene and lifecycle risks**

Run `git diff --check`. Inspect that the activation task is cancelled from collapse, interruption, and deinitialization paths; confirm no timer or repeating task was added.
