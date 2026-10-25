// AppIconController.swift — 随配色切换 App 图标
import UIKit
import SwiftUI

@MainActor
enum AppIconController {
    static func names(for paletteID: String) -> String? {
        switch paletteID {
        case "qingbai": return "AppIcon-qingbai"
        case "yuebai": return "AppIcon-yuebai"
        case "wulan": return "AppIcon-wulan"
        case "nuansha": return "AppIcon-nuansha"
        case "anmo": return "AppIcon-anmo"
        default: return nil
        }
    }

    static var currentIconName: String? { UIApplication.shared.alternateIconName }

    /// 切换图标；失败时延迟重试（系统要求 App 在前台且无其他图标变更进行中）。
    static func apply(paletteID: String, enabled: Bool, retry: Int = 2) {
        guard UIApplication.shared.applicationState == .active else {
            if retry > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    apply(paletteID: paletteID, enabled: enabled, retry: retry - 1)
                }
            }
            return
        }
        guard enabled else {
            guard UIApplication.shared.supportsAlternateIcons,
                  UIApplication.shared.alternateIconName != nil else { return }
            UIApplication.shared.setAlternateIconName(nil) { _ in }
            return
        }
        guard UIApplication.shared.supportsAlternateIcons,
              let target = names(for: paletteID) else { return }
        guard UIApplication.shared.alternateIconName != target else { return }
        UIApplication.shared.setAlternateIconName(target) { error in
            guard let error else { return }
            NSLog("[AppIcon] set failed %@ (retry left %d)", error.localizedDescription, retry)
            if retry > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    apply(paletteID: paletteID, enabled: enabled, retry: retry - 1)
                }
            }
        }
    }
}
