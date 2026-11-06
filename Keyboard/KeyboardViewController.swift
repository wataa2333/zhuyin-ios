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
    private var fixedLayout = KeyboardPreferences.layout
    private var isLayoutPreview = false
    var onPreviewExpansionChanged: ((Bool) -> Void)?
    var layoutConfiguration: KeyboardLayoutConfiguration { fixedLayout }

    static func makeLayoutPreview(_ layout: KeyboardLayoutConfiguration, showsPinyin: Bool) -> KeyboardViewController {
        let controller = KeyboardViewController()
        controller.isLayoutPreview = true
        controller.fixedLayout = layout
        controller.showsPinyin = showsPinyin
        return controller
    }

    func updateLayoutPreview(_ layout: KeyboardLayoutConfiguration, showsPinyin: Bool, expanded: Bool) {
        guard isLayoutPreview else { return }
        loadViewIfNeeded()
        applyLayoutConfiguration(layout)
        self.showsPinyin = showsPinyin
        alternatePage = .finals
        returnTitle = "发送"
        documentHasText = true
        updateKeys()
        setCandidatePanelVisible(expanded, animated: false)
    }
    private static let emojiByWord = [
        "想": "🤔", "下": "⬇️", "心": "❤️", "爱": "❤️", "你好": "👋", "再见": "👋",
        "笑": "😄", "哈哈": "😂", "哭": "😢", "生气": "😡", "谢谢": "🙏", "赞": "👍",
        "恭喜": "🎉", "生日": "🎂", "生日快乐": "🎂", "晚安": "🌙", "太阳": "☀️", "下雨": "🌧️",
        "苹果": "🍎", "咖啡": "☕", "猫": "🐱", "狗": "🐶", "花": "🌸", "火": "🔥"
    ]
    private var showsPinyin = KeyboardPreferences.localPinyin
    private var preferenceLoad: Task<Void, Never>?
    private var settingsObserver: KeyboardSettingsObserver?
    private var composition = Composition()
    private var textWriter = CompositionTextWriter()
    private var updatingDocument = false
    private var synchronizingSettings = false
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
    private var documentHasText = false
    private var returnRequiresText = false
    private var isSearchField = false
    private var keyboardWarmup: Task<Void, Never>?

    private let rows = UIView()
    private let keyArea = UIView()
    private let candidateList = CandidateListView()
    private let candidateStripSlot = UIView()
    private let candidateDivider = UIView()
    private var displayedCandidates: [String] = []
    private var highlightsFirstCandidate = false
    private var candidateRefreshPending = false
    private let expandCandidates = NearbyTouchButton(type: .system)
    private lazy var candidatePanel = CandidatePanelController(
        keyboard: rows, candidates: candidateList, toggle: expandCandidates, keepsCandidatesVisible: true
    )
    private var showsCandidatePanel: Bool { candidatePanel.isExpanded }
    private var candidateListHeight: NSLayoutConstraint?
    private var keyAreaHeight: NSLayoutConstraint?
    private var toolbarHeight: NSLayoutConstraint?
    private var contentTop: NSLayoutConstraint?
    private var contentBottom: NSLayoutConstraint?
    private var contentStack: UIStackView?
    private var keyPreview: KeyPreviewView?
    private weak var previewKey: KeyboardButton?
    private var deleteHoldBounds: CGRect?
    private var deleteRepeatTask: Task<Void, Never>?
    private var feedback: KeyFeedbackSettings = {
        var settings = KeyFeedbackSettings()
        settings.volume = 0
        settings.haptics = 0
        return settings
    }() {
        didSet {
            if oldValue.haptics != feedback.haptics { keyHaptic = nil }
            if feedback.volume == 0 { keyAudio.stop() }
        }
    }
    private var canPlayKeyFeedback = false
    private var isKeyboardVisible = false
    private var keyHaptic: UIImpactFeedbackGenerator?
    private let keyAudio = KeyboardAudioFeedback()

    private var page: Page { alternatePage ?? (composition.showsFinals ? .finals : .initials) }
    private func refreshInputTraits(from proxy: UITextDocumentProxy) {
        let returnKeyType = proxy.returnKeyType
        isSearchField = returnKeyType == .search || returnKeyType == .google
            || returnKeyType == .yahoo || proxy.keyboardType == .webSearch
        returnTitle = title(for: returnKeyType)
        returnRequiresText = returnKeyType == .send || proxy.enablesReturnKeyAutomatically == true
        if !composition.hasInput && textWriter.markedText.isEmpty { documentHasText = proxy.hasText }
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
        let keyboard = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboard.contentHeight = fixedLayout.contentHeight
        inputView = keyboard
        if isLayoutPreview { keyboard.backgroundColor = .systemGray5 }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (inputView as? KeyboardInputView)?.nearbyTouchTarget = expandCandidates
        let divider = candidateDivider
        keyArea.accessibilityIdentifier = "keyboard.keyArea"
        candidateList.accessibilityIdentifier = "keyboard.candidates"
        divider.backgroundColor = .secondaryLabel
        divider.layer.cornerRadius = KeyboardLayoutConfiguration.dividerWidth / 2
        divider.layer.shadowColor = UIColor.black.cgColor
        divider.layer.shadowOpacity = 0.16
        divider.layer.shadowRadius = 0.8
        divider.layer.shadowOffset = CGSize(width: 0.5, height: 0)
        divider.layer.shadowPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0,
            width: KeyboardLayoutConfiguration.dividerWidth, height: KeyboardLayoutConfiguration.dividerHeight),
            cornerRadius: KeyboardLayoutConfiguration.dividerWidth / 2).cgPath
        divider.translatesAutoresizingMaskIntoConstraints = false
        let dividerSlot = UIView()
        dividerSlot.addSubview(divider)
        NSLayoutConstraint.activate([
            dividerSlot.widthAnchor.constraint(equalToConstant: KeyboardLayoutConfiguration.dividerWidth),
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
            if self.isLayoutPreview { self.onPreviewExpansionChanged?(self.showsCandidatePanel) }
            self.playKeyFeedback()
        }
        let toolbar = UIStackView(arrangedSubviews: [candidateStripSlot, dividerSlot, arrowSlot])
        toolbar.insetsLayoutMarginsFromSafeArea = false
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: 0)
        toolbar.spacing = 3
        let barHeight = toolbar.heightAnchor.constraint(equalToConstant: fixedLayout.candidateBarHeight)
        barHeight.isActive = true
        toolbarHeight = barHeight
        keyArea.clipsToBounds = true
        rows.translatesAutoresizingMaskIntoConstraints = false
        keyArea.addSubview(rows)
        if !isLayoutPreview { configureDeleteHold() }

        let layout = UIStackView(arrangedSubviews: [toolbar, keyArea])
        layout.axis = .vertical
        layout.spacing = fixedLayout.toolbarSpacing
        contentStack = layout
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        candidateList.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateList)
        candidateList.candidateBarHeight = fixedLayout.candidateBarHeight
        candidateList.onSelect = { [weak self] index in
            guard let self, !self.isLayoutPreview else { return }
            self.selectCandidate(at: index)
        }
        candidatePanel.prepareTransition = { [weak self] expanded in
            guard let self else { return }
            if !self.view.bounds.isEmpty { self.view.layoutIfNeeded() }
            self.candidateList.prepareTransition(expanded: expanded)
        }
        candidatePanel.animateTransition = { [weak self] expanded in
            guard let self else { return }
            self.candidateListHeight?.constant = expanded
                ? self.fixedLayout.candidatePanelHeight
                : self.fixedLayout.candidateBarHeight
            self.candidateList.applyLayout()
            if !self.view.bounds.isEmpty { self.view.layoutIfNeeded() }
        }
        let area = (view as? KeyboardInputView)?.contentLayoutGuide ?? view.safeAreaLayoutGuide
        let top = layout.topAnchor.constraint(equalTo: view.topAnchor, constant: fixedLayout.topInset)
        let bottom = layout.bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -fixedLayout.bottomInset)
        contentTop = top
        contentBottom = bottom
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            top, bottom,
            arrowSlot.widthAnchor.constraint(equalToConstant: KeyboardLayoutConfiguration.candidateToggleWidth),
            expandCandidates.leadingAnchor.constraint(equalTo: arrowSlot.leadingAnchor),
            expandCandidates.trailingAnchor.constraint(equalTo: arrowSlot.trailingAnchor),
            expandCandidates.topAnchor.constraint(equalTo: arrowSlot.topAnchor),
            expandCandidates.bottomAnchor.constraint(equalTo: arrowSlot.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: keyArea.leadingAnchor, constant: sideInset),
            rows.trailingAnchor.constraint(equalTo: keyArea.trailingAnchor, constant: -sideInset),
            rows.topAnchor.constraint(equalTo: keyArea.topAnchor),
            rows.bottomAnchor.constraint(equalTo: keyArea.bottomAnchor),
            candidateList.leadingAnchor.constraint(equalTo: rows.leadingAnchor),
            candidateList.trailingAnchor.constraint(equalTo: rows.trailingAnchor),
            candidateList.topAnchor.constraint(equalTo: toolbar.topAnchor)
        ])
        let listHeight = candidateList.heightAnchor.constraint(equalToConstant: fixedLayout.candidateBarHeight)
        listHeight.isActive = true
        candidateListHeight = listHeight
        let height = keyArea.heightAnchor.constraint(
            equalToConstant: fixedLayout.keyAreaHeight
        )
        height.isActive = true
        keyAreaHeight = height
        setCandidatePanelVisible(false, animated: false)

        if isLayoutPreview {
            candidateList.update(titles: Self.starterCandidates + Self.starterCandidates, highlightsFirst: true)
        }

        // viewWillAppear reads the input traits and builds the initial page once.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isLayoutPreview else { return }
        isKeyboardVisible = true
        refreshDocument(reloadCandidates: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isLayoutPreview else { return }
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
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isKeyboardVisible else { return }
            self.canPlayKeyFeedback = self.hasFullAccess
            if self.settingsObserver == nil {
                self.settingsObserver = KeyboardSettingsObserver { [weak self] in self?.reloadPreferences() }
            }
            self.reloadPreferences()
            if !self.isSearchField, self.synchronizeSettings() { self.updateKeys() }
        }
    }

    private func reloadPreferences() {
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDeleteHold()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !isLayoutPreview else { return }
        isKeyboardVisible = false
        canPlayKeyFeedback = false
        settingsObserver = nil
        keyboardWarmup?.cancel()
        preferenceLoad?.cancel()
        keyAudio.stop()
        composition = Composition()
        textWriter.reset()
        selectedSegments.removeAll()
        alternatePage = nil
        clearKeyPreview()
        candidateRefreshPending = false
        setCandidatePanelVisible(false, animated: false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        guard !isLayoutPreview else { return }
        keyboardWarmup?.cancel()
        clearKeyPreview()
        keyPreview?.removeFromSuperview()
        keyPreview = nil
        keyHaptic = nil
        keyAudio.releaseResources()
        let unusedPages = keyLayouts.keys.filter { !isKeyboardVisible || $0 != displayedPage }
        for page in unusedPages { keyLayouts.removeValue(forKey: page)?.removeFromSuperview() }
        if !isKeyboardVisible {
            displayedPage = nil
            candidateList.releaseCachedContent()
            displayedCandidates.removeAll()
            candidates.removeAll()
            highlightsFirstCandidate = false
            candidateRefreshPending = false
            updateCandidateArrow()
        }
        if let lexicon {
            Task.detached(priority: .utility) { lexicon.releaseUnusedMemory() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        candidateList.updateViewport(firstRowWidth: candidateStripSlot.bounds.width)
        updateCandidateArrow()
    }

    private func applyLayoutConfiguration(_ configuration: KeyboardLayoutConfiguration) {
        guard configuration.isValid, configuration != fixedLayout else { return }
        stopDeleteHold()
        clearKeyPreview()
        let wasExpanded = showsCandidatePanel
        setCandidatePanelVisible(false, animated: false)
        fixedLayout = configuration
        keyAreaHeight?.constant = configuration.keyAreaHeight
        toolbarHeight?.constant = configuration.candidateBarHeight
        candidateListHeight?.constant = configuration.candidateBarHeight
        contentTop?.constant = configuration.topInset
        contentBottom?.constant = -configuration.bottomInset
        contentStack?.spacing = configuration.toolbarSpacing
        candidateList.candidateBarHeight = configuration.candidateBarHeight
        (inputView as? KeyboardInputView)?.contentHeight = configuration.contentHeight
        for layout in keyLayouts.values { layout.spacing = configuration.rowSpacing }
        if wasExpanded { setCandidatePanelVisible(true, animated: false) }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if isViewLoaded, !isLayoutPreview, !updatingDocument { refreshDocument() }
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        if isViewLoaded, !isLayoutPreview, !updatingDocument, synchronizeSettings() { updateKeys() }
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
        let hadComposition = composition.hasInput || !textWriter.markedText.isEmpty
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
            if hadComposition { documentHasText = proxy.hasText }
        }
        // A settings field must be consumed before drawing the first keyboard frame, too.
        synchronizeSettings()
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
        synchronizeSettings(using: textDocumentProxy)
    }

    @discardableResult
    func synchronizeSettings(using proxy: UITextDocumentProxy) -> Bool {
        guard !synchronizingSettings else { return false }
        guard proxy.textContentType == .nickname else { return false }
        let code = (proxy.documentContextBeforeInput ?? "") + (proxy.selectedText ?? "")
            + (proxy.documentContextAfterInput ?? "")
        guard let settings = KeyboardPreferences.syncSettings(from: code) else { return false }
        synchronizingSettings = true
        defer { synchronizingSettings = false }
        preferenceLoad?.cancel()
        // A newly selected settings payload replaces any interrupted composition in this field.
        if composition.hasInput {
            composition = Composition()
            textWriter.reset()
            selectedSegments.removeAll()
            alternatePage = nil
        }
        do {
            if let layout = settings.layout {
                try KeyboardPreferences.saveLocally(layout)
                applyLayoutConfiguration(layout)
            }
            if let syncedFeedback = settings.feedback {
                KeyboardPreferences.saveLocally(syncedFeedback)
                feedback = syncedFeedback
            }
            KeyboardPreferences.saveLocally(settings.pinyin)
            showsPinyin = settings.pinyin
            // Only our dedicated, fully selected sync field gets a receipt. Ordinary text is untouched.
            if proxy.selectedText == code {
                updatingDocument = true
                proxy.insertText(KeyboardPreferences.syncReply(for: code))
                updatingDocument = false
            }
            return true
        } catch {
            if proxy.selectedText == code {
                updatingDocument = true
                proxy.insertText(KeyboardPreferences.syncReply(for: code, succeeded: false))
                updatingDocument = false
            }
            return false
        }
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
        candidatePanel.setExpanded(showsCandidatePanel, animated: false)
        candidateList.update(titles: candidates.map(\.text), highlightsFirst: highlightsFirstCandidate)
        if showsCandidatePanel && !candidateList.hasOverflow { setCandidatePanelVisible(false) }
        updateCandidateArrow()
    }

    private func selectCandidate(at index: Int) {
        guard candidates.indices.contains(index) else { return }
        let selected = candidates[index]
        if candidateRefreshPending {
            renderCandidates()
            guard candidates.contains(where: {
                $0.text == selected.text && $0.readingCode == selected.readingCode && $0.isEmoji == selected.isEmoji
            }) else { return }
        }
        choose(selected)
        playKeyFeedback()
    }

    private func updateCandidateArrow() {
        let hidden = !showsCandidatePanel && !candidateList.hasOverflow
        expandCandidates.isHidden = hidden
        candidateDivider.isHidden = hidden
    }

    private func setCandidatePanelVisible(_ visible: Bool, animated: Bool = true) {
        if visible && !candidateList.hasOverflow { return }
        if visible {
            stopDeleteHold()
            clearKeyPreview()
        }
        candidatePanel.setExpanded(visible, animated: animated)
        updateCandidateArrow()
    }

    private func updateKeys() {
        let globe = isLayoutPreview ? false : needsInputModeSwitchKey
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
        updateReturnKeyAppearance()
    }

    private func updateReturnKeyAppearance() {
        let enabled = !returnRequiresText || documentHasText || composition.hasInput || !textWriter.selectedText.isEmpty
        for layout in keyLayouts.values {
            for case let row as KeyboardKeyRow in layout.arrangedSubviews {
                for case let button as KeyboardButton in row.subviews where button.isReturnKey {
                    button.applyReturnAppearance(action: returnTitle != "换行", enabled: enabled)
                }
            }
        }
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
        layout.spacing = fixedLayout.rowSpacing
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
        let space = Key(isPhonetic ? "注音输入法" : "空格",
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
                self?.insertLiteralText(String(symbol))
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
                if isLayoutPreview { button.isUserInteractionEnabled = false }
                button.isReturnKey = key.accessibilityLabel == returnTitle
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
                } else if key.title == "注音输入法" {
                    let marker = UILabel()
                    marker.text = "注音输入法"
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

    private func clearKeyPreview() {
        keyPreview?.isHidden = true
        previewKey?.setPreviewPresented(false)
        previewKey = nil
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
        guard canPlayKeyFeedback, feedback.volume > 0 else { return }
        keyAudio.prepare()
    }

    private func playKeyFeedback(at location: CGPoint? = nil, deleting: Bool = false) {
        guard canPlayKeyFeedback else { return }
        if feedback.volume > 0 { keyAudio.play(volume: feedback.volume, deleting: deleting) }
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
        clearKeyPreview()
        if rows.layer.needsLayout() { rows.layoutIfNeeded() }
        let key = sender.convert(sender.bounds, to: view)
        let preview: KeyPreviewView
        if let existing = keyPreview { preview = existing }
        else {
            preview = KeyPreviewView(frame: .zero)
            keyPreview = preview
            view.addSubview(preview)
        }
        view.bringSubviewToFront(preview)
        preview.show(title, key: key, viewport: view.bounds, compact: traitCollection.verticalSizeClass == .compact)
        sender.setPreviewPresented(true)
        previewKey = sender
    }

    @objc private func hideKeyPreview(_ sender: UIButton) {
        guard previewKey === sender else { return }
        clearKeyPreview()
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
            documentHasText = textDocumentProxy.hasText
        }
        updateReturnKeyAppearance()
    }

    private func space() {
        if alternatePage == nil, !composition.current.symbols.isEmpty {
            composition.finish(tone: "1")
            updateComposition()
        } else if composition.hasInput {
            commitPending()
        } else {
            insertLiteralText(" ")
        }
    }

    private func insertLiteralText(_ text: String) {
        textDocumentProxy.insertText(text)
        if !text.isEmpty { documentHasText = true }
        updateReturnKeyAppearance()
    }

    private func enter() {
        guard !returnRequiresText || documentHasText || composition.hasInput || !textWriter.selectedText.isEmpty else { return }
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
        if !composition.hasInput && !text.isEmpty { documentHasText = true }
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
        let commitsPrefix = !composition.hasInput && !textWriter.selectedText.isEmpty
        textWriter.update(composition.display, in: ProxyTextDocument(proxy: textDocumentProxy))
        if commitsPrefix { documentHasText = true }
        updateReturnKeyAppearance()
        scheduleCandidateRefresh()
    }

    private func commit(_ text: String) {
        updatingDocument = true
        defer { updatingDocument = false }
        textWriter.commit(text, in: ProxyTextDocument(proxy: textDocumentProxy))
        if !text.isEmpty { documentHasText = true }
        updateReturnKeyAppearance()
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
    private let preferredHeight = KeyboardLayoutConfiguration.defaults.keyHeight

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

private final class KeyboardButton: UIButton {
    var isReturnKey = false
    private var returnAppearance: Int?
    private var returnBackground: UIColor?

    func applyReturnAppearance(action: Bool, enabled: Bool) {
        let state = (action ? 2 : 0) + (enabled ? 1 : 0)
        guard returnAppearance != state else { return }
        if returnAppearance == nil { returnBackground = backgroundColor }
        returnAppearance = state
        isEnabled = enabled
        backgroundColor = action && enabled ? .systemBlue : (enabled ? returnBackground : .systemGray4)
        let foreground: UIColor = action && enabled ? .white : (enabled ? .label : .secondaryLabel)
        setTitleColor(foreground, for: .normal)
        setTitleColor(.secondaryLabel, for: .disabled)
        tintColor = foreground
    }

    var previewTitle: String?
    var pinyin: String?
    var activatesOnTouchDown = false
    var isDeleteKey = false
    private var pinyinCaption: UILabel?
    private var pinyinIsVisible = false
    private var previewIsPresented = false
    private var shadowBounds: CGRect?

    override func accessibilityActivate() -> Bool {
        guard activatesOnTouchDown else { return super.accessibilityActivate() }
        sendActions(for: .touchDown)
        sendActions(for: .touchUpInside)
        return true
    }

    func setPinyinVisible(_ visible: Bool) {
        guard let pinyin, let title = title(for: .normal) else { return }
        pinyinIsVisible = visible
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
        pinyinCaption?.isHidden = !visible || previewIsPresented
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
        didSet { alpha = isHighlighted && !previewIsPresented ? 0.62 : 1 }
    }

    func setPreviewPresented(_ visible: Bool) {
        previewIsPresented = visible
        titleLabel?.isHidden = visible
        pinyinCaption?.isHidden = visible || !pinyinIsVisible
        alpha = isHighlighted && !visible ? 0.62 : 1
    }
}
