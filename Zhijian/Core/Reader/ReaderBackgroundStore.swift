// ReaderBackgroundStore.swift — 阅读背景图（亮度/模糊/透明度）
import SwiftUI
import Combine
import UIKit

@MainActor
final class ReaderBackgroundStore: ObservableObject {
    static let shared = ReaderBackgroundStore()

    @Published private(set) var imageData: Data?
    @Published var opacity: Double {
        didSet { save() }
    }
    @Published var blur: Double {
        didSet { save() }
    }
    @Published var enabled: Bool {
        didSet { save() }
    }

    private let file = "reader_background.json"

    private struct Payload: Codable {
        var imageData: Data?
        var opacity: Double
        var blur: Double
        var enabled: Bool
    }

    private init() {
        let payload = AppData.load(Payload.self, file)
        imageData = payload?.imageData
        opacity = payload?.opacity ?? 0.35
        blur = payload?.blur ?? 6
        enabled = payload?.enabled ?? false
    }

    /// 从磁盘重载（备份恢复后调用）
    func reload() {
        let payload = AppData.load(Payload.self, file)
        imageData = payload?.imageData
        opacity = payload?.opacity ?? 0.35
        blur = payload?.blur ?? 6
        enabled = payload?.enabled ?? false
    }

    var image: UIImage? {
        guard let imageData else { return nil }
        return UIImage(data: imageData)
    }

    var hasImage: Bool { imageData != nil }

    func setImage(_ image: UIImage) {
        // 限制长边 2000px，避免存储膨胀
        let maxSide: CGFloat = 2000
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        imageData = resized.jpegData(compressionQuality: 0.85)
        enabled = true
        save()
    }

    func clear() {
        imageData = nil
        enabled = false
        save()
    }

    private func save() {
        AppData.save(Payload(imageData: imageData, opacity: opacity, blur: blur, enabled: enabled), file)
    }
}

/// 阅读背景视图：主题底色 + 可选背景图（模糊 + 遮罩）。
struct ReaderBackgroundView: View {
    let theme: ReaderTheme?
    var customBackground: Color? = nil
    @ObservedObject private var store = ReaderBackgroundStore.shared

    private var baseBackground: Color { customBackground ?? (theme?.background ?? Color.white) }

    var body: some View {
        ZStack {
            baseBackground
            if store.enabled, let image = store.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: store.blur)
                    .opacity(store.opacity)
                    .overlay(baseBackground.opacity(1 - store.opacity * 1.4))
                    .ignoresSafeArea()
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }
}
