@preconcurrency import AppKit
import Combine
import KotoverlayCore
import SwiftUI

@MainActor
final class CompanionPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let hostingController: NSHostingController<CompanionPanelView>
    private let viewModel: CompanionPanelViewModel
    private let scrollCoordinator: CompanionScrollCoordinator
    private let onClose: () -> Void
    private var programmaticHide = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let viewModel = CompanionPanelViewModel()
        let scrollCoordinator = CompanionScrollCoordinator()
        self.viewModel = viewModel
        self.scrollCoordinator = scrollCoordinator
        hostingController = NSHostingController(
            rootView: CompanionPanelView(
                model: viewModel,
                scrollCoordinator: scrollCoordinator
            )
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
        let distanceFromBottom = scrollCoordinator.distanceFromBottom()
        let startsNewContext = viewModel.update(results: results, status: status)
        if startsNewContext {
            scrollCoordinator.scrollToBottomAfterLayout()
        } else if let distanceFromBottom {
            scrollCoordinator.restoreAfterLayout(distanceFromBottom: distanceFromBottom)
        }
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

    @discardableResult
    func update(results: [TranslationResult], status: String) -> Bool {
        let ordered = results.sorted { $0.visibleOrder < $1.visibleOrder }
        let startsNewContext = CompanionFeedNavigation.startsNewVisibleContext(
            previous: self.results.map(\.identity),
            current: ordered.map(\.identity)
        )
        self.results = ordered
        self.status = status
        return startsNewContext
    }
}

struct CompanionPanelView: View {
    @ObservedObject var model: CompanionPanelViewModel
    @ObservedObject var scrollCoordinator: CompanionScrollCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "character.bubble")
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !scrollCoordinator.isAtBottom {
                    Button {
                        scrollCoordinator.scrollToBottomAfterLayout(animated: true)
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
                .background(CompanionScrollViewResolver(coordinator: scrollCoordinator))
                .onAppear { scrollCoordinator.scrollToBottomAfterLayout() }
            }
        }
        .frame(minWidth: 300, minHeight: 300)
    }
}

@MainActor
final class CompanionScrollCoordinator: ObservableObject {
    @Published private(set) var isAtBottom = true

    private weak var scrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var pendingUpdate = 0

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    func attach(_ scrollView: NSScrollView) {
        guard self.scrollView !== scrollView else { return }
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        self.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshBottomState() }
        }
        refreshBottomState()
    }

    func distanceFromBottom() -> CGFloat? {
        guard let scrollView,
              let documentView = scrollView.documentView else { return nil }
        let visible = scrollView.documentVisibleRect
        if !documentView.isFlipped {
            return max(0, visible.minY - documentView.bounds.minY)
        }
        return CompanionFeedNavigation.distanceFromBottom(
            documentHeight: documentView.bounds.height,
            viewportHeight: visible.height,
            verticalOffset: visible.minY - documentView.bounds.minY
        )
    }

    func restoreAfterLayout(distanceFromBottom: CGFloat) {
        scheduleAfterLayout { [weak self] in
            self?.scroll(distanceFromBottom: distanceFromBottom)
        }
    }

    func scrollToBottomAfterLayout(animated: Bool = false) {
        scheduleAfterLayout { [weak self] in
            guard let self else { return }
            if animated, let scrollView = self.scrollView {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.scroll(distanceFromBottom: 0, animator: scrollView.contentView.animator())
                }
            } else {
                self.scroll(distanceFromBottom: 0)
            }
        }
    }

    private func scheduleAfterLayout(_ operation: @escaping @MainActor () -> Void) {
        pendingUpdate &+= 1
        let update = pendingUpdate
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingUpdate == update else { return }
            self.scrollView?.documentView?.layoutSubtreeIfNeeded()
            operation()
        }
    }

    private func scroll(
        distanceFromBottom: CGFloat,
        animator: NSClipView? = nil
    ) {
        guard let scrollView,
              let documentView = scrollView.documentView else { return }
        let viewportHeight = scrollView.contentView.bounds.height
        let targetY: CGFloat
        if documentView.isFlipped {
            targetY = documentView.bounds.minY + CompanionFeedNavigation.verticalOffset(
                preservingDistanceFromBottom: distanceFromBottom,
                documentHeight: documentView.bounds.height,
                viewportHeight: viewportHeight
            )
        } else {
            targetY = documentView.bounds.minY + max(0, distanceFromBottom)
        }
        let clipView = animator ?? scrollView.contentView
        clipView.setBoundsOrigin(NSPoint(x: scrollView.contentView.bounds.minX, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshBottomState()
    }

    private func refreshBottomState() {
        guard let distance = distanceFromBottom() else { return }
        isAtBottom = distance <= 2
    }
}

private struct CompanionScrollViewResolver: NSViewRepresentable {
    let coordinator: CompanionScrollCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolve(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolve(from: nsView)
    }

    private func resolve(from view: NSView) {
        DispatchQueue.main.async {
            var ancestor: NSView? = view
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    coordinator.attach(scrollView)
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
