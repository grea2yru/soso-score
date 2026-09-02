import XCTest
@testable import GestureCore

final class GestureEngineTests: XCTestCase {
    func feed(_ engine: inout GestureEngine, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { engine.process($0) }
    }

    func testCooldownSuppressesSecondFire() {
        var e = GestureEngine() // 쿨다운 1.5초
        var frames = eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)     // ~0.2초에 발동
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.32, to: 0.48)    // 재무장
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.5, to: 0.8)      // 쿨다운 내 → 무시
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.82, to: 1.0)     // 재무장
        frames += eyeFrames(left: 0.05, right: 0.95, from: 2.5, to: 2.8)      // 쿨다운 지남 → 발동
        XCTAssertEqual(feed(&e, frames), [.next, .next])
    }

    func testModeOffIgnoresEverything() {
        var s = GestureSettings.default
        s.mode = .off
        var e = GestureEngine(settings: s)
        var frames = headFrames(yaw: 30, from: 0, to: 0.5)
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.52, to: 0.9)
        XCTAssertEqual(feed(&e, frames), [])
    }

    func testWinkModeIgnoresHeadTurn() {
        var s = GestureSettings.default
        s.mode = .wink
        var e = GestureEngine(settings: s)
        XCTAssertEqual(feed(&e, headFrames(yaw: 30, from: 0, to: 1.0)), [])
    }

    func testHeadModeIgnoresWink() {
        var s = GestureSettings.default
        s.mode = .head
        var e = GestureEngine(settings: s)
        XCTAssertEqual(feed(&e, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 1.0)), [])
    }

    func testBothModeFiresFromEitherDetector() {
        var e = GestureEngine()
        var frames = headFrames(yaw: 25, from: 0, to: 0.5)                    // 고개 → next
        frames += headFrames(yaw: 0, from: 0.52, to: 2.0)                     // 복귀 + 쿨다운 소진
        frames += eyeFrames(left: 0.95, right: 0.05, from: 2.1, to: 2.4)      // 왼눈 윙크 → previous
        XCTAssertEqual(feed(&e, frames), [.next, .previous])
    }

    func testInvertDirectionSwapsEvents() {
        var s = GestureSettings.default
        s.invertDirection = true
        var e = GestureEngine(settings: s)
        // 오른쪽으로 돌렸지만 반전 설정 → previous
        XCTAssertEqual(feed(&e, headFrames(yaw: 25, from: 0, to: 0.5)), [.previous])
    }
}
