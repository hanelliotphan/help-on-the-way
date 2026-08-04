import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Request draft")
@MainActor
struct RequestDraftTests {

    private let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 6, day: 15, hour: 9, minute: 0
    ))!

    private func draft(_ category: HelpCategory = .handyman, instant: Bool = true) -> RequestDraft {
        RequestDraft(category: category, address: MockData.addresses[0], wantsInstant: instant, now: now)
    }

    // MARK: Defaults

    @Test("A new draft opens on the category's minimum")
    func defaultsToMinimum() {
        #expect(draft(.cleaning).minutes == 120)
        #expect(draft(.handyman).minutes == 60)
    }

    @Test("An untitled draft still books under a sensible name")
    func titleFallsBack() {
        let draft = draft(.assembly)
        #expect(draft.resolvedTitle == HelpCategory.assembly.defaultJobTitle)
        draft.title = "   "
        #expect(draft.resolvedTitle == HelpCategory.assembly.defaultJobTitle)
        draft.title = "Build the wardrobe"
        #expect(draft.resolvedTitle == "Build the wardrobe")
    }

    @Test("A scheduled-only category can't open in instant mode")
    func eventHelpCannotBeInstant() {
        #expect(draft(.eventHelp, instant: true).wantsInstant == false)
    }

    // MARK: Switching category

    @Test("Changing category resets the duration to that category's block")
    func categoryChangeResetsDuration() {
        let draft = draft(.handyman)
        draft.setMinutes(90, now: now)
        draft.select(category: .cleaning, now: now)
        #expect(draft.minutes == 120)
    }

    @Test("Changing category drops a helper who doesn't do the new work")
    func categoryChangeClearsIncompatibleHelper() {
        let draft = draft(.assembly)
        draft.chosenHelper = MockData.helper(MockData.fixedID(3))     // Yuki: assembly
        draft.select(category: .petCare, now: now)
        #expect(draft.chosenHelper == nil)
    }

    @Test("A helper who does both is kept")
    func categoryChangeKeepsCompatibleHelper() {
        let draft = draft(.assembly)
        draft.chosenHelper = MockData.helper(MockData.fixedID(3))     // Yuki: assembly + moving
        draft.select(category: .moving, now: now)
        #expect(draft.chosenHelper?.id == MockData.fixedID(3))
    }

    @Test("Switching to a scheduled-only category leaves instant mode")
    func categoryChangeForcesScheduled() {
        let draft = draft(.cleaning, instant: true)
        #expect(draft.wantsInstant)
        draft.select(category: .eventHelp, now: now)
        #expect(draft.wantsInstant == false)
    }

    @Test("Selecting the category you're already on changes nothing")
    func reselectingIsANoop() {
        let draft = draft(.handyman)
        draft.setMinutes(180, now: now)
        draft.title = "Keep me"
        draft.select(category: .handyman, now: now)
        #expect(draft.minutes == 180)
        #expect(draft.title == "Keep me")
    }

    // MARK: Duration and the slot

    @Test("The quote respects the category minimum even when the picker doesn't")
    func billableMinutesBump() {
        let draft = draft(.cleaning)
        draft.setMinutes(30, now: now)
        #expect(draft.minutes == 30)
        #expect(draft.billableMinutes == 120)
        #expect(draft.hasMinimumBump)
    }

    @Test("Stretching a job slides the slot to one that still fits")
    func longerJobSlidesTheSlot() {
        let draft = draft(.handyman, instant: false)
        let calendar = Calendar.current
        let lateStart = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        draft.scheduledStart = lateStart
        #expect(draft.schedulingIssue(now: now) == nil)

        draft.setMinutes(300, now: now)
        // 8pm plus five hours runs past closing, so the draft must have moved.
        #expect(draft.scheduledStart != lateStart)
        #expect(draft.schedulingIssue(now: now) == nil)
    }

    @Test("Switching to Later always lands on a bookable slot")
    func switchingToLaterPicksAValidSlot() {
        let draft = draft(.cleaning, instant: true)
        draft.setInstant(false, now: now)
        #expect(draft.wantsInstant == false)
        #expect(draft.schedulingIssue(now: now) == nil)
    }

    @Test("Instant mode has no scheduling to complain about")
    func instantHasNoSchedulingIssue() {
        let draft = draft(.handyman, instant: true)
        draft.scheduledStart = now.addingTimeInterval(-99_999)
        #expect(draft.schedulingIssue(now: now) == nil)
    }

    @Test("A scheduled-only category refuses to go back to instant")
    func setInstantIsRefusedForEventHelp() {
        let draft = draft(.eventHelp, instant: false)
        draft.setInstant(true, now: now)
        #expect(draft.wantsInstant == false)
    }

    // MARK: Rate and quote

    @Test("Picking a helper prices the job at their rate")
    func chosenHelperSetsTheRate() {
        let draft = draft(.assembly)
        #expect(draft.hourlyRate == HelpCategory.assembly.defaultHourlyRate)
        draft.chosenHelper = MockData.helper(MockData.fixedID(3))
        #expect(draft.hourlyRate == MockData.helper(MockData.fixedID(3))?.hourlyRate)
    }

    @Test("The draft's quote matches pricing it by hand")
    func quoteMatchesPricing() {
        let draft = draft(.cleaning, instant: true)
        let demand = DemandIndex(openRequests: 12, availableHelpers: 8)
        let expected = Pricing.quote(
            category: .cleaning, requestedMinutes: draft.minutes, hourlyRate: draft.hourlyRate,
            timing: .now, demand: demand, promo: nil, now: now
        )
        #expect(draft.quote(demand: demand, now: now) == expected)
    }

    @Test("Booking later costs less than the same job right now")
    func laterIsCheaperThanNow() {
        let busy = DemandIndex(openRequests: 12, availableHelpers: 8)
        let instant = draft(.cleaning, instant: true).quote(demand: busy, now: now)

        let later = draft(.cleaning, instant: false)
        later.scheduledStart = now.addingTimeInterval(48 * 3600)
        #expect(later.quote(demand: busy, now: now).total < instant.total)
    }

    // MARK: Promos

    @Test("A good code applies and normalises itself")
    func promoApplies() {
        let draft = draft()
        draft.promoText = " first20 "
        draft.applyPromo()
        #expect(draft.appliedPromo?.code == "FIRST20")
        #expect(draft.promoText == "FIRST20")
        #expect(draft.promoError == nil)
    }

    @Test("A bad code explains itself and applies nothing")
    func promoRejected() {
        let draft = draft()
        draft.promoText = "FREESTUFF"
        draft.applyPromo()
        #expect(draft.appliedPromo == nil)
        #expect(draft.promoError != nil)
    }

    @Test("Clearing the field clears the discount")
    func promoCleared() {
        let draft = draft()
        draft.promoText = "FIRST20"
        draft.applyPromo()
        draft.clearPromo()
        #expect(draft.appliedPromo == nil)
        #expect(draft.promoText.isEmpty)
        #expect(draft.promoError == nil)
    }

    @Test("An empty field is not an error")
    func emptyPromoIsSilent() {
        let draft = draft()
        draft.promoText = ""
        draft.applyPromo()
        #expect(draft.appliedPromo == nil)
        #expect(draft.promoError == nil)
    }

    @Test("An applied promo shows up in the quote")
    func promoReachesTheQuote() {
        let draft = draft(.cleaning, instant: false)
        let before = draft.quote(demand: .calm, now: now).total
        draft.promoText = "WEEKEND10"
        draft.applyPromo()
        let after = draft.quote(demand: .calm, now: now)
        #expect(after.promoCode == "WEEKEND10")
        #expect(after.total < before)
    }

    // MARK: Step machine

    @Test("Steps walk forwards and backwards without falling off the ends")
    func stepMachine() {
        let draft = draft()
        #expect(draft.step == .category)
        draft.retreat()
        #expect(draft.step == .category)

        for _ in RequestDraft.Step.allCases { draft.advance() }
        #expect(draft.step == .review)
        #expect(draft.isLastStep)
        draft.advance()
        #expect(draft.step == .review)
    }

    @Test("The location step won't advance without an address")
    func locationStepNeedsAnAddress() {
        let draft = RequestDraft(category: .handyman, address: nil, wantsInstant: true, startingAt: .location, now: now)
        #expect(draft.canAdvance(now: now) == false)
        draft.address = MockData.addresses[0]
        #expect(draft.canAdvance(now: now))
    }

    @Test("The timing step won't advance on an impossible slot")
    func timingStepNeedsAValidSlot() {
        let draft = RequestDraft(category: .handyman, address: MockData.addresses[0], wantsInstant: false, startingAt: .timing, now: now)
        #expect(draft.canAdvance(now: now))
        draft.scheduledStart = now.addingTimeInterval(10 * 60)   // inside the notice window
        #expect(draft.canAdvance(now: now) == false)
    }

    @Test("Every step has something to put on screen")
    func stepsAreLabelled() {
        for step in RequestDraft.Step.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.shortTitle.isEmpty)
        }
    }
}

@Suite("Persistence")
struct PersistenceTests {

    @Test("A snapshot survives a round trip through JSON")
    func snapshotRoundTrips() throws {
        let snapshot = StoreSnapshot(
            hasOnboarded: true,
            profile: MockData.profile,
            addresses: MockData.addresses,
            paymentMethods: MockData.paymentMethods,
            jobs: MockData.seedJobs(),
            timeScale: 2
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(StoreSnapshot.self, from: try encoder.encode(snapshot))
        #expect(restored.hasOnboarded)
        #expect(restored.jobs.count == snapshot.jobs.count)
        #expect(restored.jobs.first?.id == snapshot.jobs.first?.id)
        #expect(restored.profile.favoriteHelperIDs == snapshot.profile.favoriteHelperIDs)
        #expect(restored.addresses == snapshot.addresses)
        #expect(restored.timeScale == 2)
    }

    @Test("Both timings encode and come back intact")
    func timingRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let values: [JobTiming] = [.now, .scheduled(start: start)]
        for value in values {
            let restored = try decoder.decode(JobTiming.self, from: try encoder.encode(value))
            #expect(restored == value)
        }
    }

    @Test("An in-flight job keeps its dispatch plan across a save")
    func dispatchPlanRoundTrips() throws {
        var job = MockData.seedJobs()[0]
        job.dispatch = Dispatch.plan(
            helper: MockData.helpers[0], destination: MockData.homePoint,
            jobMinutes: 90, acceptedAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeScale: 2, seed: MockData.fixedID(1)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Job.self, from: try encoder.encode(job))
        #expect(restored.dispatch == job.dispatch)
        #expect(restored.dispatch?.route.count == job.dispatch?.route.count)
    }
}
