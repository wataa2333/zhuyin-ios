import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page: Equatable { case initials, finals, numbers, emoji }

    private struct Key {
        let title: String
        let weight: CGFloat
        let systemImage: String?
        let accessibilityLabel: String?
        let action: (() -> Void)?

        init(_ title: String, weight: CGFloat = 1, image: String? = nil,
             label: String? = nil, action: (() -> Void)? = nil) {
            self.title = title
            self.weight = weight
            systemImage = image
            accessibilityLabel = label
            self.action = action
        }
    }

    private var composition = Composition()
    private lazy var lexicon: Lexicon = {
        guard let url = Bundle(for: KeyboardViewController.self).url(forResource: "Lexicon", withExtension: "tsv"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled lexicon")
            return Lexicon(contents: "")
        }
        return Lexicon(contents: contents)
    }()
    private var alternatePage: Page?
    private var documentIdentifier: UUID?
    private var candidates: [Candidate] = []
    private var displayedPage: Page?
    private var displayedGlobe = false
    private var displayedReturn = ""

    private let rows = UIStackView()
    private let candidateScroll = UIScrollView()
    private let candidateRow = UIStackView()
    private let readingLabel = UILabel()
    private var keyboardHeight: NSLayoutConstraint?

    private var page: Page { alternatePage ?? (composition.showsFinals ? .finals : .initials) }
    private var returnTitle: String {
        switch textDocumentProxy.returnKeyType {
        case .go: return "前往"
        case .search, .google, .yahoo: return "搜索"
        case .send: return "发送"
        case .done: return "完成"
        case .next: return "下一项"
        case .join: return "加入"
        case .route: return "路线"
        case .continue: return "继续"
        default: return "换行"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.16, alpha: 1)
                : UIColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 1)
        }

        rows.axis = .vertical
        rows.distribution = .fillEqually
        rows.spacing = 8
        candidateRow.spacing = 3
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.addSubview(candidateRow)
        candidateRow.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidateRow.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateRow.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateRow.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateRow.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateRow.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor)
        ])

        readingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        readingLabel.textColor = .secondaryLabel
        readingLabel.lineBreakMode = .byTruncatingHead
        readingLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        readingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 112).isActive = true
        let toolbar = UIStackView(arrangedSubviews: [readingLabel, candidateScroll])
        toolbar.spacing = 4
        toolbar.heightAnchor.constraint(equalToConstant: 37).isActive = true

        let layout = UIStackView(arrangedSubviews: [toolbar, rows])
        layout.axis = .vertical
        layout.spacing = 4
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let area = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: 6),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -6),
            layout.topAnchor.constraint(equalTo: area.topAnchor, constant: 2),
            layout.bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -6)
        ])

        let height = view.heightAnchor.constraint(equalToConstant: preferredHeight)
        height.priority = .defaultHigh
        height.isActive = true
        keyboardHeight = height
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDocument()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        composition = Composition()
        alternatePage = nil
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardHeight?.constant = preferredHeight
        updateKeys()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if isViewLoaded { refreshDocument() }
    }

    private var preferredHeight: CGFloat {
        traitCollection.verticalSizeClass == .compact ? 198 : 264
    }

    private func refreshDocument() {
        let identifier = textDocumentProxy.documentIdentifier
        if documentIdentifier != identifier {
            composition = Composition()
            alternatePage = nil
            documentIdentifier = identifier
        }
        render()
    }

    private func render() {
        candidates = composition.hasInput ? lexicon.candidates(for: composition) : []
        readingLabel.text = composition.display
        readingLabel.isHidden = !composition.hasInput
        candidateRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        candidateScroll.setContentOffset(.zero, animated: false)

        for (index, candidate) in candidates.enumerated() {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = candidate.text
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
            if index == 0 {
                config.background.backgroundColor = UIColor.secondarySystemGroupedBackground
            }
            button.configuration = config
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { [weak self] _ in self?.choose(candidate) }, for: .touchUpInside)
            candidateRow.addArrangedSubview(button)
        }
        updateKeys()
    }

    private func updateKeys() {
        let globe = needsInputModeSwitchKey
        let returnKey = returnTitle
        guard page != displayedPage || globe != displayedGlobe || returnKey != displayedReturn else { return }
        displayedPage = page
        displayedGlobe = globe
        displayedReturn = returnKey
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for keys in keysForPage() { rows.addArrangedSubview(makeRow(keys)) }
    }

    private func keysForPage() -> [[Key]] {
        let shift = Key("", image: page == .finals ? "shift.fill" : "shift",
                        label: page == .finals ? "声母页" : "韵母页") { [weak self] in
            self?.composition.togglePage()
            self?.updateKeys()
        }
        let backspace = Key("", image: "delete.left", label: "删除") { [weak self] in self?.delete() }
        let space = Key(page == .initials || page == .finals ? "注" : "空格",
                        weight: 4.3, label: "空格或一声") { [weak self] in self?.space() }
        let enter = Key(returnTitle == "换行" ? "" : returnTitle, weight: 2.1,
                        image: returnTitle == "换行" ? "return" : nil,
                        label: returnTitle) { [weak self] in self?.enter() }
        let numbers = Key(page == .numbers ? "ㄅㄆㄇ" : "123", label: "数字与符号") { [weak self] in
            self?.toggle(.numbers)
        }
        let emoji = Key("", image: "face.smiling", label: "表情") { [weak self] in self?.toggle(.emoji) }
        let bottom = [numbers, emoji] + (needsInputModeSwitchKey ? [Key("", image: "globe", label: "切换键盘")] : [])
            + [space, enter]

        switch page {
        case .initials:
            return [
                [Key("", weight: 0.43)] + phonetics("ㄅㄆㄇㄈㄉㄊㄋㄌ") + [Key("", weight: 0.43)],
                phonetics("ㄍㄎㄏㄐㄑㄒㄧㄨㄩ"),
                [shift] + phonetics("ㄓㄔㄕㄖㄗㄘㄙ") + [backspace],
                bottom
            ]
        case .finals:
            let tones = zip("ˊˇˋ˙", "2345").map { symbol, tone in
                Key(String(symbol), weight: 1.65, label: "声调 \(tone)") { [weak self] in
                    self?.composition.finish(tone: tone)
                    self?.render()
                }
            }
            return [
                [Key("", weight: 0.43)] + phonetics("ㄚㄛㄜㄝㄞㄟㄠㄡ") + [Key("", weight: 0.43)],
                [Key("")] + phonetics("ㄢㄣㄤㄥㄦㄧㄨㄩ"),
                [shift, Key("", weight: 0.36)] + tones + [Key("", weight: 0.36), backspace],
                bottom
            ]
        case .numbers:
            return [
                literals("1234567890"),
                literals("－／：；（）￥＆＠"),
                literals("，。！？、＂＇…") + [backspace],
                bottom
            ]
        case .emoji:
            return [
                literals("😀😃😄😁😅😂🙂🙃"),
                literals("🥹😍🥰😎🤔😭😢😡"),
                literals("👍👏🙏🎉❤️🔥✨") + [backspace],
                bottom
            ]
        }
    }

    private func phonetics(_ symbols: String) -> [Key] {
        symbols.map { symbol in
            Key(String(symbol)) { [weak self] in
                self?.composition.type(symbol)
                self?.render()
            }
        }
    }

    private func literals(_ symbols: String) -> [Key] {
        symbols.map { symbol in
            Key(String(symbol)) { [weak self] in
                self?.commitPending()
                self?.textDocumentProxy.insertText(String(symbol))
            }
        }
    }

    private func makeRow(_ keys: [Key]) -> UIStackView {
        let row = UIStackView()
        row.spacing = 5
        for key in keys {
            let element: UIView
            if key.title.isEmpty, key.systemImage == nil {
                element = UIView()
            } else {
                let button = KeyboardButton(type: .system)
                button.accessibilityLabel = key.accessibilityLabel ?? key.title
                button.backgroundColor = UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(white: 0.34, alpha: 1)
                        : .white
                }
                button.tintColor = .label
                button.layer.cornerRadius = 6
                button.layer.shadowColor = UIColor.black.cgColor
                button.layer.shadowOpacity = 0.24
                button.layer.shadowOffset = CGSize(width: 0, height: 1)
                button.layer.shadowRadius = 0
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                if let image = key.systemImage {
                    button.setImage(UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
                } else {
                    button.setTitle(key.title, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: key.accessibilityLabel == nil ? 22 : 15)
                    button.titleLabel?.adjustsFontSizeToFitWidth = true
                    button.titleLabel?.minimumScaleFactor = 0.65
                    if key.title == "注" {
                        button.contentHorizontalAlignment = .trailing
                        button.contentVerticalAlignment = .bottom
                        button.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 7)
                        button.setTitleColor(.tertiaryLabel, for: .normal)
                        button.titleLabel?.font = .systemFont(ofSize: 12)
                    }
                }
                if let action = key.action {
                    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
                } else {
                    button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
                }
                element = button
            }
            row.addArrangedSubview(element)
            if let first = row.arrangedSubviews.first, first !== element {
                let constraint = element.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: key.weight / keys[0].weight)
                constraint.priority = UILayoutPriority(999)
                constraint.isActive = true
            }
        }
        return row
    }

    private func toggle(_ page: Page) {
        alternatePage = alternatePage == page ? nil : page
        updateKeys()
    }

    private func delete() {
        if composition.hasInput {
            composition.deleteBackward()
            render()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    private func space() {
        if alternatePage == nil, !composition.current.symbols.isEmpty {
            composition.finish(tone: "1")
            render()
        } else if composition.hasInput {
            commitPending()
        } else {
            textDocumentProxy.insertText(" ")
        }
    }

    private func enter() {
        if composition.hasInput {
            commitPending()
        } else {
            textDocumentProxy.insertText("\n")
        }
    }

    private func choose(_ candidate: Candidate) {
        composition.consume(candidate.syllableCount)
        textDocumentProxy.insertText(candidate.text)
        render()
    }

    private func commitPending() {
        // A candidate may cover just the first word. Preserve and resolve the rest.
        while let candidate = candidates.first, composition.hasInput {
            choose(candidate)
        }
        if composition.hasInput {
            let reading = composition.display
            composition = Composition()
            textDocumentProxy.insertText(reading)
            render()
        }
    }
}

private final class KeyboardButton: UIButton {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.62 : 1 }
    }
}
