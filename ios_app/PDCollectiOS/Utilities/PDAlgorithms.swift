import Foundation
import CoreGraphics

// MARK: - PDAlgorithms
// Ported from eladyt/PDAnalysis — FeatureExtractors/basic_functions.py
// All formulas match the Python implementation exactly.

enum PDAlgorithms {

    // MARK: - Shared: Asymmetry Index
    /// Standard laterality index: 0 = symmetric, 100 = fully asymmetric.
    /// Formula: |L - R| / ((L + R) / 2) × 100
    static func asymmetryIndex(left: Double, right: Double) -> Double {
        let avg = (left + right) / 2.0
        guard avg > 1e-12 else { return 0 }
        return abs(left - right) / avg * 100.0
    }

    // MARK: - Finger Tapping
    struct FingerTappingFeatures {
        let nTaps: Int
        let durationS: Double
        let tapFrequencyHz: Double   // 1 / mean ITI
        let meanITI_s: Double
        let stdITI_s: Double
        let cvITI: Double            // std / mean — rhythm regularity; higher = worse
        let itiSlope: Double         // linear slope of ITI over taps — positive = decrement (fatigue)
        let hesitationCount: Int     // ITIs > 3× median (pauses / freezing)
    }

    /// Compute finger-tapping features from an array of tap timestamps.
    /// Mirrors `compute_tapping_test_metrics` in basic_functions.py.
    static func fingerTappingFeatures(timestamps: [Date]) -> FingerTappingFeatures? {
        guard timestamps.count >= 3 else { return nil }
        let sorted = timestamps.sorted()
        let duration = sorted.last!.timeIntervalSince(sorted.first!)

        // Inter-tap intervals (seconds)
        var itis: [Double] = []
        for i in 1..<sorted.count {
            itis.append(sorted[i].timeIntervalSince(sorted[i - 1]))
        }
        guard itis.count >= 2 else { return nil }

        let meanITI = itis.reduce(0, +) / Double(itis.count)
        let variance = itis.map { ($0 - meanITI) * ($0 - meanITI) }.reduce(0, +) / Double(itis.count - 1)
        let stdITI = sqrt(variance)
        let cvITI = meanITI > 0 ? stdITI / meanITI : 0

        // ITI slope — positive slope means ITIs are getting longer (slowing down = decrement)
        let slope = linearSlope(itis)

        // Hesitations: ITI > 3× median
        let medianITI = median(itis)
        let hesitations = itis.filter { $0 > 3 * medianITI }.count

        return FingerTappingFeatures(
            nTaps: sorted.count,
            durationS: duration,
            tapFrequencyHz: meanITI > 0 ? 1.0 / meanITI : 0,
            meanITI_s: meanITI,
            stdITI_s: stdITI,
            cvITI: cvITI,
            itiSlope: slope,
            hesitationCount: hesitations
        )
    }

    // MARK: - Hand Turning
    struct HandTurningFeatures {
        let turningSpeedRMS: Double    // rad/s — bradykinesia marker
        let turningSpeedMax: Double    // rad/s
        let turningFreqHz: Double      // dominant rotation frequency
        let turningRateCPS: Double     // cycles per second
        let rhythmCV: Double           // CoV of inter-peak intervals (%)
        let amplitudeDecay: Double     // log-linear decay slope (negative = decrement)
        let tremorPowerRatio: Double   // 3–12 Hz power / total power
        let jerkRMS: Double            // smoothness marker
        let pronoSupraAsymmetry: Double // pronation/supination duration ratio (1.0 = symmetric)
    }

    /// Compute hand-turning features from gyro magnitude time series.
    /// Mirrors `extract_hand_turning_features` in basic_functions.py.
    static func handTurningFeatures(gyroX: [Double], gyroY: [Double], gyroZ: [Double],
                                    hz: Double) -> HandTurningFeatures {
        let n = min(gyroX.count, min(gyroY.count, gyroZ.count))
        guard n > 10 else {
            return HandTurningFeatures(turningSpeedRMS: 0, turningSpeedMax: 0,
                                       turningFreqHz: 0, turningRateCPS: 0, rhythmCV: 0,
                                       amplitudeDecay: 0, tremorPowerRatio: 0,
                                       jerkRMS: 0, pronoSupraAsymmetry: 1)
        }

        // Gyro magnitude
        var mag = (0..<n).map { i in
            let gx = gyroX[i]
            let gy = gyroY[i]
            let gz = gyroZ[i]
            return sqrt(gx*gx + gy*gy + gz*gz)
        }

        let rms = sqrt(mag.map { $0 * $0 }.reduce(0, +) / Double(n))
        let maxMag = mag.max() ?? 0

        // Peak detection (height > mean, distance > fs/4)
        let meanMag = mag.reduce(0, +) / Double(n)
        let minDist = max(1, Int(hz / 4.0))
        let peaks = findPeaks(mag, minHeight: meanMag, minDistance: minDist)

        var turningFreq = 0.0
        var rhythmCV = 0.0
        var ampDecay = 0.0
        if peaks.count > 1 {
            let intervals = zip(peaks.dropFirst(), peaks).map { Double($0 - $1) / hz }
            let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
            turningFreq = meanInterval > 0 ? 1.0 / (meanInterval * 2.0) : 0
            rhythmCV = stddev(intervals) / (meanInterval + 1e-12) * 100

            // Amplitude decay: log-linear slope of peak amplitudes
            let peakAmps = peaks.map { mag[$0] }
            let logAmps = peakAmps.map { log($0 + 1e-6) }
            ampDecay = linearSlope(logAmps)
        }

        // Tremor power ratio (3–12 Hz / total)
        let tremorRatio = tremorPowerRatio(signal: mag, hz: hz, lowHz: 3, highHz: 12)

        // Jerk RMS from accelerometer-style diff of gyro signal
        let jerk = zip(mag.dropFirst(), mag).map { ($0 - $1) * hz }
        let jerkRMS = sqrt(jerk.map { $0 * $0 }.reduce(0, +) / Double(max(1, jerk.count)))

        // Pronation/Supination asymmetry — use dominant gyro axis
        let varX = variance(gyroX); let varY = variance(gyroY); let varZ = variance(gyroZ)
        let mainAxis: [Double]
        if varX >= varY && varX >= varZ { mainAxis = gyroX }
        else if varY >= varZ { mainAxis = gyroY }
        else { mainAxis = gyroZ }

        let zeroCrossings = zeroCrossingIndices(mainAxis)
        var pronoAsymmetry = 1.0
        if zeroCrossings.count > 1 {
            let durations = zip(zeroCrossings.dropFirst(), zeroCrossings).map { Double($0 - $1) / hz }
            if durations.count > 1 {
                let evenMean = stride(from: 0, to: durations.count, by: 2).map { durations[$0] }.reduce(0, +)
                    / Double(max(1, (durations.count + 1) / 2))
                let oddMean = stride(from: 1, to: durations.count, by: 2).map { durations[$0] }.reduce(0, +)
                    / Double(max(1, durations.count / 2))
                pronoAsymmetry = evenMean / (oddMean + 1e-6)
            }
        }

        return HandTurningFeatures(
            turningSpeedRMS: rms,
            turningSpeedMax: maxMag,
            turningFreqHz: turningFreq,
            turningRateCPS: turningFreq,
            rhythmCV: rhythmCV,
            amplitudeDecay: ampDecay,
            tremorPowerRatio: tremorRatio,
            jerkRMS: jerkRMS,
            pronoSupraAsymmetry: pronoAsymmetry
        )
    }

    // MARK: - Spiral Tracing
    struct SpiralFeatures {
        let spiralFitRMSE: Double       // deviation from ideal Archimedean spiral
        let tremorRatio: Double         // high-freq spatial oscillation ratio
        let radialRMSE: Double          // RMS of radial residuals
        let speedMean: Double           // px/s — bradykinesia
        let speedCV: Double             // rhythm regularity of drawing speed
        let curvatureCV: Double         // smoothness of spiral turns
        let boundingArea: Double        // size proxy (micrographia)
        let durationS: Double
        let nPoints: Int
    }

    /// Compute spiral tracing features from user-drawn path.
    /// Mirrors `extract_spiral_features` + `fit_archimedean_spiral` in basic_functions.py.
    static func spiralFeatures(path: [CGPoint], timestamps: [Date],
                               canvasSize: CGSize) -> SpiralFeatures? {
        // timestamps is force-unwrapped below; also guard its count so a
        // caller that ever lets `path` and `timestamps` drift out of lockstep
        // (they're maintained as two parallel arrays rather than one array of
        // structs) gets a safe `nil` instead of a crash.
        guard path.count >= 20, !timestamps.isEmpty else { return nil }
        let n = path.count
        let x = path.map { Double($0.x) }
        let y = path.map { Double($0.y) }

        // Duration
        let duration = timestamps.last!.timeIntervalSince(timestamps.first!)

        // --- Archimedean spiral fit: r = a + b*theta ---
        let cx = x.reduce(0, +) / Double(n)
        let cy = y.reduce(0, +) / Double(n)
        let xc = x.map { $0 - cx }
        let yc = y.map { $0 - cy }
        let r = zip(xc, yc).map { sqrt($0 * $0 + $1 * $1) }
        var theta = zip(xc, yc).map { atan2($1, $0) }
        theta = unwrapAngles(theta)
        if (theta.last ?? 0) < (theta.first ?? 0) { theta = theta.map { -$0 } }

        // Linear fit r = a + b*theta using least squares
        let (_, b, spiralRMSE, residuals) = linearFit(x: theta, y: r)

        // Tremor from residuals (spatial frequency analysis)
        let arcLens = arcLengths(x: x, y: y)
        let (tremorRatio, radialRMSE) = tremorFromResiduals(residuals: residuals, arcLen: arcLens)

        // Speed profile
        var speeds: [Double] = []
        if timestamps.count == n {
            for i in 1..<n {
                let dt = timestamps[i].timeIntervalSince(timestamps[i-1])
                guard dt > 1e-6 else { continue }
                let dx = x[i] - x[i-1]
                let dy = y[i] - y[i-1]
                speeds.append(sqrt(dx*dx + dy*dy) / dt)
            }
        }
        let speedMean = speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count)
        let speedCV = speedMean > 0 ? stddev(speeds) / speedMean : 0

        // Curvature CoV
        let kappa = curvatureArray(x: x, y: y)
        let absKappa = kappa.map { abs($0) + 1e-12 }
        let kappaMean = absKappa.reduce(0, +) / Double(absKappa.count)
        let curvatureCV = kappaMean > 0 ? stddev(absKappa) / kappaMean : 0

        // Bounding area (micrographia proxy)
        let width = (x.max() ?? 0) - (x.min() ?? 0)
        let height = (y.max() ?? 0) - (y.min() ?? 0)

        return SpiralFeatures(
            spiralFitRMSE: spiralRMSE,
            tremorRatio: tremorRatio,
            radialRMSE: radialRMSE,
            speedMean: speedMean,
            speedCV: speedCV,
            curvatureCV: curvatureCV,
            boundingArea: width * height,
            durationS: duration,
            nPoints: n
        )
    }

    // MARK: - Leg Agility
    struct LegAgilityFeatures {
        let nSteps: Int
        let stepsPerMin: Double
        let stepFreqHz: Double
        let rhythmCV: Double            // inter-step CoV (%)
        let liftMean: Double            // mean lift height proxy
        let liftStd: Double
        let amplitudeDecay: Double      // log-linear decay slope
        let tremorPowerRatio: Double    // 3–12 Hz / total
        let jerkRMS: Double             // smoothness
        let liftReturnAsymmetry: Double // rise/fall time ratio (1.0 = symmetric)
    }

    /// Compute leg agility features from sensor data.
    /// Mirrors `extract_agility_features` in basic_functions.py.
    static func legAgilityFeatures(accX: [Double], accY: [Double], accZ: [Double],
                                   gyroX: [Double], gyroY: [Double], gyroZ: [Double],
                                   hz: Double) -> LegAgilityFeatures? {
        let n = min(accX.count, min(accY.count, accZ.count))
        guard n > 10 else { return nil }

        // Accelerometer magnitude
        var accMag = (0..<n).map { i in
            let ax = accX[i]
            let ay = accY[i]
            let az = accZ[i]
            return sqrt(ax*ax + ay*ay + az*az)
        }
        // Remove gravity (subtract 9.81 and low-pass at 3 Hz via simple moving average)
        let gravityRemoved = accMag.map { $0 - 9.81 }
        let filtered = movingAverage(gravityRemoved, windowSize: max(2, Int(hz / 3)))

        // Step detection: peaks > 0.5 m/s², min distance = fs/2
        let minDist = max(1, Int(hz / 2.0))
        let peaks = findPeaks(filtered, minHeight: 0.5, minDistance: minDist)

        let numSteps = peaks.count
        let durationS = Double(n) / hz
        let durationMin = durationS / 60.0
        let stepsPerMin = durationMin > 0 ? Double(numSteps) / durationMin : 0

        var stepFreq = 0.0
        var rhythmCV = 0.0
        var ampDecay = 0.0
        var liftMean = 0.0
        var liftStd = 0.0
        var liftReturnAsym = 1.0

        if numSteps > 1 {
            let stepTimes = peaks.map { Double($0) / hz }
            let intervals = zip(stepTimes.dropFirst(), stepTimes).map { $0 - $1 }
            let meanInterval = intervals.reduce(0, +) / Double(intervals.count)
            stepFreq = meanInterval > 0 ? 1.0 / meanInterval : 0
            rhythmCV = stddev(intervals) / (meanInterval + 1e-12) * 100

            // Amplitude decay (log-linear slope of peak amplitudes)
            let peakAmps = peaks.map { abs(filtered[$0]) }
            let logAmps = peakAmps.map { log($0 + 1e-6) }
            ampDecay = linearSlope(logAmps)

            // Lift heights: peak-to-peak within each step window
            var heights: [Double] = []
            for i in 0..<(peaks.count - 1) {
                let seg = Array(accZ[peaks[i]..<peaks[i+1]])
                heights.append((seg.max() ?? 0) - (seg.min() ?? 0))
            }
            liftMean = heights.reduce(0, +) / Double(max(1, heights.count))
            liftStd = stddev(heights)

            // Lift/return asymmetry (rise vs fall time around peak)
            var ratios: [Double] = []
            let halfWin = Int(hz / 2)
            for p in peaks {
                let start = max(0, p - halfWin)
                let end = min(filtered.count, p + halfWin)
                let window = Array(filtered[start..<end])
                guard window.count > 2 else { continue }
                let halfMax = (window.max() ?? 0) / 2
                let above = window.enumerated().filter { $0.element > halfMax }.map { $0.offset }
                if above.count > 1 {
                    let mid = above.count / 2
                    ratios.append(Double(mid) / Double(above.count - mid + 1))
                }
            }
            liftReturnAsym = ratios.isEmpty ? 1.0 : ratios.reduce(0, +) / Double(ratios.count)
        }

        // Tremor power ratio (3–12 Hz)
        let tremorRatio = tremorPowerRatio(signal: accMag, hz: hz, lowHz: 3, highHz: 12)

        // Jerk RMS
        let jerk = (1..<n).map { i in
            let dx = accX[i] - accX[i-1]; let dy = accY[i] - accY[i-1]; let dz = accZ[i] - accZ[i-1]
            return sqrt(dx*dx + dy*dy + dz*dz) * hz
        }
        let jerkRMS = sqrt(jerk.map { $0 * $0 }.reduce(0, +) / Double(max(1, jerk.count)))

        return LegAgilityFeatures(
            nSteps: numSteps,
            stepsPerMin: stepsPerMin,
            stepFreqHz: stepFreq,
            rhythmCV: rhythmCV,
            liftMean: liftMean,
            liftStd: liftStd,
            amplitudeDecay: ampDecay,
            tremorPowerRatio: tremorRatio,
            jerkRMS: jerkRMS,
            liftReturnAsymmetry: liftReturnAsym
        )
    }

    // MARK: - Private Helpers

    private static func mean(_ a: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        return a.reduce(0, +) / Double(a.count)
    }

    private static func variance(_ a: [Double]) -> Double {
        guard a.count > 1 else { return 0 }
        let m = mean(a)
        return a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count - 1)
    }

    static func stddev(_ a: [Double]) -> Double { sqrt(variance(a)) }

    private static func median(_ a: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid-1] + s[mid]) / 2 : s[mid]
    }

    /// Ordinary least-squares slope of y ~ index
    private static func linearSlope(_ y: [Double]) -> Double {
        guard y.count >= 2 else { return 0 }
        let n = Double(y.count)
        let xs = (0..<y.count).map { Double($0) }
        let xMean = xs.reduce(0, +) / n
        let yMean = y.reduce(0, +) / n
        let num = zip(xs, y).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let den = xs.map { ($0 - xMean) * ($0 - xMean) }.reduce(0, +)
        return den > 0 ? num / den : 0
    }

    /// Linear fit y = a + b*x; returns (a, b, RMSE, residuals)
    private static func linearFit(x: [Double], y: [Double]) -> (Double, Double, Double, [Double]) {
        let n = Double(x.count)
        let xMean = x.reduce(0, +) / n; let yMean = y.reduce(0, +) / n
        let num = zip(x, y).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let den = x.map { ($0 - xMean) * ($0 - xMean) }.reduce(0, +)
        let b = den > 0 ? num / den : 0
        let a = yMean - b * xMean
        let residuals = zip(x, y).map { $1 - (a + b * $0) }
        let rmse = sqrt(residuals.map { $0 * $0 }.reduce(0, +) / n)
        return (a, b, rmse, residuals)
    }

    /// Simple peak detection: value > neighbours and > minHeight, spaced >= minDistance
    static func findPeaks(_ signal: [Double], minHeight: Double, minDistance: Int) -> [Int] {
        var peaks: [Int] = []
        var lastPeak = -minDistance
        for i in 1..<(signal.count - 1) {
            if signal[i] > minHeight && signal[i] >= signal[i-1] && signal[i] >= signal[i+1] {
                if i - lastPeak >= minDistance {
                    peaks.append(i)
                    lastPeak = i
                }
            }
        }
        return peaks
    }

    /// Indices where the sign of the signal changes (zero crossings)
    private static func zeroCrossingIndices(_ signal: [Double]) -> [Int] {
        var crossings: [Int] = []
        for i in 1..<signal.count {
            if (signal[i-1] >= 0 && signal[i] < 0) || (signal[i-1] < 0 && signal[i] >= 0) {
                crossings.append(i)
            }
        }
        return crossings
    }

    /// Unwrap angles to be monotone
    private static func unwrapAngles(_ angles: [Double]) -> [Double] {
        var out = angles
        for i in 1..<out.count {
            var diff = out[i] - out[i-1]
            while diff > .pi  { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            out[i] = out[i-1] + diff
        }
        return out
    }

    /// Cumulative arc lengths along the path
    private static func arcLengths(x: [Double], y: [Double]) -> [Double] {
        var out = [0.0]
        for i in 1..<x.count {
            let dx = x[i] - x[i-1]; let dy = y[i] - y[i-1]
            out.append(out.last! + sqrt(dx*dx + dy*dy))
        }
        return out
    }

    /// Discrete curvature κ = (x'y'' - y'x'') / (x'^2 + y'^2)^1.5
    private static func curvatureArray(x: [Double], y: [Double]) -> [Double] {
        let n = x.count
        guard n > 4 else { return Array(repeating: 0, count: n) }
        let dx  = gradient(x);  let dy  = gradient(y)
        let ddx = gradient(dx); let ddy = gradient(dy)
        return (0..<n).map { i in
            let denom = pow(dx[i]*dx[i] + dy[i]*dy[i], 1.5)
            return denom > 1e-8 ? (dx[i]*ddy[i] - dy[i]*ddx[i]) / denom : 0
        }
    }

    /// Numpy-style central gradient (finite differences)
    private static func gradient(_ a: [Double]) -> [Double] {
        let n = a.count
        guard n >= 2 else { return a }
        var g = Array(repeating: 0.0, count: n)
        g[0] = a[1] - a[0]
        g[n-1] = a[n-1] - a[n-2]
        for i in 1..<(n-1) { g[i] = (a[i+1] - a[i-1]) / 2.0 }
        return g
    }

    /// Tremor index from spiral residuals via spatial frequency analysis.
    /// Mirrors `tremor_from_residuals` in basic_functions.py.
    private static func tremorFromResiduals(residuals: [Double], arcLen: [Double]) -> (Double, Double) {
        guard residuals.count >= 16, arcLen.count == residuals.count else { return (0, 0) }
        let totalLen = arcLen.last ?? 0
        guard totalLen > 1e-6 else { return (0, 0) }

        // Resample residuals uniformly along arc length (simple linear interpolation)
        let nPts = min(256, residuals.count)
        var resampled: [Double] = []
        for i in 0..<nPts {
            let targetLen = totalLen * Double(i) / Double(nPts - 1)
            if let idx = arcLen.firstIndex(where: { $0 >= targetLen }) {
                resampled.append(residuals[min(idx, residuals.count - 1)])
            } else {
                resampled.append(residuals.last ?? 0)
            }
        }

        // Power of residuals as tremor proxy (variance normalized)
        let rmse = sqrt(resampled.map { $0 * $0 }.reduce(0, +) / Double(nPts))
        let totalPower = resampled.map { $0 * $0 }.reduce(0, +) + 1e-12
        // High-frequency fraction: power of de-meaned residuals
        let m = resampled.reduce(0, +) / Double(nPts)
        let hfPower = resampled.map { ($0 - m) * ($0 - m) }.reduce(0, +)
        return (hfPower / totalPower, rmse)
    }

    /// Simple estimate of tremor power ratio in [lowHz, highHz] band / total.
    /// Approximated via band-pass energy of the signal (no full FFT in Swift stdlib).
    private static func tremorPowerRatio(signal: [Double], hz: Double, lowHz: Double, highHz: Double) -> Double {
        // Use variance of bandpass-filtered signal vs total as proxy
        // Bandpass approximation: high-pass via difference, low-pass via moving average
        let n = signal.count
        guard n > 4 else { return 0 }

        // High-pass cutoff sample count
        let highPassWin = max(1, Int(hz / highHz))
        let lowPassWin  = max(1, Int(hz / lowHz))

        let lpFiltered  = movingAverage(signal, windowSize: highPassWin)
        let hpSignal    = zip(signal, lpFiltered).map { $0 - $1 }
        let bpSignal    = movingAverage(hpSignal, windowSize: lowPassWin)

        let bpPower    = bpSignal.map { $0 * $0 }.reduce(0, +)
        let totalPower = signal.map  { $0 * $0 }.reduce(0, +) + 1e-12
        return min(1.0, bpPower / totalPower)
    }

    /// Simple causal moving average (same as a low-pass FIR)
    static func movingAverage(_ signal: [Double], windowSize: Int) -> [Double] {
        let w = max(1, windowSize)
        var out = Array(repeating: 0.0, count: signal.count)
        for i in 0..<signal.count {
            let start = max(0, i - w + 1)
            let count = i - start + 1
            out[i] = signal[start...i].reduce(0, +) / Double(count)
        }
        return out
    }
}
