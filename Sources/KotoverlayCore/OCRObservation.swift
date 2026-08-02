import CoreGraphics
import Foundation

public struct OCRObservation: Equatable, Sendable {
    public let identifier: String
    public let text: String
    public let confidence: Float
    public let normalizedRect: CGRect
    public let screenRect: CGRect

    public init(
        text: String,
        confidence: Float,
        normalizedRect: CGRect,
        screenRect: CGRect
    ) {
        self.text = text
        self.confidence = confidence
        self.normalizedRect = normalizedRect
        self.screenRect = screenRect
        identifier = StableIdentifier.make(
            role: "VisionText",
            text: text,
            frame: screenRect,
            path: []
        )
    }
}

public enum VisionCoordinateConverter {
    /// Converts a Vision observation relative to a request region back into
    /// full-image normalized coordinates.
    public static func imageNormalizedRect(
        for observationRect: CGRect,
        in regionOfInterest: CGRect
    ) -> CGRect {
        CGRect(
            x: regionOfInterest.minX + observationRect.minX * regionOfInterest.width,
            y: regionOfInterest.minY + observationRect.minY * regionOfInterest.height,
            width: observationRect.width * regionOfInterest.width,
            height: observationRect.height * regionOfInterest.height
        )
    }

    /// Vision uses a normalized bottom-left origin. ScreenCaptureKit window
    /// frames use a screen-space top-left origin.
    public static func screenRect(
        for normalizedRect: CGRect,
        in windowFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: windowFrame.minX + normalizedRect.minX * windowFrame.width,
            y: windowFrame.minY + (1 - normalizedRect.maxY) * windowFrame.height,
            width: normalizedRect.width * windowFrame.width,
            height: normalizedRect.height * windowFrame.height
        )
    }
}
