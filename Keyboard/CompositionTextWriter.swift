import Foundation

protocol CompositionTextDocument {
    func setMarkedText(_ text: String, selectedRange: NSRange)
    func unmarkText()
    func insertText(_ text: String)
}

/// Keeps selected segments and pending reading in one marked range until selection is complete.
struct CompositionTextWriter {
    private(set) var markedText = ""
    private(set) var selectedText = ""

    mutating func reset() {
        markedText = ""
        selectedText = ""
    }

    mutating func update(_ reading: String, in document: CompositionTextDocument) {
        if reading.isEmpty, !selectedText.isEmpty {
            // Deleting the remaining reading also finishes the already selected Chinese prefix.
            commit("", in: document)
            return
        }
        let text = selectedText + reading
        guard markedText != text else { return }
        markedText = text
        document.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        if text.isEmpty { document.unmarkText() }
    }

    mutating func select(_ text: String, remainingReading: String, in document: CompositionTextDocument) {
        selectedText += text
        // A partial choice only updates the existing range; it must not unmark and reopen it.
        update(remainingReading, in: document)
    }

    mutating func commit(_ text: String, in document: CompositionTextDocument) {
        let result = selectedText + text
        if markedText.isEmpty {
            document.insertText(result)
        } else {
            document.setMarkedText(result, selectedRange: NSRange(location: result.utf16.count, length: 0))
            document.unmarkText()
        }
        markedText = ""
        selectedText = ""
    }
}
