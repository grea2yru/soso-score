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
