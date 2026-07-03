import AppKit
import SwiftUI

enum InAppNotificationKind {
    case weather
    case battery
    case performance
    case storage
    case network
    case water
    case movement
    case sleep
    case general

    var symbolName: String {
        switch self {
        case .weather: "cloud.rain.fill"
        case .battery: "battery.25percent"
        case .performance: "gauge.with.dots.needle.67percent"
        case .storage: "internaldrive.fill"
        case .network: "wifi"
        case .water: "drop.fill"
        case .movement: "figure.walk"
        case .sleep: "moon.stars.fill"
        case .general: "bell.fill"
        }
    }

    var accent: Color {
        switch self {
        case .weather: Color(red: 0.28, green: 0.49, blue: 1.0)
        case .battery: Color(red: 0.27, green: 0.78, blue: 0.45)
        case .performance: Color(red: 1.0, green: 0.55, blue: 0.18)
        case .storage: Color(red: 0.34, green: 0.68, blue: 1.0)
        case .network: Color(red: 0.20, green: 0.72, blue: 0.95)
        case .water: Color(red: 0.23, green: 0.70, blue: 0.96)
        case .movement: Color(red: 0.40, green: 0.72, blue: 0.45)
        case .sleep: Color(red: 0.58, green: 0.43, blue: 0.94)
        case .general: AppColor.accent
        }
    }
}

struct InAppNotificationPayload {
    let title: String
    let message: String
    let kind: InAppNotificationKind
}

private enum InAppNotificationMetrics {
    static let bannerSize = CGSize(width: 356, height: 88)
    static let shadowPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 25

    static var panelSize: CGSize {
        CGSize(
            width: bannerSize.width + shadowPadding * 2,
            height: bannerSize.height + shadowPadding * 2
        )
    }
}

@MainActor
final class InAppNotificationWindowController {
    static let shared = InAppNotificationWindowController()

    private var panel: NSPanel?
    private var queue: [InAppNotificationPayload] = []
    private var presentationTask: Task<Void, Never>?
    private var isPresenting = false

    private init() {}

    func show(_ payload: InAppNotificationPayload) {
        queue.append(payload)
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard !isPresenting, !queue.isEmpty else { return }
        isPresenting = true
        let payload = queue.removeFirst()
        present(payload)
    }

    private func present(_ payload: InAppNotificationPayload) {
        presentationTask?.cancel()

        let panel = makePanelIfNeeded()
        panel.contentView = NSHostingView(
            rootView: InAppNotificationHost(payload: payload)
        )

        let panelSize = InAppNotificationMetrics.panelSize
        let targetFrame = frame(for: panelSize)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: 10)
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetFrame.origin)
        }

        presentationTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(4.2))
            guard let self, let panel, !Task.isCancelled else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrameOrigin(startFrame.origin)
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    panel?.orderOut(nil)
                    self?.isPresenting = false
                    self?.presentNextIfNeeded()
                }
            }
        }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = InAppNotificationPanel(
            contentRect: NSRect(origin: .zero, size: InAppNotificationMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.panel = panel
        return panel
    }

    private func frame(for size: NSSize) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return NSRect(origin: .zero, size: size) }

        let visibleFrame = screen.visibleFrame
        let padding = InAppNotificationMetrics.shadowPadding
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - size.height - 28 + padding,
            width: size.width,
            height: size.height
        )
    }
}

private final class InAppNotificationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct InAppNotificationHost: View {
    let payload: InAppNotificationPayload

    var body: some View {
        ZStack {
            InAppNotificationBanner(payload: payload)
        }
        .frame(
            width: InAppNotificationMetrics.panelSize.width,
            height: InAppNotificationMetrics.panelSize.height
        )
        .background(Color.clear)
    }
}

private struct InAppNotificationBanner: View {
    let payload: InAppNotificationPayload

    var body: some View {
        VStack(spacing: 7) {
            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(width: 52, height: 4)
                .padding(.top, 2)

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    payload.kind.accent.opacity(0.95),
                                    payload.kind.accent.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                    Image(systemName: payload.kind.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .shadow(color: payload.kind.accent.opacity(0.28), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(payload.message)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 17)
        .padding(.bottom, 12)
        .frame(
            width: InAppNotificationMetrics.bannerSize.width,
            height: InAppNotificationMetrics.bannerSize.height
        )
        .background {
            RoundedRectangle(cornerRadius: InAppNotificationMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.075, green: 0.082, blue: 0.092).opacity(0.98),
                            Color.black.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: InAppNotificationMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: InAppNotificationMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 2)
                        .blur(radius: 0.5)
                }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: InAppNotificationMetrics.cornerRadius,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, y: 8)
    }
}
