import UIKit

struct KeyPreviewGeometry {
    let frame: CGRect
    let head: CGRect
    let keyBody: CGRect

    /// One closed contour avoids winding cancellation between overlapping head/neck/body paths.
    var outline: UIBezierPath {
        let headRadius: CGFloat = 10
        let bodyRadius = min(9, min(keyBody.width, keyBody.height) / 2)
        let shoulderY = head.maxY - headRadius
        // Top-row heads can overlap the key. Keep a short, smooth waist in that case too.
        let joinY = min(keyBody.maxY - bodyRadius, max(head.maxY + 6, keyBody.minY + 1))
        let bend = (joinY - shoulderY) / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: headRadius, y: head.minY))
        path.addLine(to: CGPoint(x: head.maxX - headRadius, y: head.minY))
        path.addQuadCurve(to: CGPoint(x: head.maxX, y: head.minY + headRadius),
                          controlPoint: CGPoint(x: head.maxX, y: head.minY))
        path.addLine(to: CGPoint(x: head.maxX, y: shoulderY))
        path.addCurve(to: CGPoint(x: keyBody.maxX, y: joinY),
                      controlPoint1: CGPoint(x: head.maxX, y: shoulderY + bend),
                      controlPoint2: CGPoint(x: keyBody.maxX, y: joinY - bend))
        path.addLine(to: CGPoint(x: keyBody.maxX, y: keyBody.maxY - bodyRadius))
        path.addQuadCurve(to: CGPoint(x: keyBody.maxX - bodyRadius, y: keyBody.maxY),
                          controlPoint: CGPoint(x: keyBody.maxX, y: keyBody.maxY))
        path.addLine(to: CGPoint(x: keyBody.minX + bodyRadius, y: keyBody.maxY))
        path.addQuadCurve(to: CGPoint(x: keyBody.minX, y: keyBody.maxY - bodyRadius),
                          controlPoint: CGPoint(x: keyBody.minX, y: keyBody.maxY))
        path.addLine(to: CGPoint(x: keyBody.minX, y: joinY))
        path.addCurve(to: CGPoint(x: head.minX, y: shoulderY),
                      controlPoint1: CGPoint(x: keyBody.minX, y: joinY - bend),
                      controlPoint2: CGPoint(x: head.minX, y: shoulderY + bend))
        path.addLine(to: CGPoint(x: head.minX, y: head.minY + headRadius))
        path.addQuadCurve(to: CGPoint(x: headRadius, y: head.minY),
                          controlPoint: CGPoint(x: head.minX, y: head.minY))
        path.close()
        return path
    }

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
        let path = geometry.outline
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
