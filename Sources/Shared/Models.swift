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
        }
    }

    var shortTitle: String {
        switch self {
        case .assembly: "Assembly"
        case .delivery: "Delivery"
        case .eventHelp: "Events"
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
        }
    }

    var defaultHourlyRate: Decimal {
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
        }
    }

    /// Nobody sends a helper across town for fifteen minutes of work, so each
    /// category books in a block. The quote never comes in under this.
    var minimumMinutes: Int {
        switch self {
        case .cleaning, .moving: 120
        case .yardWork: 90
        case .eventHelp: 180
        default: 60
        }
    }

    var suggestedMinutes: [Int] {
        switch self {
        case .cleaning: [120, 180, 240, 300]
        case .moving: [120, 180, 240, 360]
        case .yardWork: [90, 120, 180, 240]
        case .eventHelp: [180, 240, 300, 360]
        default: [60, 90, 120, 180]
        }
    }

    /// Crews for a Saturday party get staffed days ahead, not dispatched in
    /// eleven minutes — so this category is scheduled-only.
    var supportsInstant: Bool { self != .eventHelp }

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
        }
    }
}

struct Review: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var author: String
    var stars: Int
    var body: String
    var category: HelpCategory
    var daysAgo: Int
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

    func handles(_ category: HelpCategory) -> Bool { skills.contains(category) }
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

/// Display-only. The app never asks for or stores a real card number — the
/// last four and the brand are all a demo needs to show a payment row.
struct PaymentMethod: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var brand: String
    var last4: String
    var expiry: String
    var symbol: String
    var isDefault: Bool = false

    var label: String { "\(brand) ·· \(last4)" }
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
    var paymentMethodID: UUID?
    /// Filled in at completion — a job that ran long is charged for what it ran.
    var billedMinutes: Int?
    var finalTotal: Decimal?
    var cancellationReason: String?
    /// Set when the customer picked this person themselves instead of taking
    /// whoever the dispatcher found.
    var helperWasChosen: Bool = false

    var startsAt: Date {
        timing.scheduledStart ?? createdAt
    }

    var unreadFromHelper: Int {
        // The demo has no read receipts; anything after the customer's last
        // message counts as unread, which is close enough to feel right.
        guard let lastMine = messages.last(where: { $0.fromCustomer })?.at else {
            return messages.filter { !$0.fromCustomer && !$0.isSystem }.count
        }
        return messages.filter { !$0.fromCustomer && !$0.isSystem && $0.at > lastMine }.count
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
