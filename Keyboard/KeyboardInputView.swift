import UIKit

/// Gives the host a deterministic height before any key pages have been laid out.
final class KeyboardInputView: UIInputView {
    weak var nearbyTouchTarget: UIButton?
    var contentHeight: CGFloat = KeyboardLayoutConfiguration.portrait.contentHeight {
        didSet {
            if contentHeight != oldValue { invalidateIntrinsicContentSize() }
        }
    }

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Keyboard input views are created in code") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
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
