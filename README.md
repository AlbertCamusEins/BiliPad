# BiliPad

BiliPad 是一个面向 iPhone 和手柄操作的实验性原生 B 站客户端。V0.2 已把网页套壳从主流程移除，内容列表、详情、分 P 与播放均使用 SwiftUI/AVPlayer；WebKit 只存在于登录授权页。

## V0.2 功能

- 原生热门视频双列列表、详情和分 P 选择
- 原生 AVPlayer 播放普通 HTML5 视频流
- 同机登录：创建 B 站网页授权会话，打开本机哔哩哔哩 App 确认，并自动建立 Cookie 会话
- 登录 Cookie 只保存在 iOS Keychain，不写日志、不进仓库
- 手柄：方向键导航；播放时 A 播放/暂停、B 先退出全屏再返回、Y 切换全屏、Option 切换自动连播设置、上下调音量、左右快退/快进
- 触屏操作始终可用

## 当前限制

- V0.2 首版使用热门列表，个性化推荐、搜索、收藏稍后接入
- 原生弹幕引擎尚未接入，播放时按 X 会显示明确提示
- 目前优先请求可直接交给 AVPlayer 的渐进式流；DASH 音视频合流和更高画质是后续里程碑
- B 站接口与登录页面并非稳定 SDK，服务端变化可能导致功能失效
- 本项目不修改会员权益，不下载视频，不处理 DRM

## 构建

推送到 `main` 后，GitHub Actions 在 macOS 15 上用 XcodeGen 生成工程并编译未签名 IPA。产物可在 Actions 对应运行的 Artifacts 下载，再由用户自行签名安装。

本地 macOS 构建：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project BiliPad.xcodeproj -scheme BiliPad -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
