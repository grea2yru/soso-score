import XCTest
@testable import SoSoScore

@MainActor
final class ScoreTypesetterTests: XCTestCase {
    var dir: URL!
    var cache: TypesetCache!
    var typesetter: ScoreTypesetter!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cache = TypesetCache(directory: dir)
        typesetter = ScoreTypesetter(engine: VerovioEngine(), cache: cache)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func sampleURL() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "debussy-clair-de-lune", withExtension: "mxl"))
    }

    func testFirstOpenTypesetsAndCachesThenSecondOpenIsCached() async throws {
        let url = try sampleURL()

        let first = try await typesetter.open(fileURL: url)
        XCTAssertFalse(first.isCached)
        XCTAssertGreaterThan(first.pageCount, 0)
        let liveSVG = try await first.pageSVG(0)
        XCTAssertTrue(liveSVG.contains("<svg"))

        var visible = [first.pageCount - 1]
        let index = try await first.buildFollowIndex(priorityPages: { visible })
        visible = []
        XCTAssertFalse(index.events.isEmpty)
        XCTAssertEqual(index.layout.systemCounts.count, first.pageCount)
        XCTAssertTrue(first.isCached, "인덱스를 만들면 캐시에 저장하고 캐시 모드로 전환")
        first.close()

        let key = try cache.key(for: url)
        XCTAssertEqual(cache.bundle(forKey: key)?.pageCount, first.pageCount)

        let second = try await typesetter.open(fileURL: url)
        XCTAssertTrue(second.isCached)
        XCTAssertEqual(second.pageCount, first.pageCount)
        let cachedSVG = try await second.pageSVG(0)
        XCTAssertEqual(cachedSVG, liveSVG)
        let cachedIndex = try await second.buildFollowIndex(priorityPages: { [] })
        XCTAssertEqual(cachedIndex.events.count, index.events.count)
        XCTAssertEqual(cachedIndex.layout.noteLocation.count, index.layout.noteLocation.count)
        second.close()
    }

    func testPrefetchFillsCacheForScheduledScores() async throws {
        let url = try sampleURL()
        let score = Score(id: url.lastPathComponent, url: url, kind: .musicXML)
        typesetter.schedule([score])

        let key = try cache.key(for: url)
        for _ in 0..<600 where cache.bundle(forKey: key) == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNotNil(cache.bundle(forKey: key), "백그라운드 미리 조판이 캐시를 만들어야 함")

        // 미리 조판된 악보는 엔진 없이 즉시 열린다
        let doc = try await typesetter.open(fileURL: url)
        XCTAssertTrue(doc.isCached)
        doc.close()
    }

    func testOpenWhilePrefetchingYieldsEngineToViewer() async throws {
        let url = try sampleURL()
        let others = BundledSample.bundled(for: .musicXML).filter { $0.url != url }
        typesetter.schedule(others.map { Score(id: $0.url.lastPathComponent, url: $0.url, kind: .musicXML) })

        // 미리 조판이 엔진을 잡은 상태에서 뷰어가 열어도 (양보받아) 정상 조판된다
        let doc = try await typesetter.open(fileURL: url)
        XCTAssertGreaterThan(doc.pageCount, 0)
        let svg = try await doc.pageSVG(0)
        XCTAssertTrue(svg.contains("<svg"))
        doc.close()
    }

    func testOpenInvalidFileThrowsAndReleasesEngine() async throws {
        let bad = dir.appendingPathComponent("bad.musicxml")
        try Data("<not-music/>".utf8).write(to: bad)
        do {
            _ = try await typesetter.open(fileURL: bad)
            XCTFail("손상 파일이 열리면 안 됨")
        } catch let error as VerovioError {
            guard case .loadFailed = error else { return XCTFail("loadFailed 기대, 실제: \(error)") }
        }
        // 엔진이 풀렸으므로 다음 열기는 바로 진행된다
        let doc = try await typesetter.open(fileURL: try sampleURL())
        XCTAssertGreaterThan(doc.pageCount, 0)
        doc.close()
    }
}
