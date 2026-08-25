import SwiftUI

/// The session hub — the ordered battery for one period, with live progress.
///
/// This is the screen the whole daily protocol hangs off: it launches the
/// existing test screens, learns when they finish through `SessionManager`,
/// and hands off to the completion screen once the battery is done. It owns
/// no measurement logic of its own.
struct SessionHubView: View {
    let period: SessionPeriod

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SessionHubContent(period: period,
                          session: appState.sessionManager,
                          onClose: { dismiss() })
    }
}

/// Split out so `SessionManager` can be observed directly — `AppState` holds
/// it by reference and would not republish its changes.
private struct SessionHubContent: View {
    let period: SessionPeriod
    @ObservedObject var session: SessionManager
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState

    @State private var runningTest: SessionTest?
    @State private var pendingPermission: SessionTest?
    @State private var showCompletion = false

    /// Redraws the window chip's countdown. A session is short enough that a
    /// half-minute tick is imperceptible and cheap.
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var progress: SessionProgress { session.progress(for: period) }

    var body: some View {
        ZStack {
            OnboardingBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    rows
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 26)
            }
        }
        .onAppear { session.refresh() }
        .onReceive(tick) { _ in session.refresh() }
        .fullScreenCover(item: $runningTest, onDismiss: testRunnerDismissed) { test in
            SessionTestRunner(test: test,
                              position: position(of: test),
                              total: progress.totalCount)
                .environmentObject(appState)
        }
        .fullScreenCover(item: $pendingPermission) { test in
            permissionPrimer(for: test)
        }
        .fullScreenCover(isPresented: $showCompletion, onDismiss: onClose) {
            completionDestination
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 17, weight: .medium))
                    Text("Today")
                        .font(.dopax(14, .medium))
                }
                .foregroundColor(.dopaxBlack70)
            }
            .buttonStyle(.plain)

            Text(period.title)
                .font(.dopax(28, .bold))
                .foregroundColor(.dopaxBlack90)

            HStack(spacing: 8) {
                chip(icon: "clock",
                     text: session.windowCaption(for: period),
                     foreground: .todayTextOnChip,
                     background: .todaySurfaceBrandStrong)

                chip(icon: "checkmark.circle",
                     text: "\(progress.completedCount) of \(progress.totalCount) done",
                     foreground: .sessionSuccess,
                     background: .white)
            }
        }
        .padding(.bottom, 2)
    }

    private func chip(icon: String, text: String,
                      foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(.dopax(12.5, .medium))
        }
        .foregroundColor(foreground)
        .padding(.leading, 11)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(spacing: 10) {
            ForEach(progress.battery) { test in
                SessionHubRow(test: test,
                              state: rowState(for: test),
                              result: progress.result(for: test.id)?.summary) {
                    start(test)
                }
            }
        }
    }

    private func rowState(for test: SessionTest) -> SessionHubRow.State {
        if progress.result(for: test.id) != nil { return .done }
        guard progress.nextTest?.id == test.id else { return .pending }
        // A closed or finished window leaves the remaining rows inert rather
        // than offering a Start that the manager would refuse.
        return session.state(for: period).isActionable ? .upNext : .pending
    }

    private func position(of test: SessionTest) -> Int {
        (progress.battery.firstIndex(of: test) ?? 0) + 1
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause")
                .font(.system(size: 12, weight: .medium))
            Text("Pause anytime — your progress is saved automatically.")
                .font(.dopax(12.5))
        }
        .foregroundColor(.onboardingTextTertiary)
        .padding(.top, 6)
    }

    // MARK: - Running a test

    private func start(_ test: SessionTest) {
        if let capability = test.capability,
           PermissionPrimerView.needsPrimer(for: capability) {
            pendingPermission = test
            return
        }
        launch(test)
    }

    private func launch(_ test: SessionTest) {
        session.beginTest(test.id, in: period)
        runningTest = test
    }

    /// The runner has closed, either because the test finished or because the
    /// participant backed out. Either way the attribution ends here; the
    /// completion itself was already recorded through `GamificationManager`.
    private func testRunnerDismissed() {
        session.endTestRun()
        session.refresh()
        if session.lastOutcome?.sessionCompleted == true {
            showCompletion = true
        }
    }

    @ViewBuilder
    private func permissionPrimer(for test: SessionTest) -> some View {
        if let capability = test.capability {
            PermissionPrimerView(capability: capability) { granted in
                pendingPermission = nil
                // "Not now" skips this one test rather than stalling the
                // session — the remaining rows are still worth collecting.
                if granted { launch(test) }
            }
        }
    }

    // MARK: - Completion

    @ViewBuilder
    private var completionDestination: some View {
        if session.baseline.shouldPresentCompletion {
            BaselineCompleteView(baseline: session.baseline,
                                 name: appState.userProfile.displayName) {
                session.baseline.markCompletionPresented()
                session.clearOutcome()
                showCompletion = false
            }
        } else {
            SessionCompleteView(period: period,
                                name: appState.userProfile.displayName,
                                completedCount: progress.completedCount,
                                totalCount: progress.totalCount,
                                duration: progress.activeDuration,
                                baseline: session.baseline,
                                helixGrew: session.lastOutcome?.helixGrew ?? false) {
                session.clearOutcome()
                showCompletion = false
            }
        }
    }
}

// MARK: - Row

/// One `hub-test-row`. Three states, one component, exactly as the design
/// draws it: a finished test reports what it measured, the next one is the
/// only thing you can tap, and the rest recede.
struct SessionHubRow: View {
    enum State {
        case done
        case upNext
        case pending
    }

    let test: SessionTest
    let state: State
    let result: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            iconWell

            VStack(alignment: .leading, spacing: 2) {
                Text(test.title)
                    .font(.dopax(15, .bold))
                    .foregroundColor(.dopaxBlack90)

                Text(subtitle)
                    .font(.dopax(12.5))
                    .foregroundColor(state == .upNext ? .onboardingAccent : .dopaxBlack70)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.onboardingAccentSoft, lineWidth: state == .upNext ? 2 : 0)
        )
        .opacity(state == .pending ? 0.62 : 1)
    }

    private var subtitle: String {
        switch state {
        case .done:    return result ?? "Done"
        case .upNext:  return "Up next · \(test.shortDurationHint)"
        case .pending: return test.durationHint
        }
    }

    private var iconWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(state == .pending ? Color.todaySurfaceBrandIdle : Color.todaySurfaceBrand)
            Image(systemName: test.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.onboardingAccent)
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.sessionSuccess)

        case .upNext:
            Button(action: action) {
                Text("Start")
                    .font(.dopax(13, .bold))
                    .foregroundColor(.white)
                    .frame(width: 86, height: 32)
                    .background(Color.onboardingAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

        case .pending:
            EmptyView()
        }
    }
}
