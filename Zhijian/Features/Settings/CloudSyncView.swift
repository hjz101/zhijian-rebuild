// CloudSyncView.swift — iCloud KVS 同步 + iCloud Drive 备份镜像
import SwiftUI

struct CloudSyncView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var cloud = CloudSyncService.shared
    @State private var message: String?
    @State private var showMessage = false
    @State private var working = false
    @State private var syncingComments = false
    @State private var commentSyncMessage = "尚未同步"

    var body: some View {
        List {
            Section {
                HStack {
                    Label("iCloud 键值同步", systemImage: "icloud")
                    Spacer()
                    Text(cloud.usingFallback ? "本地镜像（待签名）" : (cloud.remoteUpdated ? "云端有更新" : "已连接"))
                        .font(.caption).foregroundStyle(cloud.remoteUpdated ? ZJ.accent : .secondary)
                }
                Text(cloud.statusMessage).font(.footnote).foregroundStyle(.secondary)
                if cloud.lastConflictCount > 0 {
                    HStack {
                        Text("最近合并冲突")
                        Spacer()
                        Text("\(cloud.lastConflictCount) 处（新版本优先）").foregroundStyle(ZJ.accent)
                    }
                    .font(.caption)
                }
                Button {
                    cloud.push(settings: env.settings.settings, books: env.books.books)
                    present("已上传当前设置与阅读进度")
                } label: {
                    Label("上传设置与阅读进度", systemImage: "icloud.and.arrow.up")
                }
                Button {
                    let summary = cloud.pull(into: env.settings, books: env.books)
                    present(summary)
                } label: {
                    Label("从 iCloud 同步", systemImage: "icloud.and.arrow.down")
                }
                if let pushed = cloud.lastPushAt {
                    HStack { Text("最近上传"); Spacer(); Text(pushed.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                }
                if let pulled = cloud.lastPullAt {
                    HStack { Text("最近下载"); Spacer(); Text(pulled.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                }
            } header: {
                Text("iCloud 同步")
            } footer: {
                Text("通过 NSUbiquitousKeyValueStore 同步阅读设置与每本书的章节/页码进度；不包含书源 Cookie 与正文文件。")
            }

            Section {
                if let config = env.backup.webdav.activeConfig {
                    Button {
                        syncComments(config)
                    } label: {
                        HStack {
                            Label("同步段评 / 章末评论", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            if syncingComments { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(syncingComments)
                    Text(commentSyncMessage).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("先在「备份与同步」配置 WebDAV，即可独立同步评论。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("WebDAV 评论同步")
            } footer: {
                Text("上传/下载 zhijian-comments.json；合并按 updatedAt 新版本优先，删除以墓碑同步。")
            }

            Section {
                HStack {
                    Label("iCloud Drive", systemImage: "externaldrive.badge.icloud")
                    Spacer()
                    Text(cloud.driveAvailable ? "可用" : "不可用").font(.caption)
                        .foregroundStyle(cloud.driveAvailable ? ZJ.celadon : .secondary)
                }
                Button {
                    mirrorBackup()
                } label: {
                    Label("生成备份并镜像到 iCloud Drive", systemImage: "arrow.up.doc.on.clipboard")
                }
                .disabled(working)
            } header: {
                Text("iCloud Drive 备份")
            } footer: {
                Text(cloud.driveAvailable
                     ? "备份文件会写入 iCloud Drive/指尖阅读/Documents。"
                     : "当前构建未启用 iCloud 容器（需签名与 ubiquity 容器 entitlement）；可用「备份与同步」导出到「文件」App。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(ZJ.bgBase.ignoresSafeArea())
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        }
    }

    private func present(_ text: String) {
        message = text
        showMessage = true
    }

    private func syncComments(_ config: WebDAVConfig) {
        syncingComments = true
        Task {
            defer { syncingComments = false }
            do {
                let summary = try await env.backup.syncComments(to: config)
                commentSyncMessage = summary.localizedDescription
                present("评论同步完成：\(summary.localizedDescription)")
            } catch {
                commentSyncMessage = "失败：\(error.localizedDescription)"
                present("评论同步失败：\(error.localizedDescription)")
            }
        }
    }

    private func mirrorBackup() {
        working = true
        Task {
            defer { working = false }
            do {
                let file = try env.backup.export(password: nil)
                let target = try CloudSyncService.shared.mirrorBackup(file)
                present("已镜像：\(target.lastPathComponent)")
            } catch {
                present("镜像失败：\(error.localizedDescription)")
            }
        }
    }
}
