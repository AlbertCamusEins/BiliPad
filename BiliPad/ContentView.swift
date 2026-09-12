import SwiftUI

struct ContentView: View {
    @StateObject private var controller = ControllerManager()
    @StateObject private var session = SessionStore()
    @State private var videos: [VideoSummary] = []
    @State private var focusedIndex = 0
    @State private var isLoading = true
    @State private var error: String?
    @State private var detail: VideoDetail?
    @State private var selectedPage = 0
    @State private var playback: PlaybackRequest?
    @State private var playerFullscreen = false
    @State private var playerCommand: PlayerCommand?
    @State private var playerCommandID = 0
    @State private var showsLogin = false
    @State private var showsSettings = false
    @State private var autoplayDisabled = false
    @State private var toast: String?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.11), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            NavigationStack {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            videoCard(video, focused: index == focusedIndex)
                                .onTapGesture { focusedIndex = index; openDetail(video) }
                        }
                    }.padding()
                }
                .navigationTitle("BiliPad")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        controllerStatus
                        Button { showsLogin = true } label: {
                            if let avatarURL = session.avatarURL {
                                AsyncImage(url: avatarURL) { image in image.resizable() } placeholder: { Image(systemName: "person.crop.circle") }
                                    .frame(width: 28, height: 28).clipShape(Circle())
                            } else { Image(systemName: "person.crop.circle") }
                        }
                        Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
                .overlay { emptyState }
                .refreshable { await loadPopular() }
            }
            if let detail { detailOverlay(detail) }
            if let playback { playerOverlay(playback) }
            if let toast { toastView(toast) }
        }
        .preferredColorScheme(.dark)
        .task { await loadPopular(); await refreshProfile() }
        .sheet(isPresented: $showsLogin, onDismiss: { Task { await refreshProfile() } }) { LoginSheet(session: session) }
        .sheet(isPresented: $showsSettings) { settings }
        .onReceive(controller.actions) { handle($0) }
    }

    @ViewBuilder private var emptyState: some View {
        if isLoading && videos.isEmpty { ProgressView("正在载入热门视频…") }
        else if let error, videos.isEmpty { ContentUnavailableView("载入失败", systemImage: "wifi.exclamationmark", description: Text(error)) }
    }

    private var controllerStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(controller.isConnected ? .green : .orange).frame(width: 7, height: 7)
            Text(controller.isConnected ? controller.controllerName : "触屏").font(.caption2).lineLimit(1)
        }
    }

    private func videoCard(_ video: VideoSummary, focused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: secureURL(video.pic)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Rectangle().fill(.gray.opacity(0.25)).overlay { Image(systemName: "play.rectangle") } }
            }
            .aspectRatio(16 / 10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Text(formatDuration(video.duration)).font(.caption2.monospacedDigit()).padding(5).background(.black.opacity(0.75), in: Capsule()).padding(6)
            }
            Text(video.title).font(.headline).lineLimit(2)
            Text(video.owner.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .background(focused ? Color.pink.opacity(0.2) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(focused ? Color.pink : .clear, lineWidth: 3) }
        .scaleEffect(focused ? 1.015 : 1).animation(.easeOut(duration: 0.12), value: focused)
    }

    private func detailOverlay(_ value: VideoDetail) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 18) {
                        AsyncImage(url: secureURL(value.pic)) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.gray.opacity(0.3)) }
                            .aspectRatio(16 / 10, contentMode: .fit).frame(maxWidth: 420).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(value.title).font(.title2.bold())
                            Text(value.owner.name).foregroundStyle(.secondary)
                            Text(value.desc).font(.callout).lineLimit(6)
                        }
                    }
                    Text("选集").font(.headline)
                    ForEach(Array(value.pages.enumerated()), id: \.element.id) { index, item in
                        Button { selectedPage = index; play(value, page: item) } label: {
                            HStack {
                                Text("P\(item.page)  \(item.part)").lineLimit(1)
                                Spacer()
                                Text(formatDuration(item.duration)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(12).background(index == selectedPage ? Color.pink.opacity(0.28) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(24)
            }
        }.transition(.opacity)
    }

    private func playerOverlay(_ request: PlaybackRequest) -> some View {
        ZStack {
            Color.black.opacity(playerFullscreen ? 1 : 0.72).ignoresSafeArea()
            VStack(spacing: 8) {
                if !playerFullscreen { Spacer() }
                NativePlayerView(request: request, cookie: session.cookieHeader, command: playerCommand, commandID: playerCommandID)
                    .aspectRatio(playerFullscreen ? nil : CGFloat(16.0 / 9.0), contentMode: .fit)
                    .frame(maxWidth: playerFullscreen ? .infinity : 760, maxHeight: playerFullscreen ? .infinity : 430)
                    .clipShape(RoundedRectangle(cornerRadius: playerFullscreen ? 0 : 18))
                if !playerFullscreen {
                    Text("A 播放/暂停　B 返回　Y 全屏　方向键调节").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }.transition(.opacity)
    }

    private func toastView(_ text: String) -> some View {
        VStack { Spacer(); Text(text).padding(.horizontal, 16).padding(.vertical, 10).background(.black.opacity(0.85), in: Capsule()).padding(.bottom, 36) }
            .transition(.opacity).allowsHitTesting(false)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    if let name = session.userName { LabeledContent("已登录", value: name) }
                    Button(session.isLoggedIn ? "重新登录" : "本机 App 一键登录") { showsSettings = false; showsLogin = true }
                    if session.isLoggedIn { Button("退出本地登录", role: .destructive) { session.signOut() } }
                }
                Section("播放") { Toggle("关闭自动连播", isOn: $autoplayDisabled) }
                Section("当前版本") { Text("原生热门列表、详情、分P、播放与本机 App 登录。搜索、收藏和原生弹幕将在后续版本接入。") }
            }
            .navigationTitle("设置")
            .toolbar { Button("完成") { showsSettings = false } }
        }
    }

    private func handle(_ action: ControllerAction) {
        if playback != nil {
            switch action {
            case .confirm: sendPlayer(.togglePlayback)
            case .back: if playerFullscreen { playerFullscreen = false } else { playback = nil }
            case .fullscreen: playerFullscreen.toggle(); showToast(playerFullscreen ? "全屏" : "窗口模式")
            case .disableAutoplay: autoplayDisabled.toggle(); showToast(autoplayDisabled ? "已关闭自动连播" : "已开启自动连播")
            case .up: sendPlayer(.volume(0.08)); showToast("音量 +")
            case .down: sendPlayer(.volume(-0.08)); showToast("音量 −")
            case .left: sendPlayer(.seek(-10))
            case .right: sendPlayer(.seek(10))
            case .danmaku: showToast("原生弹幕将在下一迭代接入")
            case .menu: showsSettings = true
            }
            return
        }
        if let detail {
            switch action {
            case .up: selectedPage = max(0, selectedPage - 1)
            case .down: selectedPage = min(max(0, detail.pages.count - 1), selectedPage + 1)
            case .confirm: if detail.pages.indices.contains(selectedPage) { play(detail, page: detail.pages[selectedPage]) }
            case .back: self.detail = nil
            case .menu: showsSettings = true
            default: break
            }
            return
        }
        switch action {
        case .left: focusedIndex = max(0, focusedIndex - 1)
        case .right: focusedIndex = min(max(0, videos.count - 1), focusedIndex + 1)
        case .up: focusedIndex = max(0, focusedIndex - 2)
        case .down: focusedIndex = min(max(0, videos.count - 1), focusedIndex + 2)
        case .confirm: if videos.indices.contains(focusedIndex) { openDetail(videos[focusedIndex]) }
        case .menu: showsSettings = true
        default: break
        }
    }

    private func openDetail(_ video: VideoSummary) {
        Task {
            do { detail = try await BiliAPIClient().detail(bvid: video.bvid, cookie: session.cookieHeader); selectedPage = 0 }
            catch { self.error = error.localizedDescription }
        }
    }

    private func play(_ detail: VideoDetail, page: VideoPage) {
        playback = PlaybackRequest(title: detail.title, bvid: detail.bvid, cid: page.cid)
        playerFullscreen = false
    }

    private func sendPlayer(_ command: PlayerCommand) { playerCommand = command; playerCommandID += 1 }

    private func showToast(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(1.4)); if toast == message { toast = nil } }
    }

    private func loadPopular() async {
        isLoading = true
        do { videos = try await BiliAPIClient().popular(); focusedIndex = min(focusedIndex, max(0, videos.count - 1)); error = nil }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func refreshProfile() async {
        guard !session.cookieHeader.isEmpty else { return }
        if let nav = try? await BiliAPIClient().navigation(cookie: session.cookieHeader) { session.updateProfile(nav) }
    }

    private func secureURL(_ value: String) -> URL? { URL(string: value.hasPrefix("http://") ? "https://" + value.dropFirst(7) : value) }
    private func formatDuration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

private struct LoginSheet: View {
    @ObservedObject var session: SessionStore
    @StateObject private var login = LoginManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(login.phase.text).font(.headline).multilineTextAlignment(.center)
                if let url = login.authorizationURL {
                    Button("打开哔哩哔哩 App 授权") { login.openBilibiliApp() }.buttonStyle(.borderedProminent).tint(.pink)
                    Text("确认后返回 BiliPad，本页会自动完成登录。若系统未跳转 App，可在下方移动版页面继续。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    MobileLoginWebView(url: url).clipShape(RoundedRectangle(cornerRadius: 12))
                } else if case .preparing = login.phase { ProgressView() }
                else { Button("重试") { Task { await login.begin(sessionStore: session) } } }
            }
            .padding().navigationTitle("登录 B 站")
            .toolbar { Button("关闭") { dismiss() } }
            .task { await login.begin(sessionStore: session) }
            .onChange(of: login.phase) { _, phase in
                if phase == .confirmed { Task { try? await Task.sleep(for: .milliseconds(600)); dismiss() } }
            }
            .onDisappear { login.cancel() }
        }
    }
}

#Preview { ContentView() }
