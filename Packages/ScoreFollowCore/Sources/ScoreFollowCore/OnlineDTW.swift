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

    private var row: [Float]           // 직전 프레임의 누적 비용 (이벤트별)
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
