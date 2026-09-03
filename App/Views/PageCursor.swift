import Foundation
import GestureCore

/// 뷰어의 현재 펼침 위치. Shell과 따라가기 로직이 함께 읽고 쓴다.
@MainActor
final class PageCursor: ObservableObject {
    @Published var leadingIndex = 0
    @Published var isTwoUp = false
    var pageCount = 0

    private var navigator: PageNavigator { PageNavigator(pageCount: pageCount, twoUp: isTwoUp) }
    var visibleIndices: [Int] { navigator.visibleIndices(from: leadingIndex) }

    /// 넘김 성공 여부를 반환 (끝이면 false)
    @discardableResult
    func turn(_ event: PageTurnEvent) -> Bool {
        let target = event == .next ? navigator.next(from: leadingIndex) : navigator.previous(from: leadingIndex)
        guard target != leadingIndex else { return false }
        leadingIndex = target
        return true
    }

    /// 특정 페이지가 보이도록 이동 (펼침 경계에 맞춤)
    func show(page: Int) {
        leadingIndex = navigator.leadingIndex(from: page)
    }

    /// 회전 등으로 펼침 경계가 바뀌었을 때 짝수 인덕스로 스냅
    func snap() { leadingIndex = navigator.leadingIndex(from: leadingIndex) }
}
