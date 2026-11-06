import SwiftUI
import UIKit

struct KeyboardLayoutEditor: View {
    @Binding var savedLayout: KeyboardLayoutConfiguration
    let showsPinyin: Bool
    let feedback: KeyFeedbackSettings
    @State private var draft: KeyboardLayoutConfiguration
    @State private var expanded = false
    @State private var status = ""
    @State private var failed = false
    @State private var showingApply = false

    init(savedLayout: Binding<KeyboardLayoutConfiguration>, showsPinyin: Bool, feedback: KeyFeedbackSettings) {
        _savedLayout = savedLayout
        _draft = State(initialValue: savedLayout.wrappedValue)
        self.showsPinyin = showsPinyin
        self.feedback = feedback
    }

    var body: some View {
        Form {
            Section {
                dimension("候选栏高度", \.candidateBarHeight, 40...80)
                dimension("按键高度", \.keyHeight, 32...60)
                dimension("按键行距", \.rowSpacing, 0...16)
                dimension("顶部留白", \.topInset, 0...30)
                dimension("候选栏与按键间距", \.toolbarSpacing, 0...12)
                dimension("底部留白", \.bottomInset, 0...40)
                LabeledContent("内容总高度", value: "\(Int(draft.contentHeight)) 点")
                Button("恢复默认") { draft = .defaults; status = "预览已恢复默认，尚未保存"; failed = false }
            } footer: {
                Text("下方实时预览复用实际键盘的布局，可展开候选检查尺寸。顶部留白为 0 时，候选会贴近内容区顶部。")
            }
            if !status.isEmpty {
                Section { Text(status).foregroundStyle(failed ? Color.red : Color.secondary) }
            }
        }
        .navigationTitle("键盘高度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("保存并应用", action: save) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Toggle("展开候选预览", isOn: $expanded).padding(.horizontal).padding(.vertical, 8)
                KeyboardLayoutPreview(layout: draft, showsPinyin: showsPinyin, expanded: $expanded)
                    .frame(height: draft.contentHeight)
                    .clipped()
                Text("尺寸为实际点数；预览不包含 iOS 的地球键、麦克风和外部边框。")
                    .font(.caption).foregroundStyle(.secondary).padding(6)
            }
            .background(Color(uiColor: .systemGray5))
        }
        .onAppear {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showingApply) {
            KeyboardApplySheet(code: KeyboardPreferences.syncCode(pinyin: showsPinyin, feedback: feedback, layout: savedLayout), onResult: {
                failed = !$0
                status = $0 ? "实际键盘已接收并保存这组尺寸" : "键盘保存失败，请重新应用"
            })
        }
    }

    private func dimension(_ title: String, _ field: WritableKeyPath<KeyboardLayoutConfiguration, CGFloat>,
                           _ range: ClosedRange<CGFloat>) -> some View {
        Stepper(value: Binding(get: { draft[keyPath: field] }, set: {
            draft[keyPath: field] = $0
            status = "实时预览中，尚未保存"
            failed = false
        }), in: range, step: 1) { Text("\(title) \(Int(draft[keyPath: field])) 点") }
    }

    private func save() {
        do {
            try KeyboardPreferences.saveLayout(draft)
            savedLayout = draft
            status = "配置已保存，等待实际键盘确认接收"
            failed = false
            showingApply = true
        } catch {
            failed = true
            status = "配置写入失败，请重试。"
        }
    }
}

private struct KeyboardLayoutPreview: UIViewControllerRepresentable {
    let layout: KeyboardLayoutConfiguration
    let showsPinyin: Bool
    @Binding var expanded: Bool

    func makeUIViewController(context: Context) -> KeyboardViewController {
        KeyboardViewController.makeLayoutPreview(layout, showsPinyin: showsPinyin)
    }

    func updateUIViewController(_ controller: KeyboardViewController, context: Context) {
        controller.onPreviewExpansionChanged = { value in expanded = value }
        controller.updateLayoutPreview(layout, showsPinyin: showsPinyin, expanded: expanded)
    }
}
