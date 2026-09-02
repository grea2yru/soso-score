import Foundation
import PDFKit
import UIKit

struct Score: Identifiable, Hashable {
    /// 파일명 (확장자 포함) — 디렉토리 내에서 유일
    let id: String
    let url: URL
    var title: String { (id as NSString).deletingPathExtension }
}

@MainActor
final class ScoreLibraryStore: ObservableObject {
    enum LibraryError: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "PDF 파일을 열 수 없습니다." }
    }

    @Published private(set) var scores: [Score] = []

    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.defaults = defaults
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        scores = files
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Score(id: $0.lastPathComponent, url: $0) }
    }

    func importPDF(from source: URL) throws {
        // Files 앱 등 외부에서 온 URL은 보안 스코프 접근이 필요할 수 있다
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        guard PDFDocument(url: source) != nil else { throw LibraryError.invalidPDF }

        let base = source.deletingPathExtension().lastPathComponent
        var dest = directory.appendingPathComponent("\(base).pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = directory.appendingPathComponent("\(base) \(counter).pdf")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: dest)
        reload()
    }

    func delete(_ score: Score) {
        try? FileManager.default.removeItem(at: score.url)
        defaults.removeObject(forKey: lastPageKey(score.id))
        reload()
    }

    func rename(_ score: Score, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let dest = directory.appendingPathComponent("\(trimmed).pdf")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        do {
            try FileManager.default.moveItem(at: score.url, to: dest)
        } catch { return }
        let saved = defaults.integer(forKey: lastPageKey(score.id))
        defaults.removeObject(forKey: lastPageKey(score.id))
        if saved != 0 { defaults.set(saved, forKey: lastPageKey(dest.lastPathComponent)) }
        reload()
    }

    func lastPage(of score: Score) -> Int {
        defaults.integer(forKey: lastPageKey(score.id))
    }

    func setLastPage(_ page: Int, of score: Score) {
        defaults.set(page, forKey: lastPageKey(score.id))
    }

    func thumbnail(for score: Score, size: CGSize) -> UIImage? {
        PDFDocument(url: score.url)?.page(at: 0)?.thumbnail(of: size, for: .mediaBox)
    }

    private func lastPageKey(_ id: String) -> String { "lastPage.\(id)" }
}
