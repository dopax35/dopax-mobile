import SwiftUI
import UIKit

/// A row displayed in Settings that shows whether the PDCollect Keyboard is
/// enabled and active, and gives the user a one-tap path to fix either issue.
///
/// Enabled  = keyboard appears in iOS Settings → General → Keyboard → Keyboards list
/// Active   = keyboard is selected as the current/default keyboard
struct KeyboardSetupRow: View {

    @State private var isEnabled: Bool = false
    @State private var isActive:  Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Status indicator
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .fontWeight(.medium)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Action buttons
            if !isEnabled {
                // Step 1: enable the keyboard in iOS Settings
                Button(action: openKeyboardSettings) {
                    Label("Enable in iOS Settings", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.dopaxBlue)

                Text("Tap above → General → Keyboard → Keyboards → Add New Keyboard → PDCollect Keyboard")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            } else if !isActive {
                // Step 2: switch to it (globe key or input method settings)
                Button(action: openKeyboardSettings) {
                    Label("Switch keyboard in iOS Settings", systemImage: "keyboard.badge.ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Or tap the 🌐 globe key while typing to select PDCollect Keyboard.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear { refresh() }
        // Re-check every time the app returns from background (user may have changed settings)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refresh()
        }
    }

    // MARK: - State computation

    private var statusIcon: String {
        if isActive  { return "checkmark.circle.fill" }
        if isEnabled { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private var statusColor: Color {
        if isActive  { return .green }
        if isEnabled { return .orange }
        return .red
    }

    private var statusTitle: String {
        if isActive  { return "PDCollect Keyboard is active ✓" }
        if isEnabled { return "Keyboard enabled — not yet selected" }
        return "Keyboard not enabled"
    }

    private var statusSubtitle: String {
        if isActive  { return "Typing metrics are being collected." }
        if isEnabled { return "Tap the 🌐 globe key while typing to switch." }
        return "Enable it in iOS Settings so typing can be measured."
    }

    // MARK: - Helpers

    private func refresh() {
        isEnabled = PDKeyboardChecker.isEnabled
        isActive  = PDKeyboardChecker.isActive
    }

    private func openKeyboardSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - PDKeyboardChecker
/// Checks whether the PDCollect keyboard extension is enabled / active.
enum PDKeyboardChecker {
    static let bundleID = "com.oriw.pdcollect.ios1.keyboard"

    /// True when the user has added the keyboard to their list in iOS Settings.
    static var isEnabled: Bool {
        let imm = UITextInputMode.activeInputModes
        return imm.contains { $0.primaryLanguage?.contains("en") == true }
            // We check via UserDefaults written by the extension itself as a proxy,
            // since iOS does not expose a direct API to query which keyboards are installed.
            // A UserDefaults key written on first launch of the extension signals it ran.
            || (UserDefaults(suiteName: "group.com.oriw.pdcollect.ios1.shared")?
                .bool(forKey: "keyboard_ever_launched") ?? false)
    }

    /// True when the PDCollect keyboard is the currently selected default.
    static var isActive: Bool {
        // The extension writes "keyboard_last_launch_date" when it becomes active.
        guard let defaults = UserDefaults(suiteName: "group.com.oriw.pdcollect.ios1.shared"),
              let lastLaunch = defaults.object(forKey: "keyboard_last_launch_date") as? Date else {
            return false
        }
        // Consider it "active" if it was used in the last 5 minutes
        return Date().timeIntervalSince(lastLaunch) < 300
    }
}
