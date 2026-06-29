import Foundation

/// Parses raw BLE data frames from a Beanie temperature/IMU sensor.
/// Handles stream reassembly, temperature conversion, IMU scaling, and battery parsing.
class BeaniePacketParser {

    // MARK: - Types

    struct TemperatureSample {
        let innerC: Double
        let outerC: Double
        let tskinC: Double
        let heatFluxCalPerSec: Double
    }

    struct IMUSample {
        let axRaw: Int16, ayRaw: Int16, azRaw: Int16
        let gxRaw: Int16, gyRaw: Int16, gzRaw: Int16
        let axG: Double, ayG: Double, azG: Double
        let accelMagG: Double
        let gxDps: Double, gyDps: Double, gzDps: Double
        let gyroMagDps: Double
        let timestamp: Int64  // ms
    }

    enum ParsedFrame {
        case temperature(TemperatureSample)
        case imu([IMUSample])
        case battery(Int)  // percentage 0-100
    }

    // MARK: - Constants

    private static let tagBattery: UInt8 = 0xA0
    private static let tagTemperature: UInt8 = 0xA6
    private static let imuHeader1: UInt8 = 0xAA
    private static let imuHeader2: UInt8 = 0x55

    private static let accelScale: Double = 4096.0   // ±8g
    private static let gyroScale: Double = 16.384     // ±2000 dps
    private static let imuSampleBytes = 12            // 6 × int16
    private static let imuSampleIntervalMs: Int64 = 40 // 25 Hz

    // MARK: - State

    private var profile: BeanieProfile
    private var streamBuffer = Data()
    private static let maxBufferSize = 4096

    // Guard filter state for temperature
    private var lastInnerC: Double?
    private var lastOuterC: Double?

    init(profile: BeanieProfile) {
        self.profile = profile
    }

    func updateProfile(_ profile: BeanieProfile) {
        self.profile = profile
    }

    func resetBuffer() {
        streamBuffer.removeAll()
    }

    // MARK: - Stream Processing

    /// Feed raw BLE notification/indication data into the parser.
    /// Returns all complete frames found.
    func processData(_ data: Data) -> [ParsedFrame] {
        streamBuffer.append(data)

        // Prevent unbounded growth
        if streamBuffer.count > Self.maxBufferSize {
            streamBuffer.removeFirst(streamBuffer.count - Self.maxBufferSize)
        }

        var frames: [ParsedFrame] = []

        while !streamBuffer.isEmpty {
            guard let first = streamBuffer.first else { break }

            switch first {
            case Self.tagBattery:
                // Battery: 0xA0 + 2 bytes
                guard streamBuffer.count >= 3 else { return frames }
                let batteryData = Array(streamBuffer.prefix(3))
                streamBuffer.removeFirst(3)
                if let pct = parseBattery(batteryData) {
                    frames.append(.battery(pct))
                }

            case Self.tagTemperature:
                // Tagged temperature: 0xA6 + 4 bytes
                guard streamBuffer.count >= 5 else { return frames }
                let tempData = Array(streamBuffer.prefix(5))
                streamBuffer.removeFirst(5)
                if let sample = parseTaggedTemperature(tempData) {
                    frames.append(.temperature(sample))
                }

            case Self.imuHeader1:
                // IMU: 0xAA 0x55 ...
                guard streamBuffer.count >= 2 else { return frames }
                if streamBuffer[streamBuffer.startIndex + 1] != Self.imuHeader2 {
                    streamBuffer.removeFirst(1)
                    continue
                }

                // Check for stream format: 0xAA 0x55 0x01 0xF0 0x00 + 20×12 bytes = 245 total
                if streamBuffer.count >= 5 &&
                   streamBuffer[streamBuffer.startIndex + 2] == 0x01 &&
                   streamBuffer[streamBuffer.startIndex + 3] == 0xF0 &&
                   streamBuffer[streamBuffer.startIndex + 4] == 0x00 {
                    let totalSize = 5 + 20 * Self.imuSampleBytes  // 245
                    guard streamBuffer.count >= totalSize else { return frames }
                    let imuData = Array(streamBuffer.prefix(totalSize))
                    streamBuffer.removeFirst(totalSize)
                    let samples = parseIMU(imuData, headerSize: 5, maxSamples: 20)
                    if !samples.isEmpty {
                        frames.append(.imu(samples))
                    }
                } else {
                    // Legacy format: 0xAA 0x55 + 15×12 bytes = 182 total
                    let totalSize = 2 + 15 * Self.imuSampleBytes  // 182
                    guard streamBuffer.count >= totalSize else { return frames }
                    let imuData = Array(streamBuffer.prefix(totalSize))
                    streamBuffer.removeFirst(totalSize)
                    let samples = parseIMU(imuData, headerSize: 2, maxSamples: 15)
                    if !samples.isEmpty {
                        frames.append(.imu(samples))
                    }
                }

            default:
                // Try legacy untagged temperature (4 bytes)
                if streamBuffer.count >= 4 {
                    let tempData = Array(streamBuffer.prefix(4))
                    if let sample = parseLegacyTemperature(tempData) {
                        streamBuffer.removeFirst(4)
                        frames.append(.temperature(sample))
                    } else {
                        // Unknown byte, skip
                        streamBuffer.removeFirst(1)
                    }
                } else {
                    return frames
                }
            }
        }

        return frames
    }

    // MARK: - Battery Parsing

    /// Parse battery frame: 0xA0 + uint16 LE ADC value
    private func parseBattery(_ data: [UInt8]) -> Int? {
        guard data.count >= 3, data[0] == Self.tagBattery else { return nil }
        let ain = Int(data[1]) | (Int(data[2]) << 8)

        let pctBase: Double
        if ain > 2954 {
            pctBase = 100.0
        } else if ain > 2500 {
            let x = Double(ain)
            pctBase = -0.0001 * x * x + 0.6279 * x - 845.21
        } else {
            pctBase = Double(ain) * 0.04
        }

        let finalPct = 1.7248 * pctBase - 72.476
        return max(0, min(100, Int(finalPct.rounded())))
    }

    // MARK: - Temperature Parsing

    /// Parse tagged temperature: 0xA6 + 4 data bytes (2× uint16 LE)
    private func parseTaggedTemperature(_ data: [UInt8]) -> TemperatureSample? {
        guard data.count >= 5, data[0] == Self.tagTemperature else { return nil }
        let innerRaw = Int16(bitPattern: UInt16(data[1]) | (UInt16(data[2]) << 8))
        let outerRaw = Int16(bitPattern: UInt16(data[3]) | (UInt16(data[4]) << 8))
        return convertTemperature(innerRaw: innerRaw, outerRaw: outerRaw)
    }

    /// Parse legacy untagged temperature: 4 bytes (2× uint16 LE), validated by range check
    private func parseLegacyTemperature(_ data: [UInt8]) -> TemperatureSample? {
        guard data.count >= 4 else { return nil }
        let innerRaw = Int16(bitPattern: UInt16(data[0]) | (UInt16(data[1]) << 8))
        let outerRaw = Int16(bitPattern: UInt16(data[2]) | (UInt16(data[3]) << 8))

        // Heuristic: check if values produce plausible temperatures
        let innerC = Double(innerRaw) / 128.0
        let outerC = Double(outerRaw) / 128.0
        guard innerC > -20 && innerC < 80 && outerC > -20 && outerC < 80 else {
            return nil
        }

        return convertTemperature(innerRaw: innerRaw, outerRaw: outerRaw)
    }

    private func convertTemperature(innerRaw: Int16, outerRaw: Int16) -> TemperatureSample? {
        var innerC = Double(innerRaw) / 128.0
        var outerC = Double(outerRaw) / 128.0

        // Try legacy scaling if primary looks wrong
        if innerC < -5 || innerC > 60 || outerC < -15 || outerC > 60 {
            innerC = Double(innerRaw) / 16.0
            outerC = Double(outerRaw) / 16.0
        }

        // Validity range check
        guard innerC > -5 && innerC < 60 && outerC > -15 && outerC < 60 else {
            return nil
        }

        // Swap sensors if profile requires it
        if profile.needsSensorSwap {
            swap(&innerC, &outerC)
        }

        // Guard filter: reject large jumps
        if let lastInner = lastInnerC, let lastOuter = lastOuterC {
            let innerDelta = abs(innerC - lastInner)
            let outerDelta = abs(outerC - lastOuter)
            if innerDelta > 5 && outerDelta > 5 {
                return nil  // Both jumped — likely noise
            }
            if innerDelta > 3 && outerDelta < 0.5 {
                return nil  // One jumped while other stable
            }
            if outerDelta > 3 && innerDelta < 0.5 {
                return nil
            }
        }

        lastInnerC = innerC
        lastOuterC = outerC

        // Calculate derived values
        let deltaT = innerC - outerC
        let tskinC = innerC + profile.c1 * deltaT
        let heatFluxCalPerSec = profile.heatFluxK * deltaT * 1000.0

        return TemperatureSample(
            innerC: innerC,
            outerC: outerC,
            tskinC: tskinC,
            heatFluxCalPerSec: heatFluxCalPerSec
        )
    }

    // MARK: - IMU Parsing

    /// Parse IMU packet: header + N × 12-byte samples
    private func parseIMU(_ data: [UInt8], headerSize: Int, maxSamples: Int) -> [IMUSample] {
        var samples: [IMUSample] = []
        let baseTimestamp = Int64(Date().timeIntervalSince1970 * 1000)

        for i in 0..<maxSamples {
            let offset = headerSize + i * Self.imuSampleBytes
            guard offset + Self.imuSampleBytes <= data.count else { break }

            let axRaw = readInt16LE(data, offset: offset)
            let ayRaw = readInt16LE(data, offset: offset + 2)
            let azRaw = readInt16LE(data, offset: offset + 4)
            let gxRaw = readInt16LE(data, offset: offset + 6)
            let gyRaw = readInt16LE(data, offset: offset + 8)
            let gzRaw = readInt16LE(data, offset: offset + 10)

            // Skip padding samples (all axes identical)
            if axRaw == ayRaw && ayRaw == azRaw && azRaw == gxRaw && gxRaw == gyRaw && gyRaw == gzRaw {
                continue
            }

            let axG = Double(axRaw) / Self.accelScale
            let ayG = Double(ayRaw) / Self.accelScale
            let azG = Double(azRaw) / Self.accelScale
            let accelMag = sqrt(axG * axG + ayG * ayG + azG * azG)

            let gxDps = Double(gxRaw) / Self.gyroScale
            let gyDps = Double(gyRaw) / Self.gyroScale
            let gzDps = Double(gzRaw) / Self.gyroScale
            let gyroMag = sqrt(gxDps * gxDps + gyDps * gyDps + gzDps * gzDps)

            // Backfill timestamps at 40ms intervals (25 Hz)
            let sampleTimestamp = baseTimestamp - Int64((maxSamples - 1 - i)) * Self.imuSampleIntervalMs

            samples.append(IMUSample(
                axRaw: axRaw, ayRaw: ayRaw, azRaw: azRaw,
                gxRaw: gxRaw, gyRaw: gyRaw, gzRaw: gzRaw,
                axG: axG, ayG: ayG, azG: azG, accelMagG: accelMag,
                gxDps: gxDps, gyDps: gyDps, gzDps: gzDps, gyroMagDps: gyroMag,
                timestamp: sampleTimestamp
            ))
        }

        return samples
    }

    // MARK: - Helpers

    private func readInt16LE(_ data: [UInt8], offset: Int) -> Int16 {
        return Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
    }
}
