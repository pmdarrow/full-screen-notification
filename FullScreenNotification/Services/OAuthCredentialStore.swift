@preconcurrency import AppAuth
import Foundation
import Security

struct OAuthCredentialStore {
    private let service = "com.fullscreennotification.google-oauth"
    private let account = "Google OAuth session"

    func load() throws -> OIDAuthState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.keychain(status)
        }

        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
        } catch {
            throw CredentialStoreError.decode(error)
        }
    }

    func save(_ authState: OIDAuthState) throws {
        let data: Data
        do {
            data = try NSKeyedArchiver.archivedData(
                withRootObject: authState,
                requiringSecureCoding: true
            )
        } catch {
            throw CredentialStoreError.encode(error)
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var newItem = baseQuery
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // GoogleSignIn 9 defaults to the entitlement-gated Data Protection Keychain.
            // This app intentionally uses the classic login Keychain so ad-hoc distributions work.
            kSecUseDataProtectionKeychain as String: false,
        ]
    }
}

private enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case encode(Error)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "\(message) (\(status))"
        case .encode(let error):
            return "Could not encode the OAuth session: \(error.localizedDescription)"
        case .decode(let error):
            return "Could not decode the OAuth session: \(error.localizedDescription)"
        }
    }
}
