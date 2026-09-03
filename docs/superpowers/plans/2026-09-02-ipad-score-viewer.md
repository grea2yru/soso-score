# 아이패드 악보 뷰어 (1단계) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PDF 악보를 가져와 보고, 전면 카메라 얼굴 제스처(고개 돌리기/윙크)로 페이지를 넘기는 개인용 iPad 앱.

**Architecture:** 제스처 판정 로직은 ARKit에 의존하지 않는 순수 Swift 패키지(`GestureCore`)로 격리해 macOS에서 `swift test`로 TDD한다. 앱 타깃은 SwiftUI + PDFKit(뷰어/보관함) + ARKit(얼굴 데이터 공급)로 구성하고, XcodeGen으로 프로젝트를 생성한다.

**Tech Stack:** Swift 5.9+, SwiftUI, PDFKit, ARKit(ARFaceTrackingConfiguration), XCTest, XcodeGen

**Spec:** `docs/superpowers/specs/2026-09-02-ipad-score-viewer-design.md`

## Global Constraints

- 대상: iPadOS 17.0+, iPad 전용 (`TARGETED_DEVICE_FAMILY = "2"`), 실사용 기기는 iPad Pro 13" M5
- 외부 라이브러리 의존성 없음 — Apple 프레임워크만 사용 (빌드 도구로 XcodeGen만 사용)
- 사용자에게 보이는 모든 문구는 한국어
- 제스처 판정 로직은 `Packages/GestureCore`에 두고 ARKit/UIKit 타입 의존 금지
- 제스처 기본값(스펙 수치): 고개 임계값 20°, 유지 0.3초, 재무장 5°; 윙크 감김 >0.8, 열림 <0.3, 유지 0.2초; 쿨다운 1.5초; 방향은 오른쪽/오른눈 = 다음
- ARKit blendShape의 left/right는 **사용자 기준**임 (거울 반전 아님)
- `SoSoScore.xcodeproj`와 `App/Info.plist`는 XcodeGen 생성물이므로 커밋하지 않음
- 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` 추가

## 파일 구조

```
score-for-yru/
├── project.yml                          # XcodeGen 프로젝트 정의
├── .gitignore
├── Packages/GestureCore/                # 순수 로직 SPM 패키지 (macOS에서 swift test 가능)
│   ├── Package.swift
│   ├── Sources/GestureCore/
│   │   ├── FaceFrame.swift              # 프레임당 입력 데이터
│   │   ├── PageTurnEvent.swift          # next/previous 이벤트
│   │   ├── GestureSettings.swift        # 임계값·모드 설정 (Codable)
│   │   ├── HeadTurnDetector.swift       # 고개 돌리기 상태 기계 (internal)
│   │   ├── WinkDetector.swift           # 윙크 상태 기계 (internal)
│   │   └── GestureEngine.swift          # 모드 필터·공유 쿨다운·방향 반전 (public)
│   └── Tests/GestureCoreTests/
│       ├── TestHelpers.swift
│       ├── GestureSettingsTests.swift
│       ├── HeadTurnDetectorTests.swift
│       ├── WinkDetectorTests.swift
│       └── GestureEngineTests.swift
├── App/
│   ├── ScoreApp.swift                   # 앱 진입점
│   ├── Models/
│   │   ├── ScoreLibraryStore.swift      # PDF 파일 관리 + 마지막 페이지 기억
│   │   └── AppSettings.swift            # GestureSettings의 UserDefaults 영속화
│   ├── Views/
│   │   ├── LibraryView.swift            # 악보 보관함 격자
│   │   ├── ScoreViewerView.swift        # 뷰어 화면 (탭/제스처 넘김, 피드백)
│   │   ├── PDFKitView.swift             # PDFView SwiftUI 래퍼
│   │   └── SettingsView.swift           # 설정 + 실시간 보정값
│   └── Tracking/
│       └── FaceTrackingSession.swift    # ARKit → FaceFrame 변환·이벤트 발행
└── AppTests/
    └── ScoreLibraryStoreTests.swift
```

---

### Task 1: GestureCore 패키지와 기본 타입

**Files:**
- Create: `Packages/GestureCore/Package.swift`
- Create: `Packages/GestureCore/Sources/GestureCore/FaceFrame.swift`
- Create: `Packages/GestureCore/Sources/GestureCore/PageTurnEvent.swift`
- Create: `Packages/GestureCore/Sources/GestureCore/GestureSettings.swift`
- Test: `Packages/GestureCore/Tests/GestureCoreTests/GestureSettingsTests.swift`

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces:
  - `FaceFrame(yawDegrees: Double, leftEyeBlink: Double, rightEyeBlink: Double, timestamp: TimeInterval)` — 이후 모든 판정 로직의 입력
  - `PageTurnEvent` enum: `.next`, `.previous`
  - `GestureMode` enum: `.head`, `.wink`, `.both`, `.off`
  - `GestureSettings` struct (Codable, Equatable) + `GestureSettings.default`

- [ ] **Step 1: 패키지 스캐폴딩과 타입 작성**

`Packages/GestureCore/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "GestureCore", targets: ["GestureCore"])
    ],
    targets: [
        .target(name: "GestureCore"),
        .testTarget(name: "GestureCoreTests", dependencies: ["GestureCore"]),
    ]
)
```

`Packages/GestureCore/Sources/GestureCore/FaceFrame.swift`:

```swift
import Foundation

/// 얼굴 추적 한 프레임의 입력값. ARKit 등 공급자에 의존하지 않는다.
public struct FaceFrame: Equatable, Sendable {
    /// 고개 좌우 회전각(도). 사용자 기준 오른쪽으로 돌리면 양수.
    public var yawDegrees: Double
    /// 사용자 기준 왼눈 감김 정도 (0 = 완전히 뜸, 1 = 완전히 감음)
    public var leftEyeBlink: Double
    /// 사용자 기준 오른눈 감김 정도 (0 = 완전히 뜸, 1 = 완전히 감음)
    public var rightEyeBlink: Double
    /// 단조 증가 타임스탬프(초)
    public var timestamp: TimeInterval

    public init(yawDegrees: Double, leftEyeBlink: Double, rightEyeBlink: Double, timestamp: TimeInterval) {
        self.yawDegrees = yawDegrees
        self.leftEyeBlink = leftEyeBlink
        self.rightEyeBlink = rightEyeBlink
        self.timestamp = timestamp
    }
}
```

`Packages/GestureCore/Sources/GestureCore/PageTurnEvent.swift`:

```swift
public enum PageTurnEvent: Equatable, Sendable {
    case next
    case previous
}
```

`Packages/GestureCore/Sources/GestureCore/GestureSettings.swift`:

```swift
import Foundation

public enum GestureMode: String, CaseIterable, Codable, Equatable, Sendable {
    case head, wink, both, off
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var mode: GestureMode
    /// 고개 돌리기 발동 각도(도)
    public var headYawThresholdDegrees: Double
    /// 고개 돌리기 최소 유지 시간(초)
    public var headHoldDuration: TimeInterval
    /// 발동 후 정면 복귀로 재무장되는 각도(도)
    public var headRearmThresholdDegrees: Double
    /// 윙크로 인정하는 감김 값 (이 값 초과 = 감김)
    public var winkClosedThreshold: Double
    /// 반대쪽 눈이 떠 있다고 보는 값 (이 값 미만 = 뜸)
    public var winkOpenThreshold: Double
    /// 윙크 최소 유지 시간(초)
    public var winkHoldDuration: TimeInterval
    /// 발동 후 다음 발동까지 최소 간격(초)
    public var cooldown: TimeInterval
    /// true면 왼쪽/왼눈 = 다음 페이지
    public var invertDirection: Bool

    public static let `default` = GestureSettings(
        mode: .both,
        headYawThresholdDegrees: 20,
        headHoldDuration: 0.3,
        headRearmThresholdDegrees: 5,
        winkClosedThreshold: 0.8,
        winkOpenThreshold: 0.3,
        winkHoldDuration: 0.2,
        cooldown: 1.5,
        invertDirection: false
    )

    public init(mode: GestureMode, headYawThresholdDegrees: Double, headHoldDuration: TimeInterval,
                headRearmThresholdDegrees: Double, winkClosedThreshold: Double, winkOpenThreshold: Double,
                winkHoldDuration: TimeInterval, cooldown: TimeInterval, invertDirection: Bool) {
        self.mode = mode
        self.headYawThresholdDegrees = headYawThresholdDegrees
        self.headHoldDuration = headHoldDuration
        self.headRearmThresholdDegrees = headRearmThresholdDegrees
        self.winkClosedThreshold = winkClosedThreshold
        self.winkOpenThreshold = winkOpenThreshold
        self.winkHoldDuration = winkHoldDuration
        self.cooldown = cooldown
        self.invertDirection = invertDirection
    }
}
```

- [ ] **Step 2: 스모크 테스트 작성**

`Packages/GestureCore/Tests/GestureCoreTests/GestureSettingsTests.swift`:

```swift
import XCTest
@testable import GestureCore

final class GestureSettingsTests: XCTestCase {
    func testDefaultValuesMatchSpec() {
        let s = GestureSettings.default
        XCTAssertEqual(s.mode, .both)
        XCTAssertEqual(s.headYawThresholdDegrees, 20)
        XCTAssertEqual(s.headHoldDuration, 0.3)
        XCTAssertEqual(s.headRearmThresholdDegrees, 5)
        XCTAssertEqual(s.winkClosedThreshold, 0.8)
        XCTAssertEqual(s.winkOpenThreshold, 0.3)
        XCTAssertEqual(s.winkHoldDuration, 0.2)
        XCTAssertEqual(s.cooldown, 1.5)
        XCTAssertFalse(s.invertDirection)
    }

    func testCodableRoundTrip() throws {
        var s = GestureSettings.default
        s.mode = .wink
        s.invertDirection = true
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(GestureSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }
}
```

- [ ] **Step 3: 테스트 실행 — 통과 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: `Test Suite 'All tests' passed`, 2 tests

- [ ] **Step 4: Commit**

```bash
git add Packages/GestureCore
git commit -m "feat: GestureCore 패키지와 기본 타입(FaceFrame, PageTurnEvent, GestureSettings)"
```

---

### Task 2: HeadTurnDetector (고개 돌리기 판정)

**Files:**
- Create: `Packages/GestureCore/Sources/GestureCore/HeadTurnDetector.swift`
- Test: `Packages/GestureCore/Tests/GestureCoreTests/TestHelpers.swift`
- Test: `Packages/GestureCore/Tests/GestureCoreTests/HeadTurnDetectorTests.swift`

**Interfaces:**
- Consumes: `FaceFrame`, `GestureSettings`, `PageTurnEvent` (Task 1)
- Produces: `struct HeadTurnDetector` (internal) — `mutating func process(_ frame: FaceFrame, settings: GestureSettings) -> PageTurnEvent?`. 쿨다운은 여기서 처리하지 않는다(엔진 책임). 발동 후 |yaw| < 재무장 각도로 복귀해야 다시 발동 가능.

- [ ] **Step 1: 테스트 헬퍼와 실패하는 테스트 작성**

`Packages/GestureCore/Tests/GestureCoreTests/TestHelpers.swift`:

```swift
import Foundation
@testable import GestureCore

extension FaceFrame {
    static func head(yaw: Double, at t: TimeInterval) -> FaceFrame {
        FaceFrame(yawDegrees: yaw, leftEyeBlink: 0, rightEyeBlink: 0, timestamp: t)
    }
    static func eyes(left: Double, right: Double, at t: TimeInterval) -> FaceFrame {
        FaceFrame(yawDegrees: 0, leftEyeBlink: left, rightEyeBlink: right, timestamp: t)
    }
}

/// 60fps로 from...to 구간의 프레임 시퀀스 생성
func headFrames(yaw: Double, from: TimeInterval, to: TimeInterval) -> [FaceFrame] {
    stride(from: from, through: to, by: 1.0 / 60).map { .head(yaw: yaw, at: $0) }
}

func eyeFrames(left: Double, right: Double, from: TimeInterval, to: TimeInterval) -> [FaceFrame] {
    stride(from: from, through: to, by: 1.0 / 60).map { .eyes(left: left, right: right, at: $0) }
}
```

`Packages/GestureCore/Tests/GestureCoreTests/HeadTurnDetectorTests.swift`:

```swift
import XCTest
@testable import GestureCore

final class HeadTurnDetectorTests: XCTestCase {
    let settings = GestureSettings.default // 임계값 20°, 유지 0.3초, 재무장 5°

    func feed(_ detector: inout HeadTurnDetector, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { detector.process($0, settings: settings) }
    }

    func testTurnRightHeldFiresNextOnce() {
        var d = HeadTurnDetector()
        // 0.5초간 오른쪽 25° 유지 → 0.3초 시점에 next 1회만
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 0.5)), [.next])
    }

    func testTurnLeftHeldFiresPrevious() {
        var d = HeadTurnDetector()
        XCTAssertEqual(feed(&d, headFrames(yaw: -25, from: 0, to: 0.5)), [.previous])
    }

    func testShortGlanceDoesNotFire() {
        var d = HeadTurnDetector()
        // 0.2초만 돌림 (유지 시간 0.3초 미달) — 연주 중 건반 흘끗 보기
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 0.2)), [])
    }

    func testBelowThresholdDoesNotFire() {
        var d = HeadTurnDetector()
        // 임계값 20° 미만의 작은 움직임은 아무리 오래 유지해도 무시
        XCTAssertEqual(feed(&d, headFrames(yaw: 15, from: 0, to: 1.0)), [])
    }

    func testNoRefireWhileHeldTurned() {
        var d = HeadTurnDetector()
        // 2초간 계속 돌린 채 유지 → 정면 복귀 전에는 딱 1회만
        XCTAssertEqual(feed(&d, headFrames(yaw: 25, from: 0, to: 2.0)), [.next])
    }

    func testRefiresAfterRecentering() {
        var d = HeadTurnDetector()
        var frames = headFrames(yaw: 25, from: 0, to: 0.5)     // 발동
        frames += headFrames(yaw: 0, from: 0.52, to: 1.0)      // 정면 복귀(재무장)
        frames += headFrames(yaw: 25, from: 1.02, to: 1.5)     // 다시 발동
        XCTAssertEqual(feed(&d, frames), [.next, .next])
    }

    func testDirectionChangeMidHoldResetsTimer() {
        var d = HeadTurnDetector()
        // 오른쪽 0.2초 → 곧바로 왼쪽 0.2초: 어느 쪽도 유지 시간을 못 채움
        var frames = headFrames(yaw: 25, from: 0, to: 0.2)
        frames += headFrames(yaw: -25, from: 0.22, to: 0.42)
        XCTAssertEqual(feed(&d, frames), [])
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 컴파일 오류 `cannot find 'HeadTurnDetector' in scope`

- [ ] **Step 3: 구현**

`Packages/GestureCore/Sources/GestureCore/HeadTurnDetector.swift`:

```swift
import Foundation

/// 고개 돌리기 상태 기계.
/// 발동 조건: |yaw| ≥ 임계값이 유지 시간 이상 지속.
/// 발동 후에는 |yaw| < 재무장 각도로 정면 복귀해야 다시 발동할 수 있다.
/// 쿨다운은 GestureEngine이 담당한다.
struct HeadTurnDetector {
    private var holdStart: TimeInterval?
    private var holdDirection: PageTurnEvent?
    private var isArmed = true

    mutating func process(_ frame: FaceFrame, settings: GestureSettings) -> PageTurnEvent? {
        let yaw = frame.yawDegrees

        guard isArmed else {
            if abs(yaw) < settings.headRearmThresholdDegrees { isArmed = true }
            return nil
        }

        guard abs(yaw) >= settings.headYawThresholdDegrees else {
            holdStart = nil
            holdDirection = nil
            return nil
        }

        let direction: PageTurnEvent = yaw > 0 ? .next : .previous
        if holdDirection != direction {
            holdDirection = direction
            holdStart = frame.timestamp
            return nil
        }

        guard let start = holdStart, frame.timestamp - start >= settings.headHoldDuration else {
            return nil
        }

        isArmed = false
        holdStart = nil
        holdDirection = nil
        return direction
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 전체 통과 (GestureSettingsTests 2 + HeadTurnDetectorTests 7)

- [ ] **Step 5: Commit**

```bash
git add Packages/GestureCore
git commit -m "feat: 고개 돌리기 판정 상태 기계(HeadTurnDetector)"
```

---

### Task 3: WinkDetector (윙크 판정)

**Files:**
- Create: `Packages/GestureCore/Sources/GestureCore/WinkDetector.swift`
- Test: `Packages/GestureCore/Tests/GestureCoreTests/WinkDetectorTests.swift`

**Interfaces:**
- Consumes: `FaceFrame`, `GestureSettings`, `PageTurnEvent` (Task 1)
- Produces: `struct WinkDetector` (internal) — `mutating func process(_ frame: FaceFrame, settings: GestureSettings) -> PageTurnEvent?`. 오른눈 윙크 = `.next`, 왼눈 윙크 = `.previous`. 발동 후 양눈이 모두 열려야(둘 다 < winkOpenThreshold) 재무장.

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/GestureCore/Tests/GestureCoreTests/WinkDetectorTests.swift`:

```swift
import XCTest
@testable import GestureCore

final class WinkDetectorTests: XCTestCase {
    let settings = GestureSettings.default // 감김 >0.8, 뜸 <0.3, 유지 0.2초

    func feed(_ detector: inout WinkDetector, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { detector.process($0, settings: settings) }
    }

    func testRightWinkFiresNextOnce() {
        var d = WinkDetector()
        // 오른눈만 0.3초 감음 → next 1회
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)), [.next])
    }

    func testLeftWinkFiresPrevious() {
        var d = WinkDetector()
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.95, right: 0.05, from: 0, to: 0.3)), [.previous])
    }

    func testBothEyesBlinkIgnored() {
        var d = WinkDetector()
        // 자연스러운 양눈 깜빡임 (비대칭 조건 불충족)
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.9, right: 0.9, from: 0, to: 0.3)), [])
    }

    func testShortWinkIgnored() {
        var d = WinkDetector()
        // 0.1초 (유지 시간 0.2초 미달)
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.1)), [])
    }

    func testNaturalBlinkTransientAsymmetryIgnored() {
        var d = WinkDetector()
        // 자연 깜빡임에서 왼눈이 살짝 먼저 감기는 과도 상태(0.05초) → 발동 금지
        var frames = eyeFrames(left: 0.85, right: 0.25, from: 0, to: 0.05)
        frames += eyeFrames(left: 0.95, right: 0.95, from: 0.06, to: 0.3)
        XCTAssertEqual(feed(&d, frames), [])
    }

    func testNoRefireWhileEyeStaysClosed() {
        var d = WinkDetector()
        // 1초 내내 감고 있어도 1회만
        XCTAssertEqual(feed(&d, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 1.0)), [.next])
    }

    func testRefiresAfterBothEyesOpen() {
        var d = WinkDetector()
        var frames = eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)   // 발동
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.32, to: 0.6)   // 양눈 열림(재무장)
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.62, to: 0.9)   // 다시 발동
        XCTAssertEqual(feed(&d, frames), [.next, .next])
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 컴파일 오류 `cannot find 'WinkDetector' in scope`

- [ ] **Step 3: 구현**

`Packages/GestureCore/Sources/GestureCore/WinkDetector.swift`:

```swift
import Foundation

/// 윙크 상태 기계.
/// 발동 조건: 한쪽 눈 감김 > winkClosedThreshold 이고 반대쪽 < winkOpenThreshold 인
/// 비대칭 상태가 유지 시간 이상 지속. 양눈이 함께 감기는 자연 깜빡임은 걸리지 않는다.
/// 발동 후 양눈이 모두 열려야 재무장. 쿨다운은 GestureEngine이 담당한다.
struct WinkDetector {
    private var holdStart: TimeInterval?
    private var holdDirection: PageTurnEvent?
    private var isArmed = true

    mutating func process(_ frame: FaceFrame, settings: GestureSettings) -> PageTurnEvent? {
        let leftWink = frame.leftEyeBlink > settings.winkClosedThreshold
            && frame.rightEyeBlink < settings.winkOpenThreshold
        let rightWink = frame.rightEyeBlink > settings.winkClosedThreshold
            && frame.leftEyeBlink < settings.winkOpenThreshold

        guard isArmed else {
            if frame.leftEyeBlink < settings.winkOpenThreshold
                && frame.rightEyeBlink < settings.winkOpenThreshold {
                isArmed = true
            }
            return nil
        }

        guard leftWink || rightWink else {
            holdStart = nil
            holdDirection = nil
            return nil
        }

        let direction: PageTurnEvent = rightWink ? .next : .previous
        if holdDirection != direction {
            holdDirection = direction
            holdStart = frame.timestamp
            return nil
        }

        guard let start = holdStart, frame.timestamp - start >= settings.winkHoldDuration else {
            return nil
        }

        isArmed = false
        holdStart = nil
        holdDirection = nil
        return direction
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 전체 통과 (누적 16 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/GestureCore
git commit -m "feat: 윙크 판정 상태 기계(WinkDetector)"
```

---

### Task 4: GestureEngine (모드 필터 + 공유 쿨다운 + 방향 반전)

**Files:**
- Create: `Packages/GestureCore/Sources/GestureCore/GestureEngine.swift`
- Test: `Packages/GestureCore/Tests/GestureCoreTests/GestureEngineTests.swift`

**Interfaces:**
- Consumes: `HeadTurnDetector`, `WinkDetector` (Task 2, 3)
- Produces (앱이 사용하는 유일한 공개 진입점):
  - `public struct GestureEngine`
  - `public init(settings: GestureSettings = .default)`
  - `public var settings: GestureSettings` (실행 중 변경 가능)
  - `public mutating func process(_ frame: FaceFrame) -> PageTurnEvent?`

- [ ] **Step 1: 실패하는 테스트 작성**

`Packages/GestureCore/Tests/GestureCoreTests/GestureEngineTests.swift`:

```swift
import XCTest
@testable import GestureCore

final class GestureEngineTests: XCTestCase {
    func feed(_ engine: inout GestureEngine, _ frames: [FaceFrame]) -> [PageTurnEvent] {
        frames.compactMap { engine.process($0) }
    }

    func testCooldownSuppressesSecondFire() {
        var e = GestureEngine() // 쿨다운 1.5초
        var frames = eyeFrames(left: 0.05, right: 0.95, from: 0, to: 0.3)     // ~0.2초에 발동
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.32, to: 0.48)    // 재무장
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.5, to: 0.8)      // 쿨다운 내 → 무시
        frames += eyeFrames(left: 0.05, right: 0.05, from: 0.82, to: 1.0)     // 재무장
        frames += eyeFrames(left: 0.05, right: 0.95, from: 2.5, to: 2.8)      // 쿨다운 지남 → 발동
        XCTAssertEqual(feed(&e, frames), [.next, .next])
    }

    func testModeOffIgnoresEverything() {
        var s = GestureSettings.default
        s.mode = .off
        var e = GestureEngine(settings: s)
        var frames = headFrames(yaw: 30, from: 0, to: 0.5)
        frames += eyeFrames(left: 0.05, right: 0.95, from: 0.52, to: 0.9)
        XCTAssertEqual(feed(&e, frames), [])
    }

    func testWinkModeIgnoresHeadTurn() {
        var s = GestureSettings.default
        s.mode = .wink
        var e = GestureEngine(settings: s)
        XCTAssertEqual(feed(&e, headFrames(yaw: 30, from: 0, to: 1.0)), [])
    }

    func testHeadModeIgnoresWink() {
        var s = GestureSettings.default
        s.mode = .head
        var e = GestureEngine(settings: s)
        XCTAssertEqual(feed(&e, eyeFrames(left: 0.05, right: 0.95, from: 0, to: 1.0)), [])
    }

    func testBothModeFiresFromEitherDetector() {
        var e = GestureEngine()
        var frames = headFrames(yaw: 25, from: 0, to: 0.5)                    // 고개 → next
        frames += headFrames(yaw: 0, from: 0.52, to: 2.0)                     // 복귀 + 쿨다운 소진
        frames += eyeFrames(left: 0.95, right: 0.05, from: 2.1, to: 2.4)      // 왼눈 윙크 → previous
        XCTAssertEqual(feed(&e, frames), [.next, .previous])
    }

    func testInvertDirectionSwapsEvents() {
        var s = GestureSettings.default
        s.invertDirection = true
        var e = GestureEngine(settings: s)
        // 오른쪽으로 돌렸지만 반전 설정 → previous
        XCTAssertEqual(feed(&e, headFrames(yaw: 25, from: 0, to: 0.5)), [.previous])
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 컴파일 오류 `cannot find 'GestureEngine' in scope`

- [ ] **Step 3: 구현**

`Packages/GestureCore/Sources/GestureCore/GestureEngine.swift`:

```swift
import Foundation

/// 얼굴 프레임을 받아 페이지 넘김 이벤트를 내보내는 공개 진입점.
/// 모드 필터링, 감지기 간 공유 쿨다운, 방향 반전을 담당한다.
public struct GestureEngine {
    public var settings: GestureSettings

    private var head = HeadTurnDetector()
    private var wink = WinkDetector()
    private var lastFireTime: TimeInterval?

    public init(settings: GestureSettings = .default) {
        self.settings = settings
    }

    public mutating func process(_ frame: FaceFrame) -> PageTurnEvent? {
        guard settings.mode != .off else { return nil }

        var event: PageTurnEvent?
        if settings.mode == .head || settings.mode == .both {
            event = head.process(frame, settings: settings)
        }
        if event == nil, settings.mode == .wink || settings.mode == .both {
            event = wink.process(frame, settings: settings)
        }
        guard let fired = event else { return nil }

        // 쿨다운 내 발동은 버린다. (감지기는 이미 소모되어 재무장 필요 — 연쇄 발동 방지에 유리)
        if let last = lastFireTime, frame.timestamp - last < settings.cooldown {
            return nil
        }
        lastFireTime = frame.timestamp

        if settings.invertDirection {
            return fired == .next ? .previous : .next
        }
        return fired
    }
}
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run: `cd Packages/GestureCore && swift test`
Expected: 전체 통과 (누적 22 tests)

- [ ] **Step 5: Commit**

```bash
git add Packages/GestureCore
git commit -m "feat: GestureEngine — 모드 필터, 공유 쿨다운, 방향 반전"
```

---

### Task 5: Xcode 앱 프로젝트 스캐폴딩 (XcodeGen)

**Files:**
- Create: `project.yml`
- Create: `.gitignore`
- Create: `App/ScoreApp.swift`
- Create: `AppTests/ScoreLibraryStoreTests.swift` (빈 플레이스홀더 테스트 — Task 6에서 대체)

**Interfaces:**
- Consumes: `GestureCore` 패키지 (Task 1–4)
- Produces: `xcodegen generate`로 생성되는 `SoSoScore.xcodeproj`, 스킴 `SoSoScore` (앱 + 단위 테스트), 카메라 권한 문구와 PDF 문서 타입이 선언된 Info.plist

- [ ] **Step 1: XcodeGen 설치 확인**

Run: `which xcodegen || brew install xcodegen`
Expected: xcodegen 경로 출력 (설치 시 brew 로그 후 성공)

- [ ] **Step 2: 프로젝트 정의 작성**

`.gitignore`:

```
.DS_Store
xcuserdata/
DerivedData/
.build/
build/
SoSoScore.xcodeproj/
App/Info.plist
```

`project.yml`:

```yaml
name: SoSoScore
options:
  bundleIdPrefix: com.yru
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
packages:
  GestureCore:
    path: Packages/GestureCore
targets:
  SoSoScore:
    type: application
    platform: iOS
    sources: [App]
    dependencies:
      - package: GestureCore
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: 악보뷰어
        NSCameraUsageDescription: 얼굴 제스처(고개 돌리기·윙크)로 악보 페이지를 넘기기 위해 전면 카메라를 사용합니다.
        UILaunchScreen: {}
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        CFBundleDocumentTypes:
          - CFBundleTypeName: PDF Document
            LSHandlerRank: Alternate
            LSItemContentTypes: [com.adobe.pdf]
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "2"
        SWIFT_VERSION: "5.9"
        # 실기기 배포 시 Xcode에서 팀을 지정하거나 아래 주석을 해제해 팀 ID를 기입
        # DEVELOPMENT_TEAM: XXXXXXXXXX
  SoSoScoreTests:
    type: bundle.unit-test
    platform: iOS
    sources: [AppTests]
    dependencies:
      - target: SoSoScore
schemes:
  SoSoScore:
    build:
      targets:
        SoSoScore: all
        SoSoScoreTests: [test]
    test:
      targets: [SoSoScoreTests]
```

`App/ScoreApp.swift` (이 시점에는 최소 화면 — Task 7에서 LibraryView로 교체):

```swift
import SwiftUI

@main
struct ScoreApp: App {
    var body: some Scene {
        WindowGroup {
            Text("악보뷰어")
        }
    }
}
```

`AppTests/ScoreLibraryStoreTests.swift` (플레이스홀더 — 테스트 타깃이 비면 xcodegen이 실패하므로):

```swift
import XCTest

final class ScoreLibraryStoreTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: 프로젝트 생성과 빌드 확인**

Run:

```bash
xcodegen generate
xcodebuild -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: 테스트 실행 확인 (시뮬레이터)**

사용 가능한 iPad 시뮬레이터 이름 확인 후 실행 (이후 Task에서도 같은 이름 사용):

```bash
xcrun simctl list devices available | grep iPad
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<위에서 확인한 iPad 이름>'
```

Expected: `TEST SUCCEEDED` (플레이스홀더 1 test)

- [ ] **Step 5: Commit**

```bash
git add project.yml .gitignore App AppTests
git commit -m "feat: XcodeGen 기반 앱 프로젝트 스캐폴딩"
```

---

### Task 6: ScoreLibraryStore (PDF 파일 관리)

**Files:**
- Create: `App/Models/ScoreLibraryStore.swift`
- Modify: `AppTests/ScoreLibraryStoreTests.swift` (플레이스홀더 전체 교체)

**Interfaces:**
- Consumes: 없음 (Foundation/PDFKit만)
- Produces (Task 7·8이 사용):
  - `struct Score: Identifiable, Hashable` — `id: String`(파일명), `url: URL`, `title: String`(확장자 뺀 이름)
  - `@MainActor final class ScoreLibraryStore: ObservableObject`
    - `init(directory: URL? = nil, defaults: UserDefaults = .standard)` — nil이면 앱 Documents
    - `@Published private(set) var scores: [Score]`
    - `func importPDF(from source: URL) throws` — 열기 검증, 중복 이름 시 ` 2`, ` 3`… 접미사
    - `func delete(_ score: Score)` / `func rename(_ score: Score, to newTitle: String)`
    - `func lastPage(of score: Score) -> Int` / `func setLastPage(_ page: Int, of score: Score)`
    - `func thumbnail(for score: Score, size: CGSize) -> UIImage?`

- [ ] **Step 1: 실패하는 테스트 작성**

`AppTests/ScoreLibraryStoreTests.swift` 전체 교체:

```swift
import XCTest
import UIKit
@testable import SoSoScore

@MainActor
final class ScoreLibraryStoreTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!
    var defaults: UserDefaults!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "ScoreLibraryStoreTests")!
        defaults.removePersistentDomain(forName: "ScoreLibraryStoreTests")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: sourceDir)
    }

    /// 테스트용 PDF 파일 생성
    func makePDF(named name: String, pages: Int = 3) throws -> URL {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 300))
        let data = renderer.pdfData { ctx in
            for i in 0..<pages {
                ctx.beginPage()
                "\(i)".draw(at: .zero, withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
            }
        }
        let url = sourceDir.appendingPathComponent("\(name).pdf")
        try data.write(to: url)
        return url
    }

    func makeStore() -> ScoreLibraryStore {
        ScoreLibraryStore(directory: tempDir, defaults: defaults)
    }

    func testImportAddsScore() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "쇼팽 녹턴"))
        XCTAssertEqual(store.scores.map(\.title), ["쇼팽 녹턴"])
    }

    func testImportInvalidFileThrows() throws {
        let bad = sourceDir.appendingPathComponent("broken.pdf")
        try Data("not a pdf".utf8).write(to: bad)
        let store = makeStore()
        XCTAssertThrowsError(try store.importPDF(from: bad))
        XCTAssertTrue(store.scores.isEmpty)
    }

    func testImportDuplicateNameGetsSuffix() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "연습곡"))
        try store.importPDF(from: try makePDF(named: "연습곡"))
        XCTAssertEqual(store.scores.map(\.title).sorted(), ["연습곡", "연습곡 2"])
    }

    func testDeleteRemovesScoreAndLastPage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "소나타"))
        let score = store.scores[0]
        store.setLastPage(5, of: score)
        store.delete(score)
        XCTAssertTrue(store.scores.isEmpty)
        XCTAssertEqual(defaults.integer(forKey: "lastPage.소나타.pdf"), 0)
    }

    func testRenamePreservesLastPage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "옛이름"))
        store.setLastPage(7, of: store.scores[0])
        store.rename(store.scores[0], to: "새이름")
        XCTAssertEqual(store.scores.map(\.title), ["새이름"])
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 7)
    }

    func testLastPageDefaultsToZero() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "새 악보"))
        XCTAssertEqual(store.lastPage(of: store.scores[0]), 0)
    }

    func testThumbnailReturnsImage() throws {
        let store = makeStore()
        try store.importPDF(from: try makePDF(named: "썸네일"))
        XCTAssertNotNil(store.thumbnail(for: store.scores[0], size: CGSize(width: 160, height: 220)))
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run:

```bash
xcodegen generate
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<Task 5에서 확인한 iPad 이름>'
```

Expected: 컴파일 오류 `cannot find 'ScoreLibraryStore' in scope`

- [ ] **Step 3: 구현**

`App/Models/ScoreLibraryStore.swift`:

```swift
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
```

- [ ] **Step 4: 테스트 실행 — 통과 확인**

Run:

```bash
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>'
```

Expected: `TEST SUCCEEDED` (8 tests)

- [ ] **Step 5: Commit**

```bash
git add App/Models/ScoreLibraryStore.swift AppTests/ScoreLibraryStoreTests.swift
git commit -m "feat: ScoreLibraryStore — PDF 가져오기/삭제/이름변경/마지막 페이지 기억"
```

---

### Task 7: LibraryView (악보 보관함 화면)

**Files:**
- Create: `App/Views/LibraryView.swift`
- Create: `App/Models/AppSettings.swift`
- Modify: `App/ScoreApp.swift` (LibraryView 연결)

**Interfaces:**
- Consumes: `ScoreLibraryStore`, `Score` (Task 6), `GestureSettings` (Task 1)
- Produces:
  - `final class AppSettings: ObservableObject` — `@Published var gesture: GestureSettings` (UserDefaults `"gestureSettings"` 키에 JSON 저장, didSet 자동 저장)
  - `LibraryView` — `NavigationStack` + `navigationDestination(for: Score.self)`. Task 8의 `ScoreViewerView(score:)`, Task 9의 `SettingsView()`가 여기 연결됨. 이 Task 시점에는 임시 플레이스홀더 뷰(`Text`)로 연결해 두고 Task 8·9에서 실제 뷰로 교체.

- [ ] **Step 1: AppSettings 구현**

`App/Models/AppSettings.swift`:

```swift
import Foundation
import GestureCore

/// GestureSettings를 UserDefaults에 JSON으로 영속화
final class AppSettings: ObservableObject {
    private static let key = "gestureSettings"

    @Published var gesture: GestureSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(GestureSettings.self, from: data) {
            gesture = saved
        } else {
            gesture = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(gesture) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
```

- [ ] **Step 2: LibraryView 구현**

`App/Views/LibraryView.swift`:

```swift
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: ScoreLibraryStore
    @State private var showImporter = false
    @State private var importError: String?
    @State private var renamingScore: Score?
    @State private var newTitle = ""

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.scores.isEmpty {
                    ContentUnavailableView(
                        "악보가 없습니다",
                        systemImage: "music.note.list",
                        description: Text("오른쪽 위 + 버튼으로 PDF 악보를 가져오세요.")
                    )
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(library.scores) { score in
                            NavigationLink(value: score) {
                                ScoreCell(score: score)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("이름 변경") {
                                    newTitle = score.title
                                    renamingScore = score
                                }
                                Button("삭제", role: .destructive) {
                                    library.delete(score)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("악보 보관함")
            .navigationDestination(for: Score.self) { score in
                // Task 8에서 ScoreViewerView(score: score)로 교체
                Text(score.title)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        // Task 9에서 SettingsView()로 교체
                        Text("설정")
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    do { try library.importPDF(from: url) }
                    catch { importError = error.localizedDescription }
                }
            }
            .alert("가져오기 실패", isPresented: .constant(importError != nil)) {
                Button("확인") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .alert("이름 변경", isPresented: .constant(renamingScore != nil)) {
                TextField("새 이름", text: $newTitle)
                Button("확인") {
                    if let score = renamingScore { library.rename(score, to: newTitle) }
                    renamingScore = nil
                }
                Button("취소", role: .cancel) { renamingScore = nil }
            }
        }
        .onOpenURL { url in
            // Files/AirDrop의 "다음으로 열기"로 전달된 PDF
            try? library.importPDF(from: url)
        }
    }
}

struct ScoreCell: View {
    @EnvironmentObject var library: ScoreLibraryStore
    let score: Score

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = library.thumbnail(for: score, size: CGSize(width: 160, height: 220)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 220)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)

            Text(score.title)
                .font(.callout)
                .lineLimit(1)
        }
    }
}
```

`App/ScoreApp.swift` 전체 교체:

```swift
import SwiftUI

@main
struct ScoreApp: App {
    @StateObject private var library = ScoreLibraryStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(settings)
        }
    }
}
```

- [ ] **Step 3: 빌드 + 기존 테스트 통과 확인**

Run:

```bash
xcodegen generate
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>'
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 4: 시뮬레이터에서 수동 확인**

```bash
xcrun simctl boot "<iPad 이름>" 2>/dev/null || true
open -a Simulator
xcodebuild -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>' \
  -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/SoSoScore.app
xcrun simctl launch booted com.yru.SoSoScore
```

확인 항목:
1. 빈 보관함 안내 문구 표시
2. 임의 PDF를 시뮬레이터 창에 드래그하면 Files 앱에 저장됨 → 앱의 + 버튼 → 해당 PDF 선택 → 격자에 썸네일 표시
3. 길게 눌러 이름 변경·삭제 동작

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "feat: 악보 보관함 화면(LibraryView)과 AppSettings"
```

---

### Task 8: PDFKitView + ScoreViewerView (뷰어 — 수동 넘김)

**Files:**
- Create: `App/Views/PDFKitView.swift`
- Create: `App/Views/ScoreViewerView.swift`
- Modify: `App/Views/LibraryView.swift` (navigationDestination의 플레이스홀더 교체)

**Interfaces:**
- Consumes: `Score`, `ScoreLibraryStore` (Task 6), `PageTurnEvent` (Task 1)
- Produces:
  - `PDFKitView(document:currentPageIndex:twoUp:)` — PDFView 래퍼, 페이지 인덱스 양방향 바인딩
  - `ScoreViewerView(score:)` — Task 10이 여기에 얼굴 추적을 연결함. 내부에 `func turn(_ event: PageTurnEvent)` 페이지 이동 + 가장자리 플래시 피드백 포함

- [ ] **Step 1: PDFKitView 구현**

`App/Views/PDFKitView.swift`:

```swift
import SwiftUI
import PDFKit

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    let twoUp: Bool

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayDirection = .horizontal
        view.backgroundColor = .systemBackground
        context.coordinator.observePageChanges(of: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let mode: PDFDisplayMode = twoUp ? .twoUp : .singlePage
        if view.displayMode != mode {
            view.displayMode = mode
            view.autoScales = true
        }
        if let page = document.page(at: currentPageIndex), view.currentPage != page {
            view.go(to: page)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        init(_ parent: PDFKitView) { self.parent = parent }

        func observePageChanges(of view: PDFView) {
            NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                guard let self, let view,
                      let page = view.currentPage,
                      let doc = view.document else { return }
                let index = doc.index(for: page)
                if self.parent.currentPageIndex != index {
                    self.parent.currentPageIndex = index
                }
            }
        }
    }
}
```

- [ ] **Step 2: ScoreViewerView 구현**

`App/Views/ScoreViewerView.swift`:

```swift
import SwiftUI
import PDFKit
import GestureCore

struct ScoreViewerView: View {
    let score: Score
    @EnvironmentObject var library: ScoreLibraryStore
    @State private var document: PDFDocument?
    @State private var currentPageIndex = 0
    @State private var flashEdge: Edge?
    @State private var isTwoUp = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let document {
                    PDFKitView(document: document, currentPageIndex: $currentPageIndex, twoUp: isTwoUp)
                        .ignoresSafeArea(edges: .bottom)

                    // 좌/우 30% 탭 영역 (중앙 40%는 PDFView 제스처에 양보)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.previous) }
                        Color.clear
                            .frame(width: geo.size.width * 0.4)
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { turn(.next) }
                    }
                } else {
                    ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "exclamationmark.triangle")
                }

                if let edge = flashEdge {
                    FlashOverlay(edge: edge)
                }
            }
            .onAppear { isTwoUp = geo.size.width > geo.size.height }
            .onChange(of: geo.size) { _, size in
                isTwoUp = size.width > size.height
            }
        }
        .navigationTitle(score.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(pageLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let doc = PDFDocument(url: score.url)
            document = doc
            let pageCount = doc?.pageCount ?? 1
            currentPageIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
        }
        .onDisappear {
            library.setLastPage(currentPageIndex, of: score)
        }
    }

    private var pageLabel: String {
        let total = document?.pageCount ?? 0
        return "\(currentPageIndex + 1) / \(total)"
    }

    func turn(_ event: PageTurnEvent) {
        guard let document else { return }
        let step = isTwoUp ? 2 : 1
        let target: Int
        switch event {
        case .next: target = min(currentPageIndex + step, document.pageCount - 1)
        case .previous: target = max(currentPageIndex - step, 0)
        }
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

/// 페이지 넘김 시각 피드백: 넘긴 방향 가장자리에 짧은 색 플래시
struct FlashOverlay: View {
    let edge: Edge

    var body: some View {
        HStack {
            if edge == .trailing { Spacer() }
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 24)
            if edge == .leading { Spacer() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
```

`App/Views/LibraryView.swift`의 navigationDestination 교체:

```swift
            .navigationDestination(for: Score.self) { score in
                ScoreViewerView(score: score)
            }
```

- [ ] **Step 3: 빌드 + 테스트 통과 확인**

Run:

```bash
xcodegen generate
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>'
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 4: 시뮬레이터에서 수동 확인**

Task 7 Step 4와 같은 방법으로 설치·실행 후 확인:
1. 악보를 열면 마지막으로 본 페이지에서 시작
2. 화면 오른쪽 탭 → 다음 페이지 + 오른쪽 가장자리 플래시, 왼쪽 탭 → 이전 페이지
3. 가로 회전(⌘←) 시 두 페이지 펼침, 세로에서 한 페이지
4. 첫/마지막 페이지에서 더 넘겨도 오류 없음
5. 뒤로 갔다가 다시 열면 보던 페이지 복원

- [ ] **Step 5: Commit**

```bash
git add App/Views
git commit -m "feat: PDF 뷰어 화면 — 탭 넘김, 펼침 모드, 플래시 피드백, 페이지 기억"
```

---

### Task 9: SettingsView (제스처 설정 화면)

**Files:**
- Create: `App/Views/SettingsView.swift`
- Modify: `App/Views/LibraryView.swift` (설정 플레이스홀더 교체)

**Interfaces:**
- Consumes: `AppSettings` (Task 7), `GestureMode`, `GestureSettings` (Task 1)
- Produces: `SettingsView` — Task 10이 여기에 실시간 보정값 섹션을 추가함

- [ ] **Step 1: SettingsView 구현**

`App/Views/SettingsView.swift`:

```swift
import SwiftUI
import GestureCore

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("페이지 넘김 제스처") {
                Picker("방식", selection: $settings.gesture.mode) {
                    Text("고개 돌리기").tag(GestureMode.head)
                    Text("윙크").tag(GestureMode.wink)
                    Text("둘 다").tag(GestureMode.both)
                    Text("끄기").tag(GestureMode.off)
                }
                Toggle("방향 반전 (왼쪽/왼눈 = 다음)", isOn: $settings.gesture.invertDirection)
            }

            Section("고개 돌리기") {
                LabeledSlider(label: "감지 각도", value: $settings.gesture.headYawThresholdDegrees,
                              range: 10...35, format: "%.0f°")
                LabeledSlider(label: "유지 시간", value: $settings.gesture.headHoldDuration,
                              range: 0.1...1.0, format: "%.2f초")
            }

            Section("윙크") {
                LabeledSlider(label: "감김 민감도", value: $settings.gesture.winkClosedThreshold,
                              range: 0.5...0.95, format: "%.2f")
                LabeledSlider(label: "유지 시간", value: $settings.gesture.winkHoldDuration,
                              range: 0.1...0.5, format: "%.2f초")
            }

            Section("공통") {
                LabeledSlider(label: "쿨다운", value: $settings.gesture.cooldown,
                              range: 0.5...3.0, format: "%.1f초")
                Button("기본값으로 되돌리기") {
                    settings.gesture = .default
                }
            }
        }
        .navigationTitle("설정")
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
```

`App/Views/LibraryView.swift`의 설정 툴바 항목 교체:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
```

- [ ] **Step 2: 빌드 + 테스트 통과 확인**

Run:

```bash
xcodegen generate
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>'
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 3: 시뮬레이터에서 수동 확인**

1. 설정 화면 진입, 각 슬라이더·피커 조작
2. 앱 종료(`xcrun simctl terminate booted com.yru.SoSoScore`) 후 재실행 → 설정값 유지 확인
3. "기본값으로 되돌리기" 동작 확인

- [ ] **Step 4: Commit**

```bash
git add App/Views
git commit -m "feat: 제스처 설정 화면(SettingsView)"
```

---

### Task 10: FaceTrackingSession + 뷰어 연동 (얼굴 제스처 페이지 넘김)

**Files:**
- Create: `App/Tracking/FaceTrackingSession.swift`
- Modify: `App/Views/ScoreViewerView.swift` (추적 연결, 상태 인디케이터, 권한 안내)
- Modify: `App/Views/SettingsView.swift` (실시간 보정값 섹션 추가)

**Interfaces:**
- Consumes: `GestureEngine`, `GestureSettings`, `FaceFrame`, `PageTurnEvent` (Task 1–4), `ScoreViewerView.turn(_:)` (Task 8), `AppSettings` (Task 7)
- Produces:
  - `@MainActor final class FaceTrackingSession: NSObject, ObservableObject`
    - `static var isSupported: Bool`
    - `@Published private(set) var isTrackingFace: Bool` / `latestFrame: FaceFrame?` / `didFail: Bool`
    - `let events: PassthroughSubject<PageTurnEvent, Never>`
    - `func start()` / `func pause()` / `func updateSettings(_:)`

- [ ] **Step 1: FaceTrackingSession 구현**

`App/Tracking/FaceTrackingSession.swift`:

```swift
import ARKit
import Combine
import GestureCore
import QuartzCore

/// ARKit 얼굴 추적 세션을 감싸 GestureCore 입력(FaceFrame)으로 변환하고,
/// GestureEngine의 판정 결과를 이벤트로 발행한다.
@MainActor
final class FaceTrackingSession: NSObject, ObservableObject {
    @Published private(set) var isTrackingFace = false
    @Published private(set) var latestFrame: FaceFrame?
    /// 카메라 권한 거부 등으로 세션이 실패한 경우
    @Published private(set) var didFail = false

    let events = PassthroughSubject<PageTurnEvent, Never>()

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    /// 실기기 검증: 설정 화면의 실시간 값에서 고개를 "오른쪽"으로 돌렸을 때
    /// yaw가 음수로 나오면 이 값을 -1로 바꾼다.
    private static let yawSign: Double = 1

    private let session = ARSession()
    private var engine = GestureEngine()

    override init() {
        super.init()
        session.delegate = self
    }

    func updateSettings(_ settings: GestureSettings) {
        engine.settings = settings
    }

    func start() {
        guard Self.isSupported else { return }
        didFail = false
        let config = ARFaceTrackingConfiguration()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        session.pause()
        isTrackingFace = false
    }

    private func handle(_ frame: FaceFrame, tracked: Bool) {
        isTrackingFace = tracked
        latestFrame = frame
        guard tracked else { return }
        if let event = engine.process(frame) {
            events.send(event)
        }
    }
}

extension FaceTrackingSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let camera = session.currentFrame?.camera else { return }

        // 카메라 기준 얼굴 회전 행렬에서 yaw(좌우 회전각) 추출
        let rel = simd_mul(camera.transform.inverse, face.transform)
        let zAxis = rel.columns.2
        let yawRadians = atan2(Double(zAxis.x), Double(zAxis.z))
        let yawDegrees = Self.yawSign * yawRadians * 180 / .pi

        // ARKit blendShape의 left/right는 사용자 기준
        let left = face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0
        let right = face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0

        let frame = FaceFrame(
            yawDegrees: yawDegrees,
            leftEyeBlink: left,
            rightEyeBlink: right,
            timestamp: CACurrentMediaTime()
        )
        let tracked = face.isTracked
        Task { @MainActor in
            self.handle(frame, tracked: tracked)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.didFail = true
            self.isTrackingFace = false
        }
    }
}
```

- [ ] **Step 2: ScoreViewerView에 추적 연결**

`App/Views/ScoreViewerView.swift` 수정. 프로퍼티 추가:

```swift
    @EnvironmentObject var settings: AppSettings
    @StateObject private var tracker = FaceTrackingSession()
    @Environment(\.scenePhase) private var scenePhase
```

`ZStack` 안, `FlashOverlay` 분기 위에 권한 실패 배너 추가:

```swift
                if tracker.didFail {
                    VStack {
                        Text("카메라를 사용할 수 없어 손·탭으로만 넘길 수 있습니다. 설정 앱 > 개인정보 보호 > 카메라에서 권한을 확인하세요.")
                            .font(.footnote)
                            .padding(10)
                            .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
```

툴바를 다음으로 교체 (추적 상태 인디케이터 추가):

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // 얼굴 추적 상태: 초록 = 추적 중, 회색 = 미검출/꺼짐
                    Circle()
                        .fill(tracker.isTrackingFace ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(tracker.isTrackingFace ? "얼굴 추적 중" : "얼굴 미검출")
                    Text(pageLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
```

기존 `.onAppear`/`.onDisappear`를 다음으로 교체하고 수신 모디파이어 추가:

```swift
        .onAppear {
            let doc = PDFDocument(url: score.url)
            document = doc
            let pageCount = doc?.pageCount ?? 1
            currentPageIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))
            tracker.updateSettings(settings.gesture)
            tracker.start()
        }
        .onDisappear {
            tracker.pause()
            library.setLastPage(currentPageIndex, of: score)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tracker.start() } else { tracker.pause() }
        }
        .onChange(of: settings.gesture) { _, newValue in
            tracker.updateSettings(newValue)
        }
        .onReceive(tracker.events) { event in
            turn(event)
        }
```

- [ ] **Step 3: SettingsView에 실시간 보정값 섹션 추가**

`App/Views/SettingsView.swift`의 Form 마지막에 섹션 추가:

```swift
            Section("실시간 값 (보정용)") {
                if FaceTrackingSession.isSupported {
                    FaceDebugView()
                } else {
                    Text("이 기기에서는 얼굴 추적을 사용할 수 없습니다. (시뮬레이터 포함)")
                        .foregroundStyle(.secondary)
                }
            }
```

같은 파일에 뷰 추가:

```swift
/// 실기기에서 임계값을 보정할 수 있도록 현재 얼굴 값을 그대로 보여준다.
/// 설정 화면은 뷰어와 동시에 열리지 않으므로 자체 AR 세션을 사용해도 충돌하지 않는다.
struct FaceDebugView: View {
    @StateObject private var tracker = FaceTrackingSession()

    var body: some View {
        Group {
            if let frame = tracker.latestFrame, tracker.isTrackingFace {
                LabeledContent("고개 각도(yaw)", value: String(format: "%+.1f° (오른쪽이 +)", frame.yawDegrees))
                LabeledContent("왼눈 감김", value: String(format: "%.2f", frame.leftEyeBlink))
                LabeledContent("오른눈 감김", value: String(format: "%.2f", frame.rightEyeBlink))
            } else {
                Text("얼굴이 감지되지 않았습니다. 화면 앞에 얼굴을 비춰주세요.")
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .onAppear { tracker.start() }
        .onDisappear { tracker.pause() }
    }
}
```

- [ ] **Step 4: 빌드 + 전체 테스트 통과 확인**

Run:

```bash
xcodegen generate
cd Packages/GestureCore && swift test && cd ../..
xcodebuild test -project SoSoScore.xcodeproj -scheme SoSoScore \
  -destination 'platform=iOS Simulator,name=<iPad 이름>'
```

Expected: GestureCore 22 tests + 앱 8 tests 모두 통과, `TEST SUCCEEDED`

- [ ] **Step 5: 시뮬레이터 확인 (추적 미지원 경로)**

시뮬레이터 실행 후:
1. 뷰어에서 인디케이터가 회색이고 앱이 정상 동작 (탭 넘김 가능)
2. 설정 화면 실시간 값 섹션에 "사용할 수 없습니다" 문구

- [ ] **Step 6: 실기기 검증 (사용자 협조 필요)**

Xcode에서 `SoSoScore.xcodeproj`를 열어 Signing & Capabilities에서 팀 선택 후 iPad에 실행. (이후 `project.yml`의 `DEVELOPMENT_TEAM` 주석을 해제하고 팀 ID를 기입하면 재생성 후에도 유지됨)

검증 절차:
1. 최초 실행 시 카메라 권한 요청 → 허용
2. **설정 > 실시간 값**에서 고개를 오른쪽으로 돌려 yaw 부호 확인 — 음수로 나오면 `FaceTrackingSession.yawSign`을 `-1`로 수정 후 재배포
3. 윙크 시 감김 값이 왼/오 올바른 쪽에서 오르는지 확인 (잘못 나오면 blendShape 매핑을 좌우 교체)
4. 뷰어에서: 고개 오른쪽 0.3초 유지 → 다음 페이지 + 플래시, 왼쪽 → 이전 페이지
5. 오른눈 윙크 → 다음, 왼눈 윙크 → 이전, 자연스러운 양눈 깜빡임 → 무반응
6. 연속 제스처 시 쿨다운(1.5초) 내 추가 넘김 없음
7. 얼굴을 화면 밖으로 → 인디케이터 회색, 복귀 시 초록
8. 홈으로 나갔다 돌아와도 추적 재개
9. 카메라 권한을 거부한 상태(설정 앱에서 끄기)로 뷰어 진입 → 노란 안내 배너 + 탭 넘김 정상

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "feat: ARKit 얼굴 추적 연동 — 고개/윙크 페이지 넘김, 상태 인디케이터, 보정 화면"
```

---

## 완료 기준 (스펙 대비)

- [ ] PDF 가져오기(fileImporter, onOpenURL), 격자 보관함, 삭제/이름변경, 마지막 페이지 기억
- [ ] 뷰어: 가로 두 페이지/세로 한 페이지, 탭 수동 넘김, 플래시 피드백, 페이지 표시
- [ ] 고개 돌리기·윙크 페이지 넘김 (유지 시간·재무장·쿨다운·자연 깜빡임 무시)
- [ ] 설정: 방식·민감도·방향 반전·쿨다운, UserDefaults 영속화
- [ ] 오류 처리: 권한 거부 배너, 얼굴 미검출 인디케이터, 백그라운드 시 세션 일시정지, 손상 PDF 거부
- [ ] GestureCore 유닛 테스트 22개 + 앱 유닛 테스트 8개 통과
- [ ] 실기기(iPad Pro 13" M5) 검증 절차 통과
