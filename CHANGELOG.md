# 개발 이력

SoSo Score(iPad 악보 뷰어)의 기능별 개발 이력입니다. 각 항목의 커밋 번호를 누르면 GitHub에서 해당 변경을 볼 수 있습니다.

## 배포·브랜딩 (2026-09-03)

- 서명 없는 Release `.ipa`와 설치 안내를 `dist/`에 추가 — [6673ec0](https://github.com/grea2yru/soso-score/commit/6673ec0)
- 앱 아이콘을 애플 스타일로 단순화: 단발 여자아이 얼굴 + 한 옥타브 건반 — [fe4759c](https://github.com/grea2yru/soso-score/commit/fe4759c)
- 프로젝트명 ScoreForYou → SoSoScore, 표시 이름 SoSo Score — [6b29bac](https://github.com/grea2yru/soso-score/commit/6b29bac)
- 이전 아이콘 시안: 미니멀 얼굴·건반 — [a627eb2](https://github.com/grea2yru/soso-score/commit/a627eb2), 피아노 치는 아이 클로즈업 — [05ed1ca](https://github.com/grea2yru/soso-score/commit/05ed1ca)

## 다국어 (2026-09-03)

- 한국어/영어 앱 언어 설정 — String Catalog 기반, 설정에서 즉시 전환 — [386df8f](https://github.com/grea2yru/soso-score/commit/386df8f)

## 2B. 오디오 악보 따라가기 (2026-09-03)

- 하이라이트, 자동 넘김, 탭 재지정, 툴바 컨트롤 — [a3f63e4](https://github.com/grea2yru/soso-score/commit/a3f63e4)
- 엔진 피치/시스템 맵 API, MicrophoneSource, ScoreFollower — [bd40c22](https://github.com/grea2yru/soso-score/commit/bd40c22)
- PageCursor 외부화, Shell accessory·탭 넘김 비활성 옵션 — [e75c4fc](https://github.com/grea2yru/soso-score/commit/e75c4fc)
- ScoreFollowCore 패키지: Chroma/ChromaExtractor(vDSP), 온라인 정렬 — [8faa1b1](https://github.com/grea2yru/soso-score/commit/8faa1b1)
- 설계·구현 계획 — [24e0b29](https://github.com/grea2yru/soso-score/commit/24e0b29), [d6bcc6f](https://github.com/grea2yru/soso-score/commit/d6bcc6f)

## 2A. MusicXML 뷰어·탭 구조 (2026-09-03)

- PDF/디지털 악보 탭 구조, 전체 화면 뷰어, MusicXML 가져오기·문서 타입 — [7c2a29e](https://github.com/grea2yru/soso-score/commit/7c2a29e)
- MusicXML 뷰어: SVG 페이지 표시 웹뷰와 Verovio 연동 — [9885ce8](https://github.com/grea2yru/soso-score/commit/9885ce8)
- 뷰어 공통부를 ScoreViewerShell로 분리 — [eeeb017](https://github.com/grea2yru/soso-score/commit/eeeb017)
- ScoreKind 도입: 저장소를 PDF/MusicXML 종류별로 일반화 — [67d1790](https://github.com/grea2yru/soso-score/commit/67d1790)
- Verovio 엔진 번들 및 VerovioEngine(MusicXML 조판·타임맵) — [685e66d](https://github.com/grea2yru/soso-score/commit/685e66d)
- 구현 계획·구조 변경 반영 — [b9c78d8](https://github.com/grea2yru/soso-score/commit/b9c78d8), [0aa7722](https://github.com/grea2yru/soso-score/commit/0aa7722)

## 샘플 악보

- PDF 10곡(Mutopia), MusicXML 10곡(music21 corpus), 샘플별 설치 기록 — [994f710](https://github.com/grea2yru/soso-score/commit/994f710)
- 최초 실행 시 기본 샘플(드뷔시 달빛) 설치 — [408052a](https://github.com/grea2yru/soso-score/commit/408052a)

## 1단계. PDF 악보 뷰어·얼굴 제스처 (2026-09-02)

- 애플펜슬 필기: PencilKit 필기 모드, 페이지별 저장, 도구 팔레트 — [f140e57](https://github.com/grea2yru/soso-score/commit/f140e57), 설계 반영 — [a45dc67](https://github.com/grea2yru/soso-score/commit/a45dc67)
- 보관함 즐겨찾기·제목 검색·카드 메뉴 — [d027919](https://github.com/grea2yru/soso-score/commit/d027919)
- 책 펼침 레이아웃(짝수 정렬, 홀수 마지막 페이지 왼쪽) — [22f8833](https://github.com/grea2yru/soso-score/commit/22f8833)
- ARKit 얼굴 추적: 고개/윙크 페이지 넘김, 상태 인디케이터, 보정 화면 — [3442a5d](https://github.com/grea2yru/soso-score/commit/3442a5d)
- 제스처 설정 화면 — [0ae2338](https://github.com/grea2yru/soso-score/commit/0ae2338)
- PDF 뷰어: 탭 넘김, 펼침 모드, 플래시 피드백, 페이지 기억 — [5e40259](https://github.com/grea2yru/soso-score/commit/5e40259)
- 악보 보관함 화면과 AppSettings — [5f83337](https://github.com/grea2yru/soso-score/commit/5f83337)
- ScoreLibraryStore: PDF 가져오기/삭제/이름변경/마지막 페이지 기억 — [5c1d813](https://github.com/grea2yru/soso-score/commit/5c1d813)
- XcodeGen 기반 앱 프로젝트 스캐폴딩 — [13070cb](https://github.com/grea2yru/soso-score/commit/13070cb)
- GestureCore 패키지: 기본 타입 — [76faf4f](https://github.com/grea2yru/soso-score/commit/76faf4f), HeadTurnDetector — [956e87e](https://github.com/grea2yru/soso-score/commit/956e87e), WinkDetector — [9e051bf](https://github.com/grea2yru/soso-score/commit/9e051bf), GestureEngine — [883f0df](https://github.com/grea2yru/soso-score/commit/883f0df)
- 1단계 설계 문서·구현 계획 — [b0eb87c](https://github.com/grea2yru/soso-score/commit/b0eb87c), [e0321e6](https://github.com/grea2yru/soso-score/commit/e0321e6)
