import XCTest
@testable import GestureCore

final class WinkDetectorTests: XCTestCase {
    let settings = GestureSettings.default // 감김 >0.8, 뜸 <0.3, 유지 0.2초

    func feed(_ detector: inout WinkDetector, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { detector.process($0, settings: settings) }
    }

    func testRightWinkFiresNextOnce() {
        var d = WinkDetector()
        // 오른눈만 0.3초 감음 → next 1회
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)), [.next])
    }

    func testLeftWinkFiresPrevious() {
        var d = WinkDetector()
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.95, right: 0.05, from: 0, to: 0.3)), [.previous])
    }

    func testBothEyesBlinkIgnored() {
        var d = WinkDetector()
        // 자연스러운 양눈 깜빡임 (비대칭 조건 불충족)
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.9, right: 0.9, from: 0, to: 0.3)), [])
    }

    func testShortWinkIgnored() {
        var d = WinkDetector()
        // 0.1초 (유지 시간 0.2초 미달)
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.1)), [])
    }

    func testNaturalBlinkTransientAsymmetryIgnored() {
        var d = WinkDetector()
        // 자연 깜빡임에서 왼눈이 살짝 먼저 감기는 과도 상태(0.05초) → 발동 금지
        var frames = eyeFrames(left: 0.85, right: 0.25, from: 0, to: 0.05)
        frames += eyeFrames(left: 0.95, right: 0.95, from: 0.06, to: 0.3)
        XCTAssertEqual(feed(&d, frames), [])
    }

    func testNoRefireWhileEyeStaysClosed() {
        var d = WinkDetector()
        // 1초 내내 감고 있어도 1회만
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 1.0)), [.next])
    }

    func testRefiresAfterBothEyesOpen() {
        var d = WinkDetector()
        var frames = eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)   // 발동
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.32, to: 0.6)   // 양눈 열림(재무장)
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.62, to: 0.9)   // 다시 발동
        XCTAssertEqual(feed(&d, frames), [.next, .next])
    }
}
