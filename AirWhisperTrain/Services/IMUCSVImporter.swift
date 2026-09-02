import Foundation

/// Swift port of the reference `airwhisper_imu_visualizer.html` CSV ingestion.
/// Mirrors `parseCsv` -> `cleanRawRows` -> `trimTrailingGapTail` -> `medianDt`
/// -> `resampleRows` -> `detectEndIndex` so imported CSVs visualise exactly like
/// files dropped onto the reference web tool.
enum IMUCSVImporter {

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Result {
        let samples: [MotionSample]
        let rows: Int
        let duration: Double
        let sampleRateHz: Double
        let fileName: String
    }

    static let requiredColumns: [String] = [
        "time", "seconds_elapsed",
        "rotationRateX", "rotationRateY", "rotationRateZ",
        "gravityX", "gravityY", "gravityZ",
        "accelerationX", "accelerationY", "accelerationZ",
        "quaternionW", "quaternionX", "quaternionY", "quaternionZ"
    ]

    // MARK: - Entry point

    /// Parses raw CSV text (raw IMU format) into MotionSamples ready for the visualizer.
    static func importCSV(_ text: String, fileName: String) throws -> Result {
        let parsed = try parseCSV(text)
        let cleaned = try cleanRawRows(parsed, fileName: fileName)
        let trimmed = trimTrailingGapTail(cleaned)
        let dt = medianDt(trimmed)
        let resampled = resampleRows(trimmed, dt: dt)

        let rateHz = 1.0 / max(dt, 0.01)
        let endIndex = detectEndIndex(resampled, rateHz: rateHz)
        let finalRows = Array(resampled.prefix(max(1, endIndex + 1)))

        let samples = finalRows.map(Self.makeSample)
        let t0 = finalRows.first.flatMap { seconds($0) } ?? 0
        let duration = (finalRows.last.flatMap { seconds($0) } ?? t0) - t0

        return Result(
            samples: samples,
            rows: finalRows.count,
            duration: duration,
            sampleRateHz: (1.0 / medianDt(finalRows)).rateOne,
            fileName: fileName
        )
    }

    static func makeRecording(_ text: String, fileName: String) throws -> IMURecording {
        let result = try importCSV(text, fileName: fileName)
        return IMURecording(
            id: UUID(),
            letter: inferLetter(fileName),
            index: 1,
            duration: result.duration,
            createdAt: Date(),
            samples: result.samples,
            drawing: nil
        )
    }

    // MARK: - CSV parsing (parseCsv)

    private static func parseCSV(_ text: String) throws -> [[String: String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let src = text.replacingOccurrences(of: "\r", with: "")
        var i = 0
        let chars = Array(src)
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field += "\""
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field += String(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                row.append(field)
                field = ""
            } else if ch == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field += String(ch)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard !rows.isEmpty else { return [] }

        let header = rows[0].enumerated().map { index, name in
            let clean = String(name).replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "column\(index)" : clean
        }

        let out = rows.dropFirst().filter { r in r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }.map { values -> [String: String] in
            var obj: [String: String] = [:]
            for (index, name) in header.enumerated() {
                obj[name] = index < values.count ? values[index] : ""
            }
            return obj
        }
        return out
    }

    // MARK: - cleanRawRows

    private static func cleanRawRows(_ rows: [[String: String]], fileName: String) throws -> [[String: String]] {
        let cols = rows.first?.keys.map { $0 } ?? []
        let missing = requiredColumns.filter { !cols.contains($0) }
        if !missing.isEmpty {
            throw ParseError(message: "\(fileName) is missing columns: \(missing.joined(separator: ", "))")
        }
        let sorted = rows
            .map { row -> (key: String, row: [String: String], value: Double?) in
                let num = Double(row["seconds_elapsed"] ?? "")
                return (String(row["seconds_elapsed"] ?? ""), row, num)
            }
            .filter { $0.value != nil }
            .sorted { ($0.value ?? 0) < ($1.value ?? 0) }
        var seen = Set<String>()
        var out: [[String: String]] = []
        for entry in sorted where !seen.contains(entry.key) {
            seen.insert(entry.key)
            out.append(entry.row)
        }
        if out.count < 3 {
            throw ParseError(message: "\(fileName) has fewer than 3 valid timestamp rows.")
        }
        return out
    }

    // MARK: - trimTrailingGapTail / medianDt / resample / detectEndIndex

    private static func trimTrailingGapTail(_ rows: [[String: String]]) -> [[String: String]] {
        guard rows.count >= 4 else { return rows }
        var dts: [Double] = []
        for i in 1..<rows.count {
            let dt = seconds(rows[i]) - seconds(rows[i - 1])
            if dt > 0 { dts.append(dt) }
        }
        guard let med = median(dts), med > 0 else { return rows }
        let maxTail = max(1, Int(Double(rows.count) * 0.2))
        var cut = rows.count
        for i in stride(from: rows.count - 1, through: 1, by: -1) {
            if rows.count - i > maxTail { break }
            let dt = seconds(rows[i]) - seconds(rows[i - 1])
            if dt > med * 5.0 && dt > 0.05 { cut = i }
        }
        return Array(rows.prefix(max(3, cut)))
    }

    private static func medianDt(_ rows: [[String: String]]) -> Double {
        var dts: [Double] = []
        for i in 1..<rows.count {
            let dt = seconds(rows[i]) - seconds(rows[i - 1])
            if dt > 0 && dt < 0.1 { dts.append(dt) }
        }
        return median(dts) ?? 0.01
    }

    private static func resampleRows(_ rows: [[String: String]], dt: Double) -> [[String: String]] {
        guard let first = rows.first, let last = rows.last, dt > 0 else { return rows }
        let t0 = seconds(first)
        let t1 = seconds(last)
        let times = rows.map(seconds)
        let cols = Array(rows[0].keys).filter { $0 != "seconds_elapsed" }
        let series: [String: [Double]] = rows.reduce(into: [:]) { acc, row in
            for name in cols { acc[name, default: []].append(number(row, name)) }
        }
        var out: [[String: String]] = []
        var t = t0
        while t <= t1 + dt * 0.5 {
            var row: [String: String] = ["seconds_elapsed": String(t)]
            for name in cols {
                let v = interpolateAt(times, series[name] ?? [], t)
                row[name] = String(v)
            }
            out.append(row)
            t += dt
        }
        return out.count >= 3 ? out : rows
    }

    private static func detectEndIndex(_ rows: [[String: String]], rateHz: Double) -> Int {
        guard !rows.isEmpty else { return 0 }
        let e = rows.map { row -> Double in
            let ax = number(row, "accelerationX"), ay = number(row, "accelerationY"), az = number(row, "accelerationZ")
            let gx = number(row, "rotationRateX"), gy = number(row, "rotationRateY"), gz = number(row, "rotationRateZ")
            return sqrt(ax * ax + ay * ay + az * az) + sqrt(gx * gx + gy * gy + gz * gz)
        }
        let smoothW = max(3, Int((rateHz * 0.5).rounded()) | 1)
        let tailW = max(3, Int((rateHz * 1.5).rounded()) | 1)
        let sm = movingAverage(e, window: smoothW)
        let low = quantile(sm, 0.10)
        let high = quantile(sm, 0.90)
        let thr = low + 0.20 * (high - low)
        var quiet = 0
        for value in sm.reversed() {
            if value <= thr { quiet += 1 } else { break }
        }
        if quiet >= tailW { return max(0, sm.count - quiet - 1) }
        return rows.count - 1
    }

    // MARK: - Sample mapping

    private static func makeSample(_ row: [String: String]) -> MotionSample {
        MotionSample(
            timestamp: seconds(row),
            rotationRateX: number(row, "rotationRateX"),
            rotationRateY: number(row, "rotationRateY"),
            rotationRateZ: number(row, "rotationRateZ"),
            gravityX: number(row, "gravityX"),
            gravityY: number(row, "gravityY"),
            gravityZ: number(row, "gravityZ"),
            accelerationX: number(row, "accelerationX"),
            accelerationY: number(row, "accelerationY"),
            accelerationZ: number(row, "accelerationZ"),
            quaternionW: number(row, "quaternionW"),
            quaternionX: number(row, "quaternionX"),
            quaternionY: number(row, "quaternionY"),
            quaternionZ: number(row, "quaternionZ")
        )
    }

    // MARK: - Helpers

    private static func seconds(_ row: [String: String]) -> Double {
        number(row, "seconds_elapsed")
    }

    private static func number(_ row: [String: String], _ name: String) -> Double {
        guard let raw = row[name], let value = Double(raw), value.isFinite else { return 0 }
        return value
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }

    private static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - (window - 1) / 2)
            let hi = min(n - 1, i + window / 2)
            var sum = 0.0
            var count = 0.0
            for j in lo...hi { sum += values[j]; count += 1 }
            out[i] = sum / count
        }
        return out
    }

    private static func interpolateAt(_ times: [Double], _ values: [Double], _ t: Double) -> Double {
        guard !times.isEmpty, !values.isEmpty else { return 0 }
        if t <= times[0] { return values[0] }
        let last = times.count - 1
        if t >= times[last] { return values[last] }
        var lo = 0, hi = last
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= t { lo = mid } else { hi = mid }
        }
        let span = times[hi] - times[lo]
        let frac = span != 0 ? (t - times[lo]) / span : 0
        return values[lo] * (1 - frac) + values[hi] * frac
    }

    private static func quantile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = Double(sorted.count - 1) * q
        let lo = Int(floor(idx))
        let hi = min(sorted.count - 1, lo + 1)
        let frac = idx - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }

    private static func inferLetter(_ fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if let match = stem.range(of: #"WM\d+[_-]([A-Za-z])"#, options: .regularExpression) {
            return String(stem[match].last!).uppercased()
        }
        let lower = stem.lowercased().trimmingCharacters(in: .whitespaces)
        if let first = lower.first, first.isLetter { return String(first).uppercased() }
        return "?"
    }
}

// MARK: - Preprocessed Feature Extraction (for server upload)

extension IMUCSVImporter {
    /// Preprocess a raw IMU CSV zip file into the 15-feature format expected by the server.
    /// Returns a flat Float32 array of 384 * 15 = 5760 elements ready for JSON upload.
    /// 
    /// Note: This version uses the system `unzip` command (available on iOS).
    /// For production, consider adding ZIPFoundation via SPM for robust ZIP handling.
    static func preprocessZipToFeatures(zipURL: URL) throws -> [Float] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirWhisperPreprocess_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Use system unzip command (available on iOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ParseError(message: "Failed to unzip file (exit code: \(process.terminationStatus))")
        }

        // Find CSV file
        let csvFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "csv" }
        guard let csvFile = csvFiles.first else {
            throw ParseError(message: "No CSV file found in zip")
        }

        // Read and parse CSV
        let text = try String(contentsOf: csvFile, encoding: .utf8)
        let result = try importCSV(text, fileName: csvFile.lastPathComponent)

        // Use the same feature engineering as the reference (Stage 9 equivalent)
        let samples = result.samples
        guard !samples.isEmpty else {
            throw ParseError(message: "No valid samples after preprocessing")
        }

        // Convert to feature matrix [T, 15]
        let features = samples.map { sample in
            [
                sample.rotationRateX, sample.rotationRateY, sample.rotationRateZ,
                sample.accelerationWorldX, sample.accelerationWorldY, sample.accelerationWorldZ,
                sample.gyroEnergy, sample.accEnergy, sample.energyProgress,
                sample.deltaRotationRateX, sample.deltaRotationRateY, sample.deltaRotationRateZ,
                sample.deltaAccelerationWorldX, sample.deltaAccelerationWorldY, sample.deltaAccelerationWorldZ
            ]
        }

        // Ensure exactly 384 timesteps (pad or truncate)
        let targetLength = 384
        var featureMatrix = features
        if featureMatrix.count > targetLength {
            featureMatrix = Array(featureMatrix.prefix(targetLength))
        } else if featureMatrix.count < targetLength {
            let padding = Array(repeating: [Float](repeating: 0, count: 15), count: targetLength - featureMatrix.count)
            featureMatrix.append(contentsOf: padding)
        }

        // Flatten to [384 * 15]
        return featureMatrix.flatMap { $0 }
    }
}
