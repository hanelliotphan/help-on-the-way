import SwiftUI

@main
struct HelpOnTheWayApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Palette.accent)
        }
    }
}
