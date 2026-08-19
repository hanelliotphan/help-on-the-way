import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Vetting")
struct VettingTests {

    private var sitter: Helper { MockData.helper(MockData.fixedID(13))! }   // Bianca
    private var tutor: Helper { MockData.helper(MockData.fixedID(14))! }    // Idris
    private var carer: Helper { MockData.helper(MockData.fixedID(15))! }    // Fiona
    private var handyman: Helper { MockData.helper(MockData.fixedID(2))! }  // Terrence

    // MARK: Which work needs what

    @Test("Care work demands credentials beyond the ordinary check")
    func enhancedRequirements() {
        #expect(Vetting.required(for: .babysitting).contains(.paediatricFirstAid))
        #expect(Vetting.required(for: .tutoring).contains(.teachingCredential))
        #expect(Vetting.required(for: .seniorCare).contains(.careCertified))
        for category in [HelpCategory.babysitting, .tutoring, .seniorCare] {
            #expect(Vetting.required(for: category).contains(.enhancedCheck), "\(category)")
            #expect(category.trustTier == .enhanced)
        }
    }

    @Test("Ordinary work asks only for the ordinary check")
    func standardRequirements() {
        for category in HelpCategory.allCases where category.trustTier == .standard {
            #expect(Vetting.required(for: category) == [.backgroundChecked], "\(category)")
        }
    }

    // MARK: The filter

    @Test("A helper without the credential cannot be offered the work")
    func uncredentialedIsRefused() {
        // Terrence is a fine handyman and holds no care credentials.
        #expect(!Vetting.isEligible(handyman, for: .babysitting))
        #expect(!Vetting.isEligible(handyman, for: .tutoring))
        #expect(!Vetting.isEligible(handyman, for: .seniorCare))
        #expect(Vetting.isEligible(handyman, for: .handyman))
    }

    @Test("Credentialed helpers pass")
    func credentialedPasses() {
        #expect(Vetting.isEligible(sitter, for: .babysitting))
        #expect(Vetting.isEligible(tutor, for: .tutoring))
        #expect(Vetting.isEligible(carer, for: .seniorCare))
    }

    @Test("Claiming the skill isn't enough on its own")
    func skillWithoutCredentialIsNotEnough() {
        // The whole point: `handles` is a claim, the credential is the check.
        var pretender = handyman
        pretender.skills.append(.babysitting)
        #expect(pretender.handles(.babysitting))
        #expect(!Vetting.canTake(pretender, .babysitting), "a skill claim must not bypass vetting")
    }

    @Test("The credential alone isn't enough either — they have to do the work")
    func credentialWithoutSkill() {
        // Idris is enhanced-checked but is a tutor, not a sitter.
        #expect(tutor.badges.contains(.enhancedCheck))
        #expect(!Vetting.canTake(tutor, .babysitting))
    }

    @Test("What's missing is named, so the helper app can say why")
    func missingIsNamed() {
        let missing = Vetting.missing(for: handyman, category: .babysitting)
        #expect(Set(missing) == [.enhancedCheck, .paediatricFirstAid])
        #expect(Vetting.missing(for: sitter, category: .babysitting).isEmpty)
    }

    // MARK: Matching actually enforces it

    @Test("Nobody uncredentialed is ever ranked for care work")
    func matchingExcludesUncredentialed() {
        for category in [HelpCategory.babysitting, .tutoring, .seniorCare] {
            let matches = Matching.candidates(
                for: category, near: MockData.homePoint, in: MockData.helpers, withinMiles: 100
            )
            #expect(!matches.isEmpty, "nobody covers \(category)")
            for match in matches {
                #expect(Vetting.isEligible(match.helper, for: category),
                        "\(match.helper.displayName) was offered \(category) without credentials")
            }
        }
    }

    @Test("A skill claim can't get somebody into the matching pool")
    func matchingIgnoresBareSkillClaims() {
        var pretender = handyman
        pretender.skills.append(.babysitting)
        let matches = Matching.candidates(
            for: .babysitting, near: MockData.homePoint, in: [pretender], withinMiles: 100
        )
        #expect(matches.isEmpty)
    }

    @Test("Every category still has somebody who can take it")
    func rosterCoversTheCatalogue() {
        for category in HelpCategory.allCases {
            let matches = Matching.candidates(
                for: category, near: MockData.homePoint, in: MockData.helpers, withinMiles: 100
            )
            #expect(!matches.isEmpty, "nobody can take \(category.title)")
        }
    }

    // MARK: Timing

    @Test("Care work is never dispatched instantly")
    func enhancedIsScheduledOnly() {
        for category in HelpCategory.allCases where category.trustTier == .enhanced {
            #expect(!category.supportsInstant,
                    "\(category.title) must not be auto-dispatched to a stranger")
        }
    }

    @Test("Care work asks for more notice than an hour")
    func enhancedNeedsMoreNotice() {
        #expect(Vetting.minimumLeadMinutes(for: .babysitting) > Scheduling.minimumLeadMinutes)
        #expect(Vetting.minimumLeadMinutes(for: .handyman) == Scheduling.minimumLeadMinutes)

        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 9))!
        let inTwoHours = now.addingTimeInterval(2 * 3600)
        // Fine for a handyman, too soon for a sitter.
        #expect(Scheduling.isBookable(start: inTwoHours, minutes: 60, now: now))
        #expect(!Scheduling.isBookable(
            start: inTwoHours, minutes: 180, now: now,
            leadMinutes: Vetting.minimumLeadMinutes(for: .babysitting)
        ))
    }

    // MARK: What the customer is told

    @Test("The assurance names the actual checks")
    func assuranceNamesChecks() {
        let text = Vetting.assurance(for: .babysitting)
        #expect(text?.contains(HelperBadge.paediatricFirstAid.title) == true)
        #expect(text?.contains(HelperBadge.enhancedCheck.title) == true)
        #expect(Vetting.assurance(for: .handyman) == nil)
    }

    @Test("Every enhanced category explains itself")
    func vettingNotes() {
        for category in HelpCategory.allCases {
            if category.trustTier == .enhanced {
                #expect(category.vettingNote?.isEmpty == false, "\(category) has no note")
            } else {
                #expect(category.vettingNote == nil, "\(category) shouldn't have one")
            }
        }
    }

    @Test("Every badge says what it means")
    func badgesExplainThemselves() {
        for badge in HelperBadge.allCases {
            #expect(!badge.title.isEmpty)
            #expect(!badge.detail.isEmpty)
        }
    }

    // MARK: The new categories are complete

    @Test("Every new category is fully specified")
    func newCategoriesAreComplete() {
        for category in [HelpCategory.babysitting, .tutoring, .seniorCare, .mealPrep] {
            #expect(!category.title.isEmpty)
            #expect(!category.tagline.isEmpty)
            #expect(category.defaultHourlyRate > .zero)
            #expect(category.minimumMinutes >= 60)
            #expect(!category.checklist.isEmpty)
            #expect(!category.defaultJobTitle.isEmpty)
            #expect(!category.suggestedMinutes.isEmpty)
            // Every suggestion has to be bookable against the block minimum.
            #expect(category.suggestedMinutes.allSatisfy { $0 >= category.minimumMinutes }
                    || category.suggestedMinutes.contains(category.minimumMinutes))
        }
    }

    @Test("Care shifts book in blocks, not by the hour")
    func careBooksInBlocks() {
        #expect(HelpCategory.babysitting.minimumMinutes >= 180)
        #expect(HelpCategory.seniorCare.minimumMinutes >= 180)
    }
}
