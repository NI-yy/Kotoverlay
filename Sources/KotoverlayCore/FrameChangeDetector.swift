import CoreGraphics
import Foundation

public struct FrameSignature: Equatable, Sendable {
    public let samples: [UInt8]

    public init(samples: [UInt8]) {
        self.samples = samples
    }

    public init(image: CGImage, columns: Int = 32, rows: Int = 18) throws {
        let columns = max(1, columns)
        let rows = max(1, rows)
        var samples = [UInt8](repeating: 0, count: columns * rows)
        guard let context = CGContext(
            data: &samples,
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw FrameSignatureError.contextCreationFailed
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        self.samples = samples
    }
}

public enum FrameSignatureError: Error, LocalizedError, Sendable {
    case contextCreationFailed

    public var errorDescription: String? {
        "Could not create the in-memory frame signature."
    }
}

public struct FrameChangeDetector: Sendable {
    private var previous: FrameSignature?
    private let sampleDifferenceThreshold: UInt8
    private let changedSampleFraction: Double

    public init(
        sampleDifferenceThreshold: UInt8 = 4,
        changedSampleFraction: Double = 0.01
    ) {
        self.sampleDifferenceThreshold = sampleDifferenceThreshold
        self.changedSampleFraction = min(1, max(0, changedSampleFraction))
    }

    public mutating func hasMeaningfulChange(image: CGImage) throws -> Bool {
        try hasMeaningfulChange(signature: FrameSignature(image: image))
    }

    public mutating func hasMeaningfulChange(signature: FrameSignature) -> Bool {
        defer { previous = signature }
        guard let previous, previous.samples.count == signature.samples.count else {
            return true
        }
        guard !signature.samples.isEmpty else { return false }

        let changed = zip(previous.samples, signature.samples).reduce(into: 0) { count, pair in
            let difference = abs(Int(pair.0) - Int(pair.1))
            if difference > sampleDifferenceThreshold {
                count += 1
            }
        }
        return Double(changed) / Double(signature.samples.count) >= changedSampleFraction
    }
}
