import SwiftUI

struct ContentView: View {
    @StateObject private var controller = ControllerManager()
    @StateObject private var webModel = WebViewModel()

    @State private var showsSettings = false
    @State private var confirmsDataRemoval = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebViewContainer(model: webModel)
                .ignoresSafeArea()

            statusPill
                .padding(12)

            if let error = webModel.visibleError {
                errorBanner(error)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            settingsView
        }
        .onReceive(controller.actions) { action in
            if action == .menu {
                showsSettings = true
            } else {
                webModel.send(action)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(controller.isConnected ? controller.controllerName : "触屏模式")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.68), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { showsSettings = true }
        .accessibilityLabel(controller.isConnected ? "手柄已连接" : "未连接手柄")
    }

    private func errorBanner(_ error: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Text(error)
                    .font(.footnote)
                    .lineLimit(2)
                Button("关闭") {
                    webModel.visibleError = nil
                }
            }
            .padding(12)
            .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section("网页") {
                    Button("返回") {
                        webModel.goBack()
                        showsSettings = false
                    }
                    Button("重新载入") {
                        webModel.reload()
                        showsSettings = false
                    }
                }

                Section("隐私") {
                    Button("清除网页登录数据", role: .destructive) {
                        confirmsDataRemoval = true
                    }
                } footer: {
                    Text("会清除 B 站登录状态、Cookie、缓存和本地网页数据。")
                }
            }
            .navigationTitle("BiliPad 设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsSettings = false }
                }
            }
            .confirmationDialog(
                "确定清除全部网页登录数据？",
                isPresented: $confirmsDataRemoval,
                titleVisibility: .visible
            ) {
                Button("清除并退出登录", role: .destructive) {
                    webModel.clearWebsiteData()
                    showsSettings = false
                }
            } message: {
                Text("此操作无法撤销。")
            }
        }
    }
}

#Preview {
    ContentView()
}
