import Foundation

/// The dispatcher, as seen by both apps.
///
/// The customer app and the helper app are two separate installs with two
/// separate containers; the only thing they have in common is one JSON document
/// in a shared App Group. This is the door to it.
///
/// Every write is a read-modify-write against whatever is on disk *now* rather
/// than against a snapshot loaded a while ago — that is the difference between
/// the two apps cooperating and one silently erasing the other's work. Each
/// write bumps `revision`, which is how the other side notices it needs to
/// reload.
enum SharedStore {

    static var isShared: Bool { Persistence.isSharedStoreAvailable }

    static func load() -> StoreSnapshot? { Persistence.load() }

    /// Applies a change to the current state and hands back the result.
    ///
    /// Note the deliberate limitation: two writes landing inside the same poll
    /// interval can still lose one of them. There is no locking here because a
    /// pair of apps driven by one person's thumbs never actually races, and a
    /// file lock would buy correctness nobody in this demo can observe.
    /// - Parameter bumpRevision: pass `false` for writes the other app has no
    ///   reason to reload over. A presence heartbeat lands every second, and
    ///   bumping the revision for it would drag both apps through a full reload
    ///   of the job list once a second for no gain.
    @discardableResult
    static func mutate(bumpRevision: Bool = true, _ change: (inout StoreSnapshot) -> Void) -> StoreSnapshot {
        var snapshot = Persistence.load() ?? .seeded()
        change(&snapshot)
        if bumpRevision { snapshot.revision += 1 }
        // Trimmed on the way out, so an overweight job record can't be written
        // back by any path.
        snapshot = snapshot.normalised()
        Persistence.save(snapshot)
        return snapshot
    }

    /// Puts a helper on or off shift. This has to survive the app being
    /// suspended — on one device the helper app is always backgrounded while the
    /// customer places a request — so it's a stored latch, not a heartbeat.
    static func setOnline(_ online: Bool, helperID: UUID, at now: Date) {
        mutate { snapshot in
            if online {
                snapshot.onlineHelpers.insert(helperID)
            } else {
                snapshot.onlineHelpers.remove(helperID)
            }
            snapshot.helperLastSeen[helperID] = now
        }
    }

    /// A liveness note for display. Deliberately doesn't bump the revision —
    /// it lands every second and the other app has no reason to reload for it.
    static func touch(helperID: UUID, at now: Date) {
        mutate(bumpRevision: false) { $0.helperLastSeen[helperID] = now }
    }
}
