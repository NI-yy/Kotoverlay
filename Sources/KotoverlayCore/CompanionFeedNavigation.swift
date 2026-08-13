import Foundation

public enum CompanionFeedNavigation {
    public static func isAtLatest(
        visibleIdentity: MessageIdentity?,
        latestIdentity: MessageIdentity?
    ) -> Bool {
        guard let latestIdentity else { return true }
        return visibleIdentity == latestIdentity
    }

    public static func startsNewVisibleContext(
        previous: [MessageIdentity],
        current: [MessageIdentity]
    ) -> Bool {
        guard !previous.isEmpty, !current.isEmpty else { return false }
        return Set(previous).isDisjoint(with: Set(current))
    }

    public static func distanceFromBottom(
        documentHeight: Double,
        viewportHeight: Double,
        verticalOffset: Double
    ) -> Double {
        max(0, documentHeight - viewportHeight - verticalOffset)
    }

    public static func verticalOffset(
        preservingDistanceFromBottom distance: Double,
        documentHeight: Double,
        viewportHeight: Double
    ) -> Double {
        max(0, documentHeight - viewportHeight - max(0, distance))
    }
}
