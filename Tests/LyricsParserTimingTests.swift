import XCTest
@testable import NookFlowCore

final class LyricsParserTimingTests: XCTestCase {
    func testPositiveLRCOffsetMovesLineLater() throws {
        let lyrics = LyricsParser.parse(
            """
            [offset:400]
            [00:01.00]第一句
            """,
            format: .netEase
        )

        let line = try XCTUnwrap(lyrics.first)
        XCTAssertEqual(line.startTimeMS, 1_400, accuracy: 0.001)
    }

    func testNegativeLRCOffsetNeverProducesNegativeTime() throws {
        let lyrics = LyricsParser.parse(
            """
            [offset:-800]
            [00:00.50]第一句
            """,
            format: .netEase
        )

        let line = try XCTUnwrap(lyrics.first)
        XCTAssertEqual(line.startTimeMS, 0, accuracy: 0.001)
    }

    func testNetEaseWordLyricsPreserveExactUnitTiming() throws {
        let lyrics = LyricsParser.parse(
            """
            [1000,1800](1200,400,0)你(1700,500,0)好
            [3000,1000](3000,1000,0)下一句
            """,
            format: .netEaseWord
        )

        let line = try XCTUnwrap(lyrics.first)
        XCTAssertEqual(line.startTimeMS, 1_000, accuracy: 0.001)
        XCTAssertEqual(line.words, "你好")
        XCTAssertTrue(line.hasExactWordTiming)
        XCTAssertEqual(line.timedUnits?.map(\.text), ["你", "好"])
        XCTAssertEqual(line.timedUnits?.map(\.startTimeMS), [1_200, 1_700])
        XCTAssertEqual(line.timedUnits?.map(\.durationMS), [400, 500])
    }

    func testOffsetAlsoMovesExactWordTimestamps() throws {
        let lyrics = LyricsParser.parse(
            """
            [offset:250]
            [1000,1800](1200,400,0)你(1700,500,0)好
            """,
            format: .netEaseWord
        )

        let line = try XCTUnwrap(lyrics.first)
        XCTAssertEqual(line.startTimeMS, 1_250, accuracy: 0.001)
        XCTAssertEqual(line.timedUnits?.map(\.startTimeMS), [1_450, 1_950])
    }
}
