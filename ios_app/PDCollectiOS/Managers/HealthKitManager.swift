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
            .stepLength,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .appleWalkingSteadiness,
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate
        ]
        return Set(identifiers.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
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

    func fetchGaitMetrics(days: Int = 30) async -> [GaitMetric] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let unit = { (id: HKQuantityTypeIdentifier) -> HKUnit in
            switch id {
            case .walkingSpeed:              return HKUnit.meter().unitDivided(by: .second())
            case .stepLength:               return .meter()
            case .walkingAsymmetryPercentage,
                 .walkingDoubleSupportPercentage: return .percent()
            case .appleWalkingSteadiness:   return .percent()
            case .heartRate:                return HKUnit.count().unitDivided(by: .minute())
            case .heartRateVariabilitySDNN: return HKUnit.secondUnit(with: .milli)
            default:                        return .count()
            }
        }

        async let speeds         = fetchDailyAverage(.walkingSpeed,              unit: unit(.walkingSpeed),              start: start, end: end)
        async let lengths        = fetchDailyAverage(.stepLength,                unit: unit(.stepLength),               start: start, end: end)
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
        for m in metrics {
            func f(_ v: Double?) -> String { v.map { String(format: "%.4f", $0) } ?? "" }
            csv += "\(fmt.string(from: m.date)),\(f(m.walkingSpeed)),\(f(m.stepLength)),"
                 + "\(f(m.walkingSteadiness)),\(f(m.doubleSupportPercentage)),\(f(m.asymmetryPercentage)),"
                 + "\(f(m.heartRate)),\(f(m.hrvSDNN))\n"
        }
        return csv
    }
}
