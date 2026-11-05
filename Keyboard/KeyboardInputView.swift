import UIKit

/// Gives the host a deterministic height before any key pages have been laid out.
final class KeyboardInputView: UIInputView {
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
}
