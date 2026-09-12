import Foundation

struct BiliAPIClient: Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    func popular(page: Int = 1) async throws -> [VideoSummary] {
        let value: PopularData = try await get("/x/web-interface/popular", query: ["pn": "\(page)", "ps": "24"])
        return value.list
    }

    func detail(bvid: String, cookie: String) async throws -> VideoDetail {
        try await get("/x/web-interface/view", query: ["bvid": bvid], cookie: cookie)
    }

    func playURL(bvid: String, cid: Int64, cookie: String) async throws -> URL {
        let value: PlayURLData = try await get("/x/player/playurl", query: [
            "bvid": bvid, "cid": "\(cid)", "qn": "64", "fnval": "0", "fnver": "0", "fourk": "0", "platform": "html5"
        ], cookie: cookie)
        let candidate = value.durl?.first.flatMap { [$0.url] + ($0.backupURL ?? []) }.first(where: { URL(string: $0) != nil })
        guard let candidate, let url = URL(string: candidate) else { throw BiliError.noPlayableStream }
        return url
    }

    func navigation(cookie: String) async throws -> NavData {
        try await get("/x/web-interface/nav", cookie: cookie)
    }

    private func get<Value: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        cookie: String = ""
    ) async throws -> Value {
        var components = URLComponents(string: "https://api.bilibili.com\(path)")!
        components.queryItems = query.map(URLQueryItem.init(name:value:))
        guard let url = components.url else { throw BiliError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BiliError.invalidResponse }
        let envelope = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data)
        guard envelope.code == 0, let value = envelope.data else {
            throw BiliError.api(envelope.code, envelope.message ?? "未知错误")
        }
        return value
    }
}
