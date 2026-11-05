import UIKit

/// Owns presentation only. Candidate lookup and layout never change the requested state.
@MainActor
final class CandidatePanelController {
    private let keyboard: UIView
    private let candidates: UIView
    private let toggle: UIButton
    private let keepsCandidatesVisible: Bool
    private var animator: UIViewPropertyAnimator?
    private var revision = 0
    private(set) var isExpanded = false
    var onToggleRequested: (() -> Void)?
    var prepareTransition: ((Bool) -> Void)?
    var animateTransition: ((Bool) -> Void)?

    init(keyboard: UIView, candidates: UIView, toggle: UIButton, keepsCandidatesVisible: Bool = false) {
        self.keyboard = keyboard
        self.candidates = candidates
        self.toggle = toggle
        self.keepsCandidatesVisible = keepsCandidatesVisible
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
        prepareTransition?(expanded)
        isExpanded = expanded
        keyboard.isUserInteractionEnabled = !expanded
        candidates.isUserInteractionEnabled = expanded || keepsCandidatesVisible
        keyboard.accessibilityElementsHidden = expanded
        candidates.accessibilityElementsHidden = !expanded && !keepsCandidatesVisible
        toggle.accessibilityLabel = expanded ? "收起候选字词" : "展开候选字词"

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            animateTransition?(expanded)
            settle()
            return
        }
        keyboard.isHidden = false
        candidates.isHidden = false
        let animator = UIViewPropertyAnimator(duration: 0.16, curve: .easeInOut) {
            self.keyboard.alpha = expanded ? 0 : 1
            self.candidates.alpha = expanded || self.keepsCandidatesVisible ? 1 : 0
            self.toggle.imageView?.transform = expanded ? CGAffineTransform(rotationAngle: .pi) : .identity
            self.animateTransition?(expanded)
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
        candidates.isHidden = !isExpanded && !keepsCandidatesVisible
        candidates.alpha = isExpanded || keepsCandidatesVisible ? 1 : 0
        candidates.isUserInteractionEnabled = isExpanded || keepsCandidatesVisible
        candidates.accessibilityElementsHidden = !isExpanded && !keepsCandidatesVisible
        toggle.imageView?.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        toggle.accessibilityLabel = isExpanded ? "收起候选字词" : "展开候选字词"
    }
}
