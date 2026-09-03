import XCTest
@testable import ScoreFollowCore

final class ChromaExtractorTests: XCTestCase {
    let sampleRate = 44100.0

    func sine(_ freqs: [Double], count: Int, amplitude: Float = 0.3) -> [Float] {
        (0..<count).map { i in
            let t = Double(i) / sampleRate
            return freqs.reduce(Float(0)) { $0 + amplitude * Float(sin(2 * .pi * $1 * t)) }
        }
    }

    func testCMajorTriadPeaksOnCEG() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let frame = sine([261.63, 329.63, 392.00], count: ex.frameSize)   // C4 E4 G4
        let chroma = ex.process(frame)!
        let top3 = chroma.values.enumerated().sorted { $0.element > $1.element }.prefix(3).map(\.offset)
        XCTAssertEqual(Set(top3), [0, 4, 7])
    }

    func testSingleNoteAIsPitchClass9() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let chroma = ex.process(sine([440], count: ex.frameSize))!
        XCTAssertEqual(chroma.values.enumerated().max { $0.element < $1.element }!.offset, 9)
    }

    func testSilenceReturnsNil() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        XCTAssertNil(ex.process([Float](repeating: 0, count: ex.frameSize)))
        XCTAssertNil(ex.process(sine([440], count: ex.frameSize, amplitude: 0.0005)))  // 약 -69 dBFS
    }

    func testOutputIsUnitLength() {
        let ex = ChromaExtractor(sampleRate: sampleRate)
        let c = ex.process(sine([440, 554.37], count: ex.frameSize))!
        XCTAssertEqual(sqrt(c.values.map { $0 * $0 }.reduce(0, +)), 1, accuracy: 1e-3)
    }

    func testSimilarityOfIdenticalIsOneAndDisjointIsZero() {
        let a = Chroma(values: [1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0]).normalized()
        XCTAssertEqual(Chroma.similarity(a, a), 1, accuracy: 1e-5)
        let b = Chroma(values: [0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0]).normalized()
        XCTAssertEqual(Chroma.similarity(a, b), 0, accuracy: 1e-5)
    }
}
