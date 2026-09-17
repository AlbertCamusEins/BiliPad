import CryptoKit
import Foundation

struct BiliAPIClient: Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private static let apiUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    func recommended(refreshIndex: Int, cookie: String) async throws -> [VideoSummary] {
        let nav = try await navigation(cookie: cookie)
        guard let wbiImage = nav.wbiImg else { throw BiliError.missingWBIKey }
        let query = try signedWBIQuery([
            "fresh_type": "4", "version": "1", "ps": "14",
            "fresh_idx": "\(refreshIndex)", "fresh_idx_1h": "\(refreshIndex)",
            "web_location": "1430650"
        ], imageURL: wbiImage.imgURL, subURL: wbiImage.subURL)
        let value: RecommendedData = try await get("/x/web-interface/wbi/index/top/feed/rcmd", query: query, cookie: cookie)
        return value.item
    }

    func detail(bvid: String, cookie: String) async throws -> VideoDetail {
        try await get("/x/web-interface/view", query: ["bvid": bvid], cookie: cookie)
    }

    func playURLs(bvid: String, cid: Int64, cookie: String) async throws -> [URL] {
        var lastError: Error = BiliError.noPlayableStream
        for quality in ["64", "32", "16"] {
            do {
                let value: PlayURLData = try await get("/x/player/playurl", query: [
                    "bvid": bvid, "cid": "\(cid)", "qn": quality, "fnval": "1",
                    "fnver": "0", "fourk": "0", "platform": "html5", "high_quality": "1"
                ], cookie: cookie, referer: "https://www.bilibili.com/video/\(bvid)")
                let urls = (value.durl ?? []).compactMap { segment in
                    ([segment.url] + (segment.backupURL ?? [])).compactMap(URL.init(string:)).first
                }
                if !urls.isEmpty { return urls }
            } catch { lastError = error }
        }
        throw lastError
    }

    func navigation(cookie: String) async throws -> NavData {
        try await get("/x/web-interface/nav", cookie: cookie)
    }

    func history(cookie: String) async throws -> [VideoSummary] {
        let value: HistoryData = try await get("/x/web-interface/history/cursor", query: ["max": "0", "view_at": "0", "business": "archive", "ps": "30"], cookie: cookie)
        return value.list.compactMap(\.video)
    }

    func reportPlayback(aid: Int64, cid: Int64, progress: Int, cookie: String, csrf: String) async throws {
        try await post(
            "/x/v2/history/report",
            form: [
                "aid": "\(aid)",
                "cid": "\(cid)",
                "progress": "\(max(1, progress))",
                "csrf": csrf
            ],
            cookie: cookie
        )
    }

    func favoriteFolders(userID: Int64, cookie: String, resourceID: Int64? = nil) async throws -> [FavoriteFolder] {
        var query = ["up_mid": "\(userID)"]
        if let resourceID { query["rid"] = "\(resourceID)"; query["type"] = "2" }
        let value: FavoriteFolderData = try await get("/x/v3/fav/folder/created/list-all", query: query, cookie: cookie)
        guard resourceID == nil else { return value.list }
        return await withTaskGroup(of: (Int, FavoriteFolder?).self) { group in
            for (index, folder) in value.list.enumerated() {
                group.addTask {
                    let info: FavoriteFolder? = try? await get("/x/v3/fav/folder/info", query: ["media_id": "\(folder.id)"], cookie: cookie)
                    return (index, info)
                }
            }
            var folders = value.list
            for await (index, info) in group {
                if let info { folders[index] = info }
            }
            return folders
        }
    }

    func favorites(folderID: Int64, cookie: String) async throws -> [VideoSummary] {
        let value: FavoriteMediaData = try await get("/x/v3/fav/resource/list", query: ["media_id": "\(folderID)", "pn": "1", "ps": "20", "platform": "web"], cookie: cookie)
        return (value.medias ?? []).compactMap(\.video)
    }

    func search(_ keyword: String, cookie: String) async throws -> [VideoSummary] {
        let nav = try await navigation(cookie: cookie)
        guard let wbiImage = nav.wbiImg else { throw BiliError.missingWBIKey }
        let query = try signedWBIQuery([
            "search_type": "video", "keyword": keyword, "page": "1", "order": "totalrank"
        ], imageURL: wbiImage.imgURL, subURL: wbiImage.subURL)
        let value: SearchData = try await get("/x/web-interface/wbi/search/type", query: query, cookie: cookie, referer: "https://search.bilibili.com/")
        return value.result.map(\.video)
    }

    func related(bvid: String, cookie: String) async throws -> [VideoSummary] {
        let value: [VideoSummary] = try await get("/x/web-interface/archive/related", query: ["bvid": bvid], cookie: cookie)
        return value
    }

    func replies(aid: Int64, cookie: String) async throws -> [VideoReply] {
        let value: ReplyData = try await get("/x/v2/reply", query: ["type": "1", "oid": "\(aid)", "pn": "1", "ps": "20", "sort": "2"], cookie: cookie)
        return value.replies ?? []
    }

    func isLiked(aid: Int64, cookie: String) async throws -> Bool {
        let value: Int = try await get("/x/web-interface/archive/has/like", query: ["aid": "\(aid)"], cookie: cookie)
        return value == 1
    }

    func isFavorited(aid: Int64, cookie: String) async throws -> Bool {
        let value: FavoriteStatusData = try await get("/x/v2/fav/video/favoured", query: ["aid": "\(aid)"], cookie: cookie)
        return value.favoured
    }

    func setLike(bvid: String, liked: Bool, cookie: String, csrf: String) async throws {
        try await post(
            "/x/web-interface/archive/like",
            form: ["bvid": bvid, "like": liked ? "1" : "2", "csrf": csrf],
            cookie: cookie,
            referer: "https://www.bilibili.com/video/\(bvid)"
        )
    }

    func triple(bvid: String, cookie: String, csrf: String) async throws {
        try await post("/x/web-interface/archive/like/triple", form: ["bvid": bvid, "csrf": csrf, "csrf_token": csrf], cookie: cookie)
    }

    func coin(bvid: String, cookie: String, csrf: String) async throws {
        try await post("/x/web-interface/coin/add", form: ["bvid": bvid, "multiply": "1", "select_like": "0", "csrf": csrf, "csrf_token": csrf], cookie: cookie)
    }

    func setFavorite(aid: Int64, folderIDs: [Int64], favorited: Bool, cookie: String, csrf: String) async throws {
        let folderKey = favorited ? "add_media_ids" : "del_media_ids"
        try await post("/x/v3/fav/resource/deal", form: ["rid": "\(aid)", "type": "2", folderKey: folderIDs.map(String.init).joined(separator: ","), "csrf": csrf, "csrf_token": csrf], cookie: cookie)
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
        request.setValue(Self.apiUserAgent, forHTTPHeaderField: "User-Agent")
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

    private func post(_ path: String, form: [String: String], cookie: String, referer: String = "https://www.bilibili.com/") async throws {
        var request = URLRequest(url: URL(string: "https://api.bilibili.com\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Self.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        var components = URLComponents(); components.queryItems = form.map(URLQueryItem.init(name:value:))
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BiliError.invalidResponse }
        let status = try JSONDecoder().decode(APIStatus.self, from: data)
        guard status.code == 0 else { throw BiliError.api(status.code, status.message ?? "操作失败") }
    }

    private func signedWBIQuery(_ input: [String: String], imageURL: String, subURL: String) throws -> [String: String] {
        let imageKey = URL(string: imageURL)?.deletingPathExtension().lastPathComponent ?? ""
        let subKey = URL(string: subURL)?.deletingPathExtension().lastPathComponent ?? ""
        let source = Array(imageKey + subKey)
        let order = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11]
        guard source.count >= 64 else { throw BiliError.missingWBIKey }
        let mixinKey = String(order.prefix(32).map { source[$0] })
        var signed = input
        signed["wts"] = String(Int(Date().timeIntervalSince1970))
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let canonical = signed.keys.sorted().map { key in
            let value = signed[key, default: ""].filter { !"!'()*".contains($0) }
            return "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        signed["w_rid"] = Insecure.MD5.hash(data: Data((canonical + mixinKey).utf8)).map { String(format: "%02x", $0) }.joined()
        return signed
    }
}

private struct APIStatus: Decodable { let code: Int; let message: String? }
