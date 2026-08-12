import Foundation

/// Validation for the customer's own details.
///
/// In `Shared` rather than in the view because the helper app reads the same
/// profile out of the shared store — a name it can't display, or a phone number
/// it can't ring, is that app's problem too.
enum ProfileEditing {

    /// A name is the only thing genuinely required: a helper standing at the
    /// door needs to know who they're asking for. Phone and email are optional,
    /// but if given they have to be usable.
    enum Issue: Hashable, Sendable {
        case nameMissing
        case phoneTooShort(digits: Int)
        case emailMalformed

        var message: String {
            switch self {
            case .nameMissing:
                "Your helper needs a name to ask for at the door."
            case .phoneTooShort(let digits):
                digits == 0
                    ? "Add a number your helper can reach you on."
                    : "That number looks too short — \(digits) digits."
            case .emailMalformed:
                "That email address doesn't look right."
            }
        }

        /// Which field to highlight, so the form can point at the problem.
        var field: Field {
            switch self {
            case .nameMissing: .name
            case .phoneTooShort: .phone
            case .emailMalformed: .email
            }
        }
    }

    enum Field: Hashable, Sendable {
        case name, phone, email
    }

    /// Shortest run of digits that could be a real phone number, ignoring
    /// punctuation and any country code.
    static let minimumPhoneDigits = 7

    static func digits(in phone: String) -> String {
        phone.filter(\.isNumber)
    }

    /// Deliberately loose. Anything stricter than "one @, a dot after it, and no
    /// spaces" starts rejecting addresses that genuinely work.
    static func isPlausibleEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.count >= 6 else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let domain = parts.last else { return false }
        guard !local.isEmpty, domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        // A single-letter TLD isn't a thing.
        guard let tld = domain.split(separator: ".").last, tld.count >= 2 else { return false }
        return true
    }

    /// Everything wrong with a set of details, in field order so the form can
    /// show the first problem next to the field that caused it.
    static func issues(name: String, phone: String, email: String) -> [Issue] {
        var found: [Issue] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append(.nameMissing)
        }

        let phoneTrimmed = phone.trimmingCharacters(in: .whitespaces)
        if !phoneTrimmed.isEmpty {
            let count = digits(in: phoneTrimmed).count
            if count < minimumPhoneDigits { found.append(.phoneTooShort(digits: count)) }
        }

        let emailTrimmed = email.trimmingCharacters(in: .whitespaces)
        if !emailTrimmed.isEmpty, !isPlausibleEmail(emailTrimmed) {
            found.append(.emailMalformed)
        }

        return found
    }

    static func isValid(name: String, phone: String, email: String) -> Bool {
        issues(name: name, phone: phone, email: email).isEmpty
    }

    /// What actually gets stored: trimmed, with the email lowercased because
    /// nobody means the capitals in an address.
    static func normalised(name: String, phone: String, email: String) -> (name: String, phone: String, email: String) {
        (
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased()
        )
    }
}
