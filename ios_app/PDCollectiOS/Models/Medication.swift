import Foundation

struct Medication: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var dosage: String
    var unit: String = "pill(s)"
    var count: String = "1"

    init(name: String, dosage: String = "", unit: String = "pill(s)", count: String = "1", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.count = count
        if dosage.isEmpty {
            self.dosage = Self.composeDosage(count: count, unit: unit)
        } else {
            self.dosage = dosage
        }
    }

    static func composeDosage(count: String, unit: String) -> String {
        let c = count.trimmingCharacters(in: .whitespaces)
        let u = unit.trimmingCharacters(in: .whitespaces)
        if c.isEmpty { return u }
        if u.isEmpty { return c }
        return "\(c) \(u)"
    }

    /// Splits a free-text dosage written before this model had count + unit
    /// ("100mg", "2 pill(s)") so the editor shows what the participant actually
    /// recorded. Returns nil for anything not starting with a number ("one
    /// tablet after food"), which the caller then leaves untouched.
    static func parseDosage(_ dosage: String) -> (count: String, unit: String)? {
        let trimmed = dosage.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.range(of: #"^\d+(?:[.,]\d+)?"#, options: .regularExpression) else {
            return nil
        }
        let count = String(trimmed[match])
        let unit = trimmed[match.upperBound...].trimmingCharacters(in: .whitespaces)
        return (count, unit.isEmpty ? "pill(s)" : unit)
    }

    mutating func syncDosageFromFields() {
        dosage = Self.composeDosage(count: count, unit: unit)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, unit, count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        dosage = try container.decodeIfPresent(String.self, forKey: .dosage) ?? ""
        let storedUnit = try container.decodeIfPresent(String.self, forKey: .unit)
        let storedCount = try container.decodeIfPresent(String.self, forKey: .count)

        if let storedUnit, let storedCount {
            unit = storedUnit
            count = storedCount
        } else if let parsed = Self.parseDosage(dosage) {
            count = parsed.count
            unit = parsed.unit
        } else {
            unit = storedUnit ?? "pill(s)"
            count = storedCount ?? "1"
        }

        if dosage.isEmpty {
            dosage = Self.composeDosage(count: count, unit: unit)
        }
    }
}
