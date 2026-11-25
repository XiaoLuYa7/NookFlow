import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import NookFlowCore

final class PlaybackSourceSelectionTests: XCTestCase {
    @MainActor
    func testSimulationPlaybackRemainsInactiveAfterLifecycleAndTransportRequests() async throws {
        let provider = PlaybackProvider(settings: IslandSettings(), isMonitoringEnabled: false)
        provider.start()
        provider.togglePlayback()
        provider.nextTrack()
        provider.previousTrack()
        provider.seek(to: 0.5)
        provider.updateAccessConfiguration(from: IslandSettings())
        provider.stop()
        provider.start()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(provider.snapshot, .idle)
        XCTAssertTrue(provider.diagnosticText.isEmpty)
        provider.stop()
    }

    private func player(_ name: String, state: PlaybackState = .playing) -> PlaybackSnapshot {
        var snapshot = PlaybackSnapshot.idle
        snapshot.appName = name
        snapshot.state = state
        return snapshot
    }

    func testCurrentPlayingSourceSurvivesHigherPriorityPlayerAndStreamRefresh() {
        let candidates = [player("Music"), player("Spotify"), player("QQ音乐")]
        XCTAssertEqual(PlaybackProvider.selectSnapshot(from: candidates, preferredAppName: "QQ音乐")?.appName, "QQ音乐")
        XCTAssertEqual(PlaybackProvider.selectSnapshot(from: candidates, preferredAppName: nil)?.appName, "Music")
    }

    func testPausedOrExitedSourceYieldsToFirstPlayingPlayer() {
        let candidates = [player("Music", state: .paused), player("Spotify"), player("QQ音乐")]
        XCTAssertEqual(PlaybackProvider.selectSnapshot(from: candidates, preferredAppName: "Music")?.appName, "Spotify")
        XCTAssertEqual(PlaybackProvider.selectSnapshot(from: candidates, preferredAppName: "网易云音乐")?.appName, "Spotify")
        XCTAssertNil(PlaybackProvider.selectSnapshot(from: [], preferredAppName: "Music"))
    }

    func testNoPlayingSourceKeepsDeterministicFallback() {
        let candidates = [player("Music", state: .paused), player("Spotify", state: .paused)]
        XCTAssertEqual(PlaybackProvider.selectSnapshot(from: candidates, preferredAppName: "Spotify")?.appName, "Music")
    }
}

final class FileClassificationAndScanTests: XCTestCase {
    func testCategoriesUseTypeIdentifiersAndOtherIsExclusive() {
        let examples: [(UTType, FileCategory)] = [
            (.pdf, .document), (.plainText, .document), (.rtf, .document),
            (.png, .image), (.movie, .video), (.mp3, .audio),
            (.zip, .other), (.application, .other)
        ]
        for (type, expected) in examples {
            XCTAssertEqual(FileCategory.category(typeIdentifier: type.identifier, isDirectory: false), expected)
        }
        XCTAssertEqual(FileCategory.category(typeIdentifier: UTType.folder.identifier, isDirectory: true), .other)
        XCTAssertEqual(FileCategory.category(typeIdentifier: "", isDirectory: false), .other)
    }

    func testScanReturnsNamesWithoutWaitingForArtworkAndPropagatesMissingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("hello".utf8).write(to: directory.appendingPathComponent("note.txt"))
        let items = try await FileDataProvider.scanDirectory(directory)
        XCTAssertEqual(items.map(\.name), ["note.txt"])
        XCTAssertNil(items.first?.thumbnail)
        XCTAssertEqual(items.first?.hasLoadedArtwork, false)
        XCTAssertTrue(FileCategory.document.matches(try XCTUnwrap(items.first)))
        XCTAssertFalse(FileCategory.other.matches(try XCTUnwrap(items.first)))
        do {
            _ = try await FileDataProvider.scanDirectory(directory.appendingPathComponent("missing"))
            XCTFail("A missing directory must not appear as an empty folder")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }
}


final class CompactLyricPairTests: XCTestCase {
    func testCapsuleWidthRespectsNotchSpaceAndScreenLimit() {
        XCTAssertEqual(CapsuleLyricsLayout.fittedWidth(600, cameraWidth: 200, maximumWidth: 900), 600)
        XCTAssertEqual(CapsuleLyricsLayout.fittedWidth(240, cameraWidth: 200, maximumWidth: 900), 400)
        XCTAssertEqual(CapsuleLyricsLayout.fittedWidth(1000, cameraWidth: 0, maximumWidth: 620), 620)
    }

    func testInvalidCapsulePreferencesRecoverToUsableValues() {
        XCTAssertEqual(CapsuleLyricsLayout.clampedWidth(1000), 650)
        XCTAssertEqual(CapsuleLyricsLayout.clampedWidth(.nan), CapsuleLyricsLayout.defaultWidth)
        XCTAssertEqual(CapsuleLyricsLayout.clampedFontSize(.infinity), CapsuleLyricsLayout.defaultFontSize)
        XCTAssertEqual(CapsuleLyricsLayout.clampedFontSize(2), 9)
        XCTAssertEqual(CapsuleLyricsLayout.clampedFontSize(40), 13)
    }

    func testPairRemainsOnScreenThroughoutBothLinesAndThenAdvancesTogether() {
        let lines = (0..<5).map { LyricLine(startTimeMS: Double($0 * 5000), words: "Line \($0)") }
        XCTAssertEqual(CompactLyricPair.resolve(at: 0, in: lines), .init(leftIndex: 0, rightIndex: 1))
        XCTAssertEqual(CompactLyricPair.resolve(at: 1, in: lines), .init(leftIndex: 0, rightIndex: 1))
        XCTAssertEqual(CompactLyricPair.resolve(at: 2, in: lines), .init(leftIndex: 2, rightIndex: 3))
        XCTAssertEqual(CompactLyricPair.resolve(at: 3, in: lines), .init(leftIndex: 2, rightIndex: 3))
        XCTAssertEqual(CompactLyricPair.resolve(at: 4, in: lines), .init(leftIndex: 4, rightIndex: nil))
        XCTAssertNil(CompactLyricPair.resolve(at: nil, in: lines))
        XCTAssertNil(CompactLyricPair.resolve(at: 9, in: lines))
    }

    func testEmptyLinesDoNotOccupyEitherSideAndTranslationOnlyLinesRemainVisible() {
        let lines = [LyricLine(startTimeMS: 0, words: ""),
                     LyricLine(startTimeMS: 1000, words: "Left"),
                     LyricLine(startTimeMS: 2000, words: "  "),
                     LyricLine(startTimeMS: 3000, words: "", translation: "Right"),
                     LyricLine(startTimeMS: 4000, words: "Next")]
        XCTAssertNil(CompactLyricPair.resolve(at: 0, in: lines))
        XCTAssertEqual(CompactLyricPair.resolve(at: 2, in: lines), .init(leftIndex: 1, rightIndex: 3))
        XCTAssertEqual(CompactLyricPair.resolve(at: 3, in: lines), .init(leftIndex: 1, rightIndex: 3))
        XCTAssertEqual(CompactLyricPair.resolve(at: 4, in: lines), .init(leftIndex: 4, rightIndex: nil))
    }

    func testHighlightProgressRemainsOnLeftUntilRightStarts() throws {
        let lines = [LyricLine(startTimeMS: 0, words: "Left", timedUnits: [
                        .init(text: "Left", startTimeMS: 0, durationMS: 5000)]),
                     LyricLine(startTimeMS: 5000, words: "Right", timedUnits: [
                        .init(text: "Right", startTimeMS: 5000, durationMS: 5000)])]
        let timeline = LyricTimingEstimator().estimate(lines: lines, songDuration: 10)
        let left = try XCTUnwrap(timeline.first)
        let right = try XCTUnwrap(timeline.last)
        XCTAssertFalse(left.revealState(at: 2.5).isComplete)
        XCTAssertEqual(right.revealState(at: 2.5).completedUTF16Offset, 0)
        XCTAssertTrue(left.revealState(at: 7.5).isComplete)
        XCTAssertFalse(right.revealState(at: 7.5).isComplete)
        XCTAssertTrue(right.revealState(at: 10).isComplete)
    }
}
