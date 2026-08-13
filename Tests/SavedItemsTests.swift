import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Removing saved addresses and cards")
struct SavedItemsTests {

    private func card(_ last4: String, isDefault: Bool = false) -> PaymentMethod {
        PaymentMethod(brand: "Visa", last4: last4, expiry: "12/29", symbol: "creditcard.fill", isDefault: isDefault)
    }

    // MARK: Addresses

    @Test("An address can be removed while another remains")
    func removeAddress() {
        let addresses = MockData.addresses
        let target = addresses[1].id
        #expect(SavedItems.canRemove(address: target, from: addresses))

        let after = SavedItems.removing(address: target, from: addresses)
        #expect(after.count == addresses.count - 1)
        #expect(!after.contains { $0.id == target })
    }

    @Test("The last address stays put")
    func lastAddressIsKept() {
        let one = [MockData.addresses[0]]
        #expect(!SavedItems.canRemove(address: one[0].id, from: one))
        #expect(SavedItems.removing(address: one[0].id, from: one) == one)
    }

    @Test("Removing an address that isn't there changes nothing")
    func removeUnknownAddress() {
        let addresses = MockData.addresses
        #expect(!SavedItems.canRemove(address: UUID(), from: addresses))
        #expect(SavedItems.removing(address: UUID(), from: addresses) == addresses)
    }

    @Test("Addresses can be removed down to one, then no further")
    func removeDownToOne() {
        var addresses = MockData.addresses
        #expect(addresses.count == 3)

        while let removable = addresses.first(where: { SavedItems.canRemove(address: $0.id, from: addresses) }) {
            addresses = SavedItems.removing(address: removable.id, from: addresses)
        }
        #expect(addresses.count == 1)
    }

    // MARK: Cards

    @Test("Removing a card leaves the rest alone")
    func removeCard() {
        let cards = [card("1111", isDefault: true), card("2222"), card("3333")]
        let after = SavedItems.removing(paymentMethod: cards[1].id, from: cards)
        #expect(after.count == 2)
        #expect(after.first?.last4 == "1111")
        #expect(after.first?.isDefault == true)
    }

    @Test("Removing the default promotes another one")
    func removingDefaultPromotes() {
        let cards = [card("1111", isDefault: true), card("2222"), card("3333")]
        let after = SavedItems.removing(paymentMethod: cards[0].id, from: cards)
        #expect(after.count == 2)
        #expect(after[0].last4 == "2222")
        #expect(after[0].isDefault, "something has to be the default")
        #expect(SavedItems.hasSingleDefault(after))
    }

    @Test("Removing a non-default doesn't move the default")
    func removingNonDefaultKeepsDefault() {
        let cards = [card("1111"), card("2222", isDefault: true)]
        let after = SavedItems.removing(paymentMethod: cards[0].id, from: cards)
        #expect(after.count == 1)
        #expect(after[0].last4 == "2222")
        #expect(after[0].isDefault)
    }

    @Test("Every card can go — cards aren't load-bearing the way an address is")
    func removeAllCards() {
        var cards = [card("1111", isDefault: true), card("2222")]
        for existing in cards {
            cards = SavedItems.removing(paymentMethod: existing.id, from: cards)
        }
        #expect(cards.isEmpty)
        #expect(SavedItems.hasSingleDefault(cards), "no cards means no default to hold")
    }

    @Test("Removing a card that isn't there changes nothing")
    func removeUnknownCard() {
        let cards = [card("1111", isDefault: true)]
        #expect(SavedItems.removing(paymentMethod: UUID(), from: cards) == cards)
    }

    @Test("Exactly one default survives any sequence of removals")
    func defaultInvariantHolds() {
        var cards = [
            card("1111", isDefault: true), card("2222"), card("3333"), card("4444"),
        ]
        // Take them out from the front, which repeatedly removes the default.
        while !cards.isEmpty {
            #expect(SavedItems.hasSingleDefault(cards), "invariant broken at \(cards.count) cards")
            cards = SavedItems.removing(paymentMethod: cards[0].id, from: cards)
        }
        #expect(cards.isEmpty)
    }

    // MARK: Adding

    @Test("The first card is the default whether it asked to be or not")
    func firstCardBecomesDefault() {
        let added = SavedItems.adding(card("1111", isDefault: false), to: [])
        #expect(added.count == 1)
        #expect(added[0].isDefault)
    }

    @Test("A new default demotes the old one")
    func newDefaultDemotesOld() {
        let existing = [card("1111", isDefault: true)]
        let added = SavedItems.adding(card("2222", isDefault: true), to: existing)
        #expect(added.count == 2)
        #expect(added[0].isDefault == false)
        #expect(added[1].isDefault)
        #expect(SavedItems.hasSingleDefault(added))
    }

    @Test("Adding a non-default leaves the existing default in place")
    func addingNonDefault() {
        let existing = [card("1111", isDefault: true)]
        let added = SavedItems.adding(card("2222", isDefault: false), to: existing)
        #expect(added[0].isDefault)
        #expect(added[1].isDefault == false)
        #expect(SavedItems.hasSingleDefault(added))
    }

    @Test("Adding then removing the same card returns the original set")
    func addRemoveRoundTrip() {
        let original = [card("1111", isDefault: true), card("2222")]
        let newCard = card("3333")
        let added = SavedItems.adding(newCard, to: original)
        let back = SavedItems.removing(paymentMethod: newCard.id, from: added)
        #expect(back == original)
    }

    @Test("The seeded cards already satisfy the invariant")
    func seededCardsHaveOneDefault() {
        #expect(SavedItems.hasSingleDefault(MockData.paymentMethods))
    }
}
