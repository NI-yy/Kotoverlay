import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Vision text recognition")
struct VisionTextRecognizerTests {
    @Test("Recognizes synthetic English text without screen capture permission")
    func recognizesSyntheticText() throws {
        let image = try syntheticImage(text: "HELLO METAL")
        let observations = try VisionTextRecognizer().recognize(
            image: image,
            windowFrame: CGRect(x: 10, y: 20, width: 1_000, height: 260),
            options: VisionRecognitionOptions(
                level: .accurate,
                minimumConfidence: 0.2,
                recognitionLanguages: ["en-US"]
            )
        )
        let recognized = observations.map(\.text).joined(separator: " ").uppercased()

        #expect(recognized.contains("HELLO"))
        #expect(recognized.contains("METAL"))
        #expect(observations.allSatisfy { !$0.screenRect.isEmpty })
    }

    private func syntheticImage(text: String) throws -> CGImage {
        let width = 1_000
        let height = 260
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SyntheticImageError.contextCreationFailed
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        context.textPosition = CGPoint(x: 60, y: 80)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else {
            throw SyntheticImageError.imageCreationFailed
        }
        return image
    }

    private enum SyntheticImageError: Error {
        case contextCreationFailed
        case imageCreationFailed
    }
}
