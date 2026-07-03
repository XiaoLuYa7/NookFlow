import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let islandWindowController = IslandWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        islandWindowController.setup()
        NotificationCoordinator.shared.start()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        islandWindowController.showSettingsFromDock()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        islandWindowController.bringSettingsToFrontIfVisible()
    }
}
