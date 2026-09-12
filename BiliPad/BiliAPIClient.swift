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

    func playURLs(bvid: String, cid: Int64, cookie: String) async throws -> [URL] {
        let value: PlayURLData = try await get("/x/player/playurl", query: [
            "bvid": bvid, "cid": "\(cid)", "qn": "64", "fnval": "0", "fnver": "0", "fourk": "0", "platform": "html5"
        ], cookie: cookie)
        let urls = (value.durl ?? []).compactMap { segment in
            ([segment.url] + (segment.backupURL ?? [])).compactMap(URL.init(string:)).first
        }
        guard !urls.isEmpty else { throw BiliError.noPlayableStream }
        return urls
    }

    func navigation(cookie: String) async throws -> NavData {
        try await get("/x/web-interface/nav", cookie: cookie)
    }

    func history(cookie: String) async throws -> [VideoSummary] {
        let value: HistoryData = try await get("/x/web-interface/history/cursor", query: ["max": "0", "view_at": "0", "business": "archive", "ps": "30"], cookie: cookie)
        return value.list.compactMap(\.video)
    }

    func favoriteFolders(userID: Int64, cookie: String) async throws -> [FavoriteFolder] {
        let value: FavoriteFolderData = try await get("/x/v3/fav/folder/created/list-all", query: ["up_mid": "\(userID)"], cookie: cookie)
        return value.list
    }

    func favorites(folderID: Int64, cookie: String) async throws -> [VideoSummary] {
        let value: FavoriteMediaData = try await get("/x/v3/fav/resource/list", query: ["media_id": "\(folderID)", "pn": "1", "ps": "20", "platform": "web"], cookie: cookie)
        return (value.medias ?? []).compactMap(\.video)
    }

    func search(_ keyword: String, cookie: String) async throws -> [VideoSummary] {
        let value: SearchData = try await get("/x/web-interface/search/type", query: ["search_type": "video", "keyword": keyword, "page": "1", "order": "totalrank"], cookie: cookie, referer: "https://search.bilibili.com/")
        return (value.result ?? []).map(\.video)
    }

    func related(bvid: String, cookie: String) async throws -> [VideoSummary] {
        let value: [VideoSummary] = try await get("/x/web-interface/archive/related", query: ["bvid": bvid], cookie: cookie)
        return value
    }

    func replies(aid: Int64, cookie: String) async throws -> [VideoReply] {
        let value: ReplyData = try await get("/x/v2/reply", query: ["type": "1", "oid": "\(aid)", "pn": "1", "ps": "20", "sort": "2"], cookie: cookie)
        return value.replies ?? []
    }

    func like(bvid: String, cookie: String, csrf: String) async throws {
        try await post("/x/web-interface/archive/like", form: ["bvid": bvid, "like": "1", "csrf": csrf], cookie: cookie)
    }

    func triple(bvid: String, cookie: String, csrf: String) async throws {
        try await post("/x/web-interface/archive/like/triple", form: ["bvid": bvid, "csrf": csrf], cookie: cookie)
    }

    func coin(bvid: String, cookie: String, csrf: String) async throws {
        try await post("/x/web-interface/coin/add", form: ["bvid": bvid, "multiply": "1", "select_like": "0", "csrf": csrf], cookie: cookie)
    }

    func favorite(aid: Int64, folderID: Int64, cookie: String, csrf: String) async throws {
        try await post("/x/v3/fav/resource/deal", form: ["rid": "\(aid)", "type": "2", "add_media_ids": "\(folderID)", "csrf": csrf], cookie: cookie)
    }

    private func get<Value: Decodable & Sendable>(
        _ path: String,
        query: [String: String] = [:],
        cookie: String = "",
        referer: String = "https://www.bilibili.com/"
    ) async throws -> Value {
        var components = URLComponents(string: "https://api.bilibili.com\(path)")!
        components.queryItems = query.map(URLQueryItem.init(name:value:))
        guard let url = components.url else { throw BiliError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BiliError.invalidResponse }
        let envelope = try JSONDecoder().decode(APIEnvelope<Value>.self, from: data)
        guard envelope.code == 0, let value = envelope.data else {
            throw BiliError.api(envelope.code, envelope.message ?? "未知错误")
        }
        return value
    }

    private func post(_ path: String, form: [String: String], cookie: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.bilibili.com\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        var components = URLComponents(); components.queryItems = form.map(URLQueryItem.init(name:value:))
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BiliError.invalidResponse }
        let status = try JSONDecoder().decode(APIStatus.self, from: data)
        guard status.code == 0 else { throw BiliError.api(status.code, status.message ?? "操作失败") }
    }
}

private struct APIStatus: Decodable { let code: Int; let message: String? }
