import SwiftUI

struct HelperProfileView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let helper: Helper
    var draft: RequestDraft?

    private var jobsWithThisHelper: [Job] {
        session.jobs.filter { $0.helper?.id == helper.id && $0.status == .completed }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                stats
                about
                if !helper.badges.isEmpty { badges }
                skills
                if !jobsWithThisHelper.isEmpty { history }
                reviews
                actions
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle(helper.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.toggleFavorite(helper.id)
                } label: {
                    Image(systemName: session.isFavorite(helper.id) ? "heart.fill" : "heart")
                        .foregroundStyle(session.isFavorite(helper.id) ? Palette.danger : Palette.accent)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 11) {
            Avatar(helper: helper, size: 88)
            VStack(spacing: 4) {
                Text(helper.displayName)
                    .font(.title2.weight(.bold))
                Text(helper.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 6) {
                Stars(value: helper.rating, size: 13)
                Text(Format.rating(helper.rating))
                    .font(.subheadline.weight(.bold))
                Text("· \(Format.jobsCompleted(helper.jobsCompleted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var stats: some View {
        Card(padding: 14) {
            HStack(spacing: 0) {
                StatBlock(value: Format.rate(helper.hourlyRate), caption: "Rate", symbol: "banknote.fill")
                Divider().frame(height: 40)
                StatBlock(value: "\(helper.respondsWithinMinutes) min", caption: "Replies in", symbol: "bolt.fill")
                Divider().frame(height: 40)
                StatBlock(value: "\(helper.repeatRate)%", caption: "Rebooked", symbol: "arrow.clockwise")
                Divider().frame(height: 40)
                StatBlock(value: "\(helper.yearsExperience) yr", caption: "Experience", symbol: "calendar")
            }
        }
    }

    private var about: some View {
        Card(spacing: 9) {
            Text("About")
                .font(.subheadline.weight(.semibold))
            Text(helper.bio)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let vehicle = helper.vehicle {
                LabeledRow(label: "Vehicle", value: vehicle, symbol: "car.fill")
            }
            LabeledRow(
                label: "Based",
                value: Format.distance(helper.basePoint.miles(to: (draft?.address ?? session.homeAddress).point)) + " from \((draft?.address ?? session.homeAddress).label)",
                symbol: "location.fill"
            )
        }
    }

    private var badges: some View {
        Card(spacing: 9) {
            Text("Checks and cover")
                .font(.subheadline.weight(.semibold))
            ForEach(helper.badges) { badge in
                HStack(spacing: 9) {
                    Image(systemName: badge.symbol)
                        .font(.footnote)
                        .foregroundStyle(Palette.success)
                        .frame(width: 20)
                    Text(badge.title)
                        .font(.footnote)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.success)
                }
            }
        }
    }

    private var skills: some View {
        Card(spacing: 10) {
            Text("Takes on")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 8), count: 2), spacing: 8) {
                ForEach(helper.skills) { skill in
                    HStack(spacing: 6) {
                        Image(systemName: skill.symbol)
                            .font(.caption2.weight(.bold))
                        Text(skill.shortTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(Palette.accent)
                    .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var history: some View {
        Card(spacing: 10) {
            Text("You've booked \(helper.firstName) \(jobsWithThisHelper.count == 1 ? "once" : "\(jobsWithThisHelper.count) times")")
                .font(.subheadline.weight(.semibold))
            ForEach(jobsWithThisHelper) { job in
                NavigationLink { JobDetailView(jobID: job.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: job.category.symbol)
                            .font(.caption)
                            .foregroundStyle(Palette.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(job.title)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                            Text(Format.ago(job.createdAt, now: session.now))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if let rating = job.rating, rating.stars > 0 {
                            Stars(value: Double(rating.stars), size: 9)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reviews: some View {
        Card(spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(helper.reviews.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(helper.reviews) { review in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(review.author)
                            .font(.footnote.weight(.semibold))
                        Stars(value: Double(review.stars), size: 9)
                        Spacer()
                        Text(Format.agoInDays(review.daysAgo))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(review.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Chip(text: review.category.shortTitle, symbol: review.category.symbol, tint: .secondary)
                }
                if review.id != helper.reviews.last?.id { Divider() }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let draft {
                BigButton(title: "Book \(helper.firstName)", symbol: "checkmark") {
                    draft.chosenHelper = helper
                    session.toast = "\(helper.displayName) added to your booking."
                    dismiss()
                }
            } else {
                BigButton(title: "Request \(helper.firstName)", symbol: "calendar.badge.plus", tint: Palette.planned) {
                    let new = RequestDraft(
                        category: helper.skills.first ?? .handyman,
                        address: session.homeAddress,
                        wantsInstant: false,
                        startingAt: .details,
                        now: session.now
                    )
                    new.chosenHelper = helper
                    new.paymentMethod = session.defaultPaymentMethod
                    session.draft = new
                }
                QuietButton(
                    title: session.isFavorite(helper.id) ? "Remove from saved" : "Save \(helper.firstName)",
                    symbol: session.isFavorite(helper.id) ? "heart.slash" : "heart",
                    tint: Palette.danger
                ) {
                    session.toggleFavorite(helper.id)
                }
            }
        }
    }
}
