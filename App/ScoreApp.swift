import SwiftUI

@main
struct ScoreApp: App {
    @StateObject private var library = ScoreLibraryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library)
                .environmentObject(settings)
                .onAppear {
                    library.installSamplesIfNeeded(BundledSample.bundled(for: .pdf))
                }
        }
    }
}
