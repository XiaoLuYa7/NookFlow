import SwiftUI

struct TodoCardSettingsStorage: DynamicProperty {
    @AppStorage(TodoCardStorageKeys.showDateSelector) var showDateSelector = TodoCardSettings.defaults.showDateSelector
    @AppStorage(TodoCardStorageKeys.showTime) var showTime = TodoCardSettings.defaults.showTime
    @AppStorage(TodoCardStorageKeys.showCategory) var showCategory = TodoCardSettings.defaults.showCategory
    @AppStorage(TodoCardStorageKeys.showCompleted) var showCompleted = TodoCardSettings.defaults.showCompleted
    @AppStorage(TodoCardStorageKeys.maxVisibleItems) var maxVisibleItems = TodoCardSettings.defaults.maxVisibleItems
    @AppStorage(TodoCardStorageKeys.defaultRange) var defaultRangeRaw = TodoCardSettings.defaults.defaultRange.rawValue
    @AppStorage(TodoCardStorageKeys.sortMode) var sortModeRaw = TodoCardSettings.defaults.sortMode.rawValue
    @AppStorage(TodoCardStorageKeys.highlightColor) var highlightColorRaw = TodoCardSettings.defaults.highlightColor.rawValue
    @AppStorage(TodoCardStorageKeys.useCompactMode) var useCompactMode = TodoCardSettings.defaults.useCompactMode
    @AppStorage(TodoCardStorageKeys.showEdgeGlow) var showEdgeGlow = TodoCardSettings.defaults.showEdgeGlow
    @AppStorage(TodoCardStorageKeys.showReminderBadge) var showReminderBadge = TodoCardSettings.defaults.showReminderBadge
    @AppStorage(TodoCardStorageKeys.dueSoonMinutes) var dueSoonMinutes = TodoCardSettings.defaults.dueSoonMinutes

    var defaultRange: TodoDefaultRange {
        TodoDefaultRange(rawValue: defaultRangeRaw) ?? TodoCardSettings.defaults.defaultRange
    }

    var sortMode: TodoSortMode {
        TodoSortMode(rawValue: sortModeRaw) ?? TodoCardSettings.defaults.sortMode
    }

    var highlightColor: TodoHighlightColor {
        TodoHighlightColor(rawValue: highlightColorRaw) ?? TodoCardSettings.defaults.highlightColor
    }

    var snapshot: TodoCardSettings {
        TodoCardSettings(
            showDateSelector: showDateSelector,
            showTime: showTime,
            showCategory: showCategory,
            showCompleted: showCompleted,
            maxVisibleItems: maxVisibleItems,
            defaultRange: defaultRange,
            sortMode: sortMode,
            highlightColor: highlightColor,
            useCompactMode: useCompactMode,
            showEdgeGlow: showEdgeGlow,
            showReminderBadge: showReminderBadge,
            dueSoonMinutes: dueSoonMinutes
        )
    }
}
