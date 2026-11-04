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

    private static let starterCandidates = [
        "我", "你", "这", "那", "他", "有", "因为", "我们",
        "你好", "谢谢", "可以", "今天", "怎么", "现在", "知道", "好的"
    ]
    private static let candidateFont = UIFont.systemFont(ofSize: 19)
    private static let candidateBarHeight: CGFloat = 44
    private static let portraitKeyHeight: CGFloat = 42
    private static let portraitKeySpacing: CGFloat = 9
    private static let emojiByWord = [
        "想": "🤔", "下": "⬇️", "心": "❤️", "爱": "❤️", "你好": "👋", "再见": "👋",
        "笑": "😄", "哈哈": "😂", "哭": "😢", "生气": "😡", "谢谢": "🙏", "赞": "👍",
        "恭喜": "🎉", "生日": "🎂", "生日快乐": "🎂", "晚安": "🌙", "太阳": "☀️", "下雨": "🌧️",
        "苹果": "🍎", "咖啡": "☕", "猫": "🐱", "狗": "🐶", "花": "🌸", "火": "🔥"
    ]
    private var showsPinyin = KeyboardPreferences.localPinyin
    private var preferenceLoad: Task<Void, Never>?
    private var composition = Composition()
    private var markedReading = ""
    private var updatingDocument = false
    private lazy var userDictionary = UserDictionary()
    private var selectedSegments: [Candidate] = []
    private let lexiconURL = Bundle(for: KeyboardViewController.self).url(forResource: "Lexicon", withExtension: "tsv")
    private static let lexiconLoad = Task.detached(priority: .utility) {
        let url = Bundle(for: KeyboardViewController.self).url(forResource: "Lexicon", withExtension: "tsv")
        return KeyboardViewController.loadLexicon(from: url)
    }
    private var awaitingLexicon = false
    private var lexicon: Lexicon?
    private var alternatePage: Page?
    private var documentIdentifier: UUID?
    private var candidates: [Candidate] = []
    private var displayedPage: Page?
    private var displayedGlobe = false
    private var displayedReturn = ""
    private var displayedPinyin = false
    private var keyLayouts: [Page: UIStackView] = [:]
    private var returnTitle = "换行"

    private let rows = UIView()
    private let keyArea = UIView()
    private let candidateScroll = UIScrollView()
    private var candidateButtons: [UIButton] = []
    private var displayedCandidates: [String] = []
    private var highlightsFirstCandidate = false
    private let expandCandidates = UIButton(type: .system)
    private let candidateGridScroll = UIScrollView()
    private var candidateGridButtons: [UIButton] = []
    private var showsCandidatePanel = false
    private var candidateTransition = 0
    private var candidateViewportWidth: CGFloat = 0
    private var candidateGridWidth: CGFloat = 0
    private var portraitKeyAreaHeight: NSLayoutConstraint?
    private let keyPreview = UILabel()
    private lazy var keyHaptic: UIImpactFeedbackGenerator = {
        if #available(iOS 17.5, *) {
            return UIImpactFeedbackGenerator(style: .soft, view: view)
        }
        return UIImpactFeedbackGenerator(style: .soft)
    }()

    private var page: Page { alternatePage ?? (composition.showsFinals ? .finals : .initials) }
    private func currentReturnTitle() -> String {
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
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.contentInsetAdjustmentBehavior = .never

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.widthAnchor.constraint(equalToConstant: 1 / 3).isActive = true
        expandCandidates.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let sideInset: CGFloat = 7
        var arrowConfiguration = UIButton.Configuration.plain()
        arrowConfiguration.baseForegroundColor = .label
        arrowConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
        expandCandidates.configuration = arrowConfiguration
        expandCandidates.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setCandidatePanelVisible(!self.showsCandidatePanel, animated: true)
        }, for: .touchUpInside)
        let toolbar = UIStackView(arrangedSubviews: [candidateScroll, divider, expandCandidates])
        toolbar.spacing = 3
        toolbar.heightAnchor.constraint(equalToConstant: Self.candidateBarHeight).isActive = true
        keyArea.clipsToBounds = true
        rows.translatesAutoresizingMaskIntoConstraints = false
        keyArea.addSubview(rows)
        candidateGridScroll.contentInsetAdjustmentBehavior = .never
        candidateGridScroll.translatesAutoresizingMaskIntoConstraints = false
        keyArea.addSubview(candidateGridScroll)

        let layout = UIStackView(arrangedSubviews: [toolbar, keyArea])
        layout.axis = .vertical
        layout.spacing = 2
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let area = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor, constant: sideInset),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor, constant: -sideInset),
            layout.topAnchor.constraint(equalTo: view.topAnchor, constant: 1),
            layout.bottomAnchor.constraint(equalTo: area.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor),
            rows.topAnchor.constraint(equalTo: keyArea.topAnchor),
            rows.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor),
            candidateGridScroll.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor),
            candidateGridScroll.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor),
            candidateGridScroll.topAnchor.constraint(equalTo: keyArea.topAnchor),
            candidateGridScroll.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor)
        ])
        if #available(iOS 26.0, *) {
            let height = keyArea.heightAnchor.constraint(
                equalToConstant: 4 * Self.portraitKeyHeight + 3 * Self.portraitKeySpacing
            )
            // Keep the initial size measurable without overriding a height imposed by the host.
            height.priority = UILayoutPriority(751)
            portraitKeyAreaHeight = height
            updatePreferredKeyAreaHeight()
        }
        setCandidatePanelVisible(false)

        configureKeyPreview()
        returnTitle = currentReturnTitle()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDocument(reloadCandidates: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prepareLexicon()
        if hasFullAccess { keyHaptic.prepare() }

        preferenceLoad?.cancel()
        let reading = Task.detached(priority: .utility) { KeyboardPreferences.showsPinyin }
        preferenceLoad = Task(priority: .utility) { [weak self] in
            let enabled = await reading.value
            guard let self, !Task.isCancelled, self.showsPinyin != enabled else { return }
            KeyboardPreferences.saveLocally(enabled)
            self.showsPinyin = enabled
            self.updateKeys()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.synchronizePinyinSetting() else { return }
            self.updateKeys()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        preferenceLoad?.cancel()
        composition = Composition()
        markedReading = ""
        selectedSegments.removeAll()
        alternatePage = nil
        keyPreview.isHidden = true
        setCandidatePanelVisible(false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePreferredKeyAreaHeight()
        if documentIdentifier != nil { updateKeys() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = candidateScroll.bounds.width
        let gridWidth = candidateGridScroll.bounds.width
        if viewport != candidateViewportWidth || gridWidth != candidateGridWidth {
            candidateViewportWidth = viewport
            candidateGridWidth = gridWidth
            updateCandidateArrow()
            if showsCandidatePanel { updateCandidateGrid() }
        }
    }

    private func updatePreferredKeyAreaHeight() {
        guard let height = portraitKeyAreaHeight else { return }
        let isPortraitPhone = traitCollection.userInterfaceIdiom == .phone
            && traitCollection.verticalSizeClass != .compact
        if height.isActive != isPortraitPhone { height.isActive = isPortraitPhone }
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

    private func prepareLexicon() {
        guard lexicon == nil, !awaitingLexicon else { return }
        awaitingLexicon = true
        let loading = Self.lexiconLoad
        Task(priority: .utility) { [weak self] in
            let loaded = await loading.value
            guard let self, self.lexicon == nil else { return }
            self.lexicon = loaded
            if self.composition.hasInput { self.render() }
        }
    }

    private func refreshDocument(reloadCandidates: Bool = false) {
        returnTitle = currentReturnTitle()
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
        preferenceLoad?.cancel()
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
        let titles = candidates.map(\.text)
        let highlight = composition.hasInput && !candidates.isEmpty
        if titles != displayedCandidates || highlight != highlightsFirstCandidate {
            displayedCandidates = titles
            highlightsFirstCandidate = highlight
            updateCandidateBar()
        }
        updateKeys()
    }

    private func updateCandidateBar() {
        var x: CGFloat = 0
        for (index, button) in candidateButtons.enumerated() {
            if index >= candidates.count { button.isHidden = true }
        }
        for index in candidates.indices {
            if index == candidateButtons.count {
                let button = candidateButton()
                candidateButtons.append(button)
                candidateScroll.addSubview(button)
            }
            let button = candidateButtons[index]
            let width = candidateWidth(at: index)
            configureCandidateButton(button, at: index)
            button.frame = CGRect(x: x, y: 0, width: width, height: Self.candidateBarHeight - 4)
            button.isHidden = false
            x += width + 1
        }
        candidateScroll.contentSize = CGSize(width: max(0, x - 1), height: Self.candidateBarHeight)
        candidateScroll.setContentOffset(.zero, animated: false)
        updateCandidateArrow()
        if showsCandidatePanel {
            updateCandidateGrid()
        } else {
            // A selection may refresh the first row while the old grid is fading out.
            candidateGridScroll.isHidden = true
        }
    }

    private func candidateWidth(at index: Int) -> CGFloat {
        let text = candidates[index].text as NSString
        return max(38, ceil(text.size(withAttributes: [.font: Self.candidateFont]).width) + 12)
    }

    private func candidateButton() -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        let font = Self.candidateFont
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        configuration.baseForegroundColor = .label
        configuration.buttonSize = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        button.configuration = configuration
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
        return button
    }

    private func configureCandidateButton(_ button: UIButton, at index: Int) {
        guard var configuration = button.configuration else { return }
        configuration.title = candidates[index].text
        configuration.background.backgroundColor = index == 0 && composition.hasInput
            ? .secondarySystemGroupedBackground : .clear
        button.configuration = configuration
        button.tag = index
    }

    @objc private func selectCandidate(_ button: UIButton) {
        guard candidates.indices.contains(button.tag) else { return }
        choose(candidates[button.tag])
    }

    private var hasMoreCandidates: Bool {
        candidateScroll.bounds.width > 0
            && candidateScroll.contentSize.width > candidateScroll.bounds.width + 0.5
    }

    private func updateCandidateArrow() {
        expandCandidates.isEnabled = showsCandidatePanel || hasMoreCandidates
    }

    private func setCandidatePanelVisible(_ visible: Bool, animated: Bool = false) {
        if visible, !hasMoreCandidates { return }
        let changed = showsCandidatePanel != visible
        guard changed || !animated else { return }
        showsCandidatePanel = visible
        candidateTransition += 1
        let transition = candidateTransition
        let image = UIImage(systemName: visible ? "chevron.up" : "chevron.down",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        var arrowConfiguration = expandCandidates.configuration
        arrowConfiguration?.image = image
        expandCandidates.configuration = arrowConfiguration
        expandCandidates.accessibilityLabel = visible ? "收起候选字词" : "展开候选字词"
        updateCandidateArrow()
        if visible {
            let maxOffset = max(0, candidateScroll.contentSize.width - candidateScroll.bounds.width)
            let offset = min(max(0, candidateScroll.contentOffset.x), maxOffset)
            candidateScroll.isScrollEnabled = false
            candidateScroll.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
            updateCandidateGrid()
            candidateGridScroll.setContentOffset(.zero, animated: false)
        }
        guard changed, animated, !UIAccessibility.isReduceMotionEnabled, keyArea.bounds.height > 0 else {
            rows.layer.removeAllAnimations()
            candidateGridScroll.layer.removeAllAnimations()
            finishCandidateTransition(showingCandidates: visible)
            return
        }

        // The first row and arrow stay put; only the content below them changes.
        rows.isHidden = false
        candidateGridScroll.isHidden = false
        rows.isUserInteractionEnabled = false
        candidateGridScroll.isUserInteractionEnabled = false
        rows.accessibilityElementsHidden = true
        candidateGridScroll.accessibilityElementsHidden = true
        UIView.animate(withDuration: 0.20, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.rows.transform = visible ? CGAffineTransform(translationX: 0, y: 22) : .identity
            self.rows.alpha = visible ? 0 : 1
            self.candidateGridScroll.alpha = visible ? 1 : 0
        } completion: { [weak self] _ in
            guard let self, self.candidateTransition == transition else { return }
            self.finishCandidateTransition(showingCandidates: visible)
        }
    }

    private func finishCandidateTransition(showingCandidates: Bool) {
        candidateScroll.isScrollEnabled = !showingCandidates
        if !showingCandidates {
            for index in candidates.indices { candidateButtons[index].isHidden = false }
        }
        rows.isHidden = showingCandidates
        rows.isUserInteractionEnabled = !showingCandidates
        rows.accessibilityElementsHidden = showingCandidates
        rows.transform = showingCandidates ? CGAffineTransform(translationX: 0, y: 22) : .identity
        rows.alpha = showingCandidates ? 0 : 1
        candidateGridScroll.isHidden = !showingCandidates
        candidateGridScroll.isUserInteractionEnabled = showingCandidates
        candidateGridScroll.accessibilityElementsHidden = !showingCandidates
        candidateGridScroll.alpha = showingCandidates ? 1 : 0
    }

    private func updateCandidateGrid() {
        let availableWidth = candidateGridScroll.bounds.width
        guard availableWidth > 0 else { return }
        let viewport = candidateScroll.bounds.insetBy(dx: -0.5, dy: 0)
        let spacing: CGFloat = 4
        let rowHeight: CGFloat = 38
        var x: CGFloat = 0
        var y: CGFloat = 0
        var buttonCount = 0

        for index in candidates.indices {
            // Keep the visible first row in place, including after a horizontal swipe.
            let inFirstRow = viewport.contains(candidateButtons[index].frame)
            candidateButtons[index].isHidden = !inFirstRow
            if inFirstRow { continue }

            let width = min(availableWidth, candidateButtons[index].frame.width)
            if x > 0, x + width > availableWidth {
                x = 0
                y += rowHeight + spacing
            }
            if buttonCount == candidateGridButtons.count {
                let button = candidateButton()
                candidateGridButtons.append(button)
                candidateGridScroll.addSubview(button)
            }
            let button = candidateGridButtons[buttonCount]
            configureCandidateButton(button, at: index)
            button.frame = CGRect(x: x, y: y, width: width, height: rowHeight)
            button.isHidden = false
            buttonCount += 1
            x += width + spacing
        }
        for button in candidateGridButtons.dropFirst(buttonCount) { button.isHidden = true }
        candidateGridScroll.contentSize = CGSize(width: availableWidth, height: buttonCount > 0 ? y + rowHeight : 0)
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
        if #available(iOS 26.0, *) { layout.spacing = Self.portraitKeySpacing } else { layout.spacing = 8 }
        // The host can measure the keyboard before giving it a height.
        // Keep the key rows in the constraint chain so they contribute their intrinsic size.
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
        let bottom = [numbers] + (displayedGlobe ? [Key("", image: "globe", label: "切换键盘")] : [])
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
                            : .white
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
                } else {
                    button.setTitle(key.title, for: .normal)
                    button.titleLabel?.font = .systemFont(ofSize: key.accessibilityLabel == nil ? 22 : 15)
                    button.titleLabel?.adjustsFontSizeToFitWidth = true
                    button.titleLabel?.minimumScaleFactor = 0.65
                    if showsPinyin, let pinyin = key.pinyin {
                        // Keep the same one-line title for sizing and draw the caption inside the key.
                        button.setTitleColor(.clear, for: .normal)
                        button.setTitleColor(.clear, for: .highlighted)
                        let caption = UILabel(frame: button.bounds)
                        caption.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                        caption.numberOfLines = 2
                        caption.textAlignment = .center
                        caption.isAccessibilityElement = false
                        let text = NSMutableAttributedString(string: key.title, attributes: [
                            .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label
                        ])
                        text.append(NSAttributedString(string: "\n" + pinyin, attributes: [
                            .font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.secondaryLabel
                        ]))
                        caption.attributedText = text
                        button.addSubview(caption)
                        button.accessibilityLabel = "\(key.title)，\(pinyin)"
                    }
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
            keyHaptic.impactOccurred()
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
        if composition.hasInput { prepareLexicon() }
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
    private var shadowBounds: CGRect?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard shadowBounds != bounds else { return }
        shadowBounds = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.62 : 1 }
    }
}
