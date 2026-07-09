import HealthKit
import Foundation

class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()
    @Published var isAuthorized = false
    @Published var authorizationError: String?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .walkingSpeed,
            .walkingStepLength,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .appleWalkingSteadiness,
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate
        ]
        // Explicitly typed as Set<HKObjectType>: without this annotation Swift
        // infers Set<HKQuantityType> from the initializer below, and then the
        // workoutType() insert a few lines down (HKWorkoutType, a sibling
        // HKObjectType subclass, not a HKQuantityType) fails to compile.
        var types: Set<HKObjectType> = []
        for identifier in identifiers {
            if let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(quantityType)
            }
        }
        // Workout imports (Running/Bike/Swimming/Weight Training/Pilates logs)
        // — a separate read scope from the passive gait metrics above.
        types.insert(HKObjectType.workoutType())
        // Sleep imports — see fetchRecentSleep() below. Requested in the same
        // authorization call as everything else so there's one system
        // prompt, not a separate one the first time the user taps
        // "Import Sleep".
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        return types
    }

    func requestAuthorization() async {
        guard Self.isAvailable else {
            await MainActor.run { authorizationError = "HealthKit is not available on this device." }
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            await MainActor.run { isAuthorized = true }
        } catch {
            await MainActor.run { authorizationError = error.localizedDescription }
        }
    }

    // MARK: - Workout Import

    /// Fetches workouts logged in the last [days] days (Apple Health / Apple
    /// Fitness / any third-party app that writes HKWorkout, e.g. Strava if
    /// the user has that integration enabled on their end) and maps them
    /// onto this app's physical-activity schema.
    func fetchRecentWorkouts(days: Int = 7) async -> [PhysicalActivityEvent] {
        guard Self.isAvailable else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var events: [PhysicalActivityEvent] = []
        for workout in workouts {
            let durationMin = workout.duration / 60.0
            // totalEnergyBurned is the long-established HKWorkout property —
            // used over the newer per-statistic workout API for broader SDK
            // compatibility.
            let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            let avgHeartRate = await averageHeartRate(from: workout.startDate, to: workout.endDate)

            events.append(PhysicalActivityEvent(
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                activityType: PhysicalActivityEvent.mapExternalType(Self.workoutTypeName(workout.workoutActivityType)),
                timeOfDayMs: Int64(workout.startDate.timeIntervalSince1970 * 1000),
                source: "HealthKit",
                durationMin: durationMin,
                calories: calories,
                avgHeartRate: avgHeartRate,
                // Every HKObject carries a stable UUID — used for import dedup.
                externalId: workout.uuid.uuidString
            ))
        }
        return events
    }

    // MARK: - Sleep Import

    /// Fetches sleep sessions logged in the last [days] days — Apple Health,
    /// Apple Watch, or any third-party app that writes sleep-analysis
    /// samples into Health (Garmin Connect, Oura, AutoSleep, etc.) — and
    /// groups the raw per-stage samples HealthKit returns into whole-night
    /// sessions.
    ///
    /// Unlike workouts, HealthKit has no single "sleep session" object — a
    /// night's sleep comes back as many small HKCategorySamples, one per
    /// stage segment (e.g. "asleepDeep 12:15–1:02am"). This groups samples
    /// into one session per night by starting a new session whenever the
    /// gap since the previous sample's end exceeds sessionGapMinutes, which
    /// bridges brief overnight wake periods without merging two genuinely
    /// separate nights together.
    func fetchRecentSleep(days: Int = 14, sessionGapMinutes: Double = 60) async -> [SleepEvent] {
        guard Self.isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return [] }

        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var lastEnd: Date?
        let gapSeconds = sessionGapMinutes * 60

        for sample in samples {
            if let prevEnd = lastEnd, sample.startDate.timeIntervalSince(prevEnd) > gapSeconds {
                sessions.append(current)
                current = []
            }
            current.append(sample)
            lastEnd = max(lastEnd ?? sample.endDate, sample.endDate)
        }
        if !current.isEmpty { sessions.append(current) }

        return sessions.compactMap { group -> SleepEvent? in
            guard let firstStart = group.map(\.startDate).min(),
                  let lastEndDate = group.map(\.endDate).max() else { return nil }

            func minutes(_ value: HKCategoryValueSleepAnalysis) -> Double {
                group.filter { $0.value == value.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60.0 }
            }

            let awakeMin = minutes(.awake)
            let lightMin = minutes(.asleepCore)
            let deepMin = minutes(.asleepDeep)
            let remMin = minutes(.asleepREM)
            let unspecifiedMin = minutes(.asleepUnspecified)
            let inBedMin = minutes(.inBed)
            let totalSleepMin = lightMin + deepMin + remMin + unspecifiedMin
            // Some sources (e.g. simple trackers) only tag "in bed" spans,
            // never granular stages — fall back to the full session span so
            // time-in-bed isn't left at zero for those sources.
            let timeInBedMin = inBedMin > 0 ? inBedMin : lastEndDate.timeIntervalSince(firstStart) / 60.0

            return SleepEvent(
                timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                source: "HealthKit",
                // HealthKit already gives us a human-friendly app name here
                // (e.g. "Garmin Connect", "AutoSleep") — no mapping needed,
                // unlike Health Connect on Android.
                provider: group.first?.sourceRevision.source.name,
                sleepStartMs: Int64(firstStart.timeIntervalSince1970 * 1000),
                sleepEndMs: Int64(lastEndDate.timeIntervalSince1970 * 1000),
                timeInBedMin: timeInBedMin,
                totalSleepMin: totalSleepMin,
                lightMin: lightMin,
                deepMin: deepMin,
                remMin: remMin,
                awakeMin: awakeMin,
                unspecifiedMin: unspecifiedMin,
                // Every HKObject carries a stable UUID; the first sample's
                // works fine as the session's dedup key as long as the
                // source doesn't rewrite its samples on a later sync.
                externalId: group.first?.uuid.uuidString
            )
        }
    }

    private func averageHeartRate(from start: Date, to end: Date) async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                      return "running"
        case .cycling:                       return "cycling"
        case .swimming:                      return "swimming"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:    return "weight training"
        case .yoga, .pilates, .flexibility:  return "pilates"
        default:                             return "other"
        }
    }

    func fetchGaitMetrics(days: Int = 30) async -> [GaitMetric] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let unit = { (id: HKQuantityTypeIdentifier) -> HKUnit in
            switch id {
            case .walkingSpeed:              return HKUnit.meter().unitDivided(by: .second())
            case .walkingStepLength:         return .meter()
            case .walkingAsymmetryPercentage,
                 .walkingDoubleSupportPercentage: return .percent()
            case .appleWalkingSteadiness:   return .percent()
            case .heartRate:                return HKUnit.count().unitDivided(by: .minute())
            case .heartRateVariabilitySDNN: return HKUnit.secondUnit(with: .milli)
            default:                        return .count()
            }
        }

        async let speeds         = fetchDailyAverage(.walkingSpeed,              unit: unit(.walkingSpeed),              start: start, end: end)
        async let lengths        = fetchDailyAverage(.walkingStepLength,          unit: unit(.walkingStepLength),          start: start, end: end)
        async let steadiness     = fetchDailyAverage(.appleWalkingSteadiness,    unit: unit(.appleWalkingSteadiness),   start: start, end: end)
        async let doubleSupport  = fetchDailyAverage(.walkingDoubleSupportPercentage, unit: unit(.walkingDoubleSupportPercentage), start: start, end: end)
        async let asymmetry      = fetchDailyAverage(.walkingAsymmetryPercentage, unit: unit(.walkingAsymmetryPercentage), start: start, end: end)
        async let heartRates     = fetchDailyAverage(.heartRate,                 unit: unit(.heartRate),                start: start, end: end)
        async let hrv            = fetchDailyAverage(.heartRateVariabilitySDNN,  unit: unit(.heartRateVariabilitySDNN), start: start, end: end)

        let (s, l, st, ds, as_, hr, h) = await (speeds, lengths, steadiness, doubleSupport, asymmetry, heartRates, hrv)

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let allDates = Set([s, l, st, ds, as_, hr, h].flatMap { $0.keys })

        return allDates.compactMap { dateStr -> GaitMetric? in
            guard let date = fmt.date(from: dateStr) else { return nil }
            return GaitMetric(
                date: date,
                walkingSpeed: s[dateStr],
                stepLength: l[dateStr],
                walkingSteadiness: st[dateStr],
                doubleSupportPercentage: ds[dateStr],
                asymmetryPercentage: as_[dateStr],
                heartRate: hr[dateStr],
                hrvSDNN: h[dateStr]
            )
        }.sorted { $0.date < $1.date }
    }

    private func fetchDailyAverage(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [:] }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .discreteAverage,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            query.initialResultsHandler = { _, results, _ in
                var data: [String: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity() {
                        data[fmt.string(from: stats.startDate)] = avg.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    func csvString(for metrics: [GaitMetric]) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var csv = Constants.CSV.gaitMetricsHeader
        // en_US_POSIX: force "." decimals regardless of device region — a
        // comma-decimal locale would otherwise split these CSV rows into
        // extra columns. See the same note in PhysicalActivityEvent.csvRow.
        let posix = Locale(identifier: "en_US_POSIX")
        for m in metrics {
            func f(_ v: Double?) -> String { v.map { String(format: "%.4f", locale: posix, $0) } ?? "" }
            csv += "\(fmt.string(from: m.date)),\(f(m.walkingSpeed)),\(f(m.stepLength)),"
                 + "\(f(m.walkingSteadiness)),\(f(m.doubleSupportPercentage)),\(f(m.asymmetryPercentage)),"
                 + "\(f(m.heartRate)),\(f(m.hrvSDNN))\n"
        }
        return csv
    }
}
