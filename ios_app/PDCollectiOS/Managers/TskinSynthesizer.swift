import Foundation

/// TskinSynthesizer — warmup-aware temperature smoothing/prediction.
///
/// Swift port of Android's TskinSynthesizer.kt (itself already a port of this
/// same iOS reference project's EnvInference.swift TskinSynthesizer class, at
/// the time this app's iOS side had no synthesizer wired in at all). Kept
/// parameter-for-parameter identical to the Android port so both platforms
/// synthesize the same tSkin for the ML model's temp_input given the same
/// innerC/outerC stream — this app uses TskinSynthesizer (not the reference
/// project's newer ThermalEngine) on both platforms for that consistency.
///
/// Provides:
///  - Classic lowpass filtering with asymmetric rate limiting
///  - Not-worn / put-on detection
///  - Warmup tracking with slope boost
///  - Robust (MAD-based) outlier clamping
///  - Smooth handoff blending between warmup prediction and classic smoothing
///    (the displayC/displayValid/isThermalizing fields — not currently surfaced
///    in any UI, but computed for parity; only synthC is consumed today, as the
///    model's tSkin input).

// MARK: - Small numeric helpers

private func clampD(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

private func median(_ xs: [Double]) -> Double {
    if xs.isEmpty { return .nan }
    let sorted = xs.sorted()
    let n = sorted.count
    return n % 2 == 1 ? sorted[n / 2] : 0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
}

private func mad(_ xs: [Double], about: Double) -> Double {
    if xs.isEmpty { return 0.0 }
    return median(xs.map { abs($0 - about) })
}

// MARK: - EMAFilter

final class EMAFilter {
    private var y: Double?
    private var lastT: Date?

    func reset() { y = nil; lastT = nil }

    @discardableResult
    func update(time: Date, x: Double, tau: Double) -> Double {
        guard let yPrev = y, let last = lastT else {
            y = x; lastT = time
            return x
        }
        let dt = max(0.001, time.timeIntervalSince(last))
        let alpha = dt / (tau + dt)
        let newY = yPrev + alpha * (x - yPrev)
        y = newY
        lastT = time
        return newY
    }
}

// MARK: - AsymRateLimiter

final class AsymRateLimiter {
    private(set) var y: Double?

    func reset() { y = nil }

    @discardableResult
    func update(_ x: Double, dt: Double, upCPerMin: Double, downCPerMin: Double) -> Double {
        guard let yPrev = y else {
            y = x
            return x
        }
        let dtClamped = max(0.001, dt)
        let upStep = (upCPerMin / 60.0) * dtClamped
        let dnStep = (downCPerMin / 60.0) * dtClamped
        let out = clampD(x, yPrev - dnStep, yPrev + upStep)
        y = out
        return out
    }
}

// MARK: - RollingWindow

final class RollingWindow {
    private let windowSec: Double
    private let maxN: Int
    private var t: [Date] = []
    private var x: [Double] = []

    init(windowSec: Double, maxN: Int = 400) {
        self.windowSec = windowSec
        self.maxN = maxN
    }

    func reset() { t.removeAll(); x.removeAll() }

    func push(time: Date, value: Double) {
        let cutoff = time.addingTimeInterval(-windowSec)
        while let first = t.first, first < cutoff {
            t.removeFirst(); x.removeFirst()
        }
        t.append(time)
        x.append(value)
        if t.count > maxN {
            let overflow = t.count - maxN
            t.removeFirst(overflow)
            x.removeFirst(overflow)
        }
    }

    func std() -> Double {
        if x.count < 8 { return 0.0 }
        let m = x.reduce(0, +) / Double(x.count)
        let v = x.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return sqrt(v)
    }

    func slopeOver(seconds: Double, now: Date) -> Double {
        if x.count < 2 { return 0.0 }
        let cutoff = now.addingTimeInterval(-seconds)
        var idx = 0
        while idx < t.count && t[idx] < cutoff { idx += 1 }
        if idx >= t.count { return 0.0 }
        let dt = max(0.001, now.timeIntervalSince(t[idx]))
        return (x.last! - x[idx]) / dt
    }
}

// MARK: - RobustClamper

struct RobustClamperConfig {
    var windowSeconds: Double = 25.0
    var kMAD: Double = 8.0
    var minJumpC: Double = 1.0
    var persistSeconds: Double = 12.0
    var maxWindowSamples: Int = 200
}

struct RobustClamperResult {
    let raw: Double
    let clamped: Double
    let wasClamped: Bool
    let isOutlier: Bool
    let outlierRunSeconds: Double
}

final class RobustClamper {
    private let cfg: RobustClamperConfig
    private var bufT: [Date] = []
    private var bufX: [Double] = []
    private var outlierRunStart: Date?

    init(_ cfg: RobustClamperConfig = RobustClamperConfig()) {
        self.cfg = cfg
    }

    func reset() { bufT.removeAll(); bufX.removeAll(); outlierRunStart = nil }

    func update(time: Date, xRaw: Double) -> RobustClamperResult {
        prune(cutoff: time.addingTimeInterval(-cfg.windowSeconds))

        let windowVals = bufX.filter { $0.isFinite }
        let med = median(windowVals)
        let madVal = mad(windowVals, about: med)
        let scale = madVal.isFinite ? (1.4826 * madVal) : 0.0
        let thr = max(cfg.minJumpC, cfg.kMAD * scale)

        let isOutlier = med.isFinite && windowVals.count >= 7 && abs(xRaw - med) > thr

        if isOutlier {
            if outlierRunStart == nil { outlierRunStart = time }
        } else {
            outlierRunStart = nil
        }

        let runSeconds = outlierRunStart.map { time.timeIntervalSince($0) } ?? 0.0
        let shouldEscape = runSeconds >= cfg.persistSeconds

        let clamped: Double
        let wasClamped: Bool
        if isOutlier && !shouldEscape {
            clamped = med
            wasClamped = true
        } else {
            clamped = xRaw
            wasClamped = false
        }

        bufT.append(time)
        bufX.append(clamped)
        if bufT.count > cfg.maxWindowSamples {
            let overflow = bufT.count - cfg.maxWindowSamples
            bufT.removeFirst(overflow)
            bufX.removeFirst(overflow)
        }

        return RobustClamperResult(
            raw: xRaw, clamped: clamped, wasClamped: wasClamped,
            isOutlier: isOutlier, outlierRunSeconds: runSeconds
        )
    }

    private func prune(cutoff: Date) {
        while let first = bufT.first, first < cutoff {
            bufT.removeFirst(); bufX.removeFirst()
        }
    }
}

// MARK: - TskinOutput

struct TskinOutput {
    let rawModel: Double
    let safeLowpass: Double
    let predictedStable: Double?
    let confidence: Double
    let synthC: Double
    let displayValid: Bool
    let displayC: Double?
    let isThermalizing: Bool
}

// MARK: - TskinSynthesizer

final class TskinSynthesizer {
    // Physiological bounds
    private let physLo = 30.0
    private let physHi = 39.5

    // Not-worn detection
    private let notWornBelowTemp = 30.0
    private let notWornDeltaMax = 0.2
    private let notWornMaxSlopeCPerMin = 0.5

    // Put-on detection
    private let plateauNeedSec = 45.0
    private let putOnFastRiseC = 2.5
    private let putOnConfirmRiseC = 4.0
    private let putOnMinSlopeCPerSec = 0.02
    private let putOnMinDeltaAfterOn = 0.35

    // Warmup timing
    private let hideFirstSec = 60.0
    private let predictorEndSec = 180.0
    private let handoffBlendSec = 25.0

    // Classic smoothing parameters
    private let classicTau = 15.0
    private let classicUpCPerMin = 8.0
    private let classicDownCPerMin = 5.0

    // Warm tracking parameters
    private let warmInputTau = 4.0
    private let warmTrackUpCPerMin = 28.0
    private let warmTrackDownCPerMin = 6.0
    private let warmTrackTau = 8.0

    // Slope boost parameters
    private let slopeWinSec = 25.0
    private let slopeClamp = 0.05
    private let boostTau = 95.0
    private let maxBoost = 2.2

    // Display rate limiting
    private let displayUpCPerMin = 12.0
    private let displayDownCPerMin = 10.0

    // Filters and state
    private let detInner = EMAFilter()
    private let detOuter = EMAFilter()
    private let detDelta = EMAFilter()
    private let classicLP = EMAFilter()
    private let classicLimiter = AsymRateLimiter()

    private let warmInputLP = EMAFilter()
    private let warmTrackLimiter = AsymRateLimiter()
    private let warmTrackLP = EMAFilter()
    private let displayLimiter = AsymRateLimiter()

    private let classicClamper: RobustClamper
    private let warmClamper: RobustClamper

    private let classicWin = RollingWindow(windowSec: 30.0, maxN: 300)
    private let warmTrackWin = RollingWindow(windowSec: 40.0, maxN: 400)

    private var plateauSec = 0.0
    private var plateauInnerBuf: [Double] = []
    private let plateauBufMaxN = 180
    private var putOnOnset: Date?
    private var putOnConfirm: Date?
    private var isThermal = false
    private var lastDetTime: Date?
    private var lastDetInner: Double?
    private var lastDetOuter: Double?

    private struct RecentSample { let t: Date; let i: Double; let o: Double; let d: Double }
    private var recent: [RecentSample] = []
    private let recentWinSec = 25.0

    init() {
        classicClamper = RobustClamper(RobustClamperConfig(
            windowSeconds: 20.0, kMAD: 6.0, minJumpC: 0.9, persistSeconds: 12.0, maxWindowSamples: 250
        ))
        warmClamper = RobustClamper(RobustClamperConfig(
            windowSeconds: 15.0, kMAD: 6.0, minJumpC: 0.8, persistSeconds: 8.0, maxWindowSamples: 250
        ))
    }

    func reset() {
        detInner.reset(); detOuter.reset(); detDelta.reset()
        classicLP.reset(); classicLimiter.reset(); classicClamper.reset()

        warmInputLP.reset(); warmTrackLimiter.reset(); warmTrackLP.reset()
        warmClamper.reset(); warmTrackWin.reset(); displayLimiter.reset()

        classicWin.reset()

        plateauSec = 0.0
        plateauInnerBuf.removeAll()
        putOnOnset = nil
        putOnConfirm = nil
        isThermal = false
        lastDetTime = nil
        lastDetInner = nil
        lastDetOuter = nil
        recent.removeAll()
    }

    func update(time: Date, innerC: Double, outerC: Double, dt: Double, c1: Double) -> TskinOutput {
        let rawModel = innerC + c1 * (innerC - outerC)
        let dtC = clampD(dt, 0.001, 30.0)

        // Detection filtering
        let iSm = detInner.update(time: time, x: innerC, tau: 3.0)
        let oSm = detOuter.update(time: time, x: outerC, tau: 3.0)
        let dSm = detDelta.update(time: time, x: innerC - outerC, tau: 4.0)

        // Derivative calculation
        var dInner = 0.0
        var dOuter = 0.0
        if let lastT = lastDetTime, let lastI = lastDetInner, let lastO = lastDetOuter {
            let dtDet = max(0.001, time.timeIntervalSince(lastT))
            dInner = (iSm - lastI) / dtDet
            dOuter = (oSm - lastO) / dtDet
        }
        lastDetTime = time
        lastDetInner = iSm
        lastDetOuter = oSm

        // Recent sample tracking
        recent.append(RecentSample(t: time, i: iSm, o: oSm, d: dSm))
        let cutoff = time.addingTimeInterval(-recentWinSec)
        while let first = recent.first, first.t < cutoff {
            recent.removeFirst()
        }
        if recent.count > 200 {
            recent.removeFirst()
        }

        // Not-worn detection
        let belowTemp = (iSm < notWornBelowTemp) && (oSm < notWornBelowTemp)
        let smallDelta = abs(dSm) < notWornDeltaMax
        let slowChange = abs(dInner) < notWornMaxSlopeCPerMin / 60.0 && abs(dOuter) < notWornMaxSlopeCPerMin / 60.0
        let notWornCandidate = belowTemp && smallDelta && slowChange

        // Plateau tracking for put-on detection
        if notWornCandidate {
            plateauSec += dtC
            plateauInnerBuf.append(iSm)
            if plateauInnerBuf.count > plateauBufMaxN {
                plateauInnerBuf.removeFirst()
            }
        } else {
            plateauSec = 0.0
            plateauInnerBuf.removeAll()
        }

        // Exit thermal state if not worn
        if isThermal && notWornCandidate {
            isThermal = false
            putOnOnset = nil
            putOnConfirm = nil
            warmTrackWin.reset()
            displayLimiter.reset()
        }

        let isWorn = !notWornCandidate

        // Classic smoothing pipeline
        let classicInput = isWorn ? clampD(rawModel, physLo, physHi) : rawModel
        let classicClampRes = classicClamper.update(time: time, xRaw: classicInput)
        let classicLPv = classicLP.update(time: time, x: classicClampRes.clamped, tau: classicTau)
        let classicSmoothed = classicLimiter.update(
            classicLPv, dt: dtC, upCPerMin: classicUpCPerMin, downCPerMin: classicDownCPerMin
        )

        classicWin.push(time: time, value: classicSmoothed)
        let classicStd = classicWin.std()
        let classicSlope = classicWin.slopeOver(seconds: 20.0, now: time)
        let isStableNow = classicStd.isFinite && classicStd < 0.12 && abs(classicSlope) < 0.005

        // Put-on detection
        if !isThermal && plateauSec >= plateauNeedSec {
            let baseline = plateauInnerBuf.isEmpty
                ? iSm
                : plateauInnerBuf.reduce(0, +) / Double(max(1, plateauInnerBuf.count))
            let rise = iSm - baseline
            let deltaOK = abs(dSm) >= putOnMinDeltaAfterOn

            if rise >= putOnFastRiseC ||
                (rise >= putOnConfirmRiseC && deltaOK) ||
                (dInner >= putOnMinSlopeCPerSec && rise >= 1.5 && deltaOK) {
                putOnConfirm = time
                putOnOnset = backdateOnset(confirmTime: time)
                isThermal = true
                plateauSec = 0.0
                plateauInnerBuf.removeAll()

                warmInputLP.reset()
                warmTrackLimiter.reset()
                warmTrackLP.reset()
                warmClamper.reset()
                warmTrackWin.reset()
                displayLimiter.reset()
            }
        }

        // Warm tracking with slope boost
        var predictedStable: Double?
        var conf = 0.0
        var warmTargetForDisplay: Double?

        if isThermal, let confirm = putOnConfirm {
            let age = time.timeIntervalSince(confirm)

            let warmInput = warmInputLP.update(time: time, x: clampD(rawModel, 20.0, physHi), tau: warmInputTau)
            let warmClamp = warmClamper.update(time: time, xRaw: warmInput).clamped
            let warmTrack = warmTrackLimiter.update(
                warmClamp, dt: dtC, upCPerMin: warmTrackUpCPerMin, downCPerMin: warmTrackDownCPerMin
            )
            let warmTrackSm = warmTrackLP.update(time: time, x: warmTrack, tau: warmTrackTau)

            warmTrackWin.push(time: time, value: warmTrackSm)

            let slope = max(0.0, min(slopeClamp, warmTrackWin.slopeOver(seconds: slopeWinSec, now: time)))
            let boost = min(maxBoost, boostTau * slope)
            let pred = clampD(warmTrackSm + boost, 20.0, physHi)
            predictedStable = pred
            conf = isStableNow ? 0.85 : 0.45

            let overshootMax: Double
            if age < 120 { overshootMax = 1.0 }
            else if age < 180 { overshootMax = 0.6 }
            else { overshootMax = 0.35 }

            let overshootAdj = isStableNow ? min(overshootMax, 0.25) : overshootMax
            let predCapped = min(pred, classicSmoothed + overshootAdj)
            let predFloored = max(predCapped, classicSmoothed - 0.10)
            let warmTarget = isStableNow ? (0.88 * classicSmoothed + 0.12 * predFloored) : predFloored
            warmTargetForDisplay = warmTarget
        }

        let synthC = isWorn ? classicSmoothed : rawModel

        if !isWorn {
            return TskinOutput(
                rawModel: rawModel,
                safeLowpass: classicSmoothed,
                predictedStable: nil,
                confidence: 0.0,
                synthC: synthC,
                displayValid: false,
                displayC: nil,
                isThermalizing: false
            )
        }

        // Display output calculation
        var displayValid = true
        var displayC: Double?
        var isThermalizing: Bool

        if isThermal, let confirm = putOnConfirm {
            isThermalizing = true
            let age = time.timeIntervalSince(confirm)

            if age < hideFirstSec {
                displayValid = false
                displayC = nil
            } else {
                let warmTarget = warmTargetForDisplay ?? classicSmoothed
                let target: Double
                if age < predictorEndSec {
                    target = warmTarget
                } else {
                    let w = clampD((age - predictorEndSec) / handoffBlendSec, 0.0, 1.0)
                    target = (1.0 - w) * warmTarget + w * classicSmoothed
                    if w >= 1.0 {
                        isThermalizing = false
                    }
                }

                if displayLimiter.y == nil {
                    displayLimiter.update(target, dt: dtC, upCPerMin: 999.0, downCPerMin: 999.0)
                    displayC = target
                } else {
                    displayC = displayLimiter.update(
                        target, dt: dtC, upCPerMin: displayUpCPerMin, downCPerMin: displayDownCPerMin
                    )
                }
            }
        } else {
            displayLimiter.reset()
            isThermalizing = false
            displayC = classicSmoothed
        }

        return TskinOutput(
            rawModel: rawModel,
            safeLowpass: classicSmoothed,
            predictedStable: predictedStable,
            confidence: conf,
            synthC: synthC,
            displayValid: displayValid,
            displayC: displayC,
            isThermalizing: isThermalizing
        )
    }

    private func backdateOnset(confirmTime: Date) -> Date {
        if recent.count < 2 { return confirmTime }
        let baseInner = recent.first!.i
        for sample in recent.reversed() {
            if sample.i - baseInner < 0.3 {
                return sample.t
            }
        }
        return recent.last!.t
    }
}
