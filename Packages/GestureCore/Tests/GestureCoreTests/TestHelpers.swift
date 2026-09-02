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
