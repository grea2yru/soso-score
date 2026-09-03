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

        // 2B: 피치·시스템 맵
        let typed = try await engine.timemapEntries()
        let ids = Array(typed.flatMap { $0.on ?? [] }.prefix(20))
        let pitches = try await engine.pitches(for: ids)
        XCTAssertEqual(pitches.count, ids.count)
        XCTAssertTrue(pitches.values.allSatisfy { (21...108).contains($0) })
        let systems = try await engine.systemMap(page: 0)
        XCTAssertGreaterThan(systems.count, 0)
        XCTAssertFalse(systems.notes.isEmpty)
        XCTAssertFalse(systems.measures.isEmpty)
    }

    func testAllBundledMusicXMLSamplesLoad() async throws {
        let samples = BundledSample.bundled(for: .musicXML)
        XCTAssertEqual(samples.count, 10)
        let engine = VerovioEngine()
        for sample in samples {
            let pages = try await engine.load(fileURL: sample.url)
            XCTAssertGreaterThan(pages, 0, sample.title)
        }
    }

    func testAllBundledPDFSamplesAreValid() {
        let samples = BundledSample.bundled(for: .pdf)
        XCTAssertEqual(samples.count, 10)
        for sample in samples {
            XCTAssertTrue(ScoreKind.pdf.validate(fileAt: sample.url), sample.title)
        }
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
