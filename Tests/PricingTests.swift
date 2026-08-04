import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Pricing")
struct PricingTests {

    // MARK: Minimums and labour

    @Test("A category's block minimum overrides a shorter request")
    func minimumMinutesWins() {
        #expect(Pricing.billableMinutes(category: .cleaning, requested: 30) == 120)
        #expect(Pricing.billableMinutes(category: .handyman, requested: 30) == 60)
        // A longer request is left alone.
        #expect(Pricing.billableMinutes(category: .cleaning, requested: 300) == 300)
    }

    @Test("Labour is rate times hours, to the cent")
    func labourMath() {
        let quote = Pricing.quote(
            category: .handyman, requestedMinutes: 90, hourlyRate: .usd(58),
            timing: .scheduled(start: Date().addingTimeInterval(3600))
        )
        #expect(quote.minutes == 90)
        #expect(quote.labor == .usd(87))
    }

    @Test("An awkward duration still lands on whole cents")
    func labourRounding() {
        // 58 × (70/60) = 67.6666… — the ledger only ever sees 67.67.
        let quote = Pricing.quote(
            category: .handyman, requestedMinutes: 70, hourlyRate: .usd(58),
            timing: .scheduled(start: Date().addingTimeInterval(7200))
        )
        #expect(quote.labor == .usd(67, 67))
    }

    // MARK: Instant vs scheduled

    @Test("A scheduled job carries no dispatch fee and no surge")
    func scheduledHasNoUrgency() {
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(46),
            timing: .scheduled(start: Date().addingTimeInterval(3 * 3600)),
            demand: DemandIndex(openRequests: 40, availableHelpers: 4)
        )
        #expect(quote.urgencyFee == .zero)
        #expect(quote.surgeAmount == .zero)
        #expect(quote.surgeMultiplier == 1)
    }

    @Test("An instant job pays the dispatch fee")
    func instantAddsDispatchFee() {
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(46),
            timing: .now, demand: .calm
        )
        #expect(quote.urgencyFee == Pricing.instantDispatchFee)
    }

    @Test("A calm neighbourhood doesn't surge")
    func calmDemandDoesNotSurge() {
        #expect(DemandIndex.calm.multiplier == 1)
        #expect(DemandIndex.calm.isSurging == false)
    }

    @Test("Surge is a tenth-rounded ratio, capped")
    func surgeIsClamped() {
        #expect(DemandIndex(openRequests: 12, availableHelpers: 8).multiplier == Decimal(22) / 10)
        #expect(DemandIndex(openRequests: 400, availableHelpers: 1).multiplier == Pricing.maximumSurge)
        // Nobody free at all is the worst case, not a divide by zero.
        #expect(DemandIndex(openRequests: 5, availableHelpers: 0).multiplier == Pricing.maximumSurge)
    }

    @Test("Surge is charged on labour only, never on the fees")
    func surgeAppliesToLabourOnly() {
        let demand = DemandIndex(openRequests: 12, availableHelpers: 8) // 2.2×
        let quote = Pricing.quote(
            category: .assembly, requestedMinutes: 60, hourlyRate: .usd(50),
            timing: .now, demand: demand
        )
        #expect(quote.labor == .usd(50))
        #expect(quote.surgeAmount == .usd(60))       // 50 × 1.2
        #expect(quote.urgencyFee == .usd(6))
    }

    // MARK: Planned-ahead credit

    @Test("Booking a day or more ahead earns the credit")
    func plannedDiscountApplies() {
        let now = Date()
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(50),
            timing: .scheduled(start: now.addingTimeInterval(25 * 3600)), now: now
        )
        #expect(quote.plannedDiscount == .usd(5))    // 5% of 100
    }

    @Test("Booking for later today does not")
    func plannedDiscountNeedsADayOfLead() {
        let now = Date()
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(50),
            timing: .scheduled(start: now.addingTimeInterval(23 * 3600)), now: now
        )
        #expect(quote.plannedDiscount == .zero)
    }

    // MARK: Fees, tax, totals

    @Test("The service fee has a floor")
    func serviceFeeFloor() {
        // 12% of a tiny job would come to less than the minimum.
        let quote = Pricing.quote(
            category: .petCare, requestedMinutes: 60, hourlyRate: .usd(10),
            timing: .scheduled(start: Date().addingTimeInterval(3600))
        )
        #expect(quote.serviceFee == Pricing.minimumServiceFee)
    }

    @Test("The total is exactly its parts")
    func totalIsSumOfParts() {
        let quote = Pricing.quote(
            category: .moving, requestedMinutes: 180, hourlyRate: .usd(62),
            timing: .now, demand: DemandIndex(openRequests: 12, availableHelpers: 8)
        )
        #expect(quote.total == quote.subtotal + quote.serviceFee + quote.tax)
    }

    @Test("A known instant clean prices out the same every time")
    func regressionOnAKnownQuote() {
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 60, hourlyRate: .usd(46),
            timing: .now, demand: .calm
        )
        // Bumped to the 2-hour cleaning minimum: 92 labour + 6 dispatch.
        #expect(quote.minutes == 120)
        #expect(quote.labor == .usd(92))
        #expect(quote.subtotal == .usd(98))
        #expect(quote.serviceFee == .usd(11, 76))
        #expect(quote.tax == .usd(9, 74))
        #expect(quote.total == .usd(119, 50))
    }

    @Test("Every line except the total shows up in the receipt")
    func linesCoverTheQuote() {
        let quote = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(46),
            timing: .now, demand: DemandIndex(openRequests: 12, availableHelpers: 8),
            promo: Promo.named("WEEKEND10")
        )
        let names = quote.lines.map(\.name)
        #expect(names.contains("Labour"))
        #expect(names.contains("Instant dispatch"))
        #expect(names.contains("Busy-area rate"))
        #expect(names.contains("WEEKEND10"))
        #expect(names.contains("Service fee"))
        #expect(names.last == "Total")
        #expect(quote.lines.last?.amount == quote.total)
    }

    // MARK: Promos

    @Test("A percentage promo respects its cap")
    func promoCap() {
        let promo = Promo.named("FIRST20")
        #expect(promo != nil)
        // 20% of 400 would be 80; the cap is 25.
        #expect(promo?.discount(onLabor: .usd(400)) == .usd(25))
        #expect(promo?.discount(onLabor: .usd(50)) == .usd(10))
    }

    @Test("A promo can't discount more than the labour it applies to")
    func promoCannotExceedLabour() {
        let promo = Promo.named("WEEKEND10")
        #expect(promo?.discount(onLabor: .usd(4)) == .usd(4))
    }

    @Test("Unknown codes are rejected")
    func unknownPromo() {
        #expect(Promo.named("NOPE") == nil)
        // Case and whitespace shouldn't matter.
        #expect(Promo.named("  first20 ")?.code == "FIRST20")
    }

    @Test("Discounts can't push a quote below zero")
    func discountsCannotGoNegative() {
        let quote = Pricing.quote(
            category: .petCare, requestedMinutes: 60, hourlyRate: .usd(5),
            timing: .scheduled(start: Date().addingTimeInterval(3600)),
            promo: Promo.named("WEEKEND10")
        )
        #expect(quote.subtotal >= .zero)
        #expect(quote.total >= .zero)
    }

    // MARK: Settlement

    @Test("Overtime is billed in quarter-hour blocks")
    func settlementRoundsUpToFifteens() {
        let booked = Pricing.quote(
            category: .handyman, requestedMinutes: 60, hourlyRate: .usd(60),
            timing: .scheduled(start: Date().addingTimeInterval(3600))
        )
        let settled = Pricing.settle(booked, billedMinutes: 68)
        #expect(settled.minutes == 75)
        #expect(settled.labor == .usd(75))
    }

    @Test("Finishing early still bills the booked time")
    func settlementNeverBillsLessThanBooked() {
        let booked = Pricing.quote(
            category: .cleaning, requestedMinutes: 120, hourlyRate: .usd(46),
            timing: .scheduled(start: Date().addingTimeInterval(3600))
        )
        let settled = Pricing.settle(booked, billedMinutes: 40)
        #expect(settled.minutes == booked.minutes)
        #expect(settled.total == booked.total)
    }

    @Test("Settlement re-derives the surge rather than carrying the old amount")
    func settlementRecomputesSurge() {
        let booked = Pricing.quote(
            category: .assembly, requestedMinutes: 60, hourlyRate: .usd(50),
            timing: .now, demand: DemandIndex(openRequests: 12, availableHelpers: 8)
        )
        let settled = Pricing.settle(booked, billedMinutes: 120)
        #expect(settled.labor == .usd(100))
        #expect(settled.surgeAmount == .usd(120))     // 100 × 1.2
        #expect(settled.total > booked.total)
    }

    @Test("An unchanged duration settles to the identical quote")
    func settlementIsIdentityWhenNothingChanged() {
        let booked = Pricing.quote(
            category: .techHelp, requestedMinutes: 90, hourlyRate: .usd(58),
            timing: .scheduled(start: Date().addingTimeInterval(3600))
        )
        #expect(Pricing.settle(booked, billedMinutes: 90) == booked)
    }
}

@Suite("Cancellation policy")
struct CancellationTests {

    private func job(status: JobStatus, startsIn seconds: TimeInterval = 0, acceptedAgo: TimeInterval? = nil) -> Job {
        let now = Date()
        var job = Job(
            category: .handyman,
            title: "Test",
            address: MockData.addresses[0],
            timing: status == .scheduled ? .scheduled(start: now.addingTimeInterval(seconds)) : .now,
            estimatedMinutes: 60,
            quote: Pricing.quote(category: .handyman, requestedMinutes: 60, hourlyRate: .usd(58), timing: .now),
            status: status
        )
        if let acceptedAgo {
            job.dispatch = DispatchPlan(
                acceptedAt: now.addingTimeInterval(-acceptedAgo), timeScale: 60,
                confirmMinutes: 1, travelMinutes: 10, greetMinutes: 2, jobMinutes: 60,
                origin: MockData.homePoint, destination: MockData.addresses[0].point,
                route: [MockData.homePoint, MockData.addresses[0].point]
            )
        }
        return job
    }

    @Test("Cancelling before anyone accepts is free")
    func searchingIsFree() {
        #expect(Cancellation.fee(for: job(status: .searching)) == .zero)
    }

    @Test("A scheduled job is free to drop outside the notice window")
    func scheduledOutsideWindowIsFree() {
        #expect(Cancellation.fee(for: job(status: .scheduled, startsIn: 5 * 3600)) == .zero)
    }

    @Test("Dropping a scheduled job at the last minute costs the trip fee")
    func scheduledInsideWindowCharges() {
        #expect(Cancellation.fee(for: job(status: .scheduled, startsIn: 30 * 60)) == Cancellation.fee)
    }

    @Test("There's a minute of grace after a helper accepts")
    func graceAfterAccept() {
        #expect(Cancellation.fee(for: job(status: .accepted, acceptedAgo: 20)) == .zero)
        #expect(Cancellation.fee(for: job(status: .enRoute, acceptedAgo: 300)) == Cancellation.fee)
    }

    @Test("An already-finished job can't be charged again")
    func finishedJobsAreFree() {
        #expect(Cancellation.fee(for: job(status: .completed)) == .zero)
        #expect(Cancellation.fee(for: job(status: .cancelled)) == .zero)
        #expect(Cancellation.fee(for: job(status: .unmatched)) == .zero)
    }
}
