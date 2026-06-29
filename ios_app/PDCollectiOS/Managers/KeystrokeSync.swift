import Foundation

// KeystrokeEvent model is defined in Models/KeystrokeEvent.swift

// MARK: - KeystrokeSync

/// Reads keystroke events that the keyboard extension buffered into the
/// shared App Group container (`keystroke_buffer.csv`) and forwards them
/// to the main app's `DataManager` for permanent storage.
///
/// Call `importBufferedKeystrokes(dataManager:)` whenever the app returns
/// to the foreground or when a new data-collection session starts.
final class KeystrokeSync {

    // MARK: - Constants

    private let appGroupID = "group.com.oriweissberg.pdcollect.shared"
    private let bufferFileName = "keystroke_buffer.csv"

    // MARK: - Import

    /// Reads every row from the shared CSV buffer, converts each to a
    /// `KeystrokeEvent`, writes it through `DataManager`, and then
    /// **deletes** the buffer file so events are not imported twice.
    ///
    /// - Parameter dataManager: The app's `DataManager` instance that
    ///   will persist the events into the appropriate daily CSV.
    func importBufferedKeystrokes(dataManager: DataManager) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            print("[KeystrokeSync] ⚠️ Could not access App Group container.")
            return
        }

        let bufferURL = containerURL.appendingPathComponent(bufferFileName)

        guard FileManager.default.fileExists(atPath: bufferURL.path) else {
            // Nothing to import — this is the normal case when the user
            // hasn't typed since the last sync.
            return
        }

        guard let content = try? String(contentsOf: bufferURL, encoding: .utf8) else {
            print("[KeystrokeSync] ⚠️ Could not read buffer file.")
            return
        }

        // Parse rows, skipping the header and any blank lines.
        let lines = content
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.hasPrefix("timestamp_ms") }

        var importedCount = 0

        for line in lines {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 4,
                  let ts = Int64(cols[0]) else {
                continue
            }

            let event = KeystrokeEvent(
                timestampMs: ts,
                keyClass: cols[1],
                isBackspace: cols[2] == "true",
                sourceApp: cols[3]
            )

            dataManager.writeKeystrokeEvent(event)
            importedCount += 1
        }

        // Remove the buffer so we don't re-import the same events.
        do {
            try FileManager.default.removeItem(at: bufferURL)
        } catch {
            print("[KeystrokeSync] ⚠️ Failed to clear buffer: \(error)")
        }

        print("[KeystrokeSync] ✅ Imported \(importedCount) keystroke events.")
    }
}
