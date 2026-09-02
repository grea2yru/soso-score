import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    let twoUp: Bool

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayDirection = .horizontal
        view.backgroundColor = .systemBackground
        context.coordinator.observePageChanges(of: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        let mode: PDFDisplayMode = twoUp ? .twoUp : .singlePage
        if view.displayMode != mode {
            view.displayMode = mode
            view.autoScales = true
        }
        if let page = document.page(at: currentPageIndex), view.currentPage != page {
            view.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        init(_ parent: PDFKitView) { self.parent = parent }

        func observePageChanges(of view: PDFView) {
            NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view,
                      let page = view.currentPage,
                      let doc = view.document else { return }
                let index = doc.index(for: page)
                if self.parent.currentPageIndex != index {
                    self.parent.currentPageIndex = index
                }
            }
        }
    }
}
