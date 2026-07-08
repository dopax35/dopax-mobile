import SwiftUI
import AVFoundation

/// iOS equivalent of Android's VoiceSampleActivity: shows a short news
/// passage and records the participant reading it aloud for up to 60
/// seconds. Logs one row per recording to voice_log.csv (schema matches
/// Android exactly: timestamp_ms,filename,story_headline,duration_ms).
struct VoiceSampleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private enum RecordState { case idle, recording, recorded }

    @State private var headline = ""
    @State private var storyBody = ""
    @State private var isLoadingStory = true
    @State private var recordState: RecordState = .idle
    @State private var remainingSeconds = 60
    @State private var statusMessage = ""
    @State private var showMicDeniedAlert = false

    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var recordingStartMs: Int64 = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Voice Sample")
                        .font(.title2).fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("Read the story aloud at a normal pace when you press Record. The recording stops automatically after 60 seconds.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    if isLoadingStory {
                        ProgressView()
                            .padding(.vertical, 8)
                    }

                    VStack(alignment: .trailing, spacing: 10) {
                        Text(isLoadingStory ? "טוען כתבה..." : headline)
                            .font(.system(size: 19, weight: .semibold))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if !isLoadingStory {
                            Text(storyBody)
                                .font(.system(size: 19))
                                .lineSpacing(9)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    Button("Load New Story") { loadStory() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(recordState == .recording || isLoadingStory)
                }
                .padding()
            }

            // Fixed bottom controls — mirrors Android's fixed card at the
            // bottom of the screen so Record is always reachable without
            // scrolling past a long story.
            VStack(spacing: 8) {
                if recordState == .recording {
                    Text(String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.dopaxBlue)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button(recordButtonTitle) {
                    if recordState == .recording { stopRecording() } else { requestMicPermissionAndRecord() }
                }
                .buttonStyle(.borderedProminent)
                .tint(recordState == .recording ? .dopaxStatusError : .dopaxBlue)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if recordState == .recorded {
                    Button("Finish and Back to Menu") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.dopaxDarkBlue)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

                Button("Exit Task") {
                    if recordState == .recording { stopRecording() }
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Voice Sample")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recordState == .recording)
        .onAppear { if headline.isEmpty { loadStory() } }
        .onDisappear {
            if recordState == .recording { stopRecording() }
        }
        .alert("Microphone Access Needed", isPresented: $showMicDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record a voice sample.")
        }
    }

    private var recordButtonTitle: String {
        switch recordState {
        case .idle: return "Start Recording"
        case .recording: return "Stop Recording"
        case .recorded: return "Record Again"
        }
    }

    // MARK: - Story loading

    private func loadStory() {
        isLoadingStory = true
        statusMessage = ""
        recordState = .idle
        Task {
            let (title, body) = await fetchLongHebrewStory()
            headline = title
            storyBody = body
            isLoadingStory = false
        }
    }

    // MARK: - Recording

    private func requestMicPermissionAndRecord() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            startRecording()
        case .denied:
            showMicDeniedAlert = true
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted { startRecording() } else { showMicDeniedAlert = true }
                }
            }
        @unknown default:
            break
        }
    }

    private func startRecording() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        recordingStartMs = timestamp
        let url = appState.dataManager.newVoiceRecordingURL(timestamp: timestamp)
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                statusMessage = "Could not start recording"
                return
            }
            audioRecorder = recorder

            recordState = .recording
            remainingSeconds = 60
            statusMessage = "Recording in progress..."
            startCountdown()
        } catch {
            statusMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                stopRecording()
            }
        }
    }

    private func stopRecording() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        let durationMs = Int64(Date().timeIntervalSince1970 * 1000) - recordingStartMs

        audioRecorder?.stop()
        audioRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else {
            statusMessage = "Recording too short — try again"
            if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
            recordingURL = nil
            recordState = .idle
            return
        }

        let secs = durationMs / 1000
        statusMessage = "Saved (\(secs)s) — tap Record Again or Done"
        appState.dataManager.writeVoiceLogEntry(filename: url.lastPathComponent,
                                                 headline: headline,
                                                 durationMs: durationMs)
        recordingURL = nil
        recordState = .recorded
    }
}

// MARK: - Story fetching (RSS + safety filter + curated fallback)

/// Fetches a long-form Hebrew news passage for the participant to read
/// aloud. Mirrors Android's fetchLongHebrewStory(): pulls a live RSS feed,
/// strips distressing headlines, and falls back to curated static stories
/// if the network fails or nothing safe remains.
private func fetchLongHebrewStory() async -> (String, String) {
    guard let url = URL(string: "https://www.ynet.co.il/Integration/StoryRss2.xml") else {
        return randomFallbackStory()
    }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.setValue("PDCollect/1.0", forHTTPHeaderField: "User-Agent")

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            return randomFallbackStory()
        }

        let rawItems = SimpleRSSParser().parse(data: data)

        // This reads live third-party news headlines out loud to a study
        // population that the app's own questionnaire screens for anxiety
        // and depression. Breaking news can include distressing content
        // (attacks, casualties, disasters) with no editorial control on our
        // side, so filter those items out before they can be picked as a
        // "read this aloud" passage — curated fallback stories are used if
        // too little safe content remains. (Matches Android exactly.)
        let safeItems = rawItems.filter { !isDistressingContent("\($0.title) \($0.description)") }
        guard !safeItems.isEmpty else { return randomFallbackStory() }

        let shuffled = safeItems.shuffled()
        let primary = shuffled[0]
        var body = primary.description
        // Add up to 3 secondary stories to ensure plenty of text for 60 seconds.
        for item in shuffled.dropFirst().prefix(3) {
            body += "\n\n\(item.title)\n\n\(item.description)"
        }
        return (primary.title, body)
    } catch {
        return randomFallbackStory()
    }
}

/// Heuristic safety net for the live news feed above: excludes headlines
/// covering death, violence, terror, or disaster so participants aren't
/// unexpectedly asked to read distressing news aloud. Not a substitute for
/// real editorial moderation, but cheap insurance since this text is
/// otherwise shown completely unfiltered. Mirrors Android's blocklist.
private func isDistressingContent(_ text: String) -> Bool {
    let blocklist = [
        // Hebrew
        "נהרג", "נהרגו", "נהרגה", "הרוג", "הרוגים", "רצח", "נרצח", "התאבד", "התאבדות",
        "פיגוע", "טרור", "מחבל", "חטוף", "חטופים", "חטיפה", "טבח", "מלחמה", "אסון",
        "פיצוץ", "מטען חבלה", "ירי", "נפגעים", "תאונת דרכים קטלנית",
        // English (occasional mixed-language wire content)
        "killed", "dead", "death", "murder", "terror attack", "hostage", "massacre",
        "suicide", "bombing", "shooting", "casualties"
    ]
    let lower = text.lowercased()
    return blocklist.contains { lower.contains($0.lowercased()) }
}

private func stripHtml(_ html: String) -> String {
    var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = [
        "&nbsp;": " ", "&amp;": "&", "&quot;": "\"",
        "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">"
    ]
    for (entity, replacement) in entities {
        text = text.replacingOccurrences(of: entity, with: replacement)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func randomFallbackStory() -> (String, String) {
    let fallbacks: [(String, String)] = [
        ("מזג האוויר בישראל", """
מזג האוויר בישראל צפוי להיות נעים ומתון בימים הקרובים. הטמפרטורות יהיו ממוצעות לעונה, עם ערכים שבין שמונה עשרה לעשרים וחמש מעלות צלזיוס. בשעות הצהריים צפויה התחממות קלה, בעוד שהלילות יהיו קרירים ונוחים.

רוחות קלות עד בינוניות צפויות לנשוב ממערב, ולהביא עימן אוויר ים תיכוני רענן ונקי. הלחות תהיה בינונית, כך שלא ייגרם אי נוחות משמעותי. שמיים בהירים צפויים ברוב שעות היום, עם ביטוי ענן חלקי בעיקר בצפון הארץ.

לאחר מספר ימים של יציבות, עשוי להגיע שינוי קל בסוף השבוע, עם עלייה קלה ברמות הלחות ואפשרות לעננות בצפון. תושבי השרון והגליל מתבקשים לשים לב לעדכוני מזג האוויר.

שירות מטאורולוגי ישראל ממליץ לנצל את מזג האוויר הנוח לפעילויות חוץ ולטיולים בטבע, תוך שמירה על שתיית נוזלים מספקת. ילדים וקשישים מתבקשים להיזהר משינויים פתאומיים בטמפרטורה בשעות הבוקר המוקדמות.
"""),
        ("חדשות מהשוק הישראלי", """
שוק המניות הישראלי סגר את המסחר בשבוע החולף עם תוצאות מעורבות. מדד תל אביב מאה עלה בכחצי אחוז, בעוד שמדד תל אביב שלושים וחמישה ירד בשיעור קטן. מגזר הטכנולוגיה הפגין יציבות יחסית, עם עליות קלות בחברות הסייבר והתוכנה המובילות.

נתוני הייצוא החודש הצביעו על מגמת שיפור בענפי הייטק ופרמצבטיקה. יצוא שירותי הטכנולוגיה עלה בשמונה אחוזים בהשוואה לתקופה המקבילה אשתקד. כלכלנים מציינים כי הנתונים מצביעים על חוסן כלכלי בולט, על אף האתגרים הגיאופוליטיים.

בנק ישראל פרסם את הדוח הרבעוני שלו, בו הוא מסמן כי האינפלציה נמצאת במגמת ירידה הדרגתית. הריבית צפויה להישאר ללא שינוי בפגישה הבאה של הוועדה המוניטרית. ממשלת ישראל מקדמת מספר תוכניות לעידוד השקעות זרות ותמיכה ביזמים צעירים.

שוק הנדל"ן ממשיך להציג ביקושים גבוהים, אם כי ניכרת עלייה בהיצע הדירות החדשות. מחירי השכירות בערים הגדולות יציבים יחסית, לאחר שנים של עליות חדות. כלכלנים מייחסים זאת לשיפור בתנאי המשכנתא ולבנייה מואצת בפריפריה.
"""),
        ("ספורט ישראלי וספורטאים מצטיינים", """
נבחרת ישראל בכדורגל ממשיכה בהכנות האינטנסיביות לקראת משחקי הבית הקרובים. הסלקטור הלאומי הכריז על הרכב הנבחרת, הכולל מספר שחקנים צעירים ומבטיחים לצד הוותיקים המנוסים. האימונים מתקיימים בסמנה מרובה פגישות אינטנסיביות, עם דגש על משחק תחתון וכיסוי הגנתי.

בכדורסל, מכבי תל אביב מציגה עונה מרשימה בליגת יורוליג. הקבוצה ניצחה בארבעת משחקיה האחרונים וחיזקה את מקומה בשמונה הגדולות. הקהל הממלא את היכל מנורה מבטיח מדי משחק מתנהג בהתלהבות רבה, ותומך בשחקנים בצורה יוצאת דופן.

בספורט מים, שחיינים ישראלים שברו שישה שיאים ארציים בתחרות הלאומית שנערכה בבאר שבע. הנבחרת הצעירה מביאה ביצועים מעוררי התפעלות, ומגדילה לקוות לתוצאות מפתיעות באליפות אירופה הקרובה.

ספורטאים ישראלים בענפי הלחימה גם הם מוסיפים גאווה למדינה, עם זכייה במדליות בינלאומיות. הג'ודוקאים, האופניסטים ורוכבי האופניים מציגים עוצמה בתחרויות בינלאומיות, ומגייסים מעריצים רבים ברחבי הארץ.
"""),
        ("טכנולוגיה, בינה מלאכותית וחדשנות ישראלית", """
חברות טכנולוגיה ישראליות ממשיכות לרשום הצלחות בינלאומיות מרשימות בתחום הבינה המלאכותית. השנה האחרונה ראתה השקות של מוצרים פורצי דרך במגוון תחומים, החל מרפואה ועד חקלאות. ישראל נחשבת כיום לאחת ממדינות הסטארטאפ המובילות בעולם.

בתחום הסייבר, חברות ביטחון סייבר ישראליות מגייסות השקעות עתק מקרנות בינלאומיות מובילות. הטכנולוגיות שפותחו בישראל מגינות על תשתיות קריטיות ברחבי העולם. המדינה נחשבת ל"ואדי הסיליקון של הסייבר", ומאות מומחים מגיעים כל שנה לרכוש ידע בתעשייה המקומית.

בתחום הבינה המלאכותית הרפואית, מספר חברות ישראליות פיתחו אלגוריתמים לאיתור מוקדם של מחלות. מערכות אלה כבר פועלות בבתי חולים בארצות הברית, גרמניה ויפן, ומסייעות לרופאים לאבחן מחלות מוקדם יותר.

האקדמיה הישראלית גם היא שותפה פעילה בפיתוח הטכנולוגי. אוניברסיטת תל אביב, הטכניון ועוד מספר מוסדות מחקר מובילים פרויקטים בינלאומיים רחבי היקף. שיתופי פעולה עם חברות טכנולוגיה ענקיות כגוגל, מיקרוסופט ואמזון מגבירים את עוצמת המחקר הישראלי.
"""),
        ("חינוך ורווחה חברתית בישראל", """
מערכת החינוך הישראלית עוברת שינויים משמעותיים במגמה להתאים את עצמה לעידן הדיגיטלי. משרד החינוך פתח השנה בתוכנית לאומית להטמעת בינה מלאכותית בבתי ספר, מגן הילדים ועד כיתה יב. כשלושים אלף מורים קיבלו הכשרה מתאימה לשימוש בכלים הדיגיטליים החדשניים.

התלמידים מגלים עניין רב בלמידה מבוססת פרויקטים וחשיבה יצירתית. שיעורי ה-STEM, הכוללים מדע, טכנולוגיה, הנדסה ומתמטיקה, זוכים לפופולריות גוברת. תחרויות ממציאים לצעירים מושכות משתתפים ממחוזות שונים ברחבי הארץ.

בתחום הרווחה החברתית, המדינה מגדילה השנה את תקציבי השירות לאוכלוסיות בסיכון. פעילויות מתנדבים ועמותות מתרחבות בעיר ובפריפריה, עם מאות פרויקטים חברתיים חדשים. אנשים מכל הגילאים יוצאים להתנדב ולסייע לקשישים, ילדים ומשפחות נזקקות.

תוכניות לאומיות לטיפול בתלמידים עם לקויות למידה זוכות להרחבה ולתוספת תקציבית. מומחים בתחום מדגישים כי זיהוי מוקדם ותמיכה מתאימה יכולים לשנות את חייהם של ילדים רבים. ישראל נמצאת בחזית של מחקר ותמיכה ילדים עם אוטיזם, דיסלקציה ולקויות אחרות.
""")
    ]
    return fallbacks.randomElement()!
}

// MARK: - Minimal RSS <item><title>/<description> parser

/// Bare-bones RSS parser mirroring Android's XmlPullParser-based reader:
/// walks <item> elements and collects title/description text (including
/// CDATA-wrapped content), skipping anything malformed. Stops early once
/// 30 items are collected, matching Android's cap.
private final class SimpleRSSParser: NSObject, XMLParserDelegate {
    struct Item { let title: String; let description: String }

    private var items: [Item] = []
    private var currentElement = ""
    private var inItem = false
    private var title = ""
    private var description = ""

    func parse(data: Data) -> [Item] {
        items = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            inItem = true
            title = ""
            description = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let str = String(data: CDATABlock, encoding: .utf8) {
            appendText(str)
        }
    }

    private func appendText(_ string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": title += string
        case "description": description += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "item", inItem else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDescription = stripHtml(description.trimmingCharacters(in: .whitespacesAndNewlines))
        if !cleanTitle.isEmpty && cleanDescription.count > 40 {
            items.append(Item(title: cleanTitle, description: cleanDescription))
        }
        inItem = false
        if items.count >= 30 {
            parser.abortParsing()
        }
    }
}
