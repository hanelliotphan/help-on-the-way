import CoreLocation
import Foundation

// MARK: - Geography

/// A latitude/longitude pair we can persist. `CLLocationCoordinate2D` isn't
/// `Codable`, and every job in the store has to survive a relaunch mid-trip.
struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Straight-line miles. Street distance runs longer, which is why
    /// ``Dispatch`` pads it before turning the number into an ETA.
    func miles(to other: GeoPoint) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return here.distance(from: there) / 1609.344
    }

    func interpolated(to other: GeoPoint, fraction: Double) -> GeoPoint {
        let clamped = min(max(fraction, 0), 1)
        return GeoPoint(
            latitude: latitude + (other.latitude - latitude) * clamped,
            longitude: longitude + (other.longitude - longitude) * clamped
        )
    }

    /// Metres offset, used to scatter demo helpers around a neighbourhood.
    func offset(metersNorth: Double, metersEast: Double) -> GeoPoint {
        let latitudeDegrees = metersNorth / 111_320
        let longitudeDegrees = metersEast / (111_320 * cos(latitude * .pi / 180))
        return GeoPoint(latitude: latitude + latitudeDegrees, longitude: longitude + longitudeDegrees)
    }
}

// MARK: - Money

extension Decimal {
    /// Money literals through `Double` pick up rounding error before they ever
    /// reach the ledger, so amounts are always built from whole units.
    static func usd(_ dollars: Int, _ cents: Int = 0) -> Decimal {
        Decimal(dollars) + Decimal(cents) / 100
    }

    func roundedToCents() -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    var currency: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// "$46" for a round rate, "$46.50" when the cents matter.
    var shortCurrency: String {
        let rounded = roundedToCents()
        let whole = rounded.roundedToWhole()
        guard rounded == whole else { return rounded.currency }
        return rounded.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func roundedToWhole() -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, 0, .plain)
        return result
    }

    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}

// MARK: - Catalog

/// The kinds of help a customer can ask for. Rates and minimums are per
/// category because a two-hour deep clean and a ten-minute TV mount can't
/// share one price sheet.
/// How much vetting a kind of work demands.
///
/// The difference between somebody assembling a wardrobe and somebody minding a
/// child is not a difference of degree, and the app shouldn't treat it as one.
enum TrustTier: String, Codable, Hashable, Sendable {
    case standard
    case enhanced
}

enum HelpCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case cleaning
    case handyman
    case assembly
    case moving
    case delivery
    case yardWork
    case techHelp
    case petCare
    case eventHelp
    case babysitting
    case tutoring
    case seniorCare
    case mealPrep
    /// Anything the catalogue doesn't cover. Has no standard rate, so the
    /// customer names one and it gets negotiated from there.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleaning: "Cleaning"
        case .handyman: "Handyman"
        case .assembly: "Furniture Assembly"
        case .moving: "Moving Help"
        case .delivery: "Pickup & Delivery"
        case .yardWork: "Yard Work"
        case .techHelp: "Tech Help"
        case .petCare: "Pet Care"
        case .eventHelp: "Event Help"
        case .babysitting: "Babysitting"
        case .tutoring: "Tutoring"
        case .seniorCare: "Senior Care"
        case .mealPrep: "Meal Prep"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .assembly: "Assembly"
        case .delivery: "Delivery"
        case .eventHelp: "Events"
        case .babysitting: "Sitting"
        case .seniorCare: "Seniors"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .cleaning: "sparkles"
        case .handyman: "wrench.and.screwdriver.fill"
        case .assembly: "hammer.fill"
        case .moving: "shippingbox.fill"
        case .delivery: "car.fill"
        case .yardWork: "leaf.fill"
        case .techHelp: "laptopcomputer"
        case .petCare: "pawprint.fill"
        case .eventHelp: "party.popper.fill"
        case .babysitting: "figure.and.child.holdinghands"
        case .tutoring: "book.fill"
        case .seniorCare: "figure.2.arms.open"
        case .mealPrep: "fork.knife"
        case .custom: "square.dashed"
        }
    }

    var tagline: String {
        switch self {
        case .cleaning: "Kitchens, bathrooms, move-out deep cleans"
        case .handyman: "Mounting, patching, leaks, small repairs"
        case .assembly: "Flat-pack builds, teardowns, mounting"
        case .moving: "Lifting, loading, hauling, one-item moves"
        case .delivery: "Store runs, returns, package drop-offs"
        case .yardWork: "Mowing, weeding, leaves, brush hauling"
        case .techHelp: "Wi-Fi, TVs, printers, new-device setup"
        case .petCare: "Walks, drop-in visits, vet runs"
        case .eventHelp: "Setup, serving, cleanup crews"
        case .babysitting: "Evenings, school runs, date nights"
        case .tutoring: "Maths, reading, languages, exam prep"
        case .seniorCare: "Company, errands, appointments"
        case .mealPrep: "A week of cooking, done in one go"
        case .custom: "Describe it and name your rate"
        }
    }

    /// What this work goes for. Nil for Custom: the app has no rate to quote for
    /// a job it doesn't know, and inventing one would be a number pulled out of
    /// the air presented as a going rate.
    var standardHourlyRate: Decimal? {
        switch self {
        case .cleaning: .usd(46)
        case .handyman: .usd(58)
        case .assembly: .usd(52)
        case .moving: .usd(62)
        case .delivery: .usd(44)
        case .yardWork: .usd(48)
        case .techHelp: .usd(55)
        case .petCare: .usd(38)
        case .eventHelp: .usd(42)
        case .babysitting: .usd(32)
        case .tutoring: .usd(45)
        case .seniorCare: .usd(34)
        case .mealPrep: .usd(40)
        case .custom: nil
        }
    }

    /// What a category tile shows. Custom advertises no price, because it has none.
    var rateLabel: String {
        standardHourlyRate.map { "\($0.shortCurrency)/hr" } ?? "You name it"
    }

    /// True when the customer has to supply the rate themselves.
    var needsNamedRate: Bool { standardHourlyRate == nil }

    /// Nobody sends a helper across town for fifteen minutes of work, so each
    /// category books in a block. The quote never comes in under this.
    var minimumMinutes: Int {
        switch self {
        case .cleaning, .moving: 120
        case .yardWork: 90
        case .eventHelp: 180
        // Nobody books a sitter or a carer for an hour; the block is the shift.
        case .babysitting, .seniorCare, .mealPrep: 180
        default: 60
        }
    }

    var suggestedMinutes: [Int] {
        switch self {
        case .cleaning: [120, 180, 240, 300]
        case .moving: [120, 180, 240, 360]
        case .yardWork: [90, 120, 180, 240]
        case .eventHelp: [180, 240, 300, 360]
        case .babysitting, .seniorCare: [180, 240, 300, 480]
        case .mealPrep: [180, 240, 300]
        case .tutoring: [60, 90, 120, 180]
        default: [60, 90, 120, 180]
        }
    }

    /// How much vetting this work needs before somebody is let through the door.
    var trustTier: TrustTier {
        switch self {
        case .babysitting, .tutoring, .seniorCare: .enhanced
        default: .standard
        }
    }

    /// Crews for a Saturday party get staffed days ahead, not dispatched in
    /// eleven minutes. Care work is scheduled-only for a different and better
    /// reason: auto-assigning a stranger to mind a child in eleven minutes is
    /// not a thing this app should be able to do. Those bookings go through the
    /// calendar, where the customer sees who they're getting first.
    var supportsInstant: Bool {
        self != .eventHelp && trustTier == .standard
    }

    /// Shown wherever the category is chosen, so the extra vetting is visible
    /// rather than implied.
    var vettingNote: String? {
        guard trustTier == .enhanced else { return nil }
        return switch self {
        case .babysitting:
            "Sitters carry an enhanced check and current paediatric first aid. Booked ahead so you can read their profile first."
        case .tutoring:
            "Tutors carry an enhanced check and a verified teaching qualification."
        case .seniorCare:
            "Carers carry an enhanced check and a care certificate. Booked ahead so you can choose who comes."
        default: nil
        }
    }

    /// Shown on the details step so people know what they're buying.
    var checklist: [String] {
        switch self {
        case .cleaning:
            ["Supplies and vacuum brought along", "Kitchen, bath, floors, surfaces", "Trash and recycling taken out"]
        case .handyman:
            ["Standard hand and power tools", "Anchors, screws and patch material", "Cleanup and debris removal"]
        case .assembly:
            ["Build from the box, hardware sorted", "Wall anchoring where the maker calls for it", "Boxes flattened and hauled out"]
        case .moving:
            ["Two-person lifts on request", "Blankets, straps and a dolly", "Loading, unloading, stair carries"]
        case .delivery:
            ["Own vehicle, insured", "Receipts photographed at pickup", "Contactless hand-off available"]
        case .yardWork:
            ["Mower, trimmer and rake brought along", "Bagging and green-waste hauling", "Beds edged and swept down"]
        case .techHelp:
            ["Network, streaming and printer setup", "Data transfer between devices", "A written walkthrough left behind"]
        case .petCare:
            ["GPS-tracked walks with photos", "Food, water and litter", "Vet and groomer transport"]
        case .eventHelp:
            ["Tables, chairs and linens set", "Serving and bussing through the night", "Full teardown and haul-out"]
        case .babysitting:
            ["Enhanced check and paediatric first aid", "Meals, bath and bedtime as you set them", "A note on how the evening went"]
        case .tutoring:
            ["Enhanced check and a verified qualification", "Session plan matched to their syllabus", "A short write-up of what was covered"]
        case .seniorCare:
            ["Enhanced check and a care certificate", "Company, light housekeeping, meal help", "Errands and appointment transport"]
        case .mealPrep:
            ["Shopping list agreed in advance", "A week of meals cooked and portioned", "Kitchen left as it was found"]
        case .custom:
            ["Exactly what you write in the notes", "Tools and supplies as agreed", "Nothing assumed — spell it out"]
        }
    }

    /// A sensible default job title so the request never lands unnamed.
    var defaultJobTitle: String {
        switch self {
        case .cleaning: "Apartment clean"
        case .handyman: "Small repairs around the house"
        case .assembly: "Assemble new furniture"
        case .moving: "Help moving a few heavy things"
        case .delivery: "Pick up and drop off"
        case .yardWork: "Tidy up the yard"
        case .techHelp: "Set up a device"
        case .petCare: "Dog walk"
        case .eventHelp: "Event setup and teardown"
        case .babysitting: "Evening babysitting"
        case .tutoring: "Tutoring session"
        case .seniorCare: "Companion visit"
        case .mealPrep: "A week of meals"
        case .custom: "Something else"
        }
    }
}

// MARK: - Helpers (the people doing the work)

enum HelperBadge: String, Codable, CaseIterable, Identifiable, Sendable {
    case backgroundChecked
    case topRated
    case quickResponder
    case licensed
    case insured
    case ownsTruck
    case suppliesIncluded
    /// The care credentials. These aren't decoration — `Vetting` refuses to
    /// offer a helper work with children or vulnerable adults without them.
    case enhancedCheck
    case paediatricFirstAid
    case teachingCredential
    case careCertified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgroundChecked: "Background checked"
        case .topRated: "Top rated"
        case .quickResponder: "Quick responder"
        case .licensed: "Licensed trade"
        case .insured: "Insured"
        case .ownsTruck: "Has a truck"
        case .suppliesIncluded: "Brings supplies"
        case .enhancedCheck: "Enhanced check"
        case .paediatricFirstAid: "Paediatric first aid"
        case .teachingCredential: "Qualified teacher"
        case .careCertified: "Care certified"
        }
    }

    var symbol: String {
        switch self {
        case .backgroundChecked: "checkmark.shield.fill"
        case .topRated: "star.circle.fill"
        case .quickResponder: "bolt.circle.fill"
        case .licensed: "seal.fill"
        case .insured: "umbrella.fill"
        case .ownsTruck: "truck.box.fill"
        case .suppliesIncluded: "bag.fill"
        case .enhancedCheck: "checkmark.shield.fill"
        case .paediatricFirstAid: "cross.case.fill"
        case .teachingCredential: "graduationcap.fill"
        case .careCertified: "heart.text.square.fill"
        }
    }

    /// What it actually means, for the profile screen. A badge nobody can
    /// explain is a sticker.
    var detail: String {
        switch self {
        case .backgroundChecked: "Identity and criminal record checked."
        case .topRated: "Consistently rated near five stars."
        case .quickResponder: "Usually answers within minutes."
        case .licensed: "Holds a trade licence for this work."
        case .insured: "Covered while working in your home."
        case .ownsTruck: "Can move things that don't fit in a car."
        case .suppliesIncluded: "Brings their own materials."
        case .enhancedCheck: "Extended vetting for work with children and vulnerable adults."
        case .paediatricFirstAid: "Current paediatric first aid and CPR certificate."
        case .teachingCredential: "Verified teaching qualification."
        case .careCertified: "Trained in personal and companion care."
        }
    }
}

struct Review: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var author: String
    var stars: Int
    var body: String
    var category: HelpCategory
    /// How long ago, for the seeded fixtures that have no real date.
    var daysAgo: Int
    /// Set on reviews a customer actually wrote. Both of the fields below are
    /// optional so reviews stored before they existed still decode — a schema
    /// bump here would wipe every account's history to add a nicety.
    var postedAt: Date?
    var compliments: [String]?

    var complimentList: [String] { compliments ?? [] }

    /// Real date when we have one, otherwise the fixture's relative age.
    func ageLabel(now: Date = Date()) -> String {
        postedAt.map { Format.ago($0, now: now) } ?? Format.agoInDays(daysAgo)
    }
}

struct Helper: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var firstName: String
    var lastInitial: String
    var headline: String
    var bio: String
    var rating: Double
    var jobsCompleted: Int
    var hourlyRate: Decimal
    var skills: [HelpCategory]
    var badges: [HelperBadge]
    var reviews: [Review]
    var respondsWithinMinutes: Int
    var yearsExperience: Int
    var vehicle: String?
    /// Where they idle between jobs — the origin of every ETA we quote.
    var basePoint: GeoPoint
    /// Keeps a person's avatar the same colour everywhere it appears.
    var accentHue: Double

    var displayName: String { "\(firstName) \(lastInitial)." }

    var initials: String {
        "\(firstName.prefix(1))\(lastInitial.prefix(1))".uppercased()
    }

    /// Share of customers who book this person again. Derived rather than
    /// stored — one fewer number to keep consistent in the fixtures, and it
    /// tracks the rating the way you'd expect it to.
    var repeatRate: Int {
        min(94, max(55, Int(((rating - 4.7) * 40 + 76).rounded())))
    }

    /// The copy that gets stored on a `Job`.
    ///
    /// A job keeps a snapshot of who did it so a receipt still shows the right
    /// name and rate years later, even if they since raised it. What it has no
    /// business keeping is their review list: reviews belong to the person, not
    /// to one job, and embedding them means every review ever written is
    /// duplicated into every job that person has done. Storage then grows as
    /// jobs × reviews, and 27% of the store was already these copies.
    ///
    /// Anything that wants the live reviews resolves the helper from the roster.
    var forJobRecord: Helper {
        var trimmed = self
        trimmed.reviews = []
        return trimmed
    }

    /// Custom isn't a skill — it's "something else", and the job description is
    /// the only thing to judge it on. Filtering the roster by it would leave
    /// nobody, so every helper is eligible and decides for themselves.
    func handles(_ category: HelpCategory) -> Bool {
        category == .custom || skills.contains(category)
    }
}

// MARK: - Customer account

struct SavedAddress: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String
    var symbol: String
    var street: String
    var unit: String?
    var city: String
    var state: String
    var postalCode: String
    var point: GeoPoint
    var accessNotes: String = ""

    var oneLine: String {
        let head = [street, unit].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
        return "\(head.isEmpty ? street : head), \(city)"
    }

    var fullAddress: String {
        var lines = street
        if let unit, !unit.isEmpty { lines += ", \(unit)" }
        return "\(lines)\n\(city), \(state) \(postalCode)"
    }
}

/// Where the card is registered.
///
/// Held as a copy rather than a pointer at a `SavedAddress` on purpose: a
/// billing address is what the card was registered against at the time, and
/// editing your home address later shouldn't silently rewrite it.
struct BillingAddress: Codable, Hashable, Sendable {
    var line1: String
    var line2: String?
    var city: String
    var state: String
    var postalCode: String
    var country: String = "US"

    var oneLine: String {
        [line1, city, "\(state) \(postalCode)".trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var formatted: String {
        var lines = [line1]
        if let line2, !line2.isEmpty { lines.append(line2) }
        lines.append("\(city), \(state) \(postalCode)".trimmingCharacters(in: .whitespaces))
        return lines.joined(separator: "\n")
    }

    /// Reuses a service address the customer already has on file.
    init(from saved: SavedAddress) {
        line1 = saved.street
        line2 = saved.unit
        city = saved.city
        state = saved.state
        postalCode = saved.postalCode
        country = "US"
    }

    init(line1: String, line2: String? = nil, city: String, state: String, postalCode: String, country: String = "US") {
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}

/// Display-only. The app never stores a card number — the brand and last four
/// are all it keeps, alongside the name and billing address the card is
/// registered to.
///
/// The two new fields are optional so a store written before they existed still
/// decodes: a synthesised `Codable` throws on a missing non-optional key, and
/// wiping somebody's saved cards to add a column would be a poor trade.
struct PaymentMethod: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var brand: String
    var last4: String
    var expiry: String
    var symbol: String
    var isDefault: Bool = false
    var cardholderName: String?
    var billing: BillingAddress?

    var label: String { "\(brand) ·· \(last4)" }

    /// What to show when a card predates these fields.
    var holderLabel: String {
        cardholderName?.isEmpty == false ? cardholderName! : "No name on file"
    }

    var billingSummary: String {
        billing?.oneLine ?? "No billing address"
    }

    var isComplete: Bool {
        cardholderName?.isEmpty == false && billing != nil
    }
}

struct CustomerProfile: Codable, Hashable, Sendable {
    var name: String = ""
    var phone: String = ""
    var email: String = ""
    var creditBalance: Decimal = .zero
    var joined: Date = Date()
    var favoriteHelperIDs: Set<UUID> = []

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Jobs

/// Instant means "somebody is on the way right now"; scheduled means a slot on
/// the calendar. Almost every branch in the app hangs off this one distinction.
enum JobTiming: Codable, Hashable, Sendable {
    case now
    case scheduled(start: Date)

    var isInstant: Bool {
        if case .now = self { return true }
        return false
    }

    var scheduledStart: Date? {
        if case .scheduled(let start) = self { return start }
        return nil
    }
}

enum JobStatus: String, Codable, CaseIterable, Sendable {
    /// Instant request out to nearby helpers, nobody has taken it yet.
    case searching
    /// On the calendar, waiting for its start window.
    case scheduled
    /// A helper took it; they haven't set off yet.
    case accepted
    case enRoute
    case arrived
    case inProgress
    case completed
    case cancelled
    /// Nobody nearby took the instant request.
    case unmatched

    var title: String {
        switch self {
        case .searching: "Finding a helper"
        case .scheduled: "Scheduled"
        case .accepted: "Helper confirmed"
        case .enRoute: "On the way"
        case .arrived: "Arrived"
        case .inProgress: "Working"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .unmatched: "No helper found"
        }
    }

    var symbol: String {
        switch self {
        case .searching: "dot.radiowaves.left.and.right"
        case .scheduled: "calendar"
        case .accepted: "checkmark.circle.fill"
        case .enRoute: "car.fill"
        case .arrived: "mappin.circle.fill"
        case .inProgress: "hammer.fill"
        case .completed: "checkmark.seal.fill"
        case .cancelled: "xmark.circle.fill"
        case .unmatched: "exclamationmark.triangle.fill"
        }
    }

    /// True while the job is worth putting a live banner on the home screen for.
    var isLive: Bool {
        switch self {
        case .searching, .accepted, .enRoute, .arrived, .inProgress: true
        case .scheduled, .completed, .cancelled, .unmatched: false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .cancelled, .unmatched: true
        default: false
        }
    }

    /// The order the tracking timeline draws them in.
    static let trackingOrder: [JobStatus] = [.accepted, .enRoute, .arrived, .inProgress, .completed]
}

struct JobEvent: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var at: Date
    var status: JobStatus
    var note: String
}

struct Message: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var at: Date
    var body: String
    var fromCustomer: Bool
    var isSystem: Bool = false
}

struct JobRating: Codable, Hashable, Sendable {
    var stars: Int
    var comment: String = ""
    var tip: Decimal = .zero
    var compliments: [String] = []

    static let complimentOptions = [
        "On time", "Great communication", "Careful work",
        "Left it spotless", "Went above and beyond", "Friendly",
    ]
}

// MARK: - Haggling over the rate

/// One side's number, on the record.
struct RateProposal: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var rate: Decimal
    var byCustomer: Bool
    var at: Date = Date()
    var note: String = ""
    /// Which helper countered. Nil on the customer's own proposals.
    var helperID: UUID?
}

/// The back-and-forth over an hourly rate.
///
/// Kept as the full list rather than just the current number, because "they
/// asked 64, I said 52, they came back at 58" is the thing both sides want to
/// see — and it's what stops either app from quietly rewriting history.
struct RateNegotiation: Codable, Hashable, Sendable {
    /// Chronological. The first entry is always the customer's opening offer.
    var proposals: [RateProposal]
    var agreedRate: Decimal?
    var declinedBy: Bool?

    init(openingRate: Decimal, at date: Date = Date(), note: String = "") {
        proposals = [RateProposal(rate: openingRate, byCustomer: true, at: date, note: note)]
    }

    var opening: RateProposal { proposals[0] }
    var latest: RateProposal { proposals[proposals.count - 1] }

    var isSettled: Bool { agreedRate != nil || declinedBy != nil }

    /// The customer has a number in front of them they haven't answered.
    var awaitingCustomer: Bool { !isSettled && !latest.byCustomer }
    /// The helper side has the ball — either the opening offer or a counter-back.
    var awaitingHelper: Bool { !isSettled && latest.byCustomer }

    /// What the job should be priced at right now: the agreement if there is
    /// one, otherwise the most recent thing the *customer* put on the table.
    /// A helper's counter doesn't move the price until it's accepted.
    var customerFacingRate: Decimal {
        agreedRate ?? proposals.last { $0.byCustomer }?.rate ?? opening.rate
    }

    /// How far apart the two sides still are.
    var gap: Decimal? {
        guard !isSettled, !latest.byCustomer else { return nil }
        return latest.rate - customerFacingRate
    }

    var rounds: Int { proposals.count }

    mutating func counter(_ rate: Decimal, byCustomer: Bool, helperID: UUID? = nil, note: String = "", at date: Date = Date()) {
        proposals.append(RateProposal(
            rate: rate, byCustomer: byCustomer, at: date, note: note, helperID: helperID
        ))
    }

    mutating func agree(at rate: Decimal) {
        agreedRate = rate
    }

    mutating func decline(byCustomer: Bool) {
        declinedBy = byCustomer
    }
}

struct Job: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var category: HelpCategory
    var title: String
    var notes: String = ""
    var photoNames: [String] = []
    var address: SavedAddress
    var timing: JobTiming
    var estimatedMinutes: Int
    var quote: Quote
    var status: JobStatus
    var helper: Helper?
    var dispatch: DispatchPlan?
    var createdAt: Date = Date()
    var events: [JobEvent] = []
    var messages: [Message] = []
    var rating: JobRating?
    /// When each side last opened the thread. Nil means never.
    var customerReadAt: Date?
    var helperReadAt: Date?
    var paymentMethodID: UUID?
    /// Filled in at completion — a job that ran long is charged for what it ran.
    var billedMinutes: Int?
    var finalTotal: Decimal?
    var cancellationReason: String?
    /// Set when the customer picked this person themselves instead of taking
    /// whoever the dispatcher found.
    var helperWasChosen: Bool = false
    /// Present when the rate was named by the customer rather than taken from
    /// the category's going rate — always for Custom, optionally for the rest.
    var negotiation: RateNegotiation?

    /// True while a helper's counter is sitting unanswered. The one state the
    /// customer has to be pulled back into the app for.
    var needsRateResponse: Bool {
        status == .searching && negotiation?.awaitingCustomer == true
    }

    var startsAt: Date {
        timing.scheduledStart ?? createdAt
    }

    /// Unread counts, one per side.
    ///
    /// Read state is a timestamp rather than a flag per message: a thread is
    /// read up to the moment you looked at it. Each side gets its own stamp —
    /// the customer opening the chat says nothing about whether the helper has
    /// seen it, and they share one `Job` in the store.
    ///
    /// Replying also counts as reading, so answering without scrolling to the
    /// top doesn't leave a badge behind.
    var unreadFromHelper: Int {
        Job.unread(in: messages, fromCustomer: false, seenAt: customerReadAt, repliedBy: true)
    }

    var unreadFromCustomer: Int {
        Job.unread(in: messages, fromCustomer: true, seenAt: helperReadAt, repliedBy: false)
    }

    private static func unread(
        in messages: [Message],
        fromCustomer wantCustomer: Bool,
        seenAt: Date?,
        repliedBy myReplyIsFromCustomer: Bool
    ) -> Int {
        let myLastReply = messages.last { $0.fromCustomer == myReplyIsFromCustomer && !$0.isSystem }?.at
        let seenUpTo = [seenAt, myLastReply].compactMap { $0 }.max()
        return messages.filter { message in
            message.fromCustomer == wantCustomer
                && !message.isSystem
                && (seenUpTo.map { message.at > $0 } ?? true)
        }.count
    }

    var amountDue: Decimal { finalTotal ?? quote.total }
}

// MARK: - Demand

/// What the dispatcher knows about the neighbourhood right now. Held as data
/// rather than read off a clock inside the pricing code so tests can pin it.
struct DemandIndex: Codable, Hashable, Sendable {
    var openRequests: Int
    var availableHelpers: Int

    static let calm = DemandIndex(openRequests: 4, availableHelpers: 12)

    /// Clamped and rounded to a tenth, because "1.3×" is a number a customer
    /// can argue with and "1.2837×" isn't.
    var multiplier: Decimal {
        guard availableHelpers > 0 else { return Pricing.maximumSurge }
        let ratio = Double(openRequests) / Double(availableHelpers)
        let raw = 1.0 + max(0, ratio - 0.4) * 1.1
        let stepped = (raw * 10).rounded() / 10
        let clamped = min(max(stepped, 1.0), Pricing.maximumSurge.doubleValue)
        return Decimal(Int(clamped * 10)) / 10
    }

    var isSurging: Bool { multiplier > 1 }

    var blurb: String {
        isSurging
            ? "Busy right now — \(multiplier.formatted(.number.precision(.fractionLength(1))))× on labour"
            : "\(availableHelpers) helpers free nearby"
    }
}
