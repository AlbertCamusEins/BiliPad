import Foundation

struct APIEnvelope<Value: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: Value?
}

struct VideoOwner: Decodable, Hashable, Sendable {
    let name: String
    let face: String?
}

struct VideoStat: Decodable, Hashable, Sendable {
    let view: Int?
    let danmaku: Int?
}

struct VideoSummary: Decodable, Identifiable, Hashable, Sendable {
    let bvid: String
    let title: String
    let pic: String
    let duration: Int
    let owner: VideoOwner
    let stat: VideoStat?

    var id: String { bvid }
}

extension VideoSummary {
    init(bvid: String, title: String, pic: String, duration: Int, ownerName: String, ownerFace: String? = nil, view: Int? = nil, danmaku: Int? = nil) {
        self.init(bvid: bvid, title: title, pic: pic, duration: duration, owner: VideoOwner(name: ownerName, face: ownerFace), stat: VideoStat(view: view, danmaku: danmaku))
    }
}

struct RecommendedData: Decodable, Sendable {
    let item: [VideoSummary]
}

struct VideoPage: Decodable, Identifiable, Hashable, Sendable {
    let cid: Int64
    let page: Int
    let part: String
    let duration: Int

    var id: Int64 { cid }
}

struct VideoDetail: Decodable, Identifiable, Sendable {
    let aid: Int64
    let bvid: String
    let title: String
    let pic: String
    let desc: String
    let owner: VideoOwner
    let pages: [VideoPage]
    let stat: VideoStat?

    var id: String { bvid }
}

struct PlayURLData: Decodable, Sendable {
    let durl: [PlaySegment]?
}

struct SearchData: Decodable, Sendable {
    let result: [SearchVideo]

    private enum CodingKeys: String, CodingKey { case result }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decodeIfPresent([LossySearchVideo].self, forKey: .result)?.compactMap(\.value) ?? []
    }
}

private struct LossySearchVideo: Decodable, Sendable {
    let value: SearchVideo?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(SearchVideo.self)
    }
}

struct SearchVideo: Decodable, Sendable {
    let bvid: String
    let title: String
    let pic: String
    let duration: String?
    let author: String
    let play: Int?

    private enum CodingKeys: String, CodingKey { case bvid, title, pic, duration, author, play }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try container.decode(String.self, forKey: .bvid)
        title = try container.decode(String.self, forKey: .title)
        pic = try container.decode(String.self, forKey: .pic)
        author = try container.decode(String.self, forKey: .author)
        duration = (try? container.decode(String.self, forKey: .duration))
            ?? (try? container.decode(Int.self, forKey: .duration)).map { String($0) }
        play = (try? container.decode(Int.self, forKey: .play))
            ?? (try? container.decode(String.self, forKey: .play)).flatMap { Int($0) }
    }
    var video: VideoSummary {
        VideoSummary(bvid: bvid, title: title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression), pic: pic.hasPrefix("//") ? "https:\(pic)" : pic, duration: Self.seconds(duration), ownerName: author, view: play)
    }
    private static func seconds(_ value: String?) -> Int {
        let parts = (value ?? "0").split(separator: ":").compactMap { Int($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

struct ReplyData: Decodable, Sendable { let replies: [VideoReply]? }
struct VideoReply: Decodable, Identifiable, Sendable {
    let rpid: Int64
    let member: ReplyMember
    let content: ReplyContent
    let like: Int?
    var id: Int64 { rpid }
}
struct ReplyMember: Decodable, Sendable { let uname: String; let avatar: String? }
struct ReplyContent: Decodable, Sendable { let message: String }

struct FavoriteStatusData: Decodable, Sendable { let favoured: Bool }

struct PlaySegment: Decodable, Sendable {
    let url: String
    let backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case backupURL = "backup_url"
    }
}

struct NavData: Decodable, Sendable {
    let isLogin: Bool
    let uname: String?
    let face: String?
    let mid: Int64?
    let wbiImg: WBIImage?

    enum CodingKeys: String, CodingKey {
        case isLogin = "isLogin"
        case uname, face, mid
        case wbiImg = "wbi_img"
    }
}

struct WBIImage: Decodable, Sendable {
    let imgURL: String
    let subURL: String

    enum CodingKeys: String, CodingKey {
        case imgURL = "img_url"
        case subURL = "sub_url"
    }
}

struct HistoryData: Decodable, Sendable {
    let list: [HistoryEntry]
}

struct HistoryEntry: Decodable, Sendable {
    let title: String
    let cover: String
    let duration: Int
    let authorName: String
    let authorFace: String?
    let progress: Int?
    let history: HistoryIdentity

    enum CodingKeys: String, CodingKey {
        case title, cover, duration, progress, history
        case authorName = "author_name"
        case authorFace = "author_face"
    }

    var video: VideoSummary? {
        guard let bvid = history.bvid, !bvid.isEmpty else { return nil }
        return VideoSummary(bvid: bvid, title: title, pic: cover, duration: duration, ownerName: authorName, ownerFace: authorFace)
    }
}

struct HistoryIdentity: Decodable, Sendable {
    let bvid: String?
    let cid: Int64?
}

struct FavoriteFolderData: Decodable, Sendable {
    let list: [FavoriteFolder]
}

struct FavoriteFolder: Decodable, Identifiable, Hashable, Sendable {
    let id: Int64
    let title: String
    let cover: String?
    let mediaCount: Int?
    let favState: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, cover
        case mediaCount = "media_count"
        case favState = "fav_state"
    }
}

struct FavoriteMediaData: Decodable, Sendable {
    let medias: [FavoriteMedia]?
}

struct FavoriteMedia: Decodable, Sendable {
    let bvid: String?
    let title: String
    let cover: String
    let duration: Int
    let upper: FavoriteUpper
    let countInfo: FavoriteCountInfo?

    enum CodingKeys: String, CodingKey {
        case bvid, title, cover, duration, upper
        case countInfo = "cnt_info"
    }

    var video: VideoSummary? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoSummary(bvid: bvid, title: title, pic: cover, duration: duration, ownerName: upper.name, ownerFace: upper.face, view: countInfo?.play, danmaku: countInfo?.danmaku)
    }
}

struct FavoriteUpper: Decodable, Sendable {
    let name: String
    let face: String?
}

struct FavoriteCountInfo: Decodable, Sendable {
    let play: Int?
    let danmaku: Int?
}

struct PlaybackRequest: Identifiable, Sendable {
    let title: String
    let bvid: String
    let cid: Int64
    var id: String { "\(bvid)-\(cid)" }
}

enum BiliError: LocalizedError {
    case invalidResponse
    case api(Int, String)
    case noPlayableStream
    case missingWBIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "B 站返回了无法识别的数据"
        case let .api(code, message): "B 站接口错误 \(code)：\(message)"
        case .noPlayableStream: "未找到可直接播放的视频流"
        case .missingWBIKey: "无法获取个性化推荐所需的动态签名"
        }
    }
}
