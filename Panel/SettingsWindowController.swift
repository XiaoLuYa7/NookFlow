import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSPanel?
    private var hostingView: NSHostingView<SettingsRootView>?
    private var editorModel: SettingsEditorModel?
    private let settings: IslandSettings
    private let defaultWindowSize = NSSize(width: 1020, height: 660)
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    init(settings: IslandSettings) {
        self.settings = settings
        super.init()
    }

    func show(page: SettingsPage = .home, presentFeedback: Bool = false) {
        let model = editorModel ?? SettingsEditorModel(settings: settings)
        model.prepareForOpen(page: page, presentFeedback: presentFeedback)
        editorModel = model

        if window == nil {
            createWindow(model: model)
        } else {
            hostingView?.rootView = SettingsRootView(settings: settings, model: model)
        }

        normalizeWindowSizeIfNeeded()
        ensureAppCanActivateForSettings()
        presentWindowOnTop()
    }

    @discardableResult
    func bringToFrontIfVisible() -> Bool {
        guard window?.isVisible == true else { return false }
        ensureAppCanActivateForSettings()
        presentWindowOnTop()
        return true
    }

    private func presentWindowOnTop() {
        guard let window else { return }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Bring the settings window above the island and the current app once,
        // then drop it back to normal so it does not pin itself above other apps.
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        NSApp.arrangeInFront(nil)

        Task { @MainActor [weak self, weak window] in
            await Task.yield()
            guard let self, let window, self.window === window, window.isVisible else { return }

            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)

            try? await Task.sleep(nanoseconds: 420_000_000)
            guard self.window === window, window.isVisible else { return }
            window.level = .normal
        }
    }

    private func ensureAppCanActivateForSettings() {
        guard previousActivationPolicy == nil else { return }

        let policy = NSApp.activationPolicy()
        previousActivationPolicy = policy

        if policy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func createWindow(model: SettingsEditorModel) {
        let size = defaultWindowSize
        let rect = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "L-Nook Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 900, height: 580)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .normal
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(red: 0.982, green: 0.986, blue: 0.99, alpha: 1)
        panel.collectionBehavior = [.moveToActiveSpace]

        let rootView = SettingsRootView(settings: settings, model: model)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = rect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        window = panel
        self.hostingView = hostingView
    }

    private func normalizeWindowSizeIfNeeded() {
        guard let window else { return }

        let size = window.frame.size
        let shouldUseDefaultSize = size.width > defaultWindowSize.width * 1.12
            || size.height > defaultWindowSize.height * 1.12
            || size.width < window.minSize.width
            || size.height < window.minSize.height

        guard shouldUseDefaultSize else {
            window.center()
            return
        }

        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.midX - defaultWindowSize.width / 2,
            y: screenFrame.midY - defaultWindowSize.height / 2
        )
        window.setFrame(
            NSRect(origin: origin, size: defaultWindowSize),
            display: false
        )
    }

    func windowWillClose(_ notification: Notification) {
        restoreActivationPolicyIfNeeded()
    }

    private func restoreActivationPolicyIfNeeded() {
        guard let previousActivationPolicy else { return }
        self.previousActivationPolicy = nil

        if previousActivationPolicy != NSApp.activationPolicy() {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
    }
}
