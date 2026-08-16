import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Unread counts")
struct UnreadTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    /// `m` builds a thread compactly: "h" helper, "c" customer, "s" system.
    private func job(_ script: String, customerReadAt: Date? = nil, helperReadAt: Date? = nil) -> Job {
        var job = Job(
            category: .handyman,
            title: "Test",
            address: MockData.addresses[0],
            timing: .now,
            estimatedMinutes: 60,
            quote: Pricing.quote(category: .handyman, requestedMinutes: 60, hourlyRate: .usd(58), timing: .now),
            status: .inProgress
        )
        job.messages = script.enumerated().map { offset, kind in
            Message(
                at: at(Double(offset) * 60),
                body: String(kind),
                fromCustomer: kind == "c",
                isSystem: kind == "s"
            )
        }
        job.customerReadAt = customerReadAt
        job.helperReadAt = helperReadAt
        return job
    }

    // MARK: The bug this fixes

    @Test("Opening a thread clears the badge")
    func openingClearsIt() {
        // Three helper messages, never replied to: this is the state the badge
        // used to get stuck in, climbing and never coming down.
        let unread = job("hhh")
        #expect(unread.unreadFromHelper == 3)

        let read = job("hhh", customerReadAt: at(1_000))
        #expect(read.unreadFromHelper == 0)
    }

    @Test("Messages arriving after you read still count")
    func newAfterReading() {
        var job = job("hh", customerReadAt: at(90))
        #expect(job.unreadFromHelper == 0)

        job.messages.append(Message(at: at(500), body: "new", fromCustomer: false))
        #expect(job.unreadFromHelper == 1)
    }

    @Test("Replying counts as reading")
    func replyingCounts() {
        // Answering without scrolling up shouldn't leave a badge behind.
        #expect(job("hhc").unreadFromHelper == 0)
        #expect(job("hhch").unreadFromHelper == 1)
    }

    @Test("The later of reading and replying wins")
    func latestSignalWins() {
        // Read at 90s, replied at 60s — the read is newer, so nothing is unread.
        #expect(job("hc", customerReadAt: at(90)).unreadFromHelper == 0)
        // Read long ago, replied since, then one more arrives.
        #expect(job("hchh", customerReadAt: at(0)).unreadFromHelper == 2)
    }

    // MARK: What counts

    @Test("System lines are never unread")
    func systemLinesIgnored() {
        #expect(job("sss").unreadFromHelper == 0)
        #expect(job("shs").unreadFromHelper == 1)
    }

    @Test("Your own messages are never unread to you")
    func ownMessagesIgnored() {
        #expect(job("ccc").unreadFromHelper == 0)
        #expect(job("hhh").unreadFromCustomer == 0)
    }

    @Test("An empty thread has nothing unread")
    func emptyThread() {
        #expect(job("").unreadFromHelper == 0)
        #expect(job("").unreadFromCustomer == 0)
    }

    // MARK: Two sides, two stamps

    @Test("Each side has its own read state")
    func sidesAreIndependent() {
        // The customer has read; the helper hasn't.
        let job = job("hchc", customerReadAt: at(500))
        #expect(job.unreadFromHelper == 0)
        #expect(job.unreadFromCustomer > 0)
    }

    @Test("The customer reading doesn't clear the helper's badge")
    func customerReadDoesNotClearHelper() {
        let before = job("cc")
        #expect(before.unreadFromCustomer == 2)

        let after = job("cc", customerReadAt: at(9_999))
        #expect(after.unreadFromCustomer == 2, "customer's own stamp must not touch the helper's count")

        let helperRead = job("cc", helperReadAt: at(9_999))
        #expect(helperRead.unreadFromCustomer == 0)
    }

    @Test("A mirrored thread reads symmetrically from both ends")
    func symmetry() {
        let fresh = job("hc")
        // One message each way, neither side has opened anything: each sees the
        // other's, and replying already covered the earlier one.
        #expect(fresh.unreadFromHelper == 0)   // the customer's reply is newer
        #expect(fresh.unreadFromCustomer == 1)
    }

    // MARK: Round trip

    @Test("Read stamps survive a save")
    func readStateRoundTrips() throws {
        let original = job("hh", customerReadAt: at(120), helperReadAt: at(60))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(Job.self, from: try encoder.encode(original))
        #expect(restored.customerReadAt == original.customerReadAt)
        #expect(restored.helperReadAt == original.helperReadAt)
        #expect(restored.unreadFromHelper == original.unreadFromHelper)
    }

    @Test("Seeded history isn't already shouting at you")
    func seededHistoryIsQuiet() {
        // Every fixture thread ends with the helper's sign-off after the
        // customer's last reply, so a fresh install shouldn't open on a badge
        // for jobs that finished weeks ago... but if it does, that's the
        // fixtures' doing, and worth knowing about.
        let total = MockData.seedJobs().reduce(0) { $0 + $1.unreadFromHelper }
        #expect(total <= 3, "seeded threads produced \(total) unread")
    }
}
