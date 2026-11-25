// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookFlowRegressionTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NookFlowCore",
            path: "Models",
            exclude: [
                "ApplicationLauncher.swift",
                "ApplicationsProvider.swift",
                "AppUpdateController.swift",
                "IslandSettings.swift",
                "IslandState.swift",
                "IslandViewModel.swift",
                "LyricTextMeasurer.swift",
                "ModuleDragController.swift",
                "NotchGeometryProvider.swift",
                "NotificationCoordinator.swift",
                "QuickAppItem.swift",
                "QuickAppsStore.swift",
                "ReminderProvider.swift",
                "ShortcutItem.swift",
                "ShortcutsStore.swift",
                "WeatherProvider.swift",
            ],
            sources: [
                "CompactMusicPresentation.swift",
                "FileDataProvider.swift",
                "LyricsCacheModel.swift",
                "LyricsModels.swift",
                "LyricsNetworkService.swift",
                "LyricsParser.swift",
                "LyricsProvider.swift",
                "LyricTimingEstimator.swift",
                "LicenseManager.swift",
                "NotificationRuntimePolicy.swift",
                "PlaybackProvider.swift",
                "MediaRemoteStreamBridge.swift",
                "PlaybackSettingsStub.swift",
                "TimelineRefreshPolicy.swift",
                "TodoCardSettingsStorage.swift",
                "TodoViewModel.swift",
            ]
        ),
        .testTarget(
            name: "NookFlowCoreTests",
            dependencies: ["NookFlowCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
