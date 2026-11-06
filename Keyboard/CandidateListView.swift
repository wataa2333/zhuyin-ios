import UIKit

/// One set of buttons for both the horizontal strip and the expanded, vertically scrolling list.
final class CandidateListView: UIScrollView {
    private let font = UIFont.systemFont(ofSize: 19)
    private let viewportMask = CAShapeLayer()
    private var maskedBounds = CGRect.null
    private var buttons: [CandidateButton] = []
    private var widths: [CGFloat] = []
    private var firstRowWidth: CGFloat = 0
    var candidateBarHeight: CGFloat = KeyboardLayoutConfiguration.defaults.candidateBarHeight {
        didSet {
            guard candidateBarHeight != oldValue else { return }
            maskedBounds = .null
            applyLayout()
            setNeedsLayout()
        }
    }
    private(set) var isExpanded = false
    var onSelect: ((Int) -> Void)?
    var hasOverflow: Bool { firstRowWidth > 0 && widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) > firstRowWidth }

    func releaseCachedContent() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        widths.removeAll()
        setContentOffset(.zero, animated: false)
        contentSize = .zero
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        delaysContentTouches = false
        canCancelContentTouches = true
        isDirectionalLockEnabled = true
        panGestureRecognizer.cancelsTouchesInView = true
        scrollsToTop = false
        viewportMask.fillRule = .evenOdd
        layer.mask = viewportMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Candidate lists are created in code") }

    func update(titles: [String], highlightsFirst: Bool) {
        widths = titles.map { max(38, ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 12) }
        for (index, title) in titles.enumerated() {
            if index == buttons.count {
                let button = CandidateButton(type: .custom)
                button.titleLabel?.font = font
                button.titleLabel?.lineBreakMode = .byTruncatingTail
                button.setTitleColor(.label, for: .normal)
                button.setTitleColor(.label, for: .highlighted)
                button.layer.cornerRadius = 8
                button.addAction(UIAction { [weak self, weak button] _ in
                    guard let button else { return }
                    self?.onSelect?(button.tag)
                }, for: .touchUpInside)
                buttons.append(button)
                addSubview(button)
            }
            let button = buttons[index]
            button.tag = index
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = title
            button.isHighlighted = false
            button.isPrimaryCandidate = index == 0 && highlightsFirst
            button.isHidden = false
        }
        for button in buttons.dropFirst(titles.count) { button.isHidden = true }
        setContentOffset(.zero, animated: false)
        applyLayout()
    }

    func updateViewport(firstRowWidth width: CGFloat) {
        let width = max(0, min(bounds.width, width))
        guard width != firstRowWidth || layoutWidth != bounds.width else { return }
        firstRowWidth = width
        maskedBounds = .null
        setNeedsLayout()
        applyLayout()
    }

    /// Rebase the current visual positions before changing scroll direction or reversing an animation.
    func prepareTransition(expanded: Bool) {
        let offset = contentOffset
        setContentOffset(.zero, animated: false)
        for button in buttons {
            button.isHighlighted = false
            button.frame = button.frame.offsetBy(dx: -offset.x, dy: -offset.y)
        }
        isExpanded = expanded
        showsVerticalScrollIndicator = expanded
    }

    private var layoutWidth: CGFloat = 0

    func applyLayout() {
        maskedBounds = .null
        setNeedsLayout()
        layoutWidth = bounds.width
        guard layoutWidth > 0, firstRowWidth > 0 else { return }
        let rowHeight = candidateBarHeight - 4
        let rowPitch = candidateBarHeight
        var x: CGFloat = 0
        var y: CGFloat = 0
        for (index, intrinsicWidth) in widths.enumerated() {
            if isExpanded {
                let capacity = y == 0 ? firstRowWidth : layoutWidth
                // A word clipped at the strip's trailing edge moves, as the same button, to row two.
                if x > 0 && x + intrinsicWidth > capacity || y == 0 && intrinsicWidth > capacity {
                    x = 0
                    y += rowPitch
                }
            }
            let width = min(intrinsicWidth, isExpanded && y > 0 ? layoutWidth : firstRowWidth)
            buttons[index].frame = CGRect(x: x, y: y, width: width, height: rowHeight)
            x += width + (isExpanded ? 4 : 1)
        }
        contentSize = isExpanded
            ? CGSize(width: layoutWidth, height: widths.isEmpty ? 0 : y + rowHeight)
            : CGSize(width: max(0, x - 1) + layoutWidth - firstRowWidth, height: candidateBarHeight)
        updateBounce()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Scrolling changes bounds.origin every frame. It must never reconfigure or lay out the words.
        updateBounce()
        guard maskedBounds != bounds else { return }
        maskedBounds = bounds
        let rect = CGRect(origin: .zero, size: bounds.size)
        let path = UIBezierPath(rect: rect)
        let headerWidth = visibleHeaderWidth
        path.append(UIBezierPath(rect: CGRect(x: headerWidth, y: 0,
            width: max(0, rect.width - headerWidth), height: candidateBarHeight)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        viewportMask.frame = bounds
        viewportMask.path = path.cgPath
        CATransaction.commit()
    }

    private var visibleHeaderWidth: CGFloat {
        guard !isExpanded, !widths.isEmpty else { return firstRowWidth }
        // The trailing word is either fully visible or moves to the expanded list; never cut a glyph.
        // Frames are ordered in strip mode, so scrolling needs only a binary search, not a cell walk.
        let end = bounds.minX + firstRowWidth
        var low = 0
        var high = widths.count
        while low < high {
            let middle = (low + high) / 2
            if buttons[middle].frame.maxX <= end { low = middle + 1 }
            else { high = middle }
        }
        guard low > 0 else { return 0 }
        return max(0, min(firstRowWidth, buttons[low - 1].frame.maxX - bounds.minX))
    }

    private func updateBounce() {
        alwaysBounceVertical = isExpanded && contentSize.height > bounds.height
        alwaysBounceHorizontal = !isExpanded && hasOverflow
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let viewportPoint = CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        if viewportPoint.y < candidateBarHeight && viewportPoint.x >= visibleHeaderWidth { return false }
        return super.point(inside: point, with: event)
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        // Every subview is a candidate control: a drag always takes priority over its pending tap.
        true
    }
}

final class CandidateButton: UIButton {
    var isPrimaryCandidate = false { didSet { updatePressAppearance() } }

    override var isHighlighted: Bool { didSet { updatePressAppearance() } }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        isHighlighted = false
    }

    private func updatePressAppearance() {
        // A cell-sized rounded press indicator; no pop-up or animation delays scrolling.
        backgroundColor = isHighlighted ? .systemGray3 : (isPrimaryCandidate ? .secondarySystemGroupedBackground : .clear)
    }
}
