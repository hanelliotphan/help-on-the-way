import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Cardholder and billing")
struct BillingEntryTests {

    private let good = (
        name: "Han-Elliot Phan",
        line1: "1042 Valencia St",
        city: "San Francisco",
        state: "CA",
        postal: "94110"
    )

    private func issues(
        name: String? = nil, line1: String? = nil, city: String? = nil,
        state: String? = nil, postal: String? = nil, country: String = "US"
    ) -> [BillingEntry.Issue] {
        BillingEntry.issues(
            name: name ?? good.name,
            line1: line1 ?? good.line1,
            city: city ?? good.city,
            state: state ?? good.state,
            postalCode: postal ?? good.postal,
            country: country
        )
    }

    // MARK: Name

    @Test("A complete set validates clean")
    func validSet() {
        #expect(issues().isEmpty)
    }

    @Test("A missing name is caught")
    func nameMissing() {
        #expect(issues(name: "").contains(.nameMissing))
        #expect(issues(name: "   ").contains(.nameMissing))
    }

    @Test("One word is flagged as a half-finished name, not as missing")
    func nameNeedsSurname() {
        let found = issues(name: "Han")
        #expect(found.contains(.nameLacksSurname))
        #expect(!found.contains(.nameMissing))
    }

    @Test("A hyphenated first name still counts as one part")
    func hyphenatedFirstName() {
        // "Han-Elliot Phan" is two whitespace-separated parts, which is the test.
        #expect(BillingEntry.hasTwoParts("Han-Elliot Phan"))
        #expect(!BillingEntry.hasTwoParts("Han-Elliot"))
        #expect(BillingEntry.hasTwoParts("Mary Jane Watson"))
    }

    @Test("Names are collapsed to single spaces")
    func nameNormalisation() {
        #expect(BillingEntry.normalisedName("  Han-Elliot   Phan \n") == "Han-Elliot Phan")
    }

    // MARK: Address parts

    @Test("Street, city, state and ZIP are each required")
    func requiredParts() {
        #expect(issues(line1: "").contains(.line1Missing))
        #expect(issues(city: "").contains(.cityMissing))
        #expect(issues(state: "").contains(.stateMissing))
        #expect(issues(postal: "").contains(.postalMissing))
    }

    @Test("A state has to be the two-letter code")
    func stateShape() {
        #expect(issues(state: "California").contains(.stateMalformed))
        #expect(issues(state: "C").contains(.stateMalformed))
        #expect(issues(state: "C4").contains(.stateMalformed))
        #expect(issues(state: "ca").isEmpty)   // case is a typing convenience
    }

    @Test("US ZIPs are five digits, or five plus four")
    func postalShape() {
        #expect(BillingEntry.isValidUSPostal("94110"))
        #expect(BillingEntry.isValidUSPostal("94110-1234"))
        #expect(!BillingEntry.isValidUSPostal("9411"))
        #expect(!BillingEntry.isValidUSPostal("941101"))
        #expect(!BillingEntry.isValidUSPostal("9411O"))       // letter O, not zero
        #expect(!BillingEntry.isValidUSPostal("94110-12"))
        #expect(!BillingEntry.isValidUSPostal("94110-"))
    }

    @Test("Outside the US any non-empty postal code is accepted")
    func postalOutsideUS() {
        // Nothing here is verifying against a postal service, so pretending to
        // know every country's format would be theatre.
        #expect(BillingEntry.isValidPostal("SW1A 1AA", country: "GB"))
        #expect(!BillingEntry.isValidPostal("  ", country: "GB"))
        #expect(issues(state: "Greater London", postal: "SW1A 1AA", country: "GB").isEmpty)
    }

    @Test("Every issue explains itself and points at a field")
    func issuesAreUsable() {
        let all: [BillingEntry.Issue] = [
            .nameMissing, .nameLacksSurname, .line1Missing, .cityMissing,
            .stateMissing, .stateMalformed, .postalMissing, .postalMalformed(country: "US"),
        ]
        for issue in all { #expect(!issue.message.isEmpty) }
        #expect(BillingEntry.Issue.nameMissing.field == .name)
        #expect(BillingEntry.Issue.postalMalformed(country: "US").field == .postalCode)
        // The message differs by country, since the rule does.
        #expect(BillingEntry.Issue.postalMalformed(country: "US").message
                != BillingEntry.Issue.postalMalformed(country: "GB").message)
    }

    // MARK: Building the stored value

    @Test("Stored addresses are trimmed and the state upper-cased")
    func addressNormalisation() {
        let billing = BillingEntry.billingAddress(
            line1: "  1042 Valencia St ", line2: " Apt 3B ",
            city: " San Francisco ", state: " ca ", postalCode: " 94110 "
        )
        #expect(billing.line1 == "1042 Valencia St")
        #expect(billing.line2 == "Apt 3B")
        #expect(billing.city == "San Francisco")
        #expect(billing.state == "CA")
        #expect(billing.postalCode == "94110")
    }

    @Test("An empty unit is stored as nothing rather than as blank")
    func emptyUnit() {
        let billing = BillingEntry.billingAddress(
            line1: "1042 Valencia St", line2: "   ",
            city: "San Francisco", state: "CA", postalCode: "94110"
        )
        #expect(billing.line2 == nil)
    }

    @Test("A saved address copies across")
    func fromSavedAddress() {
        let saved = MockData.addresses[0]
        let billing = BillingAddress(from: saved)
        #expect(billing.line1 == saved.street)
        #expect(billing.line2 == saved.unit)
        #expect(billing.city == saved.city)
        #expect(billing.postalCode == saved.postalCode)
    }

    @Test("A copied billing address doesn't follow later edits to the original")
    func billingIsASnapshot() {
        var saved = MockData.addresses[0]
        let billing = BillingAddress(from: saved)
        saved.street = "Somewhere else entirely"
        // The whole reason this is a copy rather than an id.
        #expect(billing.line1 != saved.street)
    }

    @Test("One-line and multi-line forms both read properly")
    func formatting() {
        let billing = BillingAddress(
            line1: "1042 Valencia St", line2: "Apt 3B",
            city: "San Francisco", state: "CA", postalCode: "94110"
        )
        #expect(billing.oneLine == "1042 Valencia St, San Francisco, CA 94110")
        #expect(billing.formatted == "1042 Valencia St\nApt 3B\nSan Francisco, CA 94110")
    }

    // MARK: The card as a whole

    @Test("A card is only built when the name and billing address are there")
    func cardNeedsNameAndBilling() {
        let billing = BillingAddress(from: MockData.addresses[0])
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(CardEntry.paymentMethod(
            number: "4242424242424242", expiry: "12/29", cvc: "123",
            cardholderName: "Han-Elliot Phan", billing: billing, now: now
        ) != nil)

        // No billing address.
        #expect(CardEntry.paymentMethod(
            number: "4242424242424242", expiry: "12/29", cvc: "123",
            cardholderName: "Han-Elliot Phan", billing: nil, now: now
        ) == nil)

        // No name.
        #expect(CardEntry.paymentMethod(
            number: "4242424242424242", expiry: "12/29", cvc: "123",
            cardholderName: "   ", billing: billing, now: now
        ) == nil)
    }

    @Test("The name is stored normalised")
    func cardStoresNormalisedName() {
        let billing = BillingAddress(from: MockData.addresses[0])
        let method = CardEntry.paymentMethod(
            number: "4242424242424242", expiry: "12/29", cvc: "123",
            cardholderName: "  Han-Elliot   Phan  ", billing: billing,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        )
        #expect(method?.cardholderName == "Han-Elliot Phan")
        #expect(method?.billing == billing)
        #expect(method?.isComplete == true)
    }

    @Test("Adding a name and address still stores no number or code")
    func stillStoresNothingSensitive() throws {
        let billing = BillingAddress(from: MockData.addresses[0])
        let method = CardEntry.paymentMethod(
            number: "4242424242424242", expiry: "12/29", cvc: "123",
            cardholderName: "Han-Elliot Phan", billing: billing,
            now: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        )
        let blob = try String(data: JSONEncoder().encode(method), encoding: .utf8)!
        #expect(!blob.contains("4242424242424242"))
        #expect(blob.contains("4242"))                 // the last four
        #expect(blob.contains("Han-Elliot Phan"))
        #expect(blob.contains("94110"))
    }

    // MARK: Fixtures and migration

    @Test("Seeded cards carry a name and a billing address, except the wallet")
    func seededCards() {
        for method in MockData.paymentMethods {
            if method.brand == "Apple Pay" {
                // A device token genuinely has neither.
                #expect(method.cardholderName == nil)
                #expect(method.billing == nil)
                #expect(!method.isComplete)
            } else {
                #expect(method.isComplete, "\(method.label) is missing details")
                #expect(BillingEntry.isValid(
                    name: method.cardholderName ?? "",
                    line1: method.billing?.line1 ?? "",
                    city: method.billing?.city ?? "",
                    state: method.billing?.state ?? "",
                    postalCode: method.billing?.postalCode ?? ""
                ))
            }
        }
    }

    @Test("A card stored before these fields existed still decodes")
    func decodesLegacyCard() throws {
        // Exactly the shape the store held one version ago. This must not throw,
        // or upgrading would wipe everybody's saved cards.
        let legacy = """
        {"id":"00000000-0000-4000-8000-000000000201","brand":"Visa","last4":"4242",
         "expiry":"07/29","symbol":"creditcard.fill","isDefault":true}
        """
        let method = try JSONDecoder().decode(PaymentMethod.self, from: Data(legacy.utf8))
        #expect(method.last4 == "4242")
        #expect(method.cardholderName == nil)
        #expect(method.billing == nil)
        #expect(method.holderLabel == "No name on file")
        #expect(method.billingSummary == "No billing address")
        #expect(!method.isComplete)
    }
}
