import Foundation

/// Verovio `renderToTimemap` 항목
public struct TimemapEntry: Decodable, Sendable {
    public var qstamp: Double
    public var on: [String]?
    public var off: [String]?
    public var measureOn: String?

    public init(qstamp: Double, on: [String]? = nil, off: [String]? = nil, measureOn: String? = nil) {
        self.qstamp = qstamp
        self.on = on
        self.off = off
        self.measureOn = measureOn
    }
}

/// 악보의 onset 이벤트 하나: 이 시점에 시작하는 음표들과, 그때 울리는 모든 피치의 크로마 템플릿
public struct ScoreEvent: Equatable, Sendable {
    public let index: Int
    public let qstamp: Double
    /// 이 시점에 시작하는 음표 id (하이라이트 대상)
    public let noteIDs: [String]
    /// 이 시점에 울리는 모든 MIDI 피치 (지속음 포함, 정렬)
    public let pitches: [Int]
    public let measureID: String?
    public let template: Chroma
}

public enum ScoreTemplateBuilder {
    /// 1·2·3배음의 반음 오프셋과 가중치
    static let harmonicWeights: [(Int, Float)] = [(0, 1.0), (12, 0.5), (19, 0.33)]

    public static func template(for pitches: [Int]) -> Chroma {
        var v = [Float](repeating: 0, count: 12)
        for p in pitches {
            for (offset, w) in harmonicWeights {
                v[((p + offset) % 12 + 12) % 12] += w
            }
        }
        return Chroma(values: v).normalized()
    }

    /// 타임맵에서 onset 이벤트 시퀀스를 만든다. off만 있는 항목은 이벤트가 아니다.
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
