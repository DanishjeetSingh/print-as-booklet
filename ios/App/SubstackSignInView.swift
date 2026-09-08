import SwiftUI
import WebKit

@MainActor
final class SubstackSignInSession: ObservableObject {
    weak var webView: WKWebView?

    func synchronizeCookies() async {
        guard let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore else {
            return
        }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        SharedCookieStore.importFromWebKit(cookies)
    }
}

struct SubstackSignInView: UIViewRepresentable {
    @ObservedObject var session: SubstackSignInSession

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        session.webView = webView
        webView.load(URLRequest(url: AppConfiguration.substackSignInURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                SharedCookieStore.importFromWebKit(cookies)
            }
        }
    }
}
