import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        AppLogger.info(
            "app.lifecycle",
            "Launched version=\(version) build=\(build) log=\(AppLogger.logFileURL.path)"
        )

        NSApp.setActivationPolicy(.accessory)
        registerForLaunchAtLogin()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLogger.info("app.lifecycle", "Terminating")
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
            AppLogger.info("app.lifecycle", "Registered launch-at-login service")
        } catch {
            AppLogger.error(
                "app.lifecycle",
                "Launch-at-login registration failed \(AppLogger.errorSummary(error))"
            )
        }
    }
}
