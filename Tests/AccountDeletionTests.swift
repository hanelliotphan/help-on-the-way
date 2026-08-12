import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Account deletion")
struct AccountDeletionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func job(
        _ title: String,
        status: JobStatus,
        startsIn seconds: TimeInterval = 0,
        photos: Int = 0,
        messages: Int = 0
    ) -> Job {
        var job = Job(
            category: .handyman,
            title: title,
            address: MockData.addresses[0],
            timing: status == .scheduled ? .scheduled(start: now.addingTimeInterval(seconds)) : .now,
            estimatedMinutes: 60,
            quote: Pricing.quote(category: .handyman, requestedMinutes: 60, hourlyRate: .usd(58), timing: .now),
            status: status
        )
        job.photoNames = (0..<photos).map { "photo-\($0).jpg" }
        job.messages = (0..<messages).map {
            Message(at: now, body: "m\($0)", fromCustomer: $0.isMultiple(of: 2))
        }
        return job
    }

    // MARK: Blockers

    @Test("A clean account deletes")
    func noBlockers() {
        let jobs = [job("Done", status: .completed), job("Dropped", status: .cancelled)]
        #expect(AccountDeletion.blockers(in: jobs, now: now).isEmpty)
        #expect(AccountDeletion.canDelete(jobs: jobs, now: now))
    }

    @Test("An empty account deletes")
    func emptyAccount() {
        #expect(AccountDeletion.canDelete(jobs: [], now: now))
    }

    @Test("A job in flight blocks deletion")
    func liveJobBlocks() {
        for status: JobStatus in [.searching, .accepted, .enRoute, .arrived, .inProgress] {
            let jobs = [job("Live one", status: status)]
            #expect(!AccountDeletion.canDelete(jobs: jobs, now: now), "\(status) should block")
        }
    }

    @Test("A booking still ahead blocks deletion")
    func scheduledJobBlocks() {
        let jobs = [job("Next week", status: .scheduled, startsIn: 7 * 86_400)]
        let blockers = AccountDeletion.blockers(in: jobs, now: now)
        #expect(blockers.count == 1)
        #expect(!AccountDeletion.canDelete(jobs: jobs, now: now))
    }

    @Test("A booking whose slot has passed doesn't block")
    func pastScheduledDoesNotBlock() {
        // Stale rather than pending: nobody is waiting on it.
        let jobs = [job("Last month", status: .scheduled, startsIn: -30 * 86_400)]
        #expect(AccountDeletion.canDelete(jobs: jobs, now: now))
    }

    @Test("Finished work never blocks")
    func finishedNeverBlocks() {
        for status: JobStatus in [.completed, .cancelled, .unmatched] {
            #expect(AccountDeletion.canDelete(jobs: [job("Old", status: status)], now: now), "\(status)")
        }
    }

    @Test("Every blocker says what it is and what to do")
    func blockersExplainThemselves() {
        let jobs = [
            job("Leaky tap", status: .enRoute),
            job("Deep clean", status: .scheduled, startsIn: 3 * 86_400),
        ]
        let blockers = AccountDeletion.blockers(in: jobs, now: now)
        #expect(blockers.count == 2)
        for blocker in blockers {
            #expect(!blocker.message.isEmpty)
            #expect(!blocker.remedy.isEmpty)
        }
        // The live one is listed first, because it's the more urgent thing.
        #expect(blockers.first == .liveJob(title: "Leaky tap", status: .enRoute))
    }

    @Test("The seeded account can be deleted")
    func seededAccountDeletes() {
        // All the fixture history is finished work, so nothing should block.
        #expect(AccountDeletion.canDelete(jobs: MockData.seedJobs(), now: Date()))
    }

    // MARK: Confirmation

    @Test("The typed word has to match")
    func confirmationMatching() {
        #expect(AccountDeletion.matchesConfirmation("DELETE"))
        #expect(AccountDeletion.matchesConfirmation("delete"))
        #expect(AccountDeletion.matchesConfirmation("  Delete  "))
        #expect(!AccountDeletion.matchesConfirmation(""))
        #expect(!AccountDeletion.matchesConfirmation("DELET"))
        #expect(!AccountDeletion.matchesConfirmation("DELETE ACCOUNT"))
        #expect(!AccountDeletion.matchesConfirmation("yes"))
    }

    // MARK: Summary

    @Test("The summary counts what's actually there")
    func summaryCounts() {
        let jobs = [
            job("One", status: .completed, photos: 2, messages: 3),
            job("Two", status: .cancelled, photos: 1, messages: 1),
        ]
        let lines = AccountDeletion.summary(
            jobs: jobs,
            addresses: MockData.addresses,
            paymentMethods: MockData.paymentMethods,
            favourites: 2
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("2 past jobs"))
        #expect(joined.contains("3 attached photos"))
        #expect(joined.contains("3 saved addresses"))
        #expect(joined.contains("3 saved cards"))
        #expect(joined.contains("2 saved helpers"))
        // Always mentioned, since it's always there.
        #expect(joined.contains("name, phone number and email"))
    }

    @Test("Singulars read as singulars")
    func summarySingulars() {
        let lines = AccountDeletion.summary(
            jobs: [job("One", status: .completed, photos: 1, messages: 1)],
            addresses: [MockData.addresses[0]],
            paymentMethods: [MockData.paymentMethods[0]],
            favourites: 1
        )
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("1 past job,"))
        #expect(joined.contains("1 attached photo"))
        #expect(joined.contains("1 saved address"))
        #expect(joined.contains("1 saved card"))
        #expect(joined.contains("1 saved helper"))
    }

    @Test("Nothing on the account means nothing listed but the personal details")
    func summaryOfAnEmptyAccount() {
        let lines = AccountDeletion.summary(jobs: [], addresses: [], paymentMethods: [], favourites: 0)
        #expect(lines.count == 1)
        #expect(lines[0].contains("name, phone number and email"))
    }

    @Test("System messages aren't counted as conversation")
    func summaryIgnoresSystemMessages() {
        var withSystem = job("One", status: .completed)
        withSystem.messages = [
            Message(at: now, body: "Helper assigned", fromCustomer: false, isSystem: true),
            Message(at: now, body: "On my way", fromCustomer: false),
        ]
        let joined = AccountDeletion.summary(
            jobs: [withSystem], addresses: [], paymentMethods: [], favourites: 0
        ).joined(separator: "\n")
        // One real message, not two.
        #expect(joined.contains("1 message"))
    }
}
