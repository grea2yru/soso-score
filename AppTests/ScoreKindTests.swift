import XCTest
@testable import SoSoScore

final class ScoreKindTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testKindForExtension() {
        XCTAssertEqual(ScoreKind.kind(forExtension: "PDF"), .pdf)
        XCTAssertEqual(ScoreKind.kind(forExtension: "musicxml"), .musicXML)
        XCTAssertEqual(ScoreKind.kind(forExtension: "mxl"), .musicXML)
        XCTAssertEqual(ScoreKind.kind(forExtension: "xml"), .musicXML)
        XCTAssertNil(ScoreKind.kind(forExtension: "txt"))
    }

    func testMusicXMLValidation() throws {
        let partwise = try write("a.musicxml", Array("<?xml version=\"1.0\"?><score-partwise></score-partwise>".utf8))
        let timewise = try write("b.xml", Array("<score-timewise/>".utf8))
        let notMusic = try write("c.musicxml", Array("<html></html>".utf8))
        let mxl = try write("d.mxl", [0x50, 0x4B, 0x03, 0x04, 0, 0])
        let badMxl = try write("e.mxl", [0x00, 0x01])
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: partwise))
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: timewise))
        XCTAssertFalse(ScoreKind.musicXML.validate(fileAt: notMusic))
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: mxl))
        XCTAssertFalse(ScoreKind.musicXML.validate(fileAt: badMxl))
    }

    func testKeysAreDistinct() {
        XCTAssertNotEqual(ScoreKind.pdf.favoritesKey, ScoreKind.musicXML.favoritesKey)
        XCTAssertNotEqual(ScoreKind.pdf.samplesInstalledKey, ScoreKind.musicXML.samplesInstalledKey)
        XCTAssertNotEqual(ScoreKind.pdf.lastPageKeyPrefix, ScoreKind.musicXML.lastPageKeyPrefix)
        XCTAssertEqual(ScoreKind.pdf.favoritesKey, "favoriteScoreIDs")   // 기존 데이터 호환
        XCTAssertNil(ScoreKind.pdf.subdirectory)
        XCTAssertEqual(ScoreKind.musicXML.subdirectory, "MusicXML")
    }
}
