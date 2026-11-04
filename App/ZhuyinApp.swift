import SwiftUI

@main
struct ZhuyinApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

private struct SetupView: View {
    @State private var text = ""
    @State private var showsPinyin = KeyboardPreferences.showsPinyin
    @State private var savingFailed = false
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("启用键盘") {
                    Text("1. 打开「设置 → 通用 → 键盘 → 键盘 → 添加新键盘」。")
                    Text("2. 选择「简体注音」。在输入时长按地球键切换到它。")
                    Text("字词查询在设备上运行，无需开启「允许完全访问」。")
                        .foregroundStyle(.secondary)
                    Text("要使用按键轻触反馈，可在「设置 → 通用 → 键盘 → 键盘 → 简体注音」开启「允许完全访问」。")
                        .foregroundStyle(.secondary)
                }

                Section("键盘设置") {
                    Toggle("按键显示拼音", isOn: Binding(get: { showsPinyin }, set: setPinyin))
                        .disabled(KeyboardPreferences.pinyinFile == nil)
                    if KeyboardPreferences.pinyinFile == nil || savingFailed {
                        Text("当前安装无法访问共享容器。请用包含同一 App Group 的描述文件签名 App 和键盘扩展。")
                            .foregroundStyle(.secondary)
                    }
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
            }
            .navigationTitle("简体注音")
        }
    }

    private func setPinyin(_ enabled: Bool) {
        guard let file = KeyboardPreferences.pinyinFile else { return }
        do {
            try Data([enabled ? 1 : 0]).write(to: file, options: .atomic)
            showsPinyin = enabled
            savingFailed = false
            isTyping = false
        } catch {
            savingFailed = true
        }
    }
}
