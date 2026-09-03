import SwiftUI

/// 상단 탭: PDF 악보 | 디지털 악보 | 설정 (iPadOS 18 탭 바, 사이드바 전환 가능).
/// 뷰어는 전체 화면 커버로 열어 탭 바를 가리고 악보에 화면을 최대한 할당한다.
struct RootTabView: View {
    @ObservedObject var pdfLibrary: ScoreLibraryStore
    @ObservedObject var xmlLibrary: ScoreLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var openScore: Score?

    var body: some View {
        TabView {
            Tab(ScoreKind.pdf.title, systemImage: ScoreKind.pdf.symbolName) {
                LibraryView(library: pdfLibrary) { openScore = $0 }
            }
            Tab(ScoreKind.musicXML.title, systemImage: ScoreKind.musicXML.symbolName) {
                LibraryView(library: xmlLibrary) { openScore = $0 }
            }
            Tab(L10n.string("설정"), systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(item: $openScore) { score in
            NavigationStack {
                Group {
                    switch score.kind {
                    case .pdf: PDFScoreViewer(score: score, library: pdfLibrary)
                    case .musicXML: MusicXMLScoreViewer(score: score, library: xmlLibrary)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            openScore = nil
                        } label: {
                            Label("보관함으로", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
    }
}
