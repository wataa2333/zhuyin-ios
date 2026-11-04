import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page: Equatable { case initials, finals, numbers, emoji }

    private struct Key {
        let title: String
        let weight: CGFloat
        let systemImage: String?
        let accessibilityLabel: String?
        let pinyin: String?
        let action: (() -> Void)?

        init(_ title: String, weight: CGFloat = 1, image: String? = nil,
             label: String? = nil, pinyin: String? = nil, action: (() -> Void)? = nil) {
            self.title = title
            self.weight = weight
            systemImage = image
            accessibilityLabel = label
            self.pinyin = pinyin
            self.action = action
        }
    }

    private static let pinyinBySymbol: [Character: String] = [
        "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l",
        "ㄍ": "g", "ㄎ": "k", "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x",
        "ㄓ": "zh", "ㄔ": "ch", "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s",
        "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "ê", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
        "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er", "ㄧ": "i", "ㄨ": "u", "ㄩ": "ü"
    ]

    private static let pinyinPreference = "showPinyinOnKeys"
    private static let starterCandidates = ["我", "你", "这", "那", "他", "有", "因为", "我们"]
    private var showsPinyin = UserDefaults.standard.bool(forKey: KeyboardViewController.pinyinPreference)
    private var composition = Composition()
    private var markedReading = ""
    private var updatingDocument = false
    private var userDictionary = UserDictionary()
    private var selectedSegments: [Candidate] = []
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
    private let keyArea = UIView()
    private let candidateScroll = UIScrollView()
    private let candidateRow = UIStackView()
    private let expandCandidates = UIButton(type: .system)
    private let candidatePanel = UIStackView()
    private let candidateGridScroll = UIScrollView()
    private let candidateGrid = UIStackView()
    private let pinyinToggle = UIButton(type: .system)
    private var showsCandidatePanel = false
    private var candidateGridWidth: CGFloat = 0
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
        installBackground()

        rows.axis = .vertical
        rows.distribution = .fillEqually
        rows.spacing = 8
        if #available(iOS 26.0, *) { rows.spacing = 11 }
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

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.widthAnchor.constraint(equalToConstant: 1 / 3).isActive = true
        expandCandidates.tintColor = .label
        expandCandidates.widthAnchor.constraint(equalToConstant: 36).isActive = true
        expandCandidates.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setCandidatePanelVisible(!self.showsCandidatePanel, animated: true)
        }, for: .touchUpInside)
        let toolbar = UIStackView(arrangedSubviews: [candidateScroll, divider, expandCandidates])
        toolbar.spacing = 3
        toolbar.heightAnchor.constraint(equalToConstant: 38).isActive = true
        configureCandidatePanel()
        for content in [rows, candidatePanel] {
            content.translatesAutoresizingMaskIntoConstraints = false
            keyArea.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor),
                content.topAnchor.constraint(equalTo: keyArea.topAnchor),
                content.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor)
            ])
        }
        setCandidatePanelVisible(false)

        let layout = UIStackView(arrangedSubviews: [toolbar, keyArea])
        layout.axis = .vertical
        layout.spacing = 7
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let area = view.safeAreaLayoutGuide
        let sideInset: CGFloat = 7
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: sideInset),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -sideInset),
            layout.topAnchor.constraint(equalTo: area.topAnchor, constant: 8),
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
        markedReading = ""
        selectedSegments.removeAll()
        alternatePage = nil
        setCandidatePanelVisible(false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        keyboardHeight?.constant = preferredHeight
        updateKeys()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if showsCandidatePanel, abs(candidateGridWidth - keyArea.bounds.width) > 1 {
            updateCandidateGrid()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if isViewLoaded, !updatingDocument { refreshDocument() }
    }

    private var preferredHeight: CGFloat {
        traitCollection.verticalSizeClass == .compact ? 198 : 264
    }

    private func installBackground() {
        if #available(iOS 26.0, *) {
            view.isOpaque = false
            view.backgroundColor = .clear
            let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            material.isUserInteractionEnabled = false
            material.layer.cornerCurve = .continuous
            material.layer.cornerRadius = 27
            material.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            material.clipsToBounds = true
            material.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(material, at: 0)
            NSLayoutConstraint.activate([
                material.topAnchor.constraint(equalTo: view.topAnchor),
                material.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                material.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        } else {
            view.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.16, alpha: 1)
                    : UIColor(red: 0.84, green: 0.85, blue: 0.88, alpha: 1)
            }
        }
    }

    private func refreshDocument() {
        switch textDocumentProxy.keyboardAppearance {
        case .dark: view.overrideUserInterfaceStyle = .dark
        case .light: view.overrideUserInterfaceStyle = .light
        default: view.overrideUserInterfaceStyle = .unspecified
        }
        let identifier = textDocumentProxy.documentIdentifier
        if documentIdentifier != identifier {
            composition = Composition()
            markedReading = ""
            selectedSegments.removeAll()
            alternatePage = nil
            setCandidatePanelVisible(false)
            documentIdentifier = identifier
        }
        render()
    }

    private func togglePinyin() {
        showsPinyin.toggle()
        UserDefaults.standard.set(showsPinyin, forKey: Self.pinyinPreference)
        updatePinyinToggle()
        displayedPage = nil
        updateKeys()
        setCandidatePanelVisible(false, animated: true)
    }

    private func updatePinyinToggle() {
        var configuration = showsPinyin ? UIButton.Configuration.tinted() : .plain()
        configuration.title = showsPinyin ? "拼音标注：开" : "拼音标注：关"
        configuration.baseForegroundColor = showsPinyin ? .systemBlue : .secondaryLabel
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        pinyinToggle.configuration = configuration
        pinyinToggle.accessibilityValue = showsPinyin ? "已开启" : "已关闭"
    }

    private func render() {
        if composition.hasInput {
            candidates = lexicon.candidates(for: composition, learned: userDictionary.candidates)
        } else if alternatePage == nil {
            candidates = Self.starterCandidates.map { Candidate(text: $0) }
        } else {
            candidates = []
        }
        candidateRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        candidateScroll.setContentOffset(.zero, animated: false)

        for (index, candidate) in candidates.enumerated() {
            let button = candidateButton(candidate, highlighted: index == 0 && composition.hasInput)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            candidateRow.addArrangedSubview(button)
        }
        if showsCandidatePanel { updateCandidateGrid() }
        updateKeys()
    }

    private func candidateButton(_ candidate: Candidate, highlighted: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = candidate.text
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 18)
            return attributes
        }
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
        if highlighted { configuration.background.backgroundColor = .secondarySystemGroupedBackground }
        button.configuration = configuration
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.addAction(UIAction { [weak self] _ in self?.choose(candidate) }, for: .touchUpInside)
        return button
    }

    private func configureCandidatePanel() {
        pinyinToggle.accessibilityLabel = "按键拼音标注"
        pinyinToggle.addAction(UIAction { [weak self] _ in self?.togglePinyin() }, for: .touchUpInside)
        pinyinToggle.heightAnchor.constraint(equalToConstant: 32).isActive = true
        updatePinyinToggle()

        candidatePanel.axis = .vertical
        candidatePanel.spacing = 5
        candidatePanel.addArrangedSubview(candidateGridScroll)
        candidatePanel.addArrangedSubview(pinyinToggle)
        candidateGrid.axis = .vertical
        candidateGrid.spacing = 4
        candidateGridScroll.addSubview(candidateGrid)
        candidateGrid.translatesAutoresizingMaskIntoConstraints = false
        let content = candidateGridScroll.contentLayoutGuide
        NSLayoutConstraint.activate([
            candidateGrid.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            candidateGrid.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            candidateGrid.topAnchor.constraint(equalTo: content.topAnchor),
            candidateGrid.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            candidateGrid.widthAnchor.constraint(equalTo: candidateGridScroll.frameLayoutGuide.widthAnchor)
        ])
    }

    private func setCandidatePanelVisible(_ visible: Bool, animated: Bool = false) {
        let changed = showsCandidatePanel != visible
        showsCandidatePanel = visible
        let image = UIImage(systemName: visible ? "chevron.up" : "chevron.down",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        expandCandidates.setImage(image, for: .normal)
        expandCandidates.accessibilityLabel = visible ? "收起候选字词" : "展开候选字词和拼音设置"
        if visible {
            updateCandidateGrid()
            candidateGridScroll.setContentOffset(.zero, animated: false)
        }
        let showContent = {
            self.rows.isHidden = visible
            self.candidatePanel.isHidden = !visible
        }
        if changed, animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: keyArea, duration: 0.20,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction],
                              animations: showContent)
        } else {
            showContent()
        }
    }

    private func updateCandidateGrid() {
        let availableWidth = keyArea.bounds.width
        guard availableWidth >= 44 else { return }
        candidateGridWidth = availableWidth
        candidateGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let spacing: CGFloat = 4
        var row = UIStackView()
        var occupied: CGFloat = 0

        for candidate in candidates {
            let button = candidateButton(candidate)
            let width = min(availableWidth, max(44, ceil(button.intrinsicContentSize.width)))
            if occupied > 0, occupied + spacing + width > availableWidth {
                appendCandidateRow(row)
                row = UIStackView()
                occupied = 0
            }
            row.spacing = spacing
            row.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            occupied += occupied > 0 ? spacing + width : width
        }
        if occupied > 0 { appendCandidateRow(row) }
    }

    private func appendCandidateRow(_ row: UIStackView) {
        if let last = row.arrangedSubviews.last { row.setCustomSpacing(0, after: last) }
        row.addArrangedSubview(UIView())
        candidateGrid.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
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
        let modifierWeight: CGFloat = page == .finals ? 1.1 : 1
        let shift = Key("", weight: modifierWeight, image: page == .finals ? "shift.fill" : "shift",
                        label: page == .finals ? "声母页" : "韵母页") { [weak self] in
            self?.composition.togglePage()
            self?.updateKeys()
        }
        let backspace = Key("", weight: modifierWeight, image: "delete.left", label: "删除") { [weak self] in self?.delete() }
        let space = Key(page == .initials || page == .finals ? "注" : "空格",
                        weight: 4.42, label: "空格或一声") { [weak self] in self?.space() }
        let enter = Key(returnTitle == "换行" ? "" : returnTitle, weight: 2.15,
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
                Key(String(symbol), weight: 1.55, label: "声调 \(tone)") { [weak self] in
                    self?.composition.finish(tone: tone)
                    self?.updateComposition()
                }
            }
            return [
                [Key("", weight: 0.43)] + phonetics("ㄚㄛㄜㄝㄞㄟㄠㄡ") + [Key("", weight: 0.43)],
                [Key("")] + phonetics("ㄢㄣㄤㄥㄦㄧㄨㄩ"),
                [shift, Key("", weight: 0.30)] + tones + [Key("", weight: 0.30), backspace],
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
            Key(String(symbol), pinyin: Self.pinyinBySymbol[symbol]) { [weak self] in
                self?.composition.type(symbol)
                self?.updateComposition()
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
        row.spacing = 6
        for key in keys {
            let element: UIView
            if key.title.isEmpty, key.systemImage == nil {
                element = UIView()
            } else {
                let button = KeyboardButton(type: .system)
                button.accessibilityLabel = key.accessibilityLabel ?? key.title
                button.backgroundColor = UIColor { traits in
                    if #available(iOS 26.0, *) {
                        return traits.userInterfaceStyle == .dark
                            ? UIColor.white.withAlphaComponent(0.18)
                            : UIColor.white.withAlphaComponent(0.78)
                    }
                    return traits.userInterfaceStyle == .dark
                        ? UIColor(white: 0.34, alpha: 1)
                        : .white
                }
                button.tintColor = .label
                button.layer.cornerRadius = 6
                button.layer.shadowColor = UIColor.black.cgColor
                button.layer.shadowOpacity = 0.24
                button.layer.shadowOffset = CGSize(width: 0, height: 1)
                button.layer.shadowRadius = 0
                if #available(iOS 26.0, *) {
                    button.layer.cornerCurve = .continuous
                    button.layer.cornerRadius = 9
                    button.layer.shadowOpacity = 0.08
                }
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                if let image = key.systemImage {
                    button.setImage(UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
                } else if key.title == "注" {
                    let marker = UILabel()
                    marker.text = "注"
                    marker.textColor = .secondaryLabel
                    marker.font = .systemFont(ofSize: 12)
                    marker.isAccessibilityElement = false
                    marker.translatesAutoresizingMaskIntoConstraints = false
                    button.addSubview(marker)
                    NSLayoutConstraint.activate([
                        marker.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
                        marker.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -5)
                    ])
                } else if showsPinyin, let pinyin = key.pinyin {
                    let caption = NSMutableAttributedString(string: key.title, attributes: [
                        .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label
                    ])
                    caption.append(NSAttributedString(string: "\n" + pinyin, attributes: [
                        .font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.secondaryLabel
                    ]))
                    button.titleLabel?.numberOfLines = 2
                    button.titleLabel?.textAlignment = .center
                    button.setAttributedTitle(caption, for: .normal)
                    button.accessibilityLabel = "\(key.title)，\(pinyin)"
                } else {
                    button.setTitle(key.title, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: key.accessibilityLabel == nil ? 22 : 15)
                    button.titleLabel?.adjustsFontSizeToFitWidth = true
                    button.titleLabel?.minimumScaleFactor = 0.65
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
        render()
    }

    private func delete() {
        if composition.hasInput {
            composition.deleteBackward()
            if !composition.hasInput { selectedSegments.removeAll() }
            updateComposition()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    private func space() {
        if alternatePage == nil, !composition.current.symbols.isEmpty {
            composition.finish(tone: "1")
            updateComposition()
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
        if !candidate.reading.isEmpty {
            userDictionary.learn(candidate)
            if composition.hasInput || !selectedSegments.isEmpty {
                selectedSegments.append(candidate)
                if !composition.hasInput {
                    userDictionary.learn(Candidate(
                        text: selectedSegments.map(\.text).joined(),
                        reading: selectedSegments.flatMap(\.reading)
                    ))
                    selectedSegments.removeAll()
                }
            }
        }
        setCandidatePanelVisible(false, animated: true)
        commit(candidate.text)
        updateComposition()
    }

    private func updateComposition() {
        let reading = composition.display
        if markedReading != reading {
            markedReading = reading
            setMarkedText(reading, keepMarked: !reading.isEmpty)
        }
        render()
    }

    private func setMarkedText(_ text: String, keepMarked: Bool) {
        updatingDocument = true
        defer { updatingDocument = false }
        let proxy = textDocumentProxy
        proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        if !keepMarked { proxy.unmarkText() }
    }

    private func commit(_ text: String) {
        if markedReading.isEmpty {
            textDocumentProxy.insertText(text)
        } else {
            markedReading = ""
            setMarkedText(text, keepMarked: false)
        }
    }

    private func commitPending() {
        // A candidate may cover just the first word. Preserve and resolve the rest.
        while let candidate = candidates.first, composition.hasInput {
            choose(candidate)
        }
        if composition.hasInput {
            let reading = composition.display
            composition = Composition()
            selectedSegments.removeAll()
            commit(reading)
            render()
        }
    }
}

private final class KeyboardButton: UIButton {
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.62 : 1 }
    }
}
