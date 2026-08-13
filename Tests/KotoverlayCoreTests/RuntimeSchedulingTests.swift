import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Runtime scheduling")
struct RuntimeSchedulingTests {
    @Test("Unchanged frames enter idle cadence and a change restores active cadence")
    func adaptiveScanCadence() {
        var schedule = AdaptiveScanSchedule(
            activeInterval: .milliseconds(500),
            idleInterval: .seconds(1),
            stableFramesBeforeIdle: 3
        )

        #expect(schedule.interval(afterMeaningfulChange: false) == .milliseconds(500))
        #expect(schedule.interval(afterMeaningfulChange: false) == .milliseconds(500))
        #expect(schedule.interval(afterMeaningfulChange: false) == .seconds(1))
        #expect(schedule.interval(afterMeaningfulChange: false) == .seconds(1))
        #expect(schedule.interval(afterMeaningfulChange: true) == .milliseconds(500))
        #expect(schedule.consecutiveStableFrames == 0)
    }

    @Test("Retry delay grows to a cap and reset restores the initial delay")
    func cappedRetryBackoff() {
        var backoff = RetryBackoff(
            initialDelayMilliseconds: 500,
            maximumDelayMilliseconds: 2_000
        )

        #expect(backoff.nextDelay() == .milliseconds(500))
        #expect(backoff.nextDelay() == .seconds(1))
        #expect(backoff.nextDelay() == .seconds(2))
        #expect(backoff.nextDelay() == .seconds(2))
        backoff.reset()
        #expect(backoff.nextDelay() == .milliseconds(500))
    }
}
