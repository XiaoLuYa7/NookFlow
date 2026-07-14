# New Todo Sheet Design QA

- Source visual truth: `/var/folders/01/6c79mhb54t3960yc52tjqhmc0000gn/T/codex-clipboard-3b09eb37-3adf-403d-ada0-e4e3d39091c1.png`
- Intended implementation: `NewTodoSheetView` in `Views/TodoView.swift`
- Implementation screenshot: `NookFlow settings implementation screenshot, 2026-07-10 18:02`
- Viewport: macOS settings window, approximately 900 x 450 in the captured debug instance
- State: settings scene opened from the application menu

## Full-View Comparison Evidence

The source mockup opened successfully. The debug application launched, but its SwiftUI `Settings` scene intentionally contains `EmptyView`; the captured implementation evidence therefore shows only the empty system settings window and cannot represent `NewTodoSheetView`.

## Focused Region Comparison Evidence

Focused comparison was not possible because the target sheet was not rendered in the captured debug window. A temporary preview route was prepared and then fully reverted when the environment blocked the required rebuild.

## Findings

- [P1] Rendered implementation evidence is unavailable.
  - Evidence: the captured settings window is blank while the source contains the complete new-todo form.
  - Impact: typography, spacing, control alignment, and visual fidelity cannot be honestly approved from a screenshot.
  - Fix: launch the normal in-app Todo settings flow or run a dedicated preview build when build execution is available, then capture the 620 x 700 sheet and compare it with the source.

## Required Fidelity Surfaces

- Fonts and typography: implemented with native system fonts and explicit hierarchy; visual comparison blocked.
- Spacing and layout rhythm: implemented with fixed sheet dimensions, stable control heights, and section spacing; visual comparison blocked.
- Colors and visual tokens: implemented with the existing `AppColor` palette plus the existing accent gradient; visual comparison blocked.
- Image quality and asset fidelity: no raster assets are required; native SF Symbols are used as in-product icons.
- Copy and content: Chinese labels and the original form structure are preserved.

## Comparison History

- Initial capture: application menu opened the intentionally empty SwiftUI settings scene.
- Investigation: confirmed `NookFlowApp` defines `Settings { EmptyView() }` and the real settings flow is managed elsewhere.
- Preview attempt: a temporary debug route was added, but rebuild execution was blocked by environment limits; the route was immediately reverted.

## Implementation Checklist

- Capture the actual in-app `NewTodoSheetView` at 620 x 700.
- Compare header, input card, schedule card, settings card, and footer against the source.
- Correct any P0/P1/P2 mismatches before changing this result.

final result: blocked
