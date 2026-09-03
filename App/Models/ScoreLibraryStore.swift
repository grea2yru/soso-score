import Foundation
import PDFKit
import UIKit

struct Score: Identifiable, Hashable {
    /// 파일명 (확장자 포함) — 같은 종류의 폴더 안에서 유일
    let id: String
    let url: URL
    let kind: ScoreKind
    var title: String { (id as NSString).deletingPathExtension }
}

/// 앱에 내장된 기본 샘플 악보. 출처와 라이선스는 Samples/LICENSE.md 참고.
/// 목록의 첫 항목은 이전 버전(불리언 플래그 시절)부터 있던 샘플이어야 한다 (설치 기록 이관용).
struct BundledSample {
    let url: URL
    let title: String

    private static func sample(_ resource: String, _ ext: String, _ title: String) -> BundledSample? {
        Bundle.main.url(forResource: resource, withExtension: ext).map { BundledSample(url: $0, title: title) }
    }

    static func bundled(for kind: ScoreKind) -> [BundledSample] {
        switch kind {
        case .pdf:
            return [
                sample("debussy-clair-de-lune", "pdf", "드뷔시 - 달빛 (Clair de Lune)"),
                sample("chopin-nocturne-op9-no2", "pdf", "쇼팽 - 녹턴 Op.9 No.2"),
                sample("chopin-etude-op10-no12", "pdf", "쇼팽 - 연습곡 Op.10 No.12 「혁명」"),
                sample("chopin-etude-op10-no5", "pdf", "쇼팽 - 연습곡 Op.10 No.5 「흑건」"),
                sample("satie-gnossienne-no1", "pdf", "사티 - 그노시엔 1번"),
                sample("mozart-k309-1", "pdf", "모차르트 - 피아노 소나타 K.309 1악장"),
                sample("beethoven-op2-no1-1", "pdf", "베토벤 - 피아노 소나타 1번 Op.2 No.1 1악장"),
                sample("beethoven-op10-no2-1", "pdf", "베토벤 - 피아노 소나타 6번 Op.10 No.2 1악장"),
                sample("schumann-kinderszenen-no1", "pdf", "슈만 - 어린이 정경 1번 「미지의 나라들」"),
                sample("schumann-traeumerei", "pdf", "슈만 - 어린이 정경 7번 「트로이메라이」"),
            ].compactMap { $0 }
        case .musicXML:
            return [
                sample("bach-bwv846", "mxl", "바흐 - 평균율 1권 전주곡 C장조 (BWV 846)"),
                sample("mozart-k545-1", "mxl", "모차르트 - 피아노 소나타 K.545 1악장 (제시부)"),
                sample("joplin-maple-leaf-rag", "mxl", "조플린 - 메이플 리프 래그"),
                sample("cschumann-polonaise-op1-no1", "mxl", "클라라 슈만 - 폴로네즈 Op.1 No.1"),
                sample("cschumann-polonaise-op1-no2", "mxl", "클라라 슈만 - 폴로네즈 Op.1 No.2"),
                sample("cschumann-polonaise-op1-no3", "mxl", "클라라 슈만 - 폴로네즈 Op.1 No.3"),
                sample("bach-bwv227-1", "mxl", "바흐 - 코랄 「예수, 나의 기쁨」 (BWV 227-1)"),
                sample("bach-bwv244-54", "mxl", "바흐 - 코랄 「오 피와 상처로 가득한 머리」 (BWV 244-54)"),
                sample("bach-bwv269", "mxl", "바흐 - 코랄 「내 마음의 깊은 곳에서」 (BWV 269)"),
                sample("schubert-lindenbaum", "xml", "슈베르트 - 보리수 (Der Lindenbaum)"),
            ].compactMap { $0 }
        }
    }
}

@MainActor
final class ScoreLibraryStore: ObservableObject {
    enum LibraryError: LocalizedError {
        case invalidFile(ScoreKind)
        var errorDescription: String? {
            switch self {
            case .invalidFile(.pdf): return L10n.string("PDF 파일을 열 수 없습니다.")
            case .invalidFile(.musicXML): return L10n.string("MusicXML 파일이 아니거나 열 수 없습니다.")
            }
        }
    }

    let kind: ScoreKind
    @Published private(set) var scores: [Score] = []
    /// 즐겨찾기된 악보의 id(파일명) 집합
    @Published private(set) var favoriteIDs: Set<String> = []

    /// 악보별 필기 저장소 (종류 폴더/Annotations)
    let annotations: AnnotationStore

    private let directory: URL
    private let defaults: UserDefaults

    init(kind: ScoreKind = .pdf, directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.kind = kind
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = kind.subdirectory.map { base.appendingPathComponent($0, isDirectory: true) } ?? base
        self.defaults = defaults
        self.annotations = AnnotationStore(directory: self.directory.appendingPathComponent("Annotations", isDirectory: true))
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        favoriteIDs = Set(defaults.stringArray(forKey: kind.favoritesKey) ?? [])
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
        defaults.set(Array(favoriteIDs).sorted(), forKey: kind.favoritesKey)
    }

    // MARK: 파일 관리

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        scores = files
            .filter { kind.allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Score(id: $0.lastPathComponent, url: $0, kind: kind) }
    }

    func importFile(from source: URL) throws {
        // Files 앱 등 외부에서 온 URL은 보안 스코프 접근이 필요할 수 있다
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        guard kind.validate(fileAt: source) else { throw LibraryError.invalidFile(kind) }

        let ext = source.pathExtension.lowercased()
        let base = source.deletingPathExtension().lastPathComponent
        var dest = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = directory.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: dest)
        reload()
    }

    /// 아직 설치한 적 없는 샘플만 보관함에 복사한다. 사용자가 지운 샘플은 다시 설치하지 않으며,
    /// 나중에 추가된 샘플은 기존 사용자에게도 설치된다.
    func installSamplesIfNeeded(_ samples: [BundledSample]) {
        var installed = Set(defaults.stringArray(forKey: kind.installedSamplesKey) ?? [])
        // 이전 버전(불리언 플래그) 호환: 목록이 없고 플래그만 있으면 첫 샘플은 이미 설치된 것으로 본다
        if installed.isEmpty, defaults.bool(forKey: kind.samplesInstalledKey), let first = samples.first {
            installed.insert(first.title)
        }
        var changed = false
        for sample in samples where !installed.contains(sample.title) {
            let dest = directory.appendingPathComponent("\(sample.title).\(sample.url.pathExtension)")
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: sample.url, to: dest)
            }
            installed.insert(sample.title)
            changed = true
        }
        guard changed else { return }
        defaults.set(Array(installed).sorted(), forKey: kind.installedSamplesKey)
        defaults.set(true, forKey: kind.samplesInstalledKey)
        reload()
    }

    func delete(_ score: Score) {
        try? FileManager.default.removeItem(at: score.url)
        defaults.removeObject(forKey: lastPageKey(score.id))
        if favoriteIDs.remove(score.id) != nil { saveFavorites() }
        annotations.delete(for: score.id)
        reload()
    }

    func rename(_ score: Score, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let dest = directory.appendingPathComponent("\(trimmed).\(score.url.pathExtension)")
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
        annotations.move(from: score.id, to: dest.lastPathComponent)
        reload()
    }

    func lastPage(of score: Score) -> Int {
        defaults.integer(forKey: lastPageKey(score.id))
    }

    func setLastPage(_ page: Int, of score: Score) {
        defaults.set(page, forKey: lastPageKey(score.id))
    }

    /// PDF만 첫 페이지 썸네일을 만든다. 디지털 악보는 아이콘으로 표시.
    func thumbnail(for score: Score, size: CGSize) -> UIImage? {
        guard kind == .pdf else { return nil }
        return PDFDocument(url: score.url)?.page(at: 0)?.thumbnail(of: size, for: .mediaBox)
    }

    private func lastPageKey(_ id: String) -> String { "\(kind.lastPageKeyPrefix)\(id)" }
}
