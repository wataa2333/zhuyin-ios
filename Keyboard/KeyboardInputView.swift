import UIKit

/// Gives the host a deterministic height before any key pages have been laid out.
final class KeyboardInputView: UIInputView {
    weak var nearbyTouchTarget: UIButton?
    /// Fixed content bounds, independent of the host's transient presentation height.
    let contentLayoutGuide = UILayoutGuide()
    private lazy var contentHeightConstraint = contentLayoutGuide.heightAnchor.constraint(equalToConstant: contentHeight)
    private lazy var requestedHeightConstraint = heightAnchor.constraint(equalToConstant: intrinsicContentSize.height)
    var contentHeight: CGFloat = KeyboardLayoutConfiguration.defaults.contentHeight {
        didSet {
            guard contentHeight != oldValue else { return }
            contentHeightConstraint.constant = contentHeight
            updateHeightRequest()
        }
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        // Let UIKit honor our explicit fixed height; no host size or safe-area height is measured.
        allowsSelfSizing = true
        addLayoutGuide(contentLayoutGuide)
        requestedHeightConstraint.identifier = "Keyboard.requestedHeight"
        NSLayoutConstraint.activate([
            contentLayoutGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            contentLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            contentHeightConstraint,
            requestedHeightConstraint
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Keyboard input views are created in code") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        CGSize(width: targetSize.width, height: contentHeight)
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                         verticalFittingPriority: UILayoutPriority) -> CGSize {
        CGSize(width: targetSize.width, height: contentHeight)
    }

    private func updateHeightRequest() {
        let height = intrinsicContentSize.height
        guard requestedHeightConstraint.constant != height else { return }
        requestedHeightConstraint.constant = height
        invalidateIntrinsicContentSize()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let original = super.hitTest(point, with: event) else { return nil }
        guard bounds.contains(point), let target = nearbyTouchTarget,
              !target.isHidden, target.isEnabled, target.isUserInteractionEnabled,
              target.point(inside: target.convert(point, from: self), with: event) else { return original }
        // Respect the normal hit result first. Never steal a candidate or another key's touch.
        var current: UIView? = original
        while let view = current, view !== self {
            if view === target { return original }
            if view is UIControl { return original }
            current = view.superview
        }
        return target
    }
}

final class NearbyTouchButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -24, dy: -14).contains(point)
    }
}
