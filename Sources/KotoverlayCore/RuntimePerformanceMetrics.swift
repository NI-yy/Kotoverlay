import Foundation

public enum RuntimeMetricStage: String, CaseIterable, Codable, Sendable {
    case capture
    case ocr
    case translation
}

public struct RuntimeMetricSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let averageMilliseconds: Double
    public let maximumMilliseconds: Double

    public init(
        sampleCount: Int,
        averageMilliseconds: Double,
        maximumMilliseconds: Double
    ) {
        self.sampleCount = sampleCount
        self.averageMilliseconds = averageMilliseconds
        self.maximumMilliseconds = maximumMilliseconds
    }
}

public struct RuntimePerformanceMetrics: Equatable, Sendable {
    public static let defaultMaximumSamplesPerStage = 256

    public let maximumSamplesPerStage: Int
    public private(set) var changedFrameCount = 0
    public private(set) var unchangedFrameCount = 0
    public private(set) var failureCount = 0
    private var durationsByStage: [RuntimeMetricStage: [Double]] = [:]

    public init(
        maximumSamplesPerStage: Int = Self.defaultMaximumSamplesPerStage
    ) {
        self.maximumSamplesPerStage = max(1, maximumSamplesPerStage)
    }

    public mutating func record(
        stage: RuntimeMetricStage,
        duration: Duration
    ) {
        record(stage: stage, milliseconds: duration.milliseconds)
    }

    public mutating func record(
        stage: RuntimeMetricStage,
        milliseconds: Double
    ) {
        guard milliseconds.isFinite else { return }
        var samples = durationsByStage[stage, default: []]
        samples.append(max(0, milliseconds))
        if samples.count > maximumSamplesPerStage {
            samples.removeFirst(samples.count - maximumSamplesPerStage)
        }
        durationsByStage[stage] = samples
    }

    public mutating func recordFrame(changed: Bool) {
        if changed {
            changedFrameCount = changedFrameCount.saturatingIncremented
        } else {
            unchangedFrameCount = unchangedFrameCount.saturatingIncremented
        }
    }

    public mutating func recordFailure() {
        failureCount = failureCount.saturatingIncremented
    }

    public func summary(for stage: RuntimeMetricStage) -> RuntimeMetricSummary {
        let samples = durationsByStage[stage, default: []]
        guard !samples.isEmpty else {
            return RuntimeMetricSummary(
                sampleCount: 0,
                averageMilliseconds: 0,
                maximumMilliseconds: 0
            )
        }
        return RuntimeMetricSummary(
            sampleCount: samples.count,
            averageMilliseconds: samples.reduce(0, +) / Double(samples.count),
            maximumMilliseconds: samples.max() ?? 0
        )
    }

    public func diagnosticsLines() -> [String] {
        var lines = [
            "performance.framesChanged=\(changedFrameCount)",
            "performance.framesUnchanged=\(unchangedFrameCount)",
            "performance.failures=\(failureCount)",
            "performance.sampleLimit=\(maximumSamplesPerStage)"
        ]
        for stage in RuntimeMetricStage.allCases {
            let value = summary(for: stage)
            lines.append(
                "performance.\(stage.rawValue)="
                    + "count:\(value.sampleCount),"
                    + "avgMs:\(Self.format(value.averageMilliseconds)),"
                    + "maxMs:\(Self.format(value.maximumMilliseconds))"
            )
        }
        return lines
    }

    public mutating func reset() {
        changedFrameCount = 0
        unchangedFrameCount = 0
        failureCount = 0
        durationsByStage.removeAll(keepingCapacity: false)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

private extension Int {
    var saturatingIncremented: Int {
        self == .max ? self : self + 1
    }
}
