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

    @Test("Progressive insertions preserve distance from the bottom")
    func preservesBottomDistance() {
        let distance = CompanionFeedNavigation.distanceFromBottom(
            documentHeight: 1_000,
            viewportHeight: 400,
            verticalOffset: 450
        )
        #expect(distance == 150)
        #expect(CompanionFeedNavigation.verticalOffset(
            preservingDistanceFromBottom: distance,
            documentHeight: 1_300,
            viewportHeight: 400
        ) == 750)
        #expect(CompanionFeedNavigation.verticalOffset(
            preservingDistanceFromBottom: 0,
            documentHeight: 1_300,
            viewportHeight: 400
        ) == 900)
    }
}
