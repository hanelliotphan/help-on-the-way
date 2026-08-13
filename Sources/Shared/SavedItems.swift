import Foundation

/// Rules for removing the things a customer has saved.
///
/// Pulled out of `AppSession` so they can be checked without standing up a
/// session — and so a test can't write over the real store on its way past.
enum SavedItems {

    // MARK: Addresses

    /// Every request needs somewhere to send a helper, so the last address stays
    /// put. The UI disables its delete rather than letting a row animate away
    /// and spring back.
    static func canRemove(address id: UUID, from addresses: [SavedAddress]) -> Bool {
        addresses.count > 1 && addresses.contains { $0.id == id }
    }

    static func removing(address id: UUID, from addresses: [SavedAddress]) -> [SavedAddress] {
        guard canRemove(address: id, from: addresses) else { return addresses }
        return addresses.filter { $0.id != id }
    }

    // MARK: Payment methods

    /// Cards can all go — the review step copes with none on file and offers to
    /// add one. What can't happen is a set of cards with no default in it, or
    /// the review step has nothing to preselect and every booking asks again.
    static func removing(paymentMethod id: UUID, from methods: [PaymentMethod]) -> [PaymentMethod] {
        guard methods.contains(where: { $0.id == id }) else { return methods }

        var remaining = methods.filter { $0.id != id }
        if !remaining.isEmpty, !remaining.contains(where: \.isDefault) {
            remaining[0].isDefault = true
        }
        return remaining
    }

    /// Adding a card. The first one is the default whether it asked to be or not,
    /// and a new default demotes the old one.
    static func adding(_ method: PaymentMethod, to methods: [PaymentMethod]) -> [PaymentMethod] {
        var added = method
        if methods.isEmpty { added.isDefault = true }

        var updated = methods
        if added.isDefault {
            for index in updated.indices { updated[index].isDefault = false }
        }
        updated.append(added)
        return updated
    }

    /// Exactly one default, always — the invariant both of the above maintain.
    static func hasSingleDefault(_ methods: [PaymentMethod]) -> Bool {
        methods.isEmpty || methods.filter(\.isDefault).count == 1
    }
}
