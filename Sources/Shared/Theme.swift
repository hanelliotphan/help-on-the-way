import SwiftUI

/// Spacing and corner radii, in one place.
///
/// Everything used to be an 18-point rounded rectangle with 16 points of
/// padding, which at this density reads like a template rather than a product.
/// Tighter radii and less air let more of the screen carry information.
enum Metrics {
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let tileRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let gutter: CGFloat = 16
    static let controlHeight: CGFloat = 48
    static let hairlineWidth: CGFloat = 1
}

enum Palette {

    // MARK: Neutrals
    //
    // The app is monochrome first. Ink carries primary actions and primary text;
    // colour is reserved for things that genuinely need to signal.

    /// Primary text, and the fill on primary buttons.
    static let ink = dynamic(light: 0x11151B, dark: 0xF2F4F7)
    /// Secondary text. Sits at roughly 4.6:1 on canvas, so it stays readable.
    static let inkSoft = dynamic(light: 0x5A6472, dark: 0x99A2AF)
    static let inkFaint = dynamic(light: 0x8A93A1, dark: 0x6E7784)

    static let canvas = dynamic(light: 0xF6F7F9, dark: 0x0B0D10)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x161A20)
    static let hairline = dynamic(light: 0xE3E7ED, dark: 0x272C34)
    /// Text fields and other inset controls.
    static let fill = dynamic(light: 0xF1F3F6, dark: 0x1E232A)

    // MARK: One accent

    /// Used for links, selection and emphasis — not for every button. Primary
    /// actions wear `ink`, which is what stops the UI looking like a demo.
    static let accent = dynamic(light: 0x0B57D0, dark: 0x86AFFF)
    static let accentSoft = dynamic(light: 0xEBF1FD, dark: 0x18243A)

    // MARK: Timing signals
    //
    // "Now" is warm and "Later" is cool everywhere, and they never trade — but
    // muted, because a booking screen shouldn't glow.

    static let instant = dynamic(light: 0x92500A, dark: 0xDDA35A)
    static let instantSoft = dynamic(light: 0xFBF2E5, dark: 0x2A2114)
    static let planned = dynamic(light: 0x0A6A61, dark: 0x63BDB3)
    static let plannedSoft = dynamic(light: 0xE7F3F1, dark: 0x102420)

    static let success = dynamic(light: 0x116843, dark: 0x6FCB98)
    static let successSoft = dynamic(light: 0xE8F3EC, dark: 0x0E2318)
    static let danger = dynamic(light: 0xB0231A, dark: 0xF08B80)
    static let dangerSoft = dynamic(light: 0xFCEBE9, dark: 0x2A1513)

    /// The helper app runs on its own accent, so one glance at a screenshot
    /// tells you which of the two apps you're looking at.
    static let helper = dynamic(light: 0x1A4D35, dark: 0x74C69B)
    static let helperSoft = dynamic(light: 0xEAF2ED, dark: 0x11251A)

    // MARK: Adaptive plumbing

    /// Hex pairs rather than a single tint, so light and dark are each chosen
    /// deliberately instead of one being a washed-out guess at the other.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

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
    /// same colour on every screen they show up on — desaturated, so a wall of
    /// them reads as a directory rather than a bag of sweets.
    static func avatar(hue: Double) -> Color {
        Color(hue: hue, saturation: 0.34, brightness: 0.52)
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
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

    /// "10:30" — no meridiem. Only for slot buttons sitting under a
    /// morning/afternoon/evening heading, where AM or PM is already settled and
    /// repeating it on every button just costs width.
    ///
    /// Built by hand rather than with a format style: asking `FormatStyle` to
    /// omit the meridiem also makes it zero-pad the hour, and "01:00" for one in
    /// the afternoon reads like a 24-hour clock. A 24-hour locale still gets its
    /// padding, because there "09:00" is the correct shape.
    static func shortTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        if usesTwelveHourClock {
            let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
            return String(format: "%d:%02d", hour, minute)
        }
        return String(format: "%02d:%02d", hour24, minute)
    }

    /// Asked of the locale rather than assumed.
    static var usesTwelveHourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
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
