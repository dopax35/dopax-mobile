import Foundation

/// A single keystroke event. Privacy-first: only the key class is recorded,
/// never the actual character.
struct KeystrokeEvent {
    let timestampMs: Int64
    // Must match Android's vocabulary exactly (Constants.kt): one of
    // "char", "digit", "space", "backspace", "punct", "enter", "other".
    let keyClass: String
    let isBackspace: Bool
    let sourceApp: String    // bundle ID or "keyboard_extension"

    var csvRow: String {
        "\(timestampMs),\(keyClass),\(isBackspace),\(sourceApp)\n"
    }

    /// Classify a character into a privacy-safe key class. Not currently
    /// called anywhere — KeystrokeSync passes the keyboard extension's own
    /// already-classified keyClass straight through — but kept in sync with
    /// KeyboardViewController.classify()'s vocabulary so it isn't a latent
    /// trap if something starts calling it later.
    static func classify(_ char: Character) -> (keyClass: String, isBackspace: Bool) {
        if char.isLetter { return ("char", false) }
        if char.isNumber { return ("digit", false) }
        if char == " "   { return ("space", false) }
        if char == "\n" || char == "\r" { return ("enter", false) }
        if char.isPunctuation || char.isSymbol { return ("punct", false) }
        return ("other", false)
    }
}
