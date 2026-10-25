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
        ScrollView {
            VStack(spacing: 18) {
                QiSettingsSection(title: "iCloud 同步") {
                    QiRow(icon: "icloud", title: "iCloud 键值同步",
                          subtitle: cloud.statusMessage,
                          value: cloud.usingFallback ? "本地镜像（待签名）" : (cloud.remoteUpdated ? "云端有更新" : "已连接"))
                    QiDivider()
                    if cloud.lastConflictCount > 0 {
                        QiRow(icon: "arrow.triangle.merge", title: "最近合并冲突",
                              value: "\(cloud.lastConflictCount) 处（新版本优先）")
                        QiDivider()
                    }
                    primaryAction("上传设置与阅读进度", icon: "icloud.and.arrow.up") {
                        cloud.push(settings: env.settings.settings, books: env.books.books)
                        present("已上传当前设置与阅读进度")
                    }
                    QiDivider()
                    actionRow("从 iCloud 同步", icon: "icloud.and.arrow.down") {
                        let summary = cloud.pull(into: env.settings, books: env.books)
                        present(summary)
                    }
                    if let pushed = cloud.lastPushAt {
                        QiDivider()
                        QiRow(icon: "clock", title: "最近上传",
                              value: pushed.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let pulled = cloud.lastPullAt {
                        QiDivider()
                        QiRow(icon: "clock", title: "最近下载",
                              value: pulled.formatted(date: .abbreviated, time: .shortened))
                    }
                    footer("通过 NSUbiquitousKeyValueStore 同步阅读设置与每本书的章节/页码进度；不包含书源 Cookie 与正文文件。")
                }

                QiSettingsSection(title: "WebDAV 评论同步") {
                    if let config = env.backup.webdav.activeConfig {
                        actionRow(syncingComments ? "正在同步…" : "同步段评 / 章末评论",
                                  icon: "bubble.left.and.bubble.right",
                                  disabled: syncingComments) {
                            syncComments(config)
                        }
                        QiDivider()
                        Text(commentSyncMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("先在「备份与同步」配置 WebDAV，即可独立同步评论。")
                            .font(.system(size: 12))
                            .foregroundStyle(ZJ.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                    }
                    footer("上传/下载 zhijian-comments.json；合并按 updatedAt 新版本优先，删除以墓碑同步。")
                }

                QiSettingsSection(title: "iCloud Drive 备份") {
                    QiRow(icon: "externaldrive.badge.icloud", title: "iCloud Drive",
                          value: cloud.driveAvailable ? "可用" : "不可用")
                    QiDivider()
                    actionRow("生成备份并镜像到 iCloud Drive",
                              icon: "arrow.up.doc.on.clipboard",
                              disabled: working) {
                        mirrorBackup()
                    }
                    footer(cloud.driveAvailable
                           ? "备份文件会写入 iCloud Drive/指尖阅读/Documents。"
                           : "当前构建未启用 iCloud 容器（需签名与 ubiquity 容器 entitlement）；可用「备份与同步」导出到「文件」App。")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(QiBackground())
        .tint(ZJ.accent)
        .navigationTitle("iCloud 同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: $showMessage) {
            Button("好", role: .cancel) {}
        }
    }

    private func actionRow(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
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
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func primaryAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(ZJ.accent, in: Capsule())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
