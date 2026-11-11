import Foundation
import Security

/// Secret values, one generic-password item each in the login Keychain. This is the only place
/// a secret's value is stored. Calls can block (the Keychain may ask for the login password),
/// so run them off the main thread.
enum SecretStore {
    static let service = "com.omar.clipdock.saved"

    struct Failure: Error {
        let status: OSStatus
    }

    static func add(_ value: String, account: String) throws {
        var query = match(account)
        query[kSecAttrLabel] = "ClipDock saved secret"
        query[kSecValueData] = Data(value.utf8)
        try check(SecItemAdd(query as CFDictionary, nil))
    }

    static func update(_ value: String, account: String) throws {
        try check(SecItemUpdate(match(account) as CFDictionary, [kSecValueData: Data(value.utf8)] as CFDictionary))
    }

    static func read(account: String) throws -> String {
        var query = match(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Failure(status: errSecDecode)
        }
        return value
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(match(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func match(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure(status: status) }
    }
}
