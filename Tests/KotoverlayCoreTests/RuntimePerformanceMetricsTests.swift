import Foundation
import Testing
@testable import KotoverlayCore

@Suite("Runtime performance metrics")
struct RuntimePerformanceMetricsTests {
    @Test("Keeps only the newest bounded timing samples")
    func boundedSamples() {
        var metrics = RuntimePerformanceMetrics(maximumSamplesPerStage: 2)

        metrics.record(stage: .capture, milliseconds: 10)
        metrics.record(stage: .capture, milliseconds: 20)
        metrics.record(stage: .capture, milliseconds: 30)

        let summary = metrics.summary(for: .capture)
        #expect(summary.sampleCount == 2)
        #expect(summary.averageMilliseconds == 25)
        #expect(summary.maximumMilliseconds == 30)
    }

    @Test("Separates stages and ignores invalid durations")
    func stagesAndInvalidDurations() {
        var metrics = RuntimePerformanceMetrics()

        metrics.record(stage: .capture, milliseconds: -.infinity)
        metrics.record(stage: .ocr, milliseconds: -5)
        metrics.record(stage: .translation, duration: .milliseconds(12))

        #expect(metrics.summary(for: .capture).sampleCount == 0)
        #expect(metrics.summary(for: .ocr).averageMilliseconds == 0)
        #expect(metrics.summary(for: .translation).averageMilliseconds == 12)
    }

    @Test("Diagnostics contain only content-free aggregate labels")
    func contentFreeDiagnostics() {
        var metrics = RuntimePerformanceMetrics(maximumSamplesPerStage: 4)
        metrics.recordFrame(changed: true)
        metrics.recordFrame(changed: false)
        metrics.recordFailure()
        metrics.record(stage: .ocr, milliseconds: 12.34)

        let report = metrics.diagnosticsLines().joined(separator: "\n")
        #expect(report.contains("performance.framesChanged=1"))
        #expect(report.contains("performance.ocr=count:1,avgMs:12.3,maxMs:12.3"))
        #expect(!report.contains("Discord"))
        #expect(!report.contains("sourceText"))
    }

    @Test("Reset clears counts and samples")
    func reset() {
        var metrics = RuntimePerformanceMetrics()
        metrics.recordFrame(changed: true)
        metrics.recordFailure()
        metrics.record(stage: .capture, milliseconds: 5)

        metrics.reset()

        #expect(metrics.changedFrameCount == 0)
        #expect(metrics.unchangedFrameCount == 0)
        #expect(metrics.failureCount == 0)
        #expect(metrics.summary(for: .capture).sampleCount == 0)
    }
}
