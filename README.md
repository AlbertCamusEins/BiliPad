# BiliPad

BiliPad 是一个自用、横屏、手柄优先的 iOS B 站网页外壳。它使用 B 站正常网页完成登录、权限判断和播放，只增加原生手柄输入、二维焦点导航和少量横屏样式。

当前里程碑是 **V0.1.1 播放控制与登录可用性**。项目不读取或导出 Cookie，不解析视频流，不使用 B 站私有 API，也不改变账号在网页端拥有的任何内容权限。

## V0.1.1 已实现

- SwiftUI + `WKWebView` 横屏应用
- `WKWebsiteDataStore.default()` 持久化网页登录数据
- B 站顶层导航白名单，外部网页交给系统浏览器
- Xbox 风格扩展手柄输入，支持 D-pad 和左摇杆
- 摇杆死区、首次触发延迟和连续导航节流
- A 确认、B 返回、Menu 打开设置
- X 开关弹幕、Y 发送播放器 `F` 全屏快捷键、Option 关闭自动连播
- B 在 iOS 原生视频全屏时优先退出全屏
- 设置中的 B 站官方网页登录入口，登录页使用移动显示模式
- 忽略正常的 WebKit 导航取消错误（`NSURLErrorDomain -999`）
- 原创占位 App 图标
- 基于元素几何位置的二维焦点导航
- SPA/懒加载页面的防抖重新扫描
- 基础滚动位置和焦点恢复
- 对可见 `<video>` 执行播放/暂停和前后 10 秒
- 可见错误提示以及触屏降级
- macOS GitHub Actions 无签名构建和 IPA artifact

## 目录

```text
BiliPad/
├── project.yml
├── BiliPad/
│   ├── BiliPadApp.swift
│   ├── ContentView.swift
│   ├── ControllerManager.swift
│   ├── WebBridge.swift
│   ├── WebViewContainer.swift
│   ├── Info.plist
│   └── Resources/
│       ├── controller-bridge.js
│       ├── focus-navigation.js
│       └── bilipad.css
├── Tests/
├── .github/workflows/build-ios.yml
└── AGENTS.md
```

## Windows 开发与检查

Windows 没有 Apple iOS SDK，不能在本地编译这个应用，但可以修改全部源码并测试 Web 层。需要 Node.js 20 或更高版本：

```powershell
npm run check
npm test
```

项目文件由 XcodeGen 在 macOS/CI 上生成，因此不要在 Windows 上手工创建或编辑 `project.pbxproj`。

## macOS 构建

安装 XcodeGen 后：

```bash
xcodegen generate
xcodebuild \
  -project BiliPad.xcodeproj \
  -scheme BiliPad \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

模拟器名称应按本机实际可用设备修改。手柄识别、登录持久化和真实视频播放仍必须在 iPhone 上验证。

## GitHub Actions 与 IPA

推送到 GitHub 后，`Build iOS` 工作流会：

1. 检查和测试注入 JavaScript；
2. 在固定的 macOS runner 上记录 Xcode/Swift 版本；
3. 使用 XcodeGen 生成工程；
4. 执行无签名 iPhoneOS Release 构建；
5. 验证 App、可执行文件及三个注入资源；
6. 包装 `Payload/BiliPad.app`，上传未签名 IPA、SHA-256 和精简构建证据。

CI artifact 中的 `BiliPad-unsigned.ipa` **尚未签名，不能直接安装**。SideStore 会使用用户自己的 Apple 账号在安装时重签。项目仓库和 CI 不需要、也不应保存 Apple ID、证书或 provisioning profile。

## SideStore 安装

1. 按 SideStore 官方文档在 iPhone 上完成首次安装和设备配置。
2. 从 GitHub Actions 下载并解压 `BiliPad-unsigned-<commit>` artifact。
3. 在 SideStore 中选择 `BiliPad-unsigned.ipa` 安装。
4. 按 SideStore 要求定期刷新签名。

## 手柄映射

| 输入 | 浏览页面 | 检测到可见视频时 |
| --- | --- | --- |
| D-pad / 左摇杆 | 移动焦点 | 上下仍移动焦点；左右跳转 10 秒 |
| A | 激活焦点 | 播放/暂停 |
| B | 关闭可见弹层或返回 | 退出 iOS 视频全屏/关闭弹层/返回 |
| X | 无操作 | 开关弹幕 |
| Y | 无操作 | 发送 `F` 全屏快捷键 |
| Option | 无操作 | 关闭自动连播 |
| Menu | 打开原生设置 | 打开原生设置 |

部分 8BitDo 手柄有多种配对模式，必须使用能被 iOS 识别为标准扩展手柄的模式。

## 必须进行的真机验收

- iPhone 上的 B 站首页、登录、验证码和新窗口流程
- 杀掉 App 后登录状态仍在
- MCON、Xbox 或 8BitDo 至少一款手柄被系统和 App 正确识别
- 首页连续导航 30 次不跳项、不丢焦
- A 打开视频；播放页 A、左右和 B 正常工作
- 返回后焦点和滚动位置可接受
- 手柄断开后网页触屏操作正常
- SideStore 能成功重签并安装 CI 生成的 IPA

网页结构、风控和播放器实现都可能变化。出现问题时先保留失败页面和操作步骤；不要提交 Cookie、账号凭据或完整个人页面 HTML。
