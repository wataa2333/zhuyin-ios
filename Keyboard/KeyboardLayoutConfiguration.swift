import UIKit

struct KeyboardLayoutConfiguration: Equatable {
    static let candidateBarHeight: CGFloat = 44
    static let dividerHeight: CGFloat = 22
    static let topInset: CGFloat = 1
    static let toolbarSpacing: CGFloat = 2
    static let portrait = Self(keyHeight: 42, rowSpacing: 9)
    static let compact = Self(keyHeight: 32, rowSpacing: 6)

    let keyHeight: CGFloat
    let rowSpacing: CGFloat
    var keyAreaHeight: CGFloat { 4 * keyHeight + 3 * rowSpacing }
    var contentHeight: CGFloat {
        Self.topInset + Self.candidateBarHeight + Self.toolbarSpacing + keyAreaHeight
    }
}
