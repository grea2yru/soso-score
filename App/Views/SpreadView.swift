import SwiftUI

/// 한 페이지 또는 두 페이지(책 펼침)를 표시한다. 페이지 내용은 `content`가, 페이지 위 겹침은 `overlay`가 만든다.
/// 펼침에서 오른쪽 페이지가 없으면(홀수 마지막) 왼쪽만 채우고 오른쪽은 비워 둔다.
struct SpreadView<Content: View, Overlay: View>: View {
    let indices: [Int]
    let twoUp: Bool
    /// 페이지의 정규화 좌표계 크기 (가로세로 비율과 필기 배율 계산에 사용)
    let pageSize: (Int) -> CGSize
    let content: (Int) -> Content
    /// (페이지 인덱스, 표시 배율 = 표시 폭 ÷ pageSize.width)
    let overlay: (Int, CGFloat) -> Overlay

    init(indices: [Int], twoUp: Bool,
         pageSize: @escaping (Int) -> CGSize,
         @ViewBuilder content: @escaping (Int) -> Content,
         @ViewBuilder overlay: @escaping (Int, CGFloat) -> Overlay) {
        self.indices = indices
        self.twoUp = twoUp
        self.pageSize = pageSize
        self.content = content
        self.overlay = overlay
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<(twoUp ? 2 : 1), id: \.self) { slot in
                if slot < indices.count {
                    let index = indices[slot]
                    PageSlot(pageSize: pageSize(index), alignment: alignment(for: slot)) {
                        content(index)
                    } overlay: { scale in
                        overlay(index, scale)
                    }
                } else {
                    Color.clear
                }
            }
        }
    }

    /// 펼침에서는 두 페이지가 가운데 책등에서 만나도록 정렬
    private func alignment(for slot: Int) -> Alignment {
        guard twoUp else { return .center }
        return slot == 0 ? .trailing : .leading
    }
}

/// 주어진 영역에 페이지 비율을 유지하며 맞추고, 같은 크기로 오버레이를 겹친다.
struct PageSlot<Content: View, Overlay: View>: View {
    let pageSize: CGSize
    let alignment: Alignment
    @ViewBuilder let content: () -> Content
    @ViewBuilder let overlay: (CGFloat) -> Overlay

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fitScale(pageSize: pageSize, into: geo.size)
            let shown = CGSize(width: pageSize.width * fit, height: pageSize.height * fit)
            ZStack {
                content()
                overlay(fit)
            }
            .frame(width: shown.width, height: shown.height)
            .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
    }

    static func fitScale(pageSize: CGSize, into size: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / pageSize.width, size.height / pageSize.height)
    }
}
