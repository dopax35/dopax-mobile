import Foundation
import SwiftUI

extension Date {
    var dateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 130)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - iOS 16 compatible pulse animation (replaces .symbolEffect on iOS 17)
struct PulseModifier: ViewModifier {
    @State private var pulsing = false
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            // On iOS 17+ the caller can use .symbolEffect directly;
            // here we just pass through (symbolEffect already applied above)
            content
        } else {
            content
                .scaleEffect(pulsing ? 1.08 : 1.0)
                .opacity(pulsing ? 0.85 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                           value: pulsing)
                .onAppear { pulsing = true }
        }
    }
}

// MARK: - iOS 16 compatible Empty State
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    var descriptionText: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            if let desc = descriptionText {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
