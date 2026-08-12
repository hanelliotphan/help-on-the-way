import SwiftUI

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    var spacing: CGFloat = 10
    var background: Color = Palette.card
    @ViewBuilder var content: () -> Content

    /// A hairline border rather than a drop shadow. Shadows on every card is
    /// what makes a screen look like a stack of sticky notes.
    private var isTinted: Bool { background != Palette.card }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                if !isTinted {
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: Metrics.hairlineWidth)
                }
            }
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
    }
}

// MARK: - Buttons

/// The primary action. Defaults to ink rather than a bright accent — a
/// near-black button is what most booking apps use, and it stops every screen
/// competing for attention with itself.
struct BigButton: View {
    let title: String
    var symbol: String?
    var tint: Color = Palette.ink
    var isLoading = false
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.card)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.controlHeight)
            .foregroundStyle(Palette.card)
            .background(
                (isEnabled ? tint : Palette.inkFaint.opacity(0.45)),
                in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

/// The secondary action: outlined, not a tinted slab.
struct QuietButton: View {
    let title: String
    var symbol: String?
    var tint: Color = Palette.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(tint)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: Metrics.hairlineWidth)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small parts

/// A small status label. Outlined by default so a row of them reads as
/// metadata; filled only when the state genuinely needs to shout.
struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = Palette.inkSoft
    var filled = false

    var body: some View {
        HStack(spacing: 3.5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .foregroundStyle(filled ? Palette.card : tint)
        .background(
            filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.08)),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            if !filled {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: Metrics.hairlineWidth)
            }
        }
    }
}

struct TimingChip: View {
    let timing: JobTiming
    var now: Date = Date()

    var body: some View {
        switch timing {
        case .now:
            Chip(text: "Now", symbol: "bolt.fill", tint: Palette.instant, filled: true)
        case .scheduled(let start):
            Chip(text: Format.slot(start, now: now), symbol: "calendar", tint: Palette.planned)
        }
    }
}

struct Stars: View {
    let value: Double
    var size: CGFloat = 10
    /// A deeper amber than the usual bright gold; a wall of ratings shouldn't
    /// be the loudest thing on the screen.
    var tint: Color = Color(red: 0.72, green: 0.53, blue: 0.10)

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(at: index))
                    .font(.system(size: size))
                    .foregroundStyle(tint)
            }
        }
    }

    private func symbol(at index: Int) -> String {
        let filled = value - Double(index)
        if filled >= 0.85 { return "star.fill" }
        if filled >= 0.35 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct Avatar: View {
    let initials: String
    let hue: Double
    var size: CGFloat = 46
    var ring: Bool = false

    var body: some View {
        let colour = Palette.avatar(hue: hue)
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [colour.opacity(0.95), colour.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay {
                if ring {
                    Circle().strokeBorder(.white, lineWidth: 2.5)
                }
            }
    }
}

extension Avatar {
    init(helper: Helper, size: CGFloat = 46, ring: Bool = false) {
        self.init(initials: helper.initials, hue: helper.accentHue, size: size, ring: ring)
    }
}

struct BadgeRow: View {
    let badges: [HelperBadge]
    var limit: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges.prefix(limit)) { badge in
                Chip(text: badge.title, symbol: badge.symbol, tint: Palette.success)
            }
            if badges.count > limit {
                Chip(text: "+\(badges.count - limit)", tint: .secondary)
            }
        }
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct StatBlock: View {
    let value: String
    let caption: String
    var symbol: String?

    var body: some View {
        VStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(Palette.accent)
            }
            Text(value)
                .font(.headline)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helper presentation

struct HelperRow: View {
    let match: HelperMatch
    var showRate = true
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(helper: match.helper, size: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(match.helper.displayName)
                        .font(.subheadline.weight(.semibold))
                    if match.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.danger)
                    }
                }
                HStack(spacing: 5) {
                    Stars(value: match.helper.rating, size: 10)
                    Text(Format.rating(match.helper.rating))
                        .font(.caption.weight(.semibold))
                    Text("· \(Format.jobsCompleted(match.helper.jobsCompleted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(match.helper.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
            } else if showRate {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(match.helper.hourlyRate.shortCurrency)
                        .font(.subheadline.weight(.bold))
                    Text("per hour")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Chip(text: "\(match.etaMinutes) min", symbol: "location.fill", tint: Palette.accent)
                }
            }
        }
    }
}

// MARK: - Job presentation

struct StatusTimelineView: View {
    let job: Job
    var now: Date = Date()

    private var reachedIndex: Int {
        JobStatus.trackingOrder.firstIndex(of: job.status) ?? -1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(JobStatus.trackingOrder.enumerated()), id: \.element) { index, status in
                let reached = index <= reachedIndex
                let isCurrent = index == reachedIndex
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(reached ? Palette.accent : Palette.hairline)
                            .frame(width: isCurrent ? 12 : 9, height: isCurrent ? 12 : 9)
                            .overlay {
                                if isCurrent {
                                    Circle().strokeBorder(Palette.accentSoft, lineWidth: 5)
                                }
                            }
                        if index < JobStatus.trackingOrder.count - 1 {
                            Rectangle()
                                .fill(index < reachedIndex ? Palette.accent : Palette.hairline)
                                .frame(width: 2, height: 26)
                        }
                    }
                    .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title)
                            .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(reached ? .primary : .secondary)
                        if let event = job.events.last(where: { $0.status == status }) {
                            Text(Format.time(event.at))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

struct QuoteTable: View {
    let quote: Quote
    var showTotalOnly = false

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows) { line in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name)
                            .font(line.isEmphasised ? .subheadline.weight(.bold) : .subheadline)
                        if let detail = line.detail, !line.isEmphasised {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(line.isDeduction ? "−\(line.amount.currency)" : line.amount.currency)
                        .font(line.isEmphasised ? .subheadline.weight(.bold) : .subheadline)
                        .foregroundStyle(line.isDeduction ? Palette.success : .primary)
                }
                if line.isEmphasised == false, line.id == rows.dropLast().last?.id {
                    Divider()
                }
            }
        }
    }

    private var rows: [QuoteLine] {
        showTotalOnly ? quote.lines.filter(\.isEmphasised) : quote.lines
    }
}

struct JobSummaryRow: View {
    let job: Job
    var now: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.tint(for: job.status).opacity(0.15))
                Image(systemName: job.category.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.tint(for: job.status))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: job.status.symbol)
                        .font(.caption2)
                    Text(job.status.title)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Palette.tint(for: job.status))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(job.amountDue.currency)
                    .font(.subheadline.weight(.semibold))
                if let helper = job.helper {
                    Avatar(helper: helper, size: 26)
                }
            }
        }
    }

    private var subtitle: String {
        switch job.status {
        case .scheduled: Format.slot(job.startsAt, now: now)
        case .completed: "\(Format.ago(job.createdAt, now: now)) · \(job.helper?.displayName ?? "")"
        case .cancelled: job.cancellationReason ?? "Cancelled"
        case .unmatched: "Nobody available — try again"
        default: "\(job.helper?.displayName ?? "Finding someone") · \(job.address.label)"
        }
    }
}

// MARK: - Feedback

struct EmptyBlock: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

/// A short-lived confirmation. Lives at the root so any screen can raise one by
/// setting `session.toast`.
struct ToastOverlay: View {
    @Binding var text: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let text {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(text)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.thickMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.6))
                    withAnimation(.easeOut(duration: 0.25)) { self.text = nil }
                }
            }
        }
        .animation(.spring(duration: 0.35), value: text)
        .allowsHitTesting(false)
    }
}

struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { step in
                Capsule()
                    .fill(step <= index ? Palette.accent : Palette.hairline)
                    .frame(width: step == index ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.3), value: index)
    }
}
