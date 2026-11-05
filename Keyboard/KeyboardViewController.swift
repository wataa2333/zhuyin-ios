import AVFAudio
import UIKit

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private enum Page: Hashable { case initials, finals, numbers, symbols }

    private struct Key {
        let title: String
        let weight: CGFloat
        let systemImage: String?
        let accessibilityLabel: String?
        let pinyin: String?
        let activatesOnTouchDown: Bool
        let isDeleteKey: Bool
        let action: (() -> Void)?

        init(_ title: String, weight: CGFloat = 1, image: String? = nil,
             label: String? = nil, pinyin: String? = nil, activatesOnTouchDown: Bool = false, isDeleteKey: Bool = false,
             action: (() -> Void)? = nil) {
            self.title = title
            self.weight = weight
            systemImage = image
            accessibilityLabel = label
            self.pinyin = pinyin
            self.activatesOnTouchDown = activatesOnTouchDown
            self.isDeleteKey = isDeleteKey
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
    private static let candidateBarHeight = KeyboardLayoutConfiguration.candidateBarHeight
    private static let emojiByWord = [
        "想": "🤔", "下": "⬇️", "心": "❤️", "爱": "❤️", "你好": "👋", "再见": "👋",
        "笑": "😄", "哈哈": "😂", "哭": "😢", "生气": "😡", "谢谢": "🙏", "赞": "👍",
        "恭喜": "🎉", "生日": "🎂", "生日快乐": "🎂", "晚安": "🌙", "太阳": "☀️", "下雨": "🌧️",
        "苹果": "🍎", "咖啡": "☕", "猫": "🐱", "狗": "🐶", "花": "🌸", "火": "🔥"
    ]
    private var showsPinyin = KeyboardPreferences.localPinyin
    private var preferenceLoad: Task<Void, Never>?
    private var composition = Composition()
    private var textWriter = CompositionTextWriter()
    private var updatingDocument = false
    private lazy var userDictionary = UserDictionary()
    private var selectedSegments: [Candidate] = []
    private static let lexiconLoad = Task.detached(priority: .utility) {
        KeyboardViewController.loadLexicon()
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
    private var isSearchField = false
    private var keyboardWarmup: Task<Void, Never>?

    private let rows = UIView()
    private let keyArea = UIView()
    private let candidateScroll = CandidateScrollView()
    private var candidateButtons: [UIButton] = []
    private var displayedCandidates: [String] = []
    private var highlightsFirstCandidate = false
    private var candidateRefreshPending = false
    private let expandCandidates = UIButton(type: .system)
    private let candidateGridScroll = CandidateScrollView()
    private var candidateGridButtons: [UIButton] = []
    private lazy var candidatePanel = CandidatePanelController(
        keyboard: rows, candidates: candidateGridScroll, toggle: expandCandidates
    )
    private var showsCandidatePanel: Bool { candidatePanel.isExpanded }
    private var candidateGridNeedsLayout = true
    private var candidateGridFirstRowBounds = CGRect.null
    private var candidateViewportWidth: CGFloat = 0
    private var candidateGridWidth: CGFloat = 0
    private var portraitKeyAreaHeight: NSLayoutConstraint?
    private var appliedLayout: KeyboardLayoutConfiguration?
    private let keyPreview = UILabel()
    private weak var previewKey: UIButton?
    private var deleteHoldBounds: CGRect?
    private var deleteRepeatTask: Task<Void, Never>?
    private var feedback = KeyboardPreferences.localFeedback {
        didSet {
            if oldValue.haptics != feedback.haptics { keyHaptic = nil }
            if feedback.volume == 0 { clickPlayers.values.forEach { $0.stop() } }
        }
    }
    private var canPlayKeyFeedback = false
    private var keyHaptic: UIImpactFeedbackGenerator?
    private var clickPlayers: [Bool: AVAudioPlayer] = [:]
    private var attemptedClickSetup = false

    private var page: Page { alternatePage ?? (composition.showsFinals ? .finals : .initials) }
    private func refreshInputTraits(from proxy: UITextDocumentProxy) {
        let returnKeyType = proxy.returnKeyType
        isSearchField = returnKeyType == .search || returnKeyType == .google
            || returnKeyType == .yahoo || proxy.keyboardType == .webSearch
        returnTitle = title(for: returnKeyType)
    }

    private func title(for returnKeyType: UIReturnKeyType?) -> String {
        switch returnKeyType {
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
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.contentInsetAdjustmentBehavior = .never

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        let dividerSlot = UIView()
        dividerSlot.addSubview(divider)
        NSLayoutConstraint.activate([
            dividerSlot.widthAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
            divider.leadingAnchor.constraint(equalTo: dividerSlot.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: dividerSlot.trailingAnchor),
            divider.centerYAnchor.constraint(equalTo: dividerSlot.centerYAnchor),
            divider.heightAnchor.constraint(equalToConstant: KeyboardLayoutConfiguration.dividerHeight)
        ])
        let sideInset: CGFloat = 7
        let arrowSlot = UIView()
        arrowSlot.addSubview(expandCandidates)
        expandCandidates.translatesAutoresizingMaskIntoConstraints = false
        var arrowConfiguration = UIButton.Configuration.plain()
        arrowConfiguration.baseForegroundColor = .label
        arrowConfiguration.image = UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        arrowConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 4, trailing: sideInset)
        expandCandidates.configuration = arrowConfiguration
        candidatePanel.onToggleRequested = { [weak self] in
            guard let self else { return }
            guard !self.expandCandidates.isHidden else { return }
            self.setCandidatePanelVisible(!self.showsCandidatePanel)
            self.playKeyFeedback()
        }
        let toolbar = UIStackView(arrangedSubviews: [candidateScroll, dividerSlot, arrowSlot])
        toolbar.insetsLayoutMarginsFromSafeArea = false
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0)
        toolbar.spacing = 3
        toolbar.heightAnchor.constraint(equalToConstant: Self.candidateBarHeight).isActive = true
        keyArea.clipsToBounds = true
        rows.translatesAutoresizingMaskIntoConstraints = false
        keyArea.addSubview(rows)
        configureDeleteHold()
        candidateGridScroll.contentInsetAdjustmentBehavior = .never
        candidateGridScroll.translatesAutoresizingMaskIntoConstraints = false
        keyArea.addSubview(candidateGridScroll)

        let layout = UIStackView(arrangedSubviews: [toolbar, keyArea])
        layout.axis = .vertical
        layout.spacing = KeyboardLayoutConfiguration.toolbarSpacing
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let area = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            layout.topAnchor.constraint(equalTo: view.topAnchor, constant: KeyboardLayoutConfiguration.topInset),
            layout.bottomAnchor.constraint(equalTo: area.bottomAnchor),
            arrowSlot.widthAnchor.constraint(equalToConstant: 44 + sideInset),
            expandCandidates.leadingAnchor.constraint(equalTo: arrowSlot.leadingAnchor),
            expandCandidates.trailingAnchor.constraint(equalTo: arrowSlot.trailingAnchor),
            expandCandidates.topAnchor.constraint(equalTo: arrowSlot.topAnchor),
            expandCandidates.bottomAnchor.constraint(equalTo: arrowSlot.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: sideInset),
            rows.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -sideInset),
            rows.topAnchor.constraint(equalTo: keyArea.topAnchor),
            rows.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor),
            candidateGridScroll.leadingAnchor.constraint(equalTo: rows.leadingAnchor),
            candidateGridScroll.trailingAnchor.constraint(equalTo: rows.trailingAnchor),
            candidateGridScroll.topAnchor.constraint(equalTo: keyArea.topAnchor),
            candidateGridScroll.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor)
        ])
        let height = keyArea.heightAnchor.constraint(
            equalToConstant: KeyboardLayoutConfiguration.portrait.keyAreaHeight
        )
        height.priority = UILayoutPriority(999)
        height.isActive = true
        portraitKeyAreaHeight = height
        updatePreferredKeyAreaHeight()
        setCandidatePanelVisible(false, animated: false)

        configureKeyPreview()
        // viewWillAppear reads the input traits and builds the initial page once.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        canPlayKeyFeedback = hasFullAccess
        refreshDocument(reloadCandidates: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        keyboardWarmup?.cancel()
        keyboardWarmup = Task { [weak self] in
            // Prepare only the database handle after the first frame; no word list is parsed here.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            // Spotlight needs only its initial page until the user starts composing.
            guard !self.isSearchField else { return }
            self.prepareFinalsPage()
            self.prepareLexicon()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self.hapticGenerator()?.prepare()
            self.prepareClickPlayers()
            self.clickPlayers.values.forEach { _ = $0.prepareToPlay() }
        }

        preferenceLoad?.cancel()
        let previousFeedback = feedback
        let reading = Task.detached(priority: .utility) {
            (KeyboardPreferences.showsPinyin, KeyboardPreferences.sharedFeedback ?? KeyboardPreferences.localFeedback)
        }
        preferenceLoad = Task(priority: .utility) { [weak self] in
            let (enabled, feedback) = await reading.value
            guard let self, !Task.isCancelled else { return }
            if self.feedback == previousFeedback, self.feedback != feedback {
                KeyboardPreferences.saveLocally(feedback)
                self.feedback = feedback
            }
            guard self.showsPinyin != enabled else { return }
            KeyboardPreferences.saveLocally(enabled)
            self.showsPinyin = enabled
            self.updateKeys()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isSearchField, self.synchronizeSettings() else { return }
            self.updateKeys()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDeleteHold()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboardWarmup?.cancel()
        preferenceLoad?.cancel()
        clickPlayers.values.forEach { $0.stop() }
        if clickPlayers.isEmpty { attemptedClickSetup = false }
        composition = Composition()
        textWriter.reset()
        selectedSegments.removeAll()
        alternatePage = nil
        keyPreview.isHidden = true
        previewKey = nil
        candidateRefreshPending = false
        setCandidatePanelVisible(false, animated: false)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updatePreferredKeyAreaHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = candidateScroll.bounds.width
        let gridWidth = candidateGridScroll.bounds.width
        if viewport != candidateViewportWidth || gridWidth != candidateGridWidth {
            candidateViewportWidth = viewport
            candidateGridWidth = gridWidth
            candidateGridNeedsLayout = true
            refreshCandidatePanel()
        }
    }

    private func updatePreferredKeyAreaHeight() {
        guard let height = portraitKeyAreaHeight else { return }
        let configuration: KeyboardLayoutConfiguration = traitCollection.verticalSizeClass == .compact ? .compact : .portrait
        guard configuration != appliedLayout else { return }
        appliedLayout = configuration
        height.constant = configuration.keyAreaHeight
        (inputView as? KeyboardInputView)?.contentHeight = configuration.contentHeight
        for layout in keyLayouts.values { layout.spacing = configuration.rowSpacing }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if isViewLoaded, !updatingDocument { refreshDocument() }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if isViewLoaded, !isSearchField, !updatingDocument, synchronizeSettings() { updateKeys() }
    }

    private nonisolated static func loadLexicon() -> Lexicon {
        let bundle = Bundle(for: KeyboardViewController.self)
        if let url = bundle.url(forResource: "Lexicon", withExtension: "sqlite"),
           let indexed = try? Lexicon(databaseURL: url) { return indexed }
        // The small legacy dictionary is an emergency fallback for a damaged/missing database.
        let contents = bundle.url(forResource: "Lexicon", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
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
            if self.composition.hasInput { self.scheduleCandidateRefresh() }
        }
    }

    private func refreshDocument(reloadCandidates: Bool = false) {
        let proxy = textDocumentProxy
        let wasSearchField = isSearchField
        refreshInputTraits(from: proxy)
        let identifier = proxy.documentIdentifier
        let changed = documentIdentifier != identifier
        if changed {
            stopDeleteHold()
            composition = Composition()
            textWriter.reset()
            selectedSegments.removeAll()
            alternatePage = nil
            setCandidatePanelVisible(false, animated: false)
            documentIdentifier = identifier
        }
        if !isSearchField, changed || reloadCandidates { _ = synchronizeSettings() }
        updateKeys()
        if isSearchField && !composition.hasInput {
            // Keep the toolbar's height, but skip the idle candidate buttons in search fields.
            candidateRefreshPending = false
            if !candidates.isEmpty { renderCandidates() }
        } else if changed || reloadCandidates || wasSearchField != isSearchField {
            scheduleCandidateRefresh()
        }
    }

    @discardableResult
    private func synchronizeSettings() -> Bool {
        guard !composition.hasInput else { return false }
        let proxy = textDocumentProxy
        guard proxy.textContentType == .nickname else { return false }
        let code = (proxy.documentContextBeforeInput ?? "") + (proxy.selectedText ?? "")
            + (proxy.documentContextAfterInput ?? "")
        guard let settings = KeyboardPreferences.syncSettings(from: code) else { return false }
        if let syncedFeedback = settings.feedback, syncedFeedback != feedback, KeyboardPreferences.sharedFeedback == nil {
            KeyboardPreferences.saveLocally(syncedFeedback)
            feedback = syncedFeedback
        }
        guard showsPinyin != settings.pinyin, KeyboardPreferences.sharedPinyin == nil else { return false }
        preferenceLoad?.cancel()
        KeyboardPreferences.saveLocally(settings.pinyin)
        showsPinyin = settings.pinyin
        return true
    }

    private func render() {
        updateKeys()
        renderCandidates()
    }

    private func scheduleCandidateRefresh() {
        guard !candidateRefreshPending else { return }
        candidateRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.candidateRefreshPending else { return }
            self.renderCandidates()
        }
    }

    private func renderCandidates() {
        candidateRefreshPending = false
        if composition.hasInput {
            let words = lexicon?.candidates(for: composition, learned: userDictionary.candidates()) ?? []
            var shownEmoji: Set<String> = []
            candidates = words.flatMap { word -> [Candidate] in
                guard let emoji = Self.emojiByWord[word.text], shownEmoji.insert(emoji).inserted else {
                    return [word]
                }
                return [word, Candidate(text: emoji, reading: word.reading, isEmoji: true)]
            }
        } else if alternatePage == nil && !isSearchField {
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
    }

    private func updateCandidateBar() {
        candidateGridNeedsLayout = true
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
        refreshCandidatePanel()
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
        let selected = candidates[button.tag]
        if candidateRefreshPending {
            // Preserve the tapped word across refreshes instead of using a possibly changed button tag.
            renderCandidates()
            guard candidates.contains(where: {
                $0.text == selected.text && $0.readingCode == selected.readingCode && $0.isEmoji == selected.isEmoji
            }) else { return }
        }
        playKeyFeedback()
        choose(selected)
    }

    private var hasMoreCandidates: Bool {
        candidateScroll.bounds.width > 0
            && candidateScroll.contentSize.width > candidateScroll.bounds.width + 0.5
    }

    private func updateCandidateArrow() {
        expandCandidates.isHidden = !showsCandidatePanel && !hasMoreCandidates
    }

    private func refreshCandidatePanel() {
        if showsCandidatePanel, candidateScroll.bounds.width > 0, !hasMoreCandidates {
            setCandidatePanelVisible(false)
        } else {
            updateCandidateArrow()
            if showsCandidatePanel { updateCandidateGrid() }
        }
    }

    private func setCandidatePanelVisible(_ visible: Bool, animated: Bool = true) {
        if visible, !hasMoreCandidates { return }
        if visible, !showsCandidatePanel {
            stopDeleteHold()
            keyPreview.isHidden = true
            previewKey = nil
            let maxOffset = max(0, candidateScroll.contentSize.width - candidateScroll.bounds.width)
            let offset = min(max(0, candidateScroll.contentOffset.x), maxOffset)
            candidateScroll.isScrollEnabled = false
            candidateScroll.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
            updateCandidateGrid()
            candidateGridScroll.setContentOffset(.zero, animated: false)
        }
        candidateScroll.isScrollEnabled = !visible
        candidatePanel.setExpanded(visible, animated: animated)
        updateCandidateArrow()
    }

    private func updateCandidateGrid() {
        let availableWidth = candidateGridScroll.bounds.width
        guard availableWidth > 0 else { return }
        let viewport = candidateScroll.bounds.insetBy(dx: -0.5, dy: 0)
        guard candidateGridNeedsLayout || candidateGridFirstRowBounds != viewport else { return }
        candidateGridNeedsLayout = false
        candidateGridFirstRowBounds = viewport
        let spacing: CGFloat = 4
        let rowHeight: CGFloat = 38
        var x: CGFloat = 0
        var y: CGFloat = 0
        var buttonCount = 0

        for index in candidates.indices {
            // The toolbar is identical in both states, including partially clipped words.
            // Repeat a clipped word below so its full title remains accessible.
            let inFirstRow = viewport.contains(candidateButtons[index].frame)
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
        if globe != displayedGlobe || returnTitle != displayedReturn {
            displayedGlobe = globe
            displayedReturn = returnTitle
            for (page, layout) in keyLayouts {
                layout.arrangedSubviews.last?.removeFromSuperview()
                layout.addArrangedSubview(makeRow(bottomKeys(for: page)))
            }
        }
        if showsPinyin != displayedPinyin {
            displayedPinyin = showsPinyin
            for layout in keyLayouts.values {
                for case let row as KeyboardKeyRow in layout.arrangedSubviews {
                    for case let button as KeyboardButton in row.subviews {
                        button.setPinyinVisible(showsPinyin)
                    }
                }
            }
        }
        showKeyPage()
    }

    private func showKeyPage() {
        let page = self.page
        guard page != displayedPage else { return }
        let layout = keyLayout(for: page)
        if let displayedPage { keyLayouts[displayedPage]?.isHidden = true }
        displayedPage = page
        layout.isHidden = false
        if layout.bounds.isEmpty, !rows.bounds.isEmpty { rows.layoutIfNeeded() }
    }

    private func prepareFinalsPage() {
        guard keyLayouts[.finals] == nil else { return }
        _ = keyLayout(for: .finals)
        if !rows.bounds.isEmpty { rows.layoutIfNeeded() }
    }

    private func keyLayout(for page: Page) -> UIStackView {
        if let cached = keyLayouts[page] { return cached }
        let layout = UIStackView(arrangedSubviews: (keysForPage(page) + [bottomKeys(for: page)]).map(makeRow))
        layout.axis = .vertical
        layout.distribution = .fillEqually
        layout.isHidden = true
        layout.spacing = (appliedLayout ?? .portrait).rowSpacing
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
        return layout
    }

    private func keysForPage(_ page: Page) -> [[Key]] {
        let isSymbols = page == .symbols
        let modifierWeight: CGFloat = page == .finals ? 1.1 : 1
        let shift = Key("", weight: modifierWeight, image: page == .finals ? "shift.fill" : "shift",
                        label: page == .finals ? "声母页" : "韵母页", activatesOnTouchDown: true) { [weak self] in
            self?.composition.togglePage()
            self?.showKeyPage()
        }
        let backspace = Key("", weight: modifierWeight, image: "delete.left", label: "删除",
                            activatesOnTouchDown: true, isDeleteKey: true) { [weak self] in self?.delete() }
        let symbols = Key(isSymbols ? "123" : "#+=", weight: 1.4,
                          label: isSymbols ? "数字页" : "符号页") { [weak self] in
            self?.showAlternatePage(isSymbols ? .numbers : .symbols)
        }
        switch page {
        case .initials:
            return [
                [Key("", weight: 0.43)] + phonetics("ㄅㄆㄇㄈㄉㄊㄋㄌ") + [Key("", weight: 0.43)],
                phonetics("ㄍㄎㄏㄐㄑㄒㄧㄨㄩ"),
                [shift] + phonetics("ㄓㄔㄕㄖㄗㄘㄙ") + [backspace]
            ]
        case .finals:
            let tones = zip("ˊˇˋ˙", "2345").map { symbol, tone in
                Key(String(symbol), weight: 1.55, label: "声调 \(tone)", activatesOnTouchDown: true) { [weak self] in
                    self?.composition.finish(tone: tone)
                    self?.updateComposition()
                }
            }
            return [
                [Key("", weight: 0.43)] + phonetics("ㄚㄛㄜㄝㄞㄟㄠㄡ") + [Key("", weight: 0.43)],
                [Key("")] + phonetics("ㄢㄣㄤㄥㄦㄧㄨㄩ"),
                [shift, Key("", weight: 0.30)] + tones + [Key("", weight: 0.30), backspace]
            ]
        case .numbers:
            return [
                literals("1234567890"),
                literals("－／：；（）￥＆＠＂"),
                [symbols] + literals("，。！？、＇…") + [backspace]
            ]
        case .symbols:
            return [
                literals("[]{}#%^*+="),
                literals("_\\|~<>€£¥•"),
                [symbols] + literals(".,?!'@/") + [backspace]
            ]
        }
    }

    private func bottomKeys(for page: Page) -> [Key] {
        let isPhonetic = page == .initials || page == .finals
        let numbers = Key(isPhonetic ? "123" : "ㄅㄆㄇ", label: isPhonetic ? "数字页" : "返回注音") { [weak self] in
            self?.showAlternatePage(isPhonetic ? .numbers : nil)
        }
        let space = Key(isPhonetic ? "注" : "空格",
                        weight: 5.42, label: isPhonetic ? "空格或一声" : "空格",
                        activatesOnTouchDown: isPhonetic) { [weak self] in self?.space() }
        let enter = Key(returnTitle == "换行" ? "" : returnTitle, weight: 2.15,
                        image: returnTitle == "换行" ? "return" : nil,
                        label: returnTitle) { [weak self] in self?.enter() }
        return [numbers] + (displayedGlobe ? [Key("", image: "globe", label: "切换键盘")] : [])
            + [space, enter]
    }

    private func phonetics(_ symbols: String) -> [Key] {
        symbols.map { symbol in
            Key(String(symbol), pinyin: Self.pinyinBySymbol[symbol], activatesOnTouchDown: true) { [weak self] in
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

    private func makeRow(_ keys: [Key]) -> KeyboardKeyRow {
        let views = keys.map { key -> UIView in
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
                    button.pinyin = key.pinyin
                    if showsPinyin { button.setPinyinVisible(true) }
                }
                if let action = key.action {
                    button.isDeleteKey = key.isDeleteKey
                    if !key.title.isEmpty,
                       key.pinyin != nil || key.accessibilityLabel == nil || "ˊˇˋ˙".contains(key.title) {
                        button.previewTitle = key.title
                    }
                    button.activatesOnTouchDown = key.activatesOnTouchDown
                    button.addAction(UIAction { [weak self, weak button] _ in
                        guard let self, let button, self.isOnDisplayedPage(button) else { return }
                        self.pressKey(button)
                        if key.activatesOnTouchDown { action() }
                    }, for: .touchDown)
                    button.addTarget(self, action: #selector(hideKeyPreview(_:)), for: [
                        .touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel
                    ])
                    if !key.activatesOnTouchDown {
                        button.addAction(UIAction { [weak self, weak button] _ in
                            guard let self, let button, self.isOnDisplayedPage(button) else { return }
                            action()
                        }, for: .touchUpInside)
                    }
                } else {
                    button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
                }
                element = button
            }
            return element
        }
        return KeyboardKeyRow(views: views, weights: keys.map(\.weight))
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

    private func isOnDisplayedPage(_ button: UIButton) -> Bool {
        guard let displayedPage, let layout = keyLayouts[displayedPage] else { return false }
        return button.isDescendant(of: layout)
    }

    private func hapticGenerator() -> UIImpactFeedbackGenerator? {
        guard canPlayKeyFeedback, feedback.haptics > 0 else { return nil }
        if let keyHaptic { return keyHaptic }
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch feedback.haptics {
        case 3: style = .heavy
        case 2: style = .medium
        default: style = .light
        }
        let generator: UIImpactFeedbackGenerator
        if #available(iOS 17.5, *) {
            generator = UIImpactFeedbackGenerator(style: style, view: view)
        } else {
            generator = UIImpactFeedbackGenerator(style: style)
        }
        keyHaptic = generator
        return generator
    }

    private func prepareClickPlayers() {
        guard canPlayKeyFeedback, feedback.volume > 0, !attemptedClickSetup else { return }
        attemptedClickSetup = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            return
        }
        let bundle = Bundle(for: KeyboardViewController.self)
        for (deleting, name) in [(false, "tap"), (true, "delete")] {
            guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "KeySounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            clickPlayers[deleting] = player
        }
    }

    private func playKeyFeedback(at location: CGPoint? = nil, deleting: Bool = false) {
        guard canPlayKeyFeedback else { return }
        if feedback.volume > 0 {
            prepareClickPlayers()
            if let player = clickPlayers[deleting] {
                player.volume = Float(feedback.volume) / 100
                player.currentTime = 0
                player.play()
            }
        }
        if let keyHaptic = hapticGenerator() {
            if #available(iOS 17.5, *), let location {
                keyHaptic.impactOccurred(at: location)
            } else {
                keyHaptic.impactOccurred()
            }
            keyHaptic.prepare()
        }
    }

    private func pressKey(_ sender: KeyboardButton) {
        if !sender.isDeleteKey { stopDeleteHold() }
        playKeyFeedback(at: sender.convert(CGPoint(x: sender.bounds.midX, y: sender.bounds.midY), to: view),
                        deleting: sender.isDeleteKey)
        guard let title = sender.previewTitle else { return }
        let key = sender.convert(sender.bounds, to: view)
        let width = max(44, key.width + 12)
        let x = min(max(2, key.midX - width / 2), view.bounds.width - width - 2)
        keyPreview.frame = CGRect(x: x, y: max(0, key.minY - 39), width: width, height: 42)
        keyPreview.text = title
        keyPreview.isHidden = false
        previewKey = sender
    }

    @objc private func hideKeyPreview(_ sender: UIButton) {
        guard previewKey === sender else { return }
        keyPreview.isHidden = true
        previewKey = nil
    }

    private func showAlternatePage(_ page: Page?) {
        alternatePage = page
        render()
    }

    private func configureDeleteHold() {
        // Track on the shared container so deletion can cross from the finals page to initials.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteHold(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 14
        hold.cancelsTouchesInView = false
        hold.delaysTouchesBegan = false
        hold.delaysTouchesEnded = false
        hold.delegate = self
        rows.addGestureRecognizer(hold)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let current = target, current !== rows {
            if let key = current as? KeyboardButton, key.isDeleteKey, isOnDisplayedPage(key) {
                deleteHoldBounds = key.convert(key.bounds, to: rows).insetBy(dx: -10, dy: -10)
                return true
            }
            target = current.superview
        }
        return false
    }

    @objc private func handleDeleteHold(_ hold: UILongPressGestureRecognizer) {
        switch hold.state {
        case .began:
            guard let bounds = deleteHoldBounds, bounds.contains(hold.location(in: rows)) else { return }
            let location = hold.location(in: view)
            deleteRepeatTask = Task { [weak self] in
                var repeatCount = 0
                while !Task.isCancelled {
                    guard let self, self.composition.hasInput || self.textDocumentProxy.hasText else { return }
                    self.delete()
                    self.playKeyFeedback(at: location, deleting: true)
                    repeatCount += 1
                    let interval: UInt64 = repeatCount < 8 ? 75_000_000 : 45_000_000
                    do {
                        try await Task.sleep(nanoseconds: interval)
                    } catch {
                        return
                    }
                }
            }
        case .changed:
            if let bounds = deleteHoldBounds, !bounds.contains(hold.location(in: rows)) { stopDeleteHold() }
        case .ended, .cancelled, .failed:
            stopDeleteHold()
        default:
            break
        }
    }

    private func stopDeleteHold() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
        deleteHoldBounds = nil
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
        setCandidatePanelVisible(false)
        writeSelectedText(candidate.text)
        updateComposition()
    }

    private func writeSelectedText(_ text: String) {
        updatingDocument = true
        defer { updatingDocument = false }
        textWriter.select(text, remainingReading: composition.display,
                          in: ProxyTextDocument(proxy: textDocumentProxy))
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
        showKeyPage()
        if composition.hasInput { prepareLexicon() }
        updatingDocument = true
        defer { updatingDocument = false }
        textWriter.update(composition.display, in: ProxyTextDocument(proxy: textDocumentProxy))
        scheduleCandidateRefresh()
    }

    private func commit(_ text: String) {
        updatingDocument = true
        defer { updatingDocument = false }
        textWriter.commit(text, in: ProxyTextDocument(proxy: textDocumentProxy))
    }

    private func commitPending() {
        guard composition.hasInput else { return }
        if lexicon == nil { lexicon = Self.loadLexicon() }
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
        setCandidatePanelVisible(false)
        commit(text)
        render()
    }
}

private struct ProxyTextDocument: CompositionTextDocument {
    let proxy: UITextDocumentProxy

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        proxy.setMarkedText(text, selectedRange: selectedRange)
    }

    func unmarkText() { proxy.unmarkText() }
    func insertText(_ text: String) { proxy.insertText(text) }
}

private final class KeyboardKeyRow: UIView {
    private let keys: [UIView]
    private let weights: [CGFloat]
    private let totalWeight: CGFloat
    private let preferredHeight = KeyboardLayoutConfiguration.portrait.keyHeight

    init(views: [UIView], weights: [CGFloat]) {
        keys = views
        self.weights = weights
        totalWeight = weights.reduce(0, +)
        super.init(frame: .zero)
        views.forEach { addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Keyboard rows are created in code") }

    override var intrinsicContentSize: CGSize {
        // The vertical stack still contributes a nonzero fitting height before the host assigns bounds.
        CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing = min(6, bounds.width / CGFloat(keys.count))
        let unit = (bounds.width - spacing * CGFloat(keys.count - 1)) / totalWeight
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var offset: CGFloat = 0
        for (key, weight) in zip(keys, weights) {
            let width = unit * weight
            let x = rightToLeft ? bounds.maxX - offset - width : bounds.minX + offset
            key.frame = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            offset += width + spacing
        }
    }
}

private final class CandidateScrollView: UIScrollView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        // Buttons react immediately, but dragging still takes over to scroll the candidates.
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}

private final class KeyboardButton: UIButton {
    var previewTitle: String?
    var pinyin: String?
    var activatesOnTouchDown = false
    var isDeleteKey = false
    private var pinyinCaption: UILabel?
    private var shadowBounds: CGRect?

    override func accessibilityActivate() -> Bool {
        guard activatesOnTouchDown else { return super.accessibilityActivate() }
        sendActions(for: .touchDown)
        sendActions(for: .touchUpInside)
        return true
    }

    func setPinyinVisible(_ visible: Bool) {
        guard let pinyin, let title = title(for: .normal) else { return }
        // The one-line title still supplies the key's intrinsic size in both modes.
        if visible, pinyinCaption == nil {
            let caption = UILabel(frame: bounds)
            caption.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            caption.numberOfLines = 2
            caption.textAlignment = .center
            caption.isAccessibilityElement = false
            let text = NSMutableAttributedString(string: title, attributes: [
                .font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.label
            ])
            text.append(NSAttributedString(string: "\n" + pinyin, attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: UIColor.secondaryLabel
            ]))
            caption.attributedText = text
            addSubview(caption)
            pinyinCaption = caption
        }
        pinyinCaption?.isHidden = !visible
        setTitleColor(visible ? .clear : .label, for: .normal)
        setTitleColor(visible ? .clear : .label, for: .highlighted)
        accessibilityLabel = visible ? "\(title)，\(pinyin)" : title
    }

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
