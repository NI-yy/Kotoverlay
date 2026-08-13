import Testing
@testable import KotoverlayCore

@Suite("Companion feed navigation")
struct CompanionFeedNavigationTests {
    private let first = MessageIdentity(rawValue: "first")
    private let second = MessageIdentity(rawValue: "second")
    private let third = MessageIdentity(rawValue: "third")

    @Test("Only the latest visible item keeps automatic following active")
    func detectsLatestPosition() {
        #expect(CompanionFeedNavigation.isAtLatest(
            visibleIdentity: second,
            latestIdentity: second
        ))
        #expect(!CompanionFeedNavigation.isAtLatest(
            visibleIdentity: first,
            latestIdentity: second
        ))
        #expect(CompanionFeedNavigation.isAtLatest(
            visibleIdentity: nil,
            latestIdentity: nil
        ))
    }

    @Test("A disjoint result set resets navigation for a channel or viewport change")
    func detectsNewContext() {
        #expect(CompanionFeedNavigation.startsNewVisibleContext(
            previous: [first, second],
            current: [third]
        ))
        #expect(!CompanionFeedNavigation.startsNewVisibleContext(
            previous: [first, second],
            current: [second, third]
        ))
        #expect(!CompanionFeedNavigation.startsNewVisibleContext(
            previous: [],
            current: [third]
        ))
    }

    @Test("A progressively added translation preserves the current reading position")
    func preservesPositionForProgressiveResults() {
        #expect(!CompanionFeedNavigation.shouldKeepFollowingAfterLatestChanges(
            previousLatest: second,
            currentLatest: third,
            visibleIdentity: second
        ))
        #expect(CompanionFeedNavigation.shouldKeepFollowingAfterLatestChanges(
            previousLatest: second,
            currentLatest: third,
            visibleIdentity: third
        ))
        #expect(CompanionFeedNavigation.shouldKeepFollowingAfterLatestChanges(
            previousLatest: nil,
            currentLatest: first,
            visibleIdentity: nil
        ))
    }
}
