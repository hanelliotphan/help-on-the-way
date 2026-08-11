import SwiftUI

struct OnboardingView: View {
    @Environment(AppSession.self) private var session

    @State private var name = ""
    @State private var phone = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero

                VStack(spacing: 12) {
                    pitch(
                        symbol: "bolt.fill", tint: Palette.instant,
                        title: "Now",
                        detail: "Someone nearby takes the job in minutes. Watch them come to you."
                    )
                    pitch(
                        symbol: "calendar", tint: Palette.planned,
                        title: "Later",
                        detail: "Pick a day, a time, and the exact helper you want."
                    )
                    pitch(
                        symbol: "checkmark.shield.fill", tint: Palette.success,
                        title: "Vetted either way",
                        detail: "Background-checked, rated by neighbours, insured on every job."
                    )
                }

                Card(spacing: 14) {
                    Text("Who are we sending help to?")
                        .font(.headline)
                    VStack(spacing: 10) {
                        field(title: "Name", text: $name, placeholder: "Han-Elliot Phan")
                        field(title: "Mobile", text: $phone, placeholder: "(415) 555-0134", keyboard: .phonePad)
                    }
                    Text("Used so your helper can reach you at the door. Nothing else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    BigButton(title: "Get started", symbol: "arrow.right") {
                        session.completeOnboarding(name: name, phone: phone)
                    }
                    Button("Skip for now") {
                        session.completeOnboarding(name: "", phone: "")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(Palette.canvas)
        .onAppear {
            // The demo account already has details; showing them beats making
            // somebody type a name to see the app.
            if name.isEmpty { name = session.profile.name }
            if phone.isEmpty { phone = session.profile.phone }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: 108, height: 108)
                Image(systemName: "figure.wave.circle.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.top, 26)

            VStack(spacing: 6) {
                Text("Help on the Way")
                    .font(.largeTitle.weight(.bold))
                Text("Cleaning, repairs, moving, errands — right now or on your calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func pitch(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func field(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}
