import XCTest
import PencilKit
@testable import SoSoScore

final class AnnotationStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 두 점을 잇는 획 하나가 든 PKDrawing
    func makeDrawing(from a: CGPoint, to b: CGPoint) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let points = [a, b].enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: TimeInterval(i) * 0.1,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
    }

    func testLoadMissingReturnsEmpty() {
        let store = AnnotationStore(directory: dir)
        XCTAssertTrue(store.load(for: "없는악보.pdf").isEmpty)
    }

    func testSaveAndLoadRoundTripPerPage() throws {
        let store = AnnotationStore(directory: dir)
        let page0 = makeDrawing(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 100, y: 200))
        let page3 = makeDrawing(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 60))
        try store.save([0: page0, 3: page3], for: "녹턴.pdf")

        let loaded = store.load(for: "녹턴.pdf")
        XCTAssertEqual(Set(loaded.keys), [0, 3])
        XCTAssertEqual(loaded[0]?.strokes.count, 1)
        XCTAssertEqual(loaded[0]?.bounds.integral, page0.bounds.integral)
    }

    func testSaveSkipsEmptyDrawingsAndRemovesFileWhenAllEmpty() throws {
        let store = AnnotationStore(directory: dir)
        try store.save([0: makeDrawing(from: .zero, to: CGPoint(x: 5, y: 5)), 1: PKDrawing()], for: "a.pdf")
        XCTAssertEqual(Array(store.load(for: "a.pdf").keys), [0])

        try store.save([0: PKDrawing()], for: "a.pdf")   // 전부 지움
        XCTAssertTrue(store.load(for: "a.pdf").isEmpty)
    }

    func testMoveFollowsRename() throws {
        let store = AnnotationStore(directory: dir)
        try store.save([2: makeDrawing(from: .zero, to: CGPoint(x: 5, y: 5))], for: "옛이름.pdf")
        store.move(from: "옛이름.pdf", to: "새이름.pdf")
        XCTAssertTrue(store.load(for: "옛이름.pdf").isEmpty)
        XCTAssertEqual(store.load(for: "새이름.pdf").count, 1)
    }

    func testDeleteRemovesAnnotations() throws {
        let store = AnnotationStore(directory: dir)
        try store.save([0: makeDrawing(from: .zero, to: CGPoint(x: 5, y: 5))], for: "지울곡.pdf")
        store.delete(for: "지울곡.pdf")
        XCTAssertTrue(store.load(for: "지울곡.pdf").isEmpty)
    }
}
