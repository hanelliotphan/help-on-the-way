import Foundation

/// The rules for "later". Helpers keep ordinary working hours, need an hour's
/// notice, and won't be booked into next month.
enum Scheduling {
    static let minimumLeadMinutes = 60
    static let horizonDays = 14
    static let openHour = 7
    /// Nothing starts after this — a 6pm start on a four-hour job is somebody
    /// finishing at ten.
    static let lastStartHour = 20
    static let closeHour = 22
    static let stepMinutes = 30

    enum Issue: Hashable, Sendable {
        case inThePast
        case tooSoon(minimumLeadMinutes: Int)
        case beforeOpen
        case startsTooLate
        case endsAfterClose(closesAt: Int)
        case beyondHorizon(days: Int)

        var message: String {
            switch self {
            case .inThePast:
                "That time has already passed."
            case .tooSoon(let lead):
                "Helpers need about \(lead) minutes' notice. Pick a later slot, or switch to Now."
            case .beforeOpen:
                "Bookings start at \(Self.hourLabel(Scheduling.openHour))."
            case .startsTooLate:
                "The last start of the day is \(Self.hourLabel(Scheduling.lastStartHour))."
            case .endsAfterClose(let hour):
                "A job this long would run past \(Self.hourLabel(hour)). Shorten it or start earlier."
            case .beyondHorizon(let days):
                "You can book up to \(days) days out."
            }
        }

        private static func hourLabel(_ hour: Int) -> String {
            var components = DateComponents()
            components.hour = hour
            let date = Calendar.current.date(from: components) ?? Date()
            return Format.time(date)
        }
    }

    static func issue(start: Date, minutes: Int, now: Date = Date()) -> Issue? {
        let calendar = Calendar.current
        if start < now { return .inThePast }

        let lead = start.timeIntervalSince(now) / 60
        if lead < Double(minimumLeadMinutes) { return .tooSoon(minimumLeadMinutes: minimumLeadMinutes) }

        // The horizon is the *end* of the fourteenth day, not this time of day
        // fourteen days out — otherwise the last day in the picker only offers
        // slots earlier than the hour you happen to be looking at it.
        if let lastDay = calendar.date(byAdding: .day, value: horizonDays, to: now),
           let horizon = calendar.date(bySettingHour: closeHour, minute: 0, second: 0, of: lastDay),
           start > horizon {
            return .beyondHorizon(days: horizonDays)
        }

        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)
        if hour < openHour { return .beforeOpen }
        if hour > lastStartHour || (hour == lastStartHour && minute > 0) { return .startsTooLate }

        let endMinutes = hour * 60 + minute + minutes
        if endMinutes > closeHour * 60 { return .endsAfterClose(closesAt: closeHour) }

        return nil
    }

    static func isBookable(start: Date, minutes: Int, now: Date = Date()) -> Bool {
        issue(start: start, minutes: minutes, now: now) == nil
    }

    /// Every half-hour start on a given day that could actually take the job.
    static func slots(on day: Date, minutes: Int, now: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        guard let dayStart = calendar.date(bySettingHour: openHour, minute: 0, second: 0, of: day) else { return [] }

        var results: [Date] = []
        var cursor = dayStart
        while calendar.component(.hour, from: cursor) <= lastStartHour {
            if isBookable(start: cursor, minutes: minutes, now: now) { results.append(cursor) }
            guard let next = calendar.date(byAdding: .minute, value: stepMinutes, to: cursor) else { break }
            cursor = next
            if !calendar.isDate(cursor, inSameDayAs: day) { break }
        }
        return results
    }

    /// The days worth showing in the picker — today only sticks around while it
    /// still has a slot left.
    static func days(minutes: Int, now: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        return (0...horizonDays).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            let normalised = calendar.startOfDay(for: day)
            return slots(on: normalised, minutes: minutes, now: now).isEmpty ? nil : normalised
        }
    }

    /// The default the picker opens on: soonest legal slot, rounded up to the
    /// next half hour.
    static func nextSlot(minutes: Int, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let earliest = now.addingTimeInterval(Double(minimumLeadMinutes) * 60)
        var cursor = roundedUpToStep(earliest)

        // Walk forward a day at a time until something is bookable — a late
        // request rolls to tomorrow morning rather than failing.
        for _ in 0...(horizonDays * 48) {
            if isBookable(start: cursor, minutes: minutes, now: now) { return cursor }
            guard let next = calendar.date(byAdding: .minute, value: stepMinutes, to: cursor) else { break }
            cursor = next
            let hour = calendar.component(.hour, from: cursor)
            if hour > lastStartHour {
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: cursor),
                      let morning = calendar.date(bySettingHour: openHour, minute: 0, second: 0, of: tomorrow)
                else { break }
                cursor = morning
            }
        }
        return cursor
    }

    static func roundedUpToStep(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = components.minute else { return date }
        let remainder = minute % stepMinutes
        let bump = remainder == 0 ? 0 : stepMinutes - remainder
        let floored = calendar.date(from: DateComponents(
            year: components.year, month: components.month, day: components.day,
            hour: components.hour, minute: minute
        )) ?? date
        return calendar.date(byAdding: .minute, value: bump, to: floored) ?? date
    }

    /// How long before a scheduled start the helper is put on the road. Also
    /// what the store watches for when flipping a booking into a live job.
    static func leadSeconds(travelMinutes: Int, timeScale: Double) -> TimeInterval {
        (Double(travelMinutes) + Dispatch.confirmMinutes + Dispatch.greetMinutes) * timeScale
    }
}
