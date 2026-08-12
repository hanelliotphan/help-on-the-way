import SwiftUI

/// Closing the account.
///
/// Deliberately unhurried: it lists what's about to go, refuses outright while a
/// helper is relying on the account, and asks for a typed word rather than a
/// second tap. None of that is friction for its own sake — there's no undo and
/// no server-side copy to restore from.
struct DeleteAccountView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var showingFinalConfirm = false
    @FocusState private var fieldFocused: Bool

    private var blockers: [AccountDeletion.Blocker] { session.deletionBlockers }

    private var summary: [String] {
        AccountDeletion.summary(
            jobs: session.jobs,
            addresses: session.addresses,
            paymentMethods: session.paymentMethods,
            favourites: session.profile.favoriteHelperIDs.count
        )
    }

    private var canDelete: Bool {
        blockers.isEmpty && AccountDeletion.matchesConfirmation(typed)
    }

    var body: some View {
        Form {
            if blockers.isEmpty {
                whatGoesSection
                confirmationSection
                buttonSection
            } else {
                blockedSection
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showingFinalConfirm) {
            Button("Delete everything", role: .destructive) { delete() }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("This can't be undone. Everything listed is erased from this device immediately.")
        }
    }

    // MARK: Blocked

    private var blockedSection: some View {
        Section {
            ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                VStack(alignment: .leading, spacing: 3) {
                    Text(blocker.message)
                        .font(.subheadline.weight(.medium))
                    Text(blocker.remedy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Button {
                dismiss()
                session.selectedTab = .activity
            } label: {
                Label("Go to Activity", systemImage: "arrow.right.circle")
            }
        } header: {
            Text("Finish up first")
        } footer: {
            Text("A helper has committed time to these. Cancelling from your side is one tap; disappearing on them isn't something the app will do quietly.")
        }
    }

    // MARK: Deleting

    private var whatGoesSection: some View {
        Section {
            ForEach(summary, id: \.self) { line in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                    Text(line)
                        .font(.subheadline)
                }
                .padding(.vertical, 1)
            }
        } header: {
            Text("What gets erased")
        } footer: {
            Text("There's no server behind this app, so there's no backup to restore from. Once it's gone it's gone.")
        }
    }

    private var confirmationSection: some View {
        Section {
            TextField(AccountDeletion.confirmationPhrase, text: $typed)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldFocused)
        } header: {
            Text("Type \(AccountDeletion.confirmationPhrase) to confirm")
        }
    }

    private var buttonSection: some View {
        Section {
            Button(role: .destructive) {
                fieldFocused = false
                showingFinalConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete my account")
                        .font(.headline)
                    Spacer()
                }
            }
            .disabled(!canDelete)
        }
    }

    private func delete() {
        // Returns false if something started blocking between opening this screen
        // and pressing the button — a scheduled job going live, for instance.
        guard session.deleteAccount() else {
            session.toast = "Couldn't delete — a job just became active."
            return
        }
        session.toast = "Account deleted."
        dismiss()
    }
}
