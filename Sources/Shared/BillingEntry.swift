import Foundation

/// Validating the name and billing address on a card.
///
/// Separate from `CardEntry` because these are a different kind of claim: the
/// card number can be checked arithmetically, whereas a name and an address can
/// only be checked for shape. So the rules here are deliberately shallow — they
/// catch blank and obviously malformed, and nothing more. Pretending to verify an
/// address that no service is being asked about would be theatre.
enum BillingEntry {

    enum Field: Hashable, Sendable {
        case name, line1, line2, city, state, postalCode
    }

    enum Issue: Hashable, Sendable {
        case nameMissing
        case nameLacksSurname
        case line1Missing
        case cityMissing
        case stateMissing
        case stateMalformed
        case postalMissing
        case postalMalformed(country: String)

        var message: String {
            switch self {
            case .nameMissing:
                "Enter the name printed on the card."
            case .nameLacksSurname:
                "Cards carry a first and last name."
            case .line1Missing:
                "Enter the street the card is billed to."
            case .cityMissing:
                "Enter the city."
            case .stateMissing:
                "Enter the state."
            case .stateMalformed:
                "Use the two-letter state code, like CA."
            case .postalMissing:
                "Enter the ZIP code."
            case .postalMalformed(let country):
                country == "US"
                    ? "US ZIP codes are 5 digits, or 5+4."
                    : "That postal code doesn't look right."
            }
        }

        var field: Field {
            switch self {
            case .nameMissing, .nameLacksSurname: .name
            case .line1Missing: .line1
            case .cityMissing: .city
            case .stateMissing, .stateMalformed: .state
            case .postalMissing, .postalMalformed: .postalCode
            }
        }
    }

    // MARK: Pieces

    /// Cards are embossed with a given and a family name, so a single word is
    /// almost always a half-finished entry rather than somebody's full name.
    /// It's a warning-shaped rule, which is why it's separate from `nameMissing`.
    static func hasTwoParts(_ name: String) -> Bool {
        name.split(whereSeparator: \.isWhitespace).count >= 2
    }

    /// "94110" or "94110-1234".
    static func isValidUSPostal(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return parts[0].count == 5 && parts[0].allSatisfy(\.isNumber)
        case 2:
            return parts[0].count == 5 && parts[0].allSatisfy(\.isNumber)
                && parts[1].count == 4 && parts[1].allSatisfy(\.isNumber)
        default:
            return false
        }
    }

    static func isValidPostal(_ raw: String, country: String) -> Bool {
        country == "US"
            ? isValidUSPostal(raw)
            : !raw.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isValidUSState(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 2 && trimmed.allSatisfy(\.isLetter)
    }

    // MARK: Validation

    static func issues(
        name: String,
        line1: String,
        city: String,
        state: String,
        postalCode: String,
        country: String = "US"
    ) -> [Issue] {
        var found: [Issue] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            found.append(.nameMissing)
        } else if !hasTwoParts(trimmedName) {
            found.append(.nameLacksSurname)
        }

        if line1.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.line1Missing) }
        if city.trimmingCharacters(in: .whitespaces).isEmpty { found.append(.cityMissing) }

        let trimmedState = state.trimmingCharacters(in: .whitespaces)
        if trimmedState.isEmpty {
            found.append(.stateMissing)
        } else if country == "US", !isValidUSState(trimmedState) {
            found.append(.stateMalformed)
        }

        let trimmedPostal = postalCode.trimmingCharacters(in: .whitespaces)
        if trimmedPostal.isEmpty {
            found.append(.postalMissing)
        } else if !isValidPostal(trimmedPostal, country: country) {
            found.append(.postalMalformed(country: country))
        }

        return found
    }

    static func isValid(
        name: String,
        line1: String,
        city: String,
        state: String,
        postalCode: String,
        country: String = "US"
    ) -> Bool {
        issues(name: name, line1: line1, city: city, state: state, postalCode: postalCode, country: country).isEmpty
    }

    /// Trimmed, with the state upper-cased because "ca" is a typing convenience
    /// rather than a different place.
    static func billingAddress(
        line1: String,
        line2: String,
        city: String,
        state: String,
        postalCode: String,
        country: String = "US"
    ) -> BillingAddress {
        let unit = line2.trimmingCharacters(in: .whitespaces)
        return BillingAddress(
            line1: line1.trimmingCharacters(in: .whitespaces),
            line2: unit.isEmpty ? nil : unit,
            city: city.trimmingCharacters(in: .whitespaces),
            state: state.trimmingCharacters(in: .whitespaces).uppercased(),
            postalCode: postalCode.trimmingCharacters(in: .whitespaces),
            country: country
        )
    }

    static func normalisedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
