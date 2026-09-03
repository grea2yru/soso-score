import SwiftUI

@main
struct ScoreApp: App {
    @StateObject private var pdfLibrary = ScoreLibraryStore(kind: .pdf)
    @StateObject private var xmlLibrary = ScoreLibraryStore(kind: .musicXML)
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView(pdfLibrary: pdfLibrary, xmlLibrary: xmlLibrary)
                .environmentObject(settings)
                // 앱 내 언어 설정: SwiftUI 문구(LocalizedStringKey)는 이 로케일로 조회된다
                .environment(\.locale, settings.language.locale)
                .onAppear {
                    pdfLibrary.installSamplesIfNeeded(BundledSample.bundled(for: .pdf))
                    xmlLibrary.installSamplesIfNeeded(BundledSample.bundled(for: .musicXML))
                    _ = VerovioEngine.shared   // WASM 초기화를 미리 시작
                    ScoreTypesetter.shared.schedule(xmlLibrary.scores)   // 캐시 없는 악보를 미리 조판
                }
                .onChange(of: xmlLibrary.scores) { _, scores in
                    ScoreTypesetter.shared.schedule(scores)
                }
                .onOpenURL { url in
                    // Files/AirDrop "다음으로 열기": 확장자로 종류 판별
                    switch ScoreKind.kind(forExtension: url.pathExtension) {
                    case .pdf: try? pdfLibrary.importFile(from: url)
                    case .musicXML: try? xmlLibrary.importFile(from: url)
                    case nil: break
                    }
                }
        }
    }
}
