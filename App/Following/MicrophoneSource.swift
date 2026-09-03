import AVFoundation

/// 마이크 입력을 모노 Float 프레임(4096 샘플, 홉 2048)으로 잘라 전달한다.
/// 콜백은 오디오 스레드에서 호출된다.
final class MicrophoneSource {
    static let frameSize = 4096
    static let hop = 2048

    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private(set) var sampleRate: Double = 44100
    private(set) var isRunning = false

    /// onFrame(frame, sampleRate)
    func start(onFrame: @escaping ([Float], Double) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        let rate = sampleRate
        buffer.removeAll()

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Self.hop), format: format) { [weak self] pcm, _ in
            guard let self, let channels = pcm.floatChannelData else { return }
            let count = Int(pcm.frameLength)
            self.buffer.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
            while self.buffer.count >= Self.frameSize {
                onFrame(Array(self.buffer[0..<Self.frameSize]), rate)
                self.buffer.removeFirst(Self.hop)
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
