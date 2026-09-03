import Foundation

/// 12 피치 클래스(C=0 … B=11) 에너지 벡터
public struct Chroma: Equatable, Sendable {
    public var values: [Float]

    public init(values: [Float]) {
        precondition(values.count == 12, "크로마는 12차원이어야 합니다")
        self.values = values
    }

    public static let zero = Chroma(values: [Float](repeating: 0, count: 12))

    public func normalized() -> Chroma {
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return self }
        return Chroma(values: values.map { $0 / norm })
    }

    /// 코사인 유사도 (0…1). 영벡터가 있으면 0.
    public static func similarity(_ a: Chroma, _ b: Chroma) -> Float {
        let dot = zip(a.values, b.values).reduce(0) { $0 + $1.0 * $1.1 }
        let na = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let nb = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na * nb)
    }
}
