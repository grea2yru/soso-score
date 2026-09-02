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
