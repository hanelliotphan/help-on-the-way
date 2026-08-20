import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Custom category")
struct CustomCategoryTests {

    @Test("Custom is a category like any other, with everything filled in")
    func customIsComplete() {
        let custom = HelpCategory.custom
        #expect(custom.rawValue == "custom")
        #expect(!custom.title.isEmpty)
        #expect(!custom.tagline.isEmpty)
        #expect(!custom.symbol.isEmpty)
        #expect(!custom.defaultJobTitle.isEmpty)
        #expect(!custom.checklist.isEmpty)
        // Custom deliberately has no going rate to quote.
        #expect(custom.standardHourlyRate == nil)
        #expect(custom.needsNamedRate)
        #expect(custom.minimumMinutes == 60)
        #expect(custom.supportsInstant)
    }

    @Test("Custom sits at the end of the catalogue")
    func customIsLast() {
        // The category grid is ordered by allCases; "something else" belongs
        // after the things that are actually named.
        #expect(HelpCategory.allCases.last == .custom)
        // Deliberately not a count: the catalogue is meant to grow, and a magic
        // number here just breaks every time it does. What matters is that
        // "something else" stays at the end.
        #expect(HelpCategory.allCases.dropLast().allSatisfy { $0 != .custom })
    }

    @Test("Custom is not a listed skill, but everybody is eligible for it")
    func everyoneCanTakeCustom() {
        // Regression: Custom started out filtered like any other skill, which
        // meant nobody matched and every custom request died unmatched.
        for helper in MockData.helpers {
            #expect(!helper.skills.contains(.custom))
            #expect(helper.handles(.custom))
        }
        #expect(Matching.candidates(for: .custom, near: MockData.homePoint, in: MockData.helpers).count
                == MockData.helpers.filter { $0.basePoint.miles(to: MockData.homePoint) <= Matching.radiusMiles }.count)
    }

    @Test("A custom job still prices, even though it has no going rate")
    func customPrices() {
        let quote = Pricing.quote(
            category: .custom, requestedMinutes: 90, hourlyRate: .usd(40),
            timing: .scheduled(start: Date().addingTimeInterval(7200))
        )
        #expect(quote.minutes == 90)
        #expect(quote.labor == .usd(60))
        #expect(quote.total > quote.labor)
    }

    @Test("A suggested opening rate for Custom is the roster's average")
    func suggestedOpening() {
        let opening = Negotiation.suggestedOpening(for: .custom, in: MockData.helpers)
        let rates = MockData.helpers.map(\.hourlyRate)
        #expect(opening >= rates.min()!)
        #expect(opening <= rates.max()!)
        // Named categories just use their own rate.
        #expect(Negotiation.suggestedOpening(for: .handyman, in: MockData.helpers)
                == HelpCategory.handyman.standardHourlyRate)
    }
}

@Suite("Negotiation rules")
struct NegotiationRuleTests {

    @Test("An offer has to be a real number")
    func bounds() {
        #expect(Negotiation.issue(offering: .usd(5)) == .belowFloor(Negotiation.floor))
        #expect(Negotiation.issue(offering: .usd(900)) == .aboveCeiling(Negotiation.ceiling))
        #expect(Negotiation.issue(offering: .usd(50)) == nil)
        // The bounds themselves are allowed.
        #expect(Negotiation.issue(offering: Negotiation.floor) == nil)
        #expect(Negotiation.issue(offering: Negotiation.ceiling) == nil)
    }

    @Test("Re-offering the same rate isn't a counter")
    func unchangedIsRejected() {
        var negotiation = RateNegotiation(openingRate: .usd(50))
        negotiation.counter(.usd(60), byCustomer: false, helperID: MockData.fixedID(2))
        #expect(Negotiation.issue(offering: .usd(60), in: negotiation) == .unchanged)
        #expect(Negotiation.issue(offering: .usd(55), in: negotiation) == nil)
    }

    @Test("The haggling is not allowed to run forever")
    func roundsAreCapped() {
        var negotiation = RateNegotiation(openingRate: .usd(30))
        for round in 1..<Negotiation.maximumRounds {
            negotiation.counter(.usd(30 + round), byCustomer: round.isMultiple(of: 2))
        }
        #expect(negotiation.rounds == Negotiation.maximumRounds)
        #expect(Negotiation.issue(offering: .usd(99), in: negotiation)
                == .exhausted(rounds: Negotiation.maximumRounds))
    }

    @Test("Every issue explains itself")
    func issuesHaveMessages() {
        let issues: [Negotiation.Issue] = [
            .belowFloor(.usd(15)), .aboveCeiling(.usd(400)), .unchanged, .exhausted(rounds: 8),
        ]
        for issue in issues { #expect(!issue.message.isEmpty) }
    }

    @Test("The going rate comes from who actually does the work")
    func goingRate() {
        let band = Negotiation.goingRate(for: .cleaning, in: MockData.helpers)
        #expect(band != nil)
        let cleaners = MockData.helpers.filter { $0.handles(.cleaning) }.map(\.hourlyRate)
        #expect(band?.lowerBound == cleaners.min())
        #expect(band?.upperBound == cleaners.max())
        // Anybody can take a Custom job, so its band is the whole roster —
        // which is exactly the guidance a customer naming a rate wants.
        let custom = Negotiation.goingRate(for: .custom, in: MockData.helpers)
        #expect(custom?.lowerBound == MockData.helpers.map(\.hourlyRate).min())
        #expect(custom?.upperBound == MockData.helpers.map(\.hourlyRate).max())
        #expect(Negotiation.goingRate(for: .cleaning, in: []) == nil)
    }

    @Test("Rates round to whole dollars")
    func roundingToStep() {
        #expect(Negotiation.roundedToStep(Decimal(string: "52.4")!) == .usd(52))
        #expect(Negotiation.roundedToStep(Decimal(string: "52.5")!) == .usd(53))
        #expect(Negotiation.roundedToStep(.usd(52)) == .usd(52))
    }
}

@Suite("How a helper answers a rate")
struct NegotiationResponseTests {

    /// Terrence charges $64/hr.
    private let terrence = MockData.helpers[1]

    private func negotiation(_ rate: Decimal) -> RateNegotiation {
        RateNegotiation(openingRate: rate)
    }

    @Test("At or above their rate, they just take it")
    func acceptsAtOrAbove() {
        #expect(Negotiation.response(to: .usd(64), helper: terrence, negotiation: negotiation(.usd(64))) == .accept)
        #expect(Negotiation.response(to: .usd(80), helper: terrence, negotiation: negotiation(.usd(80))) == .accept)
    }

    @Test("A shade under their rate is still worth taking")
    func acceptsSlightlyUnder() {
        // 95% of 64 is 60.80 — a helper would rather work than argue over a dollar.
        #expect(Negotiation.response(to: .usd(61), helper: terrence, negotiation: negotiation(.usd(61))) == .accept)
    }

    @Test("A serious gap gets a counter, in the middle")
    func countersInTheMiddle() {
        let response = Negotiation.response(to: .usd(50), helper: terrence, negotiation: negotiation(.usd(50)))
        #expect(response == .counter(.usd(57)))   // midpoint of 50 and 64
    }

    @Test("A counter never lands below the offer or above their own rate")
    func counterIsBounded() {
        for offered in stride(from: 36, through: 63, by: 1).map({ Decimal($0) }) {
            let response = Negotiation.response(to: offered, helper: terrence, negotiation: negotiation(offered))
            if case .counter(let rate) = response {
                #expect(rate > offered, "counter \(rate) not above offer \(offered)")
                #expect(rate <= terrence.hourlyRate, "counter \(rate) above own rate")
            }
        }
    }

    @Test("An insulting offer is walked away from, not haggled")
    func walksAwayWhenFarApart() {
        // Below 55% of 64 is under 35.20.
        #expect(Negotiation.response(to: .usd(20), helper: terrence, negotiation: negotiation(.usd(20))) == .walkAway)
        #expect(Negotiation.response(to: .usd(30), helper: terrence, negotiation: negotiation(.usd(30))) == .walkAway)
    }

    @Test("With the rounds nearly gone, they settle rather than stall")
    func settlesWhenRoundsRunOut() {
        var late = negotiation(.usd(50))
        for round in 1..<(Negotiation.maximumRounds - 1) {
            late.counter(.usd(50 + round), byCustomer: round.isMultiple(of: 2))
        }
        #expect(Negotiation.response(to: .usd(50), helper: terrence, negotiation: late) == .accept)
    }

    @Test("The same offer always gets the same answer")
    func responseIsDeterministic() {
        let first = Negotiation.response(to: .usd(48), helper: terrence, negotiation: negotiation(.usd(48)))
        let second = Negotiation.response(to: .usd(48), helper: terrence, negotiation: negotiation(.usd(48)))
        #expect(first == second)
    }

    @Test("The counter comes with a reason a customer can read")
    func rationaleIsWritten() {
        #expect(!Negotiation.rationale(for: .usd(64), helper: terrence).isEmpty)
        #expect(Negotiation.rationale(for: .usd(57), helper: terrence).contains("64"))
    }
}

@Suite("Negotiation state")
struct NegotiationStateTests

{
    @Test("A fresh negotiation is the customer's opening offer, awaiting a helper")
    func opening() {
        let negotiation = RateNegotiation(openingRate: .usd(45))
        #expect(negotiation.rounds == 1)
        #expect(negotiation.opening.rate == .usd(45))
        #expect(negotiation.latest.rate == .usd(45))
        #expect(negotiation.opening.byCustomer)
        #expect(negotiation.awaitingHelper)
        #expect(!negotiation.awaitingCustomer)
        #expect(!negotiation.isSettled)
        #expect(negotiation.customerFacingRate == .usd(45))
        #expect(negotiation.gap == nil)
    }

    @Test("A helper's counter puts the ball back with the customer")
    func counterFlipsTurn() {
        var negotiation = RateNegotiation(openingRate: .usd(45))
        negotiation.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2))
        #expect(negotiation.awaitingCustomer)
        #expect(!negotiation.awaitingHelper)
        #expect(negotiation.latest.rate == .usd(58))
        #expect(negotiation.latest.helperID == MockData.fixedID(2))
        // The price doesn't move until the customer agrees to it.
        #expect(negotiation.customerFacingRate == .usd(45))
        #expect(negotiation.gap == .usd(13))
    }

    @Test("The customer's counter moves the price and the turn")
    func customerCounter() {
        var negotiation = RateNegotiation(openingRate: .usd(45))
        negotiation.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2))
        negotiation.counter(.usd(52), byCustomer: true)
        #expect(negotiation.awaitingHelper)
        #expect(negotiation.customerFacingRate == .usd(52))
        #expect(negotiation.rounds == 3)
    }

    @Test("Agreeing settles it and fixes the rate")
    func agreeing() {
        var negotiation = RateNegotiation(openingRate: .usd(45))
        negotiation.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2))
        negotiation.agree(at: .usd(58))
        #expect(negotiation.isSettled)
        #expect(!negotiation.awaitingCustomer)
        #expect(!negotiation.awaitingHelper)
        #expect(negotiation.customerFacingRate == .usd(58))
        #expect(negotiation.gap == nil)
    }

    @Test("Declining settles it too, and records who walked")
    func declining() {
        var negotiation = RateNegotiation(openingRate: .usd(45))
        negotiation.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2))
        negotiation.decline(byCustomer: true)
        #expect(negotiation.isSettled)
        #expect(negotiation.declinedBy == true)
        #expect(!negotiation.awaitingCustomer)
    }

    @Test("A negotiation survives the trip through the shared store")
    func roundTrips() throws {
        // Whole seconds on purpose. The store encodes dates as ISO8601 without
        // fractional seconds, so a `Date()` here would come back a few
        // milliseconds off and fail an equality check for reasons that have
        // nothing to do with negotiation. Sub-second drift on a proposal
        // timestamp is harmless; silently comparing against it in a test isn't.
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        var negotiation = RateNegotiation(openingRate: .usd(45), at: stamp)
        negotiation.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2), note: "my usual", at: stamp.addingTimeInterval(30))
        negotiation.counter(.usd(52), byCustomer: true, at: stamp.addingTimeInterval(60))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(RateNegotiation.self, from: try encoder.encode(negotiation))
        #expect(restored == negotiation)
        #expect(restored.rounds == 3)
        #expect(restored.proposals[1].note == "my usual")
    }

    @Test("A job knows when it's waiting on the customer")
    func jobFlagsTheStall() {
        var job = Job(
            category: .custom, title: "Something else",
            address: MockData.addresses[0], timing: .now, estimatedMinutes: 60,
            quote: Pricing.quote(category: .custom, requestedMinutes: 60, hourlyRate: .usd(45), timing: .now),
            status: .searching
        )
        job.negotiation = RateNegotiation(openingRate: .usd(45))
        #expect(!job.needsRateResponse)

        job.negotiation?.counter(.usd(58), byCustomer: false, helperID: MockData.fixedID(2))
        #expect(job.needsRateResponse)

        // Once it's booked, there's nothing to answer.
        job.status = .accepted
        #expect(!job.needsRateResponse)
    }
}

@Suite("Repricing an agreed rate")
struct RepriceTests {

    private var quote: Quote {
        Pricing.quote(
            category: .custom, requestedMinutes: 120, hourlyRate: .usd(50),
            timing: .now, demand: DemandIndex(openRequests: 12, availableHelpers: 8)
        )
    }

    @Test("A new rate rebuilds labour, surge, fee and tax")
    func repriceRebuildsEverything() {
        let original = quote
        #expect(original.labor == .usd(100))
        #expect(original.surgeAmount == .usd(120))       // 2.2× on 100

        let repriced = Pricing.reprice(original, at: .usd(60))
        #expect(repriced.hourlyRate == .usd(60))
        #expect(repriced.labor == .usd(120))
        #expect(repriced.surgeAmount == .usd(144))       // surge follows labour
        #expect(repriced.minutes == original.minutes)
        #expect(repriced.urgencyFee == original.urgencyFee)
        #expect(repriced.total == repriced.subtotal + repriced.serviceFee + repriced.tax)
        #expect(repriced.total > original.total)
    }

    @Test("Repricing to the same rate changes nothing")
    func repriceIsIdentity() {
        #expect(Pricing.reprice(quote, at: .usd(50)) == quote)
    }

    @Test("Agreeing a lower rate genuinely costs less")
    func repriceDownwards() {
        let cheaper = Pricing.reprice(quote, at: .usd(40))
        #expect(cheaper.labor == .usd(80))
        #expect(cheaper.total < quote.total)
    }

    @Test("A promo survives repricing")
    func repriceKeepsAdjustments() {
        let discounted = Pricing.quote(
            category: .custom, requestedMinutes: 120, hourlyRate: .usd(50),
            timing: .scheduled(start: Date().addingTimeInterval(3600)),
            promo: Promo.named("WEEKEND10")
        )
        let repriced = Pricing.reprice(discounted, at: .usd(70))
        #expect(repriced.promoCode == "WEEKEND10")
        #expect(repriced.promoDiscount == discounted.promoDiscount)
    }

    @Test("Repricing then settling overtime compounds correctly")
    func repriceThenSettle() {
        let agreed = Pricing.reprice(quote, at: .usd(60))
        let settled = Pricing.settle(agreed, billedMinutes: 150)
        #expect(settled.hourlyRate == .usd(60))
        #expect(settled.minutes == 150)
        #expect(settled.labor == .usd(150))             // 60 × 2.5
    }

    @Test("The helper is paid on the agreed rate, not the opening offer")
    func payoutFollowsTheAgreement() {
        var job = Job(
            category: .custom, title: "Something else",
            address: MockData.addresses[0], timing: .now, estimatedMinutes: 120,
            quote: quote, status: .completed
        )
        job.billedMinutes = 120
        let before = Payout.earnings(for: job)

        job.quote = Pricing.reprice(job.quote, at: .usd(60))
        let after = Payout.earnings(for: job)

        #expect(before.labour == .usd(100))
        #expect(after.labour == .usd(120))
        #expect(after.gross > before.gross)
    }
}

@Suite("Custom has no rate until you name one")
@MainActor
struct CustomRateTests {

    private let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 6, day: 15, hour: 9, minute: 0
    ))!

    private func draft(_ category: HelpCategory) -> RequestDraft {
        RequestDraft(category: category, address: MockData.addresses[0], wantsInstant: false, now: now)
    }

    @Test("Custom advertises no price on its tile")
    func tileAdvertisesNoPrice() {
        #expect(HelpCategory.custom.rateLabel == "You name it")
        // Everything else still quotes a number.
        for category in HelpCategory.allCases where category != .custom {
            #expect(category.rateLabel.contains("/hr"), "\(category.title) lost its rate")
        }
    }

    @Test("A fresh Custom draft has no rate at all")
    func customStartsUnpriced() {
        let draft = draft(.custom)
        #expect(draft.offeredRate == nil)
        #expect(draft.hourlyRate == nil)
        #expect(!draft.isPriceable)
        #expect(draft.quote(demand: .calm, now: now) == nil)
    }

    @Test("An unpriced Custom job can't leave the details step or be booked")
    func unpricedCannotAdvance() {
        let draft = draft(.custom)
        draft.step = .details
        #expect(!draft.canAdvance(now: now))

        draft.setOfferedRate(.usd(40))
        #expect(draft.canAdvance(now: now))
    }

    @Test("Naming a rate prices the job at that rate")
    func namingARatePrices() {
        let draft = draft(.custom)
        draft.setOfferedRate(.usd(37))
        #expect(draft.hourlyRate == .usd(37))
        #expect(draft.isPriceable)
        #expect(draft.quote(demand: .calm, now: now)?.hourlyRate == .usd(37))
    }

    @Test("Every other category is priceable straight away")
    func standardCategoriesArePriced() {
        for category in HelpCategory.allCases where category != .custom {
            let draft = draft(category)
            #expect(draft.isPriceable, "\(category.title) should have a rate")
            #expect(draft.hourlyRate == category.standardHourlyRate)
        }
    }

    @Test("Switching into Custom clears the rate it inherited")
    func switchingToCustomClearsRate() {
        let draft = draft(.handyman)
        #expect(draft.hourlyRate == HelpCategory.handyman.standardHourlyRate)
        draft.select(category: .custom, now: now)
        #expect(draft.hourlyRate == nil, "carried the handyman rate into Custom")
    }

    @Test("Switching out of Custom picks the new category's rate back up")
    func switchingOutOfCustomRestoresRate() {
        let draft = draft(.custom)
        draft.setOfferedRate(.usd(90))
        draft.select(category: .cleaning, now: now)
        #expect(draft.hourlyRate == HelpCategory.cleaning.standardHourlyRate)
    }

    @Test("The suggestion is drawn from what helpers actually charge")
    func suggestionIsGrounded() {
        let draft = draft(.custom)
        let suggested = draft.suggestedRate(in: MockData.helpers)
        let rates = MockData.helpers.map(\.hourlyRate)
        #expect(suggested >= rates.min()!)
        #expect(suggested <= rates.max()!)
        // And it stays a suggestion — reading it doesn't set anything.
        #expect(draft.hourlyRate == nil)
    }

    @Test("A named Custom rate opens a negotiation on the job")
    func namedRateIsNegotiable() {
        let draft = draft(.custom)
        draft.setOfferedRate(.usd(30))
        #expect(draft.isNegotiating)

        // A helper who charges more answers with a number rather than silently
        // working for it.
        let pricier = MockData.helpers.first { $0.hourlyRate > .usd(50) }!
        let negotiation = RateNegotiation(openingRate: .usd(30), at: now)
        let response = Negotiation.response(to: .usd(30), helper: pricier, negotiation: negotiation)
        #expect(response != .accept)
    }
}
