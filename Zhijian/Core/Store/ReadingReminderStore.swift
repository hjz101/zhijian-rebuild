// ReadingReminderStore.swift — 每日阅读提醒（本地通知）
import Foundation
import Combine
import UserNotifications

@MainActor
final class ReadingReminderStore: ObservableObject {
    static let shared = ReadingReminderStore()

    @Published var enabled: Bool {
        didSet {
            persist()
            if enabled { schedule() } else { cancel() }
        }
    }
    @Published var hour: Int {
        didSet { persist(); if enabled { schedule() } }
    }
    @Published var minute: Int {
        didSet { persist(); if enabled { schedule() } }
    }

    private let file = "reading_reminder.json"
    private struct Snapshot: Codable {
        var enabled = false
        var hour = 21
        var minute = 0
    }

    private init() {
        let snapshot = AppData.load(Snapshot.self, file) ?? Snapshot()
        enabled = snapshot.enabled
        hour = snapshot.hour
        minute = snapshot.minute
        if enabled { schedule() }
    }

    /// 请求通知权限（首次开启时）
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func schedule() {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "指尖阅读"
        content.body = "该读书啦 📖 今天的阅读时间到了。"
        content.sound = .default
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "zhijian.daily.reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["zhijian.daily.reminder"])
    }

    private func persist() {
        AppData.save(Snapshot(enabled: enabled, hour: hour, minute: minute), file)
    }
}
