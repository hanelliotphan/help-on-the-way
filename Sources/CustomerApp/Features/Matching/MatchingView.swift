import SwiftUI

/// The wait. An instant request goes out to everyone nearby at once, so this
/// screen shows who was asked and what they said rather than a spinner.
struct MatchingView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var pulse = false
    @State private var showingCancel = false
    @State private var showingCounter = false
    @State private var counterRate: Decimal = .zero

    private var job: Job? { session.job(jobID) }
    private var progress: MatchingProgress { session.matching[jobID] ?? MatchingProgress() }

    private var candidates: [HelperMatch] {
        guard let job else { return [] }
        return Array(session.backend.candidates(
            for: job.category,
            near: job.address.point,
            favorites: session.profile.favoriteHelperIDs
        ).prefix(5))
    }

    private var elapsed: String {
        let seconds = Int(session.now.timeIntervalSince(progress.startedAt))
        return String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        radar
                        headline
                        if let job, let negotiation = job.negotiation, negotiation.awaitingCustomer {
                            counterCard(job, negotiation: negotiation)
                        }
                        if !candidates.isEmpty { candidateList }
                        if let job { jobRecap(job) }
                    }
                    .padding(20)
                }
                footer
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(progress.failed ? "No luck" : "Finding a helper · \(elapsed)")
                        .font(.subheadline.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hide") { session.matchingJobID = nil }
                        .font(.subheadline)
                }
            }
            .confirmationDialog("Cancel this request?", isPresented: $showingCancel, titleVisibility: .visible) {
                Button("Cancel request", role: .destructive) {
                    session.cancel(jobID: jobID, reason: "Cancelled while searching")
                }
                Button("Keep looking", role: .cancel) {}
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .sheet(isPresented: $showingCounter) {
            if let job, let negotiation = job.negotiation {
                counterSheet(job, negotiation: negotiation)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: Radar

    private var radar: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .strokeBorder(Palette.instant.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 2.3 : 0.7)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(ring) * 0.8),
                        value: pulse
                    )
            }

            Circle()
                .fill(progress.failed ? Palette.dangerSoft : Palette.instantSoft)
                .frame(width: 112, height: 112)

            Image(systemName: progress.failed ? "exclamationmark.triangle.fill" : (job?.category.symbol ?? "bolt.fill"))
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(progress.failed ? Palette.danger : Palette.instant)
        }
        .frame(height: 200)
    }

    private var headline: some View {
        VStack(spacing: 7) {
            Text(headlineTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(headlineDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if progress.awaitingLiveHelpers > 0 {
                Chip(text: "Live helper on shift", symbol: "person.wave.2.fill", tint: Palette.success)
                    .padding(.top, 2)
            }
        }
    }

    private var isHaggling: Bool {
        job?.negotiation?.awaitingCustomer == true
    }

    private var headlineTitle: String {
        if isHaggling { return "They want more per hour" }
        if progress.failed { return "Nobody's free right now" }
        if progress.awaitingLiveHelpers > 0 {
            return progress.awaitingLiveHelpers == 1
                ? "A helper is looking at this"
                : "\(progress.awaitingLiveHelpers) helpers are looking at this"
        }
        return "Asking \(max(progress.pinged, 1)) helpers nearby"
    }

    private var headlineDetail: String {
        if isHaggling {
            return "Your offer was under their rate. Nothing is booked and nothing is charged until you agree on a number."
        }
        if progress.failed {
            return "Every \(job?.category.title.lowercased() ?? "") helper near you is mid-job. Booking a time gets you the same people at a lower rate."
        }
        if progress.awaitingLiveHelpers > 0 {
            // Somebody is genuinely running the helper app, so the simulated
            // dispatcher has stood down and we're waiting on a real thumb.
            return "Somebody on shift has your request open in their app right now. Nothing is auto-assigned while they decide."
        }
        return "They see your notes, your address and what it pays. First one to take it is yours."
    }

    // MARK: The counter

    /// Somebody has answered the offered rate with a number of their own. Three
    /// ways out: take it, come back with another number, or walk.
    private func counterCard(_ job: Job, negotiation: RateNegotiation) -> some View {
        let counter = negotiation.latest
        let helper = counter.helperID.flatMap { id in session.backend.roster.first { $0.id == id } }
        let yours = negotiation.customerFacingRate
        let hours = Decimal(job.quote.minutes) / 60
        let extra = ((counter.rate - yours) * hours).roundedToCents()

        return Card(spacing: 13) {
            HStack(spacing: 11) {
                if let helper { Avatar(helper: helper, size: 42) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(helper?.displayName ?? "A helper") countered")
                        .font(.subheadline.weight(.semibold))
                    if let helper {
                        Text(Negotiation.rationale(for: counter.rate, helper: helper))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("You offered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Format.rate(yours))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 2) {
                    Text("They want")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Format.rate(counter.rate))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.instant)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 9)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(extra > 0
                 ? "That's \(extra.currency) more over \(Format.duration(minutes: job.quote.minutes))."
                 : "Same total over \(Format.duration(minutes: job.quote.minutes)).")
                .font(.caption)
                .foregroundStyle(.secondary)

            BigButton(title: "Accept \(Format.rate(counter.rate))", symbol: "checkmark", tint: Palette.success) {
                session.acceptCounter(jobID: jobID)
            }

            HStack(spacing: 10) {
                QuietButton(title: "Counter", symbol: "arrow.uturn.left", tint: Palette.instant) {
                    counterRate = midpoint(between: yours, and: counter.rate)
                    showingCounter = true
                }
                QuietButton(title: "Let it go", symbol: "xmark", tint: Palette.danger) {
                    session.declineCounter(jobID: jobID)
                }
            }
        }
    }

    private func midpoint(between mine: Decimal, and theirs: Decimal) -> Decimal {
        Negotiation.roundedToStep((mine + theirs) / 2)
    }

    private func counterSheet(_ job: Job, negotiation: RateNegotiation) -> some View {
        let theirs = negotiation.latest.rate

        return NavigationStack {
            VStack(spacing: 18) {
                Text("They asked \(Format.rate(theirs)). What's your number?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    Button { counterRate -= Negotiation.step } label: {
                        Image(systemName: "minus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Palette.instantSoft, in: Circle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 1) {
                        Text(counterRate.shortCurrency)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("per hour")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button { counterRate += Negotiation.step } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Palette.instantSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Palette.instant)

                if let issue = Negotiation.issue(offering: counterRate, in: negotiation) {
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                BigButton(
                    title: "Send \(Format.rate(counterRate))",
                    symbol: "paperplane.fill",
                    tint: Palette.instant,
                    isEnabled: Negotiation.isValid(offering: counterRate, in: negotiation)
                ) {
                    showingCounter = false
                    session.counterBack(jobID: jobID, rate: counterRate)
                }
            }
            .padding(20)
            .background(Palette.canvas)
            .navigationTitle("Your counter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showingCounter = false }
                }
            }
        }
    }

    // MARK: Who was asked

    private var candidateList: some View {
        Card(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, match in
                HStack(spacing: 11) {
                    Avatar(helper: match.helper, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(match.helper.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(Format.distance(match.miles)) · \(Format.rating(match.helper.rating))★")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    statusChip(for: match, index: index)
                }
                .opacity(hasDeclined(match) ? 0.45 : 1)
                .padding(.vertical, 8)

                if match.id != candidates.last?.id { Divider() }
            }
        }
    }

    private func hasDeclined(_ match: HelperMatch) -> Bool {
        progress.declined.contains { $0.id == match.helper.id }
    }

    private func statusChip(for match: HelperMatch, index: Int) -> some View {
        if hasDeclined(match) {
            Chip(text: "Passed", symbol: "xmark", tint: .secondary)
        } else if progress.failed {
            Chip(text: "Busy", symbol: "clock", tint: .secondary)
        } else if index < progress.pinged {
            Chip(text: "Asked", symbol: "dot.radiowaves.left.and.right", tint: Palette.instant)
        } else {
            Chip(text: "Queued", tint: .secondary)
        }
    }

    // MARK: Recap

    private func jobRecap(_ job: Job) -> some View {
        Card(spacing: 9) {
            LabeledRow(label: "Job", value: job.title, symbol: job.category.symbol)
            LabeledRow(label: "Where", value: job.address.oneLine, symbol: job.address.symbol)
            LabeledRow(label: "Estimate", value: "\(Format.duration(minutes: job.quote.minutes)) · \(job.quote.total.currency)", symbol: "clock")
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if progress.failed {
                BigButton(title: "Ask again", symbol: "arrow.clockwise", tint: Palette.instant) {
                    session.retryMatching(jobID: jobID)
                }
                QuietButton(title: "Book a time instead", symbol: "calendar", tint: Palette.planned) {
                    guard let job else { return }
                    session.cancel(jobID: jobID, reason: "Switched to a scheduled booking")
                    let draft = RequestDraft(
                        category: job.category, address: job.address,
                        wantsInstant: false, startingAt: .timing, now: session.now
                    )
                    draft.title = job.title
                    draft.notes = job.notes
                    draft.photoNames = job.photoNames
                    draft.setMinutes(job.estimatedMinutes, now: session.now)
                    draft.paymentMethod = session.defaultPaymentMethod
                    session.draft = draft
                }
            } else {
                Text("You're not charged until someone accepts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                QuietButton(title: "Cancel request", symbol: "xmark", tint: Palette.danger) {
                    showingCancel = true
                }
            }
        }
        .padding(16)
        .background(.bar)
    }
}
