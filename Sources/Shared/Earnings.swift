import Foundation

struct Earnings: Hashable, Sendable {
    var labour: Decimal = .zero
    var surge: Decimal = .zero
    var tips: Decimal = .zero
    var jobs: Int = 0
    var minutes: Int = 0

    var gross: Decimal { labour + surge + tips }

    /// What the hour actually paid, once the short jobs and the long ones are
    /// averaged out. The number a helper judges a platform by.
    var effectiveHourly: Decimal {
        guard minutes > 0 else { return .zero }
        return (gross / (Decimal(minutes) / 60)).roundedToCents()
    }

    static func + (lhs: Earnings, rhs: Earnings) -> Earnings {
        Earnings(
            labour: lhs.labour + rhs.labour,
            surge: lhs.surge + rhs.surge,
            tips: lhs.tips + rhs.tips,
            jobs: lhs.jobs + rhs.jobs,
            minutes: lhs.minutes + rhs.minutes
        )
    }
}

enum Payout {
    /// How the money splits. The platform keeps the service fee and the instant
    /// dispatch fee — the two things it actually provides — and the helper takes
    /// the labour, the whole busy-area premium, and every cent of the tip.
    ///
    /// Tax isn't in either column: it's collected from the customer and passed
    /// on, so counting it as anybody's income would be wrong.
    static func earnings(for job: Job) -> Earnings {
        let settled = job.billedMinutes.map { Pricing.settle(job.quote, billedMinutes: $0) } ?? job.quote
        return Earnings(
            labour: settled.labor,
            surge: settled.surgeAmount,
            tips: job.rating?.tip ?? .zero,
            jobs: 1,
            minutes: settled.minutes
        )
    }

    static func earnings(for jobs: [Job]) -> Earnings {
        jobs.reduce(Earnings()) { $0 + earnings(for: $1) }
    }

    /// What the platform kept on a job — shown to the helper rather than hidden,
    /// because the argument about the cut is worse when the number isn't there.
    static func platformCut(for job: Job) -> Decimal {
        let settled = job.billedMinutes.map { Pricing.settle(job.quote, billedMinutes: $0) } ?? job.quote
        return settled.serviceFee + settled.urgencyFee - settled.plannedDiscount - settled.promoDiscount
    }

    /// The headline on an offer card: what taking this job pays, before tips.
    static func offerPay(for job: Job) -> Decimal {
        job.quote.labor + job.quote.surgeAmount
    }
}

/// Buckets a helper's finished work by when it happened.
enum EarningsPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .allTime: "All time"
        }
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= weekAgo
        case .allTime:
            return true
        }
    }
}
