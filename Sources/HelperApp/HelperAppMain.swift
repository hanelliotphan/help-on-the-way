import SwiftUI

@main
struct HelpOnTheWayHelperApp: App {
    @State private var session = HelperSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HelperRootView()
                .environment(session)
                .tint(Palette.helper)
                .onChange(of: scenePhase) { _, phase in
                    // Coming back from the background is when the interesting
                    // thing has happened — the customer placed a request while
                    // this app was suspended.
                    if phase == .active { session.refreshFromForeground() }
                }
        }
    }
}

struct HelperRootView: View {
    @Environment(HelperSession.self) private var session

    var body: some View {
        Group {
            if session.me == nil {
                PersonaPickerView()
            } else {
                tabs
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay(text: Binding(
                get: { session.toast },
                set: { session.toast = $0 }
            ))
        }
    }

    private var tabs: some View {
        @Bindable var session = session

        return TabView(selection: $session.selectedTab) {
            NavigationStack { DriveView() }
                .tabItem { Label("Drive", systemImage: "steeringwheel") }
                .tag(HelperTab.drive)

            NavigationStack { HelperScheduleView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .badge(session.upcoming.count)
                .tag(HelperTab.schedule)

            NavigationStack { EarningsView() }
                .tabItem { Label("Earnings", systemImage: "banknote.fill") }
                .tag(HelperTab.earnings)

            NavigationStack { HelperAccountView() }
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(HelperTab.account)
        }
    }
}

/// Signing in, demo-style. The roster is fixed, so becoming a helper is picking
/// which of them you are — and it makes the two-app demo obvious, because you
/// can be the person the customer app just dispatched.
struct PersonaPickerView: View {
    @Environment(HelperSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Palette.helperSoft)
                            .frame(width: 96, height: 96)
                        Image(systemName: "steeringwheel")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Palette.helper)
                    }
                    .padding(.top, 24)

                    Text("Help on the Way")
                        .font(.largeTitle.weight(.bold))
                    Text("for helpers")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.helper)
                    Text("Pick who you're signing in as. Go online and requests from the customer app land here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !session.isSharedStore {
                    Card(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.instant)
                            Text("Not linked to the customer app")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("The shared App Group container isn't available, so this app is running against its own copy of the data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(session.roster) { helper in
                        Button {
                            session.signIn(as: helper)
                        } label: {
                            Card(padding: 14) {
                                HStack(spacing: 12) {
                                    Avatar(helper: helper, size: 46)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(helper.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        HStack(spacing: 5) {
                                            Stars(value: helper.rating, size: 10)
                                            Text("\(Format.rating(helper.rating)) · \(Format.rate(helper.hourlyRate))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(helper.skills.prefix(3).map(\.shortTitle).joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
    }
}
