import XCTest
@testable import NookFlowCore

final class LyricTimingEstimatorTests: XCTestCase {
    private let estimator = LyricTimingEstimator()

    func testChineseLineCreatesOneVocalUnitPerCharacter() {
        let line = estimate("我曾经跨过山和大海", duration: 4)
        let vocalUnits = line.units.filter { $0.kind.isVocal }

        XCTAssertEqual(vocalUnits.count, 9)
        XCTAssertEqual(vocalUnits.map(\.text).joined(), "我曾经跨过山和大海")
        XCTAssertGreaterThan(line.vocalEndTime, line.lineStartTime)
        XCTAssertLessThanOrEqual(line.vocalEndTime, line.lineEndTime)
    }

    func testLongGapKeepsAFullGreenRestAfterFinalHold() {
        let line = estimate("风吹过这片安静海岸", duration: 10)

        XCTAssertLessThanOrEqual(line.finalHoldDuration, 2.201)
        XCTAssertGreaterThan(line.trailingRestDuration, 0)
        XCTAssertLessThan(line.vocalEndTime, line.lineEndTime)
        XCTAssertTrue(line.revealState(at: line.vocalEndTime).isComplete)
    }

    func testSingleCharacterMayUseShortLineHoldLimit() {
        let line = estimate("啊", duration: 6)

        XCTAssertGreaterThan(line.finalHoldDuration, 2.2)
        XCTAssertLessThanOrEqual(line.finalHoldDuration, 3.001)
    }

    func testWaveEndingHoldsLongerThanSentenceEnding() {
        let wave = estimate("回来吧～", duration: 5)
        let sentence = estimate("回来吧。", duration: 5)

        XCTAssertGreaterThan(wave.finalHoldDuration, sentence.finalHoldDuration)
    }

    func testEnglishWordsAreIndependentVocalUnits() {
        let line = estimate("I really love you", duration: 4)
        let words = line.units
            .filter { $0.kind == .englishWord }
            .map(\.text)

        XCTAssertEqual(words, ["I", "really", "love", "you"])
    }

    func testMixedContentPreservesUnitOrderAndNumbers() {
        let line = estimate("第2次 say hello！", duration: 4)
        let vocalUnits = line.units.filter { $0.kind.isVocal }

        XCTAssertEqual(vocalUnits.map(\.text), ["第", "2", "次", "say", "hello"])
        XCTAssertEqual(vocalUnits.map(\.kind), [
            .chineseCharacter,
            .number,
            .chineseCharacter,
            .englishWord,
            .englishWord,
        ])
    }

    func testEarlierFollowingTimestampDoesNotProduceNegativeTiming() {
        let lines = [
            LyricLine(startTimeMS: 5_000, words: "第一句"),
            LyricLine(startTimeMS: 4_000, words: "异常时间"),
        ]
        let results = estimator.estimate(lines: lines, songDuration: 12)

        XCTAssertEqual(results.count, 2)
        for line in results {
            XCTAssertGreaterThan(line.lineEndTime, line.lineStartTime)
            XCTAssertGreaterThanOrEqual(line.vocalEndTime, line.lineStartTime)
            XCTAssertLessThanOrEqual(line.vocalEndTime, line.lineEndTime)
        }
    }

    func testPlaybackAnchorUsesMonotonicHostTime() {
        let anchor = PlaybackTimeAnchor(
            mediaTime: 12,
            playbackRate: 1,
            hostTime: 100
        )

        XCTAssertEqual(anchor.estimatedTime(at: 100.75), 12.75, accuracy: 0.001)
        XCTAssertEqual(anchor.estimatedTime(at: 99), 12, accuracy: 0.001)
    }

    func testEstimatedHighlightNeverStartsBeforeLineTimestamp() {
        let line = estimator.estimate(
            lines: [
                LyricLine(startTimeMS: 5_000, words: "还没有唱"),
                LyricLine(startTimeMS: 8_000, words: "下一句"),
            ],
            songDuration: 12
        )[0]

        let reveal = line.revealState(at: 4.999)

        XCTAssertEqual(LyricPlaybackTiming.revealOffset, 0)
        XCTAssertEqual(reveal.completedUTF16Offset, 0)
        XCTAssertNil(reveal.activeUnitRange)
        XCTAssertEqual(reveal.activeUnitProgress, 0)
    }

    func testExactWordTimingIsUsedInsteadOfEstimatedDistribution() {
        let lines = [
            LyricLine(
                startTimeMS: 1_000,
                words: "你好",
                timedUnits: [
                    LyricTimedUnit(text: "你", startTimeMS: 1_200, durationMS: 400),
                    LyricTimedUnit(text: "好", startTimeMS: 1_700, durationMS: 500),
                ]
            ),
            LyricLine(startTimeMS: 3_000, words: "下一句"),
        ]

        let line = estimator.estimate(lines: lines, songDuration: 6)[0]

        XCTAssertEqual(line.precision, .exactWord)
        XCTAssertEqual(line.units.map(\.startTime), [1.2, 1.7])
        XCTAssertEqual(line.units.map(\.endTime), [1.6, 2.2])
        XCTAssertNil(line.revealState(at: 1.1).activeUnitRange)
        XCTAssertEqual(
            line.revealState(at: 1.4).activeUnitProgress,
            0.5,
            accuracy: 0.001
        )
    }

    private func estimate(_ text: String, duration: TimeInterval) -> EstimatedLyricLine {
        let lines = [
            LyricLine(startTimeMS: 0, words: text),
            LyricLine(startTimeMS: duration * 1_000, words: "下一句"),
        ]
        return estimator.estimate(lines: lines, songDuration: duration + 3)[0]
    }
}
