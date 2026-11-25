import Foundation
import Testing
@testable import PersonalRadioCore

struct DemoScheduleTests {
    @Test func normalBoundaryQueuesNewsBeforeRoadworksOnlyOnce() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .standard,
                                        newsEnabled: true, worksEnabled: true)

        #expect(first.time == time(60))
        #expect(first.decisions == [.newsReady, .roadworksReady])
        #expect(first.decisions.map(\.message) == [
            "Fresh bulletin queued at song boundary",
            "Fresh roadworks report queued"
        ])

        let second = schedule.afterTrack(1, at: first.time, scenario: .standard,
                                         newsEnabled: true, worksEnabled: true)
        #expect(second.time == time(300))
        #expect(second.decisions.isEmpty)
    }

    @Test func lateNewsWaitsWithoutBlockingRoadworksAndBecomesReadyAtTwoMinutes() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .lateNews,
                                        newsEnabled: true, worksEnabled: true)

        #expect(first.decisions == [.newsWaiting, .roadworksReady])
        #expect(first.decisions.first?.message == "Bulletin still loading. Music continues.")
        let stillWaiting = schedule.afterTrack(0, at: time(119.999), scenario: .lateNews,
                                               newsEnabled: true, worksEnabled: true)
        #expect(stillWaiting.decisions.isEmpty)
        let available = schedule.afterTrack(0, at: time(120), scenario: .lateNews,
                                            newsEnabled: true, worksEnabled: true)
        #expect(available.decisions == [.newsReady])
        let next = schedule.afterTrack(1, at: available.time, scenario: .lateNews,
                                       newsEnabled: true, worksEnabled: true)
        #expect(next.decisions.isEmpty)
    }

    @Test func expiredScenarioMovesClockPastBothDeadlines() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .expired,
                                        newsEnabled: true, worksEnabled: true)

        #expect(first.time == time(16 * 60))
        #expect(first.decisions == [.newsExpired, .roadworksExpired])
        #expect(first.decisions.map(\.message) == ["Hourly bulletin expired", "Travel report expired"])
        let second = schedule.afterTrack(1, at: first.time, scenario: .expired,
                                         newsEnabled: true, worksEnabled: true)
        #expect(second.decisions.isEmpty)
    }

    @Test func newsIsFreshJustBeforeFifteenMinutesAndExpiresAtTheDeadline() {
        var before = DemoSchedule()
        let freshTime = time(899.999)
        let fresh = before.afterTrack(0, at: freshTime, scenario: .standard,
                                      newsEnabled: true, worksEnabled: false)
        #expect(fresh.time == freshTime)
        #expect(fresh.decisions == [.newsReady])

        var exactly = DemoSchedule()
        let expired = exactly.afterTrack(0, at: time(900), scenario: .standard,
                                         newsEnabled: true, worksEnabled: false)
        #expect(expired.decisions == [.newsExpired])
    }

    @Test func roadworksExpireFiveMinutesAfterTheUpdate() {
        var before = DemoSchedule()
        let fresh = before.afterTrack(0, at: time(329.999), scenario: .standard,
                                      newsEnabled: false, worksEnabled: true)
        #expect(fresh.decisions == [.roadworksReady])

        var exactly = DemoSchedule()
        let expired = exactly.afterTrack(0, at: time(330), scenario: .standard,
                                         newsEnabled: false, worksEnabled: true)
        #expect(expired.decisions == [.roadworksExpired])
    }

    @Test func reopenedRoadSuppressesTheClosureWithoutSuppressingNews() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .reopened,
                                        newsEnabled: true, worksEnabled: true)

        #expect(first.decisions == [.newsReady, .roadReopened])
        #expect(first.decisions.last?.message == "Road reopened. Previous closure suppressed.")
        let second = schedule.afterTrack(1, at: first.time, scenario: .reopened,
                                         newsEnabled: true, worksEnabled: true)
        #expect(second.decisions.isEmpty)
    }

    @Test func disabledSourcesRemainEligibleWhenEnabledBeforeExpiry() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .standard,
                                        newsEnabled: false, worksEnabled: false)
        let second = schedule.afterTrack(1, at: first.time, scenario: .standard,
                                         newsEnabled: true, worksEnabled: true)

        #expect(first.decisions.isEmpty)
        #expect(second.decisions == [.newsReady, .roadworksReady])
    }

    @Test func newSessionCanQueueReportsAgain() {
        var schedule = DemoSchedule()
        let first = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .standard,
                                        newsEnabled: true, worksEnabled: true)
        #expect(first.decisions == [.newsReady, .roadworksReady])
        schedule = DemoSchedule()

        let restarted = schedule.afterTrack(0, at: DemoSchedule.startTime, scenario: .standard,
                                            newsEnabled: true, worksEnabled: true)
        #expect(restarted.time == first.time)
        #expect(restarted.decisions == first.decisions)
    }

    private func time(_ secondsAfterHour: TimeInterval) -> Date {
        DemoSchedule.bulletinHour.addingTimeInterval(secondsAfterHour)
    }
}
