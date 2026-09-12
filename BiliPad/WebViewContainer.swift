import SwiftUI
import UIKit
import WebKit

struct WebViewContainer: UIViewRepresentable {
    static let homeURL = URL(string: "https://www.bilibili.com/")!

    @ObservedObject var model: WebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent()

        let userContentController = WKUserContentController()
        addBundleScript("controller-bridge", injectionTime: .atDocumentStart, to: userContentController)
        addBundleScript("focus-navigation", injectionTime: .atDocumentEnd, to: userContentController)
        addBundleCSS("bilipad", to: userContentController)
        userContentController.add(context.coordinator, name: "bilipadBridge")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        model.attach(webView)
        webView.load(URLRequest(url: Self.homeURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "bilipadBridge")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    private func addBundleScript(
        _ name: String,
        injectionTime: WKUserScriptInjectionTime,
        to controller: WKUserContentController
    ) {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Missing bundled script: \(name).js")
            return
        }
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: injectionTime,
            forMainFrameOnly: true
        ))
    }

    private func addBundleCSS(_ name: String, to controller: WKUserContentController) {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8),
            let data = try? JSONEncoder().encode(css),
            let encoded = String(data: data, encoding: .utf8)
        else {
            assertionFailure("Missing bundled stylesheet: \(name).css")
            return
        }

        let source = """
        (() => {
          if (document.getElementById('bilipad-style')) return;
          const style = document.createElement('style');
          style.id = 'bilipad-style';
          style.textContent = \(encoded);
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let model: WebViewModel

        init(model: WebViewModel) {
            self.model = model
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .cancel
            }

            if navigationAction.targetFrame?.isMainFrame == false {
                return .allow
            }

            guard Self.isAllowedTopLevelURL(url) else {
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    _ = await UIApplication.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                return nil
            }
            if Self.isAllowedTopLevelURL(url) {
                webView.load(URLRequest(url: url))
            } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            model.visibleError = "网页加载失败：\(error.localizedDescription)"
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            model.visibleError = "网页导航失败：\(error.localizedDescription)"
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard Self.isBilibiliHost(message.frameInfo.securityOrigin.host) else { return }
            guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else {
                return
            }
            if type == "error", let text = payload["message"] as? String {
                model.visibleError = String(text.prefix(300))
            }
        }

        private static func isAllowedTopLevelURL(_ url: URL) -> Bool {
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
            return isBilibiliHost(url.host ?? "")
        }

        private static func isBilibiliHost(_ host: String) -> Bool {
            let normalized = host.lowercased()
            return normalized == "bilibili.com" || normalized.hasSuffix(".bilibili.com")
        }
    }
}
