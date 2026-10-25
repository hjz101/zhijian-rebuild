// VolumeButtonPageTurn.swift — 音量键翻页（隐藏 MPVolumeView + 音量还原）
import SwiftUI
import MediaPlayer
import AVFoundation

struct VolumeButtonPageTurnMonitor: UIViewRepresentable {
    var enabled: Bool
    /// +1 = 下一页，-1 = 上一页
    let onTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTurn: onTurn) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.isUserInteractionEnabled = false
        let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 40, height: 40))
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        container.addSubview(volumeView)
        context.coordinator.attach(volumeView)
        context.coordinator.enabled = enabled
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.enabled = enabled
        if enabled { context.coordinator.attachIfNeeded(uiView) }
    }

    final class Coordinator: NSObject {
        var enabled = false
        private let onTurn: (Int) -> Void
        private weak var slider: UISlider?
        private var baseline: Float?
        private var restoring = false

        init(onTurn: @escaping (Int) -> Void) {
            self.onTurn = onTurn
        }

        func attach(_ volumeView: MPVolumeView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak volumeView] in
                guard let self, let volumeView, let slider = Self.findSlider(in: volumeView) else { return }
                self.slider = slider
                self.baseline = slider.value
                slider.addTarget(self, action: #selector(self.valueChanged(_:)), for: .valueChanged)
            }
        }

        func attachIfNeeded(_ container: UIView) {
            guard slider == nil else { return }
            if let volumeView = container.subviews.compactMap({ $0 as? MPVolumeView }).first {
                attach(volumeView)
            }
        }

        @objc private func valueChanged(_ sender: UISlider) {
            guard enabled, !restoring else { return }
            let reference = baseline ?? 0.5
            let direction = sender.value > reference ? 1 : -1
            onTurn(direction)
            restoring = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak sender] in
                guard let self, let sender else { return }
                if let baseline = self.baseline {
                    sender.setValue(baseline, animated: false)
                }
                self.restoring = false
            }
        }

        private static func findSlider(in view: UIView) -> UISlider? {
            if let slider = view as? UISlider { return slider }
            for sub in view.subviews {
                if let found = findSlider(in: sub) { return found }
            }
            return nil
        }
    }
}
