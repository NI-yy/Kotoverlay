@preconcurrency import AppKit
import Combine
import KotoverlayCore
import SwiftUI

@MainActor
final class CompanionPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let hostingController: NSHostingController<CompanionPanelView>
    private let viewModel: CompanionPanelViewModel
    private let onClose: () -> Void
    private var programmaticHide = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let viewModel = CompanionPanelViewModel()
        self.viewModel = viewModel
        hostingController = NSHostingController(
            rootView: CompanionPanelView(model: viewModel)
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
        viewModel.update(results: results, status: status)
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

@MainActor
final class CompanionPanelViewModel: ObservableObject {
    @Published private(set) var results: [TranslationResult] = []
    @Published private(set) var status = "Waiting for Discord…"
    @Published private(set) var contextRevision = 0

    func update(results: [TranslationResult], status: String) {
        let ordered = results.sorted { $0.visibleOrder < $1.visibleOrder }
        if CompanionFeedNavigation.startsNewVisibleContext(
            previous: self.results.map(\.identity),
            current: ordered.map(\.identity)
        ) {
            contextRevision &+= 1
        }
        self.results = ordered
        self.status = status
    }
}

struct CompanionPanelView: View {
    @ObservedObject var model: CompanionPanelViewModel
    @State private var scrollPosition: MessageIdentity?
    @State private var followsLatest = true

    private var latestIdentity: MessageIdentity? {
        model.results.last?.identity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "character.bubble")
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !followsLatest {
                    Button {
                        followLatest()
                    } label: {
                        Label("Latest", systemImage: "arrow.down.to.line.compact")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Return to the latest Discord translation")
                }
            }
            .padding(12)
            Divider()

            if model.results.isEmpty {
                ContentUnavailableView(
                    "No translations yet",
                    systemImage: "text.bubble",
                    description: Text("Open an English Discord channel or scroll to new messages.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.results, id: \.identity) { result in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Original")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(result.sourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Text("日本語")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                Text(result.translatedText)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollPosition(id: $scrollPosition, anchor: .bottom)
                .onAppear { followLatest() }
                .onChange(of: latestIdentity) { _, latest in
                    guard followsLatest else { return }
                    scrollPosition = latest
                }
                .onChange(of: scrollPosition) { _, visibleIdentity in
                    followsLatest = CompanionFeedNavigation.isAtLatest(
                        visibleIdentity: visibleIdentity,
                        latestIdentity: latestIdentity
                    )
                }
                .onChange(of: model.contextRevision) { _, _ in
                    followLatest()
                }
            }
        }
        .frame(minWidth: 300, minHeight: 300)
    }

    private func followLatest() {
        followsLatest = true
        withAnimation(.easeOut(duration: 0.2)) {
            scrollPosition = latestIdentity
        }
    }
}
