import Foundation
import UIKit

@MainActor
final class LoginManager: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case waiting
        case confirmed
        case failed(String)

        var text: String {
            switch self {
            case .idle: "准备登录"
            case .preparing: "正在创建安全登录会话…"
            case .waiting: "请在哔哩哔哩 App 中确认登录"
            case .confirmed: "登录成功"
            case let .failed(message): message
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var authorizationURL: URL?

    private var key: String?
    private var pollTask: Task<Void, Never>?
    private let cookieStorage = HTTPCookieStorage.shared
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }()

    func begin(sessionStore: SessionStore) async {
        pollTask?.cancel()
        phase = .preparing
        do {
            var request = URLRequest(url: URL(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/generate")!)
            request.setValue(BiliAPIClient.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: request)
            let envelope = try JSONDecoder().decode(APIEnvelope<QRCodeData>.self, from: data)
            guard envelope.code == 0, let value = envelope.data, let url = URL(string: value.url) else {
                throw BiliError.api(envelope.code, envelope.message ?? "无法创建登录会话")
            }
            key = value.qrcodeKey
            authorizationURL = url
            phase = .waiting
            pollTask = Task { [weak self, weak sessionStore] in
                await self?.poll(sessionStore: sessionStore)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func openBilibiliApp() {
        guard let authorizationURL else { return }
        UIApplication.shared.open(authorizationURL, options: [.universalLinksOnly: true]) { opened in
            if !opened { UIApplication.shared.open(authorizationURL) }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll(sessionStore: SessionStore?) async {
        guard let key else { return }
        do {
            for _ in 0..<90 {
                try Task.checkCancellation()
                var components = URLComponents(string: "https://passport.bilibili.com/x/passport-login/web/qrcode/poll")!
                components.queryItems = [URLQueryItem(name: "qrcode_key", value: key)]
                var request = URLRequest(url: components.url!)
                request.setValue(BiliAPIClient.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, _) = try await session.data(for: request)
                let envelope = try JSONDecoder().decode(APIEnvelope<QRCodePollData>.self, from: data)
                if let value = envelope.data, value.code == 0 {
                    sessionStore?.accept(cookieStorage.cookies ?? [])
                    if let store = sessionStore {
                        let nav = try await BiliAPIClient().navigation(cookie: store.cookieHeader)
                        store.updateProfile(nav)
                    }
                    phase = .confirmed
                    return
                }
                if envelope.data?.code == 86038 { throw LoginError.expired }
                try await Task.sleep(for: .seconds(2))
            }
            throw LoginError.expired
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct QRCodeData: Decodable, Sendable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }
}

private struct QRCodePollData: Decodable, Sendable {
    let code: Int
}

private enum LoginError: LocalizedError {
    case expired
    var errorDescription: String? { "登录会话已过期，请重试" }
}
