import SwiftUI
import PDFKit

/// PDF 문서를 열어 ScoreViewerShell에 페이지를 공급한다.
struct PDFScoreViewer: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    @State private var document: PDFDocument?
    @State private var failed = false

    var body: some View {
        Group {
            if let document {
                ScoreViewerShell(
                    score: score,
                    library: library,
                    pageCount: document.pageCount,
                    pageSize: { index in
                        document.page(at: index).map(PDFPageImage.displaySize(of:))
                            ?? CGSize(width: 595, height: 842)
                    }
                ) { index in
                    if let page = document.page(at: index) {
                        PDFPageImage(page: page)
                    } else {
                        Color.white
                    }
                }
            } else if failed {
                ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard document == nil else { return }
            if let doc = PDFDocument(url: score.url) { document = doc } else { failed = true }
        }
    }
}
