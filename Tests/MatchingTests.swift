import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Matching")
struct MatchingTests {

    private let roster = MockData.helpers
    private let home = MockData.homePoint

    // MARK: Filtering

    @Test("Only helpers who do the work get asked")
    func filtersByCategory() {
        let matches = Matching.candidates(for: .petCare, near: home, in: roster)
        #expect(!matches.isEmpty)
        for match in matches {
            #expect(match.helper.handles(.petCare))
        }
        // Nobody who only does event work should turn up on a pet-care request.
        #expect(!matches.contains { $0.helper.id == MockData.fixedID(9) })
    }

    @Test("Every category has somebody who covers it")
    func rosterCoversTheCatalog() {
        for category in HelpCategory.allCases {
            let matches = Matching.candidates(for: category, near: home, in: roster)
            #expect(!matches.isEmpty, "no helper covers \(category.title)")
        }
    }

    @Test("The radius is respected")
    func radiusFilters() {
        let tight = Matching.candidates(for: .handyman, near: home, in: roster, withinMiles: 0.75)
        let wide = Matching.candidates(for: .handyman, near: home, in: roster, withinMiles: 30)
        #expect(tight.count < wide.count)
        for match in tight {
            #expect(match.miles <= 0.75)
        }
    }

    @Test("An empty roster matches nobody rather than crashing")
    func emptyRoster() {
        #expect(Matching.candidates(for: .cleaning, near: home, in: []).isEmpty)
        #expect(Matching.best(for: .cleaning, near: home, in: []) == nil)
    }

    // MARK: Ranking

    @Test("Results come back best-first")
    func resultsAreSortedByScore() {
        let matches = Matching.candidates(for: .handyman, near: home, in: roster)
        let scores = matches.map(\.score)
        #expect(scores == scores.sorted(by: >))
    }

    @Test("The same request always ranks the same way")
    func rankingIsDeterministic() {
        let first = Matching.candidates(for: .moving, near: home, in: roster).map(\.id)
        let second = Matching.candidates(for: .moving, near: home, in: roster).map(\.id)
        #expect(first == second)
    }

    @Test("Close, highly rated and quick to reply wins an assembly job")
    func bestAssemblyHelper() {
        let best = Matching.best(for: .assembly, near: home, in: roster)
        #expect(best?.helper.id == MockData.fixedID(3))   // Yuki T.
    }

    @Test("A saved helper is enough to jump the queue")
    func favoritesAreBoosted() {
        let terrence = MockData.fixedID(2)
        let neutral = Matching.best(for: .assembly, near: home, in: roster)
        #expect(neutral?.helper.id != terrence)

        let favoured = Matching.best(for: .assembly, near: home, in: roster, favorites: [terrence])
        #expect(favoured?.helper.id == terrence)
        #expect(favoured?.isFavorite == true)
    }

    @Test("A favourite still can't beat somebody miles better")
    func favoriteBoostIsBounded() {
        // Owen is the lowest-rated mover and the furthest out; a single
        // favourite bonus shouldn't be able to carry him to the top.
        let owen = MockData.fixedID(11)
        let best = Matching.best(for: .moving, near: home, in: roster, favorites: [owen])
        #expect(best?.helper.id != owen)
    }

    @Test("Excluding someone moves on to the next best")
    func exclusionFallsThrough() {
        let first = Matching.best(for: .assembly, near: home, in: roster)
        let second = Matching.best(for: .assembly, near: home, in: roster, excluding: [first!.helper.id])
        #expect(second != nil)
        #expect(second?.helper.id != first?.helper.id)
        #expect((second?.score ?? 0) <= (first?.score ?? 0))
    }

    @Test("An ETA comes back with every match")
    func matchesCarryAnEta() {
        for match in Matching.candidates(for: .cleaning, near: home, in: roster) {
            #expect(match.etaMinutes >= 3)
            #expect(match.miles >= 0)
        }
    }

    // MARK: Explicit sorts

    @Test("Sorting by price puts the cheapest first")
    func sortByPrice() {
        let sorted = Matching.sorted(Matching.candidates(for: .handyman, near: home, in: roster), by: .price)
        let rates = sorted.map(\.helper.hourlyRate)
        #expect(rates == rates.sorted())
    }

    @Test("Sorting by rating puts the highest first")
    func sortByRating() {
        let sorted = Matching.sorted(Matching.candidates(for: .cleaning, near: home, in: roster), by: .rating)
        let ratings = sorted.map(\.helper.rating)
        #expect(ratings == ratings.sorted(by: >))
    }

    @Test("Sorting by distance puts the closest first")
    func sortByDistance() {
        let sorted = Matching.sorted(Matching.candidates(for: .moving, near: home, in: roster), by: .distance)
        let miles = sorted.map(\.miles)
        #expect(miles == miles.sorted())
    }

    @Test("Recommended leaves the scored order alone")
    func sortRecommendedIsIdentity() {
        let matches = Matching.candidates(for: .techHelp, near: home, in: roster)
        #expect(Matching.sorted(matches, by: .recommended).map(\.id) == matches.map(\.id))
    }

    // MARK: Broadcast size

    @Test("The ping count only counts helpers genuinely nearby")
    func pingCountIsTight() {
        let all = Matching.candidates(for: .cleaning, near: home, in: roster).count
        let pinged = Matching.pingCount(for: .cleaning, near: home, in: roster)
        #expect(pinged > 0)
        #expect(pinged <= all)
    }
}

@Suite("Fixtures")
struct MockDataTests {

    @Test("Fixed ids are stable and well-formed")
    func fixedIDs() {
        #expect(MockData.fixedID(3) == MockData.fixedID(3))
        #expect(MockData.fixedID(3) != MockData.fixedID(4))
        #expect(MockData.helper(MockData.fixedID(3))?.firstName == "Yuki")
        #expect(MockData.helper(UUID()) == nil)
    }

    @Test("No two helpers share an id")
    func helperIDsAreUnique() {
        let ids = Set(MockData.helpers.map(\.id))
        #expect(ids.count == MockData.helpers.count)
    }

    @Test("Every helper looks like a real listing")
    func helpersAreWellFormed() {
        for helper in MockData.helpers {
            #expect(!helper.skills.isEmpty)
            #expect(helper.rating > 3.5 && helper.rating <= 5)
            #expect(helper.hourlyRate > .zero)
            #expect(helper.jobsCompleted > 0)
            #expect(!helper.reviews.isEmpty)
            #expect(helper.badges.contains(.backgroundChecked))
            #expect((0...1).contains(helper.accentHue))
            #expect(helper.initials.count == 2)
            // A review's category should be something they actually do.
            for review in helper.reviews {
                #expect(helper.handles(review.category))
                #expect((1...5).contains(review.stars))
            }
        }
    }

    @Test("Rebook rate stays a sane percentage")
    func repeatRateIsBounded() {
        for helper in MockData.helpers {
            #expect((55...94).contains(helper.repeatRate))
        }
    }

    @Test("Seeded history is all finished work")
    func seededJobsAreClosed() {
        let jobs = MockData.seedJobs()
        #expect(jobs.count == 4)
        for job in jobs {
            #expect(job.status.isFinished)
            #expect(!job.title.isEmpty)
        }
        #expect(jobs.filter { $0.status == .completed }.count == 3)
        #expect(jobs.filter { $0.rating != nil }.count == 3)
    }

    @Test("Seeded history is newest first")
    func seededJobsAreSorted() {
        let dates = MockData.seedJobs().map(\.createdAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("A completed job that ran long was billed for the overtime")
    func seededOvertimeIsBilled() {
        let jobs = MockData.seedJobs()
        let clean = jobs.first { $0.id == MockData.fixedID(301) }
        #expect(clean?.billedMinutes == 255)
        #expect((clean?.finalTotal ?? .zero) > (clean?.quote.total ?? .zero))
    }

    @Test("A cancelled job owes nothing")
    func seededCancellationIsFree() {
        let cancelled = MockData.seedJobs().first { $0.status == .cancelled }
        #expect(cancelled?.amountDue == .zero)
        #expect(cancelled?.helper == nil)
    }

    @Test("The demo account has a home, a card and a favourite")
    func accountFixtures() {
        #expect(MockData.addresses.count == 3)
        #expect(MockData.addresses.first?.label == "Home")
        #expect(MockData.paymentMethods.filter(\.isDefault).count == 1)
        #expect(MockData.profile.favoriteHelperIDs.count == 1)
    }
}
