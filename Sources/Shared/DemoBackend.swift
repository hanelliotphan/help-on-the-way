import Foundation

enum BackendError: LocalizedError {
    case noHelpersNearby(HelpCategory)

    var errorDescription: String? {
        switch self {
        case .noHelpersNearby(let category):
            "No \(category.title.lowercased()) helpers are free near you right now."
        }
    }
}

/// What the matching screen watches while an instant request is out.
enum MatchingUpdate: Sendable {
    /// The request went out to this many helpers.
    case broadcasting(count: Int)
    /// Somebody passed — usually because they're finishing another job.
    case declined(Helper)
    /// A real helper app is online and looking at this offer, so the simulation
    /// stands down and waits for a person to tap Accept.
    case awaitingLiveHelper(count: Int)
    case accepted(Helper)
    case failed
}

/// Stands in for the server. Every call is async with a plausible delay so the
/// UI has to handle its own loading states honestly; swap this for URLSession
/// and nothing above it changes.
@MainActor
final class DemoBackend {
    private(set) var roster: [Helper]

    /// Demo switches, driven from Profile → Demo tools.
    var simulateNoHelpers = false
    var latencyScale: Double = 1

    init(roster: [Helper] = MockData.helpers) {
        self.roster = roster
    }

    // MARK: Demand

    /// Busy-ness follows the clock rather than a dice roll — mornings and the
    /// after-work rush are when everyone wants a helper, and a customer who
    /// checks twice in a minute should see the same number both times.
    func demand(for category: HelpCategory, near point: GeoPoint, at date: Date = Date()) -> DemandIndex {
        let pool = max(1, Matching.candidates(for: category, near: point, in: roster).count)
        let hour = Calendar.current.component(.hour, from: date)
        let isWeekend = Calendar.current.isDateInWeekend(date)

        let pressure: Double = switch hour {
        case 7...9: 1.5
        case 10...15: isWeekend ? 1.2 : 0.6
        case 16...19: 1.7
        case 20...22: 0.9
        default: 0.3
        }

        let open = Int((Double(pool) * pressure).rounded())
        let free = max(1, pool - Int((Double(open) * 0.35).rounded()))
        return DemandIndex(openRequests: open, availableHelpers: free)
    }

    func nearbyCount(for category: HelpCategory, near point: GeoPoint) -> Int {
        Matching.pingCount(for: category, near: point, in: roster)
    }

    func candidates(for category: HelpCategory, near point: GeoPoint, favorites: Set<UUID>) -> [HelperMatch] {
        Matching.candidates(for: category, near: point, in: roster, favorites: favorites)
    }

    // MARK: Matching

    /// Runs an instant request out to the neighbourhood. Which helpers pass and
    /// who ends up taking it is seeded off the job id, so re-running a job
    /// replays the same story.
    func match(job: Job, favorites: Set<UUID>, liveHelperCount: Int = 0) -> AsyncStream<MatchingUpdate> {
        let category = job.category
        let point = job.address.point
        let preferred = job.helperWasChosen ? job.helper : nil
        let seed = job.id
        let scale = latencyScale
        let blocked = simulateNoHelpers
        let ranked = Matching.candidates(for: category, near: point, in: roster, favorites: favorites)

        return AsyncStream { continuation in
            Task { @MainActor in
                func pause(_ seconds: Double) async {
                    try? await Task.sleep(for: .seconds(seconds * scale))
                }

                guard !blocked, !ranked.isEmpty else {
                    await pause(2.4)
                    continuation.yield(.failed)
                    continuation.finish()
                    return
                }

                // Somebody is actually running the helper app. Broadcast, then
                // get out of the way — a simulated accept would steal the job
                // out from under a real person about to tap the button.
                if liveHelperCount > 0 {
                    continuation.yield(.broadcasting(count: max(ranked.count, liveHelperCount)))
                    await pause(1.2)
                    continuation.yield(.awaitingLiveHelper(count: liveHelperCount))
                    continuation.finish()
                    return
                }

                // Somebody the customer picked themselves doesn't get shopped
                // around — we just wait for them to confirm.
                if let preferred {
                    continuation.yield(.broadcasting(count: 1))
                    await pause(2.0)
                    continuation.yield(.accepted(preferred))
                    continuation.finish()
                    return
                }

                continuation.yield(.broadcasting(count: min(ranked.count, 8)))
                await pause(1.4)

                var generator = SplitMix64(seed: seed)
                let possibleDeclines = max(0, min(ranked.count - 1, 2))
                let declines = possibleDeclines == 0 ? 0 : Int(generator.next() % UInt64(possibleDeclines + 1))

                for index in 0..<declines {
                    await pause(1.6)
                    continuation.yield(.declined(ranked[index].helper))
                }

                await pause(1.8)
                continuation.yield(.accepted(ranked[min(declines, ranked.count - 1)].helper))
                continuation.finish()
            }
        }
    }

    // MARK: Chat

    /// The helper's side of the conversation. Canned, but it reads the job's
    /// status and the customer's last message so the replies aren't nonsense.
    func reply(for job: Job, to text: String) async -> Message? {
        guard let helper = job.helper else { return nil }
        try? await Task.sleep(for: .seconds(1.6 * latencyScale))

        let lowered = text.lowercased()
        var generator = SplitMix64(seed: UInt64(job.messages.count) &+ UInt64(job.id.hashValue.magnitude % 100_000))

        func pick(_ options: [String]) -> String {
            options[Int(generator.next() % UInt64(options.count))]
        }

        let body: String
        switch true {
        case lowered.contains("eta") || lowered.contains("how long") || lowered.contains("when"):
            body = switch job.status {
            case .accepted, .enRoute:
                "About \(job.dispatch?.etaMinutes(at: Date()) ?? 10) minutes out — I'll text when I'm parking."
            case .arrived:
                "I'm outside now."
            case .inProgress:
                "Roughly \(job.dispatch?.workRemainingMinutes(at: Date()) ?? 30) minutes left on my estimate."
            default:
                "I'll be there for the start of the window and message you when I'm close."
            }
        case lowered.contains("park"):
            body = pick([
                "No problem — I'll find street parking and walk up.",
                "Is there a driveway I can use, or should I look on the street?",
            ])
        case lowered.contains("code") || lowered.contains("gate") || lowered.contains("buzz"):
            body = "Got it, thanks — saved that."
        case lowered.contains("cancel"):
            body = "That's fine, no hard feelings. Cancel in the app and it'll sort itself out."
        case lowered.contains("thank") || lowered.contains("thanks") || lowered.contains("great"):
            body = pick(["Any time!", "Happy to help.", "No worries at all."])
        case lowered.contains("photo") || lowered.contains("picture") || lowered.contains("pic"):
            body = "Sure — I'll send photos through when I'm finished."
        case lowered.contains("?"):
            body = pick([
                "Good question. Short answer: yes, I can handle that within the time we booked.",
                "Let me take a look when I'm there and I'll tell you straight away if it changes the estimate.",
            ])
        default:
            body = switch job.status {
            case .searching:
                "Just picked this up — reading through your notes now."
            case .accepted, .enRoute:
                pick(["Understood, see you shortly.", "Noted, thanks for the heads up."])
            case .arrived:
                "I'm here whenever you're ready."
            case .inProgress:
                pick(["Making good progress.", "Getting there — nothing unexpected so far."])
            case .completed:
                "Thanks again for the booking — \(helper.firstName)."
            default:
                "Thanks, noted."
            }
        }

        return Message(at: Date(), body: body, fromCustomer: false)
    }

    /// The unprompted messages a helper sends as a job moves along.
    func systemVoiceMessage(for status: JobStatus, job: Job) -> Message? {
        guard let helper = job.helper else { return nil }
        let body: String? = switch status {
        case .accepted:
            "\(helper.firstName) took your job and is heading over."
        case .enRoute:
            "On my way now. \(helper.vehicle.map { "Driving a \($0)." } ?? "")"
        case .arrived:
            "I'm outside — \(job.address.oneLine)."
        case .inProgress:
            "Starting now. I'll let you know if anything changes the estimate."
        case .completed:
            "All finished. Have a look and let me know if anything needs another pass."
        default:
            nil
        }
        guard let body else { return nil }
        let fromHelper = status == .enRoute || status == .arrived || status == .inProgress || status == .completed
        return Message(
            at: Date(),
            body: body.trimmingCharacters(in: .whitespaces),
            fromCustomer: false,
            isSystem: !fromHelper
        )
    }
}
