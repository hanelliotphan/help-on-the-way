import Foundation

struct HelperMatch: Identifiable, Hashable, Sendable {
    var helper: Helper
    var miles: Double
    var etaMinutes: Int
    var score: Double
    var isFavorite: Bool

    var id: UUID { helper.id }
}

/// Picks who gets asked, and in what order. Instant requests take the top
/// match automatically; scheduled requests hand the same ranked list to the
/// customer to choose from.
enum Matching {
    static let radiusMiles: Double = 12

    /// Weights, gathered here so the ranking is arguable in one place rather
    /// than buried in a sort closure.
    static let starWeight = 1.0
    static let milePenalty = 0.22
    static let favoriteBonus = 0.9
    static let quickResponderBonus = 0.25
    /// Experience matters, but a 900-job helper shouldn't outrank a 400-job one
    /// across town, so it's deliberately a small, saturating term.
    static let volumeWeight = 0.4

    static func candidates(
        for category: HelpCategory,
        near point: GeoPoint,
        in helpers: [Helper],
        favorites: Set<UUID> = [],
        withinMiles: Double = radiusMiles,
        limit: Int? = nil
    ) -> [HelperMatch] {
        let matches = helpers
            .filter { $0.handles(category) }
            .map { helper -> HelperMatch in
                let miles = helper.basePoint.miles(to: point)
                let isFavorite = favorites.contains(helper.id)
                return HelperMatch(
                    helper: helper,
                    miles: miles,
                    etaMinutes: Dispatch.travelMinutes(from: helper.basePoint, to: point),
                    score: score(helper: helper, miles: miles, isFavorite: isFavorite),
                    isFavorite: isFavorite
                )
            }
            .filter { $0.miles <= withinMiles }
            // Ties break on id so the same request always ranks the same way.
            .sorted { ($0.score, $0.helper.id.uuidString) > ($1.score, $1.helper.id.uuidString) }

        guard let limit else { return matches }
        return Array(matches.prefix(limit))
    }

    static func score(helper: Helper, miles: Double, isFavorite: Bool) -> Double {
        var total = helper.rating * starWeight
        total -= miles * milePenalty
        total += min(Double(helper.jobsCompleted) / 600, 1) * volumeWeight
        if helper.badges.contains(.quickResponder) { total += quickResponderBonus }
        if isFavorite { total += favoriteBonus }
        return total
    }

    static func best(
        for category: HelpCategory,
        near point: GeoPoint,
        in helpers: [Helper],
        favorites: Set<UUID> = [],
        excluding excluded: Set<UUID> = []
    ) -> HelperMatch? {
        candidates(for: category, near: point, in: helpers, favorites: favorites)
            .first { !excluded.contains($0.helper.id) }
    }

    /// How many helpers the request actually went out to — the number the
    /// matching screen counts down.
    static func pingCount(for category: HelpCategory, near point: GeoPoint, in helpers: [Helper]) -> Int {
        candidates(for: category, near: point, in: helpers, withinMiles: 6).count
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recommended
        case rating
        case price
        case distance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recommended: "Recommended"
            case .rating: "Highest rated"
            case .price: "Lowest rate"
            case .distance: "Closest"
            }
        }
    }

    static func sorted(_ matches: [HelperMatch], by sort: Sort) -> [HelperMatch] {
        switch sort {
        case .recommended:
            matches
        case .rating:
            matches.sorted { ($0.helper.rating, $0.helper.jobsCompleted) > ($1.helper.rating, $1.helper.jobsCompleted) }
        case .price:
            matches.sorted { ($0.helper.hourlyRate, $1.helper.rating) < ($1.helper.hourlyRate, $0.helper.rating) }
        case .distance:
            matches.sorted { $0.miles < $1.miles }
        }
    }
}
