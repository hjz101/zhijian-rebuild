// DeviceIdentity.swift — 稳定的设备标识（对齐 Legado `java.androidId()` / `java.deviceID()`）
import Foundation

enum DeviceIdentity {
    private static let key = "zhijian.device.androidId"

    /// 16 位小写 hex，形如 Android ID；首次生成后持久化，卸载重装才会变化。
    static var androidId: String {
        if let existing = UserDefaults.standard.string(forKey: key), existing.count == 16 {
            return existing
        }
        var value = ""
        let chars = Array("0123456789abcdef")
        for _ in 0..<16 { value.append(chars.randomElement()!) }
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    /// 部分聚合源用它做设备指纹，格式与 androidId 一致。
    static var deviceId: String { androidId }
}
