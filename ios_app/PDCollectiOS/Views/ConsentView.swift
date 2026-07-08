import SwiftUI

struct ConsentView: View {
    @EnvironmentObject var appState: AppState
    @State private var scrolledToBottom = false
    @State private var agreed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { outerGeo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Research Consent")
                                .font(.largeTitle).fontWeight(.bold)
                                .padding(.top)

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

                            Spacer(minLength: 32)

                            Text("By tapping 'I Agree', you confirm you have read and understood this consent form and agree to participate.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.bottom)
                        }
                        .padding(.horizontal)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).maxY)
                        })
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { contentBottomY in
                        // contentBottomY is the content's bottom edge position
                        // relative to the scroll viewport; it decreases as the
                        // user scrolls down. Once it reaches (near) the visible
                        // viewport height, the participant has actually scrolled
                        // through the whole consent document. Previously this
                        // closure ignored the value entirely and always set
                        // scrolledToBottom = true on the very first layout pass —
                        // effectively immediately, before any scrolling — and
                        // nothing even read scrolledToBottom afterwards, so the
                        // Agree button was always enabled regardless of whether
                        // the participant had read the document.
                        if contentBottomY <= outerGeo.size.height + 24 {
                            scrolledToBottom = true
                        }
                    }
                }

                Divider()

                Button(action: {
                    appState.userProfile.consentGiven = true
                }) {
                    Text(scrolledToBottom ? "I Agree & Continue" : "Scroll to read the full consent form")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(scrolledToBottom ? Color.dopaxBlue : Color.dopaxGray50)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding()
                }
                .disabled(!scrolledToBottom)
            }
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private func consentSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundColor(.secondary)
        }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
