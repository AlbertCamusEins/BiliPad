import SwiftUI

private enum ContentTab: Int, CaseIterable, Identifiable {
    case recommended, history, favorites
    var id: Int { rawValue }
    var title: String { switch self { case .recommended: "推荐"; case .history: "历史"; case .favorites: "收藏" } }
}

private enum FavoriteViewMode: String, CaseIterable, Identifiable {
    case icons, list
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var bindings: ControllerBindings
    @StateObject private var controller: ControllerManager
    @StateObject private var session = SessionStore()
    @State private var selectedTab: ContentTab = .recommended
    @State private var items: [VideoSummary] = []
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
    @State private var favoriteFolders: [FavoriteFolder] = []
    @State private var favoriteViewMode: FavoriteViewMode = .icons
    @State private var recommendedPage = 0
    @State private var favoriteFolderOpen: FavoriteFolder?
    @State private var settingsFocus = 0
    @State private var remapTarget: MappableControllerAction?

    init() {
        let bindings = ControllerBindings()
        _bindings = StateObject(wrappedValue: bindings)
        _controller = StateObject(wrappedValue: ControllerManager(bindings: bindings))
    }

    private var isBrowsingFavoriteFolders: Bool { selectedTab == .favorites && favoriteFolderOpen == nil }
    private var usesListLayout: Bool { selectedTab == .favorites && (favoriteFolderOpen != nil || favoriteViewMode == .list) }
    private var columns: [GridItem] { usesListLayout ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)] }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.055, green: 0.06, blue: 0.1), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            NavigationStack {
                contentBrowser
                    .navigationTitle("BiliPad")
                    .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { controllerStatus; accountButton; Button { showsSettings = true } label: { Image(systemName: "gearshape") } } }
                    .safeAreaInset(edge: .top, spacing: 0) { topTabs }
                    .overlay { emptyState }
            }
            if let detail { detailOverlay(detail) }
            if let playback { playerOverlay(playback) }
            if showsSettings { settingsOverlay }
            if let toast { toastView(toast) }
        }
        .preferredColorScheme(.dark)
        .task { await refreshProfile(); await loadCurrentTab() }
        .onChange(of: selectedTab) { _, _ in focusedIndex = 0; favoriteFolderOpen = nil; Task { await loadCurrentTab() } }
        .sheet(isPresented: $showsLogin, onDismiss: { Task { await refreshProfile(); await loadCurrentTab() } }) { LoginSheet(session: session) }
        .onReceive(controller.actions) { handle($0) }
    }

    private var contentBrowser: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    if isBrowsingFavoriteFolders {
                        ForEach(Array(favoriteFolders.enumerated()), id: \.element.id) { index, folder in
                            favoriteFolderCard(folder, focused: index == focusedIndex, list: favoriteViewMode == .list)
                                .id("folder-\(folder.id)")
                                .onTapGesture { focusedIndex = index; openFavoriteFolder(folder) }
                        }
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, video in
                            videoCard(video, focused: index == focusedIndex, list: usesListLayout)
                                .id(video.id)
                                .onTapGesture { focusedIndex = index; openDetail(video) }
                        }
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
            .refreshable { await loadCurrentTab() }
            .onChange(of: focusedIndex) { _, value in
                if isBrowsingFavoriteFolders, favoriteFolders.indices.contains(value) {
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("folder-\(favoriteFolders[value].id)", anchor: .center) }
                } else if items.indices.contains(value) {
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(items[value].id, anchor: .center) }
                }
            }
        }
    }

    private var topTabs: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("LB").font(.caption.monospaced()).foregroundStyle(.secondary)
                Picker("内容", selection: $selectedTab) {
                    ForEach(ContentTab.allCases) { tab in Text(tab.title).tag(tab) }
                }.pickerStyle(.segmented).frame(maxWidth: 520)
                Text("RB").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button { Task { await loadCurrentTab() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新")
            }
            if selectedTab == .favorites && !favoriteFolders.isEmpty {
                HStack {
                    if let folder = favoriteFolderOpen {
                        Button { closeFavoriteFolder() } label: { Label("返回收藏夹", systemImage: "chevron.left") }
                        Text(folder.title).font(.headline)
                    } else {
                        Text("我的收藏夹").font(.headline)
                    }
                    Spacer()
                    if favoriteFolderOpen == nil {
                        Picker("视图", selection: $favoriteViewMode) {
                            Image(systemName: "square.grid.2x2").tag(FavoriteViewMode.icons)
                            Image(systemName: "list.bullet").tag(FavoriteViewMode.list)
                        }.pickerStyle(.segmented).frame(width: 110)
                        Text("Y 切换").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: 760)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var emptyState: some View {
        if isLoading && items.isEmpty { ProgressView("正在载入\(selectedTab.title)…") }
        else if let error, items.isEmpty {
            ContentUnavailableView(selectedTab == .recommended ? "载入失败" : "暂无内容", systemImage: selectedTab == .recommended ? "wifi.exclamationmark" : "person.crop.circle.badge.exclamationmark", description: Text(error))
        }
    }

    private var controllerStatus: some View {
        HStack(spacing: 5) {
            Circle().fill(controller.isConnected ? .green : .orange).frame(width: 7, height: 7)
            Text(controller.isConnected ? controller.controllerName : "触屏").font(.caption2).lineLimit(1)
        }
    }

    private var accountButton: some View {
        Button { showsLogin = true } label: {
            if let avatarURL = session.avatarURL {
                AsyncImage(url: avatarURL) { image in image.resizable() } placeholder: { Image(systemName: "person.crop.circle") }
                    .frame(width: 28, height: 28).clipShape(Circle())
            } else { Image(systemName: "person.crop.circle") }
        }
    }

    @ViewBuilder private func videoCard(_ video: VideoSummary, focused: Bool, list: Bool) -> some View {
        if list {
            HStack(spacing: 14) {
                cover(video).frame(width: 220, height: 124)
                metadata(video)
                Spacer(minLength: 0)
            }.cardStyle(focused: focused)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                cover(video).aspectRatio(16.0 / 9.0, contentMode: .fit)
                metadata(video)
            }.cardStyle(focused: focused)
        }
    }

    @ViewBuilder private func favoriteFolderCard(_ folder: FavoriteFolder, focused: Bool, list: Bool) -> some View {
        if list {
            HStack(spacing: 16) {
                Image(systemName: "folder.fill").font(.system(size: 40)).foregroundStyle(.pink).frame(width: 72, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.title).font(.headline)
                    Text("\(folder.mediaCount ?? 0) 个视频").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.cardStyle(focused: focused)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(Color.pink.opacity(0.18)); Image(systemName: "folder.fill").font(.system(size: 54)).foregroundStyle(.pink) }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                Text(folder.title).font(.headline).lineLimit(1)
                Text("\(folder.mediaCount ?? 0) 个视频").font(.caption).foregroundStyle(.secondary)
            }.cardStyle(focused: focused)
        }
    }

    private func cover(_ video: VideoSummary) -> some View {
        GeometryReader { geometry in
            AsyncImage(url: secureURL(video.pic)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Rectangle().fill(.gray.opacity(0.22)).overlay { Image(systemName: "play.rectangle") } }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .overlay(alignment: .bottomTrailing) { Text(formatDuration(video.duration)).font(.caption2.monospacedDigit()).padding(5).background(.black.opacity(0.78), in: Capsule()).padding(6) }
        }.clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private func metadata(_ video: VideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(video.title).font(.headline).lineLimit(2)
            Text(video.owner.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let views = video.stat?.view { Label(formatCount(views), systemImage: "play.fill").font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailOverlay(_ value: VideoDetail) -> some View {
        ZStack {
            Color(red: 0.045, green: 0.047, blue: 0.065).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 22) {
                        coverImage(value.pic).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: 460).clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 12) {
                            Text(value.title).font(.title2.bold()).lineLimit(3)
                            HStack(spacing: 10) {
                                if let face = value.owner.face { coverImage(face).frame(width: 34, height: 34).clipShape(Circle()) }
                                Text(value.owner.name).font(.headline)
                            }
                            HStack(spacing: 18) {
                                if let views = value.stat?.view { Label(formatCount(views), systemImage: "play.fill") }
                                if let danmaku = value.stat?.danmaku { Label(formatCount(danmaku), systemImage: "text.bubble") }
                            }.font(.caption).foregroundStyle(.secondary)
                            Text(value.desc).font(.callout).foregroundStyle(.secondary).lineLimit(5)
                        }
                    }
                    HStack(spacing: 34) {
                        detailAction("点赞", "hand.thumbsup"); detailAction("投币", "bitcoinsign.circle"); detailAction("收藏", "star"); detailAction("分享", "square.and.arrow.up")
                    }.frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    Text(value.pages.count > 1 ? "分 P（\(value.pages.count)）" : "视频").font(.title3.bold())
                    ForEach(Array(value.pages.enumerated()), id: \.element.id) { index, page in
                        Button { selectedPage = index; play(value, page: page) } label: {
                            HStack {
                                Text("P\(page.page)").font(.caption.bold()).foregroundStyle(.pink)
                                Text(page.part).lineLimit(1)
                                Spacer()
                                Text(formatDuration(page.duration)).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "play.circle.fill").foregroundStyle(.pink)
                            }.padding(14).background(index == selectedPage ? Color.pink.opacity(0.23) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: 980).padding(26)
            }
        }.transition(.opacity)
    }

    private func detailAction(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 5) { Image(systemName: icon).font(.title3); Text(title).font(.caption) }.foregroundStyle(.secondary)
    }

    private func playerOverlay(_ request: PlaybackRequest) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(playerFullscreen ? 1 : 0.82).ignoresSafeArea()
                if playerFullscreen {
                    NativePlayerView(request: request, cookie: session.cookieHeader, command: playerCommand, commandID: playerCommandID)
                        .frame(width: geometry.size.width, height: geometry.size.height).ignoresSafeArea()
                } else {
                    let width = min(geometry.size.width - 48, 820)
                    VStack(spacing: 10) {
                        NativePlayerView(request: request, cookie: session.cookieHeader, command: playerCommand, commandID: playerCommandID)
                            .frame(width: width, height: width * 9.0 / 16.0).clipShape(RoundedRectangle(cornerRadius: 18))
                        Text("A 播放/暂停　B 返回　Y 全屏　↑↓ 音量　←→ 快退/快进").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.transition(.opacity)
    }

    private func toastView(_ text: String) -> some View {
        VStack { Spacer(); Text(text).padding(.horizontal, 16).padding(.vertical, 10).background(.black.opacity(0.88), in: Capsule()).padding(.bottom, 34) }.transition(.opacity).allowsHitTesting(false)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color(red: 0.035, green: 0.037, blue: 0.052).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("设置").font(.largeTitle.bold()); Spacer(); Text("A 选择　B 返回").foregroundStyle(.secondary) }
                        Text("账号与播放").font(.headline).foregroundStyle(.secondary).padding(.top, 8)
                        settingsRow(index: 0, title: session.isLoggedIn ? "重新登录" : "本机 App 一键登录", detail: session.userName, icon: "person.crop.circle")
                        settingsRow(index: 1, title: "关闭自动连播", detail: autoplayDisabled ? "开" : "关", icon: "play.slash")
                        settingsRow(index: 2, title: "退出本地登录", detail: session.isLoggedIn ? nil : "未登录", icon: "rectangle.portrait.and.arrow.right").opacity(session.isLoggedIn ? 1 : 0.45)
                        Text("手柄按键映射").font(.headline).foregroundStyle(.secondary).padding(.top, 10)
                        settingsRow(index: 3, title: "恢复默认按键", detail: nil, icon: "arrow.counterclockwise")
                        ForEach(Array(MappableControllerAction.allCases.enumerated()), id: \.element.id) { offset, action in
                            settingsRow(index: offset + 4, title: action.title, detail: bindings.button(for: action).title, icon: "gamecontroller")
                        }
                    }.frame(maxWidth: 820).padding(28)
                }
                .onChange(of: settingsFocus) { _, value in withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo("setting-\(value)", anchor: .center) } }
            }
            if let target = remapTarget {
                VStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 44)).foregroundStyle(.pink)
                    Text("请输入按键").font(.title2.bold())
                    Text("正在设置：\(target.title)\n如果按键已被占用，两项绑定会自动交换。")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }.padding(30).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22)).shadow(radius: 30)
            }
        }.transition(.opacity)
    }

    private func settingsRow(index: Int, title: String, detail: String?, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).frame(width: 26).foregroundStyle(index == settingsFocus ? .pink : .secondary)
            Text(title).font(.headline)
            Spacer()
            if let detail { Text(detail).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(index == settingsFocus ? Color.pink.opacity(0.22) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(index == settingsFocus ? Color.pink : .clear, lineWidth: 2) }
        .id("setting-\(index)")
        .onTapGesture { settingsFocus = index; activateSetting() }
    }

    private func handle(_ action: ControllerAction) {
        if showsLogin { handleLogin(action); return }
        if showsSettings { handleSettings(action); return }
        if playback != nil { handlePlayback(action); return }
        if let detail { handleDetail(action, detail: detail); return }
        let count = isBrowsingFavoriteFolders ? favoriteFolders.count : items.count
        let stride = usesListLayout ? 1 : 2
        switch action {
        case .previousTab: switchTab(-1)
        case .nextTab: switchTab(1)
        case .refresh: Task { await loadCurrentTab(); showToast("已刷新\(selectedTab.title)") }
        case .left: focusedIndex = max(0, focusedIndex - 1)
        case .right: focusedIndex = min(max(0, count - 1), focusedIndex + 1)
        case .up: focusedIndex = max(0, focusedIndex - stride)
        case .down: focusedIndex = min(max(0, count - 1), focusedIndex + stride)
        case .confirm:
            if isBrowsingFavoriteFolders, favoriteFolders.indices.contains(focusedIndex) { openFavoriteFolder(favoriteFolders[focusedIndex]) }
            else if items.indices.contains(focusedIndex) { openDetail(items[focusedIndex]) }
        case .back: if favoriteFolderOpen != nil { closeFavoriteFolder() }
        case .fullscreen:
            if isBrowsingFavoriteFolders { favoriteViewMode = favoriteViewMode == .icons ? .list : .icons; focusedIndex = min(focusedIndex, max(0, favoriteFolders.count - 1)); showToast(favoriteViewMode == .icons ? "图标视图" : "列表视图") }
        case .menu: settingsFocus = 0; showsSettings = true
        default: break
        }
    }

    private func handlePlayback(_ action: ControllerAction) {
        switch action {
        case .confirm: sendPlayer(.togglePlayback)
        case .back: if playerFullscreen { playerFullscreen = false } else { playback = nil }
        case .fullscreen: playerFullscreen.toggle(); showToast(playerFullscreen ? "全屏" : "窗口模式")
        case .disableAutoplay: autoplayDisabled.toggle(); showToast(autoplayDisabled ? "已关闭自动连播" : "已开启自动连播")
        case .up: sendPlayer(.volume(0.08)); showToast("音量 +")
        case .down: sendPlayer(.volume(-0.08)); showToast("音量 −")
        case .left: sendPlayer(.seek(-10)); showToast("快退 10 秒")
        case .right: sendPlayer(.seek(10)); showToast("快进 10 秒")
        case .danmaku: showToast("原生弹幕将在下一迭代接入")
        case .menu: settingsFocus = 0; showsSettings = true
        default: break
        }
    }

    private func handleSettings(_ action: ControllerAction) {
        switch action {
        case .up, .left: settingsFocus = max(0, settingsFocus - 1)
        case .down, .right: settingsFocus = min(12, settingsFocus + 1)
        case .confirm: activateSetting()
        case .back, .menu: controller.cancelCapture(); remapTarget = nil; showsSettings = false
        default: break
        }
    }

    private func activateSetting() {
        switch settingsFocus {
        case 0:
            showsSettings = false; showsLogin = true
        case 1:
            autoplayDisabled.toggle(); showToast(autoplayDisabled ? "已关闭自动连播" : "已开启自动连播")
        case 2:
            guard session.isLoggedIn else { showToast("当前未登录"); return }
            session.signOut(); selectedTab = .recommended; favoriteFolders = []; favoriteFolderOpen = nil; showToast("已退出本地登录")
        case 3:
            bindings.reset(); showToast("已恢复默认按键")
        case 4...12:
            let action = MappableControllerAction.allCases[settingsFocus - 4]
            remapTarget = action
            controller.captureNextButton { button in
                let conflict = bindings.assignments.first(where: { $0.value == button })?.key
                bindings.assign(button, to: action)
                remapTarget = nil
                if let conflict, conflict != action { showToast("已与“\(conflict.title)”交换按键") }
                else { showToast("已设置为 \(button.title)") }
            }
        default: break
        }
    }

    private func handleLogin(_ action: ControllerAction) {
        switch action {
        case .confirm: NotificationCenter.default.post(name: .controllerLoginConfirm, object: nil)
        case .back: showsLogin = false
        default: break
        }
    }

    private func handleDetail(_ action: ControllerAction, detail: VideoDetail) {
        switch action {
        case .up: selectedPage = max(0, selectedPage - 1)
        case .down: selectedPage = min(max(0, detail.pages.count - 1), selectedPage + 1)
        case .confirm: if detail.pages.indices.contains(selectedPage) { play(detail, page: detail.pages[selectedPage]) }
        case .back: self.detail = nil
        case .menu: settingsFocus = 0; showsSettings = true
        default: break
        }
    }

    private func switchTab(_ offset: Int) {
        let all = ContentTab.allCases
        selectedTab = all[(selectedTab.rawValue + offset + all.count) % all.count]
        showToast(selectedTab.title)
    }

    private func loadCurrentTab() async {
        isLoading = true; error = nil
        do {
            switch selectedTab {
            case .recommended:
                recommendedPage = recommendedPage % 10 + 1
                items = try await BiliAPIClient().popular(page: recommendedPage)
            case .history:
                try requireLogin(); items = try await BiliAPIClient().history(cookie: session.cookieHeader)
            case .favorites:
                try requireLogin()
                if let folder = favoriteFolderOpen {
                    items = try await BiliAPIClient().favorites(folderID: folder.id, cookie: session.cookieHeader)
                } else {
                    try await loadFavoriteFolders(); items = []
                }
            }
            focusedIndex = min(focusedIndex, max(0, items.count - 1))
        } catch { items = []; self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadFavoriteFolders() async throws {
        guard let userID = session.userID else { throw LocalError.loginRequired }
        favoriteFolders = try await BiliAPIClient().favoriteFolders(userID: userID, cookie: session.cookieHeader)
    }

    private func loadFavorites() async {
        isLoading = true; error = nil
        do { try await loadFavoritesThrowing() } catch { items = []; self.error = error.localizedDescription }
        isLoading = false
    }

    private func loadFavoritesThrowing() async throws {
        guard let folderID = favoriteFolderOpen?.id else { items = []; return }
        items = try await BiliAPIClient().favorites(folderID: folderID, cookie: session.cookieHeader)
    }

    private func openFavoriteFolder(_ folder: FavoriteFolder) {
        favoriteFolderOpen = folder; focusedIndex = 0
        Task { await loadFavorites() }
    }

    private func closeFavoriteFolder() { favoriteFolderOpen = nil; items = []; focusedIndex = 0 }

    private func requireLogin() throws { if !session.isLoggedIn { throw LocalError.loginRequired } }

    private func openDetail(_ video: VideoSummary) {
        Task {
            do { detail = try await BiliAPIClient().detail(bvid: video.bvid, cookie: session.cookieHeader); selectedPage = 0 }
            catch { showToast(error.localizedDescription) }
        }
    }

    private func play(_ detail: VideoDetail, page: VideoPage) { playback = PlaybackRequest(title: detail.title, bvid: detail.bvid, cid: page.cid); playerFullscreen = false }
    private func sendPlayer(_ command: PlayerCommand) { playerCommand = command; playerCommandID += 1 }

    private func showToast(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(1.4)); if toast == message { toast = nil } }
    }

    private func refreshProfile() async {
        guard !session.cookieHeader.isEmpty else { return }
        if let nav = try? await BiliAPIClient().navigation(cookie: session.cookieHeader) { session.updateProfile(nav) }
    }

    private func coverImage(_ value: String) -> some View {
        AsyncImage(url: secureURL(value)) { phase in if let image = phase.image { image.resizable().scaledToFill() } else { Rectangle().fill(.gray.opacity(0.2)) } }.clipped()
    }
    private func secureURL(_ value: String) -> URL? { URL(string: value.hasPrefix("http://") ? "https://" + value.dropFirst(7) : value) }
    private func formatDuration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private func formatCount(_ value: Int) -> String { value >= 10_000 ? String(format: "%.1f万", Double(value) / 10_000) : "\(value)" }
}

private extension View {
    func cardStyle(focused: Bool) -> some View {
        self.padding(9)
            .background(focused ? Color.pink.opacity(0.2) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(focused ? Color.pink : .clear, lineWidth: 3) }
            .scaleEffect(focused ? 1.012 : 1).animation(.easeOut(duration: 0.12), value: focused)
    }
}

private enum LocalError: LocalizedError {
    case loginRequired
    var errorDescription: String? { "请先登录后查看此标签" }
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
                    Text("确认后返回 BiliPad，本页会自动完成登录。若系统未跳转 App，可在下方移动版页面继续。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    MobileLoginWebView(url: url).clipShape(RoundedRectangle(cornerRadius: 12))
                } else if case .preparing = login.phase { ProgressView() }
                else { Button("重试") { Task { await login.begin(sessionStore: session) } } }
            }.padding().navigationTitle("登录 B 站").toolbar { Button("关闭") { dismiss() } }
            .task { await login.begin(sessionStore: session) }
            .onReceive(NotificationCenter.default.publisher(for: .controllerLoginConfirm)) { _ in
                if login.authorizationURL != nil { login.openBilibiliApp() }
                else { Task { await login.begin(sessionStore: session) } }
            }
            .onChange(of: login.phase) { _, phase in if phase == .confirmed { Task { try? await Task.sleep(for: .milliseconds(600)); dismiss() } } }
            .onDisappear { login.cancel() }
        }
    }
}

private extension Notification.Name {
    static let controllerLoginConfirm = Notification.Name("BiliPad.controllerLoginConfirm")
}

#Preview { ContentView() }
