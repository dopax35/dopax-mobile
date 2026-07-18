import UIKit

// MARK: - UIColor palette (dopa-X hex values, kept local to this target so the
// extension doesn't need to share the main app's SwiftUI Theme.swift file).
private extension UIColor {
    static let dopaxSurfaceLow = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 0.15, alpha: 1)
            : UIColor(red: 0xF0/255, green: 0xF4/255, blue: 0xF8/255, alpha: 1)
    }
    static let dopaxKeyLight = UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .white
    }
    static let dopaxKeySpecial = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : UIColor(red: 0xE2/255, green: 0xE7/255, blue: 0xF0/255, alpha: 1)
    }
    static let dopaxAccent   = UIColor(red: 0x28/255, green: 0x28/255, blue: 0xC6/255, alpha: 1) // dopaxBlue
    static let dopaxPopupBg  = UIColor(red: 0x0F/255, green: 0x0F/255, blue: 0x3D/255, alpha: 1) // dopaxDarkBlue
}

// MARK: - KeyboardViewController
/// Full bilingual keyboard extension (Hebrew ⟷ English) with a numbers/symbols
/// page and tremor-friendly correction shortcuts.
///
/// Privacy guarantee: only key *class* data is ever written to the shared buffer
/// (e.g. "letter", "backspace", "word_len_5"). The actual characters typed by the
/// user are committed directly to the text document and never stored. All
/// logging happens automatically via `observeTextChange()`, which reacts to
/// `textDidChange` — every action below goes through `textDocumentProxy`
/// (`insertText`/`deleteBackward`), so no action needs its own manual log call.
///
/// Layout:
///   • Three character rows — QWERTY, Hebrew, or numbers/symbols, selectable
///     at runtime via the "?123" / "ABC" key (previously unreachable — the
///     data model existed but no key ever triggered it).
///   • ⇧ shift key on the last letter row (English only — Hebrew has no
///     letter case) — one-shot, and also overrides auto-capitalization so
///     the user can force lowercase at a sentence start if they want to.
///   • Long-press a top-row letter for its digit / an accented variant.
///   • Swipe left on ⌫ to delete the whole previous word in one gesture.
///   • Double-tap space for ". " + auto-capitalize the next letter.
///   • Bottom action row — 🌐 (next keyboard), HE/EN language toggle, ?123,
///                         Space, Return, ⌫ Backspace.
///
class KeyboardViewController: UIInputViewController {

    // ── Language / Mode State ────────────────────────────────────────────────
    private var isHebrew        = false
    private var isUppercase     = false   // only applies to English
    private var isNumbersMode   = false
    // capitalize the first letter of a fresh field. didSet keeps the
    // on-screen key case in sync with auto-capitalization (not just the
    // manual shift key) — otherwise keys could show lowercase while
    // silently committing an uppercase letter.
    private var autoCapNext = true {
        didSet {
            guard autoCapNext != oldValue, !isHebrew, !isNumbersMode else { return }
            buildKeyboard()
        }
    }

    // ── Logging State ────────────────────────────────────────────────────────
    private var previousTextLength   = 0
    private var currentWordCharCount = 0
    private var lastSpaceDate: Date?
    private let sharedDefaults = UserDefaults(
        suiteName: "group.com.oriw.pdcollect.ios1.shared"
    )

    // ── UI root ──────────────────────────────────────────────────────────────
    private var keyboardContainer: UIView?

    // ── Long-press popup ─────────────────────────────────────────────────────
    private var popupView: UIView?
    private var popupLabels: [UILabel] = []
    private var popupAlternates: [String] = []
    private var popupBaseChar: String = ""
    private var popupSelectedIndex: Int?

    // English row-1 → digit, and a small set of common accented letters.
    // Same physical mapping as the Android layout's popupCharacters, for
    // cross-platform muscle-memory consistency.
    private let popupMapEN: [String: [String]] = [
        "q": ["1"], "w": ["2"], "e": ["3", "é", "è", "ê"], "r": ["4"], "t": ["5"],
        "y": ["6"], "u": ["7", "ü", "ú", "ù"], "i": ["8", "í", "ì", "î"],
        "o": ["9", "ó", "ò", "ô"], "p": ["0"],
        "a": ["á", "à", "â"], "s": ["ß"], "c": ["ç"], "n": ["ñ"]
    ]
    private let popupMapHE: [String: [String]] = [
        "פ": ["1"], "ם": ["2"], "ן": ["3"], "ו": ["4"], "ט": ["5"],
        "א": ["6"], "ר": ["7"], "ק": ["8"], "'": ["9"], "/": ["0"]
    ]

    // ── Geometry ─────────────────────────────────────────────────────────────
    private let rowGap:   CGFloat = 8
    private let keyGap:   CGFloat = 5
    private let sidePad:  CGFloat = 4

    // Key height adapts to portrait vs. landscape. Bumped from the original
    // 38/44 to stay comfortably above the 48pt tremor-friendly tap-target
    // floor already established elsewhere in this app.
    private var keyH: CGFloat {
        UIScreen.main.bounds.height < 680 ? 46 : 50
    }
    private var totalH: CGFloat { keyH * 4 + rowGap * 5 }

    // ── Keyboard layouts ─────────────────────────────────────────────────────

    // English QWERTY — 10 / 9 / 7 keys
    private let enRows: [[String]] = [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m"]
    ]

    // Hebrew — right-to-left visual order to match physical Israeli layout
    // Row  1 visually (LTR stored): פ ם ן ו ט א ר ק ' /
    // Row  2:                        ף ך ל ח י ע כ ג ד ש
    // Row  3:                        ץ ת צ מ נ ה ב ס ז
    private let heRows: [[String]] = [
        ["פ","ם","ן","ו","ט","א","ר","ק","'","/"],
        ["ף","ך","ל","ח","י","ע","כ","ג","ד","ש"],
        ["ץ","ת","צ","מ","נ","ה","ב","ס","ז"]
    ]

    // Numbers / symbols
    private let numRows: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","+","@","\"","#"],
        [".",",","?","!","'","~","<",">","&","$"]
    ]

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        previousTextLength = (textDocumentProxy.documentContextBeforeInput ?? "").count
        autoCapNext = true
        // Signal to the main app that this keyboard has been activated.
        sharedDefaults?.set(true, forKey: "keyboard_ever_launched")
        sharedDefaults?.set(Date(), forKey: "keyboard_last_launch_date")
        buildKeyboard()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        buildKeyboard()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        observeTextChange()
    }

    // ── Build / rebuild keyboard ──────────────────────────────────────────────

    private func buildKeyboard() {
        keyboardContainer?.removeFromSuperview()
        keyboardContainer = nil

        let w = view.bounds.width
        guard w > 4 else { return }

        let container = UIView()
        container.backgroundColor = .dopaxSurfaceLow
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.heightAnchor.constraint(equalToConstant: totalH)
        ])

        let rows = isNumbersMode ? numRows : (isHebrew ? heRows : enRows)
        var y: CGFloat = rowGap

        // Character rows (rows 0, 1, 2) — the last letter row also carries
        // the shift key (left edge), matching the Android layout's shift
        // placement on its equivalent row.
        for (index, row) in rows.enumerated() {
            buildCharacterRow(keys: row, y: y, w: w, parent: container, isLastLetterRow: index == rows.count - 1)
            y += keyH + rowGap
        }

        // Action row (row 3)
        buildActionRow(y: y, w: w, parent: container)

        keyboardContainer = container

        // Update view intrinsic height
        view.frame = CGRect(x: 0, y: 0, width: w, height: totalH)
    }

    // ── Row builders ─────────────────────────────────────────────────────────

    private func buildCharacterRow(keys: [String], y: CGFloat, w: CGFloat, parent: UIView, isLastLetterRow: Bool = false) {
        // Manual shift key, shown on the last letter row only (not on the
        // numbers page or Hebrew, which has no letter case) — mirrors the
        // Android layout, which places its ⇧ key on the equivalent row.
        let showShift: Bool = isLastLetterRow && !isHebrew && !isNumbersMode
        let shiftW: CGFloat = 44

        let n        = CGFloat(keys.count)
        let reserved = showShift ? shiftW + keyGap : 0
        let kw       = (w - sidePad * 2 - reserved - keyGap * (n - 1)) / n
        var x        = sidePad

        if showShift {
            let shifted = isUppercase || autoCapNext
            let shift = specialKey(title: "⇧", fontSize: 18)
            shift.backgroundColor = shifted ? .dopaxAccent : .dopaxKeySpecial
            shift.setTitleColor(shifted ? .white : .label, for: .normal)
            shift.frame = CGRect(x: x, y: y, width: shiftW, height: keyH)
            shift.addTarget(self, action: #selector(shiftPressed), for: .touchUpInside)
            parent.addSubview(shift)
            x += shiftW + keyGap
        }

        for key in keys {
            let title = ((isUppercase || autoCapNext) && !isHebrew && !isNumbersMode && key.count == 1)
                ? key.uppercased()
                : key
            let btn = letterKey(title: title)
            btn.frame = CGRect(x: x, y: y, width: kw, height: keyH)
            btn.addTarget(self, action: #selector(characterPressed(_:)), for: .touchUpInside)

            // Long-press popup for keys with digit/accent alternates.
            if !isNumbersMode {
                let map = isHebrew ? popupMapHE : popupMapEN
                if map[key] != nil {
                    let lp = UILongPressGestureRecognizer(target: self, action: #selector(letterLongPress(_:)))
                    lp.minimumPressDuration = 0.35
                    btn.addGestureRecognizer(lp)
                }
            }

            parent.addSubview(btn)
            x += kw + keyGap
        }
    }

    private func buildActionRow(y: CGFloat, w: CGFloat, parent: UIView) {
        // Fixed widths for special keys
        let globeW:  CGFloat = 40
        let langW:   CGFloat = 46
        let numW:    CGFloat = 46
        let backW:   CGFloat = 44
        let retW:    CGFloat = 80
        let totalSpecial = sidePad * 2 + globeW + langW + numW + backW + retW + keyGap * 5
        let spaceW = w - totalSpecial

        var x = sidePad

        // 🌐 — cycle to next system keyboard
        let globe = specialKey(title: "🌐")
        globe.frame = CGRect(x: x, y: y, width: globeW, height: keyH)
        globe.addTarget(self, action: #selector(globePressed(_:)), for: .allTouchEvents)
        parent.addSubview(globe)
        x += globeW + keyGap

        // Language toggle — shows current language as label (hidden while on
        // the numbers page, since language doesn't apply there — but the key
        // stays in place and just toggles back to letters for simplicity).
        let langLabel = isNumbersMode ? (isHebrew ? "עA" : "EN") : (isHebrew ? "EN" : "עA")
        let lang = specialKey(title: langLabel, fontSize: 13)
        lang.frame = CGRect(x: x, y: y, width: langW, height: keyH)
        lang.addTarget(self, action: #selector(langTogglePressed), for: .touchUpInside)
        parent.addSubview(lang)
        x += langW + keyGap

        // ?123 / ABC — numbers & symbols page toggle
        let num = specialKey(title: isNumbersMode ? "ABC" : "?123", fontSize: 13)
        num.frame = CGRect(x: x, y: y, width: numW, height: keyH)
        num.addTarget(self, action: #selector(numbersTogglePressed), for: .touchUpInside)
        parent.addSubview(num)
        x += numW + keyGap

        // Space bar
        let spaceTitle = isHebrew ? "רווח" : "space"
        let space = letterKey(title: spaceTitle, fontSize: 14)
        space.frame = CGRect(x: x, y: y, width: spaceW, height: keyH)
        space.addTarget(self, action: #selector(spacePressed), for: .touchUpInside)
        parent.addSubview(space)
        x += spaceW + keyGap

        // Return
        let ret = specialKey(title: "↵", fontSize: 18)
        ret.frame = CGRect(x: x, y: y, width: retW, height: keyH)
        ret.addTarget(self, action: #selector(returnPressed), for: .touchUpInside)
        parent.addSubview(ret)
        x += retW + keyGap

        // ⌫ Backspace
        let back = specialKey(title: "⌫")
        back.frame = CGRect(x: x, y: y, width: backW, height: keyH)
        back.addTarget(self, action: #selector(backspacePressed), for: .touchUpInside)
        // Long-press repeating backspace
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(backspaceLongPress(_:)))
        lp.minimumPressDuration = 0.4
        back.addGestureRecognizer(lp)
        // Swipe left anywhere on the backspace key deletes the whole word —
        // one gesture instead of many taps.
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(backspaceSwipeLeft))
        swipe.direction = .left
        back.addGestureRecognizer(swipe)
        parent.addSubview(back)
    }

    // ── Key factories ─────────────────────────────────────────────────────────

    /// Tags used purely to remember which resting background color to restore
    /// after a press — not related to key codes.
    private enum KeyKind: Int { case letter = 0, special = 1 }

    private func letterKey(title: String, fontSize: CGFloat = 18) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: fontSize)
        btn.backgroundColor = .dopaxKeyLight
        btn.tag = KeyKind.letter.rawValue
        styleKey(btn)
        return btn
    }

    private func specialKey(title: String, fontSize: CGFloat = 15) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .medium)
        btn.backgroundColor = .dopaxKeySpecial
        btn.tag = KeyKind.special.rawValue
        styleKey(btn)
        return btn
    }

    private func styleKey(_ btn: UIButton) {
        btn.layer.cornerRadius = 8
        btn.layer.shadowColor  = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.25
        btn.layer.shadowOffset  = CGSize(width: 0, height: 1)
        btn.layer.shadowRadius  = 0.5
        btn.clipsToBounds = false
        // Clear, high-contrast pressed state — important for users with
        // tremor or visual symptoms who need confirmation a tap registered.
        btn.addTarget(self, action: #selector(keyTouchDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(keyTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @objc private func keyTouchDown(_ sender: UIButton) {
        sender.backgroundColor = .dopaxAccent
        sender.setTitleColor(.white, for: .normal)
    }

    @objc private func keyTouchUp(_ sender: UIButton) {
        let isSpecial = sender.tag == KeyKind.special.rawValue
        sender.backgroundColor = isSpecial ? .dopaxKeySpecial : .dopaxKeyLight
        sender.setTitleColor(.label, for: .normal)
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    @objc private func characterPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        commitCharacter(title)
        // Auto-cancel shift after one letter
        if isUppercase && !isHebrew {
            isUppercase = false
            buildKeyboard()
        }
    }

    /// Shared insertion path for both a normal tap and a long-press popup
    /// selection, so auto-capitalization is applied consistently either way.
    private func commitCharacter(_ raw: String) {
        var char = raw
        if autoCapNext, !isHebrew, !isNumbersMode, char.count == 1, char.lowercased() != char.uppercased() {
            char = char.uppercased()
        }
        // Insert one Unicode character at a time rather than the whole
        // string in one call. Almost always 1 character anyway, but
        // uppercasing can occasionally expand to more (e.g. "ß" → "SS") —
        // inserting as a single multi-character call would make that whole
        // burst look like one textDidChange event to observeTextChange(),
        // silently dropping a keystroke-class sample from the log below.
        for c in char {
            textDocumentProxy.insertText(String(c))
        }
        if char == "." || char == "!" || char == "?" {
            autoCapNext = true
        } else if !char.isEmpty {
            autoCapNext = false
        }
        playClick()
    }

    @objc private func spacePressed() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let now = Date()
        if before.hasSuffix(" "), let last = lastSpaceDate, now.timeIntervalSince(last) < 0.6 {
            // Double-space → ". " and capitalize the next letter. Inserted
            // as two separate calls (not one ". " string) so each
            // character fires its own textDidChange and gets its own log
            // entry — see the matching note in commitCharacter().
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(".")
            textDocumentProxy.insertText(" ")
            autoCapNext = true
        } else {
            flushWordLength()
            textDocumentProxy.insertText(" ")
        }
        lastSpaceDate = now
        playClick()
    }

    @objc private func returnPressed() {
        flushWordLength()
        textDocumentProxy.insertText("\n")
        autoCapNext = true
        lastSpaceDate = nil
        playClick()
    }

    @objc private func backspacePressed() {
        textDocumentProxy.deleteBackward()
        if currentWordCharCount > 0 { currentWordCharCount -= 1 }
        lastSpaceDate = nil
        playClick()
    }

    @objc private func backspaceLongPress(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began || gr.state == .changed {
            textDocumentProxy.deleteBackward()
            if currentWordCharCount > 0 { currentWordCharCount -= 1 }
        }
    }

    /// Deletes the whole previous word in one gesture instead of many taps —
    /// each deleteBackward() still flows through the existing textDidChange
    /// observer below, so no separate logging call is needed here.
    @objc private func backspaceSwipeLeft() {
        guard let before = textDocumentProxy.documentContextBeforeInput, !before.isEmpty else { return }
        let chars = Array(before)
        var idx = chars.count
        while idx > 0, chars[idx - 1].isWhitespace { idx -= 1 }
        while idx > 0, !chars[idx - 1].isWhitespace { idx -= 1 }
        let deleteCount = chars.count - idx
        guard deleteCount > 0 else { return }
        for _ in 0..<deleteCount { textDocumentProxy.deleteBackward() }
        currentWordCharCount = 0
        playClick()
    }

    /// Passes control to iOS so the user can pick any installed keyboard.
    @objc private func globePressed(_ sender: UIButton) {
        handleInputModeList(from: sender, with: UIEvent())
    }

    /// Switches between Hebrew and English layouts within this keyboard.
    @objc private func langTogglePressed() {
        isHebrew.toggle()
        isUppercase = false
        isNumbersMode = false
        buildKeyboard()
    }

    /// Manual shift key — one-shot (auto-cancels after the next letter, see
    /// characterPressed), matching mainstream keyboard behavior. A tap while
    /// auto-cap is showing an uppercase key overrides it instead, so the
    /// user can force lowercase where auto-cap would otherwise capitalize
    /// (e.g. a deliberately lowercase word at the start of a sentence).
    @objc private func shiftPressed() {
        if autoCapNext {
            autoCapNext = false
            isUppercase = false
        } else {
            isUppercase.toggle()
        }
        buildKeyboard()
    }

    /// Switches to/from the numbers & symbols page (previously unreachable —
    /// the data model existed but no key ever set isNumbersMode).
    @objc private func numbersTogglePressed() {
        isNumbersMode.toggle()
        buildKeyboard()
    }

    // ── Long-press popup (digits / accents) ───────────────────────────────────

    @objc private func letterLongPress(_ gr: UILongPressGestureRecognizer) {
        guard let btn = gr.view as? UIButton else { return }
        switch gr.state {
        case .began:
            guard let base = btn.title(for: .normal) else { return }
            let map = isHebrew ? popupMapHE : popupMapEN
            guard let alts = map[base.lowercased()] ?? map[base] else { return }
            btn.cancelTracking(with: nil)   // suppress the base tap's touchUpInside
            showPopup(for: btn, base: base, alternates: alts)
        case .changed:
            guard let popup = popupView else { return }
            let loc = gr.location(in: popup)
            updatePopupHighlight(at: loc)
        case .ended, .cancelled, .failed:
            if let idx = popupSelectedIndex, idx < popupAlternates.count {
                commitCharacter(popupAlternates[idx])
            } else if !popupBaseChar.isEmpty {
                commitCharacter(popupBaseChar)
            }
            dismissPopup()
        default:
            break
        }
    }

    private func showPopup(for btn: UIButton, base: String, alternates: [String]) {
        dismissPopup()
        popupBaseChar = base
        popupAlternates = alternates
        popupSelectedIndex = nil

        let labelW: CGFloat = 34
        let labelH: CGFloat = 38
        let width  = labelW * CGFloat(alternates.count)
        let originX = min(max(0, btn.frame.midX - width / 2), view.bounds.width - width)
        let originY = max(0, btn.frame.minY - labelH - 4)

        let popup = UIView(frame: CGRect(x: originX, y: originY, width: width, height: labelH))
        popup.backgroundColor = .dopaxPopupBg
        popup.layer.cornerRadius = 8
        popup.isUserInteractionEnabled = false
        keyboardContainer?.addSubview(popup)

        popupLabels = alternates.enumerated().map { i, alt in
            let lbl = UILabel(frame: CGRect(x: CGFloat(i) * labelW, y: 0, width: labelW, height: labelH))
            lbl.text = alt
            lbl.textAlignment = .center
            lbl.textColor = .white
            lbl.font = .systemFont(ofSize: 17)
            popup.addSubview(lbl)
            return lbl
        }
        popupView = popup
    }

    private func updatePopupHighlight(at point: CGPoint) {
        guard !popupLabels.isEmpty, let popup = popupView else { return }
        let labelW = popup.bounds.width / CGFloat(popupLabels.count)
        guard labelW > 0 else { return }
        let idx = min(max(0, Int(point.x / labelW)), popupLabels.count - 1)
        for (i, lbl) in popupLabels.enumerated() {
            lbl.backgroundColor = (i == idx) ? UIColor.white.withAlphaComponent(0.25) : .clear
        }
        // Only count as a deliberate selection once the finger is within the
        // popup's vertical bounds — sliding off the top/bottom cancels back
        // to the base character, matching common long-press-popup behavior.
        popupSelectedIndex = (point.y >= 0 && point.y <= popup.bounds.height) ? idx : nil
    }

    private func dismissPopup() {
        popupView?.removeFromSuperview()
        popupView = nil
        popupLabels = []
        popupAlternates = []
        popupBaseChar = ""
        popupSelectedIndex = nil
    }

    // ── Text observation ──────────────────────────────────────────────────────

    private func observeTextChange() {
        let current = textDocumentProxy.documentContextBeforeInput ?? ""
        let len = current.count

        if len < previousTextLength {
            logKeystroke("backspace", isBackspace: true)
            if currentWordCharCount > 0 { currentWordCharCount -= 1 }
        } else if len > previousTextLength, let lastChar = current.last {
            let kClass = classify(lastChar)
            logKeystroke(kClass, isBackspace: false)
            if kClass == "char" || kClass == "digit" {
                currentWordCharCount += 1
            } else if kClass == "space" || kClass == "enter" {
                flushWordLength()
            }
        }
        previousTextLength = len
    }

    private func flushWordLength() {
        if currentWordCharCount > 0 {
            logWordLength(currentWordCharCount)
            currentWordCharCount = 0
        }
    }

    // ── Classification ────────────────────────────────────────────────────────

    // Values must match Android's vocabulary exactly (Constants.kt:
    // key_class is one of "char","digit","space","punct","backspace",
    // "enter","other") — this used to say "letter"/"punctuation", which
    // would silently split the two platforms' data into different
    // categories for the same key classes in any analysis that groups or
    // filters by key_class.
    private func classify(_ char: Character) -> String {
        if char.isLetter                       { return "char" }
        if char.isNumber                       { return "digit" }
        if char == " "                         { return "space" }
        if char == "\n"                        { return "enter" }
        if char.isPunctuation || char.isSymbol { return "punct" }
        return "other"
    }

    // ── Logging ───────────────────────────────────────────────────────────────

    private func logKeystroke(_ keyClass: String, isBackspace: Bool) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        appendCsvRow("\(ts),\(keyClass),\(isBackspace),external\n")
        let key = "keystroke_count_\(Date().dateKey)"
        sharedDefaults?.set((sharedDefaults?.integer(forKey: key) ?? 0) + 1, forKey: key)
    }

    private func logWordLength(_ length: Int) {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        appendCsvRow("\(ts),word_len_\(length),false,external\n")
    }

    private func appendCsvRow(_ row: String) {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.oriw.pdcollect.ios1.shared")
        else { return }

        let url = dir.appendingPathComponent("keystroke_buffer.csv")

        if !FileManager.default.fileExists(atPath: url.path) {
            try? "timestamp_ms,key_class,is_backspace,source_app\n"
                .write(to: url, atomically: true, encoding: .utf8)
        }
        if let data = row.data(using: .utf8),
           let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        }
    }

    // ── Haptics / audio ───────────────────────────────────────────────────────

    private func playClick() {
        UIDevice.current.playInputClick()
    }
}

// MARK: - Date utility
private extension Date {
    var dateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: self)
    }
}
