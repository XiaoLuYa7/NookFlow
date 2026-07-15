# Reminder EventKit Crash Design

## Goal

Prevent the EventKit `NSInvalidArgumentException` raised by `EKReminderStore remindersMatchingPredicate:` while preserving reminder creation, completion, restoration, deletion, and synchronization behavior.

## Evidence

- Xcode's exception backtrace ends in `-[EKReminderStore remindersMatchingPredicate:]` on `com.apple.eventkit.reminders.search`.
- One island activation currently starts an incomplete-reminder fetch and a todo synchronization fetch at the same time.
- The synchronization path creates fresh `EKEventStore` instances and may issue separate incomplete and completed queries.
- Apple recommends a single `EKEventStore` instance for reminder-related work because initialization and release are expensive.

## Design

- Keep one shared `EKEventStore` for all `ReminderProvider` instances.
- Fetch all reminders once with `predicateForReminders(in:)` and the store's explicit reminder calendars.
- Filter completed and incomplete reminders in Swift after the single fetch.
- Remove the redundant `reminderProvider.start()` call from island provider refresh; todo synchronization already requests access and loads the required data.
- Avoid starting the unused summary refresh after todo-specific create, complete, restore, and delete operations because callers immediately update or synchronize their todo models.
- Retain summary refresh behavior for the legacy summary-specific add and complete methods.

## Concurrency And Performance

- EventKit fetch remains asynchronous and does not block the main thread.
- Existing cancellation handling remains in place.
- The change reduces EventKit stores and fetch requests; it adds no timers, polling, caches, or long-lived tasks.

## Verification

- Add a focused source-contract test requiring one shared store, one all-reminders query, Swift-side completion filtering, and no island-start duplicate query.
- Run the focused test and a Debug Xcode build without launching NookFlow.
