import SwiftUI
import UIKit

struct KeyboardApplySheet: View {
    let code: String
    var onResult: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var result: Bool?
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("键盘出现后，长按地球键切到「简体注音」，设置会自动传入。")
                    KeyboardSyncField(code: code, autoFocus: true, attempt: attempt, onReply: {
                        result = $0
                        onResult($0)
                    })
                        .frame(height: 44)
                        .overlay {
                            Label(result == true ? "键盘已接收并保存" : "点此打开键盘", systemImage: "keyboard")
                                .foregroundStyle(Color.accentColor).allowsHitTesting(false)
                        }
                    if let result {
                        Label(result ? "这组尺寸已应用到实际键盘" : "键盘未能保存配置，请重试",
                              systemImage: result ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(result ? Color.green : Color.red)
                    } else {
                        Text("等待简体注音键盘确认接收…").foregroundStyle(.secondary)
                    }
                    Button("重新同步") { result = nil; attempt += 1 }
                }
            }
            .navigationTitle("应用到键盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

struct KeyboardSyncField: UIViewRepresentable {
    let code: String
    var autoFocus = false
    var attempt = 0
    var onReply: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SyncTextField {
        let field = SyncTextField()
        field.textColor = .clear
        field.tintColor = .clear
        field.textContentType = .nickname
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.accessibilityLabel = "打开键盘并同步设置"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: SyncTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onReply = onReply
        field.shouldAutoFocus = autoFocus
        let request = "\(attempt):\(code)"
        guard coordinator.request != request else { return }
        coordinator.installing = true
        coordinator.request = request
        coordinator.payload = code
        coordinator.success = KeyboardPreferences.syncReply(for: code)
        coordinator.failure = KeyboardPreferences.syncReply(for: code, succeeded: false)
        coordinator.reported = false
        // Keep an already visible keyboard up while replacing and selecting the entire payload.
        field.inputDelegate?.textWillChange(field)
        field.inputDelegate?.selectionWillChange(field)
        field.unmarkText()
        field.text = code
        field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
        field.inputDelegate?.textDidChange(field)
        field.inputDelegate?.selectionDidChange(field)
        coordinator.installing = false
        coordinator.changed(field)
        field.focusIfNeeded()
    }

    final class SyncTextField: UITextField {
        var shouldAutoFocus = false
        override func didMoveToWindow() { super.didMoveToWindow(); focusIfNeeded() }
        func focusIfNeeded() {
            guard shouldAutoFocus, window != nil, !isFirstResponder else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.shouldAutoFocus else { return }
                self.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var request = ""
        var payload = ""
        var success = ""
        var failure = ""
        var reported = false
        var installing = false
        var onReply: (Bool) -> Void = { _ in }

        func textFieldDidBeginEditing(_ field: UITextField) {
            guard !reported else { return }
            field.inputDelegate?.selectionWillChange(field)
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.inputDelegate?.selectionDidChange(field)
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            changed(field)
            guard !installing, !reported, field.text == payload, field.selectedTextRange?.isEmpty == true else { return }
            field.inputDelegate?.selectionWillChange(field)
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.inputDelegate?.selectionDidChange(field)
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let proposed = ((field.text ?? "") as NSString).replacingCharacters(in: range, with: string)
            guard proposed == success || proposed == failure else { return false }
            DispatchQueue.main.async { [weak self, weak field] in
                if let field { self?.changed(field) }
            }
            return true
        }

        @objc func changed(_ field: UITextField) {
            guard !installing, !reported, field.text == success || field.text == failure else { return }
            reported = true
            let succeeded = field.text == success
            DispatchQueue.main.async { [weak self] in self?.onReply(succeeded) }
        }
    }
}
