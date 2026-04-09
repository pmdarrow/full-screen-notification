import AppKit
import SwiftUI

@MainActor
final class NotificationWindowController {
    private var window: NSWindow?
    private var escapeMonitor: Any?

    func show(for event: CalendarEvent, onDismiss: @escaping () -> Void) {
        if window != nil { dismiss() }

        guard let screen = NSScreen.main else { return }

        let overlayView = NotificationOverlayView(
            event: event,
            onJoin: { [weak self] url in
                NSWorkspace.shared.open(url)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = screen.frame

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.onEscape = { [weak self] in
            self?.dismiss()
        }
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = hostingView
        window.alphaValue = 0

        // Force the app to activate so the window receives key events immediately
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                return nil
            }
            return event
        }

        self.window = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }
    }

    func dismiss() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        guard let window else { return }
        let windowRef = window
        self.window = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            windowRef.animator().alphaValue = 0
        }, completionHandler: {
            windowRef.orderOut(nil)
        })
    }
}

private class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
