import SwiftUI

/// The end of a job: how did it go, and does anything extra go to the person
/// who did it. Tips are figured off labour, not the total — nobody wants to tip
/// on the service fee.
struct RatingView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var stars = 5
    @State private var comment = ""
    @State private var compliments: Set<String> = []
    @State private var tipIndex = 1
    @State private var customTip: Decimal = .zero

    private var job: Job? { session.job(jobID) }

    private var settled: Quote {
        guard let job else { return .placeholder }
        return job.billedMinutes.map { Pricing.settle(job.quote, billedMinutes: $0) } ?? job.quote
    }

    private var tipChoices: [(label: String, amount: Decimal)] {
        let labour = settled.labor
        return [
            ("None", .zero),
            ("15%", (labour * Decimal(15) / 100).roundedToCents()),
            ("18%", (labour * Decimal(18) / 100).roundedToCents()),
            ("20%", (labour * Decimal(20) / 100).roundedToCents()),
        ]
    }

    private var tip: Decimal {
        tipIndex == tipChoices.count ? customTip : tipChoices[tipIndex].amount
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    if let job {
                        VStack(spacing: 16) {
                            head(job)
                            starPicker(job)
                            if stars > 0 { complimentPicker }
                            commentBox(job)
                            tipCard(job)
                            receipt(job)
                        }
                        .padding(16)
                    }
                }
                footer
            }
            .background(Palette.canvas)
            .navigationTitle("Job complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Later") { session.ratingJobID = nil }
                        .font(.subheadline)
                }
            }
        }
    }

    private func head(_ job: Job) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Palette.successSoft)
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.success)
            }
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text(job.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("\(job.helper?.displayName ?? "Your helper") · \(Format.duration(minutes: job.billedMinutes ?? job.quote.minutes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func starPicker(_ job: Job) -> some View {
        Card(spacing: 12) {
            Text("How did \(job.helper?.firstName ?? "it") do?")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        withAnimation(.snappy) { stars = value }
                    } label: {
                        Image(systemName: value <= stars ? "star.fill" : "star")
                            .font(.system(size: 30))
                            .foregroundStyle(value <= stars ? Color(red: 0.96, green: 0.71, blue: 0.12) : Color.secondary.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(starBlurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var starBlurb: String {
        switch stars {
        case 5: "Perfect — they'll be saved to your favourites."
        case 4: "Good. Anything that would have made it a five?"
        case 3: "Okay. Tell us what fell short."
        case 2, 1: "Sorry about that. Support will read this one."
        default: "Tap a star."
        }
    }

    private var complimentPicker: some View {
        Card(spacing: 10) {
            Text("What stood out?")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 8), count: 2), spacing: 8) {
                ForEach(JobRating.complimentOptions, id: \.self) { option in
                    Button {
                        if compliments.contains(option) { compliments.remove(option) } else { compliments.insert(option) }
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .foregroundStyle(compliments.contains(option) ? .white : Palette.accent)
                            .background(
                                compliments.contains(option) ? Palette.accent : Palette.accentSoft,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func commentBox(_ job: Job) -> some View {
        Card(spacing: 8) {
            Text("Anything else?")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $comment)
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text("Shared publicly on \(job.helper?.firstName ?? "their")'s profile.")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func tipCard(_ job: Job) -> some View {
        Card(spacing: 11) {
            HStack {
                Text("Add a tip")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(tip.currency)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tip > 0 ? Palette.success : .secondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(tipChoices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        withAnimation(.snappy) { tipIndex = index }
                    } label: {
                        VStack(spacing: 1) {
                            Text(choice.label)
                                .font(.subheadline.weight(.bold))
                            if choice.amount > 0 {
                                Text(choice.amount.shortCurrency)
                                    .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .foregroundStyle(tipIndex == index ? .white : Palette.accent)
                        .background(
                            tipIndex == index ? Palette.accent : Palette.accentSoft,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Tips are worked out on labour only and go straight to \(job.helper?.firstName ?? "your helper").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func receipt(_ job: Job) -> some View {
        Card(spacing: 11) {
            HStack {
                Text("Receipt")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let method = session.paymentMethods.first(where: { $0.id == job.paymentMethodID }) {
                    Chip(text: method.label, symbol: method.symbol, tint: .secondary)
                }
            }
            if let billed = job.billedMinutes, billed != job.estimatedMinutes {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                    Text("Ran \(Format.duration(minutes: billed - job.estimatedMinutes)) over the estimate — billed to the nearest 15 minutes.")
                }
                .font(.caption)
                .foregroundStyle(Palette.instant)
            }
            QuoteTable(quote: settled)
            if tip > 0 {
                Divider()
                HStack {
                    Text("Tip").font(.subheadline)
                    Spacer()
                    Text(tip.currency).font(.subheadline.weight(.semibold))
                }
                HStack {
                    Text("Charged").font(.subheadline.weight(.bold))
                    Spacer()
                    Text((settled.total + tip).currency).font(.subheadline.weight(.bold))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            BigButton(title: tip > 0 ? "Submit and tip \(tip.currency)" : "Submit rating", symbol: "checkmark") {
                session.rate(jobID: jobID, rating: JobRating(
                    stars: stars,
                    comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                    tip: tip,
                    compliments: Array(compliments).sorted()
                ))
            }
            Button("Skip") { session.skipRating(jobID: jobID) }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }
}
