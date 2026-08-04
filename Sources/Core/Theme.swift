import SwiftUI

enum Palette {
    /// The request blue. Anything that moves a booking forward wears it.
    static let accent = Color(red: 0.16, green: 0.36, blue: 0.96)
    static let accentSoft = Color(red: 0.16, green: 0.36, blue: 0.96).opacity(0.12)

    /// "Now" is amber everywhere; "Later" is teal everywhere. The two timing
    /// modes are the spine of the app, so they get colours of their own and
    /// never trade them.
    static let instant = Color(red: 0.95, green: 0.55, blue: 0.08)
    static let instantSoft = Color(red: 0.95, green: 0.55, blue: 0.08).opacity(0.15)
    static let planned = Color(red: 0.04, green: 0.60, blue: 0.55)
    static let plannedSoft = Color(red: 0.04, green: 0.60, blue: 0.55).opacity(0.14)

    static let success = Color(red: 0.11, green: 0.60, blue: 0.35)
    static let successSoft = Color(red: 0.11, green: 0.60, blue: 0.35).opacity(0.14)
    static let danger = Color(red: 0.81, green: 0.22, blue: 0.22)
    static let dangerSoft = Color(red: 0.81, green: 0.22, blue: 0.22).opacity(0.13)

    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let hairline = Color(uiColor: .separator).opacity(0.6)

    static func tint(for timing: JobTiming) -> Color {
        timing.isInstant ? instant : planned
    }

    static func tint(for status: JobStatus) -> Color {
        switch status {
        case .searching: instant
        case .scheduled: planned
        case .accepted, .enRoute, .arrived, .inProgress: accent
        case .completed: success
        case .cancelled, .unmatched: danger
        }
    }

    /// Avatars are drawn, not downloaded. A stored hue keeps a given helper the
    /// same colour on every screen they show up on.
    static func avatar(hue: Double) -> Color {
        Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}

enum Format {

    // MARK: Money

    static func money(_ amount: Decimal) -> String { amount.currency }

    static func rate(_ amount: Decimal) -> String { "\(amount.shortCurrency)/hr" }

    static func signed(_ amount: Decimal) -> String {
        amount < 0 ? "−\((-amount).currency)" : amount.currency
    }

    // MARK: Duration

    /// "45 min", "1 hr", "2 hr 30 min"
    static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(minutes, 0)) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// Compact form for chips and rows: "2h", "2h 30m".
    static func compactDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(minutes, 0))m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func eta(minutes: Int) -> String {
        if minutes <= 0 { return "Arriving now" }
        if minutes == 1 { return "1 min away" }
        return "\(minutes) min away"
    }

    // MARK: Dates

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today, 3:30 PM" · "Tomorrow, 9:00 AM" · "Mon, Aug 10 at 9:00 AM"
    static func slot(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time(date))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow, \(time(date))"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(time(date))"
    }

    static func day(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "3:30 – 5:30 PM"
    static func window(_ start: Date, minutes: Int) -> String {
        let end = start.addingTimeInterval(Double(minutes) * 60)
        return "\(time(start)) – \(time(end))"
    }

    /// "just now", "12 min ago", "3 days ago"
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hr ago" }
        let days = Int(seconds / 86_400)
        if days == 1 { return "yesterday" }
        if days < 30 { return "\(days) days ago" }
        let months = days / 30
        return months == 1 ? "last month" : "\(months) months ago"
    }

    static func agoInDays(_ days: Int) -> String {
        switch days {
        case ..<1: "today"
        case 1: "yesterday"
        case ..<30: "\(days) days ago"
        case ..<60: "last month"
        default: "\(days / 30) months ago"
        }
    }

    // MARK: Distance & ratings

    static func miles(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    static func distance(_ miles: Double) -> String {
        miles < 0.1 ? "right here" : "\(Self.miles(miles)) mi"
    }

    static func rating(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func jobsCompleted(_ count: Int) -> String {
        count >= 1000
            ? String(format: "%.1fk jobs", Double(count) / 1000)
            : "\(count) jobs"
    }
}
