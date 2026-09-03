# SoSo Score

<img src="App/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" align="right" alt="SoSo Score 앱 아이콘">

연주 중에 손을 쓰지 않고 악보를 넘길 수 있는 **iPad 악보 뷰어**입니다.
PDF와 MusicXML 악보를 보관함에 모아 두고, 고개 돌리기·윙크 같은 얼굴 제스처나 연주 소리로 페이지를 넘기며, 애플펜슬로 필기할 수 있습니다.

- 대상 기기: iPad, iPadOS 18.0 이상
- 언어: 한국어 / 영어 (설정에서 즉시 전환)

## 주요 기능

### 악보 보관함
- PDF · MusicXML(`.musicxml`, `.xml`, `.mxl`) 가져오기, 이름 변경, 삭제, 즐겨찾기, 제목 검색
- 파일 앱·다른 앱에서 "SoSo Score로 열기" 지원(문서 타입 등록)
- 마지막으로 본 페이지 기억
- 최초 실행 시 퍼블릭 도메인 샘플 악보 20곡 자동 설치 (PDF 10곡, MusicXML 10곡 — 출처는 [Samples/LICENSE.md](Samples/LICENSE.md))

### 악보 보기
- 탭으로 넘기기, 책처럼 두 쪽을 펼쳐 보는 펼침 모드
- MusicXML은 [Verovio](https://www.verovio.org) 엔진으로 기기에서 직접 조판해 SVG로 표시
- 애플펜슬 필기: 페이지별로 저장되며 도구 팔레트 제공

### 손대지 않고 넘기기
- **얼굴 제스처**: ARKit 전면 카메라 얼굴 추적으로 고개 돌리기·윙크를 인식해 앞/뒤 페이지 이동. 보정 화면, 방향 반전, 쿨다운 설정
- **오디오 악보 따라가기**(MusicXML): 마이크로 연주를 듣고 크로마 특징을 온라인 정렬해 현재 마디를 하이라이트하고 자동으로 페이지를 넘김. 위치가 어긋나면 탭으로 재지정

## 저장소 구성

```
App/                 iPad 앱 (SwiftUI)
  Models/            보관함·설정·필기 저장소·페이지 내비게이터
  Views/             보관함, PDF 뷰어, 펼침 레이아웃, 필기 캔버스, 설정
  MusicXML/          Verovio 엔진 브리지, SVG 페이지 뷰, MusicXML 뷰어
  Tracking/          ARKit 얼굴 추적 세션
  Following/         마이크 입력, 악보 따라가기, 툴바 컨트롤
  Localizable.xcstrings  한국어/영어 String Catalog
AppTests/            앱 단위 테스트
Packages/
  GestureCore/       얼굴 제스처 판정 (HeadTurnDetector, WinkDetector, GestureEngine) — 순수 Swift 패키지
  ScoreFollowCore/   크로마 추출(vDSP), 온라인 DTW, 악보 템플릿 — 순수 Swift 패키지
Vendor/verovio/      Verovio 6.3.0 WASM 툴킷 (LGPL-3.0, 무수정 번들 — Vendor/LICENSE.md)
Samples/             기본 샘플 악보와 출처·라이선스
Design/              앱 아이콘 렌더링 스크립트 (CoreGraphics)
docs/superpowers/    설계 문서(specs)와 구현 계획(plans)
dist/                서명 없는 Release .ipa와 설치 안내
project.yml          XcodeGen 프로젝트 정의
```

`SoSoScore.xcodeproj`와 `App/Info.plist`는 XcodeGen이 생성하는 파일이라 커밋하지 않습니다.

## 빌드

요구 사항: macOS, Xcode 26 이상, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
xcodegen generate
open SoSoScore.xcodeproj
```

Xcode에서 `SoSoScore` 스킴을 선택해 iPad 시뮬레이터 또는 실기기에서 실행합니다.
실기기에 설치하려면 `project.yml`의 `DEVELOPMENT_TEAM` 주석을 해제해 팀 ID를 넣거나, Xcode의 Signing & Capabilities에서 팀을 지정합니다.
얼굴 제스처와 오디오 따라가기는 카메라·마이크가 필요해 실기기에서만 동작합니다.

### 테스트

```bash
xcodebuild -project SoSoScore.xcodeproj -scheme SoSoScore -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' test
```

패키지 단위 테스트는 각 패키지 폴더에서 `swift test`로 실행할 수 있습니다.

```bash
cd Packages/GestureCore && swift test
```

### 설치 파일

서명 없는 Release `.ipa`가 [dist/](dist/)에 있습니다. 재서명 도구(Sideloadly, AltStore 등)로 설치하는 방법과 다시 만드는 명령은 [dist/README.md](dist/README.md)를 참고하세요.

## 앱 아이콘

아이콘은 코드로 그립니다. 색상·좌표를 바꾼 뒤 아래 명령으로 다시 렌더링합니다.

```bash
swiftc -O -o /tmp/drawicon Design/DrawAppIcon.swift && /tmp/drawicon App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## 개발 이력

기능별 변경 내역과 커밋 링크는 [docs/CHANGELOG.md](docs/CHANGELOG.md)에 있습니다.

## 라이선스 고지

- Verovio 6.3.0 — LGPL-3.0-or-later, 무수정 번들 ([Vendor/LICENSE.md](Vendor/LICENSE.md))
- 샘플 악보 — Mutopia Project(Public Domain / CC BY / CC BY-SA), music21 corpus ([Samples/LICENSE.md](Samples/LICENSE.md))
