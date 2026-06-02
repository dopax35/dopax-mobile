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

    // MARK: - Active-test Writes (existing)

    func writeTestResult(_ result: TestResult) {
        append(result.csvRow, to: todayDir, filename: Constants.CSV.testResultsFile,
               header: Constants.CSV.testResultsHeader)
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
