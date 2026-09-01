import CoreGraphics
import Foundation

public struct DiscordObservationFilterResult: Equatable, Sendable {
    public let observations: [OCRObservation]
    public let contentFrame: CGRect

    public init(observations: [OCRObservation], contentFrame: CGRect) {
        self.observations = observations
        self.contentFrame = contentFrame
    }
}

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
        analyze(observations, in: windowFrame).observations
    }

    public func analyze(
        _ observations: [OCRObservation],
        in windowFrame: CGRect
    ) -> DiscordObservationFilterResult {
        guard windowFrame.width > 0 else {
            return DiscordObservationFilterResult(
                observations: observations,
                contentFrame: windowFrame
            )
        }
        let sidebarStart = windowFrame.minX + windowFrame.width * sidebarStartFraction
        let sidebarCandidates = observations.filter {
            $0.screenRect.minX >= sidebarStart
                && $0.text.count <= maximumSidebarTextLength
        }
        guard sidebarCandidates.count >= minimumSidebarCandidates else {
            return DiscordObservationFilterResult(
                observations: observations,
                contentFrame: windowFrame
            )
        }
        return DiscordObservationFilterResult(
            observations: observations.filter { $0.screenRect.minX < sidebarStart },
            contentFrame: CGRect(
                x: windowFrame.minX,
                y: windowFrame.minY,
                width: sidebarStart - windowFrame.minX,
                height: windowFrame.height
            )
        )
    }
}
