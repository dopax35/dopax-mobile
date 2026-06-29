import Foundation

/// A single keystroke event. Privacy-first: only the key class is recorded,
/// never the actual character.
struct KeystrokeEvent {
    let timestampMs: Int64
    let keyClass: String     // "letter", "digit", "space", "backspace", "punctuation", "enter", "other"
    let isBackspace: Bool
    let sourceApp: String    // bundle ID or "keyboard_extension"

    var csvRow: String {
        "\(timestampMs),\(keyClass),\(isBackspace),\(sourceApp)\n"
    }

    /// Classify a character into a privacy-safe key class.
    static func classify(_ char: Character) -> (keyClass: String, isBackspace: Bool) {
        if char.isLetter { return ("letter", false) }
        if char.isNumber { return ("digit", false) }
        if char == " "   { return ("space", false) }
        if char == "\n" || char == "\r" { return ("enter", false) }
        if char.isPunctuation || char.isSymbol { return ("punctuation", false) }
        return ("other", false)
    }
}
