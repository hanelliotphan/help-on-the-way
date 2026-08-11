import SwiftUI

/// The shift screen. Offline it's a switch; online it's a queue; mid-job it hands
/// straight over to the job itself.
struct DriveView: View {
    @Environment(HelperSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                onlineCard

                if let active = session.activeJob {
                    activeCard(active)
                } else if !session.isOnline {
                    EmptyBlock(
                        symbol: "moon.zzz.fill",
                        title: "You're offline",
                        message: "Go online and instant requests near you will come through here."
                    )
                } else if session.offers.isEmpty {
                    waiting
                } else {
                    ForEach(session.offers) { offer in
                        OfferCard(job: offer)
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle(session.me?.firstName ?? "Drive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let me = session.me {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(session.isOnline ? Palette.success : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(Format.rating(me.rating))
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.96, green: 0.71, blue: 0.12))
                    }
                }
            }
        }
    }

    // MARK: Online switch

    /// A shift switch wants to be a big deliberate target, not a 51-point
    /// toggle — this is the button a helper hits with a thumb while holding a
    /// toolbox, so it gets the whole width of the card.
    private var onlineCard: some View {
        Card(spacing: 12, background: session.isOnline ? Palette.helper : Palette.card) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(session.isOnline ? Color.white.opacity(0.2) : Palette.helperSoft)
                    Image(systemName: session.isOnline ? "bolt.fill" : "bolt.slash.fill")
                        .font(.headline)
                        .foregroundStyle(session.isOnline ? .white : Palette.helper)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isOnline ? "Online" : "Offline")
                        .font(.headline)
                        .foregroundStyle(session.isOnline ? .white : .primary)
                    Text(session.isOnline
                         ? "Taking instant requests near you"
                         : "Not receiving anything right now")
                        .font(.caption)
                        .foregroundStyle(session.isOnline ? .white.opacity(0.85) : .secondary)
                }
                Spacer(minLength: 4)
            }

            Button {
                session.setOnline(!session.isOnline)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: session.isOnline ? "pause.fill" : "bolt.fill")
                    Text(session.isOnline ? "Go offline" : "Go online")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(session.isOnline ? Palette.helper : .white)
                .background(
                    session.isOnline ? Color.white : Palette.helper,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if session.isOnline, !session.isSharedStore {
                Text("Running unlinked — the customer app can't see this device.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(0..<2, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Palette.helper.opacity(0.3), lineWidth: 2)
                        .frame(width: 74, height: 74)
                        .scaleEffect(pulse ? 2.0 : 0.8)
                        .opacity(pulse ? 0 : 0.85)
                        .animation(
                            .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(ring) * 1.1),
                            value: pulse
                        )
                }
                Circle()
                    .fill(Palette.helperSoft)
                    .frame(width: 84, height: 84)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Palette.helper)
            }
            .frame(height: 150)

            Text("Waiting for requests")
                .font(.headline)
            Text("Open the customer app and ask for help now — it'll show up here to accept.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .onAppear { pulse = true }
    }

    @State private var pulse = false

    // MARK: Mid-job

    private func activeCard(_ job: Job) -> some View {
        NavigationLink {
            ActiveJobView(jobID: job.id)
        } label: {
            Card(spacing: 12, background: Palette.helper) {
                HStack(spacing: 8) {
                    Image(systemName: job.status.symbol)
                        .font(.subheadline.weight(.bold))
                    Text(job.status.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                    Spacer()
                    Text(Payout.offerPay(for: job).currency)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.92))

                Text(job.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)

                Text(job.address.oneLine)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                HStack {
                    Text(nextActionTitle(job))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func nextActionTitle(_ job: Job) -> String {
        switch job.status {
        case .accepted: "Start driving"
        case .enRoute: "I've arrived"
        case .arrived: "Start work"
        case .inProgress: "Complete job"
        default: "Open"
        }
    }
}

/// One incoming request. Reads like a driver-app offer: what it pays first, then
/// how far and how long, then what the job actually is.
struct OfferCard: View {
    @Environment(HelperSession.self) private var session
    let job: Job

    @State private var showingCounter = false
    @State private var counterRate: Decimal = .zero

    /// Only a job whose rate the customer named can be haggled over. A standard
    /// category rate isn't up for discussion.
    private var isNegotiable: Bool {
        job.negotiation?.isSettled == false
    }

    private var offeredRate: Decimal {
        job.negotiation?.customerFacingRate ?? job.quote.hourlyRate
    }

    var body: some View {
        Card(spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Payout.offerPay(for: job).currency)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("your take, before tip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Chip(text: job.category.shortTitle, symbol: job.category.symbol, tint: Palette.helper)
                    if job.quote.isSurging {
                        Chip(text: "Busy area", symbol: "chart.line.uptrend.xyaxis", tint: Palette.instant)
                    }
                    if isNegotiable {
                        Chip(text: "Their price", symbol: "tag.fill", tint: Palette.instant)
                    }
                }
            }

            if isNegotiable, let me = session.me {
                // The comparison that decides it: their number against yours.
                HStack(spacing: 8) {
                    Image(systemName: offeredRate >= me.hourlyRate ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(offeredRate >= me.hourlyRate ? Palette.success : Palette.instant)
                    Text(offeredRate >= me.hourlyRate
                         ? "\(Format.rate(offeredRate)) offered — at or above your \(Format.rate(me.hourlyRate))."
                         : "\(Format.rate(offeredRate)) offered — you usually get \(Format.rate(me.hourlyRate)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 0) {
                StatBlock(value: Format.distance(session.miles(to: job)), caption: "away", symbol: "location.fill")
                Divider().frame(height: 38)
                StatBlock(value: "\(session.minutesAway(from: job)) min", caption: "drive", symbol: "car.fill")
                Divider().frame(height: 38)
                StatBlock(value: Format.compactDuration(minutes: job.quote.minutes), caption: "on site", symbol: "clock.fill")
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                if !job.notes.isEmpty {
                    Text(job.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    Image(systemName: job.address.symbol)
                        .font(.caption2)
                    Text(job.address.oneLine)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if !job.photoNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.photoNames, id: \.self) { name in
                            JobPhotoView(name: name)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    session.decline(job)
                } label: {
                    Text("Pass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.secondary)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if isNegotiable {
                    Button {
                        counterRate = session.suggestedCounter(for: job) ?? offeredRate
                        showingCounter = true
                    } label: {
                        Text("Counter")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundStyle(Palette.instant)
                            .background(Palette.instantSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    session.accept(job)
                } label: {
                    Text("Accept")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(Palette.helper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingCounter) {
            counterSheet
                .presentationDetents([.medium])
        }
    }

    private var counterSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("They're offering \(Format.rate(offeredRate)) for \(Format.duration(minutes: job.quote.minutes)). Name your rate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    Button { counterRate -= Negotiation.step } label: {
                        Image(systemName: "minus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .background(Palette.helperSoft, in: Circle())
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
                            .background(Palette.helperSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Palette.helper)

                if let issue = Negotiation.issue(offering: counterRate, in: job.negotiation) {
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(((counterRate - offeredRate) * Decimal(job.quote.minutes) / 60).roundedToCents().currency) more than they offered, over the whole job.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                BigButton(
                    title: "Send \(Format.rate(counterRate))",
                    symbol: "paperplane.fill",
                    tint: Palette.helper,
                    isEnabled: Negotiation.isValid(offering: counterRate, in: job.negotiation)
                ) {
                    showingCounter = false
                    session.counter(job, rate: counterRate)
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
}
