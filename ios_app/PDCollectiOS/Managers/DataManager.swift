import Foundation
import ZIPFoundation

class DataManager: ObservableObject {
    var userId: String
    private let fm = FileManager.default

    // Serialised writers — one per file type to avoid race conditions
    private let writeQueue = DispatchQueue(label: "com.pdcollect.data-writer", qos: .utility)

    init(userId: String) {
        self.userId = userId
    }

    // MARK: - Directories

    private var rootDir: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PDCollect")
    }

    private func userDir() -> URL {
        rootDir.appendingPathComponent(userId)
    }

    func dateDirectory(for dateKey: String) -> URL {
        userDir().appendingPathComponent(dateKey)
    }

    private var todayDir: URL {
        dateDirectory(for: Date().dateKey)
    }

    private func ensureDir(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Active-test Writes (Android-compatible per-event format)

    // MARK: Finger Tapping
    /// Writes one row to finger_tapping.csv. event = "START", "SAMPLE", or "END".
    /// button_id is the side that was tapped (empty for START/END).
    func writeFingerTappingRow(wallMs: Int64, elapsedMs: Int64,
                               event: String, buttonId: String,
                               side: String, profile: UserProfile) {
        let row = "\(wallMs),\(elapsedMs),\(event),\(buttonId),\(side),\(profile.dominantHand),\(profile.affectedSide)\n"
        append(row, to: todayDir, filename: Constants.CSV.fingerTappingFile,
               header: Constants.CSV.fingerTappingHeader)
    }

    // MARK: Hand Turning
    /// Writes one row to hand_turning.csv. sensor cols are empty string for START/END.
    func writeHandTurningRow(wallMs: Int64, elapsedMs: Int64,
                             event: String,
                             gx: String, gy: String, gz: String,
                             ax: String, ay: String, az: String,
                             side: String, profile: UserProfile) {
        let row = "\(wallMs),\(elapsedMs),\(event),\(gx),\(gy),\(gz),\(ax),\(ay),\(az),\(side),\(profile.dominantHand),\(profile.affectedSide)\n"
        append(row, to: todayDir, filename: Constants.CSV.handTurningFile,
               header: Constants.CSV.handTurningHeader)
    }

    // MARK: Leg Agility (same schema as hand_turning)
    func writeLegAgilityRow(wallMs: Int64, elapsedMs: Int64,
                            event: String,
                            gx: String, gy: String, gz: String,
                            ax: String, ay: String, az: String,
                            side: String, profile: UserProfile) {
        let row = "\(wallMs),\(elapsedMs),\(event),\(gx),\(gy),\(gz),\(ax),\(ay),\(az),\(side),\(profile.dominantHand),\(profile.affectedSide)\n"
        append(row, to: todayDir, filename: Constants.CSV.legAgilityFile,
               header: Constants.CSV.legAgilityHeader)
    }

    // MARK: Spiral Tracing
    /// action = "DOWN", "MOVE", or "UP". x/y empty for START/END.
    func writeSpiralTracingRow(wallMs: Int64, elapsedMs: Int64,
                               event: String, x: String, y: String, action: String,
                               side: String, profile: UserProfile) {
        let row = "\(wallMs),\(elapsedMs),\(event),\(x),\(y),\(action),\(side),\(profile.dominantHand),\(profile.affectedSide)\n"
        append(row, to: todayDir, filename: Constants.CSV.spiralTracingFile,
               header: Constants.CSV.spiralTracingHeader)
    }

    // MARK: TMT
    /// One summary row per completed TMT part, matching Android tmt_results.csv.
    func writeTMTResult(startMs: Int64, endMs: Int64, testType: String,
                        totalMs: Int, wrongTargetErrors: Int, liftOffErrors: Int,
                        segmentTimingsJSON: String,
                        fingerPathJSON: String) {
        let escapedSegments = segmentTimingsJSON.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedFingerPath = fingerPathJSON.replacingOccurrences(of: "\"", with: "\"\"")
        let row = "\(startMs),\(endMs),\(testType),\(totalMs),\(wrongTargetErrors),\(liftOffErrors),\"\(escapedSegments)\",\"\(escapedFingerPath)\",\"\(escapedFingerPath)\"\n"
        append(row, to: todayDir, filename: Constants.CSV.tmtResultsFile,
               header: Constants.CSV.tmtResultsHeader)
    }

    func writeQuestionnaire(_ response: QuestionnaireResponse) {
        append(response.csvRow, to: todayDir, filename: Constants.CSV.questionnaireFile,
               header: Constants.CSV.questionnaireHeader)
    }

    func writeSensorReadings(_ readings: [SensorReading], dateKey: String? = nil) {
        let dir  = dateKey.map { dateDirectory(for: $0) } ?? todayDir
        let rows = readings.map(\.csvRow).joined()
        append(rows, to: dir, filename: Constants.CSV.sensorsFile,
               header: Constants.CSV.sensorsHeader)
    }

    func writeGaitMetrics(csvString: String) {
        let file = rootDir.appendingPathComponent("gait_metrics_export.csv")
        try? csvString.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Append a HealthKit gait-metrics CSV block (used by BackgroundCollectionManager).
    func appendGaitMetrics(csvString: String) {
        let file = todayDir.appendingPathComponent(Constants.CSV.gaitMetricsFile)
        writeQueue.async { [weak self] in
            guard let self else { return }
            ensureDir(todayDir)
            if !fm.fileExists(atPath: file.path) {
                try? Constants.CSV.gaitMetricsHeader.write(to: file, atomically: true, encoding: .utf8)
            }
            // Append rows only (skip duplicate header if csvString starts with header)
            var toAppend = csvString
            if toAppend.hasPrefix("date,") {
                toAppend = toAppend.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            }
            appendRaw(toAppend, to: file)
        }
    }

    // MARK: - Passive Sensor Writes (new)

    func writePassiveSensorReadings(_ readings: [SensorReading]) {
        let rows = readings.map(\.csvRow).joined()
        append(rows, to: todayDir, filename: Constants.CSV.passiveSensorsFile,
               header: Constants.CSV.passiveSensorsHeader)
    }

    // MARK: - Touch Writes (new)

    func writeTouchEvent(_ event: TouchEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.touchFile,
               header: Constants.CSV.touchHeader)
    }

    // MARK: - App Event Writes (new)

    func writeAppEvent(_ event: AppEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.appsFile,
               header: Constants.CSV.appsHeader)
    }

    // MARK: - Face Distance Writes (new)

    func writeFaceSample(_ sample: FaceDistanceSample) {
        append(sample.csvRow, to: todayDir, filename: Constants.CSV.faceDistanceFile,
               header: Constants.CSV.faceDistanceHeader)
    }

    // MARK: - Bluetooth Heart Rate Writes

    func writeHeartRateData(_ reading: HeartRateReading) {
        append(reading.csvRow, to: todayDir, filename: Constants.CSV.heartRateFile,
               header: Constants.CSV.heartRateHeader)
    }

    // MARK: - Bluetooth Beanie Temperature Writes

    func writeBeanieTemperatureData(_ reading: BeanieTemperatureReading) {
        append(reading.csvRow, to: todayDir, filename: Constants.CSV.beanieTemperatureFile,
               header: Constants.CSV.beanieTemperatureHeader)
    }

    // MARK: - Bluetooth Beanie IMU Writes

    func writeBeanieImuData(_ readings: [BeanieIMUReading]) {
        let rows = readings.map(\.csvRow).joined()
        append(rows, to: todayDir, filename: Constants.CSV.beanieImuFile,
                header: Constants.CSV.beanieImuHeader)
    }

    // MARK: - Keystroke Event Writes

    func writeKeystrokeEvent(_ event: KeystrokeEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.keyEventsFile,
               header: Constants.CSV.keyEventsHeader)
    }

    // MARK: - Medication Event Writes

    func writeMedicationEvent(_ event: MedicationEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.medicationFile,
               header: Constants.CSV.medicationHeader)
    }

    // MARK: - Physical Activity Writes

    func writePhysicalActivityEvent(_ event: PhysicalActivityEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.physicalActivityFile,
               header: Constants.CSV.physicalActivityHeader)
    }

    // MARK: - Sleep Writes

    func writeSleepEvent(_ event: SleepEvent) {
        append(event.csvRow, to: todayDir, filename: Constants.CSV.sleepFile,
               header: Constants.CSV.sleepHeader)
    }

    // MARK: - Pedometer History Writes (iOS-only backfill, see PedometerHistoryService)

    /// Backfilled rows land in the CSV for the date they actually happened on
    /// (periodStartMs), not "today" — otherwise a sync that runs after
    /// midnight would misfile yesterday evening's steps into today's folder.
    func writePedometerSample(_ sample: PedometerSample) {
        let dateKey = Date(timeIntervalSince1970: Double(sample.periodStartMs) / 1000).dateKey
        append(sample.csvRow, to: dateDirectory(for: dateKey), filename: Constants.CSV.pedometerFile,
               header: Constants.CSV.pedometerHeader)
    }

    // MARK: - Motion Activity History Writes (iOS-only backfill, see MotionActivityHistoryService)

    func writeMotionActivitySample(_ sample: MotionActivitySample) {
        let dateKey = Date(timeIntervalSince1970: Double(sample.activityStartMs) / 1000).dateKey
        append(sample.csvRow, to: dateDirectory(for: dateKey), filename: Constants.CSV.motionActivityFile,
               header: Constants.CSV.motionActivityHeader)
    }

    // MARK: - Profile Snapshot

    /// Writes a daily profile snapshot to profile.csv.
    /// Called once per app launch / collection start.
    func writeProfileSnapshot(profile: UserProfile) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let medsJSON: String
        if let data = try? JSONEncoder().encode(profile.medications),
           let str = String(data: data, encoding: .utf8) {
            medsJSON = str.replacingOccurrences(of: ",", with: ";") // avoid CSV comma conflict
        } else {
            medsJSON = "[]"
        }
        let row = "\(nowMs),\(profile.userId),\(profile.age),\(profile.gender),\(profile.dominantHand),\(profile.affectedSide),\(medsJSON)\n"
        append(row, to: todayDir, filename: Constants.CSV.profileFile,
               header: Constants.CSV.profileHeader)
    }

    // MARK: - Voice Sample

    /// Returns a fresh file URL for a new voice-sample recording, creating
    /// the containing "voice" subdirectory under today's data folder if
    /// needed. Mirrors Android's File(getDayDir(), "voice")/voice_<ts>.m4a.
    func newVoiceRecordingURL(timestamp: Int64) -> URL {
        let dir = todayDir.appendingPathComponent("voice")
        ensureDir(dir)
        return dir.appendingPathComponent("voice_\(timestamp).m4a")
    }

    /// Appends one row to voice_log.csv (schema matches Android exactly).
    func writeVoiceLogEntry(filename: String, headline: String, durationMs: Int64) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let safeHeadline = headline.replacingOccurrences(of: "\"", with: "\"\"")
        let row = "\(timestamp),\"\(filename)\",\"\(safeHeadline)\",\(durationMs)\n"
        append(row, to: todayDir, filename: Constants.CSV.voiceLogFile,
               header: Constants.CSV.voiceLogHeader)
    }

    // MARK: - Internal append (thread-safe)

    private func append(_ content: String, to dir: URL, filename: String, header: String) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            ensureDir(dir)
            let file = dir.appendingPathComponent(filename)
            if !fm.fileExists(atPath: file.path) {
                try? header.write(to: file, atomically: true, encoding: .utf8)
            }
            appendRaw(content, to: file)
        }
    }

    private func appendRaw(_ content: String, to file: URL) {
        guard let data   = content.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: file) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    // MARK: - Listing

    func listDates() -> [String] {
        let dir = userDir()
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .filter { $0.count == 10 && $0.contains("-") }
            .sorted(by: >)
    }

    func sizeString(for dateKey: String) -> String {
        let dir = dateDirectory(for: dateKey)
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 KB" }
        let totalBytes = items.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    func fileCount(for dateKey: String) -> Int {
        let dir = dateDirectory(for: dateKey)
        return (try? fm.contentsOfDirectory(atPath: dir.path).count) ?? 0
    }

    func fileList(for dateKey: String) -> [String] {
        let dir = dateDirectory(for: dateKey)
        return (try? fm.contentsOfDirectory(atPath: dir.path).sorted()) ?? []
    }

    func isUploaded(_ dateKey: String) -> Bool {
        fm.fileExists(atPath: dateDirectory(for: dateKey).appendingPathComponent(".uploaded").path)
    }

    func markUploaded(_ dateKey: String) {
        let marker = dateDirectory(for: dateKey).appendingPathComponent(".uploaded")
        fm.createFile(atPath: marker.path, contents: nil)
    }

    // MARK: - ZIP

    func zipDate(_ dateKey: String) throws -> URL {
        let sourceDir = dateDirectory(for: dateKey)
        let cacheDir  = fm.temporaryDirectory.appendingPathComponent("PDCollectZips")
        ensureDir(cacheDir)
        let zipURL = cacheDir.appendingPathComponent("\(dateKey)_\(userId).zip")
        if fm.fileExists(atPath: zipURL.path) { try? fm.removeItem(at: zipURL) }
        try fm.zipItem(at: sourceDir, to: zipURL)
        return zipURL
    }

    // MARK: - Deletion

    func deleteDate(_ dateKey: String) {
        try? fm.removeItem(at: dateDirectory(for: dateKey))
    }

    func deleteAllData() {
        try? fm.removeItem(at: userDir())
    }
}