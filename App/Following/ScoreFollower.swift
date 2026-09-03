import Foundation
import AVFoundation
import ScoreFollowCore

/// 마이크 → 크로마 → 온라인 DTW → 현재 이벤트. UI는 @Published 값만 본다.
@MainActor
final class ScoreFollower: ObservableObject {
    @Published private(set) var currentEvent: ScoreEvent?
    @Published private(set) var isListening = false
    /// 입력 레벨 0…1 (RMS 기반, 표시용)
    @Published private(set) var level: Float = 0
    @Published private(set) var permissionDenied = false

    private(set) var events: [ScoreEvent] = []
    private let mic = MicrophoneSource()
    private var dtw: OnlineDTW?

    /// 악보에 음표 이벤트가 있어 따라가기가 가능한지
    var isAvailable: Bool { !events.isEmpty }

    func configure(events: [ScoreEvent]) {
        self.events = events
        dtw = OnlineDTW(templates: events.map(\.template))
        currentEvent = events.first
    }

    func start() async {
        guard isAvailable, !isListening else { return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        // 추출기는 오디오 스레드 전용으로 첫 프레임에서 샘플레이트에 맞춰 만든다
        let box = ExtractorBox()
        do {
            try mic.start { [weak self] frame, rate in
                let extractor = box.extractor(for: rate)
                let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
                let chroma = extractor.process(frame)
                Task { @MainActor [weak self] in self?.handle(chroma: chroma, rms: rms) }
            }
            isListening = true
        } catch {
            isListening = false
        }
    }

    private func handle(chroma: Chroma?, rms: Float) {
        level = min(1, rms * 8)
        guard let chroma, var dtw else { return }
        let index = dtw.step(chroma)
        self.dtw = dtw
        if events.indices.contains(index), currentEvent?.index != index {
            currentEvent = events[index]
        }
    }

    func stop() {
        guard isListening else { return }
        mic.stop()
        isListening = false
        level = 0
    }

    /// 사용자가 마디를 탭했을 때 그 지점부터 다시 정렬
    func relocate(toEventIndex index: Int) {
        guard events.indices.contains(index) else { return }
        dtw?.reset(to: index)
        currentEvent = events[index]
    }
}

/// 오디오 스레드에서만 접근하는 추출기 보관함 (샘플레이트가 바뀌면 재생성)
private final class ExtractorBox: @unchecked Sendable {
    private var extractor: ChromaExtractor?
    func extractor(for rate: Double) -> ChromaExtractor {
        if let e = extractor, e.sampleRate == rate { return e }
        let e = ChromaExtractor(sampleRate: rate, frameSize: MicrophoneSource.frameSize)
        extractor = e
        return e
    }
}
