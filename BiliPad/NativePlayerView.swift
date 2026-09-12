import AVKit
import SwiftUI

enum PlayerCommand: Equatable {
    case togglePlayback
    case volume(Float)
    case seek(Double)
}

@MainActor
final class NativePlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var error: String?
    @Published var isLoading = true

    func load(_ request: PlaybackRequest, cookie: String) async {
        isLoading = true
        do {
            let url = try await BiliAPIClient().playURL(bvid: request.bvid, cid: request.cid, cookie: cookie)
            let headers = ["Referer": "https://www.bilibili.com/", "User-Agent": BiliAPIClient.userAgent, "Cookie": cookie]
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            player.play()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func execute(_ command: PlayerCommand) {
        switch command {
        case .togglePlayback:
            player.timeControlStatus == .playing ? player.pause() : player.play()
        case let .volume(delta):
            player.volume = min(1, max(0, player.volume + delta))
        case let .seek(delta):
            let current = player.currentTime().seconds
            guard current.isFinite else { return }
            player.seek(to: CMTime(seconds: max(0, current + delta), preferredTimescale: 600))
        }
    }
}

struct NativePlayerView: View {
    let request: PlaybackRequest
    let cookie: String
    let command: PlayerCommand?
    let commandID: Int
    @StateObject private var model = NativePlayerModel()

    var body: some View {
        ZStack {
            Color.black
            VideoPlayer(player: model.player)
            if model.isLoading { ProgressView("正在获取播放地址…") }
            if let error = model.error {
                ContentUnavailableView("播放失败", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .task(id: request.id) { await model.load(request, cookie: cookie) }
        .onChange(of: commandID) { _, _ in
            if let command { model.execute(command) }
        }
        .onDisappear { model.player.pause() }
    }
}
