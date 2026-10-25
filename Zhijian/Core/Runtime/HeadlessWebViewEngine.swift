// HeadlessWebViewEngine.swift — 离屏 WKWebView：书源 @webjs / java.webView* 的兜底渲染
import Foundation
import WebKit

struct CapturedWebResponse: Sendable, Hashable {
    var type: String
    var url: String
    var status: Int
    var body: String
}

struct HeadlessRenderResult: Sendable {
    var html: String
    var javaScriptResult: String?
    var responses: [CapturedWebResponse]
}

@MainActor
final class HeadlessWebViewEngine {
    static let shared = HeadlessWebViewEngine()
    private init() {}

    enum EngineError: LocalizedError {
        case timeout
        case navigation(String)
        case empty
        var errorDescription: String? {
            switch self {
            case .timeout: return "WebView 加载超时"
            case .navigation(let message): return "WebView 加载失败：\(message)"
            case .empty: return "WebView 返回空内容"
            }
        }
    }

    /// 加载 HTML 或 URL，执行 JS，返回字符串结果；javaScript 为空时返回整页 outerHTML。
    func render(html: String?, baseURL: String?, url: String?, headers: [String: String] = [:],
                javaScript: String?, timeout: TimeInterval = 20) async throws -> String {
        let result = try await renderDetailed(html: html, baseURL: baseURL, url: url, headers: headers,
                                              javaScript: javaScript, timeout: timeout)
        if let js = result.javaScriptResult, !js.isEmpty { return js }
        return result.html
    }

    /// 详细渲染：可选网络拦截（XHR/fetch），返回页面 HTML + 捕获响应。
    func renderDetailed(html: String?, baseURL: String?, url: String?, headers: [String: String] = [:],
                        javaScript: String?, timeout: TimeInterval = 20,
                        captureNetwork: Bool = false, captureWait: TimeInterval = 2.5) async throws -> HeadlessRenderResult {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let collector = captureNetwork ? NetworkCaptureCollector() : nil
        if let collector {
            configuration.userContentController.add(collector, name: "zjcapture")
            configuration.userContentController.addUserScript(
                WKUserScript(source: Self.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
        }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        let waiter = LoadWaiter(timeout: timeout)
        webView.navigationDelegate = waiter
        waiter.webView = webView

        if let urlString = url?.trimmingCharacters(in: .whitespacesAndNewlines), !urlString.isEmpty,
           let target = URL(string: urlString) {
            var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            webView.load(request)
        } else {
            let base = baseURL.flatMap { URL(string: $0) }
            webView.loadHTMLString(html ?? "", baseURL: base)
        }

        try await waiter.wait()
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            if captureNetwork { configuration.userContentController.removeScriptMessageHandler(forName: "zjcapture") }
        }

        if captureNetwork, captureWait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(captureWait * 1_000_000_000))
        }

        var jsResult: String?
        if let javaScript, !javaScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let value = try await webView.evaluateJavaScript(javaScript)
                jsResult = Self.stringify(value)
            } catch {
                throw EngineError.navigation(error.localizedDescription)
            }
        }
        let htmlValue = try await webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''")
        return HeadlessRenderResult(html: Self.stringify(htmlValue),
                                    javaScriptResult: jsResult,
                                    responses: collector?.responses ?? [])
    }

    /// 注入到页面的 XHR/fetch 拦截脚本
    static let captureScript = """
    (function(){
      if (window.__zjCaptureInstalled) { return; }
      window.__zjCaptureInstalled = true;
      function post(obj){ try { window.webkit.messageHandlers.zjcapture.postMessage(obj); } catch(e){} }
      var open = XMLHttpRequest.prototype.open;
      var send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url){ this.__zjUrl = String(url || ''); return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(body){
        var xhr = this;
        xhr.addEventListener('load', function(){
          var text = '';
          try { text = (xhr.responseType === '' || xhr.responseType === 'text') ? xhr.responseText : ''; } catch(e) {}
          post({type:'xhr', url: String(xhr.__zjUrl || ''), status: xhr.status, body: text || ''});
        });
        return send.apply(this, arguments);
      };
      if (window.fetch) {
        var origFetch = window.fetch;
        window.fetch = function(input, init){
          var url = (typeof input === 'string') ? input : ((input && input.url) || '');
          return origFetch.apply(this, arguments).then(function(resp){
            try {
              var clone = resp.clone();
              clone.text().then(function(text){ post({type:'fetch', url:String(url), status:resp.status, body:text || ''}); }).catch(function(){});
            } catch(e) {}
            return resp;
          });
        };
      }
    })();
    """

    /// 同步桥（供 JSRuntime / 规则引擎在非主线程调用）；主线程调用时泵 RunLoop 防死锁。
    nonisolated static func renderSync(html: String?, baseURL: String?, url: String?,
                                       headers: [String: String] = [:], javaScript: String?,
                                       timeout: TimeInterval = 20) -> String? {
        var result: String?
        var failure: String?
        let done = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                result = try await HeadlessWebViewEngine.shared.render(
                    html: html, baseURL: baseURL, url: url, headers: headers,
                    javaScript: javaScript, timeout: timeout
                )
            } catch {
                failure = error.localizedDescription
            }
            done.signal()
        }

        if Thread.isMainThread {
            let deadline = Date().addingTimeInterval(timeout + 3)
            while done.wait(timeout: .now()) == .timedOut && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        } else {
            _ = done.wait(timeout: .now() + timeout + 3)
        }
        if let failure { NSLog("[HeadlessWebView] %@", failure) }
        return result
    }

    nonisolated static func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    // MARK: 网络捕获

    final class NetworkCaptureCollector: NSObject, WKScriptMessageHandler {
        private(set) var responses: [CapturedWebResponse] = []
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let url = body["url"] as? String else { return }
            let status = (body["status"] as? NSNumber)?.intValue ?? 0
            let text = body["body"] as? String ?? ""
            responses.append(CapturedWebResponse(type: type, url: url, status: status, body: text))
        }
    }

    // MARK: 等待器

    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false
        private var timeoutWork: DispatchWorkItem?
        private let timeout: TimeInterval

        init(timeout: TimeInterval) {
            self.timeout = timeout
            super.init()
        }

        func wait() async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let work = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(EngineError.timeout))
                }
                self.timeoutWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
            }
        }

        private func finish(_ result: Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            timeoutWork?.cancel()
            timeoutWork = nil
            let continuation = self.continuation
            self.continuation = nil
            switch result {
            case .success: continuation?.resume()
            case .failure(let error): continuation?.resume(throwing: error)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finish(.success(()))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(EngineError.navigation(error.localizedDescription)))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(EngineError.navigation(error.localizedDescription)))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            finish(.failure(EngineError.navigation("WebContent 进程终止")))
        }
    }
}
