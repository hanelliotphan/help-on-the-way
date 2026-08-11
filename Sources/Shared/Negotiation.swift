import Foundation

/// The rules of haggling.
///
/// Kept out of both apps' view code because both sides need the same answers —
/// the customer app has to know whether an offer is plausible before it goes
/// out, and the helper app has to decide whether to counter.
enum Negotiation {

    /// Nobody works for less than this, so an offer beneath it isn't a
    /// negotiating position, it's a mistake.
    static let floor: Decimal = .usd(15)
    /// Above this the customer is almost certainly fat-fingering a digit.
    static let ceiling: Decimal = .usd(400)
    /// Rates move in whole dollars. Cents in an hourly rate are noise.
    static let step: Decimal = .usd(1)
    /// Enough rounds to settle, few enough that it can't run forever.
    static let maximumRounds = 8

    enum Issue: Hashable, Sendable {
        case belowFloor(Decimal)
        case aboveCeiling(Decimal)
        case unchanged
        case exhausted(rounds: Int)

        var message: String {
            switch self {
            case .belowFloor(let floor):
                "Offers start at \(floor.shortCurrency) an hour."
            case .aboveCeiling(let ceiling):
                "That's over \(ceiling.shortCurrency) an hour — check the number."
            case .unchanged:
                "That's the same rate that's already on the table."
            case .exhausted(let rounds):
                "You've been back and forth \(rounds) times. Accept, or let this one go."
            }
        }
    }

    /// Checks a rate a customer is about to put on the table.
    static func issue(offering rate: Decimal, in negotiation: RateNegotiation? = nil) -> Issue? {
        if rate < floor { return .belowFloor(floor) }
        if rate > ceiling { return .aboveCeiling(ceiling) }
        if let negotiation {
            if negotiation.rounds >= maximumRounds { return .exhausted(rounds: negotiation.rounds) }
            if rate == negotiation.latest.rate { return .unchanged }
        }
        return nil
    }

    static func isValid(offering rate: Decimal, in negotiation: RateNegotiation? = nil) -> Bool {
        issue(offering: rate, in: negotiation) == nil
    }

    /// What this kind of work actually goes for nearby, from the roster rather
    /// than a hard-coded band — the honest answer to "is my offer sane?".
    static func goingRate(for category: HelpCategory, in roster: [Helper]) -> ClosedRange<Decimal>? {
        let rates = roster.filter { $0.handles(category) }.map(\.hourlyRate).sorted()
        guard let low = rates.first, let high = rates.last else { return nil }
        return low...high
    }

    /// A starting number for the rate control. Custom has no going rate, so the
    /// midpoint of what everybody charges is the least misleading opener.
    static func suggestedOpening(for category: HelpCategory, in roster: [Helper]) -> Decimal {
        guard category == .custom else { return category.defaultHourlyRate }
        let rates = roster.map(\.hourlyRate)
        guard !rates.isEmpty else { return category.defaultHourlyRate }
        let total = rates.reduce(Decimal.zero, +)
        return roundedToStep(total / Decimal(rates.count))
    }

    static func roundedToStep(_ rate: Decimal) -> Decimal {
        var result = Decimal()
        var value = rate
        NSDecimalRound(&result, &value, 0, .plain)
        return result
    }

    // MARK: What a helper does with an offer

    enum Response: Hashable, Sendable {
        case accept
        case counter(Decimal)
        case walkAway
    }

    /// Fraction of their own rate a helper will take without arguing. Slightly
    /// under 1 because a helper would rather work at 95% than sit idle.
    static let acceptThreshold = Decimal(95) / 100
    /// Below this it isn't worth countering — the two sides aren't close.
    static let walkAwayThreshold = Decimal(55) / 100

    /// How a helper answers an offered rate.
    ///
    /// Deterministic on purpose: the same job always gets the same haggling, so
    /// a demo tells the same story twice and a test can pin it.
    static func response(
        to offered: Decimal,
        helper: Helper,
        negotiation: RateNegotiation
    ) -> Response {
        let own = helper.hourlyRate
        if offered >= (own * acceptThreshold).roundedToCents() { return .accept }
        if offered < (own * walkAwayThreshold).roundedToCents() { return .walkAway }

        // Out of rounds: take what's on the table rather than stall forever.
        if negotiation.rounds >= maximumRounds - 1 { return .accept }

        // Meet in the middle, but never below what's already offered and never
        // above their own rate.
        let midpoint = roundedToStep((offered + own) / 2)
        let counter = min(max(midpoint, offered + step), own)
        return counter <= offered ? .accept : .counter(counter)
    }

    /// A line the helper app can put next to its counter.
    static func rationale(for counter: Decimal, helper: Helper) -> String {
        counter >= helper.hourlyRate
            ? "That's \(helper.firstName)'s usual rate."
            : "\(helper.firstName) usually charges \(Format.rate(helper.hourlyRate))."
    }
}
