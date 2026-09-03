# 2A. 디지털 악보(MusicXML) 뷰어 + 탭 구조 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MusicXML 악보를 가져와 PDF 악보와 같은 경험(보관함·펼침·제스처 넘김·필기)으로 보고, 상단 탭으로 두 종류를 구분한다.

**Architecture:** Verovio(WASM)를 숨김 WKWebView 1개에 올려 A4 비율 고정 가상 페이지로 조판한 SVG를 받고, 가벼운 SVG 표시 웹뷰가 페이지를 보여준다. 기존 PDF 뷰어에서 페이지 소스와 무관한 부분을 `ScoreViewerShell`로 분리해 두 뷰어가 공유하고, `ScoreLibraryStore`를 `ScoreKind`로 일반화해 보관함 UI를 재사용한다.

**Tech Stack:** SwiftUI, WebKit(WKWebView), Verovio 6.3.0 (verovio-toolkit-wasm.js, LGPL-3.0), PencilKit, XCTest, XcodeGen

**Spec:** `docs/superpowers/specs/2026-09-03-musicxml-viewer-design.md`

## Global Constraints

- iPadOS 18.0+, iPad 전용. 외부 런타임 의존성은 번들된 Verovio JS만 (네트워크 사용 없음)
- 가상 페이지: Verovio `pageWidth: 2100`, `pageHeight: 2970`, `scale: 40`, `breaks: "auto"`, `adjustPageHeight: false`, `footer: "none"`, `svgViewBox: true`
- 디지털 악보의 필기 정규화 좌표계 = **595 × 842 pt** (A4). 표시 배율 = 표시 폭 ÷ 595
- 종류별 키/폴더 (스펙 그대로): pdf = `Documents/`, `favoriteScoreIDs`, `didInstallSamples`, `lastPage.`; musicXML = `Documents/MusicXML/`, `favoriteScoreIDs.musicxml`, `didInstallSamples.musicxml`, `lastPage.musicxml.`; 필기는 각 폴더의 `Annotations/`
- 허용 확장자: pdf = `pdf`; musicXML = `musicxml`, `mxl`, `xml`. UTType: `com.yru.musicxml`(public.xml 준수), `com.yru.mxl`(public.data 준수)
- 기존 PDF 동작·테스트(GestureCore 22, 앱 31)는 모두 유지되어야 함
- 사용자 문구는 한국어. 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 빌드/테스트 명령은 샌드박스 우회로 실행 (`xcodebuild`, `simctl`이 샌드박스에서 실패함). 시뮬레이터: `iPad Pro 13-inch (M5)`

## 파일 구조

```
Vendor/verovio/
├── verovio-toolkit-wasm.js       # Verovio 6.3.0 (다운로드: unpkg.com/verovio@6.3.0/dist/)
└── verovio.html                  # 엔진 페이지: toolkit 초기화 + window.vrv API
Vendor/LICENSE.md                 # Verovio LGPL 고지
Samples/bach-bwv846.mxl           # 기본 디지털 샘플 (music21 corpus, PD)
App/
├── ScoreApp.swift                # 저장소 2개 생성, RootTabView, onOpenURL 라우팅
├── Models/
│   ├── ScoreKind.swift           # 종류별 폴더/확장자/키/검증/UTType
│   ├── ScoreLibraryStore.swift   # kind 일반화 (수정)
│   ├── PageNavigator.swift       # 변경 없음
│   └── AnnotationStore.swift     # 변경 없음
├── MusicXML/
│   ├── VerovioEngine.swift       # 숨김 WKWebView 엔진 래퍼
│   ├── SVGPageView.swift         # SVG 1페이지 표시 웹뷰 (+highlight)
│   └── MusicXMLScoreViewer.swift # 엔진 → Shell 연결
├── Views/
│   ├── RootTabView.swift         # 3탭
│   ├── LibraryView.swift         # library 파라미터화, kind별 목적지 (수정)
│   ├── SpreadView.swift          # 콘텐츠 빌더 일반화 (수정)
│   ├── PDFPageImage.swift        # SpreadView에서 분리 (신규 파일, 기존 코드 이동)
│   ├── ScoreViewerShell.swift    # 뷰어 공통 (기존 ScoreViewerView에서 추출)
│   ├── PDFScoreViewer.swift      # PDF 문서 로드 → Shell (기존 ScoreViewerView 대체)
│   ├── PencilCanvasView.swift    # 변경 없음
│   └── SettingsView.swift        # 변경 없음
└── AppTests/
    ├── VerovioEngineTests.swift
    ├── ScoreKindTests.swift
    └── ScoreLibraryStoreTests.swift (musicXML 케이스 추가)
```

---

### Task 1: Verovio 번들 + VerovioEngine

**Files:**
- Create: `Vendor/verovio/verovio-toolkit-wasm.js` (다운로드), `Vendor/verovio/verovio.html`, `Vendor/LICENSE.md`
- Create: `Samples/bach-bwv846.mxl` (다운로드), `Samples/LICENSE.md`에 항목 추가
- Create: `App/MusicXML/VerovioEngine.swift`
- Test: `AppTests/VerovioEngineTests.swift`
- Modify: `project.yml` (Vendor 폴더 리소스 추가)

**Interfaces:**
- Produces:
  - `enum VerovioError: LocalizedError { notReady, loadFailed(String), scriptFailed(String) }`
  - `@MainActor final class VerovioEngine` — `static let shared`, `init()`,
    `func load(fileURL: URL) async throws -> Int`(페이지 수), `func pageSVG(_ index: Int) async throws -> String`(0-based, 캐시),
    `func timemap() async throws -> Data`, `func pageWithElement(_ id: String) async throws -> Int`(0-based)

- [ ] **Step 1: 파일 다운로드와 라이선스 기록**

```bash
mkdir -p Vendor/verovio
curl -sL -o Vendor/verovio/verovio-toolkit-wasm.js "https://unpkg.com/verovio@6.3.0/dist/verovio-toolkit-wasm.js"
curl -sL -o Samples/bach-bwv846.mxl "https://raw.githubusercontent.com/cuthbertLab/music21/master/music21/corpus/bach/bwv846.mxl"
ls -la Vendor/verovio Samples   # js ≈ 7.3MB, mxl ≈ 7.7KB
```

`Vendor/LICENSE.md`:

```markdown
# 서드파티 구성요소

## Verovio 6.3.0 — `verovio/verovio-toolkit-wasm.js`
- 출처: https://www.verovio.org / https://github.com/rism-digital/verovio (npm `verovio@6.3.0`)
- 라이선스: LGPL-3.0-or-later. 수정 없이 번들함. 라이선스 전문: https://www.gnu.org/licenses/lgpl-3.0.html
```

`Samples/LICENSE.md`에 추가:

```markdown
## bach-bwv846.mxl
- 곡: J. S. Bach, 평균율 클라비어곡집 1권 전주곡 C장조 BWV 846
- 출처: music21 corpus (https://github.com/cuthbertLab/music21, `corpus/bach/bwv846.mxl`, MuseScore 1.3 전사)
- 라이선스: 퍼블릭 도메인 작품, music21 corpus 수록본(자유 재배포 가능)
```

- [ ] **Step 2: 엔진 HTML 작성**

`Vendor/verovio/verovio.html`:

```html
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<script src="verovio-toolkit-wasm.js"></script>
</head><body>
<script>
window.vrvReady = false;
let tk = null;
verovio.module.onRuntimeInitialized = () => {
  tk = new verovio.toolkit();
  tk.setOptions({
    breaks: "auto", adjustPageHeight: false, footer: "none", header: "auto",
    svgViewBox: true, scale: 40,
    pageWidth: 2100, pageHeight: 2970,
    pageMarginTop: 100, pageMarginBottom: 100, pageMarginLeft: 100, pageMarginRight: 100
  });
  window.vrvReady = true;
};
function b64ToBytes(b64) {
  const bin = atob(b64); const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
window.vrv = {
  load: (base64, isZip) => {
    const bytes = b64ToBytes(base64);
    const ok = isZip ? tk.loadZipDataBuffer(bytes.buffer)
                     : tk.loadData(new TextDecoder("utf-8").decode(bytes));
    if (!ok) return -1;
    return tk.getPageCount();
  },
  pageSVG: (n) => tk.renderToSVG(n, false),
  timemap: () => JSON.stringify(tk.renderToTimemap({ includeMeasures: true, includeRests: false })),
  midi: (id) => JSON.stringify(tk.getMIDIValuesForElement(id)),
  pageWithElement: (id) => tk.getPageWithElement(id)
};
</script>
</body></html>
```

- [ ] **Step 3: project.yml에 Vendor 리소스 추가**

`sources:` 아래에 추가 (폴더 참조로 복사되어 번들 내 `verovio/` 하위에 들어감):

```yaml
      - path: Vendor/verovio
        type: folder
        buildPhase: resources
```

- [ ] **Step 4: 실패하는 테스트 작성**

`AppTests/VerovioEngineTests.swift`:

```swift
import XCTest
@testable import ScoreForYou

@MainActor
final class VerovioEngineTests: XCTestCase {
    func testLoadsSampleRendersPagesAndTimemap() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "bach-bwv846", withExtension: "mxl"))
        let engine = VerovioEngine()

        let pageCount = try await engine.load(fileURL: url)
        XCTAssertGreaterThan(pageCount, 0)

        let svg = try await engine.pageSVG(0)
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("class=\"note\""))

        let map = try await engine.timemap()
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: map) as? [[String: Any]])
        XCTAssertTrue(entries.contains { (($0["on"] as? [String])?.isEmpty == false) })
    }

    func testLoadInvalidFileThrows() async throws {
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad.musicxml")
        try Data("<not-music/>".utf8).write(to: bad)
        let engine = VerovioEngine()
        do {
            _ = try await engine.load(fileURL: bad)
            XCTFail("손상 파일이 열리면 안 됨")
        } catch let error as VerovioError {
            guard case .loadFailed = error else { return XCTFail("loadFailed 기대, 실제: \(error)") }
        }
    }
}
```

- [ ] **Step 5: 테스트 실행 — 실패 확인**

Run: `xcodegen generate -q && xcodebuild test -project ScoreForYou.xcodeproj -scheme ScoreForYou -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -derivedDataPath build 2>&1 | grep -E "TEST |error:" | sort -u`
Expected: `cannot find 'VerovioEngine' in scope`

- [ ] **Step 6: 구현**

`App/MusicXML/VerovioEngine.swift`:

```swift
import Foundation
import WebKit

enum VerovioError: LocalizedError {
    case notReady
    case loadFailed(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "악보 엔진이 준비되지 않았습니다."
        case .loadFailed(let detail): return "악보를 열 수 없습니다. (\(detail))"
        case .scriptFailed(let detail): return "악보 렌더링 오류: \(detail)"
        }
    }
}

/// Verovio(WASM)를 숨김 WKWebView에 올려 MusicXML을 A4 비율 고정 가상 페이지로 조판한다.
/// 한 번에 악보 하나만 열려 있으며, 페이지 SVG는 메모리에 캐시한다.
@MainActor
final class VerovioEngine {
    static let shared = VerovioEngine()

    private let webView: WKWebView
    private var isReady = false
    private var pageCache: [Int: String] = [:]

    init() {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        if let url = Bundle.main.url(forResource: "verovio", withExtension: "html", subdirectory: "verovio") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    /// WASM 초기화 완료를 최대 30초 기다린다 (100ms 폴링)
    private func waitUntilReady() async throws {
        if isReady { return }
        for _ in 0..<300 {
            if let ready = try? await webView.evaluateJavaScript("window.vrvReady === true") as? Bool, ready {
                isReady = true
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw VerovioError.notReady
    }

    private func evaluate(_ script: String) async throws -> Any {
        do {
            return try await webView.evaluateJavaScript(script)
        } catch {
            throw VerovioError.scriptFailed(error.localizedDescription)
        }
    }

    /// 파일을 로드하고 페이지 수를 반환한다. .mxl(ZIP)은 자동 판별.
    func load(fileURL: URL) async throws -> Int {
        try await waitUntilReady()
        let data = try Data(contentsOf: fileURL)
        let isZip = fileURL.pathExtension.lowercased() == "mxl" || data.starts(with: [0x50, 0x4B])
        pageCache = [:]
        let result = try await evaluate("window.vrv.load(\"\(data.base64EncodedString())\", \(isZip))")
        guard let count = result as? Int, count > 0 else {
            throw VerovioError.loadFailed("조판 실패")
        }
        return count
    }

    func pageSVG(_ index: Int) async throws -> String {
        if let cached = pageCache[index] { return cached }
        guard let svg = try await evaluate("window.vrv.pageSVG(\(index + 1))") as? String else {
            throw VerovioError.scriptFailed("SVG 없음")
        }
        pageCache[index] = svg
        return svg
    }

    func timemap() async throws -> Data {
        guard let json = try await evaluate("window.vrv.timemap()") as? String else {
            throw VerovioError.scriptFailed("타임맵 없음")
        }
        return Data(json.utf8)
    }

    func pageWithElement(_ id: String) async throws -> Int {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        guard let page = try await evaluate("window.vrv.pageWithElement(\"\(escaped)\")") as? Int else {
            throw VerovioError.scriptFailed("페이지 조회 실패")
        }
        return page - 1
    }
}
```

- [ ] **Step 7: 테스트 실행 — 통과 확인**

Run: 같은 명령
Expected: `TEST SUCCEEDED`, VerovioEngineTests 2개 통과 (WASM 초기화로 첫 테스트가 수 초 걸릴 수 있음)

- [ ] **Step 8: Commit**

```bash
git add Vendor Samples App/MusicXML/VerovioEngine.swift AppTests/VerovioEngineTests.swift project.yml
git commit -m "feat: Verovio 엔진 번들 및 VerovioEngine(MusicXML 조판·타임맵) + BWV 846 샘플"
```

---

### Task 2: ScoreKind와 ScoreLibraryStore 일반화

**Files:**
- Create: `App/Models/ScoreKind.swift`
- Modify: `App/Models/ScoreLibraryStore.swift`
- Test: `AppTests/ScoreKindTests.swift`, `AppTests/ScoreLibraryStoreTests.swift` (musicXML 케이스 추가)

**Interfaces:**
- Produces:
  - `enum ScoreKind: String, CaseIterable { case pdf, musicXML }` + `title`, `symbolName`, `subdirectory: String?`,
    `allowedExtensions: Set<String>`, `favoritesKey`, `samplesInstalledKey`, `lastPageKeyPrefix`, `contentTypes: [UTType]`,
    `func validate(fileAt url: URL) -> Bool`, `static func kind(forExtension:) -> ScoreKind?`
  - `extension UTType { static let musicXML; static let mxl }`
  - `Score.kind: ScoreKind`
  - `ScoreLibraryStore.init(kind: ScoreKind = .pdf, directory: URL? = nil, defaults: UserDefaults = .standard)`, `let kind`
  - `BundledSample.bundled(for kind: ScoreKind) -> [BundledSample]`
- 기존 API(`importPDF(from:)` 이름은 `importFile(from:)`로 변경, 호출부 함께 수정)

- [ ] **Step 1: 실패하는 테스트 작성**

`AppTests/ScoreKindTests.swift`:

```swift
import XCTest
@testable import ScoreForYou

final class ScoreKindTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func testKindForExtension() {
        XCTAssertEqual(ScoreKind.kind(forExtension: "PDF"), .pdf)
        XCTAssertEqual(ScoreKind.kind(forExtension: "musicxml"), .musicXML)
        XCTAssertEqual(ScoreKind.kind(forExtension: "mxl"), .musicXML)
        XCTAssertEqual(ScoreKind.kind(forExtension: "xml"), .musicXML)
        XCTAssertNil(ScoreKind.kind(forExtension: "txt"))
    }

    func testMusicXMLValidation() throws {
        let partwise = try write("a.musicxml", Array("<?xml version=\"1.0\"?><score-partwise></score-partwise>".utf8))
        let timewise = try write("b.xml", Array("<score-timewise/>".utf8))
        let notMusic = try write("c.musicxml", Array("<html></html>".utf8))
        let mxl = try write("d.mxl", [0x50, 0x4B, 0x03, 0x04, 0, 0])
        let badMxl = try write("e.mxl", [0x00, 0x01])
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: partwise))
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: timewise))
        XCTAssertFalse(ScoreKind.musicXML.validate(fileAt: notMusic))
        XCTAssertTrue(ScoreKind.musicXML.validate(fileAt: mxl))
        XCTAssertFalse(ScoreKind.musicXML.validate(fileAt: badMxl))
    }

    func testKeysAreDistinct() {
        XCTAssertNotEqual(ScoreKind.pdf.favoritesKey, ScoreKind.musicXML.favoritesKey)
        XCTAssertNotEqual(ScoreKind.pdf.samplesInstalledKey, ScoreKind.musicXML.samplesInstalledKey)
        XCTAssertNotEqual(ScoreKind.pdf.lastPageKeyPrefix, ScoreKind.musicXML.lastPageKeyPrefix)
        XCTAssertEqual(ScoreKind.pdf.favoritesKey, "favoriteScoreIDs")   // 기존 데이터 호환
        XCTAssertNil(ScoreKind.pdf.subdirectory)
        XCTAssertEqual(ScoreKind.musicXML.subdirectory, "MusicXML")
    }
}
```

`AppTests/ScoreLibraryStoreTests.swift`에 추가 (기존 `makeStore()`는 pdf 기본값 유지):

```swift
    // MARK: MusicXML 종류

    func makeXMLStore() -> ScoreLibraryStore {
        ScoreLibraryStore(kind: .musicXML, directory: tempDir, defaults: defaults)
    }

    func makeMusicXML(named name: String) throws -> URL {
        let url = sourceDir.appendingPathComponent("\(name).musicxml")
        try Data("<?xml version=\"1.0\"?><score-partwise version=\"3.1\"><part-list/></score-partwise>".utf8).write(to: url)
        return url
    }

    func testMusicXMLStoreUsesSubdirectoryAndKeepsExtension() throws {
        let store = makeXMLStore()
        try store.importFile(from: try makeMusicXML(named: "인벤션 1번"))
        XCTAssertEqual(store.scores.map(\.title), ["인벤션 1번"])
        XCTAssertEqual(store.scores[0].kind, .musicXML)
        XCTAssertEqual(store.scores[0].url.pathExtension, "musicxml")
        XCTAssertEqual(store.scores[0].url.deletingLastPathComponent().lastPathComponent, "MusicXML")
    }

    func testMusicXMLStoreRejectsPDFAndInvalidXML() throws {
        let store = makeXMLStore()
        XCTAssertThrowsError(try store.importFile(from: try makePDF(named: "pdf파일")))
        let bad = sourceDir.appendingPathComponent("bad.musicxml")
        try Data("<html/>".utf8).write(to: bad)
        XCTAssertThrowsError(try store.importFile(from: bad))
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testFavoritesAreSeparatedByKind() throws {
        let pdfStore = makeStore()
        let xmlStore = makeXMLStore()
        try pdfStore.importFile(from: try makePDF(named: "같은이름"))
        try xmlStore.importFile(from: try makeMusicXML(named: "같은이름"))
        pdfStore.toggleFavorite(pdfStore.scores[0])
        XCTAssertFalse(xmlStore.isFavorite(xmlStore.scores[0]))
    }

    func testLastPageIsSeparatedByKind() throws {
        let pdfStore = makeStore()
        let xmlStore = makeXMLStore()
        try pdfStore.importFile(from: try makePDF(named: "곡"))
        try xmlStore.importFile(from: try makeMusicXML(named: "곡"))
        pdfStore.setLastPage(3, of: pdfStore.scores[0])
        XCTAssertEqual(xmlStore.lastPage(of: xmlStore.scores[0]), 0)
    }

    func testRenameKeepsOriginalExtension() throws {
        let store = makeXMLStore()
        try store.importFile(from: try makeMusicXML(named: "옛"))
        store.rename(store.scores[0], to: "새")
        XCTAssertEqual(store.scores[0].id, "새.musicxml")
    }
```

기존 테스트의 `importPDF(` 호출을 모두 `importFile(`로 바꾼다 (sed):

```bash
sed -i '' 's/importPDF(/importFile(/g' AppTests/ScoreLibraryStoreTests.swift
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Expected: `cannot find 'ScoreKind' in scope`, `has no member 'importFile'`

- [ ] **Step 3: ScoreKind 구현**

`App/Models/ScoreKind.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// .musicxml (Info.plist UTImportedTypeDeclarations에 선언)
    static let musicXML = UTType(importedAs: "com.yru.musicxml")
    /// .mxl (압축 MusicXML)
    static let mxl = UTType(importedAs: "com.yru.mxl")
}

/// 악보 종류. 폴더·확장자·UserDefaults 키·검증 규칙을 한곳에 모은다.
enum ScoreKind: String, CaseIterable, Hashable {
    case pdf
    case musicXML

    var title: String {
        switch self {
        case .pdf: return "PDF 악보"
        case .musicXML: return "디지털 악보"
        }
    }

    var symbolName: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .musicXML: return "music.note.list"
        }
    }

    /// Documents 아래 하위 폴더. nil이면 Documents 루트(기존 PDF 위치 유지)
    var subdirectory: String? {
        switch self {
        case .pdf: return nil
        case .musicXML: return "MusicXML"
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .pdf: return ["pdf"]
        case .musicXML: return ["musicxml", "mxl", "xml"]
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .pdf: return [.pdf]
        case .musicXML: return [.musicXML, .mxl, .xml]
        }
    }

    var favoritesKey: String {
        switch self {
        case .pdf: return "favoriteScoreIDs"
        case .musicXML: return "favoriteScoreIDs.musicxml"
        }
    }

    var samplesInstalledKey: String {
        switch self {
        case .pdf: return "didInstallSamples"
        case .musicXML: return "didInstallSamples.musicxml"
        }
    }

    var lastPageKeyPrefix: String {
        switch self {
        case .pdf: return "lastPage."
        case .musicXML: return "lastPage.musicxml."
        }
    }

    static func kind(forExtension ext: String) -> ScoreKind? {
        let lower = ext.lowercased()
        return allCases.first { $0.allowedExtensions.contains(lower) }
    }

    /// 가져오기 전에 파일이 이 종류로 열릴 수 있는지 가볍게 검사한다.
    func validate(fileAt url: URL) -> Bool {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return false }
        switch self {
        case .pdf:
            return PDFDocument(url: url) != nil
        case .musicXML:
            guard let handle = try? FileHandle(forReadingFrom: url),
                  let head = try? handle.read(upToCount: 64 * 1024) else { return false }
            if url.pathExtension.lowercased() == "mxl" {
                return head.starts(with: [0x50, 0x4B])   // ZIP 매직
            }
            guard let text = String(data: head, encoding: .utf8) else { return false }
            return text.contains("<score-partwise") || text.contains("<score-timewise")
        }
    }
}
```

파일 상단에 `import PDFKit` 추가.

- [ ] **Step 4: ScoreLibraryStore 수정**

`Score`에 `let kind: ScoreKind` 추가 (init 호출부 `Score(id:url:kind:)`). `BundledSample`:

```swift
struct BundledSample {
    let url: URL
    let title: String

    static func bundled(for kind: ScoreKind) -> [BundledSample] {
        switch kind {
        case .pdf:
            guard let url = Bundle.main.url(forResource: "debussy-clair-de-lune", withExtension: "pdf") else { return [] }
            return [BundledSample(url: url, title: "드뷔시 - 달빛 (Clair de Lune)")]
        case .musicXML:
            guard let url = Bundle.main.url(forResource: "bach-bwv846", withExtension: "mxl") else { return [] }
            return [BundledSample(url: url, title: "바흐 - 평균율 1권 전주곡 C장조 (BWV 846)")]
        }
    }
}
```

스토어 본문 변경 (핵심 부분만; 나머지는 유지):

```swift
    let kind: ScoreKind
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

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        scores = files
            .filter { kind.allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Score(id: $0.lastPathComponent, url: $0, kind: kind) }
    }

    func importFile(from source: URL) throws {
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
```

- `LibraryError`: `case invalidFile(ScoreKind)` → 문구 pdf: "PDF 파일을 열 수 없습니다.", musicXML: "MusicXML 파일이 아니거나 열 수 없습니다."
- `installSamplesIfNeeded`: 키 `kind.samplesInstalledKey`, 대상 파일명 `"\(sample.title).\(sample.url.pathExtension)"`
- `rename`: `dest = directory.appendingPathComponent("\(trimmed).\(score.url.pathExtension)")`
- `saveFavorites`/init: `kind.favoritesKey`; `lastPageKey(_ id:)` → `"\(kind.lastPageKeyPrefix)\(id)"`
- `thumbnail(for:size:)`: `guard kind == .pdf else { return nil }`
- 호출부(`LibraryView`, `ScoreApp`)의 `importPDF` → `importFile`, `BundledSample.bundled` → `.bundled(for: .pdf)`

- [ ] **Step 5: 테스트 실행 — 통과 확인**

Expected: `TEST SUCCEEDED` (기존 31 + ScoreKind 3 + 스토어 5 + Verovio 2 = 41)

- [ ] **Step 6: Commit**

```bash
git add App/Models AppTests App/Views/LibraryView.swift App/ScoreApp.swift
git commit -m "feat: ScoreKind 도입 — 저장소를 PDF/MusicXML 종류별 폴더·키·검증으로 일반화"
```

---

### Task 3: SpreadView 일반화 + ScoreViewerShell + PDFScoreViewer

**Files:**
- Modify: `App/Views/SpreadView.swift` (콘텐츠 빌더 일반화)
- Create: `App/Views/PDFPageImage.swift` (기존 코드 이동·단순화)
- Create: `App/Views/ScoreViewerShell.swift` (기존 `ScoreViewerView` 본문 이동)
- Create: `App/Views/PDFScoreViewer.swift`
- Delete: `App/Views/ScoreViewerView.swift`
- Modify: `App/Views/LibraryView.swift` (목적지를 `PDFScoreViewer`로)

**Interfaces:**
- Produces:
  - `SpreadView<Content: View, Overlay: View>(indices: [Int], twoUp: Bool, pageSize: (Int) -> CGSize, content: (Int) -> Content, overlay: (Int, CGFloat) -> Overlay)`
  - `PDFPageImage(page: PDFPage)` — 자신의 프레임에 맞춰 렌더링
  - `ScoreViewerShell<Content: View>(score: Score, library: ScoreLibraryStore, pageCount: Int, pageSize: (Int) -> CGSize, content: (Int) -> Content)`
  - `PDFScoreViewer(score: Score, library: ScoreLibraryStore)`

- [ ] **Step 1: SpreadView 일반화**

`App/Views/SpreadView.swift` 전체 교체:

```swift
import SwiftUI

/// 한 페이지 또는 두 페이지(책 펼침)를 표시한다. 페이지 내용은 `content`가, 페이지 위 겹침은 `overlay`가 만든다.
/// 펼침에서 오른쪽 페이지가 없으면(홀수 마지막) 왼쪽만 채우고 오른쪽은 비워 둔다.
struct SpreadView<Content: View, Overlay: View>: View {
    let indices: [Int]
    let twoUp: Bool
    /// 페이지의 정규화 좌표계 크기 (가로세로 비율과 필기 배율 계산에 사용)
    let pageSize: (Int) -> CGSize
    let content: (Int) -> Content
    /// (페이지 인덕스, 표시 배율 = 표시 폭 ÷ pageSize.width)
    let overlay: (Int, CGFloat) -> Overlay

    init(indices: [Int], twoUp: Bool,
         pageSize: @escaping (Int) -> CGSize,
         @ViewBuilder content: @escaping (Int) -> Content,
         @ViewBuilder overlay: @escaping (Int, CGFloat) -> Overlay) {
        self.indices = indices
        self.twoUp = twoUp
        self.pageSize = pageSize
        self.content = content
        self.overlay = overlay
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<(twoUp ? 2 : 1), id: \.self) { slot in
                if slot < indices.count {
                    let index = indices[slot]
                    PageSlot(pageSize: pageSize(index), alignment: alignment(for: slot)) {
                        content(index)
                    } overlay: { scale in
                        overlay(index, scale)
                    }
                } else {
                    Color.clear
                }
            }
        }
    }

    private func alignment(for slot: Int) -> Alignment {
        guard twoUp else { return .center }
        return slot == 0 ? .trailing : .leading
    }
}

/// 주어진 영역에 페이지 비율을 유지하며 맞추고, 같은 크기로 오버레이를 겹친다.
struct PageSlot<Content: View, Overlay: View>: View {
    let pageSize: CGSize
    let alignment: Alignment
    @ViewBuilder let content: () -> Content
    @ViewBuilder let overlay: (CGFloat) -> Overlay

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fitScale(pageSize: pageSize, into: geo.size)
            let shown = CGSize(width: pageSize.width * fit, height: pageSize.height * fit)
            ZStack {
                content()
                overlay(fit)
            }
            .frame(width: shown.width, height: shown.height)
            .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
    }

    static func fitScale(pageSize: CGSize, into size: CGSize) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0, size.width > 0, size.height > 0 else { return 1 }
        return min(size.width / pageSize.width, size.height / pageSize.height)
    }
}
```

`App/Views/PDFPageImage.swift`:

```swift
import SwiftUI
import PDFKit

/// PDFPage 하나를 자신의 프레임 크기에 맞춰 화면 해상도로 렌더링해 표시한다.
struct PDFPageImage: View {
    let page: PDFPage
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private struct RenderKey: Equatable {
        let page: ObjectIdentifier
        let size: CGSize
        let scale: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image).resizable()
                } else {
                    Color.white
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: RenderKey(page: ObjectIdentifier(page), size: geo.size, scale: displayScale)) {
                let target = geo.size
                let scale = displayScale
                image = await Task.detached(priority: .userInitiated) {
                    Self.render(page, size: target, scale: scale)
                }.value
            }
        }
    }

    /// 페이지 회전(/Rotate 90·270)을 반영한 표시 기준 크기
    static func displaySize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        return page.rotation % 180 != 0
            ? CGSize(width: bounds.height, height: bounds.width)
            : CGSize(width: bounds.width, height: bounds.height)
    }

    private static func render(_ page: PDFPage, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
    }
}
```

- [ ] **Step 2: ScoreViewerShell 작성**

`App/Views/ScoreViewerShell.swift` — 기존 `ScoreViewerView`에서 문서 로딩만 빼고 옮긴다:

```swift
import SwiftUI
import PencilKit
import GestureCore

/// 페이지 소스와 무관한 뷰어 공통부: 펼침 배치, 탭/얼굴 제스처 넘김, 플래시, 페이지 표시,
/// 필기 모드(PencilKit) + 저장, 마지막 페이지 기억.
struct ScoreViewerShell<Content: View>: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    let pageCount: Int
    /// 페이지의 정규화 좌표계 크기 (필기 좌표 기준)
    let pageSize: (Int) -> CGSize
    @ViewBuilder let content: (Int) -> Content

    @EnvironmentObject var settings: AppSettings
    @StateObject private var tracker = FaceTrackingSession()
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentPageIndex = 0
    @State private var flashEdge: Edge?
    @State private var isTwoUp = false
    @State private var isAnnotating = false
    @State private var drawings: [Int: PKDrawing] = [:]
    @State private var toolPicker = PKToolPicker(toolItems: [
        PKToolPickerInkingItem(type: .pen),
        PKToolPickerInkingItem(type: .marker),
        PKToolPickerInkingItem(type: .pencil),
        PKToolPickerEraserItem(type: .vector),
        PKToolPickerLassoItem(),
    ])

    private var navigator: PageNavigator { PageNavigator(pageCount: pageCount, twoUp: isTwoUp) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpreadView(indices: navigator.visibleIndices(from: currentPageIndex), twoUp: isTwoUp,
                           pageSize: pageSize) { index in
                    content(index)
                } overlay: { index, scale in
                    PencilCanvasView(drawing: drawingBinding(for: index), scale: scale,
                                     isActive: isAnnotating, toolPicker: toolPicker)
                        .id(index)
                }
                .padding(.horizontal, 8)

                if !isAnnotating {
                    HStack(spacing: 0) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { turn(.previous) }
                        Color.clear.frame(width: geo.size.width * 0.4)
                        Color.clear.contentShape(Rectangle()).onTapGesture { turn(.next) }
                    }
                }

                if tracker.didFail {
                    VStack {
                        Text("카메라를 사용할 수 없어 손·탭으로만 넘길 수 있습니다. 설정 앱 > 개인정보 보호 > 카메라에서 권한을 확인하세요.")
                            .font(.footnote).padding(10)
                            .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }

                if let edge = flashEdge { FlashOverlay(edge: edge) }
            }
            .onAppear { isTwoUp = geo.size.width > geo.size.height }
            .onChange(of: geo.size) { _, size in isTwoUp = size.width > size.height }
        }
        .background(Color(.systemBackground))
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $isAnnotating) {
                    Image(systemName: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                }
                .toggleStyle(.button)
                .accessibilityLabel("필기 모드")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(tracker.isTrackingFace ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(tracker.isTrackingFace ? "얼굴 추적 중" : "얼굴 미검출")
                    Text(pageLabel).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            currentPageIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
            drawings = library.annotations.load(for: score.id)
            tracker.updateSettings(settings.gesture)
            tracker.start()
        }
        .onDisappear {
            tracker.pause()
            library.setLastPage(currentPageIndex, of: score)
            saveDrawings()
        }
        .onChange(of: isTwoUp) { _, _ in currentPageIndex = navigator.leadingIndex(from: currentPageIndex) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { tracker.start() } else { tracker.pause() } }
        .onChange(of: settings.gesture) { _, newValue in tracker.updateSettings(newValue) }
        .onReceive(tracker.events) { turn($0) }
    }

    private func drawingBinding(for pageIndex: Int) -> Binding<PKDrawing> {
        Binding(get: { drawings[pageIndex] ?? PKDrawing() },
                set: { drawings[pageIndex] = $0; saveDrawings() })
    }

    private func saveDrawings() { try? library.annotations.save(drawings, for: score.id) }

    private var pageLabel: String {
        let visible = navigator.visibleIndices(from: currentPageIndex).map { $0 + 1 }
        guard let first = visible.first else { return "0 / \(pageCount)" }
        if let last = visible.last, last != first { return "\(first)–\(last) / \(pageCount)" }
        return "\(first) / \(pageCount)"
    }

    func turn(_ event: PageTurnEvent) {
        let target = event == .next ? navigator.next(from: currentPageIndex) : navigator.previous(from: currentPageIndex)
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

struct FlashOverlay: View {
    let edge: Edge
    var body: some View {
        HStack {
            if edge == .trailing { Spacer() }
            Rectangle().fill(Color.accentColor.opacity(0.35)).frame(width: 24)
            if edge == .leading { Spacer() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
```

`App/Views/PDFScoreViewer.swift`:

```swift
import SwiftUI
import PDFKit

/// PDF 문서를 열어 ScoreViewerShell에 페이지를 공급한다.
struct PDFScoreViewer: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    @State private var document: PDFDocument?
    @State private var failed = false

    var body: some View {
        Group {
            if let document {
                ScoreViewerShell(score: score, library: library, pageCount: document.pageCount,
                                 pageSize: { index in
                                     document.page(at: index).map(PDFPageImage.displaySize(of:)) ?? CGSize(width: 595, height: 842)
                                 }) { index in
                    if let page = document.page(at: index) {
                        PDFPageImage(page: page)
                    } else {
                        Color.white
                    }
                }
            } else if failed {
                ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard document == nil else { return }
            if let doc = PDFDocument(url: score.url) { document = doc } else { failed = true }
        }
    }
}
```

`ScoreViewerView.swift` 삭제. `LibraryView`의 목적지 → `PDFScoreViewer(score: score, library: library)` (Task 5에서 kind 분기로 다시 수정). `LibraryView`/`ScoreCell`/`ScoreActions`의 `@EnvironmentObject var library`를 `@ObservedObject var library: ScoreLibraryStore`로 바꾸고 `LibraryView(library:)`로 주입 (`ScoreApp`에서 `LibraryView(library: library)`).

- [ ] **Step 3: 빌드·전체 테스트 통과 확인 + PDF 회귀 수동 확인**

Run: 테스트 명령. Expected: `TEST SUCCEEDED` (41)
시뮬레이터: 드뷔시 열기 → 펼침/탭 넘김/필기 복원(앞서 그린 빨간 획이 같은 자리)/페이지 기억 확인.

- [ ] **Step 4: Commit**

```bash
git add -A App/Views App/ScoreApp.swift
git commit -m "refactor: 뷰어 공통부를 ScoreViewerShell로 분리, SpreadView 콘텐츠 빌더 일반화"
```

---

### Task 4: SVGPageView + MusicXMLScoreViewer

**Files:**
- Create: `App/MusicXML/SVGPageView.swift`
- Create: `App/MusicXML/MusicXMLScoreViewer.swift`

**Interfaces:**
- Consumes: `VerovioEngine.shared` (Task 1), `ScoreViewerShell` (Task 3)
- Produces: `SVGPageView(svg: String, highlightIDs: [String])`, `MusicXMLScoreViewer(score:library:)`,
  `enum MusicXMLPage { static let size = CGSize(width: 595, height: 842) }`

- [ ] **Step 1: SVGPageView 구현**

`App/MusicXML/SVGPageView.swift`:

```swift
import SwiftUI
import WebKit

/// Verovio가 만든 SVG 페이지 하나를 표시하는 가벼운 웹뷰. 상호작용은 받지 않는다(탭 영역·필기 캔버스가 위에서 처리).
struct SVGPageView: UIViewRepresentable {
    let svg: String
    /// 하이라이트할 SVG 요소 id 목록 (2B 따라가기에서 사용)
    var highlightIDs: [String] = []

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedSVG != svg {
            context.coordinator.loadedSVG = svg
            context.coordinator.pendingHighlight = highlightIDs
            webView.loadHTMLString(Self.html(for: svg), baseURL: nil)
        } else if context.coordinator.appliedHighlight != highlightIDs {
            context.coordinator.apply(highlightIDs, to: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedSVG: String?
        var appliedHighlight: [String] = []
        var pendingHighlight: [String] = []

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            apply(pendingHighlight, to: webView)
        }

        func apply(_ ids: [String], to webView: WKWebView) {
            appliedHighlight = ids
            let json = (try? JSONSerialization.data(withJSONObject: ids)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            webView.evaluateJavaScript("window.setHighlight(\(json))")
        }
    }

    static func html(for svg: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
          html, body { margin:0; padding:0; width:100%; height:100%; background:#fff; overflow:hidden; }
          svg { width:100%; height:100%; display:block; }
          .highlighted, .highlighted * { fill:#e0532f !important; color:#e0532f !important; stroke:#e0532f; }
        </style></head><body>\(svg)
        <script>
          window.setHighlight = function(ids) {
            document.querySelectorAll('.highlighted').forEach(e => e.classList.remove('highlighted'));
            ids.forEach(id => { const e = document.getElementById(id); if (e) e.classList.add('highlighted'); });
          };
        </script></body></html>
        """
    }
}
```

- [ ] **Step 2: MusicXMLScoreViewer 구현**

`App/MusicXML/MusicXMLScoreViewer.swift`:

```swift
import SwiftUI

enum MusicXMLPage {
    /// 가상 페이지(A4)의 정규화 좌표계 크기 — 필기 저장 기준
    static let size = CGSize(width: 595, height: 842)
}

/// Verovio 엔진으로 MusicXML을 조판해 ScoreViewerShell에 페이지 SVG를 공급한다.
struct MusicXMLScoreViewer: View {
    let score: Score
    @ObservedObject var library: ScoreLibraryStore
    @State private var pageCount: Int?
    @State private var errorMessage: String?
    @State private var svgs: [Int: String] = [:]

    var body: some View {
        Group {
            if let pageCount {
                ScoreViewerShell(score: score, library: library, pageCount: pageCount,
                                 pageSize: { _ in MusicXMLPage.size }) { index in
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
            if let svg = try? await VerovioEngine.shared.pageSVG(index) { svgs[index] = svg }
        }
    }
}
```

- [ ] **Step 3: 빌드 확인**

Run: `xcodegen generate -q && xcodebuild build ... | grep -E "BUILD |error:"`. Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add App/MusicXML
git commit -m "feat: MusicXML 뷰어 — SVG 페이지 표시 웹뷰와 Verovio 연동"
```

---

### Task 5: 탭 구조 + 보관함 종류별 연결 + 문서 타입

**Files:**
- Create: `App/Views/RootTabView.swift`
- Modify: `App/ScoreApp.swift`, `App/Views/LibraryView.swift`, `project.yml`

- [ ] **Step 1: RootTabView와 ScoreApp**

`App/Views/RootTabView.swift`:

```swift
import SwiftUI

struct RootTabView: View {
    @ObservedObject var pdfLibrary: ScoreLibraryStore
    @ObservedObject var xmlLibrary: ScoreLibraryStore

    var body: some View {
        TabView {
            Tab(ScoreKind.pdf.title, systemImage: ScoreKind.pdf.symbolName) {
                LibraryView(library: pdfLibrary)
            }
            Tab(ScoreKind.musicXML.title, systemImage: ScoreKind.musicXML.symbolName) {
                LibraryView(library: xmlLibrary)
            }
            Tab("설정", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
```

`App/ScoreApp.swift`:

```swift
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
                .onAppear {
                    pdfLibrary.installSamplesIfNeeded(BundledSample.bundled(for: .pdf))
                    xmlLibrary.installSamplesIfNeeded(BundledSample.bundled(for: .musicXML))
                    _ = VerovioEngine.shared   // WASM 초기화를 미리 시작
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
```

- [ ] **Step 2: LibraryView 수정**

- 툴바의 설정(톱니바퀴) `ToolbarItem` 제거, `.onOpenURL` 제거(루트로 이동)
- 제목: `.navigationTitle(library.kind.title)`
- 빈 상태 문구: `"악보가 없습니다"`, 설명 `"오른쪽 위 + 버튼으로 \(library.kind == .pdf ? "PDF" : "MusicXML(.musicxml/.mxl)") 악보를 가져오세요."`
- `fileImporter(allowedContentTypes: library.kind.contentTypes, ...)`, `try library.importFile(from: url)`
- 목적지:

```swift
            .navigationDestination(for: Score.self) { score in
                switch score.kind {
                case .pdf: PDFScoreViewer(score: score, library: library)
                case .musicXML: MusicXMLScoreViewer(score: score, library: library)
                }
            }
```

- `ScoreCell` 썸네일 없을 때 아이콘: `Image(systemName: score.kind.symbolName)`

- [ ] **Step 3: project.yml 문서 타입 선언**

`info.properties`에 추가:

```yaml
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: com.yru.musicxml
            UTTypeDescription: MusicXML Score
            UTTypeConformsTo: [public.xml]
            UTTypeTagSpecification:
              public.filename-extension: [musicxml]
              public.mime-type: [application/vnd.recordare.musicxml+xml]
          - UTTypeIdentifier: com.yru.mxl
            UTTypeDescription: Compressed MusicXML Score
            UTTypeConformsTo: [public.data]
            UTTypeTagSpecification:
              public.filename-extension: [mxl]
              public.mime-type: [application/vnd.recordare.musicxml]
```

`CFBundleDocumentTypes`에 항목 추가:

```yaml
          - CFBundleTypeName: MusicXML Score
            LSHandlerRank: Alternate
            LSItemContentTypes: [com.yru.musicxml, com.yru.mxl, public.xml]
```

- [ ] **Step 4: 빌드·테스트·시뮬레이터 확인**

Run: 테스트 명령 → `TEST SUCCEEDED`. 앱 삭제 후 재설치·실행:
1. 상단 탭 `PDF 악보 | 디지털 악보 | 설정` 표시, PDF 탭에 드뷔시(즐겨찾기·필기 유지), 디지털 탭에 바흐 샘플 자동 설치
2. 바흐 열기 → 조판된 악보 표시, 세로 1페이지/가로 펼침, 탭 넘김, 페이지 표시
3. 필기 모드 → 그리기 → 나갔다 다시 열어 복원, 가로/세로 전환에도 같은 자리
4. 디지털 탭 검색/즐겨찾기/제목 변경/삭제 동작, 설정 탭 진입

- [ ] **Step 5: Commit**

```bash
git add App project.yml
git commit -m "feat: PDF/디지털 악보 탭 구조, MusicXML 가져오기·문서 타입, 바흐 샘플 설치"
```

---

## 완료 기준 (스펙 대비)

- [ ] Verovio 번들·엔진: 로드/페이지 수/SVG/타임맵 (테스트)
- [ ] ScoreKind: 폴더·확장자·키 분리·검증·샘플 (테스트)
- [ ] Shell 리팩터 후 PDF 뷰어 회귀 없음 (기존 테스트 + 수동)
- [ ] 디지털 악보 뷰어: 펼침·넘김·필기·페이지 기억 동작
- [ ] 탭 3개, 설정 탭 이동, 문서 타입 등록, onOpenURL 라우팅
