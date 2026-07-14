import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSPanel?
    private var hostingView: NSHostingView<SettingsRootView>?
    private var editorModel: SettingsEditorModel?
    private let settings: IslandSettings
    private let defaultWindowSize = NSSize(width: 1020, height: 660)
    private var presentationTask: Task<Void, Never>?

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

        presentationTask?.cancel()
        if !window.isKeyWindow {
            window.alphaValue = 0
        }

        NSApp.unhide(nil)
        activateApplication()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Keep a normal app-window level throughout activation. Changing levels
        // after the window appears can reorder it behind the previously active app.
        window.level = .normal
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        NSApp.arrangeInFront(nil)

        revealWindowWhenActive(window)
    }

    private func activateApplication() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func revealWindowWhenActive(_ window: NSWindow) {
        presentationTask = Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }

            // Activation policy changes can take more than one run-loop turn.
            // Keep the panel transparent until AppKit applies active control colors.
            for attempt in 0..<4 {
                guard !Task.isCancelled, self.window === window, window.isVisible else { return }

                self.activateApplication()
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                await Task.yield()

                if NSApp.isActive, window.isKeyWindow {
                    break
                }

                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                }
            }

            guard !Task.isCancelled, self.window === window, window.isVisible else { return }
            window.alphaValue = 1
            self.presentationTask = nil
        }
    }

    private func ensureAppCanActivateForSettings() {
        if NSApp.activationPolicy() != .regular {
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
        panel.title = "NookFlow 设置"
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
        presentationTask?.cancel()
        presentationTask = nil
        window?.alphaValue = 1
    }
}
