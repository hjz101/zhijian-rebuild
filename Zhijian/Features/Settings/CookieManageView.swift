// CookieManageView.swift — 书源 Cookie 查看/删除
import SwiftUI

struct CookieManageView: View {
    @ObservedObject private var store = CookieStore.shared
    @State private var showClearConfirm = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                QiSettingsSection(title: "Cookie 持久化") {
                    QiRow(icon: "network", title: "Cookie 总数", value: "\(store.cookieCount)")
                    QiDivider()
                    if let updatedAt = store.updatedAt {
                        QiRow(icon: "clock", title: "最近更新",
                              value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                        QiDivider()
                    }
                    actionRow(copied ? "已复制" : "复制全部（Netscape 格式）", icon: "doc.on.doc") { copyAll() }
                    footer("Cookie 保存在 Application Support/Zhijian/cookies.json；书源登录态会在搜索/详情/正文间共享，重启后保留。")
                }

                if store.domains.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(ZJ.textTertiary)
                        Text("暂无 Cookie").font(.system(size: 15, weight: .semibold)).foregroundStyle(ZJ.textPrimary)
                        Text("登录书源站点后会自动记录")
                            .font(.system(size: 12)).foregroundStyle(ZJ.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    ForEach(store.domains, id: \.self) { domain in
                        QiSettingsSection(title: domain) {
                            let items = (store.cookies[domain] ?? [:]).sorted(by: { $0.key < $1.key })
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(item.key).font(.system(size: 12, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.remove(domain: domain)
                                        } label: {
                                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(ZJ.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text(item.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(ZJ.textSecondary)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                if index < items.count - 1 { QiDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
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

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ZJ.accent)
                    .frame(width: 30, height: 30)
                    .background(ZJ.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(ZJ.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(ZJ.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(ZJ.textTertiary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
