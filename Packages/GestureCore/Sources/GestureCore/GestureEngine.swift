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
