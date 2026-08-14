import SwiftUI

private enum ConsentLanguage: String {
    case english = "en"
    case hebrew = "he"

    var chipLabel: String {
        switch self {
        case .english: return "LTR · English"
        case .hebrew: return "RTL · עברית"
        }
    }

    var subtitleLanguageName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "Hebrew"
        }
    }
}

private struct ConsentSection {
    let title: String
    let body: String
}

struct ConsentView: View {
    @EnvironmentObject var appState: AppState
    @State private var scrolledToBottom = false
    @State private var fullName = ""
    @State private var signatureStrokes: [[CGPoint]] = []
    @State private var language: ConsentLanguage = .english

    private let englishSections: [ConsentSection] = [
        ConsentSection(
            title: "Study Purpose",
            body: "You are being invited to participate in a research study about Parkinson's disease. This app collects motor and cognitive test data to help researchers understand disease progression."
        ),
        ConsentSection(
            title: "What We Collect",
            body: "• Active motor test results (finger tapping, hand turning, spiral tracing, Trail Making Test, leg agility)\n• Daily symptom questionnaire responses\n• HealthKit gait metrics (walking speed, step length, steadiness) — only if you grant permission\n• Motion sensor data during active tests only"
        ),
        ConsentSection(
            title: "What We Do NOT Collect",
            body: "• Keystrokes or passwords\n• Screen content\n• Location\n• Any data from other apps"
        ),
        ConsentSection(
            title: "Data Storage & Privacy",
            body: "All data is stored on your device and identified only by a randomly generated participant ID. You can export or delete your data at any time. Data is uploaded to a secure research storage system using encrypted transfer."
        ),
        ConsentSection(
            title: "Voluntary Participation",
            body: "Your participation is completely voluntary. You may withdraw at any time by clearing all data in Settings. Withdrawal will not affect your relationship with the research team."
        ),
        ConsentSection(
            title: "Contact",
            body: "If you have questions about this study, please contact the research team at the institution conducting this study."
        ),
    ]

    // TODO: study team to review translation
    private let hebrewSections: [ConsentSection] = [
        ConsentSection(
            title: "מטרת המחקר",
            body: "אתם מוזמנים להשתתף במחקר על מחלת פרקינסון. האפליקציה אוספת נתוני מוטוריקה וקוגניציה כדי לעזור לחוקרים להבין את התקדמות המחלה."
        ),
        ConsentSection(
            title: "מה אנו אוספים",
            body: "• תוצאות מבחני מוטוריקה פעילים (הקשות אצבעות, סיבוב כף יד, ספירלה, Trail Making Test, זריזות רגליים)\n• תשובות לשאלון תסמינים יומי\n• מדדי הליכה מ-HealthKit (מהירות, אורך צעד, יציבות) — רק אם ניתנה הרשאה\n• נתוני חיישני תנועה במהלך מבחנים פעילים בלבד"
        ),
        ConsentSection(
            title: "מה אנו לא אוספים",
            body: "• הקשות מקלדת או סיסמאות\n• תוכן המסך\n• מיקום\n• נתונים מאפליקציות אחרות"
        ),
        ConsentSection(
            title: "אחסון נתונים ופרטיות",
            body: "כל הנתונים נשמרים במכשיר שלך ומזוהים רק באמצעות מזהה משתתף אקראי. ניתן לייצא או למחוק את הנתונים בכל עת. הנתונים מועלים למערכת אחסון מחקר מאובטחת בהעברה מוצפנת."
        ),
        ConsentSection(
            title: "השתתפות מרצון",
            body: "ההשתתפות שלך היא מרצון לחלוטין. ניתן לפרוש בכל עת על ידי מחיקת כל הנתונים בהגדרות. הפרישה לא תשפיע על הקשר שלך עם צוות המחקר."
        ),
        ConsentSection(
            title: "יצירת קשר",
            body: "אם יש לך שאלות לגבי מחקר זה, אנא פנה לצוות המחקר במוסד המבצע את המחקר."
        ),
    ]

    private var activeSections: [ConsentSection] {
        language == .hebrew ? hebrewSections : englishSections
    }

    private var signatureIsEmpty: Bool {
        signatureStrokes.isEmpty || signatureStrokes.allSatisfy(\.isEmpty)
    }

    private var canContinue: Bool {
        scrolledToBottom
            && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !signatureIsEmpty
    }

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

                Text("Please read and sign. Presented in \(language.subtitleLanguageName).")
                    .font(.system(size: 14.5))
                    .foregroundColor(.dopaxBlack70)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Button {
                    language = language == .english ? .hebrew : .english
                } label: {
                    Text(language.chipLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.onboardingAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.onboardingAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 16)

                GeometryReader { outerGeo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(activeSections.enumerated()), id: \.offset) { _, section in
                                consentSection(section.title, section.body)
                            }

                            Text(language == .hebrew
                                 ? "בלחיצה על \"אני מסכים/ה — המשך\" את/ה מאשר/ת שקראת והבנת טופס הסכמה זה ומסכים/ה להשתתף."
                                 : "By tapping \"I agree — continue\", you confirm you have read and understood this consent form and agree to participate.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                        }
                        .padding(20)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 24)
                        .environment(\.layoutDirection, language == .hebrew ? .rightToLeft : .leftToRight)
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

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingFieldLabel(text: "Full name")
                    OnboardingTextField(placeholder: "Your full name", text: $fullName)

                    SignaturePadView(strokes: $signatureStrokes)

                    HStack {
                        Text("Sign with your finger")
                            .font(.system(size: 13))
                            .foregroundColor(.onboardingTextTertiary)
                        Spacer()
                        if !signatureIsEmpty {
                            Button("Clear") {
                                signatureStrokes = []
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.onboardingAccent)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                OnboardingPrimaryButton(
                    title: "I agree — continue",
                    enabled: canContinue
                ) {
                    submitConsent()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            if fullName.isEmpty && !appState.userProfile.displayName.isEmpty {
                fullName = appState.userProfile.displayName
            }
        }
    }

    @ViewBuilder
    private func consentSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.dopaxBlack90)
                .multilineTextAlignment(language == .hebrew ? .trailing : .leading)
            Text(body)
                .font(.body)
                .foregroundColor(.dopaxBlack70)
                .multilineTextAlignment(language == .hebrew ? .trailing : .leading)
        }
    }

    private func submitConsent() {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if appState.userProfile.displayName.isEmpty {
            appState.userProfile.displayName = trimmedName
        }

        let signatureBase64 = SignaturePadView(strokes: .constant(signatureStrokes))
            .exportPNG(size: CGSize(width: 320, height: 100))?
            .base64EncodedString() ?? ""

        appState.userProfile.consentSignatureName = trimmedName
        appState.userProfile.consentSignatureImage = signatureBase64
        appState.userProfile.consentLocale = language.rawValue
        appState.userProfile.consentGiven = true

        BackendSyncManager.shared.syncConsent(
            signatureName: trimmedName,
            signatureImage: signatureBase64.isEmpty ? nil : signatureBase64,
            documentLocale: language.rawValue
        )
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
