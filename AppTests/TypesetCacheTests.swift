import XCTest
import ScoreFollowCore
@testable import SoSoScore

final class TypesetCacheTests: XCTestCase {
    var dir: URL!
    var cache: TypesetCache!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cache = TypesetCache(directory: dir.appendingPathComponent("Typeset", isDirectory: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func writeFile(_ name: String, _ text: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func sampleContents(pages: Int) -> TypesetCache.Contents {
        TypesetCache.Contents(
            pages: (0..<pages).map { "<svg><g class=\"page\">\($0)</g></svg>" },
            timemap: Data(#"[{"qstamp":0,"on":["n1"],"measureOn":"m1"},{"qstamp":1,"on":["n2"],"off":["n1"]}]"#.utf8),
            pitches: ["n1": 60, "n2": 64],
            systems: (0..<pages).map { PageSystemMap(count: 2, notes: ["n\($0 + 1)": 1], measures: ["m\($0 + 1)": 0]) })
    }

    func testKeyDependsOnContentNotName() throws {
        let a = try writeFile("a.musicxml", "<score/>")
        let sameContent = try writeFile("renamed.musicxml", "<score/>")
        let other = try writeFile("b.musicxml", "<score>2</score>")
        XCTAssertEqual(try cache.key(for: a), try cache.key(for: sameContent))
        XCTAssertNotEqual(try cache.key(for: a), try cache.key(for: other))
        XCTAssertTrue(try cache.key(for: a).hasSuffix("-v\(TypesetCache.layoutVersion)"))
    }

    func testStoreThenBundleRoundTrip() throws {
        XCTAssertNil(cache.bundle(forKey: "missing"))
        let bundle = try cache.store(sampleContents(pages: 3), forKey: "k1")
        XCTAssertEqual(bundle.pageCount, 3)

        let loaded = try XCTUnwrap(cache.bundle(forKey: "k1"))
        XCTAssertEqual(loaded.pageCount, 3)
        XCTAssertEqual(try loaded.pageSVG(2), "<svg><g class=\"page\">2</g></svg>")
        XCTAssertEqual(try loaded.pitches(), ["n1": 60, "n2": 64])
        let entries = try loaded.timemapEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].on, ["n1"])
        let systems = try loaded.systemMaps()
        XCTAssertEqual(systems.count, 3)
        XCTAssertEqual(systems[1].notes["n2"], 1)
        XCTAssertEqual(systems[1].measures["m2"], 0)
    }

    func testStoreReplacesExistingAndLeavesNoTemp() throws {
        _ = try cache.store(sampleContents(pages: 1), forKey: "k1")
        _ = try cache.store(sampleContents(pages: 4), forKey: "k1")
        XCTAssertEqual(cache.bundle(forKey: "k1")?.pageCount, 4)
        let items = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        XCTAssertEqual(items, ["k1"])
    }

    func testIncompleteBundleIsIgnored() throws {
        let partial = cache.directory.appendingPathComponent("k2", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: partial.appendingPathComponent(TypesetCache.pageFile(0)))
        XCTAssertNil(cache.bundle(forKey: "k2"), "meta.json이 없으면 미완성 캐시")
    }

    func testRemoveAllExceptKeepsListedKeysAndFreshTemp() throws {
        _ = try cache.store(sampleContents(pages: 1), forKey: "keep")
        _ = try cache.store(sampleContents(pages: 1), forKey: "orphan")
        let tmp = cache.directory.appendingPathComponent(".tmp-inprogress", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        cache.removeAll(except: ["keep"])

        XCTAssertNotNil(cache.bundle(forKey: "keep"))
        XCTAssertNil(cache.bundle(forKey: "orphan"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path), "쓰는 중일 수 있는 새 임시 폴더는 남긴다")
    }

    func testFollowIndexBuildFromBundle() throws {
        let bundle = try cache.store(sampleContents(pages: 2), forKey: "k3")
        let index = FollowIndex.build(entries: try bundle.timemapEntries(), pitches: try bundle.pitches(), systems: try bundle.systemMaps())
        XCTAssertEqual(index.events.count, 2)
        XCTAssertEqual(index.layout.noteLocation["n2"], NoteLocation(page: 1, system: 1))
        XCTAssertEqual(index.layout.systemCounts, [0: 2, 1: 2])
        XCTAssertEqual(index.layout.measureFirstEvent["m1"], 0)
    }
}
