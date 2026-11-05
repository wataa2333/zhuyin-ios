import UIKit

struct KeyPreviewGeometry {
    let frame: CGRect
    let head: CGRect
    let keyBody: CGRect
    let anchorLeft: CGPoint
    let anchorRight: CGPoint

    init(key: CGRect, viewport: CGRect, compact: Bool) {
        let width = min(max(0, viewport.width - 4), max(compact ? 48 : 56, key.width + 20))
        let headHeight = key.height + 10
        let neckHeight: CGFloat = compact ? 10 : 15
        let x = min(max(viewport.minX + 2, key.midX - width / 2), viewport.maxX - width - 2)
        // The root-keyboard edge limits top-row previews. Keep the head full-sized and overlap
        // the pressed key's upper portion rather than pushing the text down to the next row.
        let y = max(viewport.minY + 2, key.minY - headHeight - neckHeight + 1)
        frame = CGRect(x: x, y: y, width: width, height: max(headHeight + neckHeight, key.maxY - y))
        head = CGRect(x: 0, y: 0, width: width, height: headHeight)
        keyBody = key.offsetBy(dx: -x, dy: -y)
        anchorLeft = CGPoint(x: max(0, key.minX - x), y: headHeight + neckHeight)
        anchorRight = CGPoint(x: min(width, key.maxX - x), y: headHeight + neckHeight)
    }
}

/// A reusable head-and-neck preview anchored to the key that received touch-down.
final class KeyPreviewView: UIView {
    private let shape = CAShapeLayer()
    private let title = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        layer.addSublayer(shape)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: 1)
        title.font = .systemFont(ofSize: 32)
        title.textAlignment = .center
        title.textColor = .label
        title.isAccessibilityElement = false
        addSubview(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Key previews are created in code") }

    func show(_ text: String, key: CGRect, viewport: CGRect, compact: Bool) {
        let geometry = KeyPreviewGeometry(key: key, viewport: viewport, compact: compact)
        let path = UIBezierPath(roundedRect: geometry.head, cornerRadius: 10)
        let neck = UIBezierPath()
        let left = CGPoint(x: 5, y: geometry.head.maxY - 8)
        let right = CGPoint(x: geometry.head.maxX - 5, y: left.y)
        neck.move(to: left)
        neck.addCurve(to: geometry.anchorLeft,
            controlPoint1: CGPoint(x: left.x, y: geometry.head.maxY + 4),
            controlPoint2: CGPoint(x: geometry.anchorLeft.x, y: geometry.anchorLeft.y - 8))
        neck.addLine(to: geometry.anchorRight)
        neck.addCurve(to: right,
            controlPoint1: CGPoint(x: geometry.anchorRight.x, y: geometry.anchorRight.y - 8),
            controlPoint2: CGPoint(x: right.x, y: geometry.head.maxY + 4))
        neck.close()
        path.append(neck)
        // Cover the source key as well, including when touch-down immediately changes key pages.
        path.append(UIBezierPath(roundedRect: geometry.keyBody, cornerRadius: 9))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = geometry.frame
        shape.frame = bounds
        shape.path = path.cgPath
        let color: UIColor = traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.36, alpha: 1) : .white
        shape.fillColor = color.cgColor
        layer.shadowPath = path.cgPath
        title.frame = geometry.head.insetBy(dx: 4, dy: 0)
        title.text = text
        isHidden = false
        CATransaction.commit()
    }
}
