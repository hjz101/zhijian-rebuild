// SourceLoginSheet.swift — 书源登录：loginUi 原生表单 / loginUrl WKWebView / loginCheckJs
import SwiftUI
import WebKit

struct SourceLoginRow: Decodable, Identifiable {
    var name: String = ""
    var type: String = "text"
    var action: String?
    var chars: [String?]?
    var `default`: String?
    var viewName: String?

    var id: String { name + "|" + type }

    var title: String {
        guard let viewName, !viewName.isEmpty else { return name }
        if viewName.count >= 2, viewName.first == "'", viewName.last == "'" {
            return String(viewName.dropFirst().dropLast())
        }
        return viewName
    }

    var options: [String] { (chars ?? []).compactMap { $0 }.filter { !$0.isEmpty } }
}

@MainActor
final class SourceLoginWebController: ObservableObject {
    weak var webView: WKWebView?

    func cookieHeader(completion: @escaping (String) -> Void) {
        guard let webView else { completion(""); return }
        let host = webView.url?.host ?? ""
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let matched = cookies.filter { cookie in
                host.isEmpty || cookie.domain.contains(host)
                    || host.contains(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            let header = matched.sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            DispatchQueue.main.async { completion(header) }
        }
    }
}

struct SourceLoginSheet: View {
    let source: BookSource
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .form
    @State private var rows: [SourceLoginRow] = []
    @State private var info: [String: String] = [:]
    @State private var existingHeader: [String: String] = [:]
    @State private var loading = true
    @State private var busy = false
    @State private var message: String?
    @State private var showMessage = false
    @StateObject private var webController = SourceLoginWebController()

    enum Mode { case form, web }

    init(source: BookSource) {
        self.source = source
        let storedInfo = SourceLoginStore.shared.loginInfo(for: source.bookSourceUrl)
        _info = State(initialValue: storedInfo)
        _existingHeader = State(initialValue: SourceLoginStore.shared.loginHeader(for: source.bookSourceUrl))
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("读取登录配置…")
                } else if mode == .web, let url = webURL {
                    SourceLoginWebView(url: url, controller: webController)
                } else {
                    formBody
                }
            }
            .navigationTitle("登录 · \(source.bookSourceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if busy { ProgressView().controlSize(.small) }
                        else { Text("完成").fontWeight(.semibold) }
                    }
                    .disabled(busy || loading)
                }
            }
            .task { await load() }
            .alert(message ?? "", isPresented: $showMessage) {
                Button("好", role: .cancel) { if message?.hasPrefix("登录成功") == true { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var webURL: URL? {
        guard let raw = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !raw.hasPrefix("@js:"), !raw.hasPrefix("<js>"),
              let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    @ViewBuilder
    private var formBody: some View {
        Form {
            if rows.isEmpty {
                Section {
                    Text("该书源未提供 loginUi，且 loginUrl 不是可打开的网页。请直接在浏览器登录后使用 Cookie 导入，或联系书源作者。")
                        .font(.footnote)
                }
            } else {
                Section {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text("登录信息")
                } footer: {
                    Text("填写后点击「完成」，会保存登录信息并执行 loginUrl 中的 @js:/<js> 登录脚本（如有）。")
                }
            }

            Section {
                Button("清除该书源登录态", role: .destructive) {
                    SourceLoginStore.shared.remove(sourceUrl: source.bookSourceUrl)
                    info = [:]
                    existingHeader = [:]
                    present("已清除登录态")
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SourceLoginRow) -> some View {
        switch row.type.lowercased() {
        case "password":
            SecureField(row.title, text: Binding(
                get: { info[row.name] ?? "" },
                set: { info[row.name] = $0 }
            ))
        case "toggle":
            Toggle(row.title, isOn: Binding(
                get: { (info[row.name] ?? row.default ?? "false").lowercased() == "true" },
                set: { info[row.name] = $0 ? "true" : "false" }
            ))
        case "select":
            Picker(row.title, selection: Binding(
                get: { info[row.name] ?? row.default ?? row.options.first ?? "" },
                set: { info[row.name] = $0 }
            )) {
                ForEach(row.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        case "button":
            Button(row.title) {
                performAction(row.action)
            }
        default:
            TextField(row.title, text: Binding(
                get: { info[row.name] ?? row.default ?? "" },
                set: { info[row.name] = $0 }
            ))
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let pipeline = makePipeline()
        do {
            let raw = try await pipeline.resolvedLoginUI()
            rows = Self.decodeRows(raw)
            for row in rows {
                if info[row.name] == nil {
                    if let def = row.default { info[row.name] = def }
                    else if row.type.lowercased() == "select" { info[row.name] = row.options.first }
                }
            }
        } catch {
            rows = []
            present("登录 UI 解析失败：\(error.localizedDescription)")
        }
        if ProcessInfo.processInfo.arguments.contains("-autoSubmitLogin") {
            submit()
        }
        if rows.isEmpty && webURL != nil { mode = .web }
        if rows.isEmpty && webURL == nil && source.loginUrl == nil {
            mode = .form
        }
    }

    private static func decodeRows(_ raw: String) -> [SourceLoginRow] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SourceLoginRow].self, from: data)) ?? []
    }

    private func makePipeline() -> SourcePipeline {
        SourcePipeline(source: source,
                       initialCookies: CookieStore.shared.snapshot(),
                       loginInfo: info,
                       loginHeader: existingHeader,
                       onCookiesChanged: { CookieStore.onChange($0) })
    }

    /// loginUi 按钮：执行源里的 JS action（HTTP 链接则外部打开）。
    private func performAction(_ action: String?) {
        guard let action = action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else {
            submit()
            return
        }
        if action.lowercased().hasPrefix("http"), let url = URL(string: action) {
            UIApplication.shared.open(url)
            return
        }
        busy = true
        Task {
            defer { busy = false }
            SourceLoginStore.shared.save(sourceUrl: source.bookSourceUrl,
                                         loginInfo: info, loginHeader: existingHeader)
            do {
                let pipeline = makePipeline()
                let headers = try await pipeline.runLoginAction(action, loginInfo: info)
                var merged = existingHeader
                for (key, value) in headers where !value.isEmpty { merged[key] = value }
                if merged != existingHeader {
                    existingHeader = merged
                    SourceLoginStore.shared.save(sourceUrl: source.bookSourceUrl,
                                                 loginInfo: info, loginHeader: merged)
                }
                present("已执行：\(action)")
            } catch {
                present("执行失败：\(error.localizedDescription)")
            }
        }
    }

    private func submit() {
        busy = true
        Task {
            defer { busy = false }
            if mode == .web {
                webController.cookieHeader { cookie in
                    Task { @MainActor in
                        var header = existingHeader
                        if !cookie.isEmpty { header["Cookie"] = cookie }
                        SourceLoginStore.shared.save(sourceUrl: source.bookSourceUrl,
                                                     loginInfo: info, loginHeader: header)
                        present("登录成功：已保存 Cookie（\(cookie.count) 字符）")
                    }
                }
                return
            }

            SourceLoginStore.shared.save(sourceUrl: source.bookSourceUrl,
                                         loginInfo: info, loginHeader: existingHeader)
            do {
                let pipeline = makePipeline()
                let headers = try await pipeline.runLoginScript()
                var merged = existingHeader
                for (key, value) in headers where !value.isEmpty { merged[key] = value }
                SourceLoginStore.shared.save(sourceUrl: source.bookSourceUrl,
                                             loginInfo: info, loginHeader: merged)
                let detail = merged.isEmpty ? "登录信息已保存" : "登录头：\(merged.keys.sorted().joined(separator: ", "))"
                present("登录成功：\(detail)")
            } catch {
                present("登录脚本执行失败：\(error.localizedDescription)")
            }
        }
    }

    private func present(_ text: String) {
        message = text
        showMessage = true
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let controller: SourceLoginWebController

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
        var parent: SourceLoginWebView
        init(_ parent: SourceLoginWebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.controller.webView = webView
        }
    }
}
