# Remove Calendar Card Design

## Goal

Completely remove NookFlow's standalone EventKit calendar card and its Home customization option without affecting todo date selection or ordinary date calculations.

## Removed Surface

- The calendar card module, its card layouts, styles, drag behavior, and previews.
- `CalendarProvider`, EventKit calendar reads, calendar change observers, and calendar authorization requests.
- Calendar-card settings, persistence keys, reset behavior, and module ordering entries.
- The calendar item in Home customization and its enabled-state synchronization.
- Calendar access usage descriptions and calendar-specific privacy copy.
- Source contracts and tests that require the standalone calendar card.

## Preserved Surface

- Home customization itself and all remaining module choices.
- Todo and reminder date pickers, calendar popovers, due-date parsing, and date formatting.
- `Calendar.current` calculations used by weather, progress, reminders, todos, and other non-card features.
- Reminder access through EventKit.

## Runtime Behavior

The island no longer constructs a calendar provider, requests calendar permission, observes calendar changes, or renders a calendar module. Existing saved module orders may still contain the raw string `calendar`; module-order decoding safely ignores unknown values.

## Verification

- Add a focused source-contract test proving the provider, module case, settings, Home customization item, project references, and calendar permission description are absent.
- Run the focused test through a red-green cycle.
- Run the source contract lint and a Debug Xcode build without launching NookFlow.
- Run `git diff --check` and inspect only the affected files.
