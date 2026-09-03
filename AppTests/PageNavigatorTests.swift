import XCTest
@testable import SoSoScore

final class PageNavigatorTests: XCTestCase {
    // MARK: 세로(한 페이지)

    func testSinglePageShowsOnlyCurrentIndex() {
        let nav = PageNavigator(pageCount: 5, twoUp: false)
        XCTAssertEqual(nav.visibleIndices(from: 3), [3])
    }

    func testSinglePageStepsByOne() {
        let nav = PageNavigator(pageCount: 5, twoUp: false)
        XCTAssertEqual(nav.next(from: 1), 2)
        XCTAssertEqual(nav.previous(from: 1), 0)
    }

    func testSinglePageClampsAtEnds() {
        let nav = PageNavigator(pageCount: 5, twoUp: false)
        XCTAssertEqual(nav.next(from: 4), 4)
        XCTAssertEqual(nav.previous(from: 0), 0)
    }

    // MARK: 가로(펼침)

    func testTwoUpSnapsToEvenIndex() {
        let nav = PageNavigator(pageCount: 6, twoUp: true)
        // 3페이지(인덱스 2)를 보다가 회전하면 3–4 펼침
        XCTAssertEqual(nav.visibleIndices(from: 2), [2, 3])
        // 4페이지(인덱스 3)에서 회전해도 같은 3–4 펼침
        XCTAssertEqual(nav.visibleIndices(from: 3), [2, 3])
    }

    func testTwoUpOddCountShowsLastPageAloneOnLeft() {
        let nav = PageNavigator(pageCount: 5, twoUp: true)
        // 마지막 5페이지(인덕스 4)는 왼쪽에 홀로, 오른쪽 없음
        XCTAssertEqual(nav.visibleIndices(from: 4), [4])
    }

    func testTwoUpStepsByTwo() {
        let nav = PageNavigator(pageCount: 6, twoUp: true)
        XCTAssertEqual(nav.next(from: 0), 2)
        XCTAssertEqual(nav.previous(from: 4), 2)
    }

    func testTwoUpEvenCountStopsAtLastSpread() {
        let nav = PageNavigator(pageCount: 6, twoUp: true)
        // 5–6 펼침(인덕스 4)에서 더 넘기면 그대로
        XCTAssertEqual(nav.next(from: 4), 4)
    }

    func testTwoUpOddCountAdvancesToLonelyLastPage() {
        let nav = PageNavigator(pageCount: 5, twoUp: true)
        // 3–4 펼침(인덕스 2) → 5페이지 홀로(인덕스 4)
        XCTAssertEqual(nav.next(from: 2), 4)
        XCTAssertEqual(nav.next(from: 4), 4)
    }

    func testTwoUpPreviousClampsAtStart() {
        let nav = PageNavigator(pageCount: 5, twoUp: true)
        XCTAssertEqual(nav.previous(from: 0), 0)
        XCTAssertEqual(nav.previous(from: 1), 0)
    }

    func testSinglePageDocument() {
        let nav = PageNavigator(pageCount: 1, twoUp: true)
        XCTAssertEqual(nav.visibleIndices(from: 0), [0])
        XCTAssertEqual(nav.next(from: 0), 0)
    }
}
