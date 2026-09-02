import SwiftUI
import PDFKit
import GestureCore

struct ScoreViewerView: View {
    let score: Score
    @EnvironmentObject var library: ScoreLibraryStore
    @State private var document: PDFDocument?
    @State private var currentPageIndex = 0
    @State private var flashEdge: Edge?
    @State private var isTwoUp = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let document {
                    PDFKitView(document: document, currentPageIndex: $currentPageIndex, twoUp: isTwoUp)
                        .ignoresSafeArea(edges: .bottom)

                    // 좌/우 30% 탭 영역 (중앙 40%는 PDFView 제스처에 양보)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.previous) }
                        Color.clear
                            .frame(width: geo.size.width * 0.4)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.next) }
                    }
                } else {
                    ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "exclamationmark.triangle")
                }

                if let edge = flashEdge {
                    FlashOverlay(edge: edge)
                }
            }
            .onAppear { isTwoUp = geo.size.width > geo.size.height }
            .onChange(of: geo.size) { _, size in
                isTwoUp = size.width > size.height
            }
        }
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(pageLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let doc = PDFDocument(url: score.url)
            document = doc
            let pageCount = doc?.pageCount ?? 1
            currentPageIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
        }
        .onDisappear {
            library.setLastPage(currentPageIndex, of: score)
        }
    }

    private var pageLabel: String {
        let total = document?.pageCount ?? 0
        return "\(currentPageIndex + 1) / \(total)"
    }

    func turn(_ event: PageTurnEvent) {
        guard let document else { return }
        let step = isTwoUp ? 2 : 1
        let target: Int
        switch event {
        case .next: target = min(currentPageIndex + step, document.pageCount - 1)
        case .previous: target = max(currentPageIndex - step, 0)
        }
        guard target != currentPageIndex else { return }
        currentPageIndex = target
        flash(event == .next ? .trailing : .leading)
    }

    private func flash(_ edge: Edge) {
        withAnimation(.easeIn(duration: 0.05)) { flashEdge = edge }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.3)) { flashEdge = nil }
        }
    }
}

/// 페이지 넘김 시각 피드백: 넘긴 방향 가장자리에 짧은 색 플래시
struct FlashOverlay: View {
    let edge: Edge

    var body: some View {
        HStack {
            if edge == .trailing { Spacer() }
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 24)
            if edge == .leading { Spacer() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
