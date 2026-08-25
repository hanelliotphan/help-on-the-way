import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Reputation")
struct ReputationTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Terrence: 4.89 over 848 jobs. The busy veteran.
    private var veteran: Helper { MockData.helper(MockData.fixedID(2))! }
    /// Saoirse: 4.84 over 147 jobs. Comparatively new.
    private var newcomer: Helper { MockData.helper(MockData.fixedID(12))! }

    private func review(_ stars: Int, at offset: TimeInterval = 0, body: String = "Fine") -> Review {
        Review(
            author: "A customer", stars: stars, body: body,
            category: .handyman, daysAgo: 0,
            postedAt: now.addingTimeInterval(offset), compliments: []
        )
    }

    // MARK: The average

    @Test("No reviews leaves the seeded rating alone")
    func noReviews() {
        #expect(Reputation.average(seedRating: 4.89, jobsCompleted: 848, reviews: []) == 4.89)
    }

    @Test("One bad review can't erase eight hundred good jobs")
    func oneBadReviewBarelyMoves() {
        let after = Reputation.average(seedRating: 4.89, jobsCompleted: 848, reviews: [review(1)])
        #expect(after < 4.89)
        #expect(4.89 - after < 0.02, "moved \(4.89 - after), which is too much for one review")
    }

    @Test("A newcomer feels a review more than a veteran does")
    func newcomersMoveFaster() {
        let bad = [review(1)]
        let veteranDrop = veteran.rating - Reputation.average(
            seedRating: veteran.rating, jobsCompleted: veteran.jobsCompleted, reviews: bad
        )
        let newcomerDrop = newcomer.rating - Reputation.average(
            seedRating: newcomer.rating, jobsCompleted: newcomer.jobsCompleted, reviews: bad
        )
        #expect(newcomerDrop > veteranDrop)
    }

    @Test("A brand-new helper isn't defined by their first review")
    func priorHasAFloor() {
        // Without a floor, one 5-star on a 2-job helper would read as a perfect 5.
        let after = Reputation.average(seedRating: 4.0, jobsCompleted: 2, reviews: [review(5)])
        #expect(after < 4.1, "one review swung a new helper to \(after)")
        #expect(Reputation.priorWeight(jobsCompleted: 0) == Reputation.minimumPriorWeight)
    }

    @Test("A very busy helper isn't mathematically immune to feedback")
    func priorHasACeiling() {
        #expect(Reputation.priorWeight(jobsCompleted: 100_000) == Reputation.maximumPriorWeight)
        let after = Reputation.average(seedRating: 5.0, jobsCompleted: 100_000, reviews: [review(1)])
        #expect(after < 5.0)
    }

    @Test("Good reviews pull up, bad ones pull down")
    func directionIsRight() {
        let up = Reputation.average(seedRating: 4.5, jobsCompleted: 100, reviews: [review(5), review(5)])
        let down = Reputation.average(seedRating: 4.5, jobsCompleted: 100, reviews: [review(2), review(2)])
        #expect(up > 4.5)
        #expect(down < 4.5)
    }

    @Test("The average is rounded to what the screens display")
    func roundedToTwoPlaces() {
        let value = Reputation.average(seedRating: 4.89, jobsCompleted: 848, reviews: [review(3)])
        // Compared with a tolerance, not for exact equality: 4.89 × 100 is
        // 488.99999999999994 in binary floating point, so an equality check here
        // tests Double's representation rather than the rounding.
        #expect(abs(value * 100 - (value * 100).rounded()) < 1e-9)
        #expect(Format.rating(value).split(separator: ".").last?.count == 2)
    }

    // MARK: Merging

    @Test("A published review lands at the top of the profile")
    func newestFirst() {
        let merged = Reputation.merged(veteran, published: [
            review(5, at: 0, body: "older"),
            review(4, at: 1_000, body: "newer"),
        ])
        #expect(merged.reviews.first?.body == "newer")
        #expect(merged.reviews.count == veteran.reviews.count + 2)
    }

    @Test("Merging keeps the seeded reviews underneath")
    func seededReviewsSurvive() {
        let merged = Reputation.merged(veteran, published: [review(5)])
        for original in veteran.reviews {
            #expect(merged.reviews.contains(original), "lost seeded review from \(original.author)")
        }
    }

    @Test("A reviewed job counts towards the job total")
    func jobsCompletedGrows() {
        let merged = Reputation.merged(veteran, published: [review(5), review(4)])
        #expect(merged.jobsCompleted == veteran.jobsCompleted + 2)
    }

    @Test("Merging nothing changes nothing")
    func mergingNothing() {
        #expect(Reputation.merged(veteran, published: []) == veteran)
        #expect(Reputation.roster(MockData.helpers, published: [:]) == MockData.helpers)
    }

    @Test("Only the reviewed helper is touched")
    func othersUnaffected() {
        let roster = Reputation.roster(MockData.helpers, published: [veteran.id: [review(1)]])
        for helper in roster where helper.id != veteran.id {
            #expect(helper == MockData.helper(helper.id), "\(helper.displayName) changed")
        }
        #expect(roster.first { $0.id == veteran.id }?.rating != veteran.rating)
    }

    // MARK: Turning a rating into a review

    @Test("A rating with stars becomes a review")
    func ratingBecomesReview() {
        let rating = JobRating(stars: 5, comment: "Spotless", tip: .usd(10), compliments: ["On time"])
        let review = Reputation.review(from: rating, author: "Han-Elliot Phan", category: .cleaning, at: now)
        #expect(review?.stars == 5)
        #expect(review?.body == "Spotless")
        #expect(review?.author == "Han-Elliot Phan")
        #expect(review?.category == .cleaning)
        #expect(review?.postedAt == now)
        #expect(review?.complimentList == ["On time"])
    }

    @Test("A skipped rating is not a review")
    func skippedRatingIsNotPublished() {
        // Skip writes zero stars; that has no business on somebody's profile.
        let skipped = JobRating(stars: 0, comment: "", tip: .zero)
        #expect(Reputation.review(from: skipped, author: "Anyone", category: .handyman, at: now) == nil)
    }

    @Test("Stars without a comment still publish")
    func starsAloneArePublished() {
        let rating = JobRating(stars: 4, comment: "   ", tip: .zero, compliments: ["Friendly"])
        let review = Reputation.review(from: rating, author: "Han", category: .handyman, at: now)
        #expect(review != nil)
        #expect(review?.body.isEmpty == true)
        #expect(review?.complimentList == ["Friendly"])
    }

    @Test("An anonymous customer still gets attributed")
    func blankAuthorFallsBack() {
        let rating = JobRating(stars: 5, comment: "Great", tip: .zero)
        let review = Reputation.review(from: rating, author: "  ", category: .handyman, at: now)
        #expect(review?.author == "A customer")
    }

    // MARK: Display and storage

    @Test("A real date is shown as one; a fixture falls back to its age")
    func ageLabel() {
        let posted = review(5, at: -3_600)
        #expect(posted.ageLabel(now: now) == Format.ago(now.addingTimeInterval(-3_600), now: now))

        let seeded = Review(author: "Molly T.", stars: 5, body: "x", category: .handyman, daysAgo: 3)
        #expect(seeded.ageLabel(now: now) == Format.agoInDays(3))
    }

    @Test("Published reviews survive a save")
    func roundTrips() throws {
        var snapshot = StoreSnapshot.seeded()
        snapshot.publishedReviews = [veteran.id: [review(5, body: "Kept")]]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(StoreSnapshot.self, from: try encoder.encode(snapshot))
        #expect(restored.reviewsByHelper[veteran.id]?.first?.body == "Kept")
    }

    @Test("A store written before reviews existed still decodes")
    func olderStoreStillLoads() throws {
        // The field is optional precisely so adding it didn't wipe every account.
        var snapshot = StoreSnapshot.seeded()
        snapshot.publishedReviews = nil

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(StoreSnapshot.self, from: try encoder.encode(snapshot))
        #expect(restored.reviewsByHelper.isEmpty)
    }

    @Test("The seeded roster is unchanged until somebody reviews")
    func seededRosterIsTheBaseline() {
        for helper in MockData.helpers {
            #expect(Reputation.merged(helper, published: []).rating == helper.rating)
        }
    }
}

@Suite("Storage and roster caching")
@MainActor
struct RosterStorageTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func review(_ stars: Int, body: String = "Good") -> Review {
        Review(author: "A customer", stars: stars, body: body,
               category: .handyman, daysAgo: 0, postedAt: now, compliments: [])
    }

    private func job(with helper: Helper) -> Job {
        var job = Job(
            category: .handyman, title: "Test", address: MockData.addresses[0],
            timing: .now, estimatedMinutes: 60,
            quote: Pricing.quote(category: .handyman, requestedMinutes: 60,
                                 hourlyRate: .usd(58), timing: .now),
            status: .completed
        )
        job.helper = helper
        return job
    }

    // MARK: What a job stores about its helper

    @Test("A job's helper record carries no reviews")
    func jobRecordDropsReviews() {
        let helper = MockData.helpers[0]
        #expect(!helper.reviews.isEmpty, "fixture should have reviews to drop")

        let record = helper.forJobRecord
        #expect(record.reviews.isEmpty)
        // Everything a receipt actually needs survives.
        #expect(record.id == helper.id)
        #expect(record.displayName == helper.displayName)
        #expect(record.hourlyRate == helper.hourlyRate)
        #expect(record.rating == helper.rating)
        #expect(record.badges == helper.badges)
        #expect(record.vehicle == helper.vehicle)
    }

    @Test("Trimming twice changes nothing the second time")
    func jobRecordIsIdempotent() {
        let once = MockData.helpers[0].forJobRecord
        #expect(once.forJobRecord == once)
    }

    @Test("Published reviews don't leak into a job record")
    func publishedReviewsDoNotLeak() {
        // The bug: a helper merged with published reviews got snapshotted onto
        // every job they took, duplicating every review into every job.
        let merged = Reputation.merged(MockData.helpers[0], published: [review(5), review(4)])
        #expect(merged.reviews.count > MockData.helpers[0].reviews.count)
        #expect(merged.forJobRecord.reviews.isEmpty)
    }

    @Test("Loading trims review lists off historical jobs")
    func normalisationTrimsExistingJobs() {
        var snapshot = StoreSnapshot.seeded()
        snapshot.jobs = [job(with: MockData.helpers[0]), job(with: MockData.helpers[1])]
        #expect(snapshot.jobs.allSatisfy { $0.helper?.reviews.isEmpty == false })

        let cleaned = snapshot.normalised()
        #expect(cleaned.jobs.allSatisfy { $0.helper?.reviews.isEmpty == true })
        // And nothing else moved.
        #expect(cleaned.jobs.map(\.id) == snapshot.jobs.map(\.id))
        #expect(cleaned.jobs.compactMap { $0.helper?.displayName }
                == snapshot.jobs.compactMap { $0.helper?.displayName })
    }

    @Test("Normalising is safe on jobs with no helper")
    func normalisationHandlesUnassignedJobs() {
        var snapshot = StoreSnapshot.seeded()
        var unassigned = job(with: MockData.helpers[0])
        unassigned.helper = nil
        snapshot.jobs = [unassigned]
        #expect(snapshot.normalised().jobs.first?.helper == nil)
    }

    @Test("Trimming measurably shrinks what gets written")
    func trimmingShrinksTheStore() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var fat = StoreSnapshot.seeded()
        fat.jobs = MockData.helpers.prefix(6).map { job(with: $0) }
        let before = try encoder.encode(fat).count
        let after = try encoder.encode(fat.normalised()).count

        #expect(after < before)
        // The duplication was over a quarter of the document.
        #expect(Double(before - after) / Double(before) > 0.2)
    }

    // MARK: Roster caching

    @Test("The cached roster starts as the seed")
    func cacheStartsAsSeed() {
        let backend = DemoBackend()
        #expect(backend.roster == MockData.helpers)
    }

    @Test("Publishing a review refreshes the cache")
    func cacheRefreshesOnApply() {
        let backend = DemoBackend()
        let target = MockData.helpers[0]
        let before = backend.roster.first { $0.id == target.id }?.reviews.count ?? 0

        backend.apply(publishedReviews: [target.id: [review(5, body: "New")]])
        let after = backend.roster.first { $0.id == target.id }
        #expect(after?.reviews.count == before + 1)
        #expect(after?.reviews.first?.body == "New")
    }

    @Test("Reading the roster repeatedly gives the same value")
    func cacheIsStable() {
        let backend = DemoBackend()
        backend.apply(publishedReviews: [MockData.helpers[0].id: [review(4)]])
        #expect(backend.roster == backend.roster)
    }

    @Test("Applying the same reviews again is a no-op")
    func cacheSkipsRedundantWork() {
        let backend = DemoBackend()
        let reviews = [MockData.helpers[0].id: [review(5)]]
        backend.apply(publishedReviews: reviews)
        let first = backend.roster
        backend.apply(publishedReviews: reviews)
        #expect(backend.roster == first)
    }

    @Test("Clearing the reviews puts the roster back to the seed")
    func cacheClears() {
        let backend = DemoBackend()
        backend.apply(publishedReviews: [MockData.helpers[0].id: [review(1)]])
        #expect(backend.roster != MockData.helpers)
        backend.apply(publishedReviews: [:])
        #expect(backend.roster == MockData.helpers)
    }

    @Test("A helper looked up by id comes from the merged roster")
    func lookupUsesMergedRoster() {
        let backend = DemoBackend()
        let target = MockData.helpers[0]
        backend.apply(publishedReviews: [target.id: [review(5)]])
        #expect(backend.helper(target.id)?.reviews.count == target.reviews.count + 1)
        #expect(backend.helper(UUID()) == nil)
    }
}
