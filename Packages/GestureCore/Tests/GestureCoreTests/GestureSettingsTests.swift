import XCTest
@testable import GestureCore

final class GestureSettingsTests: XCTestCase {
    func testDefaultValuesMatchSpec() {
        let s = GestureSettings.default
        XCTAssertEqual(s.mode, .both)
        XCTAssertEqual(s.headYawThresholdDegrees, 20)
        XCTAssertEqual(s.headHoldDuration, 0.3)
        XCTAssertEqual(s.headRearmThresholdDegrees, 5)
        XCTAssertEqual(s.winkClosedThreshold, 0.8)
        XCTAssertEqual(s.winkOpenThreshold, 0.3)
        XCTAssertEqual(s.winkHoldDuration, 0.2)
        XCTAssertEqual(s.cooldown, 1.5)
        XCTAssertFalse(s.invertDirection)
    }

    func testCodableRoundTrip() throws {
        var s = GestureSettings.default
        s.mode = .wink
        s.invertDirection = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(GestureSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
