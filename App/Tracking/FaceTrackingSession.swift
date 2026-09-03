import ARKit
import Combine
import GestureCore
import QuartzCore

/// ARKit 얼굴 추적 세션을 감싸 GestureCore 입력(FaceFrame)으로 변환하고,
/// GestureEngine의 판정 결과를 이벤트로 발행한다.
@MainActor
final class FaceTrackingSession: NSObject, ObservableObject {
    @Published private(set) var isTrackingFace = false
    @Published private(set) var latestFrame: FaceFrame?
    /// 카메라 권한 거부 등으로 세션이 실패한 경우
    @Published private(set) var didFail = false

    let events = PassthroughSubject<PageTurnEvent, Never>()

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    /// 실기기 검증: 설정 화면의 실시간 값에서 고개를 "오른쪽"으로 돌렸을 때
    /// yaw가 음수로 나오면 이 값을 -1로 바꾼다.
    nonisolated private static let yawSign: Double = 1

    private let session = ARSession()
    private var engine = GestureEngine()

    override init() {
        super.init()
        session.delegate = self
    }

    func updateSettings(_ settings: GestureSettings) {
        engine.settings = settings
    }

    func start() {
        guard Self.isSupported else { return }
        didFail = false
        let config = ARFaceTrackingConfiguration()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        session.pause()
        isTrackingFace = false
    }

    private func handle(_ frame: FaceFrame, tracked: Bool) {
        isTrackingFace = tracked
        latestFrame = frame
        guard tracked else { return }
        if let event = engine.process(frame) {
            events.send(event)
        }
    }
}

extension FaceTrackingSession: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first,
              let camera = session.currentFrame?.camera else { return }

        // 카메라 기준 얼굴 회전 행렬에서 yaw(좌우 회전각) 추출
        let rel = simd_mul(camera.transform.inverse, face.transform)
        let zAxis = rel.columns.2
        let yawRadians = atan2(Double(zAxis.x), Double(zAxis.z))
        let yawDegrees = Self.yawSign * yawRadians * 180 / .pi

        // ARKit blendShape의 left/right는 사용자 기준
        let left = face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0
        let right = face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0

        let frame = FaceFrame(
            yawDegrees: yawDegrees,
            leftEyeBlink: left,
            rightEyeBlink: right,
            timestamp: CACurrentMediaTime()
        )
        let tracked = face.isTracked
        Task { @MainActor in
            self.handle(frame, tracked: tracked)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.didFail = true
            self.isTrackingFace = false
        }
    }
}
