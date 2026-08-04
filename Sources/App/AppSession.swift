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

    init(backend: DemoBackend? = nil, snapshot: StoreSnapshot? = Persistence.load()) {
        self.backend = backend ?? DemoBackend()
        if let snapshot {
            hasOnboarded = snapshot.hasOnboarded
            profile = snapshot.profile
            addresses = snapshot.addresses
            paymentMethods = snapshot.paymentMethods
            jobs = snapshot.jobs
            timeScale = snapshot.timeScale
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

    /// Consumes the dispatcher's stream for an instant request.
    func runMatching(for jobID: UUID) async {
        guard let job = job(jobID) else { return }
        for await update in backend.match(job: job, favorites: profile.favoriteHelperIDs) {
            guard let index = index(of: jobID) else { return }
            // A cancel while we were waiting wins over anything the stream says.
            guard jobs[index].status == .searching else { return }

            switch update {
            case .broadcasting(let count):
                matching[jobID, default: MatchingProgress()].pinged = count
            case .declined(let helper):
                matching[jobID, default: MatchingProgress()].declined.append(helper)
            case .accepted(let helper):
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
        jobs[index].rating = rating
        if rating.tip > 0 {
            jobs[index].finalTotal = (jobs[index].finalTotal ?? jobs[index].quote.total) + rating.tip
        }
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
        var changed = false

        for index in jobs.indices {
            // A scheduled booking goes live once its helper would need to leave.
            if jobs[index].status == .scheduled,
               let helper = jobs[index].helper {
                let travel = Dispatch.travelMinutes(from: helper.basePoint, to: jobs[index].address.point)
                let lead = Scheduling.leadSeconds(travelMinutes: travel, timeScale: timeScale)
                let launchAt = jobs[index].startsAt.addingTimeInterval(-lead)
                if now >= launchAt {
                    jobs[index].status = .accepted
                    jobs[index].dispatch = makePlan(for: jobs[index], helper: helper, acceptedAt: launchAt)
                    jobs[index].events.append(JobEvent(at: launchAt, status: .accepted, note: "\(helper.displayName) is starting out"))
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
        jobs[index].billedMinutes = billed
        jobs[index].finalTotal = Pricing.settle(jobs[index].quote, billedMinutes: billed).total
        if trackingJobID == jobs[index].id { trackingJobID = nil }
        ratingJobID = jobs[index].id
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

    var snapshot: StoreSnapshot {
        StoreSnapshot(
            hasOnboarded: hasOnboarded,
            profile: profile,
            addresses: addresses,
            paymentMethods: paymentMethods,
            jobs: jobs,
            timeScale: timeScale
        )
    }

    /// Debounced — the ticker touches state every second and none of that is
    /// worth a disk write on its own.
    private func scheduleSave() {
        saveTask?.cancel()
        let pending = snapshot
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            Persistence.save(pending)
        }
    }
}
