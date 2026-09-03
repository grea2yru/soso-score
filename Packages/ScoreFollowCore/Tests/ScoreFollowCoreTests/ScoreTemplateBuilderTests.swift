import XCTest
@testable import ScoreFollowCore

final class ScoreTemplateBuilderTests: XCTestCase {
    func testTemplateHasFundamentalAndHarmonics() {
        let t = ScoreTemplateBuilder.template(for: [60])   // C4: 배음 C(1.0) C(0.5) G(0.33)
        XCTAssertGreaterThan(t.values[0], t.values[7])
        XCTAssertGreaterThan(t.values[7], 0)
        XCTAssertEqual(t.values[1], 0)
        XCTAssertEqual(sqrt(t.values.map { $0 * $0 }.reduce(0, +)), 1, accuracy: 1e-4)
    }

    func testEventsCarrySustainedNotesAndMeasure() throws {
        let json = """
        [{"qstamp":0,"on":["n1","n2"],"measureOn":"m1"},
         {"qstamp":1,"off":["n1"],"on":["n3"]},
         {"qstamp":2,"off":["n2","n3"]},
         {"qstamp":2,"on":["n4"],"measureOn":"m2"}]
        """
        let entries = try JSONDecoder().decode([TimemapEntry].self, from: Data(json.utf8))
        let events = ScoreTemplateBuilder.events(from: entries, pitches: ["n1": 60, "n2": 64, "n3": 67, "n4": 72])
        XCTAssertEqual(events.count, 3)                       // off만 있는 항목은 이벤트가 아님
        XCTAssertEqual(events[0].pitches.sorted(), [60, 64])
        XCTAssertEqual(events[1].pitches.sorted(), [64, 67])  // n2 지속 + n3
        XCTAssertEqual(events[1].noteIDs, ["n3"])
        XCTAssertEqual(events[2].pitches, [72])
        XCTAssertEqual(events.map(\.measureID), ["m1", "m1", "m2"])
        XCTAssertEqual(events.map(\.index), [0, 1, 2])
    }
}
