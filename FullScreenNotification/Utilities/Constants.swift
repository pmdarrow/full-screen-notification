import Foundation

enum Constants {
    // MARK: - Google OAuth

    static let googleClientID: String = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as! String
    static let oauthRedirectScheme: String = Bundle.main.object(forInfoDictionaryKey: "GIDRedirectScheme") as! String
    static let googleCalendarReadonlyScope = "https://www.googleapis.com/auth/calendar.readonly"
}
