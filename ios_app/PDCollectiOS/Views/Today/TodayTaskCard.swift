import SwiftUI

/// A "TODAY'S TASKS" card — the questionnaire and medication shortcuts that sit
/// beneath the session cards.
struct TodayTaskCard: View {
    let task: DailyTask
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.todaySurfaceBrand)
                    Image(systemName: task.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.onboardingAccent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.dopaxBlack90)
                    Text(task.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.dopaxBlack70)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
        }
        .buttonStyle(.plain)
    }
}
