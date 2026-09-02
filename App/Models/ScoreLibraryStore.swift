import Foundation
import PDFKit
import UIKit

struct Score: Identifiable, Hashable {
    /// 파일명 (확장자 포함) — 디렉토리 내에서 유일
    let id: String
    let url: URL
    var title: String { (id as NSString).deletingPathExtension }
}

/// 앱에 내장된 기본 샘플 악보. 출처와 라이선스는 Samples/LICENSE.md 참고.
struct BundledSample {
    let url: URL
    let title: String

    static var bundled: [BundledSample] {
        guard let url = Bundle.main.url(forResource: "debussy-clair-de-lune", withExtension: "pdf") else {
            return []
        }
        return [BundledSample(url: url, title: "드뷔시 - 달빛 (Clair de Lune)")]
    }
}

@MainActor
final class ScoreLibraryStore: ObservableObject {
    enum LibraryError: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "PDF 파일을 열 수 없습니다." }
    }

    @Published private(set) var scores: [Score] = []
    /// 즐겨찾기된 악보의 id(파일명) 집합
    @Published private(set) var favoriteIDs: Set<String> = []

    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.defaults = defaults
        favoriteIDs = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        reload()
    }

    // MARK: 즐겨찾기·검색

    func isFavorite(_ score: Score) -> Bool {
        favoriteIDs.contains(score.id)
    }

    func toggleFavorite(_ score: Score) {
        if favoriteIDs.contains(score.id) {
            favoriteIDs.remove(score.id)
        } else {
            favoriteIDs.insert(score.id)
        }
        saveFavorites()
    }

    /// 제목 부분 일치(대소문자 무시)로 걸러 즐겨찾기를 앞에 둔 목록
    func filteredScores(query: String, favoritesOnly: Bool) -> [Score] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matched = scores.filter { score in
            (!favoritesOnly || isFavorite(score))
                && (trimmed.isEmpty || score.title.localizedStandardContains(trimmed))
        }
        return matched.filter(isFavorite) + matched.filter { !isFavorite($0) }
    }

    private func saveFavorites() {
        defaults.set(Array(favoriteIDs).sorted(), forKey: Self.favoritesKey)
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

    /// 최초 1회만 샘플을 보관함에 복사한다. 사용자가 지운 샘플은 다시 설치하지 않는다.
    func installSamplesIfNeeded(_ samples: [BundledSample]) {
        guard !defaults.bool(forKey: Self.samplesInstalledKey) else { return }
        for sample in samples {
            let dest = directory.appendingPathComponent("\(sample.title).pdf")
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try? FileManager.default.copyItem(at: sample.url, to: dest)
        }
        defaults.set(true, forKey: Self.samplesInstalledKey)
        reload()
    }

    func delete(_ score: Score) {
        try? FileManager.default.removeItem(at: score.url)
        defaults.removeObject(forKey: lastPageKey(score.id))
        if favoriteIDs.remove(score.id) != nil { saveFavorites() }
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
        if favoriteIDs.remove(score.id) != nil {
            favoriteIDs.insert(dest.lastPathComponent)
            saveFavorites()
        }
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

    private static let samplesInstalledKey = "didInstallSamples"
    private static let favoritesKey = "favoriteScoreIDs"

    private func lastPageKey(_ id: String) -> String { "lastPage.\(id)" }
}
