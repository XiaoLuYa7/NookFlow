import SwiftUI

@main
struct LNookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We don't use a standard window — the panel is managed by AppDelegate.
        // This empty Settings scene keeps the app alive.
        Settings {
            EmptyView()
        }
    }
}
