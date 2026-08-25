import Foundation

/// Everything worth keeping between launches. Versioned so a schema change can
/// drop an incompatible file instead of crashing on decode.
struct StoreSnapshot: Codable {
    static let currentVersion = 3

    var version: Int = StoreSnapshot.currentVersion
    /// Bumped on every write. Each app remembers the last revision it wrote or
    /// read, and reloads when the file has moved past it — that's the whole
    /// cross-app sync mechanism.
    var revision: Int = 0
    var hasOnboarded: Bool = false
    var profile: CustomerProfile = CustomerProfile()
    var addresses: [SavedAddress] = []
    var paymentMethods: [PaymentMethod] = []
    var jobs: [Job] = []
    var timeScale: Double = Dispatch.demoTimeScale

    /// Helpers who have declared themselves on shift.
    ///
    /// This started out as a heartbeat with a timeout, which was wrong for the
    /// worst possible reason: both apps live on one device, so the helper app is
    /// suspended the instant you switch to the customer app to place a request.
    /// Its heartbeat went stale within seconds and every request auto-matched.
    /// Presence has to be a latch that survives backgrounding — the safety valve
    /// for an app that never comes back is the customer app's bounded wait, not
    /// an expiry here.
    var onlineHelpers: Set<UUID> = []
    /// Informational only — when each helper last had the app open.
    var helperLastSeen: [UUID: Date] = [:]

    /// Reviews customers have actually written, keyed by helper.
    ///
    /// Kept apart from the roster so the shared document carries only what
    /// somebody typed, and `MockData` stays a seed rather than mutable state.
    /// Optional so a store written before reviews existed still decodes instead
    /// of being wiped for the sake of a new key.
    var publishedReviews: [UUID: [Review]]?

    var reviewsByHelper: [UUID: [Review]] { publishedReviews ?? [:] }

    func onlineHelperIDs(now: Date = Date()) -> Set<UUID> { onlineHelpers }

    /// True when a real helper app is on shift and able to take this job. The
    /// customer app stops auto-matching when that's the case, so a person gets
    /// the chance to accept before the simulation does it for them.
    func hasLiveHelper(for category: HelpCategory, in roster: [Helper], now: Date = Date()) -> Bool {
        roster.contains { onlineHelpers.contains($0.id) && $0.handles(category) }
    }

    /// True when any job still carries its helper's review list.
    var hasOverweightJobRecords: Bool {
        jobs.contains { $0.helper?.reviews.isEmpty == false }
    }

    /// Trims review lists out of the helper copies stored on jobs.
    ///
    /// Applied on every write, so the duplication can never come back, and
    /// flushed once at launch so a store written before `forJobRecord` existed
    /// shrinks straight away rather than waiting on an unrelated edit.
    func normalised() -> StoreSnapshot {
        var copy = self
        for index in copy.jobs.indices where copy.jobs[index].helper?.reviews.isEmpty == false {
            copy.jobs[index].helper = copy.jobs[index].helper?.forJobRecord
        }
        return copy
    }

    static func seeded() -> StoreSnapshot {
        StoreSnapshot(
            hasOnboarded: false,
            profile: MockData.profile,
            addresses: MockData.addresses,
            paymentMethods: MockData.paymentMethods,
            jobs: MockData.seedJobs(),
            timeScale: Dispatch.demoTimeScale
        )
    }
}

enum Persistence {
    static let filename = "help-on-the-way.json"

    /// The channel between the two apps. Both installs read and write one
    /// snapshot in here, which is what makes a request placed in the customer
    /// app show up as an offer in the helper app.
    static let appGroup = "group.com.hanelliotphan.helpontheway"

    static var sharedContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// False when the App Group isn't available — the apps then run as two
    /// independent simulations rather than silently losing each other's writes.
    /// Surfaced in the UI rather than hidden, because which mode you're in
    /// changes what the app can actually demonstrate.
    static var isSharedStoreAvailable: Bool { sharedContainer != nil }

    /// Resolved once. This used to run `createDirectory` on every access, which
    /// meant a filesystem call on each of the per-second reads below.
    private static let folder: URL = {
        let base = sharedContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let folder = base.appendingPathComponent("HelpOnTheWay", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static var directory: URL { folder }

    static var fileURL: URL { folder.appendingPathComponent(filename) }

    /// When the store last changed on disk.
    ///
    /// Both apps poll for the other's writes once a second. Decoding 18KB of
    /// JSON to discover the revision hasn't moved is the wrong way round — this
    /// is a stat, and it lets the overwhelmingly common "nothing happened" case
    /// cost almost nothing. The stamp comes off the file itself, so unlike a
    /// cached revision it can't go stale relative to the contents.
    static func modifiedAt() -> Date? {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func load() -> StoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? decoder.decode(StoreSnapshot.self, from: data) else {
            // A half-written or outdated file is worth less than a clean start.
            wipe()
            return nil
        }
        guard snapshot.version == StoreSnapshot.currentVersion else {
            wipe()
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: StoreSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
