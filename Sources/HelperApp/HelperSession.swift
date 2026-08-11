import Observation
import SwiftUI

enum HelperTab: Hashable {
    case drive, schedule, earnings, account
}

/// The helper side of the dispatcher.
///
/// Where `AppSession` owns the customer's state, this owns almost nothing: the
/// jobs live in the shared store and every action here is a read-modify-write
/// against it. What's local is only what belongs to this phone — which helper is
/// signed in, whether they're online, and which offers they've waved away.
@Observable
@MainActor
final class HelperSession {

    /// Who's driving. A demo affordance rather than auth — the roster is fixed,
    /// so "signing in" is picking which of them you are.
    var me: Helper?
    var isOnline: Bool = false
    var selectedTab: HelperTab = .drive

    var jobs: [Job] = []
    var customer: CustomerProfile = CustomerProfile()
    var now: Date = Date()
    var toast: String?
    /// Offers this helper has passed on. Local: another helper should still see them.
    var declinedJobIDs: Set<UUID> = []

    let roster: [Helper] = MockData.helpers

    private var lastRevision = -1
    @ObservationIgnored private nonisolated(unsafe) var ticker: Task<Void, Never>?

    private static let personaKey = "helper.persona.id"
    private static let onlineKey = "helper.online"

    // MARK: Lifecycle

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.personaKey),
           let id = UUID(uuidString: raw) {
            me = roster.first { $0.id == id }
        }
        isOnline = UserDefaults.standard.bool(forKey: Self.onlineKey)
        reload(force: true)
        startTicker()
    }

    deinit { ticker?.cancel() }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func signIn(as helper: Helper) {
        me = helper
        UserDefaults.standard.set(helper.id.uuidString, forKey: Self.personaKey)
    }

    func signOut() {
        setOnline(false)
        me = nil
        UserDefaults.standard.removeObject(forKey: Self.personaKey)
    }

    // MARK: Presence

    func setOnline(_ value: Bool) {
        isOnline = value
        UserDefaults.standard.set(value, forKey: Self.onlineKey)
        guard let me else { return }
        SharedStore.setOnline(value, helperID: me.id, at: Date())
        toast = value
            ? "You're online. Requests from the customer app will land here."
            : "You're offline."
        reload(force: true)
    }

    // MARK: Reading the shared store

    private func reload(force: Bool = false) {
        guard let disk = Persistence.load() else { return }
        guard force || disk.revision != lastRevision else { return }
        lastRevision = disk.revision
        jobs = disk.jobs
        customer = disk.profile
    }

    func tick() {
        now = Date()
        reload()
        if isOnline, let me { SharedStore.touch(helperID: me.id, at: now) }
        advanceCompletedWork()
    }

    /// Called when the app comes back to the foreground. The ticker is suspended
    /// while backgrounded, and on one device that's exactly when the customer
    /// places the request — so the queue has to be re-read the moment we return
    /// rather than up to a second later.
    func refreshFromForeground() {
        now = Date()
        reload(force: true)
        if isOnline, let me { SharedStore.setOnline(true, helperID: me.id, at: now) }
        advanceCompletedWork()
    }

    /// A job whose plan says it finished while nobody was looking still needs to
    /// be closed out and billed.
    private func advanceCompletedWork() {
        guard let mine = activeJob, let plan = mine.dispatch else { return }
        guard plan.status(at: now) == .completed, mine.status != .completed else { return }
        complete(mine)
    }

    // MARK: Derived views of the queue

    var isSharedStore: Bool { SharedStore.isShared }

    /// Open instant requests this helper could take.
    var offers: [Job] {
        guard let me, isOnline else { return [] }
        return jobs
            .filter { $0.status == .searching }
            .filter { me.handles($0.category) }
            .filter { !declinedJobIDs.contains($0.id) }
            // A rate we've already countered is the customer's move, not ours.
            .filter { $0.negotiation?.awaitingCustomer != true }
            .filter { me.basePoint.miles(to: $0.address.point) <= Matching.radiusMiles }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activeJob: Job? {
        guard let me else { return nil }
        return jobs.first { $0.helper?.id == me.id && $0.status.isLive }
    }

    var upcoming: [Job] {
        guard let me else { return [] }
        return jobs
            .filter { $0.helper?.id == me.id && $0.status == .scheduled }
            .sorted { $0.startsAt < $1.startsAt }
    }

    var completedByMe: [Job] {
        guard let me else { return [] }
        return jobs
            .filter { $0.helper?.id == me.id && $0.status == .completed }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func earnings(for period: EarningsPeriod) -> Earnings {
        Payout.earnings(for: completedByMe.filter { period.contains($0.createdAt, now: now) })
    }

    func miles(to job: Job) -> Double {
        me?.basePoint.miles(to: job.address.point) ?? 0
    }

    func minutesAway(from job: Job) -> Int {
        guard let me else { return 0 }
        return Dispatch.travelMinutes(from: me.basePoint, to: job.address.point)
    }

    var unreadCount: Int {
        guard let me else { return 0 }
        // Mirror image of the customer's count: anything the customer sent after
        // this helper's last message.
        return jobs
            .filter { $0.helper?.id == me.id }
            .reduce(0) { total, job in
                guard let lastMine = job.messages.last(where: { !$0.fromCustomer && !$0.isSystem })?.at else {
                    return total + job.messages.filter(\.isFromCustomerHuman).count
                }
                return total + job.messages.filter { $0.isFromCustomerHuman && $0.at > lastMine }.count
            }
    }

    // MARK: Taking work

    func accept(_ job: Job) {
        guard let me else { return }
        guard activeJob == nil else {
            toast = "Finish your current job first."
            return
        }
        let acceptedAt = Date()
        commit { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == job.id }) else { return }
            // Somebody else may have taken it in the seconds since it appeared.
            guard snapshot.jobs[index].status == .searching else { return }

            var taken = snapshot.jobs[index]
            taken.helper = me
            taken.status = .accepted
            // Accepting settles the haggling at whatever the customer last
            // offered, and the quote is re-priced to match before anyone is
            // charged for it.
            if var negotiation = taken.negotiation, !negotiation.isSettled {
                let agreed = negotiation.customerFacingRate
                negotiation.agree(at: agreed)
                taken.negotiation = negotiation
                taken.quote = Pricing.reprice(taken.quote, at: agreed)
            }
            taken.dispatch = Dispatch.plan(
                helper: me,
                destination: taken.address.point,
                jobMinutes: taken.quote.minutes,
                acceptedAt: acceptedAt,
                timeScale: snapshot.timeScale,
                seed: taken.id
            )
            taken.events.append(JobEvent(at: acceptedAt, status: .accepted, note: "\(me.displayName) accepted"))
            taken.messages.append(Message(
                at: acceptedAt,
                body: "\(me.firstName) took your job and is heading over.",
                fromCustomer: false,
                isSystem: true
            ))
            snapshot.jobs[index] = taken
        }

        if activeJob == nil {
            toast = "That one went to somebody else."
        } else {
            toast = "Job accepted. Head to \(job.address.oneLine)."
        }
    }

    func decline(_ job: Job) {
        declinedJobIDs.insert(job.id)
    }

    /// Answers a named rate with a number of the helper's own. The job stays
    /// open — the customer now owes a reply.
    func counter(_ job: Job, rate: Decimal) {
        guard let me, var negotiation = job.negotiation,
              Negotiation.isValid(offering: rate, in: negotiation)
        else { return }

        negotiation.counter(rate, byCustomer: false, helperID: me.id)
        commit { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == job.id }),
                  snapshot.jobs[index].status == .searching
            else { return }
            snapshot.jobs[index].negotiation = negotiation
            snapshot.jobs[index].events.append(JobEvent(
                at: Date(), status: .searching,
                note: "\(me.displayName) countered at \(Format.rate(rate))"
            ))
        }
        toast = "Countered at \(Format.rate(rate)). Waiting on them."
    }

    /// What this helper would say to the offer, so the app can pre-fill a
    /// sensible counter instead of making them guess.
    func suggestedCounter(for job: Job) -> Decimal? {
        guard let me, let negotiation = job.negotiation else { return nil }
        if case .counter(let rate) = Negotiation.response(
            to: negotiation.customerFacingRate, helper: me, negotiation: negotiation
        ) {
            return rate
        }
        return me.hourlyRate
    }

    // MARK: Working it

    /// Each of these reshapes the plan instead of setting status, so the customer
    /// app derives the same phase from the same numbers.
    func markEnRoute(_ job: Job) {
        reshape(job, note: "Left for \(job.address.oneLine)") { $0.markEnRoute(at: Date()) }
    }

    func markArrived(_ job: Job) {
        reshape(job, note: "Arrived at \(job.address.oneLine)") { $0.markArrived(at: Date()) }
    }

    func startWork(_ job: Job) {
        reshape(job, note: "Started work") { $0.markWorkStarted(at: Date()) }
    }

    func complete(_ job: Job) {
        let finishedAt = Date()
        commit { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == job.id }),
                  var plan = snapshot.jobs[index].dispatch else { return }
            plan.markCompleted(at: finishedAt)
            snapshot.jobs[index].dispatch = plan
            snapshot.jobs[index].status = .completed
            snapshot.jobs[index].billedMinutes = plan.jobMinutes
            snapshot.jobs[index].finalTotal = Pricing.settle(
                snapshot.jobs[index].quote, billedMinutes: plan.jobMinutes
            ).total
            snapshot.jobs[index].events.append(
                JobEvent(at: finishedAt, status: .completed, note: "Job completed")
            )
            snapshot.jobs[index].messages.append(Message(
                at: finishedAt,
                body: "All finished. Have a look and let me know if anything needs another pass.",
                fromCustomer: false
            ))
        }
        toast = "Job complete. \(Payout.earnings(for: job).gross.currency) earned."
        selectedTab = .earnings
    }

    private func reshape(_ job: Job, note: String, _ change: (inout DispatchPlan) -> Void) {
        let at = Date()
        commit { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == job.id }),
                  var plan = snapshot.jobs[index].dispatch else { return }
            change(&plan)
            snapshot.jobs[index].dispatch = plan
            let derived = plan.status(at: at)
            snapshot.jobs[index].status = derived
            snapshot.jobs[index].events.append(JobEvent(at: at, status: derived, note: note))
        }
    }

    // MARK: Messaging

    func send(_ text: String, jobID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commit { snapshot in
            guard let index = snapshot.jobs.firstIndex(where: { $0.id == jobID }) else { return }
            snapshot.jobs[index].messages.append(Message(at: Date(), body: trimmed, fromCustomer: false))
        }
    }

    // MARK: Writing

    private func commit(_ change: (inout StoreSnapshot) -> Void) {
        let written = SharedStore.mutate(change)
        lastRevision = written.revision
        jobs = written.jobs
        customer = written.profile
    }
}

private extension Message {
    /// A message the customer actually typed, as opposed to a system line or the
    /// helper's own send.
    var isFromCustomerHuman: Bool { fromCustomer && !isSystem }
}
