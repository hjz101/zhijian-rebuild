// EngineSelfTest.swift — 引擎兼容层自检（fastjson / Gson / ZIP / 规则 JS）
import Foundation

struct EngineSelfTestItem: Identifiable {
    let id = UUID()
    var name: String
    var ok: Bool
    var detail: String
}

enum EngineSelfTest {
    @MainActor
    static func run() async -> [EngineSelfTestItem] {
        var items: [EngineSelfTestItem] = []
        var source = BookSource()
        source.bookSourceUrl = "http://localhost/"
        source.bookSourceName = "引擎自检"
        let jar = CookieJar()
        let http = HTTPClient(jar: jar)
        let js = JSRuntime(source: source, http: http, jar: jar)

        func number(_ value: Any?) -> Double {
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let n = value as? NSNumber { return n.doubleValue }
            return Double(String(describing: value ?? "")) ?? 0
        }

        func check(_ name: String, _ code: String, _ predicate: (Any?) -> Bool) {
            do {
                let value = try js.evaluateJS(code, bindings: RuleBindings())
                items.append(EngineSelfTestItem(name: name, ok: predicate(value),
                                                detail: String(describing: value ?? "nil")))
            } catch {
                items.append(EngineSelfTestItem(name: name, ok: false, detail: error.localizedDescription))
            }
        }

        check("fastjson.parse/getString",
              "com.alibaba.fastjson.JSON.parse('{\"a\":\"b\",\"n\":2}').getString('a')") { ($0 as? String) == "b" }
        check("fastjson.parseArray/getInt",
              "com.alibaba.fastjson.JSON.parseArray('[{\"x\":7}]').getJSONObject(0).getInt('x')") {
            String(describing: $0 ?? "").hasPrefix("7")
        }
        check("Gson.toJson",
              "new com.google.gson.Gson().toJson({a:1,b:'c'})") { ($0 as? String)?.contains("\"a\":1") == true }
        check("Gson.fromJson",
              "new com.google.gson.Gson().fromJson('{\"k\":\"v\"}').getString('k')") { ($0 as? String) == "v" }
        check("Packages.fastjson",
              "Packages.com.alibaba.fastjson.JSON.parse('{\"z\":9}').getInt('z')") {
            String(describing: $0 ?? "").hasPrefix("9")
        }

        let timeoutResult: (Bool, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var source = BookSource()
                source.bookSourceUrl = "http://localhost/"
                let runtime = JSRuntime(source: source, http: HTTPClient(jar: CookieJar()), jar: CookieJar())
                _ = runtime.installExecutionTimeLimit(seconds: 2)
                let start = Date()
                do {
                    _ = try runtime.evaluateJS("while (true) {}", bindings: RuleBindings())
                    continuation.resume(returning: (false, "未被中断"))
                } catch {
                    let elapsed = Date().timeIntervalSince(start)
                    continuation.resume(returning: (elapsed < 8, String(format: "%.1fs · %@", elapsed, error.localizedDescription)))
                }
            }
        }
        items.append(EngineSelfTestItem(name: "JSC 超时中断", ok: timeoutResult.0,
                                        detail: timeoutResult.1))

        if let url = Bundle.main.url(forResource: "demo", withExtension: "7z"),
           let data = try? Data(contentsOf: url) {
            do {
                let entries = try ArchiveReader.list(data: data)
                let target = entries.first(where: { $0.name.hasSuffix("hello.txt") })?.name ?? "hello.txt"
                let text = try ArchiveReader.read(data: data, entry: target)
                let value = String(decoding: text, as: UTF8.self)
                items.append(EngineSelfTestItem(name: "7z 解包（libarchive）",
                                                ok: entries.count >= 1 && value == "7z-hello",
                                                detail: "entries=\(entries.count) · \(value)"))
            } catch {
                items.append(EngineSelfTestItem(name: "7z 解包（libarchive）", ok: false,
                                                detail: error.localizedDescription))
            }
        } else {
            items.append(EngineSelfTestItem(name: "7z 解包（libarchive）", ok: false, detail: "缺少 demo.7z"))
        }

        do {
            let js = "var u = URL.createObjectURL(new Blob(['captured-body'], {type:'text/plain'})); fetch(u).then(function(r){return r.text();}); 'started'"
            let result = try await HeadlessWebViewEngine.shared.renderDetailed(
                html: "<html><body>capture</body></html>", baseURL: nil, url: nil,
                javaScript: js, timeout: 15, captureNetwork: true, captureWait: 3.0
            )
            let hit = result.responses.contains { $0.body.contains("captured-body") }
            let detail = result.responses.first?.body ?? "未捕获到响应"
            items.append(EngineSelfTestItem(name: "WebView 网络拦截", ok: hit, detail: String(detail.prefix(60))))
        } catch {
            items.append(EngineSelfTestItem(name: "WebView 网络拦截", ok: false, detail: error.localizedDescription))
        }

        if let url = Bundle.main.url(forResource: "demo", withExtension: "epub") {
            let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            check("ZIP getZipStringContent",
                  "java.getZipStringContent('\(path)', 'META-INF/container.xml').indexOf('container') >= 0") { ($0 as? Bool) == true }
            check("ZIP getZipByteArrayContent",
                  "java.getZipByteArrayContent('\(path)', 'mimetype').length") { number($0) > 0 }
            check("ZIP unzipFile",
                  "java.unzipFile('\(path)').length > 0") { ($0 as? Bool) == true }
            check("ZIP native list",
                  "_nativeZipList('\(path)', false).length") { number($0) >= 5 }
        } else {
            items.append(EngineSelfTestItem(name: "ZIP 示例", ok: false, detail: "Bundle 中缺少 demo.epub"))
        }

        // WKWebView 兜底
        do {
            let output = try await HeadlessWebViewEngine.shared.render(
                html: "<html><head><title>zj</title></head><body><div id=\"x\">42</div></body></html>",
                baseURL: nil, url: nil, javaScript: "document.getElementById('x').textContent", timeout: 12
            )
            items.append(EngineSelfTestItem(name: "HeadlessWebView JS", ok: output == "42", detail: output))
        } catch {
            items.append(EngineSelfTestItem(name: "HeadlessWebView JS", ok: false, detail: error.localizedDescription))
        }

        // 真实引擎调用发生在非主线程（JSContext 队列），自检也放到后台线程，
        // 避免主线程同步桥阻塞 WKWebView 的 MainActor 任务。
        let webRule: (String, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let html = "<html><body><div id=\"v\">webjs-ok</div></body></html>"
                do {
                    let context = RuleContext(result: html, baseURL: "")
                    let analyzer = RuleAnalyzer(context: context, vars: RuleVariableStore(), js: nil,
                                                webView: { html, base, script in
                        HeadlessWebViewEngine.renderSync(html: html, baseURL: base.isEmpty ? nil : base,
                                                         url: nil, javaScript: script, timeout: 12)
                    })
                    let value = try analyzer.analyze("@webjs:document.getElementById('v').textContent", input: html)
                    continuation.resume(returning: (JSONValueUtil.text(value), ""))
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription))
                }
            }
        }
        items.append(EngineSelfTestItem(name: "@webjs 规则", ok: webRule.0 == "webjs-ok",
                                        detail: webRule.0.isEmpty ? webRule.1 : webRule.0))

        let javaWebView: (String, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var source = BookSource()
                source.bookSourceUrl = "http://localhost/"
                let jar = CookieJar()
                let http = HTTPClient(jar: jar)
                let runtime = JSRuntime(source: source, http: http, jar: jar)
                do {
                    let value = try runtime.evaluateJS(
                        "java.webView('<html><head><title>jw</title></head><body>ok</body></html>', '', 'document.title')",
                        bindings: RuleBindings()
                    )
                    continuation.resume(returning: (JSONValueUtil.text(value), ""))
                } catch {
                    continuation.resume(returning: ("", error.localizedDescription))
                }
            }
        }
        items.append(EngineSelfTestItem(name: "java.webView", ok: javaWebView.0 == "jw",
                                        detail: javaWebView.0.isEmpty ? javaWebView.1 : javaWebView.0))

        return items
    }
}
