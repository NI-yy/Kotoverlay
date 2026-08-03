@preconcurrency import AppKit
import KotoverlayCore
import SwiftUI

@MainActor
final class CompanionPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let hostingController: NSHostingController<CompanionPanelView>
    private let onClose: () -> Void
    private var programmaticHide = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        hostingController = NSHostingController(
            rootView: CompanionPanelView(results: [], status: "Waiting for Discord…")
        )
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 380, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "Kotoverlay"
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.minSize = CGSize(width: 300, height: 300)
    }

    func update(results: [TranslationResult], status: String, discordFrame: CGRect) {
        hostingController.rootView = CompanionPanelView(results: results, status: status)
        guard let mainScreenMaxY = NSScreen.screens.first?.frame.maxY else { return }
        let appKitDiscordFrame = ScreenCoordinateConverter.appKitRect(
            from: discordFrame,
            mainScreenMaxY: mainScreenMaxY
        )
        let targetFrame = CompanionPanelPlacement.frame(
            beside: appKitDiscordFrame,
            panelSize: CGSize(width: 380, height: min(720, appKitDiscordFrame.height)),
            visibleScreens: NSScreen.screens.map(\.visibleFrame)
        )
        panel.setFrame(targetFrame, display: true, animate: panel.isVisible)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        programmaticHide = true
        panel.orderOut(nil)
        programmaticHide = false
    }

    func windowWillClose(_ notification: Notification) {
        guard !programmaticHide else { return }
        onClose()
    }
}

struct CompanionPanelView: View {
    let results: [TranslationResult]
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "character.bubble")
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            Divider()

            if results.isEmpty {
                ContentUnavailableView(
                    "No translations yet",
                    systemImage: "text.bubble",
                    description: Text("Open an English Discord channel or scroll to new messages.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(results, id: \.identity) { result in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.sourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text(result.translatedText)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 300, minHeight: 300)
    }
}
