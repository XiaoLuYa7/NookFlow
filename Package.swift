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
                "FileDataProvider.swift",
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
                "CalendarProvider.swift",
                "CompactMusicPresentation.swift",
                "LyricsCacheModel.swift",
                "LyricsModels.swift",
                "LyricsNetworkService.swift",
                "LyricsParser.swift",
                "LyricsProvider.swift",
                "NotificationRuntimePolicy.swift",
                "PlaybackProvider.swift",
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
