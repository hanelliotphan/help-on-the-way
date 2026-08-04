import SwiftUI

struct ReviewStep: View {
    @Environment(AppSession.self) private var session
    @Bindable var draft: RequestDraft
    let quote: Quote
    let demand: DemandIndex

    @FocusState private var promoFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summary
            helperCard

            Card(spacing: 11) {
                Text("What you'll pay")
                    .font(.subheadline.weight(.semibold))
                QuoteTable(quote: quote)
                Text(draft.wantsInstant
                     ? "Authorised now, charged when the job is done. Runs long? You're billed to the nearest 15 minutes."
                     : "Nothing is charged until the job is finished. Free to cancel up to two hours before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            paymentCard
            promoCard

            Card(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(Palette.success)
                    Text("Every job is covered")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Helpers are background checked and insured while on your job. Anything damaged is handled through support, not between you and them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        Card(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Palette.accentSoft)
                    Image(systemName: draft.category.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.resolvedTitle)
                        .font(.subheadline.weight(.bold))
                    Text(draft.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button("Edit") { draft.step = .details }
                    .font(.subheadline.weight(.semibold))
            }

            if !draft.notes.isEmpty {
                Text(draft.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !draft.photoNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.photoNames, id: \.self) { name in
                            JobPhotoView(name: name)
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            Divider()

            LabeledRow(
                label: "When",
                value: draft.wantsInstant
                    ? "As soon as someone accepts"
                    : Format.slot(draft.scheduledStart, now: session.now),
                symbol: draft.wantsInstant ? "bolt.fill" : "calendar",
                tint: Palette.tint(for: draft.timing)
            )
            LabeledRow(label: "How long", value: Format.duration(minutes: quote.minutes), symbol: "clock")
            LabeledRow(
                label: "Where",
                value: (draft.address ?? session.homeAddress).oneLine,
                symbol: (draft.address ?? session.homeAddress).symbol
            )
        }
    }

    // MARK: Helper

    private var helperCard: some View {
        Card(spacing: 11) {
            if let chosen = draft.chosenHelper {
                HStack(spacing: 12) {
                    Avatar(helper: chosen, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chosen.displayName)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            Stars(value: chosen.rating, size: 10)
                            Text("\(Format.rating(chosen.rating)) · \(Format.jobsCompleted(chosen.jobsCompleted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    Chip(text: "Your pick", symbol: "hand.thumbsup.fill", tint: Palette.accent)
                }
                Text(draft.wantsInstant
                     ? "The request goes only to \(chosen.firstName). If they don't take it, we'll offer to open it up."
                     : "\(chosen.firstName) holds the slot once you confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Palette.accentSoft)
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.accent)
                    }
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("We'll find you the best match")
                            .font(.subheadline.weight(.semibold))
                        Text("\(session.backend.nearbyCount(for: draft.category, near: (draft.address ?? session.homeAddress).point)) \(draft.category.title.lowercased()) helpers within 6 miles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if !draft.wantsInstant {
                    Button("Pick somebody myself") { draft.step = .timing }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    // MARK: Payment

    private var paymentCard: some View {
        Card(spacing: 10) {
            HStack {
                Text("Payment")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(session.paymentMethods) { method in
                        Button {
                            draft.paymentMethod = method
                        } label: {
                            Label(method.label, systemImage: method.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: (draft.paymentMethod ?? session.defaultPaymentMethod)?.symbol ?? "creditcard")
                        Text((draft.paymentMethod ?? session.defaultPaymentMethod)?.label ?? "Add a card")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                }
            }
            if session.profile.creditBalance > 0 {
                Text("\(session.profile.creditBalance.currency) in credit will be applied at checkout.")
                    .font(.caption)
                    .foregroundStyle(Palette.success)
            }
        }
    }

    private var promoCard: some View {
        Card(spacing: 10) {
            HStack {
                Text("Promo code")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if draft.appliedPromo != nil {
                    Button("Remove") { draft.clearPromo() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.danger)
                }
            }
            HStack(spacing: 9) {
                TextField("FIRST20", text: $draft.promoText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($promoFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Button("Apply") {
                    draft.applyPromo()
                    promoFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
            }
            if let promo = draft.appliedPromo {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(promo.blurb)
                }
                .font(.caption)
                .foregroundStyle(Palette.success)
            } else if let error = draft.promoError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }
        }
    }
}
