import SwiftUI

enum MusicXMLPage {
    /// 가상 페이지(A4)의 정규화 좌표계 크기 — 필기 저장 기준
    static let size = CGSize(width: 595, height: 842)
}

/// Verovio 엔진으로 MusicXML을 조판해 ScoreViewerShell에 페이지 SVG를 공급한다.
struct MusicXMLScoreViewer: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    @StateObject private var cursor = PageCursor()
    @State private var pageCount: Int?
    @State private var errorMessage: String?
    @State private var svgs: [Int: String] = [:]

    var body: some View {
        Group {
            if let pageCount {
                ScoreViewerShell(
                    score: score,
                    library: library,
                    pageCount: pageCount,
                    cursor: cursor,
                    pageSize: { _ in MusicXMLPage.size }
                ) { index in
                    SVGPage(index: index, svgs: $svgs)
                }
            } else if let errorMessage {
                ContentUnavailableView("악보를 열 수 없습니다", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("악보를 조판하는 중…")
            }
        }
        .task(id: score.id) {
            do {
                svgs = [:]
                pageCount = try await VerovioEngine.shared.load(fileURL: score.url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 페이지 SVG를 필요할 때 엔진에서 받아와 표시한다.
private struct SVGPage: View {
    let index: Int
    @Binding var svgs: [Int: String]

    var body: some View {
        Group {
            if let svg = svgs[index] {
                SVGPageView(svg: svg)
            } else {
                Color.white.overlay(ProgressView())
            }
        }
        .task(id: index) {
            guard svgs[index] == nil else { return }
            if let svg = try? await VerovioEngine.shared.pageSVG(index) {
                svgs[index] = svg
            }
        }
    }
}
