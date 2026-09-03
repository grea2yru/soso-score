import XCTest
import UIKit
import PencilKit
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
        try store.importFile(from: try makePDF(named: "쇼팽 녹턴"))
        XCTAssertEqual(store.scores.map(\.title), ["쇼팽 녹턴"])
    }

    func testImportInvalidFileThrows() throws {
        let bad = sourceDir.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: bad)
        let store = makeStore()
        XCTAssertThrowsError(try store.importFile(from: bad))
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testImportDuplicateNameGetsSuffix() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "연습곡"))
        try store.importFile(from: try makePDF(named: "연습곡"))
        XCTAssertEqual(store.scores.map(\.title).sorted(), ["연습곡", "연습곡 2"])
    }

    func testDeleteRemovesScoreAndLastPage() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "소나타"))
        let score = store.scores[0]
        store.setLastPage(5, of: score)
        store.delete(score)
        XCTAssertTrue(store.scores.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: "lastPage.소나타.pdf"), 0)
    }

    func testRenamePreservesLastPage() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "옛이름"))
        store.setLastPage(7, of: store.scores[0])
        store.rename(store.scores[0], to: "새이름")
        XCTAssertEqual(store.scores.map(\.title), ["새이름"])
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 7)
    }

    func testLastPageDefaultsToZero() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "새 악보"))
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 0)
    }

    // MARK: 기본 샘플 설치

    func testInstallSamplesCopiesWithGivenTitle() throws {
        let store = makeStore()
        let sample = try makePDF(named: "debussy-clair-de-lune")
        store.installSamplesIfNeeded([BundledSample(url: sample, title: "드뷔시 - 달빛")])
        XCTAssertEqual(store.scores.map(\.title), ["드뷔시 - 달빛"])
    }

    func testInstallSamplesRunsOnlyOnce() throws {
        let store = makeStore()
        let sample = try makePDF(named: "debussy-clair-de-lune")
        let samples = [BundledSample(url: sample, title: "드뷔시 - 달빛")]
        store.installSamplesIfNeeded(samples)
        store.delete(store.scores[0])            // 사용자가 지운 뒤
        store.installSamplesIfNeeded(samples)    // 다시 설치되면 안 됨
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testInstallSamplesSurvivesAcrossStoreInstances() throws {
        let sample = try makePDF(named: "debussy-clair-de-lune")
        let samples = [BundledSample(url: sample, title: "드뷔시 - 달빛")]
        makeStore().installSamplesIfNeeded(samples)
        let second = makeStore()                 // 앱 재실행에 해당
        second.installSamplesIfNeeded(samples)
        XCTAssertEqual(second.scores.count, 1)
    }

    func testSampleAddedLaterIsInstalledWithoutReinstallingDeletedOne() throws {
        let store = makeStore()
        let a = BundledSample(url: try makePDF(named: "a"), title: "첫 샘플")
        store.installSamplesIfNeeded([a])
        store.delete(store.scores[0])                       // 사용자가 첫 샘플 삭제
        let b = BundledSample(url: try makePDF(named: "b"), title: "나중 샘플")
        store.installSamplesIfNeeded([a, b])                // 앱 업데이트로 샘플 추가
        XCTAssertEqual(store.scores.map(\.title), ["나중 샘플"])
    }

    func testLegacyBooleanFlagTreatsFirstSampleAsInstalled() throws {
        defaults.set(true, forKey: ScoreKind.pdf.samplesInstalledKey)   // 구버전 상태
        let store = makeStore()
        let a = BundledSample(url: try makePDF(named: "a"), title: "첫 샘플")
        let b = BundledSample(url: try makePDF(named: "b"), title: "나중 샘플")
        store.installSamplesIfNeeded([a, b])
        XCTAssertEqual(store.scores.map(\.title), ["나중 샘플"])
    }

    // MARK: 즐겨찾기

    func testToggleFavoritePersistsAcrossInstances() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "녹턴"))
        store.toggleFavorite(store.scores[0])
        XCTAssertTrue(store.isFavorite(store.scores[0]))

        let second = makeStore()
        XCTAssertTrue(second.isFavorite(second.scores[0]))
        second.toggleFavorite(second.scores[0])
        XCTAssertFalse(second.isFavorite(second.scores[0]))
    }

    func testRenameKeepsFavorite() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "옛이름"))
        store.toggleFavorite(store.scores[0])
        store.rename(store.scores[0], to: "새이름")
        XCTAssertTrue(store.isFavorite(store.scores[0]))
        XCTAssertEqual(store.scores[0].title, "새이름")
    }

    func testDeleteClearsFavorite() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "지울곡"))
        store.toggleFavorite(store.scores[0])
        store.delete(store.scores[0])
        XCTAssertTrue(store.favoriteIDs.isEmpty)
    }

    // MARK: 필기 연동

    func testRenameAndDeleteCarryAnnotations() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "옛이름"))
        let ink = PKInk(.pen, color: .black)
        let point = PKStrokePoint(location: .zero, timeOffset: 0, size: CGSize(width: 3, height: 3),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let stroke = PKStroke(ink: ink, path: PKStrokePath(controlPoints: [point, point], creationDate: Date()))
        try store.annotations.save([0: PKDrawing(strokes: [stroke])], for: store.scores[0].id)

        store.rename(store.scores[0], to: "새이름")
        XCTAssertEqual(store.annotations.load(for: "새이름.pdf").count, 1)

        store.delete(store.scores[0])
        XCTAssertTrue(store.annotations.load(for: "새이름.pdf").isEmpty)
    }

    // MARK: 검색·필터

    func testFilterByTitleIsCaseInsensitivePartialMatch() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "Clair de Lune"))
        try store.importFile(from: try makePDF(named: "월광 소나타"))
        try store.importFile(from: try makePDF(named: "녹턴"))
        XCTAssertEqual(store.filteredScores(query: "lune", favoritesOnly: false).map(\.title), ["Clair de Lune"])
        XCTAssertEqual(store.filteredScores(query: "소나타", favoritesOnly: false).map(\.title), ["월광 소나타"])
        XCTAssertEqual(store.filteredScores(query: "  ", favoritesOnly: false).count, 3)
    }

    func testFavoritesOnlyFilterAndFavoritesSortFirst() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "가"))
        try store.importFile(from: try makePDF(named: "나"))
        try store.importFile(from: try makePDF(named: "다"))
        let na = store.scores.first { $0.title == "나" }!
        store.toggleFavorite(na)
        XCTAssertEqual(store.filteredScores(query: "", favoritesOnly: true).map(\.title), ["나"])
        XCTAssertEqual(store.filteredScores(query: "", favoritesOnly: false).map(\.title), ["나", "가", "다"])
    }

    // MARK: MusicXML 종류

    func makeXMLStore() -> ScoreLibraryStore {
        ScoreLibraryStore(kind: .musicXML, directory: tempDir, defaults: defaults)
    }

    func makeMusicXML(named name: String) throws -> URL {
        let url = sourceDir.appendingPathComponent("\(name).musicxml")
        try Data("<?xml version=\"1.0\"?><score-partwise version=\"3.1\"><part-list/></score-partwise>".utf8).write(to: url)
        return url
    }

    func testMusicXMLStoreUsesSubdirectoryAndKeepsExtension() throws {
        let store = makeXMLStore()
        try store.importFile(from: try makeMusicXML(named: "인벤션 1번"))
        XCTAssertEqual(store.scores.map(\.title), ["인벤션 1번"])
        XCTAssertEqual(store.scores[0].kind, .musicXML)
        XCTAssertEqual(store.scores[0].url.pathExtension, "musicxml")
        XCTAssertEqual(store.scores[0].url.deletingLastPathComponent().lastPathComponent, "MusicXML")
    }

    func testMusicXMLStoreRejectsPDFAndInvalidXML() throws {
        let store = makeXMLStore()
        XCTAssertThrowsError(try store.importFile(from: try makePDF(named: "pdf파일")))
        let bad = sourceDir.appendingPathComponent("bad.musicxml")
        try Data("<html/>".utf8).write(to: bad)
        XCTAssertThrowsError(try store.importFile(from: bad))
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testFavoritesAreSeparatedByKind() throws {
        let pdfStore = makeStore()
        let xmlStore = makeXMLStore()
        try pdfStore.importFile(from: try makePDF(named: "같은이름"))
        try xmlStore.importFile(from: try makeMusicXML(named: "같은이름"))
        pdfStore.toggleFavorite(pdfStore.scores[0])
        XCTAssertFalse(xmlStore.isFavorite(xmlStore.scores[0]))
    }

    func testLastPageIsSeparatedByKind() throws {
        let pdfStore = makeStore()
        let xmlStore = makeXMLStore()
        try pdfStore.importFile(from: try makePDF(named: "곡"))
        try xmlStore.importFile(from: try makeMusicXML(named: "곡"))
        pdfStore.setLastPage(3, of: pdfStore.scores[0])
        XCTAssertEqual(xmlStore.lastPage(of: xmlStore.scores[0]), 0)
    }

    func testRenameKeepsOriginalExtension() throws {
        let store = makeXMLStore()
        try store.importFile(from: try makeMusicXML(named: "옛"))
        store.rename(store.scores[0], to: "새")
        XCTAssertEqual(store.scores[0].id, "새.musicxml")
    }

    func testThumbnailReturnsImage() throws {
        let store = makeStore()
        try store.importFile(from: try makePDF(named: "썸네일"))
        XCTAssertNotNil(store.thumbnail(for: store.scores[0], size: CGSize(width: 160, height: 220)))
    }
}
