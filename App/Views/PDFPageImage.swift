import SwiftUI
import PDFKit

/// PDFPage 하나를 자신의 프레임 크기에 맞춰 화면 해상도로 렌더링해 표시한다.
struct PDFPageImage: View {
    let page: PDFPage
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
                    Image(uiImage: image).resizable()
                } else {
                    Color.white
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: RenderKey(page: ObjectIdentifier(page), size: geo.size, scale: displayScale)) {
                let target = geo.size
                let scale = displayScale
                image = await Task.detached(priority: .userInitiated) {
                    Self.render(page, size: target, scale: scale)
                }.value
            }
        }
    }

    /// 페이지 회전(/Rotate 90·270)을 반영한 표시 기준 크기
    static func displaySize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        return page.rotation % 180 != 0
            ? CGSize(width: bounds.height, height: bounds.width)
            : CGSize(width: bounds.width, height: bounds.height)
    }

    private static func render(_ page: PDFPage, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
    }
}
