import SwiftUI

struct EarningsView: View {
    @Environment(HelperSession.self) private var session

    @State private var period: EarningsPeriod = .week

    private var earnings: Earnings { session.earnings(for: period) }

    private var jobs: [Job] {
        session.completedByMe.filter { period.contains($0.createdAt, now: session.now) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach(EarningsPeriod.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                headline
                breakdown

                if jobs.isEmpty {
                    EmptyBlock(
                        symbol: "banknote",
                        title: "Nothing yet",
                        message: period == .today
                            ? "Finish a job today and it'll show up here."
                            : "Completed jobs and what they paid land here."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Jobs", detail: "\(jobs.count) completed")
                        ForEach(jobs) { job in
                            jobRow(job)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle("Earnings")
    }

    private var headline: some View {
        Card(spacing: 12, background: Palette.helper) {
            VStack(alignment: .leading, spacing: 3) {
                Text(period.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
                Text(earnings.gross.currency)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                metric(earnings.effectiveHourly.shortCurrency + "/hr", "effective")
                Divider().frame(height: 34).overlay(Color.white.opacity(0.3))
                metric("\(earnings.jobs)", earnings.jobs == 1 ? "job" : "jobs")
                Divider().frame(height: 34).overlay(Color.white.opacity(0.3))
                metric(Format.compactDuration(minutes: earnings.minutes), "worked")
            }
        }
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    private var breakdown: some View {
        Card(spacing: 10) {
            Text("Where it came from")
                .font(.subheadline.weight(.semibold))
            LabeledRow(label: "Labour", value: earnings.labour.currency, symbol: "hammer.fill", tint: Palette.helper)
            if earnings.surge > 0 {
                LabeledRow(label: "Busy-area premium", value: earnings.surge.currency, symbol: "chart.line.uptrend.xyaxis", tint: Palette.instant)
            }
            LabeledRow(label: "Tips", value: earnings.tips.currency, symbol: "heart.fill", tint: Palette.danger)
            Divider()
            HStack {
                Text("You keep")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(earnings.gross.currency)
                    .font(.subheadline.weight(.bold))
            }
            Text("The platform keeps the service fee and the instant dispatch fee. Labour, the busy-area premium and every cent of tip are yours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func jobRow(_ job: Job) -> some View {
        Card(padding: 14, spacing: 9) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Palette.helperSoft)
                    Image(systemName: job.category.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.helper)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(Format.ago(job.createdAt, now: session.now)) · \(Format.duration(minutes: job.billedMinutes ?? job.quote.minutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Payout.earnings(for: job).gross.currency)
                        .font(.subheadline.weight(.bold))
                    if let tip = job.rating?.tip, tip > 0 {
                        Text("incl. \(tip.currency) tip")
                            .font(.caption2)
                            .foregroundStyle(Palette.success)
                    }
                }
            }

            if let rating = job.rating, rating.stars > 0 {
                Divider()
                HStack(spacing: 7) {
                    Stars(value: Double(rating.stars), size: 10)
                    if !rating.compliments.isEmpty {
                        Text(rating.compliments.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct HelperScheduleView: View {
    @Environment(HelperSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if session.upcoming.isEmpty {
                    EmptyBlock(
                        symbol: "calendar",
                        title: "Nothing booked",
                        message: "When a customer schedules you for a specific slot, it shows up here."
                    )
                } else {
                    ForEach(session.upcoming) { job in
                        Card(spacing: 11) {
                            HStack(spacing: 12) {
                                VStack(spacing: 1) {
                                    Text(job.startsAt.formatted(.dateTime.day()))
                                        .font(.title3.weight(.bold))
                                    Text(job.startsAt.formatted(.dateTime.month(.abbreviated)))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(Format.window(job.startsAt, minutes: job.quote.minutes))
                                        .font(.caption)
                                        .foregroundStyle(Palette.planned)
                                    Text(job.address.oneLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(Payout.offerPay(for: job).currency)
                                    .font(.subheadline.weight(.bold))
                            }
                            if !job.notes.isEmpty {
                                Divider()
                                Text(job.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle("Schedule")
    }
}

struct HelperAccountView: View {
    @Environment(HelperSession.self) private var session

    var body: some View {
        List {
            if let me = session.me {
                Section {
                    HStack(spacing: 14) {
                        Avatar(helper: me, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(me.displayName)
                                .font(.headline)
                            HStack(spacing: 5) {
                                Stars(value: me.rating, size: 11)
                                Text(Format.rating(me.rating))
                                    .font(.footnote.weight(.semibold))
                            }
                            Text(me.headline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(spacing: 0) {
                        StatBlock(value: Format.jobsCompleted(me.jobsCompleted), caption: "lifetime", symbol: "checkmark.seal.fill")
                        Divider().frame(height: 38)
                        StatBlock(value: "\(me.repeatRate)%", caption: "rebooked", symbol: "arrow.clockwise")
                        Divider().frame(height: 38)
                        StatBlock(value: Format.rate(me.hourlyRate), caption: "your rate", symbol: "banknote.fill")
                    }
                    .padding(.vertical, 6)
                }

                Section("What you take on") {
                    ForEach(me.skills) { skill in
                        Label(skill.title, systemImage: skill.symbol)
                    }
                }

                Section("Checks and cover") {
                    ForEach(me.badges) { badge in
                        HStack {
                            Label(badge.title, systemImage: badge.symbol)
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.success)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Label("Linked to customer app", systemImage: session.isSharedStore ? "link" : "link.badge.plus")
                    Spacer()
                    Text(session.isSharedStore ? "Yes" : "No")
                        .foregroundStyle(session.isSharedStore ? Palette.success : Palette.danger)
                        .font(.subheadline.weight(.semibold))
                }
                HStack {
                    Label("Status", systemImage: "bolt.fill")
                    Spacer()
                    Text(session.isOnline ? "Online" : "Offline")
                        .foregroundStyle(session.isOnline ? Palette.success : .secondary)
                        .font(.subheadline.weight(.semibold))
                }
            } header: {
                Text("Dispatcher")
            } footer: {
                Text(session.isSharedStore
                     ? "Both apps read and write one job store in a shared App Group container, so a request placed in the customer app appears here within a second."
                     : "The shared container isn't available, so this app is running against its own data and the customer app can't see it.")
            }

            Section {
                Button(role: .destructive) {
                    session.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Signing out just returns you to the persona picker — there's no real account behind it.")
            }
        }
        .navigationTitle("You")
    }
}
