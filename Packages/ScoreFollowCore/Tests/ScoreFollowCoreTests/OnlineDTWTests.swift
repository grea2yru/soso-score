import XCTest
@testable import ScoreFollowCore

final class OnlineDTWTests: XCTestCase {
    /// C장조 안에서 순환하는 3화음 8개 (인접 이벤트가 서로 다르게)
    let chords: [[Int]] = [[60,64,67],[62,65,69],[64,67,71],[65,69,72],[67,71,74],[69,72,76],[71,74,77],[72,76,79]]
    var templates: [Chroma] { chords.map(ScoreTemplateBuilder.template(for:)) }

    /// 각 이벤트를 framesPerEvent 프레임씩 재생한 크로마 스트림 (잡음 추가)
    func stream(framesPerEvent: [Int], noise: Float = 0.05) -> [Chroma] {
        var rng = SystemRandomNumberGenerator()
        var out: [Chroma] = []
        for (i, n) in framesPerEvent.enumerated() {
            for _ in 0..<n {
                let noisy = templates[i].values.map { $0 + Float.random(in: -noise...noise, using: &rng) }
                out.append(Chroma(values: noisy.map { max($0, 0) }).normalized())
            }
        }
        return out
    }

    func run(_ frames: [Chroma]) -> [Int] {
        var dtw = OnlineDTW(templates: templates)
        return frames.map { dtw.step($0) }
    }

    func testTracksNormalTempoMonotonically() {
        let path = run(stream(framesPerEvent: Array(repeating: 10, count: 8)))
        XCTAssertEqual(path.last, 7)
        XCTAssertTrue(zip(path, path.dropFirst()).allSatisfy { $0 <= $1 }, "단조 증가여야 함")
    }

    func testTracksDoubleAndHalfTempo() {
        XCTAssertEqual(run(stream(framesPerEvent: Array(repeating: 3, count: 8))).last, 7)
        XCTAssertEqual(run(stream(framesPerEvent: Array(repeating: 25, count: 8))).last, 7)
    }

    func testMidStreamPositionIsClose() {
        let path = run(stream(framesPerEvent: Array(repeating: 10, count: 8)))
        // 4번째 이벤트 재생 중(프레임 35)에는 인덕스 3 근처여야 함
        XCTAssertTrue((2...4).contains(path[35]), "실제 \(path[35])")
    }

    func testResetJumpsAndContinues() {
        var dtw = OnlineDTW(templates: templates)
        dtw.reset(to: 5)
        XCTAssertEqual(dtw.currentIndex, 5)
        let frames = stream(framesPerEvent: [0,0,0,0,0,10,10,10])
        var last = 5
        for f in frames { last = dtw.step(f) }
        XCTAssertEqual(last, 7)
    }

    func testDoesNotRunAheadOnRepeatedChord() {
        // 첫 화음만 60프레임 → 여전히 0 근처
        let path = run(stream(framesPerEvent: [60,0,0,0,0,0,0,0]))
        XCTAssertLessThanOrEqual(path.last!, 1)
    }
}
