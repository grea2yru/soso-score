import Foundation
import Accelerate

/// PCM 프레임(모노 Float) → 12차원 크로마. 무음(RMS < 임계값)이면 nil.
public final class ChromaExtractor {
    public let sampleRate: Double
    public let frameSize: Int
    public let silenceThresholdDB: Float

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    /// 각 FFT 빈의 피치 클래스 (-1 = 대역 밖)
    private let binToPitchClass: [Int]

    public init(sampleRate: Double, frameSize: Int = 4096, silenceThresholdDB: Float = -50) {
        precondition(frameSize > 0 && frameSize & (frameSize - 1) == 0, "frameSize는 2의 거듭제곱")
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.silenceThresholdDB = silenceThresholdDB
        let log2n = vDSP_Length(log2(Double(frameSize)))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: frameSize, isHalfWindow: false)
        let half = frameSize / 2
        binToPitchClass = (0..<half).map { bin in
            let freq = Double(bin) * sampleRate / Double(frameSize)
            guard freq >= 55, freq <= 2000 else { return -1 }
            let midi = 69 + 12 * log2(freq / 440)
            return ((Int(midi.rounded()) % 12) + 12) % 12
        }
    }

    public func process(_ samples: [Float]) -> Chroma? {
        guard samples.count == frameSize else { return nil }
        let rms = sqrt(vDSP.meanSquare(samples))
        let db = 20 * log10(max(rms, 1e-9))
        guard db > silenceThresholdDB else { return nil }

        let windowed = vDSP.multiply(samples, window)
        let half = frameSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(ptr.baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &magnitudes)
            }
        }

        var chroma = [Float](repeating: 0, count: 12)
        for (bin, pc) in binToPitchClass.enumerated() where pc >= 0 {
            chroma[pc] += magnitudes[bin]
        }
        // 진폭 스케일로 압축해 강한 배음의 지배를 줄임
        return Chroma(values: chroma.map { sqrt($0) }).normalized()
    }
}
