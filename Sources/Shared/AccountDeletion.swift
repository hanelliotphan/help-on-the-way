import Foundation

/// The rules around closing an account.
///
/// Two ideas here. First, deletion is refused while somebody else is relying on
/// the account — a helper already driving to your door, or holding a slot on
/// their calendar, has committed time to it, and vanishing mid-job is a thing
/// done *to* them. Cancel first, then close.
///
/// Second, the confirmation is a typed word rather than a second tap. This
/// erases everything and there is no undo, so it should cost more than a
/// reflex.
enum AccountDeletion {

    /// Why deletion can't proceed yet.
    enum Blocker: Hashable, Sendable {
        case liveJob(title: String, status: JobStatus)
        case scheduledJob(title: String, startsAt: Date)

        var message: String {
            switch self {
            case .liveJob(let title, let status):
                "\"\(title)\" is \(status.title.lowercased()) right now."
            case .scheduledJob(let title, let startsAt):
                "\"\(title)\" is booked for \(Format.slot(startsAt))."
            }
        }

        var remedy: String {
            switch self {
            case .liveJob: "Cancel it, or wait for it to finish."
            case .scheduledJob: "Cancel the booking first."
            }
        }
    }

    /// Anything standing in the way, in the order a customer should deal with it.
    static func blockers(in jobs: [Job], now: Date = Date()) -> [Blocker] {
        var found: [Blocker] = []

        for job in jobs where job.status.isLive {
            found.append(.liveJob(title: job.title, status: job.status))
        }
        for job in jobs where job.status == .scheduled && job.startsAt > now {
            found.append(.scheduledJob(title: job.title, startsAt: job.startsAt))
        }
        return found
    }

    static func canDelete(jobs: [Job], now: Date = Date()) -> Bool {
        blockers(in: jobs, now: now).isEmpty
    }

    // MARK: Confirmation

    /// Typed to confirm. Uppercase because that's how it's shown, but the check
    /// is forgiving about case and stray spaces — the point is deliberateness,
    /// not a spelling test.
    static let confirmationPhrase = "DELETE"

    static func matchesConfirmation(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmationPhrase
    }

    // MARK: What goes

    /// Spelled out before the button is pressed, because "delete everything" is
    /// easier to agree to than it should be when you can't see what's in it.
    static func summary(
        jobs: [Job],
        addresses: [SavedAddress],
        paymentMethods: [PaymentMethod],
        favourites: Int
    ) -> [String] {
        var lines: [String] = []

        let finished = jobs.filter(\.status.isFinished).count
        if finished > 0 {
            lines.append("\(finished) past \(finished == 1 ? "job" : "jobs"), with their receipts and ratings")
        }

        let photos = jobs.reduce(0) { $0 + $1.photoNames.count }
        if photos > 0 {
            lines.append("\(photos) attached \(photos == 1 ? "photo" : "photos")")
        }

        let messages = jobs.reduce(0) { $0 + $1.messages.filter { !$0.isSystem }.count }
        if messages > 0 {
            lines.append("\(messages) \(messages == 1 ? "message" : "messages") with your helpers")
        }

        if !addresses.isEmpty {
            lines.append("\(addresses.count) saved \(addresses.count == 1 ? "address" : "addresses")")
        }
        if !paymentMethods.isEmpty {
            lines.append("\(paymentMethods.count) saved \(paymentMethods.count == 1 ? "card" : "cards")")
        }
        if favourites > 0 {
            lines.append("\(favourites) saved \(favourites == 1 ? "helper" : "helpers")")
        }

        lines.append("your name, phone number and email")
        return lines
    }
}
