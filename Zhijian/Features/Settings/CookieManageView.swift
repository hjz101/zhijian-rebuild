// CookieManageView.swift — 书源 Cookie 查看/删除
import SwiftUI

struct CookieManageView: View {
    @ObservedObject private var store = CookieStore.shared
    @State private var showClearConfirm = false
    @State private var copied = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Cookie 总数")
                    Spacer()
                    Text("\(store.cookieCount)").foregroundStyle(.secondary).monospacedDigit()
                }
                if let updatedAt = store.updatedAt {
                    HStack {
                        Text("最近更新")
                        Spacer()
                        Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    copyAll()
                } label: {
                    Label(copied ? "已复制" : "复制全部（Netscape 格式）", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Cookie 持久化")
            } footer: {
                Text("Cookie 保存在 Application Support/Zhijian/cookies.json；书源登录态会在搜索/详情/正文间共享，重启后保留。")
            }

            if store.domains.isEmpty {
                ContentUnavailableView("暂无 Cookie", systemImage: "network.slash",
                                       description: Text("登录书源站点或访问需要 Cookie 的源后会自动记录"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.domains, id: \.self) { domain in
                    Section(domain) {
                        ForEach((store.cookies[domain] ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                Text(value).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(ZJ.textSecondary).lineLimit(2)
                            }
                        }
                        .onDelete { _ in
                            store.remove(domain: domain)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ZJ.bgBase.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .background(QiBackground())
        .tint(ZJ.accent)
        .navigationTitle("Cookie 管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空", role: .destructive) { showClearConfirm = true }
                    .disabled(store.domains.isEmpty)
            }
        }
        .confirmationDialog("清空全部 Cookie？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { store.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已登录的书源可能需要重新登录。")
        }
    }

    private func copyAll() {
        var lines: [String] = []
        for domain in store.domains {
            for (name, value) in (store.cookies[domain] ?? [:]).sorted(by: { $0.key < $1.key }) {
                lines.append("\(domain)\tTRUE\t/\tFALSE\t0\t\(name)\t\(value)")
            }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
