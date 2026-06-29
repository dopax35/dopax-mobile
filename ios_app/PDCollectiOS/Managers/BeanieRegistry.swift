import Foundation

struct BeanieProfile {
    let c1: Double           // Tskin correction coefficient
    let heatFluxK: Double    // Heat flux scaling constant
    let needsSensorSwap: Bool // Whether inner/outer sensors are reversed
}

enum BeanieRegistry {

    static let defaultProfile = BeanieProfile(c1: 3.0, heatFluxK: 0.02, needsSensorSwap: true)

    private static let profiles: [String: BeanieProfile] = [
        "pink2":             BeanieProfile(c1: 2.5, heatFluxK: 0.015, needsSensorSwap: false),
        "pink1":             BeanieProfile(c1: 2.2, heatFluxK: 0.012, needsSensorSwap: false),
        "blue1":             BeanieProfile(c1: 2.8, heatFluxK: 0.018, needsSensorSwap: false),
        "pink3":             BeanieProfile(c1: 2.3, heatFluxK: 0.013, needsSensorSwap: false),
        "black 04":          BeanieProfile(c1: 3.2, heatFluxK: 0.0202, needsSensorSwap: true),
        "yoel's beanie":     BeanieProfile(c1: 3.0, heatFluxK: 0.02, needsSensorSwap: true),
        "gabriel's beanie":  BeanieProfile(c1: 2.8, heatFluxK: 0.018, needsSensorSwap: true),
        "trevor's beanie":   BeanieProfile(c1: 3.5, heatFluxK: 0.019, needsSensorSwap: true),
        "black 08":          BeanieProfile(c1: 3.0, heatFluxK: 0.02, needsSensorSwap: true),
        "hefner's beanie":   BeanieProfile(c1: 2.6, heatFluxK: 0.016, needsSensorSwap: true),
        "kong's beanie":     BeanieProfile(c1: 4.0, heatFluxK: 0.008, needsSensorSwap: false),
        "anantha's beanie":  BeanieProfile(c1: 1.8, heatFluxK: 0.01, needsSensorSwap: false),
        "scotty!":           BeanieProfile(c1: 3.0, heatFluxK: 0.02, needsSensorSwap: true),
        "rosanne's beanie":  BeanieProfile(c1: 2.9, heatFluxK: 0.019, needsSensorSwap: true),
        "ori's beanie":      BeanieProfile(c1: 3.1, heatFluxK: 0.02, needsSensorSwap: true),
    ]

    /// Look up the calibration profile for a given device name.
    static func profileForDevice(_ name: String) -> BeanieProfile {
        let normalized = normalizeName(name)
        // Try exact match first
        if let profile = profiles[normalized] {
            return profile
        }
        // Try substring match
        for (key, profile) in profiles {
            if normalized.contains(key) || key.contains(normalized) {
                return profile
            }
        }
        return defaultProfile
    }

    /// Returns the profile key name for logging purposes.
    static func profileNameForDevice(_ name: String) -> String {
        let normalized = normalizeName(name)
        if profiles[normalized] != nil {
            return normalized
        }
        for key in profiles.keys {
            if normalized.contains(key) || key.contains(normalized) {
                return key
            }
        }
        return "default"
    }

    /// Keywords that identify a Beanie device in BLE scan results.
    static let beanieKeywords = ["beanie", "nrf", "v3", "v4", "v4e"]

    /// Check if a device name looks like a Beanie sensor.
    static func isLikelyBeanie(_ name: String) -> Bool {
        let lower = name.lowercased()
        return beanieKeywords.contains { lower.contains($0) }
    }

    private static func normalizeName(_ name: String) -> String {
        var result = name.lowercased()
        // Strip common prefixes
        for prefix in ["beanie ", "nrf ", "v3 ", "v4 ", "v4e "] {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
