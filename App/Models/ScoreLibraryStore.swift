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
/// 이전 버전(불리언 플래그 시절)에 설치됐던 샘플 제목은 `legacyTitle`로 기억해 설치 기록을 이관한다.
struct BundledSample {
    let url: URL
    let title: String

    /// 불리언 플래그만 있던 시절에 설치됐던 유일한 샘플의 제목 (종류별)
    static func legacyTitle(for kind: ScoreKind) -> String {
        switch kind {
        case .pdf: return "드뷔시 - 달빛 (Clair de Lune)"
        case .musicXML: return "바흐 - 평균율 1권 전주곡 C장조 (BWV 846)"
        }
    }

    /// 예전 버전에 번들됐다가 빠진 샘플 (제목·확장자). 앱이 설치했던 것만 보관함에서 정리한다.
    struct Retired: Hashable {
        let title: String
        let ext: String
    }

    static func retired(for kind: ScoreKind) -> [Retired] {
        switch kind {
        case .pdf:
            return [
                "쇼팽 - 녹턴 Op.9 No.2",
                "쇼팽 - 연습곡 Op.10 No.12 「혁명」",
                "쇼팽 - 연습곡 Op.10 No.5 「흑건」",
                "사티 - 그노시엔 1번",
                "모차르트 - 피아노 소나타 K.309 1악장",
                "베토벤 - 피아노 소나타 1번 Op.2 No.1 1악장",
                "베토벤 - 피아노 소나타 6번 Op.10 No.2 1악장",
                "슈만 - 어린이 정경 1번 「미지의 나라들」",
                "슈만 - 어린이 정경 7번 「트로이메라이」",
            ].map { Retired(title: $0, ext: "pdf") }
        case .musicXML:
            return [
                "바흐 - 평균율 1권 전주곡 C장조 (BWV 846)",
                "모차르트 - 피아노 소나타 K.545 1악장 (제시부)",
                "조플린 - 메이플 리프 래그",
                "클라라 슈만 - 폴로네즈 Op.1 No.1",
                "클라라 슈만 - 폴로네즈 Op.1 No.2",
                "클라라 슈만 - 폴로네즈 Op.1 No.3",
                "바흐 - 코랄 「예수, 나의 기쁨」 (BWV 227-1)",
                "바흐 - 코랄 「오 피와 상처로 가득한 머리」 (BWV 244-54)",
                "바흐 - 코랄 「내 마음의 깊은 곳에서」 (BWV 269)",
            ].map { Retired(title: $0, ext: "mxl") }
        }
    }

    private static func sample(_ resource: String, _ ext: String, _ title: String) -> BundledSample? {
        Bundle.main.url(forResource: resource, withExtension: ext).map { BundledSample(url: $0, title: title) }
    }

    static func bundled(for kind: ScoreKind) -> [BundledSample] {
        switch kind {
        case .pdf:
            return [
                sample("debussy-clair-de-lune", "pdf", "드뷔시 - 달빛 (Clair de Lune)"),
                sample("beethoven-op27-no2-moonlight", "pdf", "베토벤 - 피아노 소나타 14번 「월광」 Op.27 No.2"),
                sample("beethoven-op13-pathetique-2", "pdf", "베토벤 - 피아노 소나타 8번 「비창」 2악장"),
                sample("chopin-fantaisie-impromptu-op66", "pdf", "쇼팽 - 환상 즉흥곡 Op.66"),
                sample("chopin-prelude-op28-no15-raindrop", "pdf", "쇼팽 - 전주곡 Op.28 No.15 「빗방울」"),
                sample("mozart-k331-3-alla-turca", "pdf", "모차르트 - 터키 행진곡 (K.331 3악장)"),
                sample("schubert-impromptu-op90-no3", "pdf", "슈베르트 - 즉흥곡 Op.90 No.3"),
                sample("rachmaninoff-prelude-op3-no2", "pdf", "라흐마니노프 - 전주곡 Op.3 No.2"),
                sample("joplin-the-entertainer", "pdf", "조플린 - 엔터테이너"),
                sample("bach-bwv971-italian-concerto", "pdf", "바흐 - 이탈리아 협주곡 (BWV 971)"),
            ].compactMap { $0 }
        case .musicXML:
            return [
                sample("debussy-clair-de-lune", "mxl", "드뷔시 - 달빛 (Clair de Lune)"),
                sample("schubert-erlkoenig", "mxl", "슈베르트 - 마왕 (Erlkönig)"),
                sample("schubert-gretchen-am-spinnrade", "mxl", "슈베르트 - 물레 감는 그레트헨"),
                sample("schubert-lindenbaum", "xml", "슈베르트 - 보리수 (Der Lindenbaum)"),
                sample("beethoven-op18-no1-1", "mxl", "베토벤 - 현악 4중주 1번 Op.18 No.1 1악장"),
                sample("mozart-k458-1", "mxl", "모차르트 - 현악 4중주 17번 「사냥」 K.458 1악장"),
                sample("haydn-op74-no1-1", "mxl", "하이든 - 현악 4중주 Op.74 No.1 1악장"),
                sample("dvorak-op96-american", "mxl", "드보르자크 - 현악 4중주 12번 「아메리카」 Op.96"),
                sample("borodin-quartet-no2", "mxl", "보로딘 - 현악 4중주 2번"),
                sample("weber-clarinet-concertino", "mxl", "베버 - 클라리넷 콘체르티노 Op.26"),
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
    /// 번들에서 빠진 샘플(`retired`)은 앱이 설치했던 것(설치 기록에 있는 것)만 필기·즐겨찾기와 함께 지운다.
    /// 사용자가 같은 이름으로 직접 가져온 파일은 설치 기록에 없으므로 남는다.
    func installSamplesIfNeeded(_ samples: [BundledSample], removingRetired retired: [BundledSample.Retired]? = nil) {
        var installed = Set(defaults.stringArray(forKey: kind.installedSamplesKey) ?? [])
        // 이전 버전(불리언 플래그) 호환: 목록이 없고 플래그만 있으면 그 시절의 샘플은 이미 설치된 것으로 본다
        if installed.isEmpty, defaults.bool(forKey: kind.samplesInstalledKey) {
            installed.insert(BundledSample.legacyTitle(for: kind))
        }
        var changed = false
        for old in retired ?? BundledSample.retired(for: kind) where installed.contains(old.title) {
            let url = directory.appendingPathComponent("\(old.title).\(old.ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                delete(Score(id: url.lastPathComponent, url: url, kind: kind))
            }
            installed.remove(old.title)
            changed = true
        }
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
