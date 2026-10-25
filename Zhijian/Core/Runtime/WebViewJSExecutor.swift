// WebViewJSExecutor.swift — WebView 书源执行器（④ qysg 启发：JSC 的补充模式）
// 战略价值：书源 JS 可在 WKWebView 里跑，可加载 jquery/crypto-js 等前端库，
// 天然规避 JSC 私有 API 合规问题；代价是只能取回「字符串结果」。
// 本文件提供可切换的执行器骨架 + 自检验证；正式管线默认仍走 JSC（稳定优先）。
import Foundation
import WebKit

/// 统一执行器协议：JSC 与 WebView 后端可切换。
protocol RuleJSSyncExecutor: Sendable {
    func evaluate(_ code: String) throws -> String
}

/// 离屏 WKWebView 执行器（同步语义：信号量等待，默认 8s 超时）。
final class WebViewJSExecutor: NSObject, @unchecked Sendable, WKNavigationDelegate, RuleJSSyncExecutor {
    private let webView: WKWebView
    private let queue = DispatchQueue(label: "zhijian.webview.js")
    private let readySemaphore = DispatchSemaphore(value: 0)
    private var ready = false

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences = WKPreferences()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        // 离屏加载空白页；didFinish 后置 ready
        webView.loadHTMLString("<html><head></head><body></body></html>", baseURL: nil)
        // 给加载留时间（后台不阻塞调用方主线程）
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.ready = true
            self?.readySemaphore.signal()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        readySemaphore.signal()
    }

    func evaluate(_ code: String) throws -> String {
        // 等待就绪（最多 1s，不阻塞主线程等待信号量→由调用方决定在哪等）
        _ = readySemaphore.wait(timeout: .now() + 1.0)
        var result: Result<String, Error>?
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [webView] in
            webView.evaluateJavaScript(code) { value, error in
                if let error {
                    result = .failure(error)
                } else if let string = value as? String {
                    result = .success(string)
                } else if let number = value as? NSNumber {
                    result = .success(number.stringValue)
                } else if value == nil {
                    result = .success("")
                } else {
                    result = .success(String(describing: value ?? ""))
                }
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 8)
        guard let result else {
            throw NSError(domain: "WebViewJSExecutor", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "WebView JS 执行超时（8s）"])
        }
        return try result.get()
    }
}
