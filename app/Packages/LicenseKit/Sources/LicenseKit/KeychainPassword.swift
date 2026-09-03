import Foundation
import Security

/// Session-cached generic-password access that never surfaces the macOS Keychain UI.
enum KeychainPassword {
    enum ReadResult: Sendable {
        case missing
        case value(Data)
        case inaccessible(OSStatus)
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: ReadResult] = [:]

    private static func cacheKey(service: String, account: String) -> String {
        "\(service)\u{1E}\(account)"
    }

    static func readData(service: String, account: String) -> ReadResult {
        let key = cacheKey(service: service, account: account)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        let result: ReadResult = switch status {
        case errSecSuccess:
            (item as? Data).map { .value($0) } ?? .inaccessible(status)
        case errSecItemNotFound:
            .missing
        default:
            .inaccessible(status)
        }

        lock.lock()
        cache[key] = result
        lock.unlock()
        return result
    }

    @discardableResult
    static func addData(_ data: Data, service: String, account: String) -> OSStatus {
        invalidate(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            lock.lock()
            cache[cacheKey(service: service, account: account)] = .value(data)
            lock.unlock()
        }
        return status
    }

    @discardableResult
    static func delete(service: String, account: String) -> OSStatus {
        invalidate(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }

    static func invalidate(service: String, account: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let account {
            cache.removeValue(forKey: cacheKey(service: service, account: account))
        } else {
            let prefix = "\(service)\u{1E}"
            for key in cache.keys where key.hasPrefix(prefix) {
                cache.removeValue(forKey: key)
            }
        }
    }
}
