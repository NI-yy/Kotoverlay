import Foundation

public struct AdaptiveScanSchedule: Equatable, Sendable {
    public let activeInterval: Duration
    public let idleInterval: Duration
    public let stableFramesBeforeIdle: Int
    public private(set) var consecutiveStableFrames = 0

    public init(
        activeInterval: Duration = .milliseconds(500),
        idleInterval: Duration = .seconds(1),
        stableFramesBeforeIdle: Int = 4
    ) {
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval
        self.stableFramesBeforeIdle = max(1, stableFramesBeforeIdle)
    }

    public mutating func interval(afterMeaningfulChange changed: Bool) -> Duration {
        if changed {
            consecutiveStableFrames = 0
            return activeInterval
        }
        consecutiveStableFrames += 1
        return consecutiveStableFrames >= stableFramesBeforeIdle
            ? idleInterval
            : activeInterval
    }

    public mutating func reset() {
        consecutiveStableFrames = 0
    }
}

public struct RetryBackoff: Equatable, Sendable {
    public let initialDelayMilliseconds: Int
    public let maximumDelayMilliseconds: Int
    public private(set) var attempt = 0

    public init(
        initialDelayMilliseconds: Int = 1_000,
        maximumDelayMilliseconds: Int = 5_000
    ) {
        let initial = max(1, initialDelayMilliseconds)
        self.initialDelayMilliseconds = initial
        self.maximumDelayMilliseconds = max(initial, maximumDelayMilliseconds)
    }

    public mutating func nextDelay() -> Duration {
        let exponent = min(attempt, 30)
        let multiplier = 1 << exponent
        let multiplied = initialDelayMilliseconds.multipliedReportingOverflow(by: multiplier)
        let delay = multiplied.overflow
            ? maximumDelayMilliseconds
            : min(maximumDelayMilliseconds, multiplied.partialValue)
        attempt = min(attempt + 1, 30)
        return .milliseconds(delay)
    }

    public mutating func reset() {
        attempt = 0
    }
}
