import SwiftUI

/// The one thing that can be covering the tabs. Modelled as a single route
/// rather than four independent covers, because a job hands off from matching to
/// tracking to rating and two covers racing each other looks broken.
enum AppRoute: Identifiable, Equatable {
    case request
    case matching(UUID)
    case tracking(UUID)
    case rating(UUID)

    var id: String {
        switch self {
        case .request: "request"
        case .matching(let id): "matching-\(id)"
        case .tracking(let id): "tracking-\(id)"
        case .rating(let id): "rating-\(id)"
        }
    }
}

extension AppSession {
    var route: AppRoute? {
        if draft != nil { return .request }
        if let id = matchingJobID { return .matching(id) }
        if let id = trackingJobID { return .tracking(id) }
        if let id = ratingJobID { return .rating(id) }
        return nil
    }

    func dismissRoute() {
        draft = nil
        matchingJobID = nil
        trackingJobID = nil
        ratingJobID = nil
    }

    /// Opens the request flow. Coming in from a category tile skips the picker.
    func startRequest(category: HelpCategory? = nil, instant: Bool = true) {
        draft = RequestDraft(
            category: category ?? .cleaning,
            address: homeAddress,
            wantsInstant: instant,
            startingAt: category == nil ? .category : .details,
            now: now
        )
        draft?.paymentMethod = defaultPaymentMethod
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.hasOnboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay(text: Binding(
                get: { session.toast },
                set: { session.toast = $0 }
            ))
        }
        .fullScreenCover(item: Binding(
            get: { session.route },
            set: { if $0 == nil { session.dismissRoute() } }
        )) { route in
            switch route {
            case .request:
                if let draft = session.draft { RequestFlowView(draft: draft) }
            case .matching(let id):
                MatchingView(jobID: id)
            case .tracking(let id):
                TrackingView(jobID: id)
            case .rating(let id):
                RatingView(jobID: id)
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session

        TabView(selection: $session.selectedTab) {
            // Outline glyphs and plain nouns. A waving hand and a pair of speech
            // bubbles read as a toy; this is the vocabulary every booking app uses.
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(RootTab.home)

            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "clock") }
                .tag(RootTab.activity)

            NavigationStack { MessagesView() }
                .tabItem { Label("Messages", systemImage: "message") }
                .badge(session.unreadCount)
                .tag(RootTab.messages)

            NavigationStack { ProfileView() }
                .tabItem { Label("Account", systemImage: "person") }
                .tag(RootTab.profile)
        }
    }
}
