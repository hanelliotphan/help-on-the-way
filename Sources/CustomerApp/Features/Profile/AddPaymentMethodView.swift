import SwiftUI

/// Adding a card.
///
/// The number is checked here and then thrown away: what gets saved is a brand,
/// four digits and an expiry, because that's all the app has any business
/// keeping. There is no network, no tokenisation and no card on a server —
/// which is exactly why the footer says so out loud rather than implying this
/// is a real payment setup.
struct AddPaymentMethodView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    // Digits only. Formatting is derived for display rather than written back
    // into the state: reformatting inside `onChange` fights the text field while
    // you type and drops keystrokes — fast entry lost half a card number.
    @State private var numberDigits = ""
    @State private var expiryDigits = ""
    @State private var cvcDigits = ""
    @State private var makeDefault = false
    @FocusState private var focused: CardEntry.Field?

    // MARK: Name and billing

    @State private var cardholderName = ""
    /// nil means "a different address", which reveals the manual fields.
    @State private var savedAddressID: UUID?
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var postalCode = ""
    @FocusState private var billingFocused: BillingEntry.Field?
    @State private var hasPrefilled = false

    private var usingSavedAddress: SavedAddress? {
        session.addresses.first { $0.id == savedAddressID }
    }

    /// Either lifted from a saved address or typed in.
    private var billing: BillingAddress? {
        if let saved = usingSavedAddress { return BillingAddress(from: saved) }
        guard billingIssues.isEmpty else { return nil }
        return BillingEntry.billingAddress(
            line1: line1, line2: line2, city: city, state: state, postalCode: postalCode
        )
    }

    private var billingIssues: [BillingEntry.Issue] {
        if let saved = usingSavedAddress {
            // A saved address is already good enough to send a helper to, so only
            // the name is still in question.
            return BillingEntry.issues(
                name: cardholderName, line1: saved.street, city: saved.city,
                state: saved.state, postalCode: saved.postalCode
            )
        }
        return BillingEntry.issues(
            name: cardholderName, line1: line1, city: city, state: state, postalCode: postalCode
        )
    }

    private func billingError(for field: BillingEntry.Field) -> BillingEntry.Issue? {
        guard billingFocused != field else { return nil }
        let raw = switch field {
        case .name: cardholderName
        case .line1: line1
        case .line2: line2
        case .city: city
        case .state: state
        case .postalCode: postalCode
        }
        // The name is required, so flag it blank; the rest only once touched.
        if field != .name, raw.isEmpty { return nil }
        return billingIssues.first { $0.field == field }
    }

    private var number: String { numberDigits }
    private var expiry: String { expiryDigits }
    private var cvc: String { cvcDigits }

    private var brand: CardEntry.Brand? {
        CardEntry.Brand.detect(from: numberDigits)
    }

    /// Longest number the detected brand allows, so the field stops rather than
    /// silently accepting digits that can never validate.
    private var numberCap: Int {
        brand?.numberLengths.max() ?? 19
    }

    private var numberField: Binding<String> {
        Binding(
            get: { CardEntry.formatted(numberDigits) },
            set: { numberDigits = String(CardEntry.digits(in: $0).prefix(numberCap)) }
        )
    }

    private var expiryField: Binding<String> {
        Binding(
            get: { Self.slashed(expiryDigits) },
            set: { expiryDigits = String(CardEntry.digits(in: $0).prefix(4)) }
        )
    }

    private var cvcField: Binding<String> {
        Binding(
            get: { cvcDigits },
            set: { cvcDigits = String(CardEntry.digits(in: $0).prefix(brand?.cvcLength ?? 4)) }
        )
    }

    private var issues: [CardEntry.Issue] {
        CardEntry.issues(number: number, expiry: expiry, cvc: cvc, now: session.now)
    }

    /// Only complain about a field once it has been filled in and left, so the
    /// form isn't red before you've finished typing.
    private func visibleIssue(for field: CardEntry.Field) -> CardEntry.Issue? {
        guard focused != field else { return nil }
        let raw = switch field {
        case .number: number
        case .expiry: expiry
        case .cvc: cvc
        }
        guard !raw.isEmpty else { return nil }
        return issues.first { $0.field == field }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Label above, field full width beneath. Side-by-side left
                    // the number clipped once the brand label claimed space.
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Card number")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let brand {
                                Text(brand.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        TextField("4242 4242 4242 4242", text: numberField)
                            .keyboardType(.numberPad)
                            .font(.body.monospacedDigit())
                            .focused($focused, equals: .number)
                        error(for: .number)
                    }
                    .padding(.vertical, 2)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Expires")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("MM/YY", text: expiryField)
                                .keyboardType(.numberPad)
                                .font(.body.monospacedDigit())
                                .focused($focused, equals: .expiry)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Security code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(brand == .amex ? "1234" : "123", text: cvcField)
                                .keyboardType(.numberPad)
                                .font(.body.monospacedDigit())
                                .focused($focused, equals: .cvc)
                        }
                    }
                    .padding(.vertical, 2)

                    error(for: .expiry)
                    error(for: .cvc)
                } header: {
                    Text("Card")
                } footer: {
                    Text("The number and security code are used to check the card and then discarded — only the brand, the last four digits and the expiry are kept, alongside the name and billing address below. There's no server behind this, so nothing leaves the device.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name on card")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Han-Elliot Phan", text: $cardholderName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($billingFocused, equals: .name)
                        if let issue = billingError(for: .name) {
                            Text(issue.message)
                                .font(.caption)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Cardholder")
                }

                Section {
                    Picker("Billing address", selection: $savedAddressID) {
                        ForEach(session.addresses) { saved in
                            Text(saved.label).tag(Optional(saved.id))
                        }
                        Text("A different address").tag(UUID?.none)
                    }

                    if let saved = usingSavedAddress {
                        Text(saved.fullAddress)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        billingFields
                    }
                } header: {
                    Text("Billing address")
                } footer: {
                    Text("Where the card is registered. Reusing a saved address copies it — editing that address later won't change what this card is billed to.")
                }

                Section {
                    Toggle("Use as default", isOn: $makeDefault)
                        .disabled(session.paymentMethods.isEmpty)
                } footer: {
                    if session.paymentMethods.isEmpty {
                        Text("This is your first card, so it becomes the default automatically.")
                    }
                }
            }
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !hasPrefilled else { return }
                hasPrefilled = true
                // Sensible openers: the account holder's own name, and their
                // home address, which is what a card is usually billed to.
                cardholderName = session.profile.name
                savedAddressID = session.addresses.first?.id
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }
                        .font(.headline)
                        .disabled(!issues.isEmpty || !billingIssues.isEmpty)
                }
            }
        }
    }

    /// Manual entry, shown only when no saved address is selected.
    @ViewBuilder
    private var billingFields: some View {
        billingField("Street", text: $line1, field: .line1, placeholder: "1042 Valencia St")
        billingField("Apartment, unit (optional)", text: $line2, field: .line2, placeholder: "Apt 3B")
        billingField("City", text: $city, field: .city, placeholder: "San Francisco")

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("State")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("CA", text: $state)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($billingFocused, equals: .state)
                    .onChange(of: state) { _, new in
                        // Two letters is the whole field, so stop rather than
                        // letting somebody type "California" and fail later.
                        let capped = String(new.filter(\.isLetter).prefix(2)).uppercased()
                        if capped != new { state = capped }
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ZIP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("94110", text: $postalCode)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($billingFocused, equals: .postalCode)
            }
        }
        .padding(.vertical, 2)

        if let issue = billingError(for: .state) ?? billingError(for: .postalCode) {
            Text(issue.message)
                .font(.caption)
                .foregroundStyle(Palette.danger)
        }
    }

    @ViewBuilder
    private func billingField(
        _ title: String,
        text: Binding<String>,
        field: BillingEntry.Field,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .focused($billingFocused, equals: field)
            if let issue = billingError(for: field) {
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func error(for field: CardEntry.Field) -> some View {
        if let issue = visibleIssue(for: field) {
            Text(issue.message)
                .font(.caption)
                .foregroundStyle(Palette.danger)
        }
    }

    private func save() {
        guard let method = CardEntry.paymentMethod(
            number: number,
            expiry: expiry,
            cvc: cvc,
            cardholderName: cardholderName,
            billing: billing,
            isDefault: makeDefault,
            now: session.now
        ) else { return }

        session.addPaymentMethod(method)
        // Clear the entry fields before the view goes away, so the digits aren't
        // sitting in view state waiting to be torn down.
        numberDigits = ""
        cvcDigits = ""
        expiryDigits = ""
        dismiss()
    }

    /// Inserts the slash as you type, and keeps it from being typed twice.
    static func slashed(_ raw: String) -> String {
        let all = CardEntry.digits(in: raw).prefix(4)
        guard all.count > 2 else { return String(all) }
        return "\(all.prefix(2))/\(all.dropFirst(2))"
    }
}
