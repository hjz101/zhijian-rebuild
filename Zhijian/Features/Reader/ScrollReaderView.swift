// ScrollReaderView.swift — 滚动阅读模式（P0：整章 UITextView 上下滚动）
//
// 分页模式用原生 TextKit 切页；滚动模式保留为最简单的整章 UITextView，
// 只上报滚动比例用于进度写回，轻点任意位置显示/隐藏控制层。
import SwiftUI
import UIKit

struct ScrollReaderView: UIViewRepresentable {
    let attributed: NSAttributedString
    /// 章节 + 排版版本；变化时重置滚动位置（用于恢复比例）。
    let resetKey: String
    let renderVersion: Int
    let initialRatio: Double
    let onProgress: (Double) -> Void
    let onToggleChrome: () -> Void
    var ttsHighlightRange: NSRange? = nil
    var onHighlight: ((Int, Int, String) -> Void)? = nil
    var onNote: ((Int, Int, String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 28, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(
            to: textView,
            attributed: attributed,
            resetKey: resetKey,
            renderVersion: renderVersion,
            initialRatio: initialRatio
        )
        context.coordinator.applyTTSHighlight(ttsHighlightRange, in: textView, base: attributed)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ScrollReaderView
        private var currentResetKey: String?
        private var currentRenderVersion = -1
        private var lastReport = Date.distantPast
        private var ignoreProgressUntil = Date.distantPast
        private var lastTTSRange: NSRange?

        init(_ parent: ScrollReaderView) {
            self.parent = parent
        }

        func apply(
            to textView: UITextView,
            attributed: NSAttributedString,
            resetKey: String,
            renderVersion: Int,
            initialRatio: Double
        ) {
            let resetChanged = currentResetKey != resetKey
            let renderChanged = currentRenderVersion != renderVersion
            guard resetChanged || renderChanged else { return }

            let ratio = resetChanged ? Self.clamp(initialRatio) : currentRatio(of: textView)
            currentResetKey = resetKey
            currentRenderVersion = renderVersion
            ignoreProgressUntil = Date().addingTimeInterval(0.2)
            // 复用 textStorage 避免整章重建（长章滚动更稳）
            textView.textStorage.setAttributedString(attributed)
            lastTTSRange = nil
            restore(offsetRatio: ratio, in: textView)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selected = textView.selectedRange
            guard selected.length > 0, let text = textView.text,
                  let swiftRange = Range(selected, in: text) else { return nil }
            let value = String(text[swiftRange])
            let highlight = UIAction(title: "划线", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                self?.parent.onHighlight?(selected.location, selected.length, value)
            }
            let note = UIAction(title: "笔记", image: UIImage(systemName: "note.text")) { [weak self] _ in
                self?.parent.onNote?(selected.location, selected.length, value)
            }
            return UIMenu(children: [highlight, note] + suggestedActions)
        }

        func applyTTSHighlight(_ range: NSRange?, in textView: UITextView, base: NSAttributedString) {
            guard range != lastTTSRange else { return }
            lastTTSRange = range
            let offset = textView.contentOffset
            let mutable = NSMutableAttributedString(attributedString: base)
            if let range, range.location != NSNotFound, range.length > 0,
               range.location >= 0, range.location + range.length <= mutable.length {
                mutable.addAttribute(.backgroundColor,
                                     value: UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 0.36),
                                     range: range)
            }
            textView.textStorage.setAttributedString(mutable)
            textView.setContentOffset(offset, animated: false)
            if let range, range.location != NSNotFound, range.length > 0,
               range.location + range.length <= textView.textStorage.length {
                textView.scrollRangeToVisible(range)
            }
        }

        private func restore(offsetRatio: Double, in textView: UITextView) {
            let ratio = Self.clamp(offsetRatio)
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.layoutIfNeeded()
                let top = textView.adjustedContentInset.top
                let bottom = textView.adjustedContentInset.bottom
                let minY = -top
                let maxY = max(textView.contentSize.height - textView.bounds.height + bottom, minY)
                let y = minY + (maxY - minY) * ratio
                textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onToggleChrome()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard Date() >= ignoreProgressUntil else { return }
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.12 else { return }
            lastReport = now
            parent.onProgress(currentRatio(of: scrollView))
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { reportNow(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportNow(scrollView)
        }

        private func reportNow(_ scrollView: UIScrollView) {
            guard Date() >= ignoreProgressUntil else { return }
            lastReport = Date()
            parent.onProgress(currentRatio(of: scrollView))
        }

        private func currentRatio(of scrollView: UIScrollView) -> Double {
            let top = scrollView.adjustedContentInset.top
            let bottom = scrollView.adjustedContentInset.bottom
            let minY = -top
            let maxY = max(scrollView.contentSize.height - scrollView.bounds.height + bottom, minY)
            let range = maxY - minY
            guard range > 1 else { return 0 }
            let offset = scrollView.contentOffset.y - minY
            return Self.clamp(Double(offset / range))
        }

        private static func clamp(_ value: Double) -> Double {
            min(max(value, 0), 1)
        }
    }
}
