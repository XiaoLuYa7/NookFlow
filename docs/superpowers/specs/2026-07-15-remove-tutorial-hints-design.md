# Remove Tutorial Hints Design

## Goal

Completely remove NookFlow's island tutorial hint feature without changing unrelated settings or island behavior.

## Scope

- Remove the tutorial hint policy control from General Settings.
- Remove `TutorialHintPolicy`, `hasShownTutorialHint`, their persistence keys, reset behavior, and mutation helpers.
- Remove tutorial visibility state, update callbacks, overlay rendering, tutorial views, tip models, and the automatic rotation task from `IslandRootView`.
- Leave existing legacy `UserDefaults` values untouched. They become inert and are no longer read or written.

## Runtime Behavior

The island no longer creates, displays, animates, or schedules tutorial content. Expansion, collapse, pinning, module content, and settings behavior remain unchanged.

## Verification

- Add a focused source-contract test proving tutorial UI, model state, persistence keys, and runtime overlay code are absent.
- Run that focused test.
- Run a Debug Xcode build without launching NookFlow.
- Run `git diff --check` and inspect only the affected files.

