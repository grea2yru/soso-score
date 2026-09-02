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
