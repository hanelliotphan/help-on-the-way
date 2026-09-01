import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session

    @State private var addressID: UUID?
    @State private var cachedNearby: [HelperMatch] = []
    @State private var cachedDemand: DemandIndex = .calm

    private var address: SavedAddress {
        session.addresses.first { $0.id == addressID } ?? session.homeAddress
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(session.liveJobs) { job in
                    LiveJobBanner(job: job)
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
        .navigationTitle(greeting)
        // Inline, not large. A large title spends ~90pt of every visit on a
        // word that never changes within the hour, and pushes the live-job
        // banner — the one thing you open this screen to check — off the fold.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addressMenu
            }
        }
        .onAppear { if addressID == nil { addressID = session.homeAddress.id } }
        .task(id: address.id) { refreshNeighbourhood() }
    }

    private var greeting: String {
        let first = session.profile.name.split(separator: " ").first.map(String.init)
        // Deliberately not `session.now`: this changes at hour boundaries, and
        // observing the per-second clock for it would drag the whole screen —
        // including the helper rail — into recomputing every tick.
        let hour = Calendar.current.component(.hour, from: Date())
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

    private var modeChooser: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                modeCard(
                    title: "Get help now",
                    detail: "Someone comes straight over",
                    symbol: "bolt.fill",
                    tint: Palette.instant
                ) { session.startRequest(instant: true) }

                modeCard(
                    title: "Schedule later",
                    detail: "Pick a time and a person",
                    symbol: "calendar.badge.clock",
                    tint: Palette.planned
                ) { session.startRequest(instant: false) }
            }
            demandStrip
        }
    }

    private func modeCard(title: String, detail: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle().fill(tint.opacity(0.16))
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var demandStrip: some View {
        let demand = cachedDemand
        return HStack(spacing: 8) {
            Image(systemName: demand.isSurging ? "chart.line.uptrend.xyaxis" : "person.2.fill")
                .font(.caption)
                .foregroundStyle(demand.isSurging ? Palette.instant : Palette.success)
            Text(demand.blurb)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // The demand notice is the point of this strip, so it gets its
                // full width first and the street absorbs any shortfall.
                .layoutPriority(1)
            Spacer(minLength: 8)
            // Street only. "street, city" never fit beside the surge line, so
            // the blurb wrapped to two lines *and* the address still truncated
            // mid-word. The city is already implied by everything around it.
            Text(address.street)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Categories

    /// A single scrolling row rather than a grid.
    ///
    /// Fourteen categories in a three-column grid is five stacked rows of tall
    /// tiles, which pushed everything worth seeing — live jobs, helpers nearby,
    /// rebooking — below the fold. A rail is how every delivery app does this,
    /// and for the same reason: browsing a catalogue is a sideways motion, and
    /// the vertical space belongs to what you actually came for.
    ///
    /// The rate comes off the rail too. It's a browsing control, not a price
    /// list, and the details step quotes the rate the moment you pick one.
    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What needs doing?", detail: "Swipe for more")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(HelpCategory.allCases) { category in
                        Button {
                            session.startRequest(category: category, instant: category.supportsInstant)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Palette.accentSoft)
                                        .frame(width: 56, height: 56)
                                    Image(systemName: category.symbol)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Palette.accent)
                                }
                                Text(category.shortTitle)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            // Fixed width keeps the labels on a shared baseline;
                            // without it "Seniors" and "Furniture Assembly" sit
                            // at different heights and the row looks ragged.
                            .frame(width: 66)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            // The rail bleeds to the screen edge so it reads as scrollable, while
            // the rest of the screen keeps its gutter.
            .padding(.horizontal, -16)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollClipDisabled()
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

    /// Recomputed when the address changes, not on every body pass. Each call
    /// below allocates a pair of `CLLocation`s per helper for the distance, and
    /// `travelMinutes` allocates two more — cheap once, wasteful at 1Hz.
    private func refreshNeighbourhood() {
        cachedNearby = uniqueNearby
        cachedDemand = session.demand(for: .handyman, at: address.point)
    }

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

    /// The two sweeps above overlap, so the rail is deduplicated by helper.
    private var uniqueNearby: [HelperMatch] {
        nearbyMatches.reduce(into: [HelperMatch]()) { result, match in
            if !result.contains(where: { $0.id == match.id }) { result.append(match) }
        }
    }

    private var nearby: some View {
        let unique = cachedNearby
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
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                                Text("\(job.helper?.displayName ?? "") · \(Format.ago(job.createdAt, now: Date()))")
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

/// Pulled out of `HomeView` so the per-second clock only invalidates this.
///
/// Reading `session.now` anywhere in the home screen's own body made the whole
/// screen — including two `Matching.candidates` sweeps and a demand calculation —
/// recompute every tick. The ETA belongs to the banner, so the dependency does too.
struct LiveJobBanner: View {
    @Environment(AppSession.self) private var session
    let job: Job

    var body: some View {
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
}
