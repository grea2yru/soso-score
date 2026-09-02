import Foundation

/// 페이지 배치 계산 (순수 로직).
/// 펼침(twoUp) 모드에서는 항상 짝수 인덱스에서 시작하는 쌍으로 묶고,
/// 페이지 수가 홀수면 마지막 페이지는 왼쪽에 홀로 놓인다.
struct PageNavigator {
    let pageCount: Int
    let twoUp: Bool

    /// 현재 인덱스가 속한 펼침의 첫(왼쪽) 인덱스
    func leadingIndex(from index: Int) -> Int {
        let clamped = min(max(index, 0), max(pageCount - 1, 0))
        return twoUp ? clamped - clamped % 2 : clamped
    }

    /// 화면에 보일 페이지 인덱스 (왼쪽 → 오른쪽 순)
    func visibleIndices(from index: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        let lead = leadingIndex(from: index)
        if twoUp, lead + 1 < pageCount {
            return [lead, lead + 1]
        }
        return [lead]
    }

    func next(from index: Int) -> Int {
        let lead = leadingIndex(from: index)
        let step = twoUp ? 2 : 1
        return lead + step < pageCount ? lead + step : lead
    }

    func previous(from index: Int) -> Int {
        let lead = leadingIndex(from: index)
        let step = twoUp ? 2 : 1
        return max(lead - step, 0)
    }
}
