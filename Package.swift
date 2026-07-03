// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookFlowRegressionTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "NookFlowCore",
            path: ".",
            sources: [
                "Models/CalendarProvider.swift",
                "Models/CompactMusicPresentation.swift",
                "Models/LyricsCacheModel.swift",
                "Models/LyricsModels.swift",
                "Models/LyricsNetworkService.swift",
                "Models/LyricsParser.swift",
                "Models/LyricsProvider.swift",
                "Models/PlaybackProvider.swift",
                "Models/TodoViewModel.swift",
                "TestsSupport/PlaybackSettingsStub.swift",
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
