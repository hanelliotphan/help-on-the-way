import Foundation

/// One row of the receipt. The quote hands these out ready to render so the
/// review screen and the past-job receipt can't drift apart.
struct QuoteLine: Identifiable, Hashable, Sendable {
    var name: String
    var detail: String?
    var amount: Decimal
    var isDeduction: Bool = false
    var isEmphasised: Bool = false

    var id: String { name }
}

struct Quote: Codable, Hashable, Sendable {
    var minutes: Int
    var hourlyRate: Decimal
    var labor: Decimal
    /// What you pay for "somebody right now" rather than "somebody Thursday".
    var urgencyFee: Decimal
    var surgeMultiplier: Decimal
    var surgeAmount: Decimal
    /// Booking well ahead frees up the dispatcher, so a little of that comes back.
    var plannedDiscount: Decimal
    var promoCode: String?
    var promoDiscount: Decimal
    var serviceFee: Decimal
    var tax: Decimal
    var total: Decimal

    var subtotal: Decimal {
        max(.zero, labor + urgencyFee + surgeAmount - plannedDiscount - promoDiscount)
    }

    var isSurging: Bool { surgeAmount > 0 }

    var lines: [QuoteLine] {
        var rows: [QuoteLine] = [
            QuoteLine(
                name: "Labour",
                detail: "\(Format.rate(hourlyRate)) × \(Format.duration(minutes: minutes))",
                amount: labor
            )
        ]
        if urgencyFee > 0 {
            rows.append(QuoteLine(name: "Instant dispatch", detail: "Helper sent to you now", amount: urgencyFee))
        }
        if surgeAmount > 0 {
            let times = surgeMultiplier.formatted(.number.precision(.fractionLength(1)))
            rows.append(QuoteLine(name: "Busy-area rate", detail: "\(times)× on labour", amount: surgeAmount))
        }
        if plannedDiscount > 0 {
            rows.append(QuoteLine(name: "Planned-ahead credit", detail: "Booked a day or more out", amount: plannedDiscount, isDeduction: true))
        }
        if promoDiscount > 0 {
            rows.append(QuoteLine(name: promoCode ?? "Promo", detail: "Promo applied", amount: promoDiscount, isDeduction: true))
        }
        rows.append(QuoteLine(name: "Service fee", detail: "Support, insurance, payments", amount: serviceFee))
        rows.append(QuoteLine(name: "Estimated tax", amount: tax))
        rows.append(QuoteLine(name: "Total", amount: total, isEmphasised: true))
        return rows
    }

    /// An empty quote for a draft that hasn't been priced yet.
    static let placeholder = Quote(
        minutes: 0, hourlyRate: .zero, labor: .zero, urgencyFee: .zero,
        surgeMultiplier: 1, surgeAmount: .zero, plannedDiscount: .zero,
        promoCode: nil, promoDiscount: .zero, serviceFee: .zero, tax: .zero, total: .zero
    )
}

struct Promo: Codable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        case percentOffLabor(Decimal)
        case flatOff(Decimal)
    }

    var code: String
    var kind: Kind
    var cap: Decimal?
    var blurb: String

    static let catalog: [Promo] = [
        Promo(code: "FIRST20", kind: .percentOffLabor(.usd(0, 20)), cap: .usd(25), blurb: "20% off labour, up to $25"),
        Promo(code: "WEEKEND10", kind: .flatOff(.usd(10)), cap: nil, blurb: "$10 off any weekend booking"),
        Promo(code: "NEIGHBOUR5", kind: .flatOff(.usd(5)), cap: nil, blurb: "$5 off — thanks for the referral"),
    ]

    static func named(_ raw: String) -> Promo? {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return catalog.first { $0.code == needle }
    }

    func discount(onLabor labor: Decimal) -> Decimal {
        let raw: Decimal = switch kind {
        case .percentOffLabor(let fraction): labor * fraction
        case .flatOff(let amount): amount
        }
        let capped = cap.map { min(raw, $0) } ?? raw
        return min(capped, labor).roundedToCents()
    }
}

enum Pricing {
    static let serviceFeeRate: Decimal = .usd(0, 12)
    static let minimumServiceFee: Decimal = .usd(2, 49)
    static let taxRate: Decimal = Decimal(8875) / 100_000
    static let instantDispatchFee: Decimal = .usd(6)
    static let plannedDiscountRate: Decimal = .usd(0, 5)
    /// Booking this far ahead earns the planned-ahead credit.
    static let plannedDiscountLead: TimeInterval = 24 * 3600
    static let maximumSurge: Decimal = .usd(2, 50)

    /// A helper's own rate wins when the customer picked them; otherwise the
    /// category's going rate is what we can promise before anyone accepts.
    /// Nil when nothing has set a rate yet — Custom with no offer on the table.
    /// A job in that state isn't priceable, and the flow won't let it be booked.
    static func hourlyRate(category: HelpCategory, helper: Helper?) -> Decimal? {
        helper?.hourlyRate ?? category.standardHourlyRate
    }

    /// Nothing books for less than the category's block, no matter what the
    /// duration picker is showing.
    static func billableMinutes(category: HelpCategory, requested: Int) -> Int {
        max(category.minimumMinutes, requested)
    }

    static func quote(
        category: HelpCategory,
        requestedMinutes: Int,
        hourlyRate: Decimal,
        timing: JobTiming,
        demand: DemandIndex = .calm,
        promo: Promo? = nil,
        now: Date = Date()
    ) -> Quote {
        let minutes = billableMinutes(category: category, requested: requestedMinutes)
        let hours = Decimal(minutes) / 60
        let labor = (hourlyRate * hours).roundedToCents()

        let instant = timing.isInstant
        let urgencyFee = instant ? instantDispatchFee : .zero
        let multiplier = instant ? demand.multiplier : 1
        let surgeAmount = instant ? (labor * (multiplier - 1)).roundedToCents() : .zero

        var plannedDiscount = Decimal.zero
        if let start = timing.scheduledStart, start.timeIntervalSince(now) >= plannedDiscountLead {
            plannedDiscount = (labor * plannedDiscountRate).roundedToCents()
        }

        let promoDiscount = promo?.discount(onLabor: labor) ?? .zero

        let subtotal = max(.zero, labor + urgencyFee + surgeAmount - plannedDiscount - promoDiscount)
        let serviceFee = max(minimumServiceFee, (subtotal * serviceFeeRate).roundedToCents())
        let tax = ((subtotal + serviceFee) * taxRate).roundedToCents()

        return Quote(
            minutes: minutes,
            hourlyRate: hourlyRate,
            labor: labor,
            urgencyFee: urgencyFee,
            surgeMultiplier: multiplier,
            surgeAmount: surgeAmount,
            plannedDiscount: plannedDiscount,
            promoCode: promo?.code,
            promoDiscount: promoDiscount,
            serviceFee: serviceFee,
            tax: tax,
            total: subtotal + serviceFee + tax
        )
    }

    /// Re-prices a finished job against the time it actually took. Overtime is
    /// billed in 15-minute blocks — helpers don't invoice by the second.
    static func settle(_ quote: Quote, billedMinutes: Int) -> Quote {
        let blocks = Int((Double(billedMinutes) / 15).rounded(.up))
        let minutes = max(quote.minutes, blocks * 15)
        guard minutes != quote.minutes else { return quote }
        return rebuild(quote, minutes: minutes, hourlyRate: quote.hourlyRate)
    }

    /// Re-prices a quote at a newly agreed rate, keeping the duration and every
    /// adjustment that was settled at booking time. This is what a finished
    /// negotiation runs through.
    static func reprice(_ quote: Quote, at hourlyRate: Decimal) -> Quote {
        guard hourlyRate != quote.hourlyRate else { return quote }
        return rebuild(quote, minutes: quote.minutes, hourlyRate: hourlyRate)
    }

    /// The one place labour, surge, fee and tax are recomputed. `settle` changes
    /// the hours, `reprice` changes the rate, and neither is allowed to drift
    /// from the other on how a total is built.
    private static func rebuild(_ quote: Quote, minutes: Int, hourlyRate: Decimal) -> Quote {
        var rebuilt = quote
        rebuilt.minutes = minutes
        rebuilt.hourlyRate = hourlyRate
        rebuilt.labor = (hourlyRate * (Decimal(minutes) / 60)).roundedToCents()
        rebuilt.surgeAmount = quote.surgeMultiplier > 1
            ? (rebuilt.labor * (quote.surgeMultiplier - 1)).roundedToCents()
            : .zero
        let subtotal = max(.zero, rebuilt.labor + rebuilt.urgencyFee + rebuilt.surgeAmount
            - rebuilt.plannedDiscount - rebuilt.promoDiscount)
        rebuilt.serviceFee = max(minimumServiceFee, (subtotal * serviceFeeRate).roundedToCents())
        rebuilt.tax = ((subtotal + rebuilt.serviceFee) * taxRate).roundedToCents()
        rebuilt.total = subtotal + rebuilt.serviceFee + rebuilt.tax
        return rebuilt
    }
}

/// When cancelling is free and when it isn't. Kept beside pricing because it's
/// the only other place the app takes money.
enum Cancellation {
    static let fee: Decimal = .usd(5)
    /// A minute of grace after a helper accepts — long enough to undo a misfire.
    static let graceAfterAccept: TimeInterval = 60
    /// Scheduled jobs are free to drop until this close to the start.
    static let scheduledFreeWindow: TimeInterval = 2 * 3600

    static func fee(for job: Job, now: Date = Date()) -> Decimal {
        switch job.status {
        case .searching, .unmatched, .cancelled, .completed:
            return .zero
        case .scheduled:
            return job.startsAt.timeIntervalSince(now) >= scheduledFreeWindow ? .zero : fee
        case .accepted, .enRoute, .arrived, .inProgress:
            guard let acceptedAt = job.dispatch?.acceptedAt else { return fee }
            return now.timeIntervalSince(acceptedAt) <= graceAfterAccept ? .zero : fee
        }
    }

    static func explanation(for job: Job, now: Date = Date()) -> String {
        let amount = fee(for: job, now: now)
        if amount == .zero {
            return job.status == .searching
                ? "Nobody has taken this yet, so cancelling is free."
                : "Still inside the free window — no charge."
        }
        return "\(amount.currency) covers your helper's trip out. The rest is refunded."
    }
}
