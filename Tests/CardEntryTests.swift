import Foundation
import Testing

@testable import HelpOnTheWay

/// Card numbers used here are the publicly documented test numbers every
/// payment provider hands out. None of them is a real account.
@Suite("Card entry")
struct CardEntryTests {

    private let visa = "4242424242424242"
    private let mastercard = "5555555555554444"
    private let amex = "378282246310005"
    private let discover = "6011111111111117"

    /// A cardholder and billing address are required now, so the storage tests
    /// need a valid pair to pass through.
    private let holder = "Han-Elliot Phan"
    private var testBilling: BillingAddress { BillingAddress(from: MockData.addresses[0]) }

    /// Fixed "now" so an expiry test doesn't start failing next January.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    // MARK: Brand detection

    @Test("Brands are read off the issuer prefix")
    func brandDetection() {
        #expect(CardEntry.Brand.detect(from: visa) == .visa)
        #expect(CardEntry.Brand.detect(from: mastercard) == .mastercard)
        #expect(CardEntry.Brand.detect(from: amex) == .amex)
        #expect(CardEntry.Brand.detect(from: discover) == .discover)
        #expect(CardEntry.Brand.detect(from: "2221000000000009") == .mastercard)  // 2-series
        #expect(CardEntry.Brand.detect(from: "6521111111111117") == .discover)
    }

    @Test("An unknown issuer is not guessed at")
    func unknownBrand() {
        #expect(CardEntry.Brand.detect(from: "9999999999999999") == nil)
        #expect(CardEntry.Brand.detect(from: "") == nil)
    }

    @Test("Amex carries a shorter number and a longer code")
    func amexShape() {
        #expect(CardEntry.Brand.amex.numberLengths == [15])
        #expect(CardEntry.Brand.amex.cvcLength == 4)
        #expect(CardEntry.Brand.visa.cvcLength == 3)
    }

    // MARK: Luhn

    @Test("Real test numbers pass the checksum")
    func luhnAccepts() {
        for number in [visa, mastercard, amex, discover] {
            #expect(CardEntry.passesLuhn(number), "rejected \(number)")
        }
    }

    @Test("A single-digit typo fails the checksum")
    func luhnCatchesTypo() {
        #expect(!CardEntry.passesLuhn("4242424242424243"))
    }

    @Test("A transposition fails the checksum")
    func luhnCatchesTransposition() {
        // 4242...4242 with two adjacent digits swapped.
        #expect(!CardEntry.passesLuhn("4224424242424242"))
    }

    @Test("Punctuation and spaces don't affect the checksum")
    func luhnIgnoresFormatting() {
        #expect(CardEntry.passesLuhn("4242 4242 4242 4242"))
        #expect(CardEntry.passesLuhn("4242-4242-4242-4242"))
    }

    @Test("Nonsense input doesn't pass")
    func luhnRejectsJunk() {
        #expect(!CardEntry.passesLuhn(""))
        #expect(!CardEntry.passesLuhn("4"))
    }

    // MARK: Formatting

    @Test("Digits group in fours, and Amex in 4-6-5")
    func formatting() {
        #expect(CardEntry.formatted("4242424242424242") == "4242 4242 4242 4242")
        #expect(CardEntry.formatted("378282246310005") == "3782 822463 10005")
        #expect(CardEntry.formatted("4242") == "4242")
        #expect(CardEntry.formatted("42424") == "4242 4")
    }

    @Test("Formatting is stable when applied to its own output")
    func formattingIsIdempotent() {
        let once = CardEntry.formatted(visa)
        #expect(CardEntry.formatted(once) == once)
    }

    @Test("The slash appears as the expiry is typed, and only once")
    func expirySlashing() {
        #expect(AddPaymentMethodView.slashed("1") == "1")
        #expect(AddPaymentMethodView.slashed("12") == "12")
        #expect(AddPaymentMethodView.slashed("123") == "12/3")
        #expect(AddPaymentMethodView.slashed("12/29") == "12/29")
        #expect(AddPaymentMethodView.slashed("12//29") == "12/29")
        // And it can't grow past MM/YY.
        #expect(AddPaymentMethodView.slashed("1229999") == "12/29")
    }

    // MARK: Expiry

    @Test("MM/YY parses, with or without the slash")
    func expiryParsing() {
        #expect(CardEntry.expiry(from: "12/29")?.month == 12)
        #expect(CardEntry.expiry(from: "12/29")?.year == 2029)
        #expect(CardEntry.expiry(from: "1229")?.year == 2029)
        #expect(CardEntry.expiry(from: "07/2029")?.year == 2029)
    }

    @Test("An impossible month is rejected")
    func expiryRejectsBadMonth() {
        #expect(CardEntry.expiry(from: "13/29") == nil)
        #expect(CardEntry.expiry(from: "00/29") == nil)
        #expect(CardEntry.expiry(from: "abc") == nil)
        #expect(CardEntry.expiry(from: "1/9") == nil)
    }

    @Test("A card is good through the last day of its printed month")
    func expiryBoundary() {
        // "Now" is June 2026.
        #expect(!CardEntry.hasExpired(month: 6, year: 2026, now: now))
        #expect(CardEntry.hasExpired(month: 5, year: 2026, now: now))
        #expect(!CardEntry.hasExpired(month: 1, year: 2027, now: now))
        #expect(CardEntry.hasExpired(month: 12, year: 2025, now: now))
    }

    @Test("Expiry is stored back as MM/YY")
    func expiryLabel() {
        #expect(CardEntry.expiryLabel(month: 7, year: 2029) == "07/29")
        #expect(CardEntry.expiryLabel(month: 12, year: 2030) == "12/30")
    }

    // MARK: Validation

    @Test("A good card validates clean")
    func validCard() {
        #expect(CardEntry.isValid(number: visa, expiry: "12/29", cvc: "123", now: now))
        #expect(CardEntry.isValid(number: amex, expiry: "12/29", cvc: "1234", now: now))
    }

    @Test("An empty number says so rather than complaining about the brand")
    func emptyNumber() {
        let issues = CardEntry.issues(number: "", expiry: "12/29", cvc: "123", now: now)
        #expect(issues.contains(.numberEmpty))
        #expect(!issues.contains(.brandUnrecognised))
    }

    @Test("An unsupported issuer is named as such")
    func unsupportedBrand() {
        let issues = CardEntry.issues(number: "9999999999999999", expiry: "12/29", cvc: "123", now: now)
        #expect(issues.contains(.brandUnrecognised))
    }

    @Test("A number of the wrong length reports both lengths")
    func wrongLength() {
        let issues = CardEntry.issues(number: "424242424242", expiry: "12/29", cvc: "123", now: now)
        #expect(issues.contains(.numberWrongLength(expected: [13, 16, 19], got: 12)))
    }

    @Test("Amex wants four digits of security code, not three")
    func amexCVCLength() {
        #expect(CardEntry.issues(number: amex, expiry: "12/29", cvc: "123", now: now)
            .contains(.cvcWrongLength(expected: 4)))
        #expect(CardEntry.issues(number: amex, expiry: "12/29", cvc: "1234", now: now).isEmpty)
    }

    @Test("An expired card is refused")
    func expiredCard() {
        #expect(CardEntry.issues(number: visa, expiry: "01/26", cvc: "123", now: now)
            .contains(.expiryPast))
    }

    @Test("Every issue explains itself and points at a field")
    func issuesAreUsable() {
        let all: [CardEntry.Issue] = [
            .numberEmpty, .brandUnrecognised, .numberWrongLength(expected: [16], got: 12),
            .numberFailsChecksum, .expiryMalformed, .expiryPast, .cvcWrongLength(expected: 3),
        ]
        for issue in all {
            #expect(!issue.message.isEmpty)
        }
        #expect(CardEntry.Issue.numberFailsChecksum.field == .number)
        #expect(CardEntry.Issue.expiryPast.field == .expiry)
        #expect(CardEntry.Issue.cvcWrongLength(expected: 3).field == .cvc)
    }

    // MARK: What actually gets stored

    @Test("Only the brand, last four and expiry survive")
    func storesNothingSensitive() {
        let method = CardEntry.paymentMethod(number: visa, expiry: "12/29", cvc: "123", cardholderName: holder, billing: testBilling, now: now)
        #expect(method?.brand == "Visa")
        #expect(method?.last4 == "4242")
        #expect(method?.expiry == "12/29")

        // The full number must not be recoverable from what we keep. Encoding the
        // stored value is the strongest check available: if any field held it,
        // it would show up here.
        let encoder = JSONEncoder()
        let blob = try! String(data: encoder.encode(method), encoding: .utf8)!
        #expect(!blob.contains(visa))
        #expect(!blob.contains("123"))          // the security code
        #expect(blob.contains("4242"))          // the last four, which is fine
    }

    @Test("An invalid card produces nothing at all")
    func invalidCardStoresNothing() {
        #expect(CardEntry.paymentMethod(number: "4242424242424243", expiry: "12/29", cvc: "123", cardholderName: holder, billing: testBilling, now: now) == nil)
        #expect(CardEntry.paymentMethod(number: visa, expiry: "01/26", cvc: "123", cardholderName: holder, billing: testBilling, now: now) == nil)
        #expect(CardEntry.paymentMethod(number: visa, expiry: "12/29", cvc: "1", cardholderName: holder, billing: testBilling, now: now) == nil)
    }

    @Test("A formatted number stores the same way as a bare one")
    func formattingDoesNotChangeStorage() {
        let bare = CardEntry.paymentMethod(number: visa, expiry: "12/29", cvc: "123", cardholderName: holder, billing: testBilling, now: now)
        let spaced = CardEntry.paymentMethod(number: "4242 4242 4242 4242", expiry: "12/29", cvc: "123", cardholderName: holder, billing: testBilling, now: now)
        #expect(bare?.last4 == spaced?.last4)
        #expect(bare?.brand == spaced?.brand)
    }

    @Test("The seeded cards look like what the entry form would produce")
    func seededCardsAreConsistent() {
        for method in MockData.paymentMethods where method.expiry != "—" {
            #expect(method.last4.count == 4)
            #expect(CardEntry.expiry(from: method.expiry) != nil, "bad expiry on \(method.label)")
        }
    }
}
