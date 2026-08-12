import Observation
import SwiftUI

enum RootTab: Hashable {
    case home, activity, messages, profile
}

/// What the matching screen has learned so far about an instant request.
struct MatchingProgress: Hashable {
    var pinged: Int = 0
    var declined: [Helper] = []
    var failed: Bool = false
    /// Non-zero once the simulation has stood down for a real helper app.
    var awaitingLiveHelpers: Int = 0
    /// Set when somebody has answered the offered rate with a number of their own.
    var counteredBy: Helper?
    /// When we started waiting on a person. Bounded, so a helper app that was
    /// force-quit while on shift can't leave a request hanging forever.
    var awaitingSince: Date?
    var startedAt: Date = Date()
}

/// The whole app's state in one place: the account, the jobs, and the clock
/// that walks live jobs through their timeline. Views read it and call methods
/// on it; nothing else mutates a job.
@Observable
@MainActor
final class AppSession {

    // MARK: Stored state

    var hasOnboarded: Bool
    var profile: CustomerProfile
    var addresses: [SavedAddress]
    var paymentMethods: [PaymentMethod]
    var jobs: [Job]
    /// Wall-clock seconds per simulated minute. Lower runs the demo faster.
    var timeScale: Double

    // MARK: Ephemeral state

    /// Bumped every second so anything showing an ETA redraws.
    var now: Date = Date()
    var selectedTab: RootTab = .home
    /// Non-nil while the request flow is on screen.
    var draft: RequestDraft?
    var matchingJobID: UUID?
    var trackingJobID: UUID?
    var ratingJobID: UUID?
    var matching: [UUID: MatchingProgress] = [:]
    var toast: String?

    let backend: DemoBackend

    // Cancelled from `deinit`, which runs outside the main actor and so can't
    // reach isolated state. Handing a `Task` its cancel is safe from anywhere.
    @ObservationIgnored private nonisolated(unsafe) var ticker: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var saveTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Last revision of the shared document this app wrote or read. Anything
    /// higher on disk is the helper app's work, and gets adopted on the next tick.
    private var lastRevision = 0

    init(backend: DemoBackend? = nil, snapshot: StoreSnapshot? = Persistence.load()) {
        self.backend = backend ?? DemoBackend()
        if let snapshot {
            hasOnboarded = snapshot.hasOnboarded
            profile = snapshot.profile
            addresses = snapshot.addresses
            paymentMethods = snapshot.paymentMethods
            jobs = snapshot.jobs
            timeScale = snapshot.timeScale
            lastRevision = snapshot.revision
        } else {
            hasOnboarded = false
            profile = MockData.profile
            addresses = MockData.addresses
            paymentMethods = MockData.paymentMethods
            jobs = MockData.seedJobs()
            timeScale = Dispatch.demoTimeScale
        }
        startTicker()
    }

    deinit {
        ticker?.cancel()
        saveTask?.cancel()
    }

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

    // MARK: Derived reads

    var homeAddress: SavedAddress { addresses.first ?? MockData.addresses[0] }

    var defaultPaymentMethod: PaymentMethod? {
        paymentMethods.first { $0.isDefault } ?? paymentMethods.first
    }

    var liveJobs: [Job] {
        jobs.filter { $0.status.isLive }.sorted { $0.createdAt > $1.createdAt }
    }

    var upcomingJobs: [Job] {
        jobs.filter { $0.status == .scheduled }.sorted { $0.startsAt < $1.startsAt }
    }

    var pastJobs: [Job] {
        jobs.filter { $0.status.isFinished }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Jobs worth a chat thread — anyone who has a helper attached.
    var threads: [Job] {
        jobs.filter { $0.helper != nil && !$0.messages.isEmpty || ($0.helper != nil && $0.status.isLive) }
            .sorted { ($0.messages.last?.at ?? $0.createdAt) > ($1.messages.last?.at ?? $1.createdAt) }
    }

    var unreadCount: Int {
        threads.reduce(0) { $0 + $1.unreadFromHelper }
    }

    var jobsAwaitingRating: [Job] {
        jobs.filter { $0.status == .completed && $0.rating == nil }
    }

    func job(_ id: UUID?) -> Job? {
        guard let id else { return nil }
        return jobs.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        jobs.firstIndex { $0.id == id }
    }

    func demand(for category: HelpCategory, at point: GeoPoint) -> DemandIndex {
        backend.demand(for: category, near: point, at: now)
    }

    func isFavorite(_ helperID: UUID) -> Bool {
        profile.favoriteHelperIDs.contains(helperID)
    }

    // MARK: Booking

    /// Turns a finished draft into a real job. Instant requests go out to the
    /// neighbourhood; scheduled ones get a helper assigned straight away so the
    /// customer knows who's coming.
    @discardableResult
    func submit(_ draft: RequestDraft) -> Job {
        let timing = draft.timing
        var job = Job(
            category: draft.category,
            title: draft.resolvedTitle,
            notes: draft.notes,
            photoNames: draft.photoNames,
            address: draft.address ?? homeAddress,
            timing: timing,
            estimatedMinutes: draft.minutes,
            quote: draft.quote(demand: demand(for: draft.category, at: (draft.address ?? homeAddress).point), now: now),
            status: timing.isInstant ? .searching : .scheduled,
            paymentMethodID: (draft.paymentMethod ?? defaultPaymentMethod)?.id
        )

        if let chosen = draft.chosenHelper {
            job.helper = chosen
            job.helperWasChosen = true
        }

        // A named rate travels with the job as an opening offer, so whoever
        // picks it up answers the number rather than silently working for it.
        if let offered = draft.offeredRate {
            job.negotiation = RateNegotiation(openingRate: offered, at: now)
        }

        if timing.isInstant {
            job.events.append(JobEvent(
                at: now, status: .searching,
                note: job.helperWasChosen
                    ? "Sent to \(job.helper?.displayName ?? "your helper")"
                    : "Asked \(backend.nearbyCount(for: job.category, near: job.address.point)) helpers nearby"
            ))
        } else {
            // Nobody wants a calendar entry that just says "a helper".
            if job.helper == nil {
                job.helper = Matching.best(
                    for: job.category,
                    near: job.address.point,
                    in: backend.roster,
                    favorites: profile.favoriteHelperIDs
                )?.helper
            }
            job.events.append(JobEvent(
                at: now, status: .scheduled,
                note: "Booked for \(Format.slot(job.startsAt, now: now))"
            ))
            if let helper = job.helper {
                job.messages.append(Message(
                    at: now,
                    body: "\(helper.firstName) is booked for \(Format.slot(job.startsAt, now: now)).",
                    fromCustomer: false,
                    isSystem: true
                ))
            }
        }

        jobs.insert(job, at: 0)
        self.draft = nil
        scheduleSave()

        if timing.isInstant {
            matching[job.id] = MatchingProgress(startedAt: now)
            matchingJobID = job.id
            Task { await runMatching(for: job.id) }
        } else {
            toast = "Booked for \(Format.slot(job.startsAt, now: now))"
            selectedTab = .activity
        }
        return job
    }

    /// How long a request waits on a real person before the simulation takes
    /// over. Long enough to switch apps and tap Accept; short enough that a
    /// helper app that never comes back doesn't strand the request.
    static let liveHelperGrace: TimeInterval = 45

    /// Consumes the dispatcher's stream for an instant request.
    func runMatching(for jobID: UUID, forceSimulated: Bool = false) async {
        guard let job = job(jobID) else { return }
        let live = forceSimulated ? 0 : liveHelperCount(for: job.category)
        for await update in backend.match(job: job, favorites: profile.favoriteHelperIDs, liveHelperCount: live) {
            guard let index = index(of: jobID) else { return }
            // A cancel while we were waiting wins over anything the stream says.
            guard jobs[index].status == .searching else { return }

            switch update {
            case .broadcasting(let count):
                matching[jobID, default: MatchingProgress()].pinged = count
            case .declined(let helper):
                matching[jobID, default: MatchingProgress()].declined.append(helper)
            case .awaitingLiveHelper(let count):
                // The job stays `.searching` on purpose. It gets picked up when
                // the helper app writes an accept into the shared store, which
                // `adoptExternalChanges()` notices on the next tick.
                matching[jobID, default: MatchingProgress()].awaitingLiveHelpers = count
                matching[jobID]?.awaitingSince = Date()
            case .countered(let helper, let rate):
                // The job stays searching; the customer now owes an answer.
                // Read once, mutate the copy, write once — a nested read inside
                // an @Observable setter's write is an exclusivity trap.
                var countered = jobs[index]
                countered.negotiation?.counter(rate, byCustomer: false, helperID: helper.id)
                countered.events.append(JobEvent(
                    at: Date(), status: .searching,
                    note: "\(helper.displayName) countered at \(Format.rate(rate))"
                ))
                jobs[index] = countered
                matching[jobID]?.counteredBy = helper
                toast = "\(helper.firstName) wants \(Format.rate(rate))."
                scheduleSave()
            case .accepted(let helper):
                if var negotiation = jobs[index].negotiation, !negotiation.isSettled {
                    let agreed = negotiation.customerFacingRate
                    negotiation.agree(at: agreed)
                    var settled = jobs[index]
                    settled.negotiation = negotiation
                    settled.quote = Pricing.reprice(settled.quote, at: agreed)
                    jobs[index] = settled
                }
                accept(helper: helper, forJobAt: index)
            case .failed:
                matching[jobID, default: MatchingProgress()].failed = true
                jobs[index].status = .unmatched
                jobs[index].events.append(JobEvent(at: Date(), status: .unmatched, note: "No helper took the request"))
                scheduleSave()
            }
        }
    }

    private func accept(helper: Helper, forJobAt index: Int) {
        let acceptedAt = Date()
        var job = jobs[index]
        job.helper = helper
        job.status = .accepted
        job.dispatch = makePlan(for: job, helper: helper, acceptedAt: acceptedAt)
        job.events.append(JobEvent(at: acceptedAt, status: .accepted, note: "\(helper.displayName) accepted"))
        if let message = backend.systemVoiceMessage(for: .accepted, job: job) {
            job.messages.append(message)
        }
        jobs[index] = job

        matchingJobID = nil
        trackingJobID = job.id
        matching[job.id] = nil
        scheduleSave()
    }

    private func makePlan(for job: Job, helper: Helper, acceptedAt: Date) -> DispatchPlan {
        var plan = Dispatch.plan(
            helper: helper,
            destination: job.address.point,
            jobMinutes: job.quote.minutes,
            acceptedAt: acceptedAt,
            timeScale: timeScale,
            seed: job.id
        )
        // Real jobs run a little long. Overtime is seeded off the job id so a
        // given booking always behaves the same way, and the settlement pass at
        // completion bills for what actually happened.
        var generator = SplitMix64(seed: job.id)
        let overtime = [0, 0, 15, 30][Int(generator.next() % 4)]
        plan.jobMinutes = job.quote.minutes + overtime
        return plan
    }

    func retryMatching(jobID: UUID) {
        guard let index = index(of: jobID) else { return }
        jobs[index].status = .searching
        jobs[index].events.append(JobEvent(at: Date(), status: .searching, note: "Asked again"))
        matching[jobID] = MatchingProgress(startedAt: Date())
        matchingJobID = jobID
        scheduleSave()
        Task { await runMatching(for: jobID) }
    }

    // MARK: Haggling

    /// Takes the helper's number. The quote is re-priced at the agreed rate
    /// before the job is handed to them, so what they accepted is what gets
    /// charged.
    func acceptCounter(jobID: UUID) {
        guard let index = index(of: jobID),
              var negotiation = jobs[index].negotiation,
              negotiation.awaitingCustomer
        else { return }

        let counter = negotiation.latest
        negotiation.agree(at: counter.rate)

        var agreed = jobs[index]
        agreed.negotiation = negotiation
        agreed.quote = Pricing.reprice(agreed.quote, at: counter.rate)
        agreed.events.append(JobEvent(
            at: Date(), status: .searching,
            note: "Agreed \(Format.rate(counter.rate))"
        ))
        jobs[index] = agreed

        guard let helper = counter.helperID.flatMap({ id in backend.roster.first { $0.id == id } }) else { return }
        accept(helper: helper, forJobAt: index)
        toast = "Booked at \(Format.rate(counter.rate))."
    }

    /// Comes back with a different number. The job goes back out at the new
    /// rate, and the dispatcher answers it again.
    func counterBack(jobID: UUID, rate: Decimal) {
        guard let index = index(of: jobID),
              var negotiation = jobs[index].negotiation,
              Negotiation.isValid(offering: rate, in: negotiation)
        else { return }

        negotiation.counter(rate, byCustomer: true)

        var reoffered = jobs[index]
        reoffered.negotiation = negotiation
        reoffered.quote = Pricing.reprice(reoffered.quote, at: rate)
        reoffered.status = .searching
        reoffered.events.append(JobEvent(
            at: Date(), status: .searching, note: "Countered at \(Format.rate(rate))"
        ))
        jobs[index] = reoffered
        matching[jobID, default: MatchingProgress()].counteredBy = nil
        matching[jobID]?.declined = []
        scheduleSave()
        Task { await runMatching(for: jobID) }
    }

    func declineCounter(jobID: UUID) {
        guard let index = index(of: jobID) else { return }
        jobs[index].negotiation?.decline(byCustomer: true)
        cancel(jobID: jobID, reason: "Couldn't agree on a rate")
    }

    // MARK: Cancelling

    func cancel(jobID: UUID, reason: String) {
        guard let index = index(of: jobID) else { return }
        let fee = Cancellation.fee(for: jobs[index], now: Date())
        jobs[index].status = .cancelled
        jobs[index].cancellationReason = reason
        jobs[index].dispatch = nil
        jobs[index].finalTotal = fee
        jobs[index].events.append(JobEvent(
            at: Date(), status: .cancelled,
            note: fee == .zero ? "Cancelled — no charge" : "Cancelled — \(fee.currency) trip fee"
        ))
        matching[jobID] = nil
        if matchingJobID == jobID { matchingJobID = nil }
        if trackingJobID == jobID { trackingJobID = nil }
        toast = fee == .zero ? "Cancelled. Nothing charged." : "Cancelled. \(fee.currency) trip fee applied."
        scheduleSave()
    }

    // MARK: Messaging

    func send(_ text: String, jobID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = index(of: jobID) else { return }
        jobs[index].messages.append(Message(at: Date(), body: trimmed, fromCustomer: true))
        scheduleSave()

        Task { [weak self] in
            guard let self, let job = self.job(jobID) else { return }
            guard let reply = await self.backend.reply(for: job, to: trimmed) else { return }
            guard let replyIndex = self.index(of: jobID) else { return }
            self.jobs[replyIndex].messages.append(reply)
            self.scheduleSave()
        }
    }

    // MARK: Rating

    func rate(jobID: UUID, rating: JobRating) {
        guard let index = index(of: jobID) else { return }
        var rated = jobs[index]
        rated.rating = rating
        if rating.tip > 0 {
            rated.finalTotal = (rated.finalTotal ?? rated.quote.total) + rating.tip
        }
        jobs[index] = rated
        if rating.stars >= 5, let helperID = jobs[index].helper?.id {
            profile.favoriteHelperIDs.insert(helperID)
        }
        ratingJobID = nil
        toast = rating.tip > 0 ? "Thanks — \(rating.tip.currency) tip sent." : "Thanks for the rating."
        scheduleSave()
    }

    func skipRating(jobID: UUID) {
        guard let index = index(of: jobID) else { return }
        jobs[index].rating = JobRating(stars: 0, comment: "", tip: .zero)
        ratingJobID = nil
        scheduleSave()
    }

    // MARK: Account edits

    func upsert(_ address: SavedAddress) {
        if let index = addresses.firstIndex(where: { $0.id == address.id }) {
            addresses[index] = address
        } else {
            addresses.append(address)
        }
        scheduleSave()
    }

    func removeAddress(_ id: UUID) {
        // The last address is load-bearing — every request needs somewhere to go.
        guard addresses.count > 1 else {
            toast = "Keep at least one address on file."
            return
        }
        addresses.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Adds a card. The caller hands over a `PaymentMethod` that `CardEntry` has
    /// already reduced to a brand and four digits — the full number never
    /// reaches this layer, so it can't be persisted by accident.
    func addPaymentMethod(_ method: PaymentMethod) {
        var added = method
        // First card on the account has to be the default, whatever was asked for.
        if paymentMethods.isEmpty { added.isDefault = true }
        if added.isDefault {
            for index in paymentMethods.indices { paymentMethods[index].isDefault = false }
        }
        paymentMethods.append(added)
        toast = "\(added.label) added."
        scheduleSave()
    }

    func removePaymentMethod(_ id: UUID) {
        guard let index = paymentMethods.firstIndex(where: { $0.id == id }) else { return }
        let wasDefault = paymentMethods[index].isDefault
        let removed = paymentMethods.remove(at: index)
        // Something has to be the default, or the review step has nothing to
        // preselect and the customer gets asked to pick on every booking.
        if wasDefault, !paymentMethods.isEmpty, !paymentMethods.contains(where: \.isDefault) {
            paymentMethods[0].isDefault = true
        }
        toast = "\(removed.label) removed."
        scheduleSave()
    }

    func makeDefault(paymentMethod id: UUID) {
        for index in paymentMethods.indices {
            paymentMethods[index].isDefault = paymentMethods[index].id == id
        }
        scheduleSave()
    }

    func toggleFavorite(_ helperID: UUID) {
        if profile.favoriteHelperIDs.contains(helperID) {
            profile.favoriteHelperIDs.remove(helperID)
        } else {
            profile.favoriteHelperIDs.insert(helperID)
        }
        scheduleSave()
    }

    /// Saves edited personal details. Writes straight through to the shared
    /// store, so the helper app sees the corrected name on its next read rather
    /// than still asking for whoever you used to be.
    func updateProfile(name: String, phone: String, email: String) {
        let clean = ProfileEditing.normalised(name: name, phone: phone, email: email)
        guard ProfileEditing.isValid(name: clean.name, phone: clean.phone, email: clean.email) else { return }
        profile.name = clean.name
        profile.phone = clean.phone
        profile.email = clean.email
        toast = "Details updated."
        scheduleSave()
    }

    func completeOnboarding(name: String, phone: String) {
        profile.name = name.isEmpty ? profile.name : name
        profile.phone = phone.isEmpty ? profile.phone : phone
        hasOnboarded = true
        scheduleSave()
    }

    // MARK: The clock

    /// Walks every live job forward. Status is always derived from the plan
    /// rather than nudged along by hand, so a job that was running when the app
    /// was killed picks up exactly where it should.
    func tick() {
        now = Date()
        // Adopt the helper app's work before deriving anything from it, so an
        // accept that landed a moment ago is already in hand this pass.
        adoptExternalChanges()
        escalateStaleSearches()
        var changed = false

        for index in jobs.indices {
            // A scheduled booking goes live once its helper would need to leave.
            if jobs[index].status == .scheduled,
               let helper = jobs[index].helper {
                let travel = Dispatch.travelMinutes(from: helper.basePoint, to: jobs[index].address.point)
                let lead = Scheduling.leadSeconds(travelMinutes: travel, timeScale: timeScale)
                let launchAt = jobs[index].startsAt.addingTimeInterval(-lead)
                if now >= launchAt {
                    var launching = jobs[index]
                    launching.status = .accepted
                    launching.dispatch = makePlan(for: launching, helper: helper, acceptedAt: launchAt)
                    launching.events.append(JobEvent(at: launchAt, status: .accepted, note: "\(helper.displayName) is starting out"))
                    jobs[index] = launching
                    changed = true
                }
            }

            guard let plan = jobs[index].dispatch, !jobs[index].status.isFinished else { continue }
            let next = plan.status(at: now)
            guard next != jobs[index].status else { continue }

            jobs[index].status = next
            jobs[index].events.append(JobEvent(at: now, status: next, note: eventNote(for: next, job: jobs[index])))
            if let message = backend.systemVoiceMessage(for: next, job: jobs[index]) {
                jobs[index].messages.append(message)
            }
            if next == .completed { finish(jobAt: index, plan: plan) }
            changed = true
        }

        if changed { scheduleSave() }
    }

    private func eventNote(for status: JobStatus, job: Job) -> String {
        switch status {
        case .enRoute: "Left for \(job.address.oneLine)"
        case .arrived: "Arrived at \(job.address.oneLine)"
        case .inProgress: "Started work"
        case .completed: "Job completed"
        default: status.title
        }
    }

    private func finish(jobAt index: Int, plan: DispatchPlan) {
        let billed = plan.jobMinutes
        var finished = jobs[index]
        finished.billedMinutes = billed
        finished.finalTotal = Pricing.settle(finished.quote, billedMinutes: billed).total
        jobs[index] = finished
        if trackingJobID == finished.id { trackingJobID = nil }
        ratingJobID = finished.id
    }

    // MARK: Demo tools

    /// Pulls a scheduled job's start time in so its timeline plays out now.
    func fastForward(jobID: UUID) {
        guard let index = index(of: jobID), jobs[index].status == .scheduled,
              let helper = jobs[index].helper else { return }
        let travel = Dispatch.travelMinutes(from: helper.basePoint, to: jobs[index].address.point)
        let lead = Scheduling.leadSeconds(travelMinutes: travel, timeScale: timeScale)
        jobs[index].timing = .scheduled(start: Date().addingTimeInterval(lead))
        toast = "Pulled \(jobs[index].title) forward."
        scheduleSave()
    }

    /// Drops a running job's remaining work so completion and rating can be
    /// checked without waiting the job out.
    func finishNow(jobID: UUID) {
        guard let index = index(of: jobID), var plan = jobs[index].dispatch else { return }
        let now = Date()
        plan.acceptedAt = now.addingTimeInterval(
            -(plan.confirmMinutes + Double(plan.travelMinutes) + plan.greetMinutes + Double(plan.jobMinutes)) * plan.timeScale
        )
        jobs[index].dispatch = plan
        tick()
    }

    func resetDemo() {
        jobs = MockData.seedJobs()
        profile = MockData.profile
        addresses = MockData.addresses
        paymentMethods = MockData.paymentMethods
        matching = [:]
        matchingJobID = nil
        trackingJobID = nil
        ratingJobID = nil
        draft = nil
        timeScale = Dispatch.demoTimeScale
        backend.simulateNoHelpers = false
        PhotoStore.shared.wipe()
        toast = "Demo data reset."
        scheduleSave()
    }

    // MARK: Persistence

    /// Pulls in anything the helper app has written since our last read — an
    /// accepted job, a status the helper advanced, a completion.
    private func adoptExternalChanges() {
        guard let disk = Persistence.load(), disk.revision != lastRevision else { return }
        lastRevision = disk.revision

        // Compare statuses before and after rather than asking "did this become
        // live" — `.searching` is already a live status, so that test could never
        // fire for the one case that matters, a request being accepted.
        let before = Dictionary(jobs.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        jobs = disk.jobs
        profile = disk.profile
        addresses = disk.addresses
        paymentMethods = disk.paymentMethods

        for job in jobs where before[job.id] != job.status {
            // The request we were watching just got taken by a real helper.
            if matchingJobID == job.id, job.status != .searching {
                matchingJobID = nil
                matching[job.id] = nil
                if job.status.isLive {
                    trackingJobID = job.id
                    toast = "\(job.helper?.displayName ?? "A helper") accepted."
                }
            }
            // The helper finished it from their side.
            if job.status == .completed, job.rating == nil {
                if trackingJobID == job.id { trackingJobID = nil }
                if ratingJobID == nil, draft == nil { ratingJobID = job.id }
            }
        }
    }

    /// A request left waiting on a real helper who never tapped Accept falls back
    /// to the simulated dispatcher rather than sitting there indefinitely.
    private func escalateStaleSearches() {
        for job in jobs where job.status == .searching {
            guard let progress = matching[job.id],
                  progress.awaitingLiveHelpers > 0,
                  let since = progress.awaitingSince,
                  now.timeIntervalSince(since) > Self.liveHelperGrace
            else { continue }

            matching[job.id]?.awaitingLiveHelpers = 0
            matching[job.id]?.awaitingSince = nil
            let id = job.id
            Task { await runMatching(for: id, forceSimulated: true) }
        }
    }

    /// How many real helper apps are online and could take this category.
    func liveHelperCount(for category: HelpCategory) -> Int {
        guard let disk = Persistence.load() else { return 0 }
        let online = disk.onlineHelperIDs(now: now)
        return backend.roster.filter { online.contains($0.id) && $0.handles(category) }.count
    }

    /// Debounced — the ticker touches state every second and none of that is
    /// worth a disk write on its own.
    ///
    /// Writes are a merge rather than a wholesale overwrite: the helper app owns
    /// `helperHeartbeats`, and stamping our copy over the file would knock every
    /// online helper offline once a second.
    private func scheduleSave() {
        saveTask?.cancel()
        let hasOnboarded = hasOnboarded
        let profile = profile
        let addresses = addresses
        let paymentMethods = paymentMethods
        let jobs = jobs
        let timeScale = timeScale

        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let written = SharedStore.mutate { disk in
                disk.hasOnboarded = hasOnboarded
                disk.profile = profile
                disk.addresses = addresses
                disk.paymentMethods = paymentMethods
                disk.jobs = jobs
                disk.timeScale = timeScale
            }
            self?.lastRevision = written.revision
        }
    }
}
