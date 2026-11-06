import Foundation

/// All vertical dimensions come from this file-backed profile, never from host measurements.
struct KeyboardLayoutConfiguration: Codable, Equatable, Sendable {
    static let defaults = Self()
    static let dividerHeight: CGFloat = 22
    static let dividerWidth: CGFloat = 1.25
    static let candidateSeparatorPadding: CGFloat = 8
    static let candidateToggleWidth: CGFloat = 64

    var candidateBarHeight: CGFloat = 44
    var keyHeight: CGFloat = 42
    var rowSpacing: CGFloat = 9
    var topInset: CGFloat = 17
    var toolbarSpacing: CGFloat = 2
    var bottomInset: CGFloat = 0

    var keyAreaHeight: CGFloat { 4 * keyHeight + 3 * rowSpacing }
    var candidateToggleTouchHeight: CGFloat { topInset + candidateBarHeight + toolbarSpacing }
    var candidatePanelHeight: CGFloat { candidateBarHeight + toolbarSpacing + keyAreaHeight }
    var contentHeight: CGFloat { topInset + candidatePanelHeight + bottomInset }

    var isValid: Bool {
        (40...80).contains(candidateBarHeight) && (32...60).contains(keyHeight)
            && (0...16).contains(rowSpacing) && (0...30).contains(topInset)
            && (0...12).contains(toolbarSpacing) && (0...40).contains(bottomInset)
    }
}

enum KeyboardLayoutFile {
    static let name = "keyboard-layout.json"

    static func read(from url: URL) -> KeyboardLayoutConfiguration? {
        guard let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(KeyboardLayoutConfiguration.self, from: data),
              layout.isValid else { return nil }
        return layout
    }

    static func save(_ layout: KeyboardLayoutConfiguration, to url: URL) throws {
        guard layout.isValid else { throw CocoaError(.coderInvalidValue) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
