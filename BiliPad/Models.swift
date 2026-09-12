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

struct PopularData: Decodable, Sendable {
    let list: [VideoSummary]
}

struct VideoPage: Decodable, Identifiable, Hashable, Sendable {
    let cid: Int64
    let page: Int
    let part: String
    let duration: Int

    var id: Int64 { cid }
}

struct VideoDetail: Decodable, Identifiable, Sendable {
    let bvid: String
    let title: String
    let pic: String
    let desc: String
    let owner: VideoOwner
    let pages: [VideoPage]

    var id: String { bvid }
}

struct PlayURLData: Decodable, Sendable {
    let durl: [PlaySegment]?
}

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

    enum CodingKeys: String, CodingKey {
        case isLogin = "isLogin"
        case uname, face
    }
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "B 站返回了无法识别的数据"
        case let .api(code, message): "B 站接口错误 \(code)：\(message)"
        case .noPlayableStream: "未找到可直接播放的视频流"
        }
    }
}
