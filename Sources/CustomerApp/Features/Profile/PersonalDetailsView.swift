import SwiftUI

/// Editing your own details. Reachable from the header row on the Account tab,
/// which previously showed the name and phone with no way to change either.
struct PersonalDetailsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var hasLoaded = false
    @FocusState private var focused: ProfileEditing.Field?

    private var issues: [ProfileEditing.Issue] {
        ProfileEditing.issues(name: name, phone: phone, email: email)
    }

    private func issue(for field: ProfileEditing.Field) -> ProfileEditing.Issue? {
        issues.first { $0.field == field }
    }

    private var isDirty: Bool {
        let clean = ProfileEditing.normalised(name: name, phone: phone, email: email)
        return clean.name != session.profile.name
            || clean.phone != session.profile.phone
            || clean.email != session.profile.email
    }

    var body: some View {
        Form {
            Section {
                field("Name", text: $name, field: .name, placeholder: "Han-Elliot Phan")
                field("Mobile", text: $phone, field: .phone, placeholder: "(415) 555-0134", keyboard: .phonePad)
                field("Email", text: $email, field: .email, placeholder: "you@example.com", keyboard: .emailAddress)
            } header: {
                Text("Your details")
            } footer: {
                Text("Your helper sees your name and can reach you on this number while a job is running. Nothing here leaves the device.")
            }

            Section {
                LabeledContent("Member since") {
                    Text(session.profile.joined.formatted(.dateTime.month(.wide).year()))
                }
                if session.profile.creditBalance > 0 {
                    LabeledContent("Credit") {
                        Text(session.profile.creditBalance.currency)
                            .foregroundStyle(Palette.success)
                    }
                }
            } footer: {
                Text("These aren't editable — they come from your booking history.")
            }
        }
        .navigationTitle("Personal details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    session.updateProfile(name: name, phone: phone, email: email)
                    dismiss()
                }
                .font(.headline)
                .disabled(!issues.isEmpty || !isDirty)
            }
        }
        .onAppear {
            // Guarded: coming back from the keyboard shouldn't wipe an edit in
            // progress by reloading the stored values over it.
            guard !hasLoaded else { return }
            hasLoaded = true
            name = session.profile.name
            phone = session.profile.phone
            email = session.profile.email
        }
    }

    @ViewBuilder
    private func field(
        _ title: String,
        text: Binding<String>,
        field: ProfileEditing.Field,
        placeholder: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(field == .email ? .never : .words)
                    .autocorrectionDisabled(field != .name)
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: field)
            }
            // Only complain about a field once the customer has left it, so the
            // form isn't scolding them mid-word.
            if let issue = issue(for: field), focused != field {
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
            }
        }
    }
}
