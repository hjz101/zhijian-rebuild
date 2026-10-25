// PagedReaderView.swift — 原生 TextKit 分页渲染（UIPageViewController 横向翻页）
//
// - 每一页是一个只读 UITextView，显示分页引擎算好的 UTF-16 子串；
// - 左右滑动由 UIPageViewController 负责；点击左/右 1/3 翻页、中间 1/3 显示/隐藏控制层；
// - 章首/章尾额外提供一页"上一章 / 下一章"过渡页，继续滑动或点击即跨章。
import SwiftUI
import UIKit

struct PagedReaderView: UIViewControllerRepresentable {
    let pages: [ReaderPage]
    let currentIndex: Int
    let renderVersion: Int
    let theme: ReaderTheme
    let previousChapterTitle: String?
    let nextChapterTitle: String?
    let pageText: (Int) -> NSAttributedString
    let onPageChanged: (Int) -> Void
    let onNextPage: () -> Void
    let onPreviousPage: () -> Void
    let onChapterBoundary: (Int) -> Void
    let onToggleChrome: () -> Void
    var onHighlight: ((Int, Int, String) -> Void)? = nil
    var onNote: ((Int, Int, String) -> Void)? = nil
    var paragraphRanges: [NSRange] = []
    var commentCounts: [Int: Int] = [:]
    var onParagraphComment: ((Int) -> Void)? = nil
    var chapterCommentCount: Int = 0
    var onChapterComments: (() -> Void)? = nil
    /// iPad / 横屏双页：一屏两栏
    var twoPage: Bool = false
    /// 翻页动画
    var animation: ReadingSettings.PageTurnAnimation = .slide
    /// 点击正文图片
    var onImageTap: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let style: UIPageViewController.TransitionStyle = animation == .curl ? .pageCurl : .scroll
        let controller = UIPageViewController(
            transitionStyle: style,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 0]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .clear
        context.coordinator.attach(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize()
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PagedReaderView
        private weak var pageController: UIPageViewController?
        private var displayedIndex = 0
        private var displayedVersion = -1
        private var displayedPageCount = 0
        private var isReady = false

        init(_ parent: PagedReaderView) {
            self.parent = parent
        }

        func attach(_ controller: UIPageViewController) {
            pageController = controller
            isReady = true
            displayedIndex = normalize(parent.currentIndex)
            displayedVersion = parent.renderVersion
            displayedPageCount = parent.pages.count
            guard let page = makePage(displayedIndex) else { return }
            controller.setViewControllers([page], direction: .forward, animated: false, completion: nil)
        }

        /// 模型状态变化后，把当前页/页数/版本同步给 UIPageViewController。
        func synchronize() {
            guard isReady, let controller = pageController, !parent.pages.isEmpty else { return }
            let targetIndex = normalize(min(max(parent.currentIndex, 0), parent.pages.count - 1))
            let contentChanged = parent.renderVersion != displayedVersion || parent.pages.count != displayedPageCount
            let indexChanged = targetIndex != displayedIndex
            guard contentChanged || indexChanged else { return }
            guard let page = makePage(targetIndex) else { return }

            // 单页前后翻（点击翻页）用动画；换章、换字号、换主题直接重建。
            let step = parent.twoPage ? 2 : 1
            let animated = !contentChanged && abs(targetIndex - displayedIndex) == step
                && parent.animation != .none
            let direction: UIPageViewController.NavigationDirection = targetIndex >= displayedIndex ? .forward : .reverse
            displayedIndex = targetIndex
            displayedVersion = parent.renderVersion
            displayedPageCount = parent.pages.count

            if parent.animation == .fade && animated {
                UIView.transition(with: controller.view, duration: 0.18,
                                  options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    controller.setViewControllers([page], direction: direction, animated: false, completion: nil)
                }
            } else {
                controller.setViewControllers([page], direction: direction, animated: animated, completion: nil)
            }
        }

        // MARK: - 页面构建

        private func normalize(_ index: Int) -> Int {
            guard parent.twoPage else { return index }
            return max(0, index - (index % 2))
        }

        private func makePage(_ index: Int) -> UIViewController? {
            guard parent.pages.indices.contains(index) else { return nil }
            if parent.twoPage {
                return makeSpread(index)
            }
            let pageStart = parent.pages[index].range.location
            let controller = ReaderPageViewController(index: index, attributed: parent.pageText(index),
                                                     pageStart: pageStart, theme: parent.theme,
                                                     paragraphRanges: parent.paragraphRanges,
                                                     commentCounts: parent.commentCounts)
            controller.onParagraphComment = { [weak self] paragraphIndex in
                self?.parent.onParagraphComment?(paragraphIndex)
            }
            controller.onTap = { [weak self, weak controller] location in
                guard let self else { return }
                self.handleTap(location: location, width: controller?.view.bounds.width ?? 0)
            }
            controller.onImageTap = { [weak self] url in
                self?.parent.onImageTap?(url)
            }
            controller.onHighlight = { [weak self] range, text in
                guard let self else { return }
                self.parent.onHighlight?(pageStart + range.location, range.length, text)
            }
            controller.onNote = { [weak self] range, text in
                guard let self else { return }
                self.parent.onNote?(pageStart + range.location, range.length, text)
            }
            return controller
        }

        private func makeSpread(_ index: Int) -> UIViewController {
            let spread = ReaderSpreadViewController(theme: parent.theme)
            let indices = [index, index + 1].filter { parent.pages.indices.contains($0) }
            let gutter = ReaderViewModel.twoPageGutter
            var previous: UIView?
            for (position, pageIndex) in indices.enumerated() {
                let pageStart = parent.pages[pageIndex].range.location
                let page = ReaderPageViewController(index: pageIndex, attributed: parent.pageText(pageIndex),
                                                   pageStart: pageStart, theme: parent.theme,
                                                   paragraphRanges: parent.paragraphRanges,
                                                   commentCounts: parent.commentCounts)
                page.onParagraphComment = { [weak self] paragraphIndex in
                    self?.parent.onParagraphComment?(paragraphIndex)
                }
                page.onTap = { [weak self, weak page] location in
                    guard let self, let page else { return }
                    self.handleTap(location: location, width: page.view.bounds.width)
                }
                page.onImageTap = { [weak self] url in
                    self?.parent.onImageTap?(url)
                }
                page.onHighlight = { [weak self] range, text in
                    guard let self else { return }
                    self.parent.onHighlight?(pageStart + range.location, range.length, text)
                }
                page.onNote = { [weak self] range, text in
                    guard let self else { return }
                    self.parent.onNote?(pageStart + range.location, range.length, text)
                }
                spread.addChild(page)
                spread.stack.addArrangedSubview(page.view)
                page.view.translatesAutoresizingMaskIntoConstraints = false
                if position == 1 {
                    page.view.widthAnchor.constraint(equalTo: spread.stack.arrangedSubviews[0].widthAnchor).isActive = true
                }
                page.didMove(toParent: spread)
                previous = page.view
            }
            if indices.count == 1 {
                let spacer = UIView()
                spacer.backgroundColor = .clear
                spread.stack.addArrangedSubview(spacer)
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalTo: spread.stack.arrangedSubviews[0].widthAnchor).isActive = true
            }
            spread.stack.spacing = gutter
            _ = previous
            return spread
        }

        private func makeGate(isNext: Bool) -> UIViewController {
            let title = (isNext ? parent.nextChapterTitle : parent.previousChapterTitle) ?? ""
            let gate = ReaderChapterGateViewController(isNext: isNext, title: title, theme: parent.theme)
            gate.onTap = { [weak self] in
                guard let self else { return }
                self.parent.onChapterBoundary(isNext ? 1 : -1)
            }
            gate.onComments = { [weak self] in
                self?.parent.onChapterComments?()
            }
            gate.commentCount = parent.chapterCommentCount
            return gate
        }

        private func handleTap(location: CGPoint, width: CGFloat) {
            let width = max(width, 1)
            if location.x < width / 3 {
                parent.onPreviousPage()
            } else if location.x > width * 2 / 3 {
                parent.onNextPage()
            } else {
                parent.onToggleChrome()
            }
        }

        // MARK: - UIPageViewControllerDataSource

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            if let page = viewController as? ReaderPageViewController {
                let step = parent.twoPage ? 2 : 1
                if page.pageIndex - step >= 0 {
                    return makePage(page.pageIndex - step)
                }
                if parent.previousChapterTitle != nil {
                    return makeGate(isNext: false)
                }
                return nil
            }
            if let gate = viewController as? ReaderChapterGateViewController, gate.isNext {
                return makePage(normalize(parent.pages.count - 1))
            }
            return nil
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            if let page = viewController as? ReaderPageViewController {
                let step = parent.twoPage ? 2 : 1
                if page.pageIndex + step < parent.pages.count {
                    return makePage(page.pageIndex + step)
                }
                if parent.nextChapterTitle != nil {
                    return makeGate(isNext: true)
                }
                return nil
            }
            if let gate = viewController as? ReaderChapterGateViewController, !gate.isNext {
                return makePage(0)
            }
            return nil
        }

        // MARK: - UIPageViewControllerDelegate

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed, let visible = pageViewController.viewControllers?.first else { return }
            if let page = visible as? ReaderPageViewController {
                let index = normalize(page.pageIndex)
                displayedIndex = index
                parent.onPageChanged(index)
            } else if let gate = visible as? ReaderChapterGateViewController {
                parent.onChapterBoundary(gate.isNext ? 1 : -1)
            }
        }
    }
}

// MARK: - 双页容器

private final class ReaderSpreadViewController: UIViewController {
    let stack = UIStackView()
    private let theme: ReaderTheme

    init(theme: ReaderTheme) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - 单页正文

private final class ReaderPageViewController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    let pageIndex: Int
    private let attributed: NSAttributedString
    private let pageStart: Int
    private let theme: ReaderTheme
    private let paragraphRanges: [NSRange]
    private let commentCounts: [Int: Int]
    private let textView = UITextView()
    private var bubbleButtons: [UIButton] = []
    var onTap: ((CGPoint) -> Void)?
    var onImageTap: ((String) -> Void)?
    var onHighlight: ((NSRange, String) -> Void)?
    var onNote: ((NSRange, String) -> Void)?
    var onParagraphComment: ((Int) -> Void)?

    init(index: Int, attributed: NSAttributedString, pageStart: Int, theme: ReaderTheme,
         paragraphRanges: [NSRange] = [], commentCounts: [Int: Int] = [:]) {
        self.pageIndex = index
        self.attributed = attributed
        self.pageStart = pageStart
        self.theme = theme
        self.paragraphRanges = paragraphRanges
        self.commentCounts = commentCounts
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 背景由 SwiftUI 层（含背景图）负责，这里保持透明
        view.backgroundColor = .clear

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = true
        textView.delegate = self
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.attributedText = attributed
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCommentBubbles()
    }

    private func layoutCommentBubbles() {
        bubbleButtons.forEach { $0.removeFromSuperview() }
        bubbleButtons.removeAll()
        guard !paragraphRanges.isEmpty, !commentCounts.isEmpty,
              attributed.length > 0, textView.bounds.width > 0 else { return }
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let pageEnd = pageStart + attributed.length

        for (index, fullRange) in paragraphRanges.enumerated() {
            guard let count = commentCounts[index], count > 0 else { continue }
            let overlap = NSIntersectionRange(fullRange, NSRange(location: pageStart, length: attributed.length))
            guard overlap.length > 0 else { continue }
            let local = NSRange(location: overlap.location - pageStart, length: overlap.length)
            guard local.location >= 0, local.location + local.length <= attributed.length else { continue }
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: local, actualCharacterRange: nil)
            var rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            let size = CGSize(width: 58, height: 24)
            var origin = CGPoint(x: textView.bounds.width - size.width - 2, y: rect.maxY - size.height + 2)
            if origin.y < 0 || origin.y > textView.bounds.height - size.height { continue }
            origin.y = max(0, min(origin.y, textView.bounds.height - size.height))

            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor(theme.accent).withAlphaComponent(0.16)
            config.baseForegroundColor = UIColor(theme.accent)
            config.cornerStyle = .capsule
            config.title = "💬 \(count)"
            config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            let button = UIButton(configuration: config)
            button.frame = CGRect(origin: origin, size: size)
            button.addAction(UIAction { [weak self] _ in self?.onParagraphComment?(index) }, for: .touchUpInside)
            view.addSubview(button)
            bubbleButtons.append(button)
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if textView.selectedRange.length > 0 {
            textView.selectedRange = NSRange(location: 0, length: 0)
            return
        }
        let point = gesture.location(in: textView)
        if let url = imageURL(at: point) {
            onImageTap?(url)
            return
        }
        onTap?(gesture.location(in: view))
    }

    /// 命中图片附件时返回其 URL。
    private func imageURL(at point: CGPoint) -> String? {
        let containerPoint = CGPoint(x: point.x - textView.textContainerInset.left,
                                     y: point.y - textView.textContainerInset.top)
        let index = textView.layoutManager.characterIndex(for: containerPoint,
                                                          in: textView.textContainer,
                                                          fractionOfDistanceBetweenInsertionPoints: nil)
        guard index >= 0, index < textView.attributedText.length else { return nil }
        return textView.attributedText.attribute(.readerImageURL, at: index, effectiveRange: nil) as? String
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // iOS 16+：自定义文本选择菜单
    func textView(_ textView: UITextView,
                  editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.length > 0,
              let textRange = Range(range, in: textView.text) else { return nil }
        let selected = String(textView.text[textRange])
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var actions = suggestedActions
        actions.append(UIAction(title: "划线", image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.onHighlight?(range, selected)
            textView.selectedRange = NSRange(location: 0, length: 0)
        })
        actions.append(UIAction(title: "笔记", image: UIImage(systemName: "note.text")) { [weak self] _ in
            self?.onNote?(range, selected)
            textView.selectedRange = NSRange(location: 0, length: 0)
        })
        return UIMenu(children: actions)
    }
}

// MARK: - 章间过渡页

private final class ReaderChapterGateViewController: UIViewController {
    let isNext: Bool
    private let chapterTitle: String
    private let theme: ReaderTheme
    var onTap: (() -> Void)?
    var onComments: (() -> Void)?
    var commentCount: Int = 0

    init(isNext: Bool, title: String, theme: ReaderTheme) {
        self.isNext = isNext
        self.chapterTitle = title
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let icon = UIImageView(image: UIImage(systemName: isNext ? "chevron.right.2" : "chevron.left.2"))
        icon.tintColor = UIColor(theme.accent)
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let kicker = UILabel()
        kicker.text = isNext ? "下一章" : "上一章"
        kicker.font = .systemFont(ofSize: 11, weight: .semibold)
        kicker.textColor = UIColor(theme.secondary)
        kicker.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = chapterTitle
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = UIColor(theme.text)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let hint = UILabel()
        hint.text = isNext ? "继续左滑进入下一章" : "继续右滑返回上一章"
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = UIColor(theme.secondary)
        hint.textAlignment = .center

        let commentButton = UIButton(type: .system)
        commentButton.setTitle("章末评论 \(commentCount)", for: .normal)
        commentButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        commentButton.tintColor = UIColor(theme.accent)
        commentButton.addAction(UIAction { [weak self] _ in self?.onComments?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, kicker, titleLabel, hint, commentButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onTap?()
    }
}
