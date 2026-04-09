import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var authIssue: AppIssue?
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var minutesBefore: Int {
        didSet { UserDefaults.standard.set(minutesBefore, forKey: "minutesBefore") }
    }
    let oauthService = GoogleOAuthService()
    let calendarService: GoogleCalendarService
    let eventMonitor: EventMonitorService

    private let notificationController = NotificationWindowController()

    init() {
        let stored = UserDefaults.standard.integer(forKey: "minutesBefore")
        self.minutesBefore = stored > 0 ? stored : 5

        self.calendarService = GoogleCalendarService(oauthService: oauthService)
        self.eventMonitor = EventMonitorService()

        self.isAuthenticated = oauthService.isAuthenticated

        eventMonitor.onEventTriggered = { [weak self] event in
            Task { @MainActor in
                self?.showNotification(for: event)
            }
        }

        Task {
            await oauthService.restorePreviousSignIn()
            if !oauthService.hasCalendarAccess, oauthService.accessToken != nil {
                authIssue = AppIssue.from(OAuthError.calendarPermissionNotGranted)
            }
            syncAuthenticationState(forceReload: true)
        }
    }

    func signIn() {
        authIssue = nil

        Task {
            do {
                try await oauthService.startSignIn(presentingWindow: resolvePresentationWindow())
                authIssue = nil
                syncAuthenticationState(forceReload: true)
            } catch {
                let oauthError = OAuthError(from: error)
                isAuthenticated = false

                if case .canceled = oauthError {
                    authIssue = nil
                } else {
                    authIssue = AppIssue.from(oauthError)
                    print("Google Sign-In failed: \(oauthError.localizedDescription)")
                }
            }
        }
    }

    func signOut() {
        oauthService.signOut()
        isAuthenticated = false
        authIssue = nil
        upcomingEvents = []
        eventMonitor.stop()
    }

    func startMonitoring() {
        eventMonitor.start(
            calendarService: calendarService,
            minutesBefore: minutesBefore
        ) { [weak self] events in
            Task { @MainActor in
                self?.upcomingEvents = events
            }
        }
    }

    func refreshMonitoring() {
        eventMonitor.stop()
        startMonitoring()
    }

    func showSampleNotification() {
        let sampleEvent = CalendarEvent(
            id: "sample-\(UUID().uuidString)",
            summary: "Hello, I'm a demo event",
            start: EventDateTime(
                dateTime: Date().addingTimeInterval(60),
                date: nil,
                timeZone: nil
            ),
            end: EventDateTime(
                dateTime: Date().addingTimeInterval(60 * 60),
                date: nil,
                timeZone: nil
            ),
            hangoutLink: "https://meet.google.com/example",
            conferenceData: nil,
            htmlLink: nil,
            status: "confirmed"
        )
        showNotification(for: sampleEvent)
    }

    private func showNotification(for event: CalendarEvent) {
        notificationController.show(for: event) { [weak self] in
            self?.notificationController.dismiss()
        }
    }

    private func syncAuthenticationState(forceReload: Bool = false) {
        let serviceAuth = oauthService.isAuthenticated
        let authChanged = serviceAuth != isAuthenticated
        isAuthenticated = serviceAuth

        if serviceAuth, authChanged || forceReload {
            startMonitoring()
        } else if !serviceAuth, authChanged || forceReload {
            upcomingEvents = []
            eventMonitor.stop()
        }
    }

    private func resolvePresentationWindow() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow {
            return mainWindow
        }

        return NSApp.windows.first(where: \.isVisible) ?? NSApp.windows.first
    }
}

struct AppIssue {
    let title: String
    let message: String
    let detail: String?

    static func from(_ error: Error) -> AppIssue {
        if let oauthError = error as? OAuthError {
            return from(oauthError)
        }

        if let calendarError = error as? CalendarServiceError {
            return from(calendarError)
        }

        return AppIssue(
            title: "Connection Problem",
            message: "The app couldn't connect to Google Calendar.",
            detail: (error as NSError).localizedDescription
        )
    }

    static func from(_ error: OAuthError) -> AppIssue {
        switch error {
        case .notAuthenticated:
            return AppIssue(
                title: "Sign In Required",
                message: "Sign in to Google Calendar to continue.",
                detail: nil
            )
        case .canceled:
            return AppIssue(
                title: "Sign-In Canceled",
                message: "Google sign-in was canceled.",
                detail: nil
            )
        case .calendarPermissionNotGranted:
            return AppIssue(
                title: "Calendar Access Not Granted",
                message: "Sign in again and keep Google Calendar enabled.",
                detail: nil
            )
        case .sdkError(let message):
            return AppIssue(
                title: "Google Sign-In Failed",
                message: "Google sign-in couldn't be completed.",
                detail: message
            )
        }
    }

    static func from(_ error: CalendarServiceError) -> AppIssue {
        switch error {
        case .fetchFailed:
            return AppIssue(
                title: "Calendar Loading Failed",
                message: "The app couldn't load your calendars.",
                detail: nil
            )
        case .unauthorized(let message):
            return AppIssue(
                title: "Sign In Required",
                message: "Your Google Calendar session expired. Sign in again.",
                detail: message
            )
        case .forbidden(let message):
            if message.localizedCaseInsensitiveContains("api has not been used") ||
                message.localizedCaseInsensitiveContains("is disabled") {
                return AppIssue(
                    title: "Calendar Unavailable",
                    message: "Google Calendar isn't available right now. Try again later.",
                    detail: debugDetail("Google Calendar API is disabled for this project. \(message)")
                )
            }

            return AppIssue(
                title: "Calendar Access Denied",
                message: "Google did not allow calendar access for this account or project.",
                detail: message
            )
        case .requestFailed(let statusCode, let message):
            return AppIssue(
                title: "Google Calendar Error",
                message: "Google Calendar returned an error (\(statusCode)).",
                detail: message
            )
        }
    }

    private static func debugDetail(_ message: String) -> String? {
        #if DEBUG
        message
        #else
        nil
        #endif
    }
}
