import Foundation

/// Who is allowed to be offered what.
///
/// The catalogue now includes work with children and vulnerable adults, and
/// that can't be a label on a tile. A helper listing `babysitting` among their
/// skills is a claim; the credentials are the check on it. Nothing here is
/// advisory — `Matching` and the helper app's own queue both refuse to surface a
/// job to somebody who doesn't hold what the category requires.
///
/// Deliberately a hard filter rather than a ranking penalty: "less likely to be
/// offered" is not a thing to say about vetting for childcare.
enum Vetting {

    /// Credentials a helper must hold before this work is offered to them.
    static func required(for category: HelpCategory) -> Set<HelperBadge> {
        switch category {
        case .babysitting: [.backgroundChecked, .enhancedCheck, .paediatricFirstAid]
        case .tutoring: [.backgroundChecked, .enhancedCheck, .teachingCredential]
        case .seniorCare: [.backgroundChecked, .enhancedCheck, .careCertified]
        // Everything else needs the ordinary check, which every helper carries.
        default: [.backgroundChecked]
        }
    }

    static func isEligible(_ helper: Helper, for category: HelpCategory) -> Bool {
        missing(for: helper, category: category).isEmpty
    }

    /// What a helper would still need. Drives the helper app's explanation of
    /// why work it can see listed isn't being offered to it.
    static func missing(for helper: Helper, category: HelpCategory) -> [HelperBadge] {
        let held = Set(helper.badges)
        return required(for: category)
            .subtracting(held)
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// Skilled *and* cleared. The only question worth asking before offering a
    /// job to somebody.
    static func canTake(_ helper: Helper, _ category: HelpCategory) -> Bool {
        helper.handles(category) && isEligible(helper, for: category)
    }

    /// Enhanced work needs more than an hour's notice: the customer is expected
    /// to read a profile before somebody comes to mind their child, and that
    /// isn't a thing to do in a hurry.
    static func minimumLeadMinutes(for category: HelpCategory) -> Int {
        category.trustTier == .enhanced ? 240 : Scheduling.minimumLeadMinutes
    }

    /// One line for the customer, naming the checks rather than gesturing at them.
    static func assurance(for category: HelpCategory) -> String? {
        guard category.trustTier == .enhanced else { return nil }
        let names = required(for: category)
            .subtracting([.backgroundChecked])
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
        guard !names.isEmpty else { return nil }
        return "Everyone offered this work holds: \(names.joined(separator: ", "))."
    }
}
