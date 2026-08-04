import MapKit
import SwiftUI

/// Live job. Map on top, everything you might want to do about it underneath.
struct TrackingView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var camera: MapCameraPosition = .automatic
    @State private var showingCancel = false
    @State private var cancelReason = ""

    private var job: Job? { session.job(jobID) }

    var body: some View {
        NavigationStack {
            Group {
                if let job {
                    content(job)
                } else {
                    EmptyBlock(symbol: "questionmark.circle", title: "Job not found", message: "It may have been cancelled.")
                }
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let job {
                        VStack(spacing: 0) {
                            Text(job.status.title)
                                .font(.subheadline.weight(.semibold))
                            Text(job.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { session.trackingJobID = nil }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func content(_ job: Job) -> some View {
        VStack(spacing: 0) {
            map(job)
                .frame(height: 300)
                // The map runs up under the navigation bar. A fade in the
                // canvas colour keeps the status text readable over streets
                // without committing to a light or dark scrim.
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Palette.canvas, Palette.canvas.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 104)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        withAnimation(.easeInOut) { camera = .region(region(for: job)) }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.footnote.weight(.bold))
                            .padding(9)
                            .background(.thickMaterial, in: Circle())
                    }
                    .padding(12)
                }

            ScrollView {
                VStack(spacing: 14) {
                    statusCard(job)
                    if let helper = job.helper { helperCard(job, helper: helper) }
                    detailsCard(job)
                    Card(spacing: 11) {
                        Text("Progress")
                            .font(.subheadline.weight(.semibold))
                        StatusTimelineView(job: job, now: session.now)
                    }
                    cancelSection(job)
                }
                .padding(16)
            }
        }
        .onAppear { camera = .region(region(for: job)) }
        .onChange(of: job.status) { _, _ in
            withAnimation(.easeInOut) { camera = .region(region(for: job)) }
        }
        .alert("Cancel this job?", isPresented: $showingCancel) {
            TextField("Reason (optional)", text: $cancelReason)
            Button("Cancel job", role: .destructive) {
                session.cancel(jobID: jobID, reason: cancelReason.isEmpty ? "Cancelled by customer" : cancelReason)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(Cancellation.explanation(for: job, now: session.now))
        }
    }

    // MARK: Map

    private func region(for job: Job) -> MKCoordinateRegion {
        let destination = job.address.point
        guard let plan = job.dispatch, job.status == .enRoute || job.status == .accepted else {
            return MKCoordinateRegion(center: destination.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        }
        let helper = plan.helperPoint(at: session.now)
        let centre = GeoPoint(
            latitude: (helper.latitude + destination.latitude) / 2,
            longitude: (helper.longitude + destination.longitude) / 2
        )
        // Pad so neither pin sits under the toolbar or the recenter button.
        let span = max(abs(helper.latitude - destination.latitude), abs(helper.longitude - destination.longitude)) * 2.4
        return MKCoordinateRegion(
            center: centre.coordinate,
            span: MKCoordinateSpan(latitudeDelta: max(span, 0.008), longitudeDelta: max(span, 0.008))
        )
    }

    private func map(_ job: Job) -> some View {
        Map(position: $camera) {
            if let plan = job.dispatch {
                MapPolyline(coordinates: plan.route.map(\.coordinate))
                    .stroke(Palette.accent.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                if job.status == .accepted || job.status == .enRoute {
                    Annotation("", coordinate: plan.helperPoint(at: session.now).coordinate) {
                        helperPuck(job, heading: plan.helperHeading(at: session.now))
                    }
                }
            }

            Marker(job.address.label, systemImage: job.address.symbol, coordinate: job.address.point.coordinate)
                .tint(Palette.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func helperPuck(_ job: Job, heading: Double) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            Image(systemName: job.helper?.vehicle == nil ? "figure.walk" : "car.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.accent)
                .rotationEffect(.degrees(job.helper?.vehicle == nil ? 0 : heading))
        }
    }

    // MARK: Cards

    private func statusCard(_ job: Job) -> some View {
        Card(spacing: 12, background: Palette.tint(for: job.status)) {
            HStack(spacing: 9) {
                Image(systemName: job.status.symbol)
                    .font(.subheadline.weight(.bold))
                Text(job.status.title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                Spacer()
                TimingChip(timing: job.timing, now: session.now)
                    .colorScheme(.light)
            }
            .foregroundStyle(.white.opacity(0.92))

            Text(headline(job))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(subhead(job))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            if let plan = job.dispatch {
                switch job.status {
                case .enRoute:
                    ProgressView(value: plan.travelFraction(at: session.now)).tint(.white)
                case .inProgress:
                    ProgressView(value: plan.workFraction(at: session.now)).tint(.white)
                default:
                    EmptyView()
                }
            }
        }
    }

    private func headline(_ job: Job) -> String {
        guard let plan = job.dispatch else { return job.status.title }
        switch job.status {
        case .accepted: return "\(job.helper?.firstName ?? "Your helper") is setting off"
        case .enRoute: return Format.eta(minutes: plan.etaMinutes(at: session.now))
        case .arrived: return "Outside now"
        case .inProgress: return "\(Format.duration(minutes: plan.workRemainingMinutes(at: session.now))) left"
        case .completed: return "All done"
        default: return job.status.title
        }
    }

    private func subhead(_ job: Job) -> String {
        guard let plan = job.dispatch else { return job.title }
        switch job.status {
        case .accepted:
            return "Packing up and heading to \(job.address.oneLine)."
        case .enRoute:
            return "\(job.helper?.displayName ?? "Your helper") is \(Format.distance(plan.helperPoint(at: session.now).miles(to: job.address.point))) away\(job.helper?.vehicle.map { " in a \($0)" } ?? "")."
        case .arrived:
            return "Let them in when you're ready — the clock starts when work does."
        case .inProgress:
            return "Booked for \(Format.duration(minutes: job.quote.minutes)). You're billed for what it actually takes."
        default:
            return job.title
        }
    }

    private func helperCard(_ job: Job, helper: Helper) -> some View {
        Card(spacing: 12) {
            HStack(spacing: 12) {
                Avatar(helper: helper, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(helper.displayName)
                        .font(.subheadline.weight(.bold))
                    HStack(spacing: 5) {
                        Stars(value: helper.rating, size: 10)
                        Text("\(Format.rating(helper.rating)) · \(Format.jobsCompleted(helper.jobsCompleted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let vehicle = helper.vehicle {
                        Text(vehicle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                NavigationLink { HelperProfileView(helper: helper) } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                NavigationLink { ChatView(jobID: job.id) } label: {
                    actionPill(symbol: "bubble.left.fill", title: "Message", badge: job.unreadFromHelper)
                }
                .buttonStyle(.plain)

                Button {
                    session.toast = "Calling \(helper.firstName) — demo only."
                } label: {
                    actionPill(symbol: "phone.fill", title: "Call", badge: 0)
                }
                .buttonStyle(.plain)

                Button {
                    session.toggleFavorite(helper.id)
                } label: {
                    actionPill(
                        symbol: session.isFavorite(helper.id) ? "heart.fill" : "heart",
                        title: session.isFavorite(helper.id) ? "Saved" : "Save",
                        badge: 0
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionPill(symbol: String, title: String, badge: Int) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 22, height: 20)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Palette.danger, in: Circle())
                        .offset(x: 7, y: -6)
                }
            }
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(Palette.accent)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func detailsCard(_ job: Job) -> some View {
        Card(spacing: 10) {
            Text("The job")
                .font(.subheadline.weight(.semibold))
            if !job.notes.isEmpty {
                Text(job.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !job.photoNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.photoNames, id: \.self) { name in
                            JobPhotoView(name: name)
                                .frame(width: 66, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            Divider()
            LabeledRow(label: "Address", value: job.address.fullAddress.replacingOccurrences(of: "\n", with: ", "), symbol: job.address.symbol)
            if !job.address.accessNotes.isEmpty {
                LabeledRow(label: "Access", value: job.address.accessNotes, symbol: "key.fill")
            }
            LabeledRow(label: "Estimate", value: job.quote.total.currency, symbol: "creditcard.fill")
        }
    }

    private func cancelSection(_ job: Job) -> some View {
        VStack(spacing: 8) {
            QuietButton(title: "Cancel this job", symbol: "xmark", tint: Palette.danger) {
                showingCancel = true
            }
            Text(Cancellation.explanation(for: job, now: session.now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
