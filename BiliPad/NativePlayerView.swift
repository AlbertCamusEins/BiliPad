import AVFoundation
import SwiftUI
import UIKit

enum PlayerCommand: Equatable {
    case togglePlayback
    case toggleChrome
    case volume(Float)
    case seek(Double)
}

@MainActor
final class NativePlayerViewModel: ObservableObject {
    let player = AVQueuePlayer()
    @Published private(set) var isPlaying = false
    @Published private(set) var volume: Float = 1
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?
    @Published private(set) var danmaku: [DanmakuItem] = []
    @Published private(set) var currentTime: Double = 0
    private(set) var finalItem: AVPlayerItem?
    private var loadedRequestID: String?
    private var timeObserver: Any?

    init() {
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
                self?.isPlaying = self?.player.timeControlStatus == .playing
            }
        }
    }

    func load(_ request: PlaybackRequest, cookie: String) async {
        guard loadedRequestID != request.id else { return }
        loadedRequestID = request.id
        isLoading = true
        currentTime = 0
        error = nil
        do {
            async let streamRequest = BiliAPIClient().playURLs(bvid: request.bvid, cid: request.cid, cookie: cookie)
            async let danmakuRequest = DanmakuService().load(cid: request.cid)
            let urls = try await streamRequest
            let headers = ["User-Agent": BiliAPIClient.userAgent, "Referer": "https://www.bilibili.com/video/\(request.bvid)", "Cookie": cookie]
            let playerItems = urls.map { AVPlayerItem(asset: AVURLAsset(url: $0, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])) }
            finalItem = playerItems.last
            player.removeAllItems()
            for item in playerItems { player.insert(item, after: nil) }
            danmaku = (try? await danmakuRequest) ?? []
            player.volume = volume
            player.play()
            isPlaying = true
        } catch {
            loadedRequestID = nil
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func perform(_ command: PlayerCommand) {
        switch command {
        case .togglePlayback:
            if player.timeControlStatus == .playing { player.pause(); isPlaying = false }
            else { player.play(); isPlaying = true }
        case .toggleChrome:
            break
        case let .volume(delta):
            volume = min(1, max(0, volume + delta)); player.volume = volume
        case let .seek(offset):
            let current = player.currentTime().seconds
            guard current.isFinite else { return }
            player.seek(to: CMTime(seconds: max(0, current + offset), preferredTimescale: 600))
        }
    }

    func reset() {
        player.pause(); player.removeAllItems(); loadedRequestID = nil; finalItem = nil
        currentTime = 0; isPlaying = false; danmaku = []
    }
}

struct NativePlayerView: View {
    let request: PlaybackRequest
    let cookie: String
    let command: PlayerCommand?
    let commandID: Int
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onPlaybackStarted: () -> Void
    let onEnded: () -> Void
    @ObservedObject var model: NativePlayerViewModel
    @State private var showsChrome = true
    @State private var chromeActivityID = UUID()

    var body: some View {
        ZStack {
            Color.black
            PlayerCanvas(player: model.player).allowsHitTesting(false)
            if danmakuEnabled { DanmakuOverlay(currentTime: model.currentTime, items: model.danmaku) }

            if showsChrome {
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                VStack {
                    HStack {
                        Text(request.title).font(.headline).lineLimit(1)
                        Spacer()
                        Button {
                            onToggleDanmaku()
                            revealChrome()
                        } label: {
                            Label(danmakuEnabled ? "弹幕开" : "弹幕关", systemImage: danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.45), in: Capsule())
                        Image(systemName: "gamecontroller.fill")
                    }.padding()
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        HStack(spacing: 12) {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            ProgressView(value: progress)
                            Text(timeText).font(.caption.monospacedDigit())
                            Image(systemName: volumeSymbol)
                        }.padding()
                    }
                }
            }

            if model.isLoading { ProgressView("正在载入视频…") }
            TimelineView(.periodic(from: .now, by: 0.7)) { _ in
                if model.player.timeControlStatus == .waitingToPlayAtSpecifiedRate && !model.isLoading {
                    VStack { ProgressView(); Text("正在加载，\(speedText)").font(.caption.monospacedDigit()) }
                        .padding(12).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let error = model.error {
                VStack(spacing: 10) { Image(systemName: "exclamationmark.triangle").font(.largeTitle); Text(error).multilineTextAlignment(.center) }
                    .padding(24).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleChrome() }
        .task(id: request.id) {
            await model.load(request, cookie: cookie)
            revealChrome()
        }
        .task(id: chromeActivityID) {
            guard showsChrome, model.isPlaying else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, model.isPlaying else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsChrome = false }
        }
        .onChange(of: commandID) { _, _ in
            guard let command else { return }
            if command == .toggleChrome { toggleChrome() }
            else { model.perform(command); revealChrome() }
        }
        .onChange(of: model.isPlaying) { _, playing in
            if playing { revealChrome() }
            else {
                chromeActivityID = UUID()
                withAnimation(.easeOut(duration: 0.16)) { showsChrome = true }
            }
        }
        .onChange(of: model.currentTime) { _, currentTime in
            if currentTime >= 0.5 { onPlaybackStarted() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let ended = notification.object as? AVPlayerItem, ended === model.finalItem else { return }
            onEnded()
        }
    }

    private var progress: Double {
        let duration = model.player.currentItem?.duration.seconds ?? 0
        let current = model.player.currentTime().seconds
        guard duration.isFinite, duration > 0, current.isFinite else { return 0 }
        return min(1, max(0, current / duration))
    }

    private var timeText: String {
        let current = model.player.currentTime().seconds
        let duration = model.player.currentItem?.duration.seconds ?? 0
        return "\(format(current)) / \(format(duration))"
    }

    private var volumeSymbol: String {
        model.volume == 0 ? "speaker.slash.fill" : (model.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
    }

    private var speedText: String {
        let bits = model.player.currentItem?.accessLog()?.events.last?.observedBitrate ?? 0
        guard bits > 0 else { return "0 KB/s" }
        return String(format: "%.0f KB/s", bits / 8 / 1024)
    }

    private func revealChrome() {
        withAnimation(.easeOut(duration: 0.16)) { showsChrome = true }
        chromeActivityID = UUID()
    }

    private func toggleChrome() {
        if showsChrome {
            chromeActivityID = UUID()
            withAnimation(.easeOut(duration: 0.16)) { showsChrome = false }
        } else {
            revealChrome()
        }
    }

    private func format(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PlayerCanvas: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) { view.player = player }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspect }
    }
}
