# 2B. 오디오 악보 따라가기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 디지털 악보 뷰어에서 마이크로 피아노 연주를 듣고 현재 위치의 음표를 하이라이트하며, 보이는 마지막 줄에 도달하면 자동으로 페이지를 넘긴다.

**Architecture:** 순수 Swift 패키지 `ScoreFollowCore`가 크로마 추출(vDSP FFT), 악보 템플릿 생성(Verovio 타임맵), 온라인 DTW 정렬을 담당하고 macOS에서 테스트된다. 앱은 `MicrophoneSource`(AVAudioEngine)와 `ScoreFollower`(ObservableObject)로 이를 묶어 `MusicXMLScoreViewer`에서 하이라이트·자동 넘김·탭 재지정을 수행한다. `ScoreViewerShell`은 페이지 커서를 외부 객체(`PageCursor`)로 빼고, 툴바 부속 뷰·탭 넘김 비활성 옵션을 얻는다.

**Tech Stack:** Swift, Accelerate(vDSP), AVFoundation(AVAudioEngine), SwiftUI, WebKit(JS 히트테스트), XCTest

**Spec:** `docs/superpowers/specs/2026-09-03-score-following-design.md`

## Global Constraints

- 프레임 4096 샘플, 홉 2048, Hann 창, 크로마 대역 55Hz~2kHz, 무음 게이트 -50 dBFS
- 템플릿 배음 가중: 1배 1.0, 2배 0.5, 3배 0.33; L2 정규화
- 온라인 DTW: 비용 = 1 − 코사인 유사도, 탐색 창 200 이벤트, 단조 증가, 인덕스 변경은 연속 2프레임 일치 시 확정
- 자동 넘김: 현재 이벤트 페이지 == 보이는 마지막 페이지 && 그 페이지의 마지막 시스템(줄)에 속할 때 다음 펼침으로. 같은 페이지에서 두 번 넘기지 않음
- 따라가기 중 화면 탭 = 위치 재지정(탭한 마디), 넘김은 얼굴 제스처
- PDF 뷰어에는 적용하지 않음. 기존 테스트(GestureCore 22, 앱 41) 유지
- 빌드/테스트는 샌드박스 우회로 실행. 시뮬레이터 `iPad Pro 13-inch (M5)`. `Packages/*`는 `swift test`(macOS)

## 파일 구조

```
Packages/ScoreFollowCore/
├── Package.swift
├── Sources/ScoreFollowCore/
│   ├── Chroma.swift              # 12차원 벡터, 정규화, 코사인 유사도
│   ├── ChromaExtractor.swift     # PCM 프레임 → Chroma? (vDSP FFT)
│   ├── ScoreTemplate.swift       # TimemapEntry, ScoreEvent, ScoreTemplateBuilder
│   └── OnlineDTW.swift           # 정렬 상태 기계
└── Tests/ScoreFollowCoreTests/
    ├── ChromaExtractorTests.swift
    ├── ScoreTemplateBuilderTests.swift
    └── OnlineDTWTests.swift
App/
├── Following/
│   ├── MicrophoneSource.swift    # AVAudioEngine 입력 탭 → 프레임 콜백, 레벨
│   ├── ScoreFollower.swift       # 소스+추출기+DTW, @Published currentEvent
│   └── FollowControls.swift      # 툴바 토글 + 레벨 미터 뷰
├── MusicXML/
│   ├── VerovioEngine.swift       # pitches(ids), systemMap(page) 추가
│   ├── SVGPageView.swift         # SVGPageController(measureAt) 추가
│   └── MusicXMLScoreViewer.swift # 따라가기 연동
├── Views/
│   ├── PageCursor.swift          # 페이지 커서 ObservableObject
│   ├── ScoreViewerShell.swift    # cursor 외부화, accessory, disablesTapTurning
│   └── PDFScoreViewer.swift      # PageCursor 생성
└── project.yml                   # NSMicrophoneUsageDescription, ScoreFollowCore 패키지
```

---

### Task 1: ScoreFollowCore — Chroma와 ChromaExtractor

**Files:** `Packages/ScoreFollowCore/Package.swift`, `Sources/ScoreFollowCore/Chroma.swift`, `Sources/ScoreFollowCore/ChromaExtractor.swift`, `Tests/ScoreFollowCoreTests/ChromaExtractorTests.swift`

**Interfaces (Produces):**
- `public struct Chroma: Equatable, Sendable { public var values: [Float] /*12*/; init(values:); func normalized() -> Chroma; static func similarity(_:_:) -> Float; static func fromPitchClassEnergy(_:) }`
- `public final class ChromaExtractor { init(sampleRate: Double, frameSize: Int = 4096, silenceThresholdDB: Float = -50); var frameSize; func process(_ samples: [Float]) -> Chroma? }` — 무음이면 nil

- [ ] **Step 1: 패키지와 실패하는 테스트**

`Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ScoreFollowCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "ScoreFollowCore", targets: ["ScoreFollowCore"])],
    targets: [
        .target(name: "ScoreFollowCore", linkerSettings: [.linkedFramework("Accelerate")]),
        .testTarget(name: "ScoreFollowCoreTests", dependencies: ["ScoreFollowCore"]),
    ]
)
```

`ChromaExtractorTests.swift`:
```swift
import XCTest
@testable import ScoreFollowCore

final class ChromaExtractorTests: XCTestCase {
    let sampleRate = 44100.0

    func sine(_ freqs: [Double], count: Int, amplitude: Float = 0.3) -> [Float] {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            return freqs.reduce(Float(0)) { $0 + amplitude * Float(sin(2 * .pi * $1 * t)) }
        }
    }

    func testCMajorTriadPeaksOnCEG() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let frame = sine([261.63, 329.63, 392.00], count: ex.frameSize)   // C4 E4 G4
        let chroma = ex.process(frame)!
        let top3 = chroma.values.enumerated().sorted { $0.element > $1.element }.prefix(3).map(\.offset)
        XCTAssertEqual(Set(top3), [0, 4, 7])
    }

    func testSingleNoteAIsPitchClass9() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let chroma = ex.process(sine([440], count: ex.frameSize))!
        XCTAssertEqual(chroma.values.enumerated().max { $0.element < $1.element }!.offset, 9)
    }

    func testSilenceReturnsNil() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        XCTAssertNil(ex.process([Float](repeating: 0, count: ex.frameSize)))
        XCTAssertNil(ex.process(sine([440], count: ex.frameSize, amplitude: 0.0005)))  // -66 dBFS
    }

    func testOutputIsUnitLength() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let c = ex.process(sine([440, 554.37], count: ex.frameSize))!
        XCTAssertEqual(sqrt(c.values.map { $0 * $0 }.reduce(0, +)), 1, accuracy: 1e-3)
    }

    func testSimilarityOfIdenticalIsOne() {
        let a = Chroma(values: [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0]).normalized()
        XCTAssertEqual(Chroma.similarity(a, a), 1, accuracy: 1e-5)
        let b = Chroma(values: [0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0]).normalized()
        XCTAssertEqual(Chroma.similarity(a, b), 0, accuracy: 1e-5)
    }
}
```

Run: `cd Packages/ScoreFollowCore && swift test` → Expected: `cannot find 'ChromaExtractor'`

- [ ] **Step 2: 구현**

`Chroma.swift`:
```swift
import Foundation

/// 12 피치 클래스(C=0 … B=11) 에너지 벡터
public struct Chroma: Equatable, Sendable {
    public var values: [Float]

    public init(values: [Float]) {
        precondition(values.count == 12)
        self.values = values
    }

    public static let zero = Chroma(values: [Float](repeating: 0, count: 12))

    public func normalized() -> Chroma {
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return self }
        return Chroma(values: values.map { $0 / norm })
    }

    /// 코사인 유사도 (두 벡터가 정규화되어 있으면 내적)
    public static func similarity(_ a: Chroma, _ b: Chroma) -> Float {
        let dot = zip(a.values, b.values).reduce(0) { $0 + $1.0 * $1.1 }
        let na = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let nb = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }
}
```

`ChromaExtractor.swift`:
```swift
import Foundation
import Accelerate

/// PCM 프레임(모노 Float) → 12차원 크로마. 무음(RMS < 임계값)이면 nil.
public final class ChromaExtractor {
    public let sampleRate: Double
    public let frameSize: Int
    public let silenceThresholdDB: Float

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private let binToPitchClass: [Int]   // -1 = 대역 밖
    private let log2n: vDSP_Length

    public init(sampleRate: Double, frameSize: Int = 4096, silenceThresholdDB: Float = -50) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.silenceThresholdDB = silenceThresholdDB
        log2n = vDSP_Length(log2(Double(frameSize)))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        // 각 FFT 빈을 가장 가까운 MIDI 음의 피치 클래스로 매핑 (55Hz~2000Hz)
        let half = frameSize / 2
        binToPitchClass = (0..<half).map { bin in
            let freq = Double(bin) * sampleRate / Double(frameSize)
            guard freq >= 55, freq <= 2000 else { return -1 }
            let midi = 69 + 12 * log2(freq / 440)
            return ((Int(midi.rounded()) % 12) + 12) % 12
        }
    }

    public func process(_ samples: [Float]) -> Chroma? {
        guard samples.count == frameSize else { return nil }
        let rms = sqrt(vDSP.meanSquare(samples))
        let db = 20 * log10(max(rms, 1e-9))
        guard db > silenceThresholdDB else { return nil }

        let windowed = vDSP.multiply(samples, window)
        let half = frameSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(ptr.baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }

        var chroma = [Float](repeating: 0, count: 12)
        for (bin, pc) in binToPitchClass.enumerated() where pc >= 0 {
            chroma[pc] += magnitudes[bin]
        }
        // 진폭 스케일로 압축해 강한 배음의 지배를 줄임
        chroma = chroma.map { sqrt($0) }
        return Chroma(values: chroma).normalized()
    }
}
```

Run: `swift test` → 5 tests PASS. Commit: `feat: ScoreFollowCore — Chroma, ChromaExtractor(vDSP)`

---

### Task 2: ScoreTemplateBuilder

**Files:** `Sources/ScoreFollowCore/ScoreTemplate.swift`, `Tests/ScoreFollowCoreTests/ScoreTemplateBuilderTests.swift`

**Interfaces (Produces):**
- `public struct TimemapEntry: Decodable { qstamp: Double; on: [String]?; off: [String]?; measureOn: String? }`
- `public struct ScoreEvent: Equatable, Sendable { index: Int; qstamp: Double; noteIDs: [String]; pitches: [Int]; measureID: String?; template: Chroma }`
- `public enum ScoreTemplateBuilder { static func events(from timemap: [TimemapEntry], pitches: [String: Int]) -> [ScoreEvent]; static func template(for pitches: [Int]) -> Chroma }`

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import ScoreFollowCore

final class ScoreTemplateBuilderTests: XCTestCase {
    func testTemplateHasFundamentalAndHarmonics() {
        let t = ScoreTemplateBuilder.template(for: [60])   // C4: 배음 C(1.0) C(0.5) G(0.33)
        XCTAssertGreaterThan(t.values[0], t.values[7])
        XCTAssertGreaterThan(t.values[7], 0)
        XCTAssertEqual(t.values[1], 0)
        XCTAssertEqual(sqrt(t.values.map { $0 * $0 }.reduce(0, +)), 1, accuracy: 1e-4)
    }

    func testEventsCarrySustainedNotesAndMeasure() throws {
        let json = """
        [{"qstamp":0,"on":["n1","n2"],"measureOn":"m1"},
         {"qstamp":1,"off":["n1"],"on":["n3"]},
         {"qstamp":2,"off":["n2","n3"]},
         {"qstamp":2,"on":["n4"],"measureOn":"m2"}]
        """
        let entries = try JSONDecoder().decode([TimemapEntry].self, from: Data(json.utf8))
        let events = ScoreTemplateBuilder.events(from: entries, pitches: ["n1": 60, "n2": 64, "n3": 67, "n4": 72])
        XCTAssertEqual(events.count, 3)                       // off만 있는 항목은 이벤트가 아님
        XCTAssertEqual(events[0].pitches.sorted(), [60, 64])
        XCTAssertEqual(events[1].pitches.sorted(), [64, 67])  // n2 지속 + n3
        XCTAssertEqual(events[1].noteIDs, ["n3"])
        XCTAssertEqual(events[2].pitches, [72])
        XCTAssertEqual(events.map(\.measureID), ["m1", "m1", "m2"])
        XCTAssertEqual(events.map(\.index), [0, 1, 2])
    }
}
```

- [ ] **Step 2: 구현**

```swift
import Foundation

public struct TimemapEntry: Decodable, Sendable {
    public var qstamp: Double
    public var on: [String]?
    public var off: [String]?
    public var measureOn: String?
}

public struct ScoreEvent: Equatable, Sendable {
    public let index: Int
    public let qstamp: Double
    /// 이 시점에 시작하는 음표 id (하이라이트 대상)
    public let noteIDs: [String]
    /// 이 시점에 울리는 모든 MIDI 피치 (지속음 포함)
    public let pitches: [Int]
    public let measureID: String?
    public let template: Chroma
}

public enum ScoreTemplateBuilder {
    static let harmonicWeights: [(Int, Float)] = [(0, 1.0), (12, 0.5), (19, 0.33)]  // 1·2·3배음(반음 오프셋)

    public static func template(for pitches: [Int]) -> Chroma {
        var v = [Float](repeating: 0, count: 12)
        for p in pitches {
            for (offset, w) in harmonicWeights {
                v[((p + offset) % 12 + 12) % 12] += w
            }
        }
        return Chroma(values: v).normalized()
    }

    public static func events(from timemap: [TimemapEntry], pitches: [String: Int]) -> [ScoreEvent] {
        var sounding = Set<String>()
        var measure: String?
        var events: [ScoreEvent] = []
        for entry in timemap {
            if let m = entry.measureOn { measure = m }
            for id in entry.off ?? [] { sounding.remove(id) }
            let onIDs = (entry.on ?? []).filter { pitches[$0] != nil }
            for id in onIDs { sounding.insert(id) }
            guard !onIDs.isEmpty else { continue }
            let ps = sounding.compactMap { pitches[$0] }.sorted()
            events.append(ScoreEvent(index: events.count, qstamp: entry.qstamp, noteIDs: onIDs,
                                     pitches: ps, measureID: measure, template: template(for: ps)))
        }
        return events
    }
}
```

Run → PASS. Commit: `feat: ScoreTemplateBuilder — 타임맵을 크로마 템플릿 이벤트로`

---

### Task 3: OnlineDTW

**Files:** `Sources/ScoreFollowCore/OnlineDTW.swift`, `Tests/ScoreFollowCoreTests/OnlineDTWTests.swift`

**Interfaces (Produces):**
- `public struct OnlineDTWSettings { windowSize: Int = 200; verticalPenalty: Float = 1.5; confirmFrames: Int = 2; static let `default` }`
- `public struct OnlineDTW { init(templates: [Chroma], settings: OnlineDTWSettings = .default); private(set) var currentIndex: Int; mutating func step(_ chroma: Chroma) -> Int; mutating func reset(to index: Int) }`

- [ ] **Step 1: 실패하는 테스트**

```swift
import XCTest
@testable import ScoreFollowCore

final class OnlineDTWTests: XCTestCase {
    /// C장조 안에서 순환하는 3화음 8개 (인접 이벤트가 서로 다르게)
    let chords: [[Int]] = [[60,64,67],[62,65,69],[64,67,71],[65,69,72],[67,71,74],[69,72,76],[71,74,77],[72,76,79]]
    var templates: [Chroma] { chords.map(ScoreTemplateBuilder.template(for:)) }

    /// 각 이벤트를 framesPerEvent 프레임씩 재생한 크로마 스트림 (잡음 추가)
    func stream(framesPerEvent: [Int], noise: Float = 0.05, seed: UInt64 = 1) -> [Chroma] {
        var rng = SystemRandomNumberGenerator()
        var out: [Chroma] = []
        for (i, n) in framesPerEvent.enumerated() {
            for _ in 0..<n {
                let noisy = templates[i].values.map { $0 + Float.random(in: -noise...noise, using: &rng) }
                out.append(Chroma(values: noisy.map { max($0, 0) }).normalized())
            }
        }
        return out
    }

    func run(_ frames: [Chroma]) -> [Int] {
        var dtw = OnlineDTW(templates: templates)
        return frames.map { dtw.step($0) }
    }

    func testTracksNormalTempoMonotonically() {
        let path = run(stream(framesPerEvent: Array(repeating: 10, count: 8)))
        XCTAssertEqual(path.last, 7)
        XCTAssertTrue(zip(path, path.dropFirst()).allSatisfy { $0 <= $1 }, "단조 증가여야 함")
    }

    func testTracksDoubleAndHalfTempo() {
        XCTAssertEqual(run(stream(framesPerEvent: Array(repeating: 3, count: 8))).last, 7)
        XCTAssertEqual(run(stream(framesPerEvent: Array(repeating: 25, count: 8))).last, 7)
    }

    func testMidStreamPositionIsClose() {
        let path = run(stream(framesPerEvent: Array(repeating: 10, count: 8)))
        // 4번째 이벤트 재생 중(프레임 35)에는 인덕스 3 근처여야 함
        XCTAssertTrue((2...4).contains(path[35]), "실제 \(path[35])")
    }

    func testResetJumpsAndContinues() {
        var dtw = OnlineDTW(templates: templates)
        dtw.reset(to: 5)
        XCTAssertEqual(dtw.currentIndex, 5)
        let frames = stream(framesPerEvent: [0,0,0,0,0,10,10,10])
        var last = 5
        for f in frames { last = dtw.step(f) }
        XCTAssertEqual(last, 7)
    }

    func testDoesNotRunAheadOnRepeatedChord() {
        // 첫 화음만 60프레임 → 여전히 0 근처
        let path = run(stream(framesPerEvent: [60,0,0,0,0,0,0,0]))
        XCTAssertLessThanOrEqual(path.last!, 1)
    }
}
```

- [ ] **Step 2: 구현**

```swift
import Foundation

public struct OnlineDTWSettings: Sendable {
    /// 현재 위치 앞쪽으로 탐색할 이벤트 수
    public var windowSize: Int = 200
    /// 시간 진행 없이 이벤트를 건너뛰는 이동(수직)의 비용 배수 — 앞서 달리는 것을 억제
    public var verticalPenalty: Float = 1.5
    /// 인덕스 변경을 확정하기 위해 같은 결정이 유지되어야 하는 프레임 수
    public var confirmFrames: Int = 2
    public static let `default` = OnlineDTWSettings()
    public init() {}
}

/// 온라인 DTW: 입력 프레임마다 누적 비용 행을 갱신하고 창 안에서 최소 비용 이벤트를 현재 위치로 낸다.
/// 단조 증가만 허용한다.
public struct OnlineDTW {
    public let templates: [Chroma]
    public let settings: OnlineDTWSettings
    public private(set) var currentIndex: Int = 0

    private var row: [Float]           // D[t][j] (전체 이벤트)
    private var candidate: Int = 0
    private var candidateCount = 0

    public init(templates: [Chroma], settings: OnlineDTWSettings = .default) {
        self.templates = templates
        self.settings = settings
        row = [Float](repeating: .infinity, count: max(templates.count, 1))
        if !templates.isEmpty { row[0] = 0 }
    }

    public mutating func reset(to index: Int) {
        guard !templates.isEmpty else { return }
        currentIndex = min(max(index, 0), templates.count - 1)
        row = [Float](repeating: .infinity, count: templates.count)
        row[currentIndex] = 0
        candidate = currentIndex
        candidateCount = 0
    }

    public mutating func step(_ chroma: Chroma) -> Int {
        guard !templates.isEmpty else { return 0 }
        let lo = currentIndex
        let hi = min(templates.count - 1, currentIndex + settings.windowSize)
        var next = [Float](repeating: .infinity, count: templates.count)
        for j in lo...hi {
            let cost = 1 - Chroma.similarity(chroma, templates[j])
            let stay = row[j]                                   // 수평: 같은 이벤트 지속
            let diag = j > lo ? row[j - 1] : .infinity          // 대각: 이벤트 진행 + 시간 진행
            let vert = j > lo ? next[j - 1] + cost * (settings.verticalPenalty - 1) : .infinity  // 수직: 건너뛰기
            next[j] = cost + min(stay, diag, vert)
        }
        row = next

        var best = lo
        for j in lo...hi where row[j] < row[best] { best = j }
        if best == candidate {
            candidateCount += 1
        } else {
            candidate = best
            candidateCount = 1
        }
        if candidateCount >= settings.confirmFrames, candidate > currentIndex {
            currentIndex = candidate
        }
        return currentIndex
    }
}
```

Run → PASS (실패 시 `verticalPenalty`·잡음 수준을 조정하지 말고 로직을 점검). Commit: `feat: OnlineDTW — 단조 증가 온라인 정렬`

---

### Task 4: 뷰어 공통부 확장 — PageCursor, accessory, 탭 넘김 비활성

**Files:** Create `App/Views/PageCursor.swift`; Modify `App/Views/ScoreViewerShell.swift`, `App/Views/PDFScoreViewer.swift`, `App/MusicXML/MusicXMLScoreViewer.swift`

**Interfaces (Produces):**
- `@MainActor final class PageCursor: ObservableObject { @Published var leadingIndex: Int; @Published var isTwoUp: Bool; var pageCount: Int; var visibleIndices: [Int]; func turn(_: PageTurnEvent) -> Bool; func snap() }`
- `ScoreViewerShell<Content, Accessory>(score:library:pageCount:cursor:pageSize:disablesTapTurning:content:accessory:)` — accessory는 툴바 오른쪽에 추가되는 뷰(기본 EmptyView)

- [ ] **Step 1: PageCursor**

```swift
import Foundation
import GestureCore

/// 뷰어의 현재 펼침 위치. Shell과 따라가기 로직이 함께 읽고 쓴다.
@MainActor
final class PageCursor: ObservableObject {
    @Published var leadingIndex = 0
    @Published var isTwoUp = false
    var pageCount = 0

    private var navigator: PageNavigator { PageNavigator(pageCount: pageCount, twoUp: isTwoUp) }
    var visibleIndices: [Int] { navigator.visibleIndices(from: leadingIndex) }

    /// 넘김 성공 여부를 반환 (끝이면 false)
    @discardableResult
    func turn(_ event: PageTurnEvent) -> Bool {
        let target = event == .next ? navigator.next(from: leadingIndex) : navigator.previous(from: leadingIndex)
        guard target != leadingIndex else { return false }
        leadingIndex = target
        return true
    }

    /// 회전 등으로 펼침 경계가 바뀌었을 때 짝수 인덕스로 스냅
    func snap() { leadingIndex = navigator.leadingIndex(from: leadingIndex) }
}
```

- [ ] **Step 2: Shell 수정**

- 제네릭에 `Accessory: View` 추가, 프로퍼티 `@ObservedObject var cursor: PageCursor`, `let disablesTapTurning: Bool`, `@ViewBuilder let accessory: () -> Accessory`
- `@State currentPageIndex`, `@State isTwoUp`, `navigator` 제거 → `cursor.leadingIndex`, `cursor.isTwoUp`, `cursor.visibleIndices`
- `onAppear`: `cursor.pageCount = pageCount; cursor.leadingIndex = min(library.lastPage(of: score), max(pageCount - 1, 0))`
- `GeometryReader.onAppear/onChange(geo.size)`: `cursor.isTwoUp = ...; cursor.snap()`
- 탭 영역 조건: `if !isAnnotating && !disablesTapTurning`
- `turn(_:)`: `guard cursor.turn(event) else { return }; flash(...)`
- 툴바: 기존 두 항목 앞에 `ToolbarItem(placement: .topBarTrailing) { accessory() }`
- `pageLabel`은 `cursor.visibleIndices` 사용
- `init` 확장(기본값): `extension ScoreViewerShell where Accessory == EmptyView { init(score:library:pageCount:cursor:pageSize:disablesTapTurning: Bool = false, content:) }`

`PDFScoreViewer`: `@StateObject private var cursor = PageCursor()` 를 만들어 전달. `MusicXMLScoreViewer`도 동일(Task 6에서 확장).

- [ ] **Step 3: 빌드·전체 테스트·PDF/디지털 뷰어 수동 회귀(탭 넘김·펼침·필기)** → Commit: `refactor: PageCursor 외부화, Shell accessory·탭 넘김 비활성 옵션`

---

### Task 5: 엔진 확장 + MicrophoneSource + ScoreFollower

**Files:** Modify `Vendor/verovio/verovio.html`, `App/MusicXML/VerovioEngine.swift`; Create `App/Following/MicrophoneSource.swift`, `App/Following/ScoreFollower.swift`; Modify `project.yml`(마이크 권한 문구, ScoreFollowCore 패키지), `AppTests/VerovioEngineTests.swift`(pitches/systemMap 테스트)

**Interfaces (Produces):**
- 엔진: `func pitches(for ids: [String]) async throws -> [String: Int]`, `struct PageSystemMap: Decodable { count: Int; notes: [String: Int]; measures: [String: Int] }`, `func systemMap(page index: Int) async throws -> PageSystemMap`, `func timemapEntries() async throws -> [TimemapEntry]`
- `final class MicrophoneSource { init(); var sampleRate: Double; func start(onFrame: @escaping ([Float]) -> Void) throws; func stop() }` — 4096 프레임/2048 홉
- `@MainActor final class ScoreFollower: ObservableObject { @Published currentEvent: ScoreEvent?; @Published isListening; @Published level: Float; @Published permissionDenied; func configure(events: [ScoreEvent]); func start() async; func stop(); func relocate(toEventIndex: Int) }`

- [ ] **Step 1: verovio.html에 API 추가** (`window.vrv` 객체 안)

```js
  pitches: (idsJson) => {
    const out = {};
    JSON.parse(idsJson).forEach(id => { const v = tk.getMIDIValuesForElement(id); if (v && v.pitch > 0) out[id] = v.pitch; });
    return JSON.stringify(out);
  },
  systemMap: (n) => {
    const doc = new DOMParser().parseFromString(tk.renderToSVG(n, false), "image/svg+xml");
    const systems = Array.from(doc.querySelectorAll("g.system"));
    const notes = {}, measures = {};
    systems.forEach((sys, i) => {
      sys.querySelectorAll("g.measure").forEach(m => { measures[m.id] = i; });
      sys.querySelectorAll("g.note").forEach(nt => { notes[nt.id] = i; });
    });
    return JSON.stringify({ count: systems.length, notes, measures });
  }
```

- [ ] **Step 2: 엔진 테스트 추가 후 구현**

테스트(기존 `testLoadsSampleRendersPagesAndTimemap`에 이어서):
```swift
        let entries = try await engine.timemapEntries()
        let ids = Array(entries.flatMap { $0.on ?? [] }.prefix(20))
        let pitches = try await engine.pitches(for: ids)
        XCTAssertEqual(pitches.count, ids.count)
        XCTAssertTrue(pitches.values.allSatisfy { (21...108).contains($0) })
        let map = try await engine.systemMap(page: 0)
        XCTAssertGreaterThan(map.count, 0)
        XCTAssertFalse(map.notes.isEmpty)
        XCTAssertFalse(map.measures.isEmpty)
```

구현(VerovioEngine에 추가, `import ScoreFollowCore`):
```swift
    struct PageSystemMap: Decodable { let count: Int; let notes: [String: Int]; let measures: [String: Int] }

    func timemapEntries() async throws -> [TimemapEntry] {
        try JSONDecoder().decode([TimemapEntry].self, from: try await timemap())
    }

    func pitches(for ids: [String]) async throws -> [String: Int] {
        let idsJSON = String(data: try JSONSerialization.data(withJSONObject: ids), encoding: .utf8)!
        let escaped = idsJSON.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        guard let json = try await evaluate("window.vrv.pitches('\(escaped)')") as? String else {
            throw VerovioError.scriptFailed("피치 조회 실패")
        }
        return try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
    }

    func systemMap(page index: Int) async throws -> PageSystemMap {
        guard let json = try await evaluate("window.vrv.systemMap(\(index + 1))") as? String else {
            throw VerovioError.scriptFailed("시스템 맵 실패")
        }
        return try JSONDecoder().decode(PageSystemMap.self, from: Data(json.utf8))
    }
```

- [ ] **Step 3: MicrophoneSource**

```swift
import AVFoundation

/// 마이크 입력을 모노 Float 프레임(4096, 홉 2048)으로 잘라 전달한다.
final class MicrophoneSource {
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private let frameSize = 4096
    private let hop = 2048
    private(set) var sampleRate: Double = 44100

    func start(onFrame: @escaping ([Float]) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        buffer.removeAll()
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hop), format: format) { [weak self] pcm, _ in
            guard let self, let ch = pcm.floatChannelData else { return }
            let n = Int(pcm.frameLength)
            self.buffer.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
            while self.buffer.count >= self.frameSize {
                onFrame(Array(self.buffer[0..<self.frameSize]))
                self.buffer.removeFirst(self.hop)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```

- [ ] **Step 4: ScoreFollower**

```swift
import Foundation
import AVFoundation
import ScoreFollowCore

/// 마이크 → 크로마 → 온라인 DTW → 현재 이벤트. UI는 @Published 값만 본다.
@MainActor
final class ScoreFollower: ObservableObject {
    @Published private(set) var currentEvent: ScoreEvent?
    @Published private(set) var isListening = false
    @Published private(set) var level: Float = 0        // 0…1 (RMS 기반)
    @Published private(set) var permissionDenied = false

    private(set) var events: [ScoreEvent] = []
    private let mic = MicrophoneSource()
    private var extractor: ChromaExtractor?
    private var dtw: OnlineDTW?

    var isAvailable: Bool { !events.isEmpty }

    func configure(events: [ScoreEvent]) {
        self.events = events
        dtw = OnlineDTW(templates: events.map(\.template))
        currentEvent = events.first
    }

    func start() async {
        guard isAvailable, !isListening else { return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { permissionDenied = true; return }
        do {
            try mic.start { [weak self] frame in
                guard let self else { return }
                let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
                let chroma = self.extractorLocked().process(frame)
                Task { @MainActor in self.handle(chroma: chroma, rms: rms) }
            }
            extractor = ChromaExtractor(sampleRate: mic.sampleRate)
            isListening = true
        } catch {
            isListening = false
        }
    }

    /// 오디오 스레드에서 호출되므로 MainActor를 거치지 않고 추출기를 얻는다 (start 이후 불변)
    private nonisolated func extractorLocked() -> ChromaExtractor {
        MainActor.assumeIsolated { extractor ?? ChromaExtractor(sampleRate: 44100) }
    }

    private func handle(chroma: Chroma?, rms: Float) {
        level = min(1, rms * 8)
        guard let chroma, var dtw else { return }
        let index = dtw.step(chroma)
        self.dtw = dtw
        if events.indices.contains(index), currentEvent?.index != index {
            currentEvent = events[index]
        }
    }

    func stop() {
        guard isListening else { return }
        mic.stop()
        isListening = false
        level = 0
    }

    func relocate(toEventIndex index: Int) {
        guard events.indices.contains(index) else { return }
        dtw?.reset(to: index)
        currentEvent = events[index]
    }
}
```
> 주의: `extractorLocked`의 `assumeIsolated`는 오디오 스레드에서 크래시한다. 대신 `extractor`를 `start()`에서 **탭 설치 전에** 만들고 지역 상수로 캡처해 클로저에 넘긴다(구현 시 이 형태로 작성: `let extractor = ChromaExtractor(sampleRate: mic.sampleRate)` — 단, `sampleRate`는 `mic.start` 안에서 정해지므로 `MicrophoneSource.start`가 `sampleRate`를 콜백 설치 전에 확정하도록 `prepare()` 단계에서 읽고, 콜백은 `(frame, sampleRate)`를 함께 전달하게 시그니처를 `onFrame: @escaping ([Float], Double) -> Void`로 한다. 추출기는 첫 콜백에서 샘플레이트로 lazily 생성해 `nonisolated(unsafe) var`로 보관.)

- [ ] **Step 5: project.yml** — `packages:`에 `ScoreFollowCore: { path: Packages/ScoreFollowCore }`, 타깃 `dependencies`에 `- package: ScoreFollowCore`, `info.properties`에 `NSMicrophoneUsageDescription: 연주 소리를 듣고 악보의 현재 위치를 따라가기 위해 마이크를 사용합니다.`

- [ ] **Step 6: 빌드·테스트(VerovioEngine 확장 테스트 통과)** → Commit: `feat: 엔진 피치/시스템 맵 API, MicrophoneSource, ScoreFollower`

---

### Task 6: 뷰어 연동 — 하이라이트·자동 넘김·탭 재지정·컨트롤

**Files:** Create `App/Following/FollowControls.swift`; Modify `App/MusicXML/SVGPageView.swift`(`SVGPageController`), `App/MusicXML/MusicXMLScoreViewer.swift`

- [ ] **Step 1: SVGPageView에 컨트롤러와 마디 히트테스트**

```swift
/// 표시 웹뷰에 JS 질의를 보내기 위한 핸들 (페이지별 1개)
@MainActor final class SVGPageController: ObservableObject {
    weak var webView: WKWebView?
    /// 페이지 내 정규화 좌표(0…1)의 마디 id
    func measureID(atX x: CGFloat, y: CGFloat) async -> String? {
        guard let webView else { return nil }
        let js = "(function(){const e=document.elementFromPoint(\(x)*window.innerWidth,\(y)*window.innerHeight);const m=e&&e.closest('g.measure');return m?m.id:''})()"
        return (try? await webView.evaluateJavaScript(js) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
```
`SVGPageView`에 `var controller: SVGPageController? = nil` 추가, `makeUIView`에서 `controller?.webView = webView`, `updateUIView`에서도 갱신.

- [ ] **Step 2: FollowControls**

```swift
import SwiftUI

/// 툴바용: 따라가기 토글(귀 아이콘) + 듣는 중 레벨 미터
struct FollowControls: View {
    @ObservedObject var follower: ScoreFollower
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if follower.isListening {
                Capsule().fill(.secondary.opacity(0.3)).frame(width: 40, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.green).frame(width: 40 * CGFloat(follower.level), height: 6)
                    }
                    .accessibilityLabel("입력 레벨")
            }
            Button(action: onToggle) {
                Image(systemName: follower.isListening ? "ear.fill" : "ear")
            }
            .disabled(!follower.isAvailable)
            .accessibilityLabel(follower.isListening ? "따라가기 끄기" : "따라가기 켜기")
        }
    }
}
```

- [ ] **Step 3: MusicXMLScoreViewer 연동**

상태 추가: `@StateObject cursor = PageCursor()`, `@StateObject follower = ScoreFollower()`, `@State noteSystem: [String: (page: Int, system: Int)]`, `@State systemCounts: [Int: Int]`, `@State measureFirstEvent: [String: Int]`, `@State controllers: [Int: SVGPageController]`, `@State lastAutoTurnedFrom: Int?`, `@State followError: String?`

로드(`.task(id: score.id)`) 뒤 이어서:
```swift
let entries = try await VerovioEngine.shared.timemapEntries()
let ids = Array(Set(entries.flatMap { $0.on ?? [] }))
let pitches = try await VerovioEngine.shared.pitches(for: ids)
let events = ScoreTemplateBuilder.events(from: entries, pitches: pitches)
var noteSystem: [String: (Int, Int)] = [:]; var counts: [Int: Int] = [:]
for p in 0..<count {
    let map = try await VerovioEngine.shared.systemMap(page: p)
    counts[p] = map.count
    for (id, sys) in map.notes { noteSystem[id] = (p, sys) }
}
var firstEvent: [String: Int] = [:]
for e in events { if let m = e.measureID, firstEvent[m] == nil { firstEvent[m] = e.index } }
self.noteSystem = noteSystem; self.systemCounts = counts; self.measureFirstEvent = firstEvent
follower.configure(events: events)
```

Shell 호출: `ScoreViewerShell(score:, library:, pageCount:, cursor: cursor, pageSize: { _ in MusicXMLPage.size }, disablesTapTurning: follower.isListening) { index in ZStack { SVGPage(index:, svgs:, highlightIDs: highlightIDs(for: index), controller: controller(for: index)); if follower.isListening { Color.clear.contentShape(Rectangle()).onTapGesture(coordinateSpace: .local) { pt in relocate(page: index, at: pt) } } } } accessory: { FollowControls(follower: follower) { toggleFollow() } }`

- `highlightIDs(for page)`: `guard let e = follower.currentEvent else { return [] }; return e.noteIDs.filter { noteSystem[$0]?.page == page }`
- `relocate(page:at:)`: 탭 위치를 페이지 프레임 크기로 나눠 0…1로 만들어 `controller.measureID(atX:y:)` → `measureFirstEvent[id]` → `follower.relocate(toEventIndex:)`. 탭 위치의 정규화는 `SVGPage`가 `GeometryReader`로 자신의 크기를 알고 있으므로 `SVGPage` 내부에 탭 처리와 콜백 `onTapNormalized: ((CGFloat, CGFloat) -> Void)?`를 둔다.
- 자동 넘김(`.onChange(of: follower.currentEvent)`): 
```swift
guard let e = newValue, let first = e.noteIDs.first, let loc = noteSystem[first] else { return }
let visible = cursor.visibleIndices
if loc.page > (visible.last ?? -1) { cursor.leadingIndex = PageNavigator(pageCount: cursor.pageCount, twoUp: cursor.isTwoUp).leadingIndex(from: loc.page); return }  // 화면 밖이면 즉시 이동
if loc.page == visible.last, let count = systemCounts[loc.page], loc.system == count - 1, lastAutoTurnedFrom != loc.page {
    lastAutoTurnedFrom = loc.page
    cursor.turn(.next)
}
```
- `toggleFollow()`: `if follower.isListening { follower.stop() } else { Task { await follower.start() } }`; `follower.permissionDenied`면 배너 "마이크 권한이 없어 따라가기를 쓸 수 없습니다. 설정 앱에서 허용해 주세요."
- `.onDisappear { follower.stop() }`, scenePhase가 비활성이면 `follower.stop()`

- [ ] **Step 4: 빌드·테스트·시뮬레이터 확인**
1. 바흐 열기 → 귀 버튼 활성 → 누르면 마이크 권한 → 레벨 미터 표시
2. Mac에서 C장조 화음(또는 유튜브 BWV 846 재생) → 하이라이트가 앞으로 진행, 페이지 끝에서 자동 넘김
3. 따라가기 중 마디 탭 → 그 마디로 하이라이트 이동
4. PDF 뷰어에는 귀 버튼 없음, 기존 동작 유지

Commit: `feat: 오디오 악보 따라가기 — 하이라이트, 자동 넘김, 탭 재지정`

## 완료 기준
- [ ] ScoreFollowCore 테스트(크로마 5, 템플릿 2, DTW 5) 통과, 앱 테스트 통과
- [ ] 시뮬레이터에서 실제 소리에 반응해 하이라이트·자동 넘김 동작
- [ ] 마이크 권한 거부 시 안내, 타임맵 없는 악보에서 버튼 비활성
