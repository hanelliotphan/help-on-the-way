import MapKit
import SwiftUI

/// The job in hand. One big primary action that walks the state machine forward,
/// and everything the helper needs to actually do the work above it.
struct ActiveJobView: View {
    @Environment(HelperSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let jobID: UUID

    @State private var camera: MapCameraPosition = .automatic

    private var job: Job? { session.jobs.first { $0.id == jobID } }

    var body: some View {
        Group {
            if let job {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 14) {
                            map(job)
                            payCard(job)
                            customerCard(job)
                            jobCard(job)
                            accessCard(job)
                        }
                        .padding(16)
                    }
                    primaryAction(job)
                }
            } else {
                EmptyBlock(symbol: "checkmark.circle", title: "Job closed", message: "Nothing more to do here.")
            }
        }
        .background(Palette.canvas)
        .navigationTitle(job?.status.title ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let job {
                camera = .region(MKCoordinateRegion(
                    center: job.address.point.coordinate,
                    latitudinalMeters: 900, longitudinalMeters: 900
                ))
            }
        }
        // A finished job has nothing left to do on this screen, and leaving it
        // pushed means coming back to Drive still shows yesterday's work.
        .onChange(of: job?.status) { _, status in
            if let status, status.isFinished { dismiss() }
        }
    }

    // MARK: Map

    private func map(_ job: Job) -> some View {
        Map(position: $camera) {
            if let plan = job.dispatch {
                MapPolyline(coordinates: plan.route.map(\.coordinate))
                    .stroke(Palette.helper.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            Marker(job.address.label, systemImage: job.address.symbol, coordinate: job.address.point.coordinate)
                .tint(Palette.helper)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button {
                openInMaps(job)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    Text("Directions")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.thickMaterial, in: Capsule())
            }
            .padding(10)
        }
    }

    /// Hands the address to Apple Maps. The one thing a helper app genuinely
    /// shouldn't try to reimplement.
    private func openInMaps(_ job: Job) {
        let placemark = MKPlacemark(coordinate: job.address.point.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = job.address.label
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    // MARK: Cards

    private func payCard(_ job: Job) -> some View {
        Card(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This job pays")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Payout.offerPay(for: job).currency)
                        .font(.title2.weight(.bold))
                }
                Spacer()
                if let plan = job.dispatch {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timeLabel(job, plan: plan))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.helper)
                        Text(Format.duration(minutes: job.quote.minutes) + " booked")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let plan = job.dispatch, job.status == .inProgress {
                ProgressView(value: plan.workFraction(at: session.now))
                    .tint(Palette.helper)
            }
        }
    }

    private func timeLabel(_ job: Job, plan: DispatchPlan) -> String {
        switch job.status {
        case .accepted, .enRoute: Format.eta(minutes: plan.etaMinutes(at: session.now))
        case .arrived: "At the door"
        case .inProgress: "\(Format.duration(minutes: plan.workRemainingMinutes(at: session.now))) left"
        default: job.status.title
        }
    }

    private func customerCard(_ job: Job) -> some View {
        Card(spacing: 12) {
            HStack(spacing: 12) {
                Avatar(initials: session.customer.initials, hue: 0.6, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.customer.name.isEmpty ? "Your customer" : session.customer.name)
                        .font(.subheadline.weight(.semibold))
                    Text(job.address.oneLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 10) {
                NavigationLink {
                    HelperChatView(jobID: job.id)
                } label: {
                    pill(symbol: "bubble.left.fill", title: "Message")
                }
                .buttonStyle(.plain)

                Button {
                    session.toast = "Calling the customer — demo only."
                } label: {
                    pill(symbol: "phone.fill", title: "Call")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pill(symbol: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(Palette.helper)
        .background(Palette.helperSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func jobCard(_ job: Job) -> some View {
        Card(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: job.category.symbol)
                    .foregroundStyle(Palette.helper)
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
            }
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
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                }
            }
            Divider()
            Text("Usually included")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(job.category.checklist, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Palette.success)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func accessCard(_ job: Job) -> some View {
        Card(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Palette.instant)
                Text("Getting in")
                    .font(.subheadline.weight(.semibold))
            }
            Text(job.address.accessNotes.isEmpty
                 ? "No access notes — ring and wait."
                 : job.address.accessNotes)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Divider()
            Text(job.address.fullAddress)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: The one button that matters

    private func primaryAction(_ job: Job) -> some View {
        VStack(spacing: 8) {
            switch job.status {
            case .accepted:
                BigButton(title: "Start driving", symbol: "car.fill", tint: Palette.helper) {
                    session.markEnRoute(job)
                }
            case .enRoute:
                BigButton(title: "I've arrived", symbol: "mappin.circle.fill", tint: Palette.helper) {
                    session.markArrived(job)
                }
            case .arrived:
                BigButton(title: "Start work", symbol: "hammer.fill", tint: Palette.helper) {
                    session.startWork(job)
                }
                Text("The clock starts now — the customer is billed for what it actually takes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .inProgress:
                BigButton(title: "Complete job", symbol: "checkmark.seal.fill", tint: Palette.success) {
                    session.complete(job)
                }
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(.bar)
    }
}

/// The helper's side of the same thread the customer sees.
struct HelperChatView: View {
    @Environment(HelperSession.self) private var session
    let jobID: UUID

    @State private var text = ""

    private var job: Job? { session.jobs.first { $0.id == jobID } }

    private let quickReplies = [
        "On my way, about 10 minutes.",
        "I'm outside.",
        "Running slightly late, sorry.",
        "All done — take a look.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let job {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 9) {
                            ForEach(job.messages) { message in
                                bubble(message).id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: job.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                        session.markThreadRead(jobID: jobID)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                        session.markThreadRead(jobID: jobID)
                    }
                }
                composer
            }
        }
        .background(Palette.canvas)
        .navigationTitle(session.customer.name.isEmpty ? "Customer" : session.customer.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Mirrored from the customer app: here, *this helper* is on the right.
    private func bubble(_ message: Message) -> some View {
        HStack {
            if message.isSystem {
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.card, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                let mine = !message.fromCustomer
                if mine { Spacer(minLength: 44) }
                VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                    Text(message.body)
                        .font(.subheadline)
                        .foregroundStyle(mine ? .white : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            mine ? Palette.helper : Palette.card,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    Text(Format.time(message.at))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !mine { Spacer(minLength: 44) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 9) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(quickReplies, id: \.self) { reply in
                        Button {
                            session.send(reply, jobID: jobID)
                        } label: {
                            Text(reply)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .foregroundStyle(Palette.helper)
                                .background(Palette.helperSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 9) {
                TextField("Message the customer", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    session.send(text, jobID: jobID)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.gray.opacity(0.45) : Palette.helper,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
