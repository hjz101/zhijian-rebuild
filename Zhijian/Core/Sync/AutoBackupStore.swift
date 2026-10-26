// AutoBackupStore.swift — 自动备份调度偏好与状态（never / onExit / daily / weekly）
import Foundation
import Combine

enum AutoBackupFrequency: String, Codable, CaseIterable, Sendable {
    case never, onExit, daily, weekly, scheduled
    var name: String {
        switch self {
        case .never: return "关闭"
        case .onExit: return "退出 App 时"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .scheduled: return "定时"
        }
    }
}

@MainActor
final class AutoBackupStore: ObservableObject {
    static let shared = AutoBackupStore()

    @Published var frequency: AutoBackupFrequency {
        didSet { persist() }
    }
    /// 定时备份的小时（0-23）
    @Published var scheduledHour: Int {
        didSet { persist() }
    }
    @Published private(set) var lastAutoBackupAt: Date?
    @Published private(set) var lastAutoBackupNote: String?

    private let file = "auto_backup.json"
    private struct Snapshot: Codable {
        var frequency: AutoBackupFrequency = .never
        var scheduledHour: Int = 22
        var lastAutoBackupAt: Date?
        var lastAutoBackupNote: String?
    }

    private init() {
        let snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
        frequency = snapshot.frequency
        scheduledHour = snapshot.scheduledHour
        lastAutoBackupAt = snapshot.lastAutoBackupAt
        lastAutoBackupNote = snapshot.lastAutoBackupNote
    }

    func record(result: String) {
        lastAutoBackupAt = Date()
        lastAutoBackupNote = result
        persist()
    }

    /// 距上次自动备份是否已到周期。
    func shouldRunNow() -> Bool {
        switch frequency {
        case .never: return false
        case .onExit: return false // 由 scenePhase 后台触发
        case .daily:
            guard let last = lastAutoBackupAt else { return true }
            return Date().timeIntervalSince(last) >= 24 * 3600
        case .weekly:
            guard let last = lastAutoBackupAt else { return true }
            return Date().timeIntervalSince(last) >= 7 * 24 * 3600
        case .scheduled:
            // 设定小时且今天尚未备份
            let hour = Calendar.current.component(.hour, from: Date())
            guard hour == scheduledHour else { return false }
            if let last = lastAutoBackupAt {
                return !Calendar.current.isDateInToday(last)
            }
            return true
        }
    }

    private func persist() {
        AppData.save(Snapshot(frequency: frequency,
                              scheduledHour: scheduledHour,
                              lastAutoBackupAt: lastAutoBackupAt,
                              lastAutoBackupNote: lastAutoBackupNote), file)
    }
}

/// 自动备份执行器：导出 .zjbk 到 iCloud Drive（不可用时落到 Documents/ZhijianAutoBackup）。
@MainActor
enum AutoBackupRunner {
    static func runNow(backup: BackupService) async -> String {
        let store = AutoBackupStore.shared
        let destination: URL?
        if CloudSyncService.shared.driveAvailable {
            destination = CloudSyncService.shared.driveDirectory()
        } else {
            destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ZhijianAutoBackup", isDirectory: true)
        }
        do {
            let url = try backup.export(to: destination)
            let dest = destination == nil ? "临时目录" : url.lastPathComponent
            let result = "自动备份完成：\(dest)"
            store.record(result: result)
            return result
        } catch {
            let result = "自动备份失败：\(error.localizedDescription)"
            store.record(result: result)
            return result
        }
    }
}
