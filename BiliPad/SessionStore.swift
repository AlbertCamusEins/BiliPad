import Foundation
import Security

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var cookies: [String: String] = [:]
    @Published private(set) var userName: String?
    @Published private(set) var avatarURL: URL?
    @Published private(set) var userID: Int64?

    private let service = "com.bilipad.session"
    private let account = "bilibili-cookies"
    private let allowedNames = Set(["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5", "sid"])

    init() {
        cookies = loadKeychain()
    }

    var isLoggedIn: Bool { userName != nil && cookies["SESSDATA"] != nil }

    var cookieHeader: String {
        cookies.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    var csrfToken: String? { cookies["bili_jct"] }

    func accept(_ source: [HTTPCookie]) {
        let accepted = source.filter {
            ($0.domain == "bilibili.com" || $0.domain.hasSuffix(".bilibili.com")) && allowedNames.contains($0.name)
        }
        guard !accepted.isEmpty else { return }
        for cookie in accepted { cookies[cookie.name] = cookie.value }
        saveKeychain(cookies)
    }

    func updateProfile(_ nav: NavData) {
        userName = nav.isLogin ? nav.uname : nil
        avatarURL = nav.isLogin ? nav.face.flatMap(URL.init(string:)) : nil
        userID = nav.isLogin ? nav.mid : nil
    }

    func signOut() {
        cookies = [:]
        userName = nil
        avatarURL = nil
        userID = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func saveKeychain(_ value: [String: String]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func loadKeychain() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return stored.filter { allowedNames.contains($0.key) }
    }
}
