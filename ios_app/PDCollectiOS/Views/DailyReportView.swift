import SwiftUI

/// Unified daily reporting view — combines Questionnaire, Medication Logging,
/// and Physical Activity reporting. Matches Android's "Daily Report & Medications" menu.
struct DailyReportView: View {
    @State private var selectedSection: ReportSection = .questionnaire

    private enum ReportSection: String, CaseIterable {
        case questionnaire = "Survey"
        case medication = "Medication"
        case activity = "Activity"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(ReportSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            // Content
            switch selectedSection {
            case .questionnaire:
                QuestionnaireView()
            case .medication:
                MedicationLogView()
            case .activity:
                PhysicalActivityLogView()
            }
        }
    }
}
