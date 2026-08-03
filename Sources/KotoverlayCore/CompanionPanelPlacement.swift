import CoreGraphics
import Foundation

public enum ScreenCoordinateConverter {
    /// Converts ScreenCaptureKit's top-left global coordinates to AppKit's
    /// bottom-left global coordinates. AppKit's main-screen top edge is the
    /// shared vertical reference for all displays.
    public static func appKitRect(
        from screenCaptureRect: CGRect,
        mainScreenMaxY: CGFloat
    ) -> CGRect {
        CGRect(
            x: screenCaptureRect.minX,
            y: mainScreenMaxY - screenCaptureRect.maxY,
            width: screenCaptureRect.width,
            height: screenCaptureRect.height
        )
    }
}

public enum CompanionPanelPlacement {
    public static func frame(
        beside discordFrame: CGRect,
        panelSize: CGSize,
        visibleScreens: [CGRect],
        gap: CGFloat = 8
    ) -> CGRect {
        guard let screen = bestScreen(for: discordFrame, visibleScreens: visibleScreens) else {
            return CGRect(origin: discordFrame.origin, size: panelSize)
        }
        let width = min(panelSize.width, screen.width)
        let height = min(panelSize.height, screen.height)
        let rightX = discordFrame.maxX + gap
        let leftX = discordFrame.minX - gap - width
        let x: CGFloat
        if rightX + width <= screen.maxX {
            x = rightX
        } else if leftX >= screen.minX {
            x = leftX
        } else {
            x = max(screen.minX, min(rightX, screen.maxX - width))
        }
        let y = max(screen.minY, min(discordFrame.maxY - height, screen.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func bestScreen(
        for frame: CGRect,
        visibleScreens: [CGRect]
    ) -> CGRect? {
        visibleScreens.max {
            intersectionArea($0, frame) < intersectionArea($1, frame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isInfinite else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
