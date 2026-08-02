import Testing
@testable import KotoverlayCore

@Suite("Frame change detection")
struct FrameChangeDetectorTests {
    @Test("First frame changes and identical frame does not")
    func identicalFrames() {
        var detector = FrameChangeDetector()
        let signature = FrameSignature(samples: [10, 20, 30, 40])

        let firstChanged = detector.hasMeaningfulChange(signature: signature)
        let secondChanged = detector.hasMeaningfulChange(signature: signature)
        #expect(firstChanged)
        #expect(!secondChanged)
    }

    @Test("Noise is ignored but a meaningful region changes")
    func thresholding() {
        var detector = FrameChangeDetector(
            sampleDifferenceThreshold: 4,
            changedSampleFraction: 0.25
        )
        let firstChanged = detector.hasMeaningfulChange(
            signature: FrameSignature(samples: [10, 10, 10, 10])
        )
        let noisyChanged = detector.hasMeaningfulChange(
            signature: FrameSignature(samples: [12, 12, 12, 12])
        )
        let regionChanged = detector.hasMeaningfulChange(
            signature: FrameSignature(samples: [30, 12, 12, 12])
        )
        #expect(firstChanged)
        #expect(!noisyChanged)
        #expect(regionChanged)
    }
}
