import Foundation

/// Validating a card at the point of entry.
///
/// The important thing about this file is what it *doesn't* do: nothing here
/// keeps the number. A card is checked, its brand and last four read off it, and
/// the rest is dropped on the floor. `PaymentMethod` has nowhere to put a full
/// number precisely so that no future change can accidentally start storing one,
/// and the CVC is used to check a length and then forgotten.
///
/// A real app would hand the number straight to a payment provider and store the
/// token it gets back. This one has no network, so it stores the only two things
/// it can legitimately show you: a brand and four digits.
enum CardEntry {

    enum Brand: String, CaseIterable, Sendable {
        case visa, mastercard, amex, discover

        var displayName: String {
            switch self {
            case .visa: "Visa"
            case .mastercard: "Mastercard"
            case .amex: "Amex"
            case .discover: "Discover"
            }
        }

        var symbol: String { "creditcard.fill" }

        /// Valid total digit counts for the brand.
        var numberLengths: Set<Int> {
            switch self {
            case .amex: [15]
            case .visa: [13, 16, 19]
            case .mastercard: [16]
            case .discover: [16, 19]
            }
        }

        var cvcLength: Int { self == .amex ? 4 : 3 }

        /// How the digits group when displayed: 4-6-5 for Amex, 4s otherwise.
        var groups: [Int] {
            self == .amex ? [4, 6, 5] : [4, 4, 4, 4, 4]
        }

        /// Identified from the issuer prefix.
        static func detect(from digits: String) -> Brand? {
            guard let first = digits.first else { return nil }
            let two = Int(digits.prefix(2)) ?? 0
            let three = Int(digits.prefix(3)) ?? 0
            let four = Int(digits.prefix(4)) ?? 0

            if first == "4" { return .visa }
            if two == 34 || two == 37 { return .amex }
            if (51...55).contains(two) || (2221...2720).contains(four) { return .mastercard }
            if four == 6011 || two == 65 || (644...649).contains(three) { return .discover }
            return nil
        }
    }

    enum Issue: Hashable, Sendable {
        case numberEmpty
        case brandUnrecognised
        case numberWrongLength(expected: [Int], got: Int)
        case numberFailsChecksum
        case expiryMalformed
        case expiryPast
        case cvcWrongLength(expected: Int)

        var message: String {
            switch self {
            case .numberEmpty:
                "Enter the long number on the front of the card."
            case .brandUnrecognised:
                "We take Visa, Mastercard, Amex and Discover."
            case .numberWrongLength(let expected, let got):
                "That's \(got) digits — this card should have \(expected.map(String.init).joined(separator: " or "))."
            case .numberFailsChecksum:
                "Those digits don't add up. Check for a typo."
            case .expiryMalformed:
                "Expiry goes in as MM/YY."
            case .expiryPast:
                "That card has expired."
            case .cvcWrongLength(let expected):
                "The security code is \(expected) digits."
            }
        }

        var field: Field {
            switch self {
            case .numberEmpty, .brandUnrecognised, .numberWrongLength, .numberFailsChecksum: .number
            case .expiryMalformed, .expiryPast: .expiry
            case .cvcWrongLength: .cvc
            }
        }
    }

    enum Field: Hashable, Sendable { case number, expiry, cvc }

    // MARK: Digits

    static func digits(in raw: String) -> String {
        raw.filter(\.isNumber)
    }

    static func last4(of raw: String) -> String {
        String(digits(in: raw).suffix(4))
    }

    /// Groups digits for display as they're typed.
    static func formatted(_ raw: String) -> String {
        let all = digits(in: raw)
        let brand = Brand.detect(from: all)
        let groups = brand?.groups ?? [4, 4, 4, 4, 4]

        var out: [String] = []
        var index = all.startIndex
        for size in groups {
            guard index < all.endIndex else { break }
            let end = all.index(index, offsetBy: size, limitedBy: all.endIndex) ?? all.endIndex
            out.append(String(all[index..<end]))
            index = end
        }
        return out.joined(separator: " ")
    }

    /// The Luhn check digit test. Catches single-digit typos and most
    /// transpositions, which is the whole reason cards carry one.
    static func passesLuhn(_ raw: String) -> Bool {
        let all = digits(in: raw)
        guard all.count >= 2 else { return false }

        var sum = 0
        for (offset, character) in all.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { return false }
            if offset.isMultiple(of: 2) {
                sum += value
            } else {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    // MARK: Expiry

    /// Accepts "MM/YY", "MMYY" or "MM / YY". Two-digit years are this century.
    static func expiry(from raw: String) -> (month: Int, year: Int)? {
        let all = digits(in: raw)
        guard all.count == 4 || all.count == 6 else { return nil }
        guard let month = Int(all.prefix(2)), (1...12).contains(month) else { return nil }

        let yearDigits = String(all.dropFirst(2))
        guard let year = Int(yearDigits) else { return nil }
        return (month: month, year: yearDigits.count == 2 ? 2000 + year : year)
    }

    /// A card is good through the last day of its printed month.
    static func hasExpired(month: Int, year: Int, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let current = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = current.year, let currentMonth = current.month else { return false }
        if year != currentYear { return year < currentYear }
        return month < currentMonth
    }

    /// Normalised back to "MM/YY" for storage and display.
    static func expiryLabel(month: Int, year: Int) -> String {
        String(format: "%02d/%02d", month, year % 100)
    }

    // MARK: Validation

    static func issues(number: String, expiry rawExpiry: String, cvc: String, now: Date = Date()) -> [Issue] {
        var found: [Issue] = []

        let all = digits(in: number)
        let brand = Brand.detect(from: all)

        if all.isEmpty {
            found.append(.numberEmpty)
        } else if brand == nil {
            found.append(.brandUnrecognised)
        } else if let brand, !brand.numberLengths.contains(all.count) {
            found.append(.numberWrongLength(expected: brand.numberLengths.sorted(), got: all.count))
        } else if !passesLuhn(all) {
            found.append(.numberFailsChecksum)
        }

        if let parsed = expiry(from: rawExpiry) {
            if hasExpired(month: parsed.month, year: parsed.year, now: now) {
                found.append(.expiryPast)
            }
        } else {
            found.append(.expiryMalformed)
        }

        let expectedCVC = brand?.cvcLength ?? 3
        if digits(in: cvc).count != expectedCVC {
            found.append(.cvcWrongLength(expected: expectedCVC))
        }

        return found
    }

    static func isValid(number: String, expiry: String, cvc: String, now: Date = Date()) -> Bool {
        issues(number: number, expiry: expiry, cvc: cvc, now: now).isEmpty
    }

    /// Turns validated entry into the only thing we're willing to keep.
    /// Returns nil rather than storing anything questionable.
    ///
    /// The cardholder name and billing address come in already validated by
    /// `BillingEntry` — this checks they're present, because a card without them
    /// isn't something a payment processor would accept.
    static func paymentMethod(
        number: String,
        expiry rawExpiry: String,
        cvc: String,
        cardholderName: String,
        billing: BillingAddress?,
        isDefault: Bool = false,
        now: Date = Date()
    ) -> PaymentMethod? {
        guard isValid(number: number, expiry: rawExpiry, cvc: cvc, now: now),
              let brand = Brand.detect(from: digits(in: number)),
              let parsed = expiry(from: rawExpiry),
              let billing
        else { return nil }

        let name = BillingEntry.normalisedName(cardholderName)
        guard !name.isEmpty else { return nil }

        return PaymentMethod(
            brand: brand.displayName,
            last4: last4(of: number),
            expiry: expiryLabel(month: parsed.month, year: parsed.year),
            symbol: brand.symbol,
            isDefault: isDefault,
            cardholderName: name,
            billing: billing
        )
    }
}
