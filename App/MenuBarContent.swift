import AppKit
import KotoverlayCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "character.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kotoverlay").font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if model.isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            ReadinessRows(model: model)

            HStack {
                Button(model.isRunning ? "Pause" : "Start") {
                    model.isRunning ? model.pause() : model.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart && !model.isRunning)

                Button("Retry") { model.retry() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(model.translationCount) translated")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Clear Cache") { model.clearCache() }
                Button("Copy Diagnostics") { model.copyDiagnostics() }
                SettingsLink { Text("Settings") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 360)
    }
}

private struct ReadinessRows: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ReadinessRow(
                title: "Screen Recording",
                ready: model.screenRecordingGranted,
                detail: model.screenRecordingGranted ? "Ready" : "Required"
            ) {
                model.requestScreenRecordingPermission()
            }
            ReadinessRow(
                title: "Ollama / qwen3:1.7b",
                ready: model.ollamaReady,
                detail: model.ollamaReady ? "Ready" : "Unavailable"
            ) {
                model.refreshReadiness()
            }
            ReadinessRow(
                title: "Discord",
                ready: model.discordAvailable,
                detail: model.discordAvailable ? "Detected" : "Not detected"
            ) {
                model.refreshReadiness()
            }
            ReadinessRow(
                title: "Accessibility",
                ready: model.accessibilityGranted,
                detail: model.accessibilityGranted ? "Optional diagnostic ready" : "Optional"
            ) {
                model.requestAccessibilityPermission()
            }
        }
    }
}

private struct ReadinessRow: View {
    let title: String
    let ready: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !ready {
                Button("Fix") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct SettingsContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Local translation") {
                LabeledContent("Endpoint", value: "http://127.0.0.1:11434")
                LabeledContent("Model", value: "qwen3:1.7b")
            }
            Section("Privacy") {
                Text("Only the Discord window is captured. Screenshots are not saved. Translations are cached locally and can be cleared from the menu.")
                    .foregroundStyle(.secondary)
                Toggle(
                    "Keep translations between launches",
                    isOn: Binding(
                        get: { model.persistentCacheEnabled },
                        set: { model.setPersistentCacheEnabled($0) }
                    )
                )
                Button("Clear Translation Cache") { model.clearCache() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 300)
    }
}
