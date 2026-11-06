import SwiftUI
import UIKit

@main
struct ZhuyinApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

private struct SetupView: View {
    @State private var text = ""
    @State private var showsPinyin = KeyboardPreferences.showsPinyin
    @State private var feedback = KeyboardPreferences.sharedFeedback ?? KeyboardPreferences.localFeedback
    @State private var savedLayout = KeyboardPreferences.layout
    @State private var draftLayout = KeyboardPreferences.layout
    @State private var layoutStatus = ""
    @State private var layoutSaveFailed = false
    @State private var needsKeyboardSync = KeyboardPreferences.pinyinFile == nil
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("启用键盘") {
                    Text("1. 打开「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」。")
                    Text("2. 选择「简体注音」。在输入时长按地球键切换到它。")
                    Text("字词查询在设备上运行，无需开启「允许完全访问」。")
                        .foregroundStyle(.secondary)
                    Text("使用按键声和轻触反馈时，请在「设置 → 通用 → 键盘 → 键盘 → 简体注音」开启「允许完全访问」。按键声随 iPhone 静音模式关闭。")
                        .foregroundStyle(.secondary)
                }

                Section("键盘设置") {
                    Toggle("按键显示拼音", isOn: Binding(get: { showsPinyin }, set: setPinyin))
                    VStack(alignment: .leading) {
                        Text("按键音量 \(feedback.volume)%")
                        Slider(value: Binding(get: { Double(feedback.volume) }, set: {
                            feedback.volume = UInt8($0.rounded())
                            saveFeedback()
                        }), in: 0...100, step: 5)
                        .accessibilityLabel("按键音量")
                    }
                    Picker("按键触感", selection: Binding(get: { feedback.haptics }, set: {
                        feedback.haptics = $0
                        saveFeedback()
                    })) {
                        Text("关闭").tag(UInt8(0))
                        Text("弱").tag(UInt8(1))
                        Text("中").tag(UInt8(2))
                        Text("强").tag(UInt8(3))
                    }
                    if needsKeyboardSync {
                        KeyboardSyncField(code: KeyboardPreferences.syncCode(pinyin: showsPinyin, feedback: feedback, layout: savedLayout))
                            .frame(minHeight: 40)
                            .overlay(alignment: .leading) {
                                Label("打开键盘同步设置", systemImage: "keyboard")
                                    .foregroundStyle(Color.accentColor)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        Text("更改后点上面的同步栏，并切到「简体注音」键盘。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("键盘固定高度") {
                    Text("横竖屏、不同 App 使用同一组固定尺寸，不自动测量或调节高度。修改后点「保存并应用」。")
                        .foregroundStyle(.secondary)
                    layoutStepper("候选栏高度", \.candidateBarHeight, range: 40...80)
                    layoutStepper("按键高度", \.keyHeight, range: 32...60)
                    layoutStepper("按键行距", \.rowSpacing, range: 0...16)
                    layoutStepper("顶部留白", \.topInset, range: 0...30)
                    layoutStepper("候选栏与按键间距", \.toolbarSpacing, range: 0...12)
                    layoutStepper("底部留白", \.bottomInset, range: 0...40)
                    LabeledContent("键盘内容总高度", value: "\(Int(draftLayout.contentHeight)) 点")
                    Button("保存并应用", action: saveLayout)
                    Button("恢复默认高度") {
                        draftLayout = .defaults
                        saveLayout()
                    }
                    if !needsKeyboardSync {
                        Button("手动同步到键盘") { needsKeyboardSync = true }
                    }
                    if !layoutStatus.isEmpty {
                        Text(layoutStatus)
                            .foregroundStyle(layoutSaveFailed ? Color.red : Color.secondary)
                    }
                    Text("保存后下次启动仍使用该配置。系统底部的地球键、麦克风区域由 iOS 管理。")
                        .foregroundStyle(.secondary)
                }

                Section("试打") {
                    TextField("在这里试打简体字和词组", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($isTyping)
                    Text("试试 ㄋㄧˇ ㄏㄠˇ → 你好，或 ㄓㄨˋ ㄧ（一声）→ 注音。")
                        .foregroundStyle(.secondary)
                }

                Section("动态布局") {
                    Text("输入声母或介音后自动切到韵母页。⇧ 可手动切页，韵母起头的音可从韵母页输入。")
                    Text("有未定调的注音时，空格键输入一声。定调后可继续输入下一个音节，或点击候选字词上屏。")
                    Text("点候选栏右侧的箭头可展开更多字词。点 123 进入数字页，再点 #+= 切到符号页。常选字词会保存在设备上。")
                }
                Section {
                    LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            }
            .navigationTitle("简体注音")
        }
    }

    private func layoutStepper(_ title: String, _ field: WritableKeyPath<KeyboardLayoutConfiguration, CGFloat>,
                               range: ClosedRange<CGFloat>) -> some View {
        Stepper(value: Binding(get: { draftLayout[keyPath: field] }, set: {
            draftLayout[keyPath: field] = $0
            layoutStatus = "有未保存的修改"
            layoutSaveFailed = false
        }), in: range, step: 1) {
            Text("\(title) \(Int(draftLayout[keyPath: field])) 点")
        }
    }

    private func saveLayout() {
        do {
            let shared = try KeyboardPreferences.saveLayout(draftLayout)
            savedLayout = draftLayout
            if !shared { needsKeyboardSync = true }
            layoutSaveFailed = false
            layoutStatus = shared ? "已保存并应用" : "已保存，请点同步栏应用到键盘"
        } catch {
            needsKeyboardSync = true
            layoutSaveFailed = true
            layoutStatus = "保存失败，请重试。"
        }
    }

    private func setPinyin(_ enabled: Bool) {
        KeyboardPreferences.saveLocally(enabled)
        showsPinyin = enabled
        guard let file = KeyboardPreferences.pinyinFile else {
            needsKeyboardSync = true
            return
        }
        let saved: Void? = try? Data([enabled ? 1 : 0]).write(to: file, options: .atomic)
        if saved == nil { needsKeyboardSync = true }
        else { KeyboardPreferences.notifyChanged() }
    }

    private func saveFeedback() {
        KeyboardPreferences.saveLocally(feedback)
        guard let file = KeyboardPreferences.feedbackFile else {
            needsKeyboardSync = true
            return
        }
        if (try? feedback.data.write(to: file, options: .atomic)) == nil { needsKeyboardSync = true }
        else { KeyboardPreferences.notifyChanged() }
    }
}

private struct KeyboardSyncField: UIViewRepresentable {
    let code: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.textColor = .clear
        field.tintColor = .clear
        field.textContentType = .nickname
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityLabel = "打开键盘同步设置"
        field.delegate = context.coordinator
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        guard field.text != code else { return }
        if field.isFirstResponder { field.resignFirstResponder() }
        field.text = code
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        func textFieldDidBeginEditing(_ textField: UITextField) {
            let end = textField.endOfDocument
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            false
        }
    }
}
