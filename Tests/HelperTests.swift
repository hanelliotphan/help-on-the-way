import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Helper actions reshape the plan")
struct HelperActionTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let origin = GeoPoint(latitude: 37.77, longitude: -122.42)
    private let destination = GeoPoint(latitude: 37.79, longitude: -122.40)

    private func plan() -> DispatchPlan {
        DispatchPlan(
            acceptedAt: base, timeScale: 60,
            confirmMinutes: 1, travelMinutes: 10, greetMinutes: 2, jobMinutes: 60,
            origin: origin, destination: destination, route: [origin, destination]
        )
    }

    @Test("Setting off makes the job read as en route right now")
    func markEnRoute() {
        var plan = plan()
        let now = base.addingTimeInterval(500)
        plan.markEnRoute(at: now)
        #expect(plan.enRouteStartsAt == now)
        #expect(plan.status(at: now) == .enRoute)
    }

    @Test("Arriving pins arrival to now, whatever the estimate said")
    func markArrived() {
        var plan = plan()
        let start = base.addingTimeInterval(500)
        plan.markEnRoute(at: start)
        let arrival = start.addingTimeInterval(300)
        plan.markArrived(at: arrival)
        #expect(plan.arrivesAt == arrival)
        #expect(plan.status(at: arrival) == .arrived)
        // Five minutes of driving, not the ten originally quoted.
        #expect(plan.travelMinutes == 5)
    }

    @Test("Arriving late stretches the drive rather than going negative")
    func arrivingLate() {
        var plan = plan()
        let start = base.addingTimeInterval(500)
        plan.markEnRoute(at: start)
        plan.markArrived(at: start.addingTimeInterval(1_800))
        #expect(plan.travelMinutes == 30)
    }

    @Test("Arriving before setting off can't produce a negative drive")
    func arrivingBeforeLeaving() {
        var plan = plan()
        plan.markEnRoute(at: base.addingTimeInterval(1_000))
        plan.markArrived(at: base)
        #expect(plan.travelMinutes == 0)
    }

    @Test("Starting work moves the job into progress")
    func startWork() {
        var plan = plan()
        let start = base.addingTimeInterval(500)
        plan.markEnRoute(at: start)
        let arrival = start.addingTimeInterval(300)
        plan.markArrived(at: arrival)
        let began = arrival.addingTimeInterval(90)
        plan.markWorkStarted(at: began)
        #expect(plan.startsWorkAt == began)
        #expect(plan.status(at: began) == .inProgress)
    }

    @Test("Completing records how long the job actually ran")
    func complete() {
        var plan = plan()
        let start = base.addingTimeInterval(500)
        plan.markEnRoute(at: start)
        let arrival = start.addingTimeInterval(300)
        plan.markArrived(at: arrival)
        let began = arrival.addingTimeInterval(90)
        plan.markWorkStarted(at: began)
        let done = began.addingTimeInterval(45 * 60)
        plan.markCompleted(at: done)
        #expect(plan.jobMinutes == 45)
        #expect(plan.status(at: done) == .completed)
    }

    @Test("A job completed instantly still bills at least a minute")
    func completeImmediately() {
        var plan = plan()
        plan.markEnRoute(at: base)
        plan.markArrived(at: base)
        plan.markWorkStarted(at: base)
        plan.markCompleted(at: base)
        #expect(plan.jobMinutes == 1)
    }

    @Test("The full walk through leaves a plan both apps read identically")
    func fullWalkthroughStaysConsistent() {
        var plan = plan()
        let t0 = base
        plan.markEnRoute(at: t0)
        plan.markArrived(at: t0.addingTimeInterval(420))
        plan.markWorkStarted(at: t0.addingTimeInterval(500))
        plan.markCompleted(at: t0.addingTimeInterval(4_100))

        // Each earlier moment still derives the phase it was in at the time —
        // that's what lets the customer app rebuild the same timeline.
        #expect(plan.status(at: t0) == .enRoute)
        #expect(plan.status(at: t0.addingTimeInterval(420)) == .arrived)
        #expect(plan.status(at: t0.addingTimeInterval(500)) == .inProgress)
        #expect(plan.status(at: t0.addingTimeInterval(4_100)) == .completed)
    }
}

@Suite("Payouts")
struct EarningsTests {

    private func completedJob(
        billedMinutes: Int? = nil,
        tip: Decimal = .zero,
        demand: DemandIndex = .calm,
        timing: JobTiming = .now
    ) -> Job {
        var job = Job(
            category: .handyman,
            title: "Test",
            address: MockData.addresses[0],
            timing: timing,
            estimatedMinutes: 60,
            quote: Pricing.quote(
                category: .handyman, requestedMinutes: 60, hourlyRate: .usd(58),
                timing: timing, demand: demand
            ),
            status: .completed
        )
        job.helper = MockData.helpers[1]
        job.billedMinutes = billedMinutes
        if tip > 0 { job.rating = JobRating(stars: 5, tip: tip) }
        return job
    }

    @Test("The helper takes labour, the premium, and the whole tip")
    func helperTake() {
        let job = completedJob(tip: .usd(12), demand: DemandIndex(openRequests: 12, availableHelpers: 8))
        let earnings = Payout.earnings(for: job)
        #expect(earnings.labour == .usd(58))
        #expect(earnings.surge == .usd(69, 60))       // 58 × 1.2
        #expect(earnings.tips == .usd(12))
        #expect(earnings.gross == .usd(139, 60))
    }

    @Test("The platform keeps the service fee and the dispatch fee")
    func platformCut() {
        let job = completedJob(demand: DemandIndex(openRequests: 12, availableHelpers: 8))
        // Subtotal 133.60 → 12% service fee of 16.03, plus the $6 dispatch fee.
        #expect(Payout.platformCut(for: job) == .usd(22, 3))
    }

    @Test("Tax belongs to neither side")
    func taxIsNotIncome() {
        let job = completedJob(demand: DemandIndex(openRequests: 12, availableHelpers: 8))
        let helper = Payout.earnings(for: job).gross
        let platform = Payout.platformCut(for: job)
        #expect(helper + platform + job.quote.tax == job.quote.total)
    }

    @Test("Overtime is paid on the settled duration, not the booked one")
    func overtimeIsPaid() {
        let short = Payout.earnings(for: completedJob(billedMinutes: 60))
        let long = Payout.earnings(for: completedJob(billedMinutes: 90))
        #expect(long.labour > short.labour)
        #expect(long.labour == .usd(87))               // 58 × 1.5
        #expect(long.minutes == 90)
    }

    @Test("A scheduled job pays no premium")
    func scheduledPaysNoSurge() {
        let job = completedJob(
            demand: DemandIndex(openRequests: 40, availableHelpers: 4),
            timing: .scheduled(start: Date().addingTimeInterval(3 * 3600))
        )
        #expect(Payout.earnings(for: job).surge == .zero)
    }

    @Test("Effective hourly averages the whole period")
    func effectiveHourly() {
        let earnings = Earnings(labour: .usd(90), surge: .zero, tips: .usd(10), jobs: 2, minutes: 120)
        #expect(earnings.effectiveHourly == .usd(50))
    }

    @Test("No time worked doesn't divide by zero")
    func effectiveHourlyWithNoWork() {
        #expect(Earnings().effectiveHourly == .zero)
    }

    @Test("Earnings add up across jobs")
    func summing() {
        let jobs = [completedJob(tip: .usd(5)), completedJob(tip: .usd(7))]
        let total = Payout.earnings(for: jobs)
        #expect(total.jobs == 2)
        #expect(total.tips == .usd(12))
        #expect(total.minutes == 120)
    }

    @Test("An offer quotes what it pays before tips")
    func offerPay() {
        let job = completedJob(demand: DemandIndex(openRequests: 12, availableHelpers: 8))
        #expect(Payout.offerPay(for: job) == .usd(127, 60))   // 58 + 69.60
    }

    @Test("Periods bucket by when the work happened")
    func periods() {
        let now = Date()
        #expect(EarningsPeriod.today.contains(now, now: now))
        #expect(!EarningsPeriod.today.contains(now.addingTimeInterval(-2 * 86_400), now: now))
        #expect(EarningsPeriod.week.contains(now.addingTimeInterval(-3 * 86_400), now: now))
        #expect(!EarningsPeriod.week.contains(now.addingTimeInterval(-9 * 86_400), now: now))
        #expect(EarningsPeriod.allTime.contains(now.addingTimeInterval(-900 * 86_400), now: now))
    }
}

@Suite("Cross-app presence")
struct PresenceTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Going on shift marks a helper online")
    func onShift() {
        var snapshot = StoreSnapshot.seeded()
        let terrence = MockData.fixedID(2)
        snapshot.onlineHelpers.insert(terrence)
        #expect(snapshot.onlineHelperIDs(now: now).contains(terrence))
    }

    @Test("Presence survives the app being suspended for a long time")
    func presenceDoesNotExpire() {
        // Regression: presence used to be a heartbeat with a 12-second window.
        // On one device the helper app is suspended the moment you switch to the
        // customer app, so its heartbeat always went stale and every request
        // auto-matched before a person could accept.
        var snapshot = StoreSnapshot.seeded()
        let terrence = MockData.fixedID(2)
        snapshot.onlineHelpers.insert(terrence)
        snapshot.helperLastSeen[terrence] = now.addingTimeInterval(-3_600)
        #expect(snapshot.hasLiveHelper(for: .handyman, in: MockData.helpers, now: now))
    }

    @Test("Going off shift takes them out of the pool")
    func offShift() {
        var snapshot = StoreSnapshot.seeded()
        let terrence = MockData.fixedID(2)
        snapshot.onlineHelpers.insert(terrence)
        snapshot.onlineHelpers.remove(terrence)
        #expect(!snapshot.hasLiveHelper(for: .handyman, in: MockData.helpers, now: now))
    }

    @Test("A live helper is only live for work they actually do")
    func presenceRespectsSkills() {
        var snapshot = StoreSnapshot.seeded()
        // Camila does pet care and delivery, not handyman work.
        snapshot.onlineHelpers.insert(MockData.fixedID(8))
        #expect(snapshot.hasLiveHelper(for: .petCare, in: MockData.helpers, now: now))
        #expect(!snapshot.hasLiveHelper(for: .handyman, in: MockData.helpers, now: now))
    }

    @Test("Nobody online means the simulation is free to auto-match")
    func noPresence() {
        let snapshot = StoreSnapshot.seeded()
        for category in HelpCategory.allCases {
            #expect(!snapshot.hasLiveHelper(for: category, in: MockData.helpers, now: now))
        }
    }

    @Test("Presence survives a round trip through the shared document")
    func presenceRoundTrips() throws {
        var snapshot = StoreSnapshot.seeded()
        snapshot.onlineHelpers.insert(MockData.fixedID(2))
        snapshot.revision = 7

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(StoreSnapshot.self, from: try encoder.encode(snapshot))
        #expect(restored.revision == 7)
        #expect(restored.onlineHelperIDs(now: now).contains(MockData.fixedID(2)))
    }

    @Test("The seeded snapshot is a sane starting point for both apps")
    func seededSnapshot() {
        let snapshot = StoreSnapshot.seeded()
        #expect(snapshot.version == StoreSnapshot.currentVersion)
        #expect(!snapshot.jobs.isEmpty)
        #expect(!snapshot.addresses.isEmpty)
        #expect(snapshot.onlineHelpers.isEmpty)
        #expect(snapshot.revision == 0)
    }
}
