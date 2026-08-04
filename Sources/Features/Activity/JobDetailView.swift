import SwiftUI

struct JobDetailView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var showingCancel = false
    @State private var cancelReason = ""

    private var job: Job? { session.job(jobID) }

    var body: some View {
        ScrollView {
            if let job {
                VStack(spacing: 14) {
                    header(job)
                    if let helper = job.helper { helperCard(job, helper: helper) }
                    detailsCard(job)
                    if !job.events.isEmpty { timelineCard(job) }
                    receiptCard(job)
                    if let rating = job.rating, rating.stars > 0 { ratingCard(rating) }
                    actions(job)
                }
                .padding(16)
            } else {
                EmptyBlock(symbol: "questionmark.circle", title: "Not found", message: "This job is no longer on file.")
            }
        }
        .background(Palette.canvas)
        .navigationTitle(job?.title ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cancel this job?", isPresented: $showingCancel) {
            TextField("Reason (optional)", text: $cancelReason)
            Button("Cancel job", role: .destructive) {
                session.cancel(jobID: jobID, reason: cancelReason.isEmpty ? "Cancelled by customer" : cancelReason)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            if let job { Text(Cancellation.explanation(for: job, now: session.now)) }
        }
    }

    private func header(_ job: Job) -> some View {
        Card(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Palette.tint(for: job.status).opacity(0.16))
                    Image(systemName: job.category.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.tint(for: job.status))
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.headline)
                    HStack(spacing: 5) {
                        Image(systemName: job.status.symbol)
                            .font(.caption2)
                        Text(job.status.title)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Palette.tint(for: job.status))
                }
                Spacer(minLength: 0)
            }

            Divider()

            LabeledRow(
                label: job.timing.isInstant ? "Requested" : "Scheduled",
                value: job.timing.isInstant
                    ? Format.slot(job.createdAt, now: session.now)
                    : "\(Format.day(job.startsAt, now: session.now)), \(Format.window(job.startsAt, minutes: job.quote.minutes))",
                symbol: job.timing.isInstant ? "bolt.fill" : "calendar",
                tint: Palette.tint(for: job.timing)
            )
            LabeledRow(
                label: "Duration",
                value: job.billedMinutes.map { billed in
                    billed == job.quote.minutes
                        ? Format.duration(minutes: billed)
                        : "\(Format.duration(minutes: billed)) (booked \(Format.duration(minutes: job.estimatedMinutes)))"
                } ?? Format.duration(minutes: job.quote.minutes),
                symbol: "clock"
            )
            LabeledRow(label: "Address", value: job.address.oneLine, symbol: job.address.symbol)
            if let reason = job.cancellationReason {
                LabeledRow(label: "Cancelled", value: reason, symbol: "xmark.circle.fill", tint: Palette.danger)
            }
        }
    }

    private func helperCard(_ job: Job, helper: Helper) -> some View {
        Card(spacing: 11) {
            NavigationLink { HelperProfileView(helper: helper) } label: {
                HStack(spacing: 12) {
                    Avatar(helper: helper, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(helper.displayName)
                                .font(.subheadline.weight(.semibold))
                            if job.helperWasChosen {
                                Chip(text: "Your pick", tint: Palette.accent)
                            }
                        }
                        HStack(spacing: 5) {
                            Stars(value: helper.rating, size: 10)
                            Text("\(Format.rating(helper.rating)) · \(Format.rate(helper.hourlyRate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if !job.messages.isEmpty || job.status.isLive {
                Divider()
                NavigationLink { ChatView(jobID: job.id) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Palette.accent)
                        Text(job.messages.last?.body ?? "Start a conversation")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if job.unreadFromHelper > 0 {
                            Text("\(job.unreadFromHelper)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.danger, in: Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detailsCard(_ job: Job) -> some View {
        Card(spacing: 10) {
            Text("What was asked for")
                .font(.subheadline.weight(.semibold))
            Text(job.notes.isEmpty ? "No extra notes." : job.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !job.photoNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.photoNames, id: \.self) { name in
                            JobPhotoView(name: name)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func timelineCard(_ job: Job) -> some View {
        Card(spacing: 11) {
            Text("What happened")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 9) {
                ForEach(job.events) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.status.symbol)
                            .font(.caption)
                            .foregroundStyle(Palette.tint(for: event.status))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.note)
                                .font(.footnote)
                            Text(Format.time(event.at))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func receiptCard(_ job: Job) -> some View {
        let settled = job.billedMinutes.map { Pricing.settle(job.quote, billedMinutes: $0) } ?? job.quote
        return Card(spacing: 11) {
            HStack {
                Text(job.status == .completed ? "Receipt" : "Estimate")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let method = session.paymentMethods.first(where: { $0.id == job.paymentMethodID }) {
                    Chip(text: method.label, symbol: method.symbol, tint: .secondary)
                }
            }
            QuoteTable(quote: settled)
            if let rating = job.rating, rating.tip > 0 {
                Divider()
                HStack {
                    Text("Tip")
                        .font(.subheadline)
                    Spacer()
                    Text(rating.tip.currency)
                        .font(.subheadline.weight(.semibold))
                }
                HStack {
                    Text("Charged")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text((settled.total + rating.tip).currency)
                        .font(.subheadline.weight(.bold))
                }
            }
            if job.status == .cancelled {
                Text(job.amountDue == .zero
                     ? "Nothing was charged."
                     : "\(job.amountDue.currency) trip fee charged; the rest was released.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ratingCard(_ rating: JobRating) -> some View {
        Card(spacing: 9) {
            HStack {
                Text("Your rating")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Stars(value: Double(rating.stars), size: 13)
            }
            if !rating.compliments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(rating.compliments, id: \.self) { item in
                        Chip(text: item, tint: Palette.success)
                    }
                }
            }
            if !rating.comment.isEmpty {
                Text("“\(rating.comment)”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actions(_ job: Job) -> some View {
        VStack(spacing: 10) {
            switch job.status {
            case .searching:
                BigButton(title: "Watch the search", symbol: "dot.radiowaves.left.and.right", tint: Palette.instant) {
                    session.matchingJobID = job.id
                }
                QuietButton(title: "Cancel request", symbol: "xmark", tint: Palette.danger) { showingCancel = true }
            case .unmatched:
                BigButton(title: "Ask again", symbol: "arrow.clockwise", tint: Palette.instant) {
                    session.retryMatching(jobID: job.id)
                }
                QuietButton(title: "Cancel request", symbol: "xmark", tint: Palette.danger) { showingCancel = true }
            case .accepted, .enRoute, .arrived, .inProgress:
                BigButton(title: "Track live", symbol: "location.fill") { session.trackingJobID = job.id }
                QuietButton(title: "Cancel this job", symbol: "xmark", tint: Palette.danger) { showingCancel = true }
            case .scheduled:
                QuietButton(title: "Message \(job.helper?.firstName ?? "helper")", symbol: "bubble.left.fill") {}
                    .disabled(job.helper == nil)
                QuietButton(title: "Cancel booking", symbol: "xmark", tint: Palette.danger) { showingCancel = true }
            case .completed:
                if job.rating == nil {
                    BigButton(title: "Rate this job", symbol: "star.fill") { session.ratingJobID = job.id }
                }
                QuietButton(title: "Book this again", symbol: "arrow.clockwise") { rebook(job) }
            case .cancelled:
                QuietButton(title: "Book this again", symbol: "arrow.clockwise") { rebook(job) }
            }
        }
    }

    private func rebook(_ job: Job) {
        let draft = RequestDraft(
            category: job.category,
            address: job.address,
            wantsInstant: false,
            startingAt: .timing,
            now: session.now
        )
        draft.title = job.title
        draft.notes = job.notes
        draft.setMinutes(job.estimatedMinutes, now: session.now)
        draft.chosenHelper = job.helper
        draft.paymentMethod = session.defaultPaymentMethod
        session.draft = draft
    }
}
