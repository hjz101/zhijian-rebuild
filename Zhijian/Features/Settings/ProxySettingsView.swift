// ProxySettingsView.swift — 网络代理设置
import SwiftUI

struct ProxySettingsView: View {
    @ObservedObject private var store = ProxySettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    QiSettingsSection(title: "代理") {
                        QiToggleRow(icon: "network.slash", title: "启用代理", isOn: Binding(
                            get: { store.enabled }, set: { store.enabled = $0 }
                        ))
                        QiDivider()
                        HStack {
                            Text("主机").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                            TextField("127.0.0.1", text: $store.host)
                                .font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        QiDivider()
                        HStack {
                            Text("端口").font(.system(size: 13)).foregroundStyle(ZJ.textPrimary)
                            TextField("8080", text: $store.port).font(.system(size: 13))
                                .keyboardType(.numberPad)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        QiDivider()
                        QiToggleRow(icon: "shuffle", title: "SOCKS5", isOn: $store.isSOCKS)
                    }
                    Text("代理只作用于本 App 的书源请求，不影响系统其它 App；填错会导致书源全部失败，请谨慎。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ZJ.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(QiBackground())
            .navigationTitle("网络代理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
