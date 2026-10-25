// CustomFontStore.swift — 自定义字体导入/注册/选择
import Foundation
import CoreText
import UIKit
import Combine

struct CustomFontEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// 注册后的 PostScript 名（用于 UIFont(name:)）
    var postScriptName: String
    var displayName: String
    var fileName: String
    var importedAt: Date = Date()
}

@MainActor
final class CustomFontStore: ObservableObject {
    static let shared = CustomFontStore()

    @Published private(set) var fonts: [CustomFontEntry] = []
    private let file = "custom_fonts.json"
    private let fm = FileManager.default
    private let root: URL

    private init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zhijian/Fonts", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        root = base
        fonts = AppData.load([CustomFontEntry].self, file) ?? []
        registerAll()
    }

    func importFont(url: URL) throws -> CustomFontEntry {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent
        let target = root.appendingPathComponent(name)
        try data.write(to: target, options: .atomic)

        guard register(target) else {
            throw FontError.invalidFont(name)
        }
        guard let entry = Self.inspect(target) else {
            throw FontError.invalidFont(name)
        }
        if !fonts.contains(where: { $0.postScriptName == entry.postScriptName }) {
            fonts.append(entry)
            persist()
        }
        return entry
    }

    func remove(_ entry: CustomFontEntry) {
        let target = root.appendingPathComponent(entry.fileName)
        CTFontManagerUnregisterFontsForURL(target as CFURL, .process, nil)
        try? fm.removeItem(at: target)
        fonts.removeAll { $0.id == entry.id }
        persist()
    }

    /// 从磁盘重载（备份恢复后调用）。
    func reload() {
        fonts = AppData.load([CustomFontEntry].self, file) ?? []
        registerAll()
    }

    func font(named postScriptName: String, size: CGFloat) -> UIFont? {
        UIFont(name: postScriptName, size: size)
    }

    var isEmpty: Bool { fonts.isEmpty }

    // MARK: - 内部

    private func registerAll() {
        for entry in fonts {
            let url = root.appendingPathComponent(entry.fileName)
            guard fm.fileExists(atPath: url.path) else { continue }
            _ = register(url)
        }
    }

    @discardableResult
    private func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let error = error?.takeRetainedValue() {
            // 已注册不算失败
            let code = CFErrorGetCode(error)
            if code == 105 { return true }
            NSLog("[Font] register failed %@", CFErrorCopyDescription(error) as String? ?? "unknown")
            return false
        }
        return true
    }

    private static func inspect(_ url: URL) -> CustomFontEntry? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        guard let postScript, !postScript.isEmpty else { return nil }
        return CustomFontEntry(postScriptName: postScript,
                               displayName: family?.isEmpty == false ? family! : postScript,
                               fileName: url.lastPathComponent)
    }

    private func persist() {
        AppData.save(fonts, file)
    }

    enum FontError: LocalizedError {
        case invalidFont(String)
        var errorDescription: String? {
            switch self {
            case .invalidFont(let name): return "无法识别字体文件：\(name)（支持 TTF/OTF/TTC）"
            }
        }
    }
}
