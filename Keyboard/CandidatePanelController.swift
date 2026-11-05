import UIKit

/// Owns presentation only. Candidate lookup and layout never change the requested state.
@MainActor
final class CandidatePanelController {
    private let keyboard: UIView
    private let candidates: UIView
    private let toggle: UIButton
    private var animator: UIViewPropertyAnimator?
    private var revision = 0
    private(set) var isExpanded = false
    var onToggleRequested: (() -> Void)?

    init(keyboard: UIView, candidates: UIView, toggle: UIButton) {
        self.keyboard = keyboard
        self.candidates = candidates
        self.toggle = toggle
        toggle.addAction(UIAction { [weak self] _ in
            self?.onToggleRequested?()
        }, for: .primaryActionTriggered)
        settle()
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        // Refreshing the same state must not restart a transition.
        guard expanded != isExpanded || !animated else { return }
        revision += 1
        let currentRevision = revision
        if let animator {
            // Preserve the current appearance when a second tap reverses the transition.
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
            self.animator = nil
        }
        isExpanded = expanded
        keyboard.isUserInteractionEnabled = !expanded
        candidates.isUserInteractionEnabled = expanded
        keyboard.accessibilityElementsHidden = expanded
        candidates.accessibilityElementsHidden = !expanded
        toggle.accessibilityLabel = expanded ? "收起候选字词" : "展开候选字词"

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            settle()
            return
        }
        keyboard.isHidden = false
        candidates.isHidden = false
        let animator = UIViewPropertyAnimator(duration: 0.16, curve: .easeInOut) {
            self.keyboard.alpha = expanded ? 0 : 1
            self.candidates.alpha = expanded ? 1 : 0
            self.toggle.imageView?.transform = expanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        }
        animator.isUserInteractionEnabled = true
        animator.addCompletion { [weak self] _ in
            guard let self, self.revision == currentRevision else { return }
            self.animator = nil
            self.settle()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func settle() {
        keyboard.isHidden = isExpanded
        keyboard.alpha = isExpanded ? 0 : 1
        keyboard.isUserInteractionEnabled = !isExpanded
        keyboard.accessibilityElementsHidden = isExpanded
        candidates.isHidden = !isExpanded
        candidates.alpha = isExpanded ? 1 : 0
        candidates.isUserInteractionEnabled = isExpanded
        candidates.accessibilityElementsHidden = !isExpanded
        toggle.imageView?.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        toggle.accessibilityLabel = isExpanded ? "收起候选字词" : "展开候选字词"
    }
}
