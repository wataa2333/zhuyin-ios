import Foundation

protocol CompositionTextDocument {
    func setMarkedText(_ text: String, selectedRange: NSRange)
    func unmarkText()
    func insertText(_ text: String)
}

/// Replaces a host's marked range before committing it; never commits the raw reading first.
struct CompositionTextWriter {
    private(set) var markedText = ""

    mutating func reset() { markedText = "" }

    mutating func update(_ text: String, in document: CompositionTextDocument) {
        guard markedText != text else { return }
        markedText = text
        document.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        if text.isEmpty { document.unmarkText() }
    }

    mutating func commit(_ text: String, in document: CompositionTextDocument) {
        if markedText.isEmpty {
            document.insertText(text)
        } else {
            // Some hosts preserve the old reading when setMarkedText("") is followed by unmarkText().
            document.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
            document.unmarkText()
        }
        markedText = ""
    }
}
