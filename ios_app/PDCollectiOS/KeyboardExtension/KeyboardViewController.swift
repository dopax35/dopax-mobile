import UIKit

// MARK: - KeyboardViewController
/// Full bilingual keyboard extension (Hebrew ⟷ English).
///
/// Privacy guarantee: only key *class* data is ever written to the shared buffer
/// (e.g. "letter", "backspace", "word_len_5"). The actual characters typed by the
/// user are committed directly to the text document and never stored.
///
/// Layout:
///   • Three character rows — QWERTY or Hebrew layout, selectable at runtime.
///   • Bottom action row — 🌐 (next keyboard), HE/EN language toggle,
///                         Space, Return, ⌫ Backspace.
///
class KeyboardViewController: UIInputViewController {

    // ── Language / Mode State ────────────────────────────────────────────────
    private var isHebrew        = false
    private var isUppercase     = false   // only applies to English
    private var isNumbersMode   = false

    // ── Logging State ────────────────────────────────────────────────────────
    private var previousTextLength   = 0
    private var currentWordCharCount = 0
    private let sharedDefaults = UserDefaults(
        suiteName: "group.com.oriw.pdcollect.ios1.shared"
    )

    // ── UI root ──────────────────────────────────────────────────────────────
    private var keyboardContainer: UIView?

    // ── Geometry ─────────────────────────────────────────────────────────────
    private let rowGap:   CGFloat = 10
    private let keyGap:   CGFloat =  5
    private let sidePad:  CGFloat =  4

    // Key height adapts to portrait vs. landscape
    private var keyH: CGFloat {
        UIScreen.main.bounds.height < 680 ? 38 : 44
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
        container.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.15, alpha: 1)
                : UIColor(white: 0.84, alpha: 1)
        }
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

        // Character rows (rows 0, 1, 2)
        for (i, row) in rows.enumerated() {
            buildCharacterRow(keys: row, y: y, w: w, parent: container)
            y += keyH + rowGap
            _ = i
        }

        // Action row (row 3)
        buildActionRow(y: y, w: w, parent: container)

        keyboardContainer = container

        // Update view intrinsic height
        view.frame = CGRect(x: 0, y: 0, width: w, height: totalH)
    }

    // ── Row builders ─────────────────────────────────────────────────────────

    private func buildCharacterRow(keys: [String], y: CGFloat, w: CGFloat, parent: UIView) {
        let n    = CGFloat(keys.count)
        let kw   = (w - sidePad * 2 - keyGap * (n - 1)) / n
        var x    = sidePad

        for key in keys {
            let title = (isUppercase && !isHebrew && !isNumbersMode && key.count == 1)
                ? key.uppercased()
                : key
            let btn = letterKey(title: title)
            btn.frame = CGRect(x: x, y: y, width: kw, height: keyH)
            btn.addTarget(self, action: #selector(characterPressed(_:)), for: .touchUpInside)
            parent.addSubview(btn)
            x += kw + keyGap
        }
    }

    private func buildActionRow(y: CGFloat, w: CGFloat, parent: UIView) {
        // Fixed widths for special keys
        let globeW: CGFloat = 44
        let langW:  CGFloat = 48
        let backW:  CGFloat = 44
        let retW:   CGFloat = 88
        let totalSpecial = sidePad * 2 + globeW + langW + backW + retW + keyGap * 4
        let spaceW = w - totalSpecial

        var x = sidePad

        // 🌐 — cycle to next system keyboard
        let globe = specialKey(title: "🌐")
        globe.frame = CGRect(x: x, y: y, width: globeW, height: keyH)
        globe.addTarget(self, action: #selector(globePressed(_:)), for: .allTouchEvents)
        parent.addSubview(globe)
        x += globeW + keyGap

        // Language toggle — shows current language as label
        let langLabel = isHebrew ? "EN" : "עA"
        let lang = specialKey(title: langLabel, fontSize: 13)
        lang.frame = CGRect(x: x, y: y, width: langW, height: keyH)
        lang.addTarget(self, action: #selector(langTogglePressed), for: .touchUpInside)
        parent.addSubview(lang)
        x += langW + keyGap

        // Space bar
        let spaceTitle = isHebrew ? "רווח" : (isNumbersMode ? "space" : "space")
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
        parent.addSubview(back)
    }

    // ── Key factories ─────────────────────────────────────────────────────────

    private func letterKey(title: String, fontSize: CGFloat = 17) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: fontSize)
        btn.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.32, alpha: 1)
                : .white
        }
        styleKey(btn)
        return btn
    }

    private func specialKey(title: String, fontSize: CGFloat = 16) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.label, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .medium)
        btn.backgroundColor = UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.22, alpha: 1)
                : UIColor(white: 0.70, alpha: 1)
        }
        styleKey(btn)
        return btn
    }

    private func styleKey(_ btn: UIButton) {
        btn.layer.cornerRadius = 5
        btn.layer.shadowColor  = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.3
        btn.layer.shadowOffset  = CGSize(width: 0, height: 1)
        btn.layer.shadowRadius  = 0.5
        btn.clipsToBounds = false
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    @objc private func characterPressed(_ sender: UIButton) {
        guard let char = sender.title(for: .normal) else { return }
        textDocumentProxy.insertText(char)
        // Auto-cancel shift after one letter
        if isUppercase && !isHebrew {
            isUppercase = false
            buildKeyboard()
        }
        playClick()
    }

    @objc private func spacePressed() {
        flushWordLength()
        textDocumentProxy.insertText(" ")
        playClick()
    }

    @objc private func returnPressed() {
        flushWordLength()
        textDocumentProxy.insertText("\n")
        playClick()
    }

    @objc private func backspacePressed() {
        textDocumentProxy.deleteBackward()
        if currentWordCharCount > 0 { currentWordCharCount -= 1 }
        playClick()
    }

    @objc private func backspaceLongPress(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began || gr.state == .changed {
            textDocumentProxy.deleteBackward()
            if currentWordCharCount > 0 { currentWordCharCount -= 1 }
        }
    }

    /// Passes control to iOS so the user can pick any installed keyboard.
    @objc private func globePressed(_ sender: UIButton) {
        handleInputModeList(from: sender, with: UIEvent())
    }

    /// Switches between Hebrew and English layouts within this keyboard.
    @objc private func langTogglePressed() {
        isHebrew.toggle()
        isUppercase = false
        buildKeyboard()
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
            if kClass == "letter" || kClass == "digit" {
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

    private func classify(_ char: Character) -> String {
        if char.isLetter                       { return "letter" }
        if char.isNumber                       { return "digit" }
        if char == " "                         { return "space" }
        if char == "\n"                        { return "enter" }
        if char.isPunctuation || char.isSymbol { return "punctuation" }
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
