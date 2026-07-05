import Foundation

struct Medication: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var dosage: String
    
    // Custom coding keys to exclude `id` from JSON if needed, but keeping it simple for now.
}
