// TTSLoginSheet.swift — HTTP TTS 登录页（WKWebView + Cookie 提取）
import SwiftUI
import WebKit

@MainActor
final class TTSLoginController: ObservableObject {
    weak var webView: WKWebView?

    func extractCookieHeader(completion: @escaping (String) -> Void) {
        guard let webView else { completion(""); return }
        let host = webView.url?.host ?? ""
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let matched = cookies.filter { cookie in
                host.isEmpty || cookie.domain.contains(host) || host.contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            let header = matched.sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            DispatchQueue.main.async { completion(header) }
        }
    }
}

struct TTSLoginSheet: View {
    let urlString: String
    let sourceName: String
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = TTSLoginController()
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let url = URL(string: urlString) {
                    TTSLoginWebView(url: url, controller: controller, loading: $loading)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView("登录地址无效", systemImage: "link.badge.plus",
                                           description: Text(urlString))
                }
                if loading {
                    ProgressView("正在打开登录页…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("登录 · \(sourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        controller.extractCookieHeader { header in
                            onComplete(header)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct TTSLoginWebView: UIViewRepresentable {
    let url: URL
    let controller: TTSLoginController
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        controller.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        controller.webView = webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TTSLoginWebView
        init(_ parent: TTSLoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            parent.controller.webView = webView
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
    }
}
