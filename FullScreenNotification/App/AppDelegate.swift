import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerForLaunchAtLogin()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func registerForLaunchAtLogin() {
        let service = SMAppService.mainApp

        switch service.status {
        case .notRegistered, .notFound:
            break
        case .enabled, .requiresApproval:
            return
        @unknown default:
            return
        }

        do {
            try service.register()
        } catch {
            NSLog("Could not register Full Screen Notification to launch at login: %@", error.localizedDescription)
        }
    }
}
