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

    // MARK: - Daily Initialisation

    /// Pre-creates ALL expected CSV files for today's directory with their header rows.
    /// Call once at collection start so every file always exists — even for sensor types
    /// that recorded nothing that day. This guarantees the nightly zip and the research
    /// data pipeline always see a complete, consistent set of files, matching Android's
    /// `DataManager.initializeAllDailyLogs()` behaviour exactly.
    func initializeDailyFiles() {
        writeQueue.async { [weak self] in
            guard let self else { return }
            let dir = todayDir
            ensureDir(dir)
            let files: [(String, String)] = [
                // Passive / sensor files
                (Constants.CSV.sensorsFile,          Constants.CSV.sensorsHeader),
                (Constants.CSV.passiveSensorsFile,   Constants.CSV.passiveSensorsHeader),
                (Constants.CSV.touchFile,            Constants.CSV.touchHeader),
                (Constants.CSV.keyEventsFile,        Constants.CSV.keyEventsHeader),
                (Constants.CSV.appsFile,             Constants.CSV.appsHeader),
                (Constants.CSV.faceDistanceFile,     Constants.CSV.faceDistanceHeader),
                (Constants.CSV.gazeFile,             Constants.CSV.gazeHeader),
                (Constants.CSV.medicationFile,       Constants.CSV.medicationHeader),
                (Constants.CSV.physicalActivityFile, Constants.CSV.physicalActivityHeader),
                (Constants.CSV.sleepFile,            Constants.CSV.sleepHeader),
                (Constants.CSV.heartRateFile,        Constants.CSV.heartRateHeader),
                (Constants.CSV.blinkLogFile,         Constants.CSV.blinkLogHeader),
                (Constants.CSV.voiceLogFile,         Constants.CSV.voiceLogHeader),
                (Constants.CSV.gaitMetricsFile,      Constants.CSV.gaitMetricsHeader),
                (Constants.CSV.pedometerFile,        Constants.CSV.pedometerHeader),
                (Constants.CSV.motionActivityFile,   Constants.CSV.motionActivityHeader),
                // SensorKit files
                (Constants.CSV.sensorKitAccelerometerFile, Constants.CSV.sensorKitAccelerometerHeader),
                (Constants.CSV.sensorKitRotationRateFile,  Constants.CSV.sensorKitRotationRateHeader),
                (Constants.CSV.sensorKitKeyboardFile,      Constants.CSV.sensorKitKeyboardHeader),
                (Constants.CSV.sensorKitDeviceUsageFile,   Constants.CSV.sensorKitDeviceUsageHeader),
                // Beanie files
                (Constants.CSV.beanieTemperatureFile, Constants.CSV.beanieTemperatureHeader),
                (Constants.CSV.beanieImuFile,         Constants.CSV.beanieImuHeader),
                // Active test files
                (Constants.CSV.fingerTappingFile,    Constants.CSV.fingerTappingHeader),
                (Constants.CSV.handTurningFile,      Constants.CSV.handTurningHeader),
                (Constants.CSV.legAgilityFile,       Constants.CSV.legAgilityHeader),
                (Constants.CSV.spiralTracingFile,    Constants.CSV.spiralTracingHeader),
                (Constants.CSV.tmtResultsFile,       Constants.CSV.tmtResultsHeader),
                // Daily profile and questionnaire
                (Constants.CSV.profileFile,          Constants.CSV.profileHeader),
                (Constants.CSV.questionnaireFile,    Constants.CSV.questionnaireHeader),
            ]
            for (filename, header) in files {
                let file = dir.appendingPathComponent(filename)
                if !fm.fileExists(atPath: file.path) {
                    // Write header only — do not overwrite existing data
                    try? header.write(to: file, atomically: true, encoding: .utf8)
                }
            }
        }
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
    /// - Parameters:
    ///   - fingerPathJSON: Array of {x,y,t} touch-point objects (index-referenced path)
    ///   - pathDataJSON:   Same path in absolute-coordinate form for backward compat with Android schema.
    ///                     Pass the same value as `fingerPathJSON` when no separate encoding is available.
    func writeTMTResult(startMs: Int64, endMs: Int64, testType: String,
                        totalMs: Int, wrongTargetErrors: Int, liftOffErrors: Int,
                        segmentTimingsJSON: String,
                        fingerPathJSON: String,
                        pathDataJSON: String? = nil) {
        let escapedSegments   = segmentTimingsJSON.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedFingerPath = fingerPathJSON.replacingOccurrences(of: "\"", with: "\"\"")
        // path_data_json (9th column) defaults to the same as finger_path_json when no separate
        // encoding is provided — matches the Android column schema while keeping the call site simple.
        let escapedPathData   = (pathDataJSON ?? fingerPathJSON).replacingOccurrences(of: "\"", with: "\"\"")
        let row = "\(startMs),\(endMs),\(testType),\(totalMs),\(wrongTargetErrors),\(liftOffErrors),\"\(escapedSegments)\",\"\(escapedFingerPath)\",\"\(escapedPathData)\"\n"
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

    /// Routed through `writeQueue` like every other write here — unlike `appendGaitMetrics`
    /// just below, this one used to write straight from the caller's thread with no
    /// synchronization against concurrent file operations.
    func writeGaitMetrics(csvString: String) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            let file = rootDir.appendingPathComponent("gait_metrics_export.csv")
            try? csvString.write(to: file, atomically: true, encoding: .utf8)
        }
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

    // MARK: - Gaze & Pupil Tracking Writes

    func writeGazeSample(_ sample: GazeSample) {
        append(sample.csvRow, to: todayDir, filename: Constants.CSV.gazeFile,
               header: Constants.CSV.gazeHeader)
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

    // MARK: - Blink Event Writes

    /// Appends one row to blink_log.csv. Schema matches Android exactly:
    /// timestamp_ms, context, left_trough_prob, right_trough_prob, blink_rate_per_min
    func writeBlinkEvent(context: String, leftTroughProb: Double, rightTroughProb: Double, blinkRatePerMin: Double) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let row = "\(timestamp),\(context),\(leftTroughProb),\(rightTroughProb),\(blinkRatePerMin)\n"
        append(row, to: todayDir, filename: Constants.CSV.blinkLogFile,
               header: Constants.CSV.blinkLogHeader)
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
        // Walk recursively so voice/ subdirectory m4a files are included.
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return "0 KB" }
        var totalBytes = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            totalBytes += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    func fileCount(for dateKey: String) -> Int {
        let dir = dateDirectory(for: dateKey)
        // Walk recursively so voice/ subdirectory files are counted.
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        for case let fileURL as URL in enumerator {
            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { count += 1 }
        }
        return count
    }

    func fileList(for dateKey: String) -> [String] {
        let dir = dateDirectory(for: dateKey)
        return (try? fm.contentsOfDirectory(atPath: dir.path).sorted()) ?? []
    }

    func isUploaded(_ dateKey: String) -> Bool {
        fm.fileExists(atPath: dateDirectory(for: dateKey).appendingPathComponent(".uploaded").path)
    }

    func markUploaded(_ dateKey: String) {
        let dir = dateDirectory(for: dateKey)
        let marker = dir.appendingPathComponent(".uploaded")
        // Write metadata so we can audit when/what was uploaded.
        let body = "uploaded_at_ms=\(Int64(Date().timeIntervalSince1970 * 1000))\n"
        try? body.write(to: marker, atomically: true, encoding: .utf8)
        // Remove the in-progress claim marker now that upload is confirmed.
        clearUploadClaim(dateKey)
    }

    // MARK: - Upload Claim Lock (mirrors Android's UploadState)

    private static let staleUploadMs: TimeInterval = 6 * 60 * 60  // 6 hours

    /// Atomically claims the upload slot for `dateKey`.
    /// Returns `true` if this caller won the race and should proceed with uploading.
    /// Returns `false` if another upload is already in progress or complete.
    func tryClaimUpload(_ dateKey: String) -> Bool {
        let dir = dateDirectory(for: dateKey)
        if isUploaded(dateKey) { return false }
        let claimFile = dir.appendingPathComponent(".uploading")
        // If a stale claim exists, clear it so we can re-attempt.
        if fm.fileExists(atPath: claimFile.path),
           let attrs = try? fm.attributesOfItem(atPath: claimFile.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > Self.staleUploadMs {
            try? fm.removeItem(at: claimFile)
        }
        // Bail if a non-stale claim exists from a concurrent upload.
        if fm.fileExists(atPath: claimFile.path) { return false }
        // Create the claim file — this is not atomic on all file systems, but
        // iOS documents directory uses HFS+/APFS where creat() is atomic enough
        // for this purpose (two simultaneous calls from different threads will
        // race, but the worst outcome is one duplicate upload, not corruption).
        let body = "started_at_ms=\(Int64(Date().timeIntervalSince1970 * 1000))\n"
        return (try? body.write(to: claimFile, atomically: true, encoding: .utf8)) != nil
    }

    func clearUploadClaim(_ dateKey: String) {
        let claimFile = dateDirectory(for: dateKey).appendingPathComponent(".uploading")
        try? fm.removeItem(at: claimFile)
    }

    // MARK: - SensorKit Writes

    func writeSensorKitAccelerometerRow(timestampMs: Int64, x: Double, y: Double, z: Double) {
        let row = "\(timestampMs),\(x),\(y),\(z)\n"
        append(row, to: todayDir, filename: Constants.CSV.sensorKitAccelerometerFile, header: Constants.CSV.sensorKitAccelerometerHeader)
    }

    func writeSensorKitRotationRateRow(timestampMs: Int64, x: Double, y: Double, z: Double) {
        let row = "\(timestampMs),\(x),\(y),\(z)\n"
        append(row, to: todayDir, filename: Constants.CSV.sensorKitRotationRateFile, header: Constants.CSV.sensorKitRotationRateHeader)
    }

    func writeSensorKitKeyboardRow(timestampMs: Int64, totalWords: Int, deleteCount: Int, pauseCount: Int, typingSpeed: Double) {
        let row = "\(timestampMs),\(totalWords),\(deleteCount),\(pauseCount),\(typingSpeed),0,0\n"
        append(row, to: todayDir, filename: Constants.CSV.sensorKitKeyboardFile, header: Constants.CSV.sensorKitKeyboardHeader)
    }

    func writeSensorKitDeviceUsageRow(timestampMs: Int64, durationSeconds: TimeInterval, totalUnlocks: Int, unlockDurationSeconds: TimeInterval, webUsageSeconds: TimeInterval) {
        let row = "\(timestampMs),\(durationSeconds),\(totalUnlocks),\(unlockDurationSeconds),\(webUsageSeconds),{}\n"
        append(row, to: todayDir, filename: Constants.CSV.sensorKitDeviceUsageFile, header: Constants.CSV.sensorKitDeviceUsageHeader)
    }

    // MARK: - ZIP

    func zipDate(_ dateKey: String) throws -> URL {
        let sourceDir = dateDirectory(for: dateKey)
        let cacheDir  = fm.temporaryDirectory.appendingPathComponent("PDCollectZips")
        ensureDir(cacheDir)
        let zipURL = cacheDir.appendingPathComponent("\(dateKey)_\(userId).zip")
        if fm.fileExists(atPath: zipURL.path) { try? fm.removeItem(at: zipURL) }

        // Ensure every expected file exists with at least its header row.
        // This is a synchronous pass on the write queue so the files are created
        // before ZIPFoundation reads the directory — preventing gaps in past-date
        // zips for sensor types that were never triggered on a particular day.
        writeQueue.sync { [weak self] in
            guard let self else { return }
            ensureDir(sourceDir)
            let files: [(String, String)] = [
                (Constants.CSV.sensorsFile,          Constants.CSV.sensorsHeader),
                (Constants.CSV.passiveSensorsFile,   Constants.CSV.passiveSensorsHeader),
                (Constants.CSV.touchFile,            Constants.CSV.touchHeader),
                (Constants.CSV.keyEventsFile,        Constants.CSV.keyEventsHeader),
                (Constants.CSV.appsFile,             Constants.CSV.appsHeader),
                (Constants.CSV.faceDistanceFile,     Constants.CSV.faceDistanceHeader),
                (Constants.CSV.gazeFile,             Constants.CSV.gazeHeader),
                (Constants.CSV.medicationFile,       Constants.CSV.medicationHeader),
                (Constants.CSV.physicalActivityFile, Constants.CSV.physicalActivityHeader),
                (Constants.CSV.sleepFile,            Constants.CSV.sleepHeader),
                (Constants.CSV.heartRateFile,        Constants.CSV.heartRateHeader),
                (Constants.CSV.blinkLogFile,         Constants.CSV.blinkLogHeader),
                (Constants.CSV.voiceLogFile,         Constants.CSV.voiceLogHeader),
                (Constants.CSV.gaitMetricsFile,      Constants.CSV.gaitMetricsHeader),
                (Constants.CSV.pedometerFile,        Constants.CSV.pedometerHeader),
                (Constants.CSV.motionActivityFile,   Constants.CSV.motionActivityHeader),
                (Constants.CSV.sensorKitAccelerometerFile, Constants.CSV.sensorKitAccelerometerHeader),
                (Constants.CSV.sensorKitRotationRateFile,  Constants.CSV.sensorKitRotationRateHeader),
                (Constants.CSV.sensorKitKeyboardFile,      Constants.CSV.sensorKitKeyboardHeader),
                (Constants.CSV.sensorKitDeviceUsageFile,   Constants.CSV.sensorKitDeviceUsageHeader),
                (Constants.CSV.beanieTemperatureFile, Constants.CSV.beanieTemperatureHeader),
                (Constants.CSV.beanieImuFile,         Constants.CSV.beanieImuHeader),
                (Constants.CSV.fingerTappingFile,    Constants.CSV.fingerTappingHeader),
                (Constants.CSV.handTurningFile,      Constants.CSV.handTurningHeader),
                (Constants.CSV.legAgilityFile,       Constants.CSV.legAgilityHeader),
                (Constants.CSV.spiralTracingFile,    Constants.CSV.spiralTracingHeader),
                (Constants.CSV.tmtResultsFile,       Constants.CSV.tmtResultsHeader),
                (Constants.CSV.profileFile,          Constants.CSV.profileHeader),
                (Constants.CSV.questionnaireFile,    Constants.CSV.questionnaireHeader),
            ]
            for (filename, header) in files {
                let file = sourceDir.appendingPathComponent(filename)
                if !fm.fileExists(atPath: file.path) {
                    try? header.write(to: file, atomically: true, encoding: .utf8)
                }
            }
        }

        try fm.zipItem(at: sourceDir, to: zipURL)
        return zipURL
    }

    // MARK: - Deletion

    /// Routed through `writeQueue.sync` (same serial queue every `append()` call uses) so
    /// this can't race an in-flight write — without it, deleting a date while a background
    /// sensor write is still queued could unlink the directory out from under `append()`,
    /// which would silently recreate it with a single stray file rather than actually
    /// blocking the delete, or write via a now-invalid `FileHandle`.
    func deleteDate(_ dateKey: String) {
        // Today's directory is actively being appended to (passive sensors, BLE, face
        // distance) — deleting it mid-collection isn't safe even serialized through
        // writeQueue, since a `FileHandle` already open via `appendRaw` would still be
        // writing into an unlinked file. Mirrors the same guard on Android.
        guard dateKey != Date().dateKey else { return }
        writeQueue.sync {
            try? self.fm.removeItem(at: self.dateDirectory(for: dateKey))
        }
    }

    func deleteAllData() {
        writeQueue.sync {
            try? self.fm.removeItem(at: self.userDir())
        }
    }
}