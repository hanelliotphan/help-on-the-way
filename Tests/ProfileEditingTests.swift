import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Personal details")
struct ProfileEditingTests {

    // MARK: Name

    @Test("A name is required")
    func nameRequired() {
        #expect(ProfileEditing.issues(name: "", phone: "", email: "").contains(.nameMissing))
        #expect(ProfileEditing.issues(name: "   ", phone: "", email: "").contains(.nameMissing))
        #expect(!ProfileEditing.issues(name: "Han-Elliot Phan", phone: "", email: "").contains(.nameMissing))
    }

    @Test("A hyphenated name is a perfectly good name")
    func hyphenatedName() {
        #expect(ProfileEditing.isValid(name: "Han-Elliot Phan", phone: "", email: ""))
    }

    @Test("A single-word name is allowed")
    func singleWordName() {
        // Plenty of people have one name; refusing it would be a bug, not a check.
        #expect(ProfileEditing.isValid(name: "Prince", phone: "", email: ""))
    }

    // MARK: Phone

    @Test("Phone is optional")
    func phoneOptional() {
        #expect(ProfileEditing.isValid(name: "Ada", phone: "", email: ""))
    }

    @Test("Punctuation doesn't count against the digit minimum")
    func phonePunctuationIgnored() {
        #expect(ProfileEditing.digits(in: "(415) 555-0134") == "4155550134")
        #expect(ProfileEditing.isValid(name: "Ada", phone: "(415) 555-0134", email: ""))
        #expect(ProfileEditing.isValid(name: "Ada", phone: "+1 415 555 0134", email: ""))
    }

    @Test("A number too short to dial is rejected, and says how short")
    func phoneTooShort() {
        let issues = ProfileEditing.issues(name: "Ada", phone: "555-12", email: "")
        #expect(issues == [.phoneTooShort(digits: 5)])
    }

    @Test("Punctuation alone counts as no digits at all")
    func phoneWithNoDigits() {
        #expect(ProfileEditing.issues(name: "Ada", phone: "---", email: "") == [.phoneTooShort(digits: 0)])
    }

    // MARK: Email

    @Test("Email is optional")
    func emailOptional() {
        #expect(ProfileEditing.isValid(name: "Ada", phone: "", email: ""))
    }

    @Test("Ordinary addresses pass")
    func emailAccepts() {
        for address in [
            "hanelliotphan@gmail.com",
            "a.b+tag@sub.domain.co.uk",
            "x_y@example.io",
        ] {
            #expect(ProfileEditing.isPlausibleEmail(address), "rejected \(address)")
        }
    }

    @Test("Broken addresses fail")
    func emailRejects() {
        for address in [
            "nope",              // no @
            "no@domain",         // no dot in the domain
            "@example.com",      // no local part
            "two@@example.com",  // two @
            "has space@ex.com",  // whitespace
            "a@b.c",             // single-letter TLD
            "a@example.",        // trailing dot
        ] {
            #expect(!ProfileEditing.isPlausibleEmail(address), "accepted \(address)")
        }
    }

    @Test("A bad email is reported against the email field")
    func emailIssueField() {
        let issues = ProfileEditing.issues(name: "Ada", phone: "", email: "nope")
        #expect(issues == [.emailMalformed])
        #expect(issues.first?.field == .email)
    }

    // MARK: Several at once

    @Test("Every problem is reported, in field order")
    func issuesAreOrdered() {
        let issues = ProfileEditing.issues(name: "", phone: "1", email: "nope")
        #expect(issues.map(\.field) == [.name, .phone, .email])
    }

    @Test("Every issue explains itself")
    func issuesHaveMessages() {
        let all: [ProfileEditing.Issue] = [
            .nameMissing, .phoneTooShort(digits: 0), .phoneTooShort(digits: 4), .emailMalformed,
        ]
        for issue in all {
            #expect(!issue.message.isEmpty)
        }
        // The empty case reads differently from the too-short case.
        #expect(ProfileEditing.Issue.phoneTooShort(digits: 0).message
                != ProfileEditing.Issue.phoneTooShort(digits: 4).message)
    }

    // MARK: Normalisation

    @Test("Stored details are trimmed, and the email is lowercased")
    func normalisation() {
        let clean = ProfileEditing.normalised(
            name: "  Han-Elliot Phan \n",
            phone: "  (415) 555-0134  ",
            email: "  HanElliotPhan@Gmail.COM "
        )
        #expect(clean.name == "Han-Elliot Phan")
        #expect(clean.phone == "(415) 555-0134")
        #expect(clean.email == "hanelliotphan@gmail.com")
    }

    @Test("Normalising twice changes nothing the second time")
    func normalisationIsIdempotent() {
        let once = ProfileEditing.normalised(name: " Ada ", phone: " 4155550134 ", email: " A@B.CO ")
        let twice = ProfileEditing.normalised(name: once.name, phone: once.phone, email: once.email)
        #expect(once == twice)
    }

    @Test("Whitespace-only details don't sneak through as valid")
    func whitespaceOnly() {
        #expect(!ProfileEditing.isValid(name: "  ", phone: "  ", email: "  "))
    }

    // MARK: What the seeded account looks like

    @Test("The demo account's own details are valid")
    func seededProfileIsValid() {
        let profile = MockData.profile
        #expect(ProfileEditing.isValid(name: profile.name, phone: profile.phone, email: profile.email))
    }

    @Test("Initials survive editing to a hyphenated name")
    func initialsFromEditedName() {
        var profile = MockData.profile
        profile.name = ProfileEditing.normalised(name: " han-elliot  phan ", phone: "", email: "").name
        #expect(profile.initials == "HP")
    }
}
