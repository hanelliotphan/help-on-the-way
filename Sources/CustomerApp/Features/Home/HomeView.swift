import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session

    @State private var addressID: UUID?

    private var address: SavedAddress {
        session.addresses.first { $0.id == addressID } ?? session.homeAddress
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(session.liveJobs) { job in
                    liveBanner(job)
                }
                ForEach(session.jobs.filter { $0.status == .unmatched }) { job in
                    unmatchedBanner(job)
                }

                modeChooser
                categories

                if !session.upcomingJobs.isEmpty { upcoming }

                nearby
                if !rebookable.isEmpty { rebook }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Palette.canvas)
        // Inline rather than a large title: a greeting is not worth a third of
        // the first screen, and the categories should be visible on arrival.
        .navigationTitle(greeting)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addressMenu
            }
        }
        .onAppear { if addressID == nil { addressID = session.homeAddress.id } }
    }

    private var greeting: String {
        let first = session.profile.name.split(separator: " ").first.map(String.init)
        let hour = Calendar.current.component(.hour, from: session.now)
        let part = hour < 12 ? "Morning" : (hour < 18 ? "Afternoon" : "Evening")
        return first.map { "\(part), \($0)" } ?? part
    }

    // MARK: Address

    private var addressMenu: some View {
        Menu {
            Picker("Address", selection: Binding(
                get: { addressID ?? session.homeAddress.id },
                set: { addressID = $0 }
            )) {
                ForEach(session.addresses) { saved in
                    Label(saved.label, systemImage: saved.symbol).tag(saved.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: address.symbol)
                    .font(.caption)
                Text(address.label)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
    }

    // MARK: Live work

    private func liveBanner(_ job: Job) -> some View {
        Button {
            // A job still out for bids belongs on the matching screen — that's
            // where the search, and any counter-offer, actually lives. Tracking
            // has nothing to draw until somebody has accepted.
            if job.status == .searching {
                session.matchingJobID = job.id
            } else {
                session.trackingJobID = job.id
            }
        } label: {
            Card(spacing: 12, background: Palette.accent) {
                HStack(spacing: 10) {
                    Image(systemName: job.status.symbol)
                        .font(.subheadline.weight(.bold))
                    Text(job.status.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                    Spacer()
                    if let plan = job.dispatch, job.status == .enRoute || job.status == .accepted {
                        Text(Format.eta(minutes: plan.etaMinutes(at: session.now)))
                            .font(.caption.weight(.semibold))
                    } else if let plan = job.dispatch, job.status == .inProgress {
                        Text("\(Format.duration(minutes: plan.workRemainingMinutes(at: session.now))) left")
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))

                HStack(spacing: 12) {
                    if let helper = job.helper {
                        Avatar(helper: helper, size: 44, ring: true)
                    } else {
                        ZStack {
                            Circle().fill(.white.opacity(0.22)).frame(width: 44, height: 44)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.helper?.displayName ?? "Asking nearby helpers")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(job.title)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let plan = job.dispatch, job.status == .enRoute {
                    ProgressView(value: plan.travelFraction(at: session.now))
                        .tint(.white)
                } else if let plan = job.dispatch, job.status == .inProgress {
                    ProgressView(value: plan.workFraction(at: session.now))
                        .tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func unmatchedBanner(_ job: Job) -> some View {
        Card(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger)
                Text("Nobody took \(job.title.lowercased())")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text("All the \(job.category.title.lowercased()) helpers near \(job.address.label) are busy. Try again, or book a time instead.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                QuietButton(title: "Ask again", symbol: "arrow.clockwise") {
                    session.retryMatching(jobID: job.id)
                }
                QuietButton(title: "Cancel", symbol: "xmark", tint: Palette.danger) {
                    session.cancel(jobID: job.id, reason: "No helper available")
                }
            }
        }
    }

    // MARK: Now vs later

    /// Two rows in one card rather than two tinted tiles side by side. The
    /// choice between now and later is a list of two options, and looks like it.
    private var modeChooser: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                modeRow(
                    title: "Get help now",
                    detail: "Sent to every helper nearby at once",
                    symbol: "bolt.fill",
                    tint: Palette.instant
                ) { session.startRequest(instant: true) }

                Divider().padding(.leading, 42)

                modeRow(
                    title: "Schedule for later",
                    detail: "Pick a time, and the person",
                    symbol: "calendar",
                    tint: Palette.planned
                ) { session.startRequest(instant: false) }
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
            )

            demandStrip
        }
    }

    private func modeRow(title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func modeCard(title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    /// One line, no card. It's an ambient status note, not a control.
    private var demandStrip: some View {
        let demand = session.demand(for: .handyman, at: address.point)
        return HStack(spacing: 6) {
            Image(systemName: demand.isSurging ? "arrow.up.right" : "checkmark.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(demand.isSurging ? Palette.instant : Palette.success)
            Text(demand.blurb)
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
            // The address used to sit on this line and both halves ended up
            // truncated. The toolbar already names the place, so it goes.
        }
        .padding(.horizontal, 2)
    }

    // MARK: Categories

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What needs doing?")
            // Four across, monochrome, no rate on the tile — the rate belongs in
            // the quote, not on a launcher.
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 8), count: 4), spacing: 8) {
                ForEach(HelpCategory.allCases) { category in
                    Button {
                        session.startRequest(category: category, instant: category.supportsInstant)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Palette.ink)
                                .frame(height: 20)
                            Text(category.shortTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Upcoming

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coming up", actionTitle: "All") { session.selectedTab = .activity }
            VStack(spacing: 0) {
                ForEach(session.upcomingJobs.prefix(2)) { job in
                    NavigationLink { JobDetailView(jobID: job.id) } label: {
                        HStack(spacing: 12) {
                            VStack(spacing: 1) {
                                Text(job.startsAt.formatted(.dateTime.day()))
                                    .font(.headline)
                                Text(job.startsAt.formatted(.dateTime.month(.abbreviated)))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(Format.window(job.startsAt, minutes: job.quote.minutes)) · \(job.helper?.displayName ?? "Assigning")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if job.id != session.upcomingJobs.prefix(2).last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Nearby helpers

    private var nearbyMatches: [HelperMatch] {
        Matching.candidates(
            for: .handyman, near: address.point, in: session.backend.roster,
            favorites: session.profile.favoriteHelperIDs, withinMiles: 30
        )
        // The home rail isn't category-specific, so rank the whole roster.
        + Matching.candidates(
            for: .cleaning, near: address.point, in: session.backend.roster,
            favorites: session.profile.favoriteHelperIDs, withinMiles: 30
        )
    }

    private var nearby: some View {
        let unique = nearbyMatches.reduce(into: [HelperMatch]()) { result, match in
            if !result.contains(where: { $0.id == match.id }) { result.append(match) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Helpers near \(address.label)", detail: "\(unique.count) available today")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    ForEach(unique.prefix(8)) { match in
                        NavigationLink { HelperProfileView(helper: match.helper) } label: {
                            helperCard(match)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink { BrowseHelpersView(category: .handyman) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Palette.accent)
                            Text("Browse all")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(width: 96)
                        // Stretches to whatever the helper cards come out at,
                        // now that their height is driven by content.
                        .frame(maxHeight: .infinity)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    private func helperCard(_ match: HelperMatch) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Avatar(helper: match.helper, size: 42)
                Spacer()
                if match.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.danger)
                }
            }
            Text(match.helper.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.96, green: 0.71, blue: 0.12))
                Text(Format.rating(match.helper.rating))
                    .font(.caption.weight(.semibold))
            }
            Text(match.helper.skills.prefix(2).map(\.shortTitle).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Format.rate(match.helper.hourlyRate))
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.accent)
        }
        .padding(12)
        // Width is fixed, height is not. Pinning a height *after* padding meant
        // taller content simply overflowed it, and the background — sized to the
        // frame — stopped short, leaving the rate sitting outside the card.
        // Every line here is capped at one, so the cards still match.
        .frame(width: 150, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
        )
    }

    // MARK: Rebook

    private var rebookable: [Job] {
        session.pastJobs.filter { $0.status == .completed }.prefix(3).map(\.self)
    }

    private var rebook: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Book it again", detail: "Same job, same helper, new date")
            VStack(spacing: 10) {
                ForEach(rebookable) { job in
                    Card(padding: 13, spacing: 10) {
                        HStack(spacing: 11) {
                            if let helper = job.helper {
                                Avatar(helper: helper, size: 38)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(job.helper?.displayName ?? "") · \(Format.ago(job.createdAt, now: session.now))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Button("Rebook") { rebook(job) }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                }
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
