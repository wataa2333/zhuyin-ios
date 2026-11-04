import UIKit

final class KeyboardViewController: UIInputViewController {
    private enum Page: Hashable { case initials, finals, numbers, symbols }

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

    private static let starterCandidates = ["我", "你", "这", "那", "他", "有", "因为", "我们"]
    private static let emojiByWord = [
        "想": "🤔", "下": "⬇️", "心": "❤️", "爱": "❤️", "你好": "👋", "再见": "👋",
        "笑": "😄", "哈哈": "😂", "哭": "😢", "生气": "😡", "谢谢": "🙏", "赞": "👍",
        "恭喜": "🎉", "生日": "🎂", "生日快乐": "🎂", "晚安": "🌙", "太阳": "☀️", "下雨": "🌧️",
        "苹果": "🍎", "咖啡": "☕", "猫": "🐱", "狗": "🐶", "花": "🌸", "火": "🔥"
    ]
    private var showsPinyin = KeyboardPreferences.showsPinyin
    private var composition = Composition()
    private var markedReading = ""
    private var updatingDocument = false
    private var userDictionary = UserDictionary()
    private var selectedSegments: [Candidate] = []
    private let lexiconURL = Bundle(for: KeyboardViewController.self).url(forResource: "Lexicon", withExtension: "tsv")
    private var lexicon: Lexicon?
    private var alternatePage: Page?
    private var documentIdentifier: UUID?
    private var candidates: [Candidate] = []
    private var displayedPage: Page?
    private var displayedGlobe = false
    private var displayedReturn = ""
    private var displayedPinyin = false
    private var keyLayouts: [Page: UIStackView] = [:]

    private let rows = UIView()
    private let keyArea = UIView()
    private let candidateScroll = UIScrollView()
    private let candidateRow = UIStackView()
    private var candidateButtons: [UIButton] = []
    private let expandCandidates = UIButton(type: .system)
    private let candidateGridScroll = UIScrollView()
    private let candidateGrid = UIStackView()
    private var showsCandidatePanel = false
    private var candidateTransition: UIViewPropertyAnimator?
    private var candidateGridWidth: CGFloat = 0
    private let keyPreview = UILabel()
    private let keyHaptic = UISelectionFeedbackGenerator()

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

    override func loadView() {
        view = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        expandCandidates.addTarget(self, action: #selector(pressKey(_:)), for: .touchDown)
        expandCandidates.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setCandidatePanelVisible(!self.showsCandidatePanel, animated: true)
        }, for: .touchUpInside)
        let toolbar = UIStackView(arrangedSubviews: [candidateScroll, divider, expandCandidates])
        toolbar.spacing = 3
        toolbar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        configureCandidatePanel()
        keyArea.clipsToBounds = true
        for content in [rows, candidateGridScroll] {
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
        layout.spacing = 5
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let area = view.safeAreaLayoutGuide
        let sideInset: CGFloat = 7
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: sideInset),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -sideInset),
            layout.topAnchor.constraint(equalTo: area.topAnchor, constant: 4),
            layout.bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -6)
        ])

        configureKeyPreview()
        let url = lexiconURL
        let loading = Task.detached(priority: .userInitiated) { Self.loadLexicon(from: url) }
        Task { [weak self] in
            let loaded = await loading.value
            guard let self, self.lexicon == nil else { return }
            self.lexicon = loaded
            if self.composition.hasInput { self.render() }
        }
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showsPinyin = KeyboardPreferences.showsPinyin
        if hasFullAccess { keyHaptic.prepare() }
        refreshDocument(reloadCandidates: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.synchronizePinyinSetting() else { return }
            self.updateKeys()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        composition = Composition()
        markedReading = ""
        selectedSegments.removeAll()
        alternatePage = nil
        keyPreview.isHidden = true
        setCandidatePanelVisible(false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
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

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if isViewLoaded, !updatingDocument, synchronizePinyinSetting() { updateKeys() }
    }

    private nonisolated static func loadLexicon(from url: URL?) -> Lexicon {
        let contents = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Lexicon(contents: contents)
    }

    private func refreshDocument(reloadCandidates: Bool = false) {
        let identifier = textDocumentProxy.documentIdentifier
        let changed = documentIdentifier != identifier
        if changed {
            composition = Composition()
            markedReading = ""
            selectedSegments.removeAll()
            alternatePage = nil
            setCandidatePanelVisible(false)
            documentIdentifier = identifier
        }
        if changed || reloadCandidates { _ = synchronizePinyinSetting() }
        if changed || reloadCandidates { render() } else { updateKeys() }
    }

    @discardableResult
    private func synchronizePinyinSetting() -> Bool {
        guard !composition.hasInput else { return false }
        let proxy = textDocumentProxy
        guard proxy.textContentType == .nickname, KeyboardPreferences.sharedPinyin == nil else { return false }
        let code = (proxy.documentContextBeforeInput ?? "") + (proxy.selectedText ?? "")
            + (proxy.documentContextAfterInput ?? "")
        guard let enabled = KeyboardPreferences.pinyinSetting(from: code), showsPinyin != enabled else { return false }
        KeyboardPreferences.saveLocally(enabled)
        showsPinyin = enabled
        return true
    }

    private func render() {
        if composition.hasInput {
            let words = lexicon?.candidates(for: composition, learned: userDictionary.candidates()) ?? []
            var shownEmoji: Set<String> = []
            candidates = words.flatMap { word -> [Candidate] in
                guard let emoji = Self.emojiByWord[word.text], shownEmoji.insert(emoji).inserted else {
                    return [word]
                }
                return [word, Candidate(text: emoji, reading: word.reading, isEmoji: true)]
            }
        } else if alternatePage == nil {
            candidates = Self.starterCandidates.map { Candidate(text: $0) }
        } else {
            candidates = []
        }
        while candidateButtons.count < candidates.count {
            let button = candidateButton()
            button.tag = candidateButtons.count
            button.setContentCompressionResistancePriority(UILayoutPriority(999), for: .horizontal)
            button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
            candidateButtons.append(button)
            candidateRow.addArrangedSubview(button)
        }
        for (index, button) in candidateButtons.enumerated() {
            button.isHidden = index >= candidates.count
            guard !button.isHidden, var configuration = button.configuration else { continue }
            configuration.title = candidates[index].text
            configuration.background.backgroundColor = index == 0 && composition.hasInput
                ? .secondarySystemGroupedBackground : .clear
            button.configuration = configuration
        }
        if candidateScroll.contentOffset != .zero { candidateScroll.setContentOffset(.zero, animated: false) }
        if showsCandidatePanel { updateCandidateGrid() }
        updateKeys()
    }

    private func candidateButton() -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 18)
            return attributes
        }
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
        button.configuration = configuration
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.addTarget(self, action: #selector(pressKey(_:)), for: .touchDown)
        return button
    }

    @objc private func selectCandidate(_ button: UIButton) {
        guard candidates.indices.contains(button.tag) else { return }
        choose(candidates[button.tag])
    }

    private func configureCandidatePanel() {
        candidateGridScroll.backgroundColor = .clear
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
        if let transition = candidateTransition {
            transition.stopAnimation(true)
            candidateTransition = nil
            finishCandidateTransition(showingCandidates: showsCandidatePanel)
        }
        showsCandidatePanel = visible
        let image = UIImage(systemName: visible ? "chevron.up" : "chevron.down",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        expandCandidates.setImage(image, for: .normal)
        expandCandidates.accessibilityLabel = visible ? "收起候选字词" : "展开候选字词"
        if visible {
            updateCandidateGrid()
            candidateGridScroll.setContentOffset(.zero, animated: false)
        }
        guard changed, animated, !UIAccessibility.isReduceMotionEnabled, keyArea.bounds.height > 0 else {
            finishCandidateTransition(showingCandidates: visible)
            return
        }

        let incoming: UIView = visible ? candidateGridScroll : rows
        let outgoing: UIView = visible ? rows : candidateGridScroll
        let direction: CGFloat = visible ? -1 : 1
        let distance: CGFloat = 22
        incoming.transform = CGAffineTransform(translationX: 0, y: direction * distance)
        incoming.alpha = 0
        incoming.isHidden = false
        incoming.isUserInteractionEnabled = false
        outgoing.isUserInteractionEnabled = false
        outgoing.accessibilityElementsHidden = true
        let transition = UIViewPropertyAnimator(duration: 0.20, curve: .easeInOut) {
            outgoing.transform = CGAffineTransform(translationX: 0, y: -direction * distance)
            outgoing.alpha = 0
            incoming.transform = .identity
            incoming.alpha = 1
        }
        transition.addCompletion { [weak self] _ in
            self?.candidateTransition = nil
            self?.finishCandidateTransition(showingCandidates: visible)
        }
        candidateTransition = transition
        transition.startAnimation()
    }

    private func finishCandidateTransition(showingCandidates: Bool) {
        rows.isHidden = showingCandidates
        rows.isUserInteractionEnabled = !showingCandidates
        rows.accessibilityElementsHidden = showingCandidates
        rows.transform = .identity
        rows.alpha = 1
        candidateGridScroll.isHidden = !showingCandidates
        candidateGridScroll.isUserInteractionEnabled = showingCandidates
        candidateGridScroll.accessibilityElementsHidden = !showingCandidates
        candidateGridScroll.transform = .identity
        candidateGridScroll.alpha = 1
    }

    private func updateCandidateGrid() {
        let availableWidth = keyArea.bounds.width
        guard availableWidth >= 44 else { return }
        candidateGridWidth = availableWidth
        candidateGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let spacing: CGFloat = 4
        var row = UIStackView()
        var occupied: CGFloat = 0

        for (index, candidate) in candidates.enumerated() {
            let button = candidateButton()
            var configuration = button.configuration
            configuration?.title = candidate.text
            button.configuration = configuration
            button.tag = index
            button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
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
        if globe != displayedGlobe || returnKey != displayedReturn || showsPinyin != displayedPinyin {
            keyLayouts.values.forEach { $0.removeFromSuperview() }
            keyLayouts.removeAll()
            displayedPage = nil
            displayedGlobe = globe
            displayedReturn = returnKey
            displayedPinyin = showsPinyin
        }
        guard page != displayedPage else { return }
        if let displayedPage { keyLayouts[displayedPage]?.isHidden = true }
        displayedPage = page
        if let cached = keyLayouts[page] {
            cached.isHidden = false
            return
        }
        let layout = UIStackView(arrangedSubviews: keysForPage().map(makeRow))
        layout.axis = .vertical
        layout.distribution = .fillEqually
        if #available(iOS 26.0, *) { layout.spacing = 11 } else { layout.spacing = 8 }
        layout.translatesAutoresizingMaskIntoConstraints = false
        rows.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: rows.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: rows.trailingAnchor),
            layout.topAnchor.constraint(equalTo: rows.topAnchor),
            layout.bottomAnchor.constraint(equalTo: rows.bottomAnchor)
        ])
        keyLayouts[page] = layout
    }

    private func keysForPage() -> [[Key]] {
        let isPhonetic = alternatePage == nil
        let isSymbols = page == .symbols
        let modifierWeight: CGFloat = page == .finals ? 1.1 : 1
        let shift = Key("", weight: modifierWeight, image: page == .finals ? "shift.fill" : "shift",
                        label: page == .finals ? "声母页" : "韵母页") { [weak self] in
            self?.composition.togglePage()
            self?.updateKeys()
        }
        let backspace = Key("", weight: modifierWeight, image: "delete.left", label: "删除") { [weak self] in self?.delete() }
        let space = Key(isPhonetic ? "注" : "空格",
                        weight: 5.42, label: isPhonetic ? "空格或一声" : "空格") { [weak self] in self?.space() }
        let enter = Key(returnTitle == "换行" ? "" : returnTitle, weight: 2.15,
                        image: returnTitle == "换行" ? "return" : nil,
                        label: returnTitle) { [weak self] in self?.enter() }
        let numbers = Key(isPhonetic ? "123" : "ㄅㄆㄇ", label: isPhonetic ? "数字页" : "返回注音") { [weak self] in
            self?.showAlternatePage(isPhonetic ? .numbers : nil)
        }
        let symbols = Key(isSymbols ? "123" : "#+=", weight: 1.4,
                          label: isSymbols ? "数字页" : "符号页") { [weak self] in
            self?.showAlternatePage(isSymbols ? .numbers : .symbols)
        }
        let bottom = [numbers] + (needsInputModeSwitchKey ? [Key("", image: "globe", label: "切换键盘")] : [])
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
                literals("－／：；（）￥＆＠＂"),
                [symbols] + literals("，。！？、＇…") + [backspace],
                bottom
            ]
        case .symbols:
            return [
                literals("[]{}#%^*+="),
                literals("_\\|~<>€£¥•"),
                [symbols] + literals(".,?!'@/") + [backspace],
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
                    if !key.title.isEmpty,
                       key.pinyin != nil || key.accessibilityLabel == nil || "ˊˇˋ˙".contains(key.title) {
                        button.previewTitle = key.title
                    }
                    button.addTarget(self, action: #selector(pressKey(_:)), for: .touchDown)
                    button.addTarget(self, action: #selector(hideKeyPreview), for: [
                        .touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel
                    ])
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

    private func configureKeyPreview() {
        keyPreview.isHidden = true
        keyPreview.isUserInteractionEnabled = false
        keyPreview.isAccessibilityElement = false
        keyPreview.textAlignment = .center
        keyPreview.textColor = .label
        keyPreview.backgroundColor = .secondarySystemGroupedBackground
        keyPreview.font = .systemFont(ofSize: 30)
        keyPreview.layer.cornerRadius = 9
        keyPreview.clipsToBounds = true
        view.addSubview(keyPreview)
    }

    @objc private func pressKey(_ sender: UIButton) {
        UIDevice.current.playInputClick()
        if hasFullAccess {
            keyHaptic.selectionChanged()
            keyHaptic.prepare()
        }
        guard let title = (sender as? KeyboardButton)?.previewTitle else { return }
        let key = sender.convert(sender.bounds, to: view)
        let width = max(44, key.width + 12)
        let x = min(max(2, key.midX - width / 2), view.bounds.width - width - 2)
        keyPreview.frame = CGRect(x: x, y: max(0, key.minY - 39), width: width, height: 42)
        keyPreview.text = title
        keyPreview.isHidden = false
    }

    @objc private func hideKeyPreview() {
        keyPreview.isHidden = true
    }

    private func showAlternatePage(_ page: Page?) {
        alternatePage = page
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
        consumeSelection(candidate)
        if !candidate.isEmoji, !candidate.reading.isEmpty { userDictionary.save() }
        setCandidatePanelVisible(false, animated: true)
        commit(candidate.text)
        updateComposition()
    }

    private func consumeSelection(_ candidate: Candidate) {
        composition.consume(candidate.syllableCount)
        if candidate.isEmoji {
            selectedSegments.removeAll()
        } else if !candidate.reading.isEmpty {
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
        guard composition.hasInput else { return }
        if lexicon == nil { lexicon = Self.loadLexicon(from: lexiconURL) }
        var text = ""
        // Resolve any remaining syllables before writing to the host field.
        while composition.hasInput,
              let candidate = lexicon?.candidates(for: composition, learned: userDictionary.candidates()).first {
            text += candidate.text
            consumeSelection(candidate)
        }
        if !text.isEmpty { userDictionary.save() }
        if composition.hasInput {
            text += composition.display
            composition = Composition()
            selectedSegments.removeAll()
        }
        setCandidatePanelVisible(false, animated: true)
        commit(text)
        render()
    }
}

private final class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

private final class KeyboardButton: UIButton {
    var previewTitle: String?

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.62 : 1 }
    }
}
