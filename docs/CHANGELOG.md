# 개발 이력

SoSo Score(iPad 악보 뷰어)의 기능별 개발 이력입니다. 각 항목의 커밋 번호를 누르면 GitHub에서 해당 변경을 볼 수 있습니다.

## 조판 속도 (2026-09-03)

- 음표 피치 조회를 MEI 한 번 파싱으로 교체 — 음표마다 `getMIDIValuesForElement`를 부르던 제곱 시간 병목 제거(4중주 36~60초 → 수십 ms). `Vendor/verovio/pitch-index.js`, Node 검증 `Vendor/tests/pitch-index.test.js` — [ddb3592](https://github.com/grea2yru/soso-score/commit/ddb3592)
- 페이지 SVG는 문서당 한 번만 렌더 — 시스템 맵이 표시용과 같은 문자열을 재사용 — [ddb3592](https://github.com/grea2yru/soso-score/commit/ddb3592)
- 보이는 펼침부터 조판하고 페이지 사이에 표시 요청이 끼어들 수 있게 양보 (`TypesetDocument.buildFollowIndex`) — [ddb3592](https://github.com/grea2yru/soso-score/commit/ddb3592)
- 조판 결과 디스크 캐시(`TypesetCache`, 파일 해시 + 조판 버전 키) — 두 번째부터는 엔진 없이 즉시 열림, 이름 바꿔도 유지, 삭제된 악보의 캐시는 자동 정리 — [ddb3592](https://github.com/grea2yru/soso-score/commit/ddb3592)
- 백그라운드 미리 조판(`ScoreTypesetter`) — 가져오기·샘플 설치 직후 캐시 없는 악보를 차례로 조판, 뷰어가 열면 엔진을 양보 — [ddb3592](https://github.com/grea2yru/soso-score/commit/ddb3592)

## 배포·브랜딩 (2026-09-03)

- README 추가: 기능 소개, 저장소 구성, 빌드·테스트·설치 방법, 라이선스 고지 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 서명 없는 Release `.ipa`와 설치 안내를 `dist/`에 추가 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 앱 아이콘을 애플 스타일로 단순화: 단발 여자아이 얼굴 + 한 옥타브 건반 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 프로젝트명 ScoreForYou → SoSoScore, 표시 이름 SoSo Score — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 이전 아이콘 시안: 미니멀 얼굴·건반 — [a627eb2](https://github.com/grea2yru/soso-score/commit/a627eb2), 피아노 치는 아이 클로즈업 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)

## 다국어 (2026-09-03)

- 한국어/영어 앱 언어 설정 — String Catalog 기반, 설정에서 즉시 전환 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- String Catalog 추출을 컴파일러 방식(`SWIFT_EMIT_LOC_STRINGS`)으로 전환 — `Text` 외 `Button`/`Section`/`Label`/`L10n` 문구가 "참조 없음"으로 표시되던 경고 45건 해소, `L10n.string`은 `String.LocalizationValue`를 받음 — [259bc64](https://github.com/grea2yru/soso-score/commit/259bc64)

## 2B. 오디오 악보 따라가기 (2026-09-03)

- 하이라이트, 자동 넘김, 탭 재지정, 툴바 컨트롤 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 엔진 피치/시스템 맵 API, MicrophoneSource, ScoreFollower — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- PageCursor 외부화, Shell accessory·탭 넘김 비활성 옵션 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- ScoreFollowCore 패키지: Chroma/ChromaExtractor(vDSP), 온라인 정렬 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 설계·구현 계획 — [24e0b29](https://github.com/grea2yru/soso-score/commit/24e0b29), [d6bcc6f](https://github.com/grea2yru/soso-score/commit/d6bcc6f)

## 2A. MusicXML 뷰어·탭 구조 (2026-09-03)

- PDF/디지털 악보 탭 구조, 전체 화면 뷰어, MusicXML 가져오기·문서 타입 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- MusicXML 뷰어: SVG 페이지 표시 웹뷰와 Verovio 연동 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 뷰어 공통부를 ScoreViewerShell로 분리 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- ScoreKind 도입: 저장소를 PDF/MusicXML 종류별로 일반화 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- Verovio 엔진 번들 및 VerovioEngine(MusicXML 조판·타임맵) — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 구현 계획·구조 변경 반영 — [b9c78d8](https://github.com/grea2yru/soso-score/commit/b9c78d8), [0aa7722](https://github.com/grea2yru/soso-score/commit/0aa7722)

## 샘플 악보

- 번들에서 빠진 옛 샘플(1~2장짜리 등)은 앱이 설치했던 것만 필기·즐겨찾기와 함께 자동 정리 — 사용자가 직접 가져온 같은 이름의 파일은 유지 — [8dfae6c](https://github.com/grea2yru/soso-score/commit/8dfae6c)
- 샘플 전면 교체: 4페이지 이상의 대중적인 곡으로 PDF 10곡(Mutopia)·MusicXML 10곡(OpenScore CC0, music21 corpus) 재구성. 드뷔시 「달빛」은 PDF와 MusicXML 모두 수록 — MusicXML은 Mutopia LilyPond 소스를 `Samples/tools/`로 직접 변환 — [fdb986f](https://github.com/grea2yru/soso-score/commit/fdb986f)
- PDF 10곡(Mutopia), MusicXML 10곡(music21 corpus), 샘플별 설치 기록 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 최초 실행 시 기본 샘플(드뷔시 달빛) 설치 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)

## 1단계. PDF 악보 뷰어·얼굴 제스처 (2026-09-02)

- 애플펜슬 필기: PencilKit 필기 모드, 페이지별 저장, 도구 팔레트 — [f140e57](https://github.com/grea2yru/soso-score/commit/f140e57), 설계 반영 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 보관함 즐겨찾기·제목 검색·카드 메뉴 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 책 펼침 레이아웃(짝수 정렬, 홀수 마지막 페이지 왼쪽) — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- ARKit 얼굴 추적: 고개/윙크 페이지 넘김, 상태 인디케이터, 보정 화면 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 제스처 설정 화면 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- PDF 뷰어: 탭 넘김, 펼침 모드, 플래시 피드백, 페이지 기억 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 악보 보관함 화면과 AppSettings — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- ScoreLibraryStore: PDF 가져오기/삭제/이름변경/마지막 페이지 기억 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- XcodeGen 기반 앱 프로젝트 스캐폴딩 — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- GestureCore 패키지: 기본 타입 — [76faf4f](https://github.com/grea2yru/soso-score/commit/76faf4f), HeadTurnDetector — [956e87e](https://github.com/grea2yru/soso-score/commit/956e87e), WinkDetector — [9e051bf](https://github.com/grea2yru/soso-score/commit/9e051bf), GestureEngine — [1dfb194](https://github.com/grea2yru/soso-score/commit/1dfb194)
- 1단계 설계 문서·구현 계획 — [b0eb87c](https://github.com/grea2yru/soso-score/commit/b0eb87c), [e0321e6](https://github.com/grea2yru/soso-score/commit/e0321e6)
