import CoreGraphics
import Foundation

public enum InPlaceOverlayLayout {
    /// Reprojects an OCR rectangle from the window frame used for recognition
    /// into the Discord window's current ScreenCaptureKit coordinate space.
    public static func reproject(
        _ sourceRect: CGRect,
        from sourceWindowFrame: CGRect,
        to currentWindowFrame: CGRect
    ) -> CGRect? {
        guard sourceWindowFrame.width > 0,
              sourceWindowFrame.height > 0,
              currentWindowFrame.width > 0,
              currentWindowFrame.height > 0 else {
            return nil
        }

        let relativeX = (sourceRect.minX - sourceWindowFrame.minX) / sourceWindowFrame.width
        let relativeY = (sourceRect.minY - sourceWindowFrame.minY) / sourceWindowFrame.height
        let widthScale = currentWindowFrame.width / sourceWindowFrame.width
        let heightScale = currentWindowFrame.height / sourceWindowFrame.height
        return CGRect(
            x: currentWindowFrame.minX + relativeX * currentWindowFrame.width,
            y: currentWindowFrame.minY + relativeY * currentWindowFrame.height,
            width: sourceRect.width * widthScale,
            height: sourceRect.height * heightScale
        )
    }

    public static func isVisible(
        _ frame: CGRect,
        inside windowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> Bool {
        guard frame.width > 0, frame.height > 0,
              intersectsWithPositiveArea(frame, windowFrame) else {
            return false
        }
        return screenFrames.contains { intersectsWithPositiveArea(frame, $0) }
    }

    /// Places a measured, potentially multi-line translation on its source
    /// anchor while keeping the complete panel inside the message content area.
    public static func overlayFrame(
        anchoredTo anchor: CGRect,
        desiredSize: CGSize,
        inside contentBounds: CGRect,
        horizontalMargin: CGFloat = 10
    ) -> CGRect? {
        guard anchor.width > 0, anchor.height > 0,
              desiredSize.width > 0, desiredSize.height > 0,
              contentBounds.width > 0, contentBounds.height > 0 else {
            return nil
        }

        let availableWidth = contentBounds.maxX - max(anchor.minX, contentBounds.minX)
            - horizontalMargin
        guard availableWidth >= 100 else { return nil }

        let width = min(desiredSize.width, availableWidth)
        let height = min(desiredSize.height, contentBounds.height)
        let x = max(
            contentBounds.minX,
            min(anchor.minX, contentBounds.maxX - horizontalMargin - width)
        )
        let top = min(anchor.maxY + 1, contentBounds.maxY)
        let y = max(contentBounds.minY, top - height)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        guard contentBounds.contains(frame) else { return nil }
        return frame
    }

    /// Resolves small OCR-box overlaps without allowing an overlay to drift far
    /// enough that it appears attached to a different Discord message.
    public static func resolveCollisions(
        _ frames: [CGRect],
        inside bounds: CGRect,
        spacing: CGFloat = 2,
        maximumDisplacement: CGFloat = 12
    ) -> [CGRect?] {
        var resolved = Array<CGRect?>(repeating: nil, count: frames.count)
        var placed: [CGRect] = []
        let visualOrder = frames.indices.sorted {
            frames[$0].maxY > frames[$1].maxY
        }

        for index in visualOrder {
            let original = frames[index]
            var candidate = original
            while let collision = placed.first(where: { intersectsWithPositiveArea(candidate, $0) }) {
                candidate.origin.y = collision.minY - spacing - candidate.height
            }
            let displacement = original.minY - candidate.minY
            guard displacement <= maximumDisplacement,
                  bounds.contains(candidate) else {
                continue
            }
            resolved[index] = candidate
            placed.append(candidate)
        }
        return resolved
    }

    private static func intersectsWithPositiveArea(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        return !intersection.isNull
            && !intersection.isInfinite
            && intersection.width > 0
            && intersection.height > 0
    }
}
