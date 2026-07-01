import UIKit

// MARK: - KeyboardViewController
/// A minimal keyboard extension that **observes** text changes and logs
/// only the *class* of each keystroke (letter, digit, space, backspace, etc.)
/// to a shared App Group CSV buffer. It never records the actual character.
///
/// The keyboard UI is intentionally minimal — a status label, a daily
/// counter, and the required "next keyboard" globe button.
class KeyboardViewController: UIInputViewController {

    // MARK: - Properties

    /// Tracks the length of text before the cursor so we can detect
    /// insertions vs. deletions between `textDidChange` calls.
    private var previousLength: Int = 0

    /// Shared `UserDefaults` backed by the App Group container so the
    /// main app can read the daily keystroke count.
    private let sharedDefaults = UserDefaults(suiteName: "group.com.oriw.pdcollect.ios1.shared")

    /// Label that shows how many keystrokes have been logged today.
    private let counterLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Seed previousLength so the first textDidChange has a baseline.
        previousLength = (textDocumentProxy.documentContextBeforeInput ?? "").count
        refreshCounter()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Status label
        let statusLabel = UILabel()
        statusLabel.text = "PDCollect • Logging keystrokes"
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabel

        // Counter label
        counterLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        counterLabel.textColor = .tertiaryLabel
        counterLabel.text = "0 keys logged today"

        // Globe / next-keyboard button (required by Apple)
        let nextKeyboardButton = UIButton(type: .system)
        nextKeyboardButton.setTitle("🌐 Switch Keyboard", for: .normal)
        nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 14)
        nextKeyboardButton.sizeToFit()
        nextKeyboardButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )

        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(counterLabel)
        stack.addArrangedSubview(nextKeyboardButton)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    // MARK: - Text Observation

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)

        let currentText = textDocumentProxy.documentContextBeforeInput ?? ""
        let currentLength = currentText.count

        let keyClass: String
        let isBackspace: Bool

        if currentLength < previousLength {
            // Text got shorter → a deletion occurred.
            keyClass = "backspace"
            isBackspace = true
        } else if currentLength > previousLength, let lastChar = currentText.last {
            // Text got longer → classify the newly inserted character.
            isBackspace = false
            keyClass = classify(lastChar)
        } else {
            // Length unchanged (e.g. cursor moved). Nothing to log.
            previousLength = currentLength
            return
        }

        previousLength = currentLength
        logKeystroke(keyClass: keyClass, isBackspace: isBackspace)
        refreshCounter()
    }

    // MARK: - Character Classification

    /// Returns a privacy-safe category string for `char`.
    /// The actual character value is **never** stored.
    private func classify(_ char: Character) -> String {
        if char.isLetter                       { return "letter" }
        if char.isNumber                       { return "digit" }
        if char == " "                         { return "space" }
        if char == "\n"                        { return "enter" }
        if char.isPunctuation || char.isSymbol { return "punctuation" }
        return "other"
    }

    // MARK: - Logging

    /// Appends a single CSV row to `keystroke_buffer.csv` inside the
    /// App Group shared container.
    ///
    /// Format: `timestamp_ms,key_class,is_backspace,source_app\n`
    ///
    /// `source_app` is always the literal string `"external"` — we
    /// intentionally avoid logging any document context.
    private func logKeystroke(keyClass: String, isBackspace: Bool) {
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let row = "\(timestampMs),\(keyClass),\(isBackspace),external\n"

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.oriw.pdcollect.ios1.shared"
        ) else { return }

        let fileURL = containerURL.appendingPathComponent("keystroke_buffer.csv")

        // Create the file with a header if it doesn't exist yet.
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let header = "timestamp_ms,key_class,is_backspace,source_app\n"
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Append the row.
        if let data = row.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }

        // Bump the daily counter in shared UserDefaults.
        let todayKey = "keystroke_count_\(Date().dateKeyString)"
        let count = (sharedDefaults?.integer(forKey: todayKey) ?? 0) + 1
        sharedDefaults?.set(count, forKey: todayKey)
    }

    // MARK: - Counter Display

    private func refreshCounter() {
        let todayKey = "keystroke_count_\(Date().dateKeyString)"
        let count = sharedDefaults?.integer(forKey: todayKey) ?? 0
        counterLabel.text = "\(count) keys logged today"
    }
}

// MARK: - Date Helper

extension Date {
    /// Returns the date formatted as `"yyyy-MM-dd"` for use as a
    /// UserDefaults key suffix.
    var dateKeyString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: self)
    }
}
