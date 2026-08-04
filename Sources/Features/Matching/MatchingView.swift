import SwiftUI

/// The wait. An instant request goes out to everyone nearby at once, so this
/// screen shows who was asked and what they said rather than a spinner.
struct MatchingView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var pulse = false
    @State private var showingCancel = false

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
            Text(progress.failed ? "Nobody's free right now" : "Asking \(max(progress.pinged, 1)) helpers nearby")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(progress.failed
                 ? "Every \(job?.category.title.lowercased() ?? "") helper near you is mid-job. Booking a time gets you the same people at a lower rate."
                 : "They see your notes, your address and what it pays. First one to take it is yours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
