import XCTest
@testable import ScoreForYou

@MainActor
final class VerovioEngineTests: XCTestCase {
    func testLoadsSampleRendersPagesAndTimemap() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "bach-bwv846", withExtension: "mxl"))
        let engine = VerovioEngine()

        let pageCount = try await engine.load(fileURL: url)
        XCTAssertGreaterThan(pageCount, 0)

        let svg = try await engine.pageSVG(0)
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("class=\"note\""))

        let map = try await engine.timemap()
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: map) as? [[String: Any]])
        XCTAssertTrue(entries.contains { (($0["on"] as? [String])?.isEmpty == false) })
    }

    func testLoadInvalidFileThrows() async throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad.musicxml")
        try Data("<not-music/>".utf8).write(to: bad)
        let engine = VerovioEngine()
        do {
            _ = try await engine.load(fileURL: bad)
            XCTFail("손상 파일이 열리면 안 됨")
        } catch let error as VerovioError {
            guard case .loadFailed = error else { return XCTFail("loadFailed 기대, 실제: \(error)") }
        }
    }
}
