import AppKit

enum ApplicationLauncher {

    @discardableResult
    static func launch(_ item: QuickAppItem) -> Bool {
        let url = URL(fileURLWithPath: item.applicationPath)

        guard FileManager.default.fileExists(atPath: item.applicationPath) else {
            return false
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: config
        ) { _, error in
            if let error {
                NSLog("QuickApps: failed to launch \(item.name): \(error)")
            }
        }

        return true
    }
}
