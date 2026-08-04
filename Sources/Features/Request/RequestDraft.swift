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
        self.wantsInstant = wantsInstant && category.supportsInstant
        self.scheduledStart = Scheduling.nextSlot(minutes: category.minimumMinutes, now: now)
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

    var hourlyRate: Decimal {
        Pricing.hourlyRate(category: category, helper: chosenHelper)
    }

    var billableMinutes: Int {
        Pricing.billableMinutes(category: category, requested: minutes)
    }

    var hasMinimumBump: Bool { billableMinutes > minutes }

    func quote(demand: DemandIndex, now: Date = Date()) -> Quote {
        Pricing.quote(
            category: category,
            requestedMinutes: minutes,
            hourlyRate: hourlyRate,
            timing: timing,
            demand: demand,
            promo: appliedPromo,
            now: now
        )
    }

    func schedulingIssue(now: Date = Date()) -> Scheduling.Issue? {
        wantsInstant ? nil : Scheduling.issue(start: scheduledStart, minutes: billableMinutes, now: now)
    }

    // MARK: Step machine

    func canAdvance(now: Date = Date()) -> Bool {
        switch step {
        case .category: true
        case .details: minutes > 0
        case .location: address != nil
        case .timing: schedulingIssue(now: now) == nil
        case .review: address != nil && schedulingIssue(now: now) == nil
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
        // Duration and helper were tied to the old category; both have to go.
        minutes = newValue.minimumMinutes
        if let chosen = chosenHelper, !chosen.handles(newValue) { chosenHelper = nil }
        if !newValue.supportsInstant { wantsInstant = false }
        scheduledStart = Scheduling.nextSlot(minutes: minutes, now: now)
    }

    func setMinutes(_ newValue: Int, now: Date = Date()) {
        minutes = max(15, newValue)
        // A longer job can push the chosen slot past closing time; slide it to
        // the next one that fits rather than letting the review step fail.
        if !wantsInstant, Scheduling.issue(start: scheduledStart, minutes: billableMinutes, now: now) != nil {
            scheduledStart = Scheduling.nextSlot(minutes: billableMinutes, now: now)
        }
    }

    func setInstant(_ newValue: Bool, now: Date = Date()) {
        guard newValue == false || category.supportsInstant else { return }
        wantsInstant = newValue
        if !newValue {
            scheduledStart = Scheduling.nextSlot(minutes: billableMinutes, now: now)
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
