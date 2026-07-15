# Settings Sidebar Width Design

## Goal

Reduce the expanded settings sidebar width so the main content has more room while preserving the current navigation hierarchy and collapse behavior.

## Design

- Change expanded width from `208pt` to `184pt`.
- Keep collapsed width at `60pt`.
- Keep icon size, row height, typography, horizontal padding, selection background, and vertical positions unchanged.
- Keep the existing two-stage collapse behavior: labels fade before width contraction and return after expansion.
- Do not change the settings window size or content layout.

## Verification

- A regression contract locks the expanded and collapsed widths.
- Existing sidebar animation and layout contracts continue to pass.
- SwiftPM tests and the Debug Xcode build pass without launching NookFlow.
