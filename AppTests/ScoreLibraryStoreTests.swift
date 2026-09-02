import XCTest
import UIKit
@testable import ScoreForYou

@MainActor
final class ScoreLibraryStoreTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!
    var defaults: UserDefaults!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "ScoreLibraryStoreTests")!
        defaults.removePersistentDomain(forName: "ScoreLibraryStoreTests")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: sourceDir)
    }

    /// 테스트용 PDF 파일 생성
    func makePDF(named name: String, pages: Int = 3) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        let data = renderer.pdfData { ctx in
            for i in 0..<pages {
                ctx.beginPage()
                "\(i)".draw(at: .zero, withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        let url = sourceDir.appendingPathComponent("\(name).pdf")
        try data.write(to: url)
        return url
    }

    func makeStore() -> ScoreLibraryStore {
        ScoreLibraryStore(directory: tempDir, defaults: defaults)
    }

    func testImportAddsScore() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "쇼팽 녹턴"))
        XCTAssertEqual(store.scores.map(\.title), ["쇼팽 녹턴"])
    }

    func testImportInvalidFileThrows() throws {
        let bad = sourceDir.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: bad)
        let store = makeStore()
        XCTAssertThrowsError(try store.importPDF(from: bad))
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testImportDuplicateNameGetsSuffix() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "연습곡"))
        try store.importPDF(from: try makePDF(named: "연습곡"))
        XCTAssertEqual(store.scores.map(\.title).sorted(), ["연습곡", "연습곡 2"])
    }

    func testDeleteRemovesScoreAndLastPage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "소나타"))
        let score = store.scores[0]
        store.setLastPage(5, of: score)
        store.delete(score)
        XCTAssertTrue(store.scores.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: "lastPage.소나타.pdf"), 0)
    }

    func testRenamePreservesLastPage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "옛이름"))
        store.setLastPage(7, of: store.scores[0])
        store.rename(store.scores[0], to: "새이름")
        XCTAssertEqual(store.scores.map(\.title), ["새이름"])
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 7)
    }

    func testLastPageDefaultsToZero() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "새 악보"))
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 0)
    }

    func testThumbnailReturnsImage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "썸네일"))
        XCTAssertNotNil(store.thumbnail(for: store.scores[0], size: CGSize(width: 160, height: 220)))
    }
}
