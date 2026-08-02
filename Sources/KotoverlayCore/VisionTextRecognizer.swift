import CoreGraphics
import Foundation
@preconcurrency import Vision

public struct VisionRecognitionOptions: Sendable {
    public enum Level: Sendable {
        case fast
        case accurate
    }

    public var level: Level
    public var minimumConfidence: Float
    public var recognitionLanguages: [String]
    public var usesLanguageCorrection: Bool
    public var regionOfInterest: CGRect

    public init(
        level: Level = .accurate,
        minimumConfidence: Float = 0.35,
        recognitionLanguages: [String] = ["en-US", "ja-JP"],
        usesLanguageCorrection: Bool = true,
        regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) {
        self.level = level
        self.minimumConfidence = min(1, max(0, minimumConfidence))
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
        let clipped = regionOfInterest.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        self.regionOfInterest = clipped.isNull || clipped.isEmpty
            ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : clipped
    }
}

public struct VisionTextRecognizer: Sendable {
    public init() {}

    public func recognize(
        image: CGImage,
        windowFrame: CGRect,
        options: VisionRecognitionOptions = .init()
    ) throws -> [OCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = options.level == .accurate ? .accurate : .fast
        request.recognitionLanguages = options.recognitionLanguages
        request.usesLanguageCorrection = options.usesLanguageCorrection
        request.regionOfInterest = options.regionOfInterest

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= options.minimumConfidence else {
                return nil
            }
            let normalizedRect = VisionCoordinateConverter.imageNormalizedRect(
                for: observation.boundingBox,
                in: options.regionOfInterest
            )
            return OCRObservation(
                text: candidate.string,
                confidence: candidate.confidence,
                normalizedRect: normalizedRect,
                screenRect: VisionCoordinateConverter.screenRect(
                    for: normalizedRect,
                    in: windowFrame
                )
            )
        }
        .sorted {
            if abs($0.screenRect.minY - $1.screenRect.minY) > 4 {
                return $0.screenRect.minY < $1.screenRect.minY
            }
            return $0.screenRect.minX < $1.screenRect.minX
        }
    }
}

public enum DiscordOCRRegion {
    /// Excludes the server/channel sidebar, toolbar, and message composer.
    /// Vision regions use a normalized bottom-left origin.
    public static let messageContent = CGRect(
        x: 0.20,
        y: 0.08,
        width: 0.79,
        height: 0.86
    )
}
