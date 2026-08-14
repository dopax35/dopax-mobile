import SwiftUI

/// The home screen: what the participant is meant to do right now.
///
/// Everything on it is derived from `SessionManager`, so the card states, the
/// task row, and the greeting cannot drift from each other.
struct TodayView: View {
    @EnvironmentObject var appState: AppState

    /// Called after a session is begun, so the shell can route to the tests.
    var onOpenSession: (SessionPeriod) -> Void = { _ in }

    var body: some View {
        TodayContent(session: appState.sessionManager,
                     profile: appState.userProfile,
                     onOpenSession: onOpenSession)
    }
}

/// Split from `TodayView` so the managers can be observed directly —
/// `AppState` holds them by reference and would not republish their changes.
private struct TodayContent: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var profile: UserProfile
    let onOpenSession: (SessionPeriod) -> Void

    @State private var presentedTask: DailyTask?

    var body: some View {
        ZStack {
            OnboardingBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    sessions
                    tasks
                    articles
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear { session.refresh() }
        .sheet(item: $presentedTask) { task in
            taskSheet(task)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dateFormatter.string(from: session.lastRefresh).uppercased())
                .font(.system(size: 13.5, weight: .medium))
                .kerning(1)
                .foregroundColor(.dopaxBlack70)

            Text(greeting)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.dopaxBlack90)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: session.lastRefresh)
        let salutation: String
        switch hour {
        case 0..<12:  salutation = "Good morning"
        case 12..<18: salutation = "Good afternoon"
        default:      salutation = "Good evening"
        }
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    // MARK: - Sessions

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("TODAY'S SESSIONS")

            ForEach(session.schedule.orderedPeriods, id: \.self) { period in
                SessionCard(period: period,
                            state: session.state(for: period),
                            subtitle: session.cardSubtitle(for: period)) {
                    open(period)
                }
            }
        }
        .padding(24)
    }

    private func open(_ period: SessionPeriod) {
        guard session.beginSession(period) else { return }
        onOpenSession(period)
    }

    // MARK: - Tasks

    @ViewBuilder
    private var tasks: some View {
        let outstanding = session.outstandingTasks
        if !outstanding.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("TODAY'S TASKS")

                HStack(alignment: .top, spacing: 14) {
                    ForEach(outstanding) { task in
                        TodayTaskCard(task: task) { presentedTask = task }
                    }
                    // Keeps a lone remaining card at half width rather than
                    // letting it stretch across the row.
                    if outstanding.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func taskSheet(_ task: DailyTask) -> some View {
        NavigationView {
            Group {
                switch task {
                case .questionnaire: QuestionnaireView()
                case .medication:    MedicationLogView()
                }
            }
            .navigationTitle(task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentedTask = nil }
                }
            }
        }
    }

    // MARK: - Articles

    private var articles: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("ARTICLES FOR YOU")
                .padding(.horizontal, 24)

            TodayArticlesCarousel(articles: TodayArticle.bundled)
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .kerning(1.2)
            .foregroundColor(.dopaxBlack90)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter
    }()
}
