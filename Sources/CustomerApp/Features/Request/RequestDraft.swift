import Observation
import SwiftUI

/// The in-progress request. Everything the five steps collect lives here, and
/// the review step prices it straight off this object so the number the
/// customer confirms is the number that gets booked.
@Observable
@MainActor
final class RequestDraft {

    enum Step: Int, CaseIterable, Identifiable {
        case category, details, location, timing, review

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .category: "What do you need?"
            case .details: "Tell us about the job"
            case .location: "Where is it?"
            case .timing: "When?"
            case .review: "Confirm and book"
            }
        }

        var shortTitle: String {
            switch self {
            case .category: "Category"
            case .details: "Details"
            case .location: "Location"
            case .timing: "Timing"
            case .review: "Review"
            }
        }
    }

    var step: Step
    var category: HelpCategory
    var title: String = ""
    var notes: String = ""
    var photoNames: [String] = []
    var minutes: Int
    var address: SavedAddress?
    /// The whole point of the app in one boolean.
    var wantsInstant: Bool
    var scheduledStart: Date
    /// Set when the customer picked somebody themselves rather than letting the
    /// dispatcher choose.
    var chosenHelper: Helper?
    /// Set when the customer names their own hourly rate instead of taking the
    /// category's going rate. Always set for Custom, which has no going rate.
    var offeredRate: Decimal?
    var paymentMethod: PaymentMethod?
    var promoText: String = ""
    var appliedPromo: Promo?
    var promoError: String?

    init(
        category: HelpCategory = .cleaning,
        address: SavedAddress? = nil,
        wantsInstant: Bool = true,
        startingAt step: Step = .category,
        now: Date = Date()
    ) {
        self.category = category
        self.address = address
        self.minutes = category.minimumMinutes
        if category == .custom {
            // Deliberately not pre-filled. Custom has no going rate, and seeding
            // the field with one would put a number in the customer's mouth.
            self.offeredRate = nil
        }
        self.wantsInstant = wantsInstant && category.supportsInstant
        self.scheduledStart = Scheduling.nextSlot(minutes: category.minimumMinutes, now: now, leadMinutes: Vetting.minimumLeadMinutes(for: category))
        self.step = step
    }

    // MARK: Derived

    var timing: JobTiming {
        wantsInstant ? .now : .scheduled(start: scheduledStart)
    }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? category.defaultJobTitle : trimmed
    }

    /// A rate the customer named beats both the chosen helper's rate and the
    /// category's — it's an offer, and the whole point is that it's theirs.
    var hourlyRate: Decimal? {
        offeredRate ?? Pricing.hourlyRate(category: category, helper: chosenHelper)
    }

    /// Nothing can be quoted until a rate exists. For every category but Custom
    /// that's immediate; for Custom it waits on the customer.
    var isPriceable: Bool { hourlyRate != nil }

    /// The rate to open a negotiation at when the customer first reaches for the
    /// stepper — a suggestion drawn from what comparable work actually pays,
    /// not a default that quietly becomes the price.
    func suggestedRate(in roster: [Helper]) -> Decimal {
        Negotiation.suggestedOpening(for: category, in: roster)
    }

    var isNegotiating: Bool { offeredRate != nil }

    var rateIssue: Negotiation.Issue? {
        offeredRate.flatMap { Negotiation.issue(offering: $0) }
    }

    func setOfferedRate(_ rate: Decimal?) {
        offeredRate = rate.map(Negotiation.roundedToStep)
    }

    /// Opens rate negotiation at whatever the job is currently priced at, so
    /// turning it on never jumps the number under the customer.
    func startNegotiating(roster: [Helper]) {
        guard offeredRate == nil else { return }
        offeredRate = Negotiation.roundedToStep(
            hourlyRate ?? Negotiation.suggestedOpening(for: category, in: roster)
        )
    }

    var billableMinutes: Int {
        Pricing.billableMinutes(category: category, requested: minutes)
    }

    var hasMinimumBump: Bool { billableMinutes > minutes }

    func quote(demand: DemandIndex, now: Date = Date()) -> Quote? {
        guard let hourlyRate else { return nil }
        return Pricing.quote(
            category: category,
            requestedMinutes: minutes,
            hourlyRate: hourlyRate,
            timing: timing,
            demand: demand,
            promo: appliedPromo,
            now: now
        )
    }

    /// Care work asks for more notice than an hour — see `Vetting`.
    var leadMinutes: Int { Vetting.minimumLeadMinutes(for: category) }

    func schedulingIssue(now: Date = Date()) -> Scheduling.Issue? {
        wantsInstant ? nil : Scheduling.issue(
            start: scheduledStart, minutes: billableMinutes, now: now, leadMinutes: leadMinutes
        )
    }

    // MARK: Step machine

    func canAdvance(now: Date = Date()) -> Bool {
        switch step {
        case .category: true
        case .details: minutes > 0 && rateIssue == nil && isPriceable
        case .location: address != nil
        case .timing: schedulingIssue(now: now) == nil
        case .review: address != nil && schedulingIssue(now: now) == nil && isPriceable
        }
    }

    var isLastStep: Bool { step == .review }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func retreat() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: Edits that need to keep other fields honest

    func select(category newValue: HelpCategory, now: Date = Date()) {
        guard newValue != category else { return }
        category = newValue
        // Duration, helper and rate were all tied to the old category.
        minutes = newValue.minimumMinutes
        if let chosen = chosenHelper, !chosen.handles(newValue) { chosenHelper = nil }
        // Custom has no going rate, so it always opens negotiating. Anything
        // else falls back to its own rate until the customer opts in again.
        offeredRate = newValue == .custom
            ? nil
            : nil
        if !newValue.supportsInstant { wantsInstant = false }
        scheduledStart = Scheduling.nextSlot(minutes: minutes, now: now, leadMinutes: leadMinutes)
    }

    func setMinutes(_ newValue: Int, now: Date = Date()) {
        minutes = max(15, newValue)
        // A longer job can push the chosen slot past closing time; slide it to
        // the next one that fits rather than letting the review step fail.
        if !wantsInstant, Scheduling.issue(start: scheduledStart, minutes: billableMinutes, now: now, leadMinutes: leadMinutes) != nil {
            scheduledStart = Scheduling.nextSlot(minutes: billableMinutes, now: now, leadMinutes: leadMinutes)
        }
    }

    func setInstant(_ newValue: Bool, now: Date = Date()) {
        guard newValue == false || category.supportsInstant else { return }
        wantsInstant = newValue
        if !newValue {
            scheduledStart = Scheduling.nextSlot(minutes: billableMinutes, now: now, leadMinutes: leadMinutes)
        }
    }

    func applyPromo() {
        let raw = promoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            appliedPromo = nil
            promoError = nil
            return
        }
        if let promo = Promo.named(raw) {
            appliedPromo = promo
            promoError = nil
            promoText = promo.code
        } else {
            appliedPromo = nil
            promoError = "We don't recognise that code."
        }
    }

    func clearPromo() {
        appliedPromo = nil
        promoText = ""
        promoError = nil
    }
}
