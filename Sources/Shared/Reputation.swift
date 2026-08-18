import Foundation

/// What a helper's rating actually means once customers start writing reviews.
///
/// The roster in `MockData` is the starting point, not the truth. Reviews a
/// customer writes are stored separately and layered on top, which keeps the
/// fixtures as a seed and means the shared document only carries what somebody
/// actually typed.
enum Reputation {

    /// A helper's history counts as evidence.
    ///
    /// Averaging the seeded rating with new reviews as equals would let one bad
    /// night erase eight hundred good jobs — and would make a brand-new helper's
    /// first review a perfect 5.00. So the existing record is weighted by the
    /// jobs behind it, and each new review carries a weight of one.
    ///
    /// The floor stops a helper with almost no history being defined by a single
    /// review; the ceiling stops a very busy one being mathematically immune to
    /// feedback forever.
    static let minimumPriorWeight = 20.0
    static let maximumPriorWeight = 400.0

    static func priorWeight(jobsCompleted: Int) -> Double {
        min(max(Double(jobsCompleted), minimumPriorWeight), maximumPriorWeight)
    }

    /// The blended average, rounded the way it's displayed.
    static func average(seedRating: Double, jobsCompleted: Int, reviews: [Review]) -> Double {
        guard !reviews.isEmpty else { return seedRating }
        let weight = priorWeight(jobsCompleted: jobsCompleted)
        let total = seedRating * weight + reviews.reduce(0.0) { $0 + Double($1.stars) }
        let count = weight + Double(reviews.count)
        // Two decimals, because that's what every screen shows.
        return ((total / count) * 100).rounded() / 100
    }

    /// A helper as they should appear now: newest reviews first, rating rederived.
    static func merged(_ helper: Helper, published: [Review]) -> Helper {
        guard !published.isEmpty else { return helper }
        var updated = helper
        // Newest first — a profile opens on what somebody said most recently.
        updated.reviews = published.sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
            + helper.reviews
        updated.rating = average(
            seedRating: helper.rating,
            jobsCompleted: helper.jobsCompleted,
            reviews: published
        )
        // A completed, reviewed job is a completed job.
        updated.jobsCompleted = helper.jobsCompleted + published.count
        return updated
    }

    static func roster(_ base: [Helper], published: [UUID: [Review]]) -> [Helper] {
        guard !published.isEmpty else { return base }
        return base.map { merged($0, published: published[$0.id] ?? []) }
    }

    /// Turns a submitted rating into a review fit to publish.
    ///
    /// Returns nil for a skipped rating — a zero-star "no thanks" is not a review
    /// and has no business on somebody's profile. A rating with stars but no
    /// comment still publishes: the number and any compliments are the point.
    static func review(
        from rating: JobRating,
        author: String,
        category: HelpCategory,
        at date: Date
    ) -> Review? {
        guard rating.stars > 0 else { return nil }
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return Review(
            author: trimmedAuthor.isEmpty ? "A customer" : trimmedAuthor,
            stars: rating.stars,
            body: rating.comment.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            daysAgo: 0,
            postedAt: date,
            compliments: rating.compliments
        )
    }
}
