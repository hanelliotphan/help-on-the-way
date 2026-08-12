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
                    Text("Only the brand, the last four digits and the expiry are saved. The number and security code are used to check the card and then discarded — there's no server behind this, so nothing is stored anywhere else.")
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }
                        .font(.headline)
                        .disabled(!issues.isEmpty)
                }
            }
        }
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
