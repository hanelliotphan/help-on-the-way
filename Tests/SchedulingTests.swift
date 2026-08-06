import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Slot labels")
struct SlotLabelTests {

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 6, day: 15, hour: hour, minute: minute
        ))!
    }

    @Test("Slot buttons drop the meridiem — the part-of-day heading carries it")
    func noMeridiem() {
        let label = Format.shortTime(at(13, 30))
        #expect(!label.contains("PM"))
        #expect(!label.contains("pm"))
        #expect(label.contains("30"))
    }

    @Test("No leading zero on single-digit hours")
    func noLeadingZero() {
        // "01:00" for one in the afternoon reads like a 24-hour clock. A
        // 24-hour locale is a different story — there the padding is correct.
        guard Format.usesTwelveHourClock else { return }
        #expect(Format.shortTime(at(13)) == "1:00")
        #expect(Format.shortTime(at(9)) == "9:00")
        #expect(Format.shortTime(at(12, 30)) == "12:30")
        // Midnight wraps to 12, not 0.
        #expect(Format.shortTime(at(0, 15)) == "12:15")
    }

    @Test("The window summary keeps the meridiem, so the day is never ambiguous")
    func windowKeepsMeridiem() {
        let window = Format.window(at(13), minutes: 120)
        #expect(window.contains("PM"))
    }
}

@Suite("Scheduling rules")
struct SchedulingTests {

    /// A fixed Monday morning so nothing here depends on when it runs.
    private let now = Calendar.current.date(from: DateComponents(
        year: 2026, month: 6, day: 15, hour: 9, minute: 0
    ))!

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: Validation

    @Test("An hour of notice is exactly enough")
    func minimumLeadIsInclusive() {
        #expect(Scheduling.issue(start: at(10), minutes: 60, now: now) == nil)
        #expect(Scheduling.issue(start: at(9, 30), minutes: 60, now: now) == .tooSoon(minimumLeadMinutes: 60))
    }

    @Test("The past is not bookable")
    func pastIsRejected() {
        #expect(Scheduling.issue(start: at(8), minutes: 60, now: now) == .inThePast)
    }

    @Test("Nothing starts before opening")
    func beforeOpen() {
        #expect(Scheduling.issue(start: at(6, 0, dayOffset: 1), minutes: 60, now: now) == .beforeOpen)
    }

    @Test("The last start of the day is 8pm sharp")
    func lastStart() {
        #expect(Scheduling.issue(start: at(20), minutes: 60, now: now) == nil)
        #expect(Scheduling.issue(start: at(20, 30), minutes: 60, now: now) == .startsTooLate)
        #expect(Scheduling.issue(start: at(21), minutes: 60, now: now) == .startsTooLate)
    }

    @Test("A job that would run past closing is refused")
    func endsAfterClose() {
        #expect(Scheduling.issue(start: at(20), minutes: 180, now: now) == .endsAfterClose(closesAt: 22))
        #expect(Scheduling.issue(start: at(19), minutes: 180, now: now) == nil)
    }

    @Test("The calendar only opens two weeks out")
    func horizon() {
        #expect(Scheduling.issue(start: at(10, 0, dayOffset: 14), minutes: 60, now: now) == nil)
        #expect(Scheduling.issue(start: at(10, 0, dayOffset: 20), minutes: 60, now: now)
                == .beyondHorizon(days: 14))
    }

    @Test("The last day in the picker is bookable all day, not just the morning")
    func lastDayIsFullyOpen() {
        // Regression: measuring the horizon as "this time, fourteen days out"
        // silently trimmed every slot past the current hour on the final day.
        #expect(Scheduling.issue(start: at(8, 0, dayOffset: 14), minutes: 60, now: now) == nil)
        #expect(Scheduling.issue(start: at(20, 0, dayOffset: 14), minutes: 60, now: now) == nil)
        #expect(Scheduling.issue(start: at(7, 0, dayOffset: 15), minutes: 60, now: now)
                == .beyondHorizon(days: 14))
        #expect(Scheduling.days(minutes: 60, now: now).count == Scheduling.horizonDays + 1)
    }

    @Test("Every issue explains itself")
    func issuesHaveMessages() {
        let issues: [Scheduling.Issue] = [
            .inThePast, .tooSoon(minimumLeadMinutes: 60), .beforeOpen,
            .startsTooLate, .endsAfterClose(closesAt: 22), .beyondHorizon(days: 14),
        ]
        for issue in issues {
            #expect(!issue.message.isEmpty)
        }
    }

    // MARK: Slots

    @Test("A day's slots are all bookable, on the half hour")
    func slotsAreValid() {
        let slots = Scheduling.slots(on: Calendar.current.startOfDay(for: now), minutes: 60, now: now)
        #expect(!slots.isEmpty)
        for slot in slots {
            #expect(Scheduling.isBookable(start: slot, minutes: 60, now: now))
            #expect([0, 30].contains(Calendar.current.component(.minute, from: slot)))
        }
        #expect(slots.first == at(10))
        #expect(slots.last == at(20))
        #expect(slots.count == 21)
    }

    @Test("A longer job has fewer slots left in the day")
    func longerJobsFitInFewerSlots() {
        let today = Calendar.current.startOfDay(for: now)
        let short = Scheduling.slots(on: today, minutes: 60, now: now)
        let long = Scheduling.slots(on: today, minutes: 300, now: now)
        #expect(long.count < short.count)
        // A five-hour job can't start after 5pm and still be done by ten.
        #expect(long.last == at(17))
    }

    @Test("Days with nothing left don't appear in the picker")
    func daysAreFiltered() {
        let lateEvening = at(21, 30)
        let days = Scheduling.days(minutes: 120, now: lateEvening)
        #expect(!days.isEmpty)
        // Today is gone by half nine at night.
        #expect(!days.contains { Calendar.current.isDate($0, inSameDayAs: lateEvening) })
    }

    @Test("The picker offers at most the horizon")
    func dayCountIsBounded() {
        #expect(Scheduling.days(minutes: 60, now: now).count <= Scheduling.horizonDays + 1)
    }

    @Test("Today is offered while it still has room")
    func todayIsOfferedInTheMorning() {
        // 9am with slots from 10am — today has to be the first day in the rail,
        // or a customer who wants help this afternoon can't ask for it.
        let days = Scheduling.days(minutes: 120, now: now)
        #expect(days.first == Calendar.current.startOfDay(for: now))
    }

    // MARK: Parts of the day

    @Test("The three parts cover every legal start hour exactly once")
    func partsTileTheDay() {
        let covered = Scheduling.DayPart.allCases.flatMap { Array($0.hours) }
        #expect(covered.sorted() == Array(Scheduling.openHour...Scheduling.lastStartHour))
        // No hour belongs to two parts.
        #expect(Set(covered).count == covered.count)
    }

    @Test("An hour maps to the part it belongs to")
    func partContaining() {
        #expect(Scheduling.DayPart.containing(at(7)) == .morning)
        #expect(Scheduling.DayPart.containing(at(11, 30)) == .morning)
        #expect(Scheduling.DayPart.containing(at(12)) == .afternoon)
        #expect(Scheduling.DayPart.containing(at(16, 30)) == .afternoon)
        #expect(Scheduling.DayPart.containing(at(17)) == .evening)
        #expect(Scheduling.DayPart.containing(at(20)) == .evening)
    }

    @Test("The parts partition the day's slots — nothing lost, nothing duplicated")
    func partsPartitionSlots() {
        let today = Calendar.current.startOfDay(for: now)
        let all = Scheduling.slots(on: today, minutes: 60, now: now)
        let byPart = Scheduling.DayPart.allCases.flatMap {
            Scheduling.slots(on: today, minutes: 60, now: now, in: $0)
        }
        #expect(byPart.sorted() == all.sorted())
    }

    @Test("Availability counts match the slots in each part")
    func availabilityCounts() {
        let today = Calendar.current.startOfDay(for: now)
        let counts = Scheduling.availability(on: today, minutes: 60, now: now)
        #expect(counts.values.reduce(0, +) == Scheduling.slots(on: today, minutes: 60, now: now).count)
        for part in Scheduling.DayPart.allCases {
            #expect(counts[part] == Scheduling.slots(on: today, minutes: 60, now: now, in: part).count)
        }
        // 9am today: the morning is nearly gone, the rest of the day is open.
        #expect(counts[.morning] == 4)      // 10:00, 10:30, 11:00, 11:30
        #expect(counts[.afternoon] == 10)
        #expect(counts[.evening] == 7)
    }

    @Test("A part with nothing left reports zero rather than being hidden")
    func emptyPart() {
        // Late evening: only tomorrow morning is left, so today has no parts.
        let lateEvening = at(21, 30)
        let today = Calendar.current.startOfDay(for: lateEvening)
        let counts = Scheduling.availability(on: today, minutes: 60, now: lateEvening)
        #expect(counts[.morning] == 0)
        #expect(counts[.afternoon] == 0)
        #expect(counts[.evening] == 0)
    }

    @Test("A long job empties the late parts first")
    func longJobsShrinkTheEvening() {
        let today = Calendar.current.startOfDay(for: now)
        let counts = Scheduling.availability(on: today, minutes: 300, now: now)
        // Five hours can't start after 5pm and be done by ten.
        #expect(counts[.evening] == 1)
        #expect((counts[.afternoon] ?? 0) > 0)
    }

    // MARK: Next slot

    @Test("The suggested slot is always one you can actually book")
    func nextSlotIsBookable() {
        for hour in 0...23 {
            let moment = at(hour, 17)
            let slot = Scheduling.nextSlot(minutes: 120, now: moment)
            #expect(Scheduling.isBookable(start: slot, minutes: 120, now: moment),
                    "nextSlot at \(hour):17 returned an unbookable \(slot)")
        }
    }

    @Test("A morning request lands the same morning")
    func nextSlotThisMorning() {
        #expect(Scheduling.nextSlot(minutes: 120, now: now) == at(10))
    }

    @Test("A late-night request rolls to tomorrow's opening")
    func nextSlotRollsOver() {
        #expect(Scheduling.nextSlot(minutes: 120, now: at(21, 0)) == at(7, 0, dayOffset: 1))
    }

    @Test("Rounding up to the half hour leaves clean times alone")
    func roundingIsStable() {
        #expect(Scheduling.roundedUpToStep(at(10, 0)) == at(10, 0))
        #expect(Scheduling.roundedUpToStep(at(10, 1)) == at(10, 30))
        #expect(Scheduling.roundedUpToStep(at(10, 30)) == at(10, 30))
        #expect(Scheduling.roundedUpToStep(at(10, 31)) == at(11, 0))
    }

    // MARK: Lead time

    @Test("Lead time covers confirming, driving and getting in the door")
    func leadSeconds() {
        let lead = Scheduling.leadSeconds(travelMinutes: 10, timeScale: 60)
        #expect(lead == (10 + Dispatch.confirmMinutes + Dispatch.greetMinutes) * 60)
        // A compressed clock needs proportionally less wall time.
        #expect(Scheduling.leadSeconds(travelMinutes: 10, timeScale: 2) == lead / 30)
    }
}
