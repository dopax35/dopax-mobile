import SwiftUI

/// The Tests tab (Figma 594:11428): the same nine tests as the daily protocol,
/// as a flat browsable list.
///
/// The old grouped-by-body-system layout was a researcher's taxonomy — it asked
/// the participant to know that Hand Rotation is "motor" before they could find
/// it. This is one list in a fixed order, with the two things a participant
/// actually decides on: what the test is and how long it takes.
///
/// A run started here is practice. It writes its data the same way, and it
/// still counts toward the streak, but it does not advance a session — the
/// protocol only counts tests taken inside their window.
struct TestsTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var running: SessionTest?
    @State private var pendingPermission: SessionTest?

    var body: some View {
        ZStack {
            OnboardingBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    Text("ALL TESTS")
                        .font(.dopax(16, .bold))
                        .kerning(1.2)
                        .foregroundColor(.dopaxBlack90)
                        .padding(.top, 28)

                    VStack(spacing: 10) {
                        ForEach(SessionTest.browseOrder) { test in
                            TestBrowseRow(test: test) { start(test) }
                        }
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(item: $running) { test in
            SessionTestRunner(test: test, position: nil, total: 0)
                .environmentObject(appState)
        }
        .fullScreenCover(item: $pendingPermission) { test in
            permissionPrimer(for: test)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tests")
                .font(.dopax(32, .bold))
                .foregroundColor(.dopaxBlack90)

            Text("Run any test, any time.\nExtra tests are always welcome.")
                .font(.dopax(15))
                .foregroundColor(.dopaxBlack70)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start(_ test: SessionTest) {
        if let capability = test.capability,
           PermissionPrimerView.needsPrimer(for: capability) {
            pendingPermission = test
            return
        }
        running = test
    }

    @ViewBuilder
    private func permissionPrimer(for test: SessionTest) -> some View {
        if let capability = test.capability {
            PermissionPrimerView(capability: capability) { granted in
                pendingPermission = nil
                if granted { running = test }
            }
        }
    }
}

private struct TestBrowseRow: View {
    let test: SessionTest
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.todaySurfaceBrandIdle)
                    Image(systemName: test.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.onboardingAccent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(test.title)
                        .font(.dopax(15, .bold))
                        .foregroundColor(.dopaxBlack90)
                    Text(test.durationHint)
                        .font(.dopax(12.5))
                        .foregroundColor(.dopaxBlack70)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.onboardingTextTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
