import AppKit
@preconcurrency import AppAuth
import Foundation

@MainActor
final class GoogleOAuthService {
    private static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private static let storedEmailKey = "googleOAuthEmail"

    private let credentialStore = OAuthCredentialStore()
    private var authState: OIDAuthState?
    private var redirectHTTPHandler: OIDRedirectHTTPHandler?
    private var presentationWindow: NSWindow?

    private(set) var isAuthenticated = false
    private(set) var currentUserEmail: String?

    init() {
        currentUserEmail = UserDefaults.standard.string(forKey: Self.storedEmailKey)
    }

    var accessToken: String? {
        authState?.lastTokenResponse?.accessToken
    }

    var hasCalendarAccess: Bool {
        guard let scope = authState?.scope else { return false }
        return scope
            .split(whereSeparator: \.isWhitespace)
            .contains(Substring(Constants.googleCalendarReadonlyScope))
    }

    private var hasOfflineAccess: Bool {
        guard let refreshToken = authState?.refreshToken else { return false }
        return !refreshToken.isEmpty
    }

    func restorePreviousSignIn() async {
        do {
            guard let restoredState = try credentialStore.load() else {
                AppLogger.info("oauth.restore", "No stored OAuth session found")
                clearSession(reason: "no stored OAuth session")
                return
            }

            authState = restoredState
            AppLogger.info("oauth.restore", "Loaded OAuth session \(stateSummary(restoredState))")

            guard hasOfflineAccess else {
                AppLogger.error(
                    "oauth.restore",
                    "Stored OAuth session cannot be renewed \(stateSummary(restoredState))"
                )
                clearSession(reason: "stored OAuth session has no refresh token")
                return
            }

            if currentUserEmail == nil {
                currentUserEmail = emailAddress(from: restoredState)
            }
            isAuthenticated = restoredState.isAuthorized && hasCalendarAccess
            AppLogger.info(
                "oauth.restore",
                "OAuth session restoration completed authenticated=\(isAuthenticated)"
            )
        } catch {
            let summary = AppLogger.errorSummary(error)
            AppLogger.error("oauth.restore", "OAuth session restoration failed \(summary)")
            clearSession(reason: "credential restoration failed \(summary)")
        }
    }

    func startSignIn(presentingWindow: NSWindow?) async throws {
        AppLogger.info("oauth.signin", "Starting Google authorization flow")

        let createdPresentationWindow = presentingWindow == nil
        let window = presentingWindow ?? makePresentationWindow()

        if createdPresentationWindow {
            presentationWindow = window
        }

        defer {
            stopRedirectListener()
            if createdPresentationWindow, presentationWindow === window {
                window.close()
                presentationWindow = nil
            }
        }

        let handler = OIDRedirectHTTPHandler(successURL: nil)
        var listenerError: NSError?
        let redirectURL = handler.startHTTPListener(&listenerError)
        if let listenerError {
            AppLogger.error(
                "oauth.signin",
                "Could not start OAuth redirect listener \(AppLogger.errorSummary(listenerError))"
            )
            throw OAuthError.sdkError(
                message: listenerError.localizedDescription
            )
        }

        redirectHTTPHandler = handler

        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: Self.authorizationEndpoint,
            tokenEndpoint: Self.tokenEndpoint
        )
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: Constants.googleClientID,
            clientSecret: nil,
            scopes: [OIDScopeOpenID, OIDScopeEmail, Constants.googleCalendarReadonlyScope],
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: [
                "access_type": "offline",
                // Google normally issues a refresh token only on the first grant.
                // Force consent so reconnecting replaces a missing or invalid token.
                "prompt": "consent",
            ]
        )

        let signedInState: OIDAuthState
        do {
            signedInState = try await withCheckedThrowingContinuation { continuation in
                let flow = OIDAuthState.authState(
                    byPresenting: request,
                    presenting: window
                ) { state, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let state else {
                        continuation.resume(
                            throwing: OAuthError.sdkError(message: "Google returned no authorization session.")
                        )
                        return
                    }

                    continuation.resume(returning: state)
                }
                handler.currentAuthorizationFlow = flow
            }
        } catch {
            AppLogger.error(
                "oauth.signin",
                "Google authorization flow failed \(AppLogger.errorSummary(error))"
            )
            throw error
        }

        authState = signedInState
        currentUserEmail = emailAddress(from: signedInState)
        AppLogger.info("oauth.signin", "Google authorization returned \(stateSummary(signedInState))")

        guard hasCalendarAccess else {
            isAuthenticated = false
            AppLogger.error("oauth.signin", "Google authorization did not grant Calendar scope")
            throw OAuthError.calendarPermissionNotGranted
        }
        guard hasOfflineAccess else {
            AppLogger.error(
                "oauth.signin",
                "Google authorization did not return a refresh token \(stateSummary(signedInState))"
            )
            clearSession(reason: "authorization returned no refresh token")
            throw OAuthError.offlineAccessNotGranted
        }

        do {
            try credentialStore.save(signedInState)
            AppLogger.info("oauth.keychain", "Saved renewable OAuth session")
        } catch {
            let summary = AppLogger.errorSummary(error)
            AppLogger.error("oauth.keychain", "Could not save OAuth session \(summary)")
            clearSession(reason: "credential save failed \(summary)")
            throw OAuthError.sdkError(message: "The Google session couldn't be saved in Keychain: \(error.localizedDescription)")
        }

        UserDefaults.standard.set(currentUserEmail, forKey: Self.storedEmailKey)
        isAuthenticated = true
        AppLogger.info("oauth.signin", "Google Calendar connection established")
    }

    func refreshTokenIfNeeded() async throws {
        guard let authState else {
            AppLogger.error("oauth.refresh", "Refresh requested without an OAuth session")
            throw OAuthError.notAuthenticated
        }
        guard hasCalendarAccess else {
            isAuthenticated = false
            AppLogger.error(
                "oauth.refresh",
                "OAuth session is missing Calendar scope \(stateSummary(authState))"
            )
            throw OAuthError.calendarPermissionNotGranted
        }
        guard hasOfflineAccess else {
            AppLogger.error(
                "oauth.refresh",
                "OAuth session cannot be renewed \(stateSummary(authState))"
            )
            clearSession(reason: "refresh requested without a refresh token")
            throw OAuthError.offlineAccessNotGranted
        }

        let previousAccessToken = authState.lastTokenResponse?.accessToken
        let token: String
        do {
            token = try await withCheckedThrowingContinuation { continuation in
                authState.performAction { accessToken, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let accessToken else {
                        continuation.resume(throwing: OAuthError.notAuthenticated)
                        return
                    }

                    continuation.resume(returning: accessToken)
                }
            }
        } catch {
            let summary = AppLogger.errorSummary(error)
            AppLogger.error(
                "oauth.refresh",
                "Access-token refresh failed \(summary) \(stateSummary(authState))"
            )

            if requiresReauthentication(after: error, authState: authState) {
                let detail = (error as NSError).localizedDescription
                clearSession(reason: "permanent access-token refresh failure \(summary)")
                throw OAuthError.sessionExpired(message: detail)
            }

            throw error
        }

        guard !token.isEmpty else {
            AppLogger.error("oauth.refresh", "AppAuth returned an empty access token")
            throw OAuthError.notAuthenticated
        }

        do {
            try credentialStore.save(authState)
        } catch {
            AppLogger.error(
                "oauth.keychain",
                "Could not save refreshed OAuth session \(AppLogger.errorSummary(error))"
            )
            throw OAuthError.sdkError(message: "The refreshed Google session couldn't be saved: \(error.localizedDescription)")
        }

        isAuthenticated = authState.isAuthorized
        if previousAccessToken != authState.lastTokenResponse?.accessToken {
            AppLogger.info(
                "oauth.refresh",
                "Access token refreshed and renewable OAuth session saved \(stateSummary(authState))"
            )
        }
    }

    func signOut(reason: String = "user disconnected Google Calendar") {
        stopRedirectListener()
        clearSession(reason: reason)
    }

    private func stopRedirectListener() {
        redirectHTTPHandler?.currentAuthorizationFlow = nil
        redirectHTTPHandler?.cancelHTTPListener()
        redirectHTTPHandler = nil
    }

    private func clearSession(reason: String) {
        AppLogger.info("oauth.session", "Clearing OAuth session reason=\(reason)")

        do {
            try credentialStore.delete()
            AppLogger.info("oauth.keychain", "Deleted stored OAuth session")
        } catch {
            AppLogger.error(
                "oauth.keychain",
                "Could not delete stored OAuth session \(AppLogger.errorSummary(error))"
            )
        }

        authState = nil
        isAuthenticated = false
        currentUserEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.storedEmailKey)
    }

    private func requiresReauthentication(after error: Error, authState: OIDAuthState) -> Bool {
        let nsError = error as NSError

        return !authState.isAuthorized ||
            nsError.domain == OIDOAuthTokenErrorDomain ||
            (nsError.domain == OIDGeneralErrorDomain &&
             nsError.code == OIDErrorCode.tokenRefreshError.rawValue)
    }

    private func emailAddress(from authState: OIDAuthState) -> String? {
        guard let idTokenString = authState.lastTokenResponse?.idToken,
              let idToken = OIDIDToken(idTokenString: idTokenString) else {
            return nil
        }

        return idToken.claims["email"] as? String
    }

    private func stateSummary(_ authState: OIDAuthState) -> String {
        let calendarScopeGranted = authState.scope?
            .split(whereSeparator: \.isWhitespace)
            .contains(Substring(Constants.googleCalendarReadonlyScope)) == true
        let refreshTokenPresent = authState.refreshToken?.isEmpty == false
        let accessTokenPresent = authState.lastTokenResponse?.accessToken?.isEmpty == false
        let expiration = authState.lastTokenResponse?.accessTokenExpirationDate
            .map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"

        return "authorized=\(authState.isAuthorized) calendarScope=\(calendarScopeGranted) " +
            "refreshTokenPresent=\(refreshTokenPresent) accessTokenPresent=\(accessTokenPresent) " +
            "accessTokenExpiresAt=\(expiration)"
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
}

enum OAuthError: LocalizedError {
    case notAuthenticated
    case canceled
    case calendarPermissionNotGranted
    case offlineAccessNotGranted
    case sessionExpired(message: String)
    case sdkError(message: String)

    init(from error: Error) {
        if let oauthError = error as? OAuthError {
            self = oauthError
            return
        }

        let nsError = error as NSError
        if nsError.domain == OIDGeneralErrorDomain &&
            (nsError.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue ||
             nsError.code == OIDErrorCode.programCanceledAuthorizationFlow.rawValue) {
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
        case .offlineAccessNotGranted:
            return "Google did not provide renewable Calendar access. Connect again to keep alerts running."
        case .sessionExpired:
            return "Your Google Calendar connection expired. Connect again to resume alerts."
        case .sdkError(let message):
            return message
        }
    }
}
