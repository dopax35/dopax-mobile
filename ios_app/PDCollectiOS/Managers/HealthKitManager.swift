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
