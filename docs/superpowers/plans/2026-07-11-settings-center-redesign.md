# NookFlow Settings Center Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved premium, light macOS settings center across all eight NookFlow settings pages without changing existing business behavior.

**Architecture:** Upgrade the shared design tokens and settings primitives first, then compose the grouped shell and Dashboard from those primitives. Existing page models, stores, bindings, notification lifecycles, and Dynamic Island dark-surface tokens remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, Swift Package Manager, Xcode 26 beta.

---

### Task 1: Establish visual regression constraints

**Files:**
- Modify: `Tests/RegressionTests.swift`

- [ ] Add a source-level regression test that verifies the settings shell contains the three approved navigation groups and that the design system contains the approved page background, 16pt section radius, and reduced-motion path.
- [ ] Run `swift test --filter SettingsDesignContractTests` and verify the new assertions fail against the old shell.

### Task 2: Upgrade design tokens and shared settings primitives

**Files:**
- Modify: `Views/AppDesignSystem.swift`
- Modify: `Views/SettingsComponents.swift`

- [ ] Refine the neutral palette, low-saturation blue accent, spacing, type scale, shadows, control heights, focus feedback, switch styling, and motion durations.
- [ ] Add reusable status badge and preference group primitives so pages do not create nested cards or local color systems.
- [ ] Run `swift test --filter SettingsDesignContractTests` and verify the design-token assertions pass.

### Task 3: Implement the grouped macOS sidebar and stable page transitions

**Files:**
- Modify: `Views/SettingsAppShell.swift`
- Modify: `Views/SettingsRootView.swift`

- [ ] Replace the flat page list with `核心`, `自动化`, and `系统` groups while preserving every existing destination.
- [ ] Increase the expanded sidebar width, keep the collapsed state stable, add glass selection styling, and keep the collapse action pinned at the bottom.
- [ ] Replace the multi-branch transition layout with stable identity-based page presentation and reduced-motion-aware animation.
- [ ] Run `swift test --filter SettingsDesignContractTests` and verify navigation assertions pass.

### Task 4: Build the approved no-AI home Dashboard

**Files:**
- Modify: `Views/SettingsRootView.swift`

- [ ] Replace the existing home content with the approved Header, 今日概览 strip, 快速控制, 提醒服务, 系统脉搏, and 最近活动 sections.
- [ ] Bind only to existing settings/model data. Do not add polling, fabricated activity data, AI labels, or background services.
- [ ] Keep the existing Dynamic Island preview and customization controls reachable from the Dashboard.
- [ ] Build with `xcodebuild -project NookFlow.xcodeproj -scheme NookFlow -configuration Debug -derivedDataPath /private/tmp/NookFlowDerivedData build`.

### Task 5: Unify all settings pages

**Files:**
- Modify: `Views/GeneralSettingsView.swift`
- Modify: `Views/NotificationSettingsView.swift`
- Modify: `Views/QuickAppsSettingsView.swift`
- Modify: `Views/ShortcutsSettingsView.swift`
- Modify: `Views/AboutView.swift`
- Modify: `Views/TodoView.swift`

- [ ] Adopt the shared Header, Section, Row, status, button, toggle, and empty-state styling in each page.
- [ ] Remove page-local colors or component dimensions that conflict with the shared design system.
- [ ] Preserve Todo, drag-and-drop, shortcut running, notification settings, and general settings bindings exactly.
- [ ] Run `swift test` and the Debug Xcode build.

### Task 6: Visual and lifecycle verification

**Files:**
- Modify only if verification reveals a defect in the files above.

- [ ] Launch the Debug app and inspect the settings window at 900x580 and a common desktop size.
- [ ] Verify all eight destinations, keyboard focus, hover feedback, scrolling, reduced-motion behavior, and long Chinese labels.
- [ ] Confirm closing the settings window does not create new timers, listeners, or animation loops.
- [ ] Run `git diff --check`, `swift test`, and the Debug Xcode build as final evidence.
