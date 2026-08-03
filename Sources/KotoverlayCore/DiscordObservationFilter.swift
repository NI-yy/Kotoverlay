import CoreGraphics
import Foundation

public struct DiscordObservationFilter: Sendable {
    public var sidebarStartFraction: CGFloat
    public var minimumSidebarCandidates: Int
    public var maximumSidebarTextLength: Int

    public init(
        sidebarStartFraction: CGFloat = 0.84,
        minimumSidebarCandidates: Int = 3,
        maximumSidebarTextLength: Int = 48
    ) {
        self.sidebarStartFraction = sidebarStartFraction
        self.minimumSidebarCandidates = minimumSidebarCandidates
        self.maximumSidebarTextLength = maximumSidebarTextLength
    }

    public func filter(
        _ observations: [OCRObservation],
        in windowFrame: CGRect
    ) -> [OCRObservation] {
        guard windowFrame.width > 0 else { return observations }
        let sidebarStart = windowFrame.minX + windowFrame.width * sidebarStartFraction
        let sidebarCandidates = observations.filter {
            $0.screenRect.minX >= sidebarStart
                && $0.text.count <= maximumSidebarTextLength
        }
        guard sidebarCandidates.count >= minimumSidebarCandidates else {
            return observations
        }
        return observations.filter { $0.screenRect.minX < sidebarStart }
    }
}
