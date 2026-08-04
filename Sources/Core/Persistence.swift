import Foundation

/// Everything worth keeping between launches. Versioned so a schema change can
/// drop an incompatible file instead of crashing on decode.
struct StoreSnapshot: Codable {
    static let currentVersion = 1

    var version: Int = StoreSnapshot.currentVersion
    var hasOnboarded: Bool = false
    var profile: CustomerProfile = CustomerProfile()
    var addresses: [SavedAddress] = []
    var paymentMethods: [PaymentMethod] = []
    var jobs: [Job] = []
    var timeScale: Double = Dispatch.demoTimeScale
}

enum Persistence {
    static let filename = "help-on-the-way.json"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let folder = base.appendingPathComponent("HelpOnTheWay", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var fileURL: URL { directory.appendingPathComponent(filename) }

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
