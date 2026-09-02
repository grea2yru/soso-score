import SwiftUI
import PDFKit

/// 한 페이지 또는 두 페이지(책 펼침)를 표시한다.
/// 펼침에서 오른쪽 페이지가 없으면(홀수 마지막) 왼쏙만 채우고 오른쪽은 비워 둔다.
struct SpreadView: View {
    let document: PDFDocument
    /// 왼쪽 → 오른쪽 순 페이지 인덕스 (1개 또는 2개)
    let indices: [Int]
    let twoUp: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<(twoUp ? 2 : 1), id: \.self) { slot in
                if slot < indices.count, let page = document.page(at: indices[slot]) {
                    PDFPageImage(page: page, alignment: alignment(for: slot))
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

/// PDFPage 하나를 주어진 영역에 맞춰 화면 해상도로 렌더링해 표시한다.
struct PDFPageImage: View {
    let page: PDFPage
    let alignment: Alignment
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct RenderKey: Equatable {
        let page: ObjectIdentifier
        let size: CGSize
        let scale: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
            .task(id: RenderKey(page: ObjectIdentifier(page), size: geo.size, scale: displayScale)) {
                let target = geo.size
                let scale = displayScale
                let rendered = await Task.detached(priority: .userInitiated) {
                    Self.render(page, fitting: target, scale: scale)
                }.value
                image = rendered
            }
        }
    }

    private static func render(_ page: PDFPage, fitting size: CGSize, scale: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return nil }
        let fit = min(size.width / bounds.width, size.height / bounds.height)
        let pixelSize = CGSize(width: bounds.width * fit * scale, height: bounds.height * fit * scale)
        return page.thumbnail(of: pixelSize, for: .mediaBox)
    }
}
