import SwiftUI

struct ConsentView: View {
    @EnvironmentObject var appState: AppState
    @State private var scrolledToBottom = false

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressDots(total: 7, current: 0)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                Text("Research consent")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.dopaxBlack90)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                Text("Please read and sign. Scroll to the end to continue.")
                    .font(.system(size: 14.5))
                    .foregroundColor(.dopaxBlack70)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                GeometryReader { outerGeo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Group {
                                consentSection("Study Purpose",
                                    "You are being invited to participate in a research study about Parkinson's disease. This app collects motor and cognitive test data to help researchers understand disease progression.")

                                consentSection("What We Collect",
                                    "• Active motor test results (finger tapping, hand turning, spiral tracing, Trail Making Test, leg agility)\n• Daily symptom questionnaire responses\n• HealthKit gait metrics (walking speed, step length, steadiness) — only if you grant permission\n• Motion sensor data during active tests only")

                                consentSection("What We Do NOT Collect",
                                    "• Keystrokes or passwords\n• Screen content\n• Location\n• Any data from other apps")

                                consentSection("Data Storage & Privacy",
                                    "All data is stored on your device and identified only by a randomly generated participant ID. You can export or delete your data at any time. Data is uploaded to a secure research storage system using encrypted transfer.")

                                consentSection("Voluntary Participation",
                                    "Your participation is completely voluntary. You may withdraw at any time by clearing all data in Settings. Withdrawal will not affect your relationship with the research team.")

                                consentSection("Contact",
                                    "If you have questions about this study, please contact the research team at the institution conducting this study.")
                            }

                            Text("By tapping Continue, you confirm you have read and understood this consent form and agree to participate.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                        }
                        .padding(20)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 24)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).maxY
                            )
                        })
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { contentBottomY in
                        if contentBottomY <= outerGeo.size.height + 24 {
                            scrolledToBottom = true
                        }
                    }
                }

                OnboardingPrimaryButton(
                    title: scrolledToBottom ? "Continue" : "Scroll to read the full consent form",
                    enabled: scrolledToBottom
                ) {
                    let name = appState.userProfile.displayName.isEmpty
                        ? "participant"
                        : appState.userProfile.displayName
                    appState.userProfile.consentGiven = true
                    BackendSyncManager.shared.syncConsent(signatureName: name)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func consentSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundColor(.dopaxBlack90)
            Text(body).font(.body).foregroundColor(.dopaxBlack70)
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
