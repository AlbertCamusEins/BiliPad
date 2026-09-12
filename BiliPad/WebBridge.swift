import Combine
import Foundation
import WebKit

@MainActor
final class WebViewModel: ObservableObject {
    @Published var visibleError: String?

    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func send(_ action: ControllerAction) {
        guard let webView else { return }
        let encoded = Self.javaScriptString(action.rawValue)
        webView.evaluateJavaScript("window.__bilipad?.receiveAction(\(encoded));") { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.visibleError = "手柄操作未送达网页：\(error.localizedDescription)"
            }
        }
    }

    func goBack() {
        if webView?.canGoBack == true {
            webView?.goBack()
        }
    }

    func reload() {
        webView?.reload()
    }

    func clearWebsiteData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.webView?.load(URLRequest(url: WebViewContainer.homeURL))
            }
        }
    }

    private static func javaScriptString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
