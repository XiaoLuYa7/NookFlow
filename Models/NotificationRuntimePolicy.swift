import Foundation

struct NotificationSettingsSnapshot: Equatable {
    var weather: WeatherNotificationSnapshot
    var device: DeviceNotificationSnapshot
    var dailyCare: DailyCareNotificationSnapshot

    init(
        weather: WeatherNotificationSnapshot = WeatherNotificationSnapshot(),
        device: DeviceNotificationSnapshot = DeviceNotificationSnapshot(),
        dailyCare: DailyCareNotificationSnapshot = DailyCareNotificationSnapshot()
    ) {
        self.weather = weather
        self.device = device
        self.dailyCare = dailyCare
    }
}

struct WeatherNotificationSnapshot: Equatable {
    var isEnabled = false
}

struct DeviceNotificationSnapshot: Equatable {
    var isEnabled = false
    var lowBatteryEnabled = false
    var fullChargeReminderEnabled = false
    var performanceAlertEnabled = false
    var storageAlertEnabled = false
    var networkStatusAlertEnabled = false

    var needsPeriodicChecks: Bool {
        isEnabled && (
            lowBatteryEnabled
                || fullChargeReminderEnabled
                || performanceAlertEnabled
                || storageAlertEnabled
        )
    }

    var needsNetworkMonitor: Bool {
        isEnabled && networkStatusAlertEnabled
    }
}

struct DailyCareNotificationSnapshot: Equatable {
    var isEnabled = false
    var waterReminderEnabled = false
    var sitReminderEnabled = false
    var sleepReminderEnabled = false

    var needsWaterProgressReset: Bool {
        isEnabled && waterReminderEnabled
    }

    var needsPeriodicChecks: Bool {
        isEnabled && (waterReminderEnabled || sitReminderEnabled || sleepReminderEnabled)
    }
}

struct NotificationRuntimeRequirements: Equatable {
    var needsPeriodicChecks: Bool
    var needsNetworkMonitor: Bool
    var needsWeatherSubscription: Bool

    static let inactive = NotificationRuntimeRequirements(
        needsPeriodicChecks: false,
        needsNetworkMonitor: false,
        needsWeatherSubscription: false
    )
}

enum NotificationRuntimePolicy {
    static func requirements(for settings: NotificationSettingsSnapshot) -> NotificationRuntimeRequirements {
        NotificationRuntimeRequirements(
            needsPeriodicChecks: settings.weather.isEnabled
                || settings.device.needsPeriodicChecks
                || settings.dailyCare.needsPeriodicChecks,
            needsNetworkMonitor: settings.device.needsNetworkMonitor,
            needsWeatherSubscription: settings.weather.isEnabled
        )
    }
}
