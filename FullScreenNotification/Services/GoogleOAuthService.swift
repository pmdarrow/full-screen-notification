import AppKit
import Foundation
@preconcurrency import GoogleSignIn

@MainActor
final class GoogleOAuthService {
    private(set) var isAuthenticated = false
    private var presentationWindow: NSWindow?

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Constants.googleClientID)
        isAuthenticated = GIDSignIn.sharedInstance.currentUser != nil
    }

    var accessToken: String? {
        GIDSignIn.sharedInstance.currentUser?.accessToken.tokenString
    }

    var currentUserEmail: String? {
        GIDSignIn.sharedInstance.currentUser?.profile?.email
    }

    var hasCalendarAccess: Bool {
        hasCalendarScope(for: GIDSignIn.sharedInstance.currentUser)
    }

    func restorePreviousSignIn() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            isAuthenticated = hasCalendarScope(for: user)
        } catch {
            isAuthenticated = false
        }
    }

    func startSignIn(presentingWindow: NSWindow?) async throws {
        let createdPresentationWindow = presentingWindow == nil
        let window = presentingWindow ?? makePresentationWindow()

        if createdPresentationWindow {
            presentationWindow = window
        }

        defer {
            if createdPresentationWindow, presentationWindow === window {
                window.close()
                presentationWindow = nil
            }
        }

        let user: GIDGoogleUser
        if let currentUser = GIDSignIn.sharedInstance.currentUser, !hasCalendarScope(for: currentUser) {
            user = try await addCalendarScope(to: currentUser, presentingWindow: window)
        } else {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: currentUserEmail,
                additionalScopes: [Constants.googleCalendarReadonlyScope]
            )
            user = result.user
        }

        guard hasCalendarScope(for: user) else {
            isAuthenticated = false
            throw OAuthError.calendarPermissionNotGranted
        }

        isAuthenticated = true
    }

    func refreshTokenIfNeeded() async throws {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw OAuthError.notAuthenticated
        }

        let refreshedUser = try await user.refreshTokensIfNeeded()
        guard hasCalendarScope(for: refreshedUser) else {
            isAuthenticated = false
            throw OAuthError.calendarPermissionNotGranted
        }

        isAuthenticated = true
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isAuthenticated = false
    }

    private func makePresentationWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0.01
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func hasCalendarScope(for user: GIDGoogleUser?) -> Bool {
        user?.grantedScopes?.contains(Constants.googleCalendarReadonlyScope) == true
    }

    private func addCalendarScope(
        to user: GIDGoogleUser,
        presentingWindow: NSWindow
    ) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.addScopes([Constants.googleCalendarReadonlyScope], presenting: presentingWindow) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: OAuthError.calendarPermissionNotGranted)
                    return
                }

                continuation.resume(returning: result.user)
            }
        }
    }
}

enum OAuthError: LocalizedError {
    case notAuthenticated
    case canceled
    case calendarPermissionNotGranted
    case sdkError(message: String)

    init(from error: Error) {
        let nsError = error as NSError
        if nsError.domain == kGIDSignInErrorDomain, nsError.code == -5 {
            self = .canceled
        } else {
            self = .sdkError(message: nsError.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .canceled:
            return "Google sign-in was canceled."
        case .calendarPermissionNotGranted:
            return "Calendar access was not granted. Sign in again and keep Google Calendar enabled."
        case .sdkError(let message):
            return message
        }
    }
}
