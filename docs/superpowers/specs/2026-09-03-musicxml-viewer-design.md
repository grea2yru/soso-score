# 2A. 디지털 악보(MusicXML) 뷰어 + 탭 구조 — 설계

- 날짜: 2026-09-03
- 상태: 승인됨
- 선행: `2026-09-02-ipad-score-viewer-design.md` (1단계 PDF 뷰어)
- 후속: `2026-09-03-score-following-design.md` (2B 오디오 따라가기)

## 목표

MusicXML(.musicxml / .mxl) 악보를 가져와 PDF 악보와 **같은 사용 경험**(보관함·검색·즐겨찾기·펼침·
탭/얼굴 제스처 넘김·애플펜슬 필기)으로 보게 한다. PDF 악보와는 **상단 탭**으로 메뉴를 구분한다.
2B의 오디오 따라가기가 필요로 하는 음표 타이밍 정보를 얻을 수 있는 렌더링 엔진을 채택한다.

## 핵심 결정

### 렌더링 엔진: Verovio (WASM, WKWebView 내장)

- `verovio-toolkit-wasm.js`(v6.3.0, 7.3MB, LGPL-3.0, WASM 내장 단일 파일)를 앱에 번들해
  오프라인으로 동작. 라이선스 고지는 `Samples/LICENSE.md`와 같은 방식으로 `Vendor/LICENSE.md`에 기록.
- 선택 이유: 조판 품질, 그리고 `renderToTimemap`/`getElementsAtTime`/`getMIDIValuesForElement`
  등 **음표별 연주 시각과 SVG 요소 ID를 연결하는 API**가 있어 2B 하이라이트에 직접 쓰임.
- 대안 기각: OpenSheetMusicDisplay(타이밍 추출·페이지 조판 약함), 네이티브 직접 조판(규모 과대).

### 고정 가상 페이지 조판 (필기 호환의 핵심)

- 화면 크기에 맞춰 재조판하지 않고, **A4 비율 고정 가상 페이지**(Verovio 기본 pageWidth 2100 ×
  pageHeight 2970)에 한 번 조판한다. 화면에는 그 페이지를 PDF처럼 축소/확대해 표시한다.
- 따라서 가로/세로 전환·펼침 여부와 무관하게 페이지 나눔과 줄바꿈이 항상 같고, 필기 좌표를
  가상 페이지 기준으로 저장하면 PDF와 동일하게 어느 방향에서도 같은 자리에 표시된다.
- 필기 정규화 좌표계: 가상 페이지를 **595 × 842 포인트**(A4 pt)로 본다. 표시 배율 = 표시 폭 ÷ 595.
- "악보 크기" 조절 옵션은 두지 않는다(재조판 시 필기와 어긋남). 필요 시 크기별 필기 세트로 확장.

## 화면 구조

- `TabView` 3탭: **PDF 악보** | **디지털 악보** | **설정**. iPadOS 18 상단 탭 바(`.tabViewStyle(.sidebarAdaptable)`).
  기존 보관함의 톱니바퀴 버튼은 제거하고 설정 탭으로 이동.
- 두 보관함은 같은 `LibraryView`를 쓰되 저장소(`ScoreLibraryStore`)와 뷰어 목적지만 다르다.
  검색·즐겨찾기·⋯ 메뉴(제목 변경/즐겨찾기/삭제)·가져오기 UI가 동일.
- 디지털 악보 카드: 썸네일 대신 악보 아이콘(`music.note.list`) + 제목(파일명). (2A에서는 조판 썸네일 생략)

## 구성 요소

### ScoreKind와 저장소 일반화

- `enum ScoreKind { case pdf, musicXML }` — 종류별 설정:
  - 폴더: pdf = `Documents/`(기존 유지), musicXML = `Documents/MusicXML/`
  - 확장자: pdf = `pdf`; musicXML = `musicxml`, `mxl`, `xml`
  - 즐겨찾기 UserDefaults 키: pdf = `favoriteScoreIDs`(기존), musicXML = `favoriteScoreIDs.musicxml`
  - 샘플 설치 플래그 키: pdf = `didInstallSamples`(기존), musicXML = `didInstallSamples.musicxml`
  - 필기 폴더: 각 폴더 아래 `Annotations/`
  - 가져오기 검증: pdf = `PDFDocument` 열기; musicXML = `.mxl`이면 ZIP 매직(`PK`) 확인,
    그 외는 파일 내용에 `<score-partwise` 또는 `<score-timewise` 포함 확인
- `Score`에 `kind` 추가. `ScoreLibraryStore(kind:directory:defaults:)`. 기존 PDF 동작·테스트 유지.
- 기본 샘플(디지털): 바흐 「평균율 클라비어곡집 1권 전주곡 C장조」 BWV 846 — music21 corpus의
  MusicXML(퍼블릭 도메인). 제목 "바흐 - 평균율 1권 전주곡 C장조 (BWV 846)".
- 마지막 페이지 기억 키는 `lastPage.<파일명>`으로 종류 간 충돌이 없다(폴더가 달라도 파일명이 같을 수
  있으므로 musicXML은 `lastPage.musicxml.<파일명>` 접두를 쓴다).

### VerovioEngine (숨김 WKWebView 1개)

- 번들 HTML(`Vendor/verovio.html`)이 toolkit을 로드하고 `window.vrv` API를 노출:
  - `load(base64, isZip)` → `{ pageCount }` — 옵션: `breaks: "auto"`, `adjustPageHeight: false`,
    `footer: "none"`, `svgViewBox: true`, `scale: 40`(가상 페이지에 적절한 악보 크기)
  - `pageSVG(n)` → SVG 문자열 (1-based)
  - `timemap()` → `renderToTimemap({includeMeasures: true})` JSON (2B에서 사용)
  - `midi(id)` → `getMIDIValuesForElement(id)` (2B에서 사용)
- Swift: `@MainActor final class VerovioEngine` — `func load(fileURL) async throws -> Int`,
  `func pageSVG(_ index: Int) async throws -> String`(0-based), `func timemap() async throws -> Data`.
  결과는 악보가 열려 있는 동안 메모리에 캐시. 로딩 실패는 `VerovioError` 로 전달.
- 엔진 초기화(toolkit 로드)는 앱 시작 시 1회, 이후 악보마다 `load`만 호출.

### 뷰어 공통화: ScoreViewerShell

- 기존 `ScoreViewerView`에서 **페이지 소스와 무관한 부분**을 `ScoreViewerShell`로 분리:
  펼침 배치(`PageNavigator`), 탭 영역, 플래시, 페이지 표시, 얼굴 추적·인디케이터·권한 배너,
  필기 모드 토글·PencilKit 캔버스·`AnnotationStore` 저장, 마지막 페이지 기억.
- Shell 입력: `pageCount`, `pageSize(index) -> CGSize`(정규화 좌표계 크기), `content(index) -> View`,
  저장 키(`score`, `library`).
- `SpreadView`는 콘텐츠 빌더를 받도록 일반화. PDF는 `PDFPageImage`, 디지털은 `SVGPageView`.
- `PDFScoreViewer`(기존 동작 그대로)와 `MusicXMLScoreViewer`(엔진에서 페이지 수·SVG를 받아 Shell에 공급,
  로딩 중 진행 표시, 실패 시 오류 안내)가 Shell을 감싼다.

### SVGPageView

- 페이지 1장을 표시하는 가벼운 `WKWebView`(Verovio 없이 SVG만). HTML: 여백 0, `svg { width:100%; height:100% }`,
  스크롤·확대 비활성, 사용자 인터랙션 비활성(탭 영역·필기 캔버스가 위에서 처리).
- `highlight(ids: [String], color)` JS 호출 지원(2B용): 지정 ID에 `highlighted` 클래스 부여, CSS
  `.highlighted { fill: <color>; color: <color>; }`.

### 가져오기·문서 타입

- `fileImporter` 허용 타입: `.pdf`(PDF 탭), MusicXML 탭은 `com.yru.musicxml`(확장자 musicxml, public.xml 준수),
  `com.yru.mxl`(확장자 mxl, public.data 준수), `.xml`. `UTImportedTypeDeclarations`와
  `CFBundleDocumentTypes`에 등록해 Files/AirDrop "다음으로 열기"도 지원. `onOpenURL`에서 확장자로 종류를 판별해
  해당 저장소에 넣는다.

## 오류 처리

- 조판 실패(손상 XML): 뷰어에 "악보를 열 수 없습니다" 안내, 보관함으로 돌아갈 수 있음.
- 엔진 초기화 실패(WASM 로드 실패): 디지털 악보 탭 상단에 안내 배너, PDF 탭은 영향 없음.
- 큰 악보 로딩 지연: 로딩 인디케이터 표시, 페이지 SVG는 필요할 때 요청하고 캐시.

## 테스트

- `ScoreLibraryStore` 종류별 동작(폴더·확장자·검증·즐겨찾기 키 분리·샘플 설치) 유닛 테스트
- `VerovioEngine` 통합 테스트(시뮬레이터): 샘플 로드 → 페이지 수 ≥ 1, 첫 페이지 SVG에 `<svg` 포함,
  타임맵에 `on` 항목 존재
- `PageNavigator`·`AnnotationStore` 기존 테스트 유지, Shell 리팩터 후 PDF 뷰어 회귀 확인(시뮬레이터)
- 시뮬레이터 수동: 탭 전환, 디지털 악보 가져오기·열기·펼침·탭 넘김·필기·재진입 복원
