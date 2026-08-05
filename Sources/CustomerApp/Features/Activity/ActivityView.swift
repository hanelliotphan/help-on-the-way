import SwiftUI

struct ActivityView: View {
    @Environment(AppSession.self) private var session

    enum Scope: String, CaseIterable, Identifiable {
        case active, upcoming, past
        var id: String { rawValue }
        var title: String {
            switch self {
            case .active: "Active"
            case .upcoming: "Upcoming"
            case .past: "Past"
            }
        }
    }

    @State private var scope: Scope = .active

    private var jobs: [Job] {
        switch scope {
        case .active: session.liveJobs + session.jobs.filter { $0.status == .unmatched }
        case .upcoming: session.upcomingJobs
        case .past: session.pastJobs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { option in
                    Text(count(for: option) > 0 ? "\(option.title) (\(count(for: option)))" : option.title)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if jobs.isEmpty {
                ScrollView { emptyState }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        if scope == .past, !session.jobsAwaitingRating.isEmpty {
                            ratingPrompt
                        }
                        ForEach(jobs) { job in
                            NavigationLink { JobDetailView(jobID: job.id) } label: {
                                Card(padding: 14) {
                                    JobSummaryRow(job: job, now: session.now)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Activity")
        .onAppear {
            // Land on whichever tab actually has something in it.
            if session.liveJobs.isEmpty {
                scope = session.upcomingJobs.isEmpty ? .past : .upcoming
            }
        }
    }

    private func count(for scope: Scope) -> Int {
        switch scope {
        case .active: session.liveJobs.count + session.jobs.filter { $0.status == .unmatched }.count
        case .upcoming: session.upcomingJobs.count
        case .past: session.pastJobs.count
        }
    }

    private var ratingPrompt: some View {
        VStack(spacing: 10) {
            ForEach(session.jobsAwaitingRating) { job in
                Card(padding: 14, spacing: 10) {
                    HStack(spacing: 11) {
                        if let helper = job.helper { Avatar(helper: helper, size: 38) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How did \(job.helper?.firstName ?? "it") do?")
                                .font(.subheadline.weight(.semibold))
                            Text(job.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Button("Rate") { session.ratingJobID = job.id }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .active:
            EmptyBlock(
                symbol: "bolt.slash",
                title: "Nothing running",
                message: "When you ask for help now, this is where you'll watch it happen."
            )
        case .upcoming:
            EmptyBlock(
                symbol: "calendar",
                title: "Nothing booked",
                message: "Schedule a job and it'll show up here with its helper and window."
            )
        case .past:
            EmptyBlock(
                symbol: "clock.arrow.circlepath",
                title: "No history yet",
                message: "Finished jobs, receipts and ratings live here."
            )
        }
    }
}
