import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let islandWindowController = IslandWindowController()
    private var licenseRefreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        islandWindowController.setup()
        NotificationCoordinator.shared.start()
        AppUpdateController.shared.start()
        refreshLicenseAfterLaunch()
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
        refreshLicenseAfterLaunch(force: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        licenseRefreshTask?.cancel()
        licenseRefreshTask = nil
        NotificationCoordinator.shared.stop()
        MediaRemoteStreamBridge.shared.shutdown()
    }

    private func refreshLicenseAfterLaunch(force: Bool = true) {
        guard licenseRefreshTask == nil else { return }
        licenseRefreshTask = Task { @MainActor in
            await LicenseManager.shared.refreshIfNeeded(force: force)
            licenseRefreshTask = nil
        }
    }
}
