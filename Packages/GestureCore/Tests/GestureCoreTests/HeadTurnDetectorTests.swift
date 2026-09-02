import XCTest
@testable import GestureCore

final class HeadTurnDetectorTests: XCTestCase {
    let settings = GestureSettings.default // 임계값 20°, 유지 0.3초, 재무장 5°

    func feed(_ detector: inout HeadTurnDetector, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { detector.process($0, settings: settings) }
    }

    func testTurnRightHeldFiresNextOnce() {
        var d = HeadTurnDetector()
        // 0.5초간 오른쪽 25° 유지 → 0.3초 시점에 next 1회만
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 0.5)), [.next])
    }

    func testTurnLeftHeldFiresPrevious() {
        var d = HeadTurnDetector()
        XCTAssertEqual(feed(&d, headFrames(yaw: -25, from: 0, to: 0.5)), [.previous])
    }

    func testShortGlanceDoesNotFire() {
        var d = HeadTurnDetector()
        // 0.2초만 돌림 (유지 시간 0.3초 미달) — 연주 중 건반 흘끗 보기
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 0.2)), [])
    }

    func testBelowThresholdDoesNotFire() {
        var d = HeadTurnDetector()
        // 임계값 20° 미만의 작은 움직임은 아무리 오래 유지해도 무시
        XCTAssertEqual(feed(&d, headFrames(yaw: 15, from: 0, to: 1.0)), [])
    }

    func testNoRefireWhileHeldTurned() {
        var d = HeadTurnDetector()
        // 2초간 계속 돌린 채 유지 → 정면 복귀 전에는 딱 1회만
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 2.0)), [.next])
    }

    func testRefiresAfterRecentering() {
        var d = HeadTurnDetector()
        var frames = headFrames(yaw: 25, from: 0, to: 0.5)     // 발동
        frames += headFrames(yaw: 0, from: 0.52, to: 1.0)      // 정면 복귀(재무장)
        frames += headFrames(yaw: 25, from: 1.02, to: 1.5)     // 다시 발동
        XCTAssertEqual(feed(&d, frames), [.next, .next])
    }

    func testDirectionChangeMidHoldResetsTimer() {
        var d = HeadTurnDetector()
        // 오른쪽 0.2초 → 곧바로 왼쪽 0.2초: 어느 쪽도 유지 시간을 못 채움
        var frames = headFrames(yaw: 25, from: 0, to: 0.2)
        frames += headFrames(yaw: -25, from: 0.22, to: 0.42)
        XCTAssertEqual(feed(&d, frames), [])
    }
}
