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
