import Foundation
import Security

struct NativeCredential: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let token: String
    let expiresAt: Date
    let origin: String
    var description: String { "NativeCredential(redacted)" }
    var debugDescription: String { description }
}
protocol NativeTokenStore: Sendable {
    func load() throws -> NativeCredential?
    func save(_ credential: NativeCredential) throws
    func clear() throws
}
protocol KeychainClient: Sendable {
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}
struct SystemKeychainClient: KeychainClient {
    func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus { SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// Token-only storage, inaccessible while locked, no iCloud sync or migration to another device.
/// The service must be unique to the approved origin. Never write passwords here.
struct KeychainNativeTokenStore: NativeTokenStore {
    let service: String
    let client: any KeychainClient
    init(service: String, client: any KeychainClient = SystemKeychainClient()) { self.service = service; self.client = client }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "native-staff-session",
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> NativeCredential? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = client.copy(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw NativeAPIError.secureStorage }
        do { return try JSONDecoder().decode(NativeCredential.self, from: data) }
        catch { try clear(); throw NativeAPIError.secureStorage }
    }
    func save(_ credential: NativeCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = client.update(query, attributes: attributes)
        if status == errSecItemNotFound {
            guard client.add(query.merging(attributes) { _, new in new }) == errSecSuccess else { throw NativeAPIError.secureStorage }
        } else if status != errSecSuccess { throw NativeAPIError.secureStorage }
    }
    func clear() throws {
        let status = client.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NativeAPIError.secureStorage }
    }
}
