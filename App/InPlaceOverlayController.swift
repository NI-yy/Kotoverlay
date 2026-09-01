@preconcurrency import AppKit
import CoreGraphics
import KotoverlayCore
import SwiftUI

@MainActor
final class InPlaceOverlayController {
    private var entries: [MessageIdentity: OverlayEntry] = [:]
    private var optionPressed = false
    private var alwaysShowOriginals = false
    private var modifierTimer: Timer?

    init() {
        modifierTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshModifierState()
            }
        }
    }

    func setAlwaysShowOriginals(_ enabled: Bool) {
        guard alwaysShowOriginals != enabled else { return }
        alwaysShowOriginals = enabled
        refreshViews()
    }

    func update(
        results: [TranslationResult],
        sourceDiscordFrame: CGRect,
        sourceDiscordContentFrame: CGRect,
        currentDiscordFrame: CGRect,
        discordWindowID: CGWindowID,
        discordIsFrontmost: Bool
    ) {
        guard discordIsFrontmost,
              let mainScreenMaxY = NSScreen.screens.first?.frame.maxY else {
            hideAll()
            return
        }

        let currentAppKitDiscordFrame = ScreenCoordinateConverter.appKitRect(
            from: currentDiscordFrame,
            mainScreenMaxY: mainScreenMaxY
        )
        guard let currentDiscordContentFrame = InPlaceOverlayLayout.reproject(
            sourceDiscordContentFrame,
            from: sourceDiscordFrame,
            to: currentDiscordFrame
        ) else {
            hideAll()
            return
        }
        let currentAppKitContentFrame = ScreenCoordinateConverter.appKitRect(
            from: currentDiscordContentFrame,
            mainScreenMaxY: mainScreenMaxY
        ).intersection(currentAppKitDiscordFrame)
        let visibleScreenFrames = NSScreen.screens.map(\.visibleFrame)
        var candidates: [(result: TranslationResult, entry: OverlayEntry, frame: CGRect)] = []

        for result in results {
            guard let reprojected = InPlaceOverlayLayout.reproject(
                result.bounds.cgRect,
                from: sourceDiscordFrame,
                to: currentDiscordFrame
            ) else { continue }
            let anchor = ScreenCoordinateConverter.appKitRect(
                from: reprojected,
                mainScreenMaxY: mainScreenMaxY
            )
            guard InPlaceOverlayLayout.isVisible(
                anchor,
                inside: currentAppKitContentFrame,
                screenFrames: visibleScreenFrames
            ) else { continue }

            let entry = entries[result.identity] ?? OverlayEntry()
            entries[result.identity] = entry
            guard let frame = overlayFrame(
                for: result,
                anchoredTo: anchor,
                inside: currentAppKitContentFrame
            ) else { continue }
            candidates.append((
                result: result,
                entry: entry,
                frame: frame
            ))
        }

        let resolvedFrames = InPlaceOverlayLayout.resolveCollisions(
            candidates.map(\.frame),
            inside: currentAppKitContentFrame
        )
        var activeIdentities: Set<MessageIdentity> = []
        for (candidate, resolvedFrame) in zip(candidates, resolvedFrames) {
            guard let resolvedFrame else { continue }
            activeIdentities.insert(candidate.result.identity)
            candidate.entry.update(
                result: candidate.result,
                frame: resolvedFrame,
                fontSize: overlayFontSize(for: resolvedFrame),
                showOriginal: alwaysShowOriginals || optionPressed,
                relativeTo: discordWindowID
            )
        }

        removeEntries(except: activeIdentities)
    }

    func hideAll() {
        for entry in entries.values { entry.hide() }
    }

    func clear() {
        for entry in entries.values { entry.close() }
        entries.removeAll(keepingCapacity: true)
    }

    private func refreshModifierState() {
        let pressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
        guard pressed != optionPressed else { return }
        optionPressed = pressed
        refreshViews()
    }

    private func refreshViews() {
        for entry in entries.values {
            entry.setShowOriginal(alwaysShowOriginals || optionPressed)
        }
    }

    private func removeEntries(except activeIdentities: Set<MessageIdentity>) {
        let stale = Set(entries.keys).subtracting(activeIdentities)
        for identity in stale {
            entries.removeValue(forKey: identity)?.close()
        }
    }

    private func overlayFrame(
        for result: TranslationResult,
        anchoredTo anchor: CGRect,
        inside discordFrame: CGRect
    ) -> CGRect? {
        let horizontalMargin: CGFloat = 10
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 5
        let availableWidth = discordFrame.maxX - anchor.minX - horizontalMargin
        guard availableWidth >= 100 else { return nil }
        let fontSize = min(16, max(11, anchor.height * 0.72))
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let preferredWidth = min(
            max(anchor.width + horizontalPadding, min(520, availableWidth)),
            availableWidth
        )
        let measured = (result.translatedText as NSString).boundingRect(
            with: CGSize(
                width: max(60, preferredWidth - horizontalPadding),
                height: 400
            ),
            options: [.usesFontLeading, .usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        let desiredHeight = min(
            150,
            max(anchor.height + verticalPadding, ceil(measured.height) + verticalPadding)
        )
        return InPlaceOverlayLayout.overlayFrame(
            anchoredTo: anchor,
            desiredSize: CGSize(width: preferredWidth, height: desiredHeight),
            inside: discordFrame,
            horizontalMargin: horizontalMargin
        )
    }

    private func overlayFontSize(for frame: CGRect) -> CGFloat {
        min(16, max(11, (frame.height - 5) * 0.72))
    }
}

@MainActor
private final class OverlayEntry {
    private let panel: NSPanel
    private let hostingController: NSHostingController<InPlaceTranslationView>
    private var result: TranslationResult?
    private var showOriginal = false
    private var fontSize: CGFloat = 14

    init() {
        hostingController = NSHostingController(
            rootView: InPlaceTranslationView(
                sourceText: "",
                translatedText: "",
                showOriginal: false
            )
        )
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
    }

    func update(
        result: TranslationResult,
        frame: CGRect,
        fontSize: CGFloat,
        showOriginal: Bool,
        relativeTo discordWindowID: CGWindowID
    ) {
        self.result = result
        self.fontSize = fontSize
        self.showOriginal = showOriginal
        refreshView()
        panel.setFrame(frame, display: true)
        panel.order(.above, relativeTo: Int(discordWindowID))
    }

    func setShowOriginal(_ enabled: Bool) {
        guard showOriginal != enabled else { return }
        showOriginal = enabled
        refreshView()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    private func refreshView() {
        guard let result else { return }
        hostingController.rootView = InPlaceTranslationView(
            sourceText: result.sourceText,
            translatedText: result.translatedText,
            showOriginal: showOriginal,
            fontSize: fontSize
        )
    }
}

private struct InPlaceTranslationView: View {
    let sourceText: String
    let translatedText: String
    let showOriginal: Bool
    var fontSize: CGFloat = 14

    var body: some View {
        Text(showOriginal ? sourceText : translatedText)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(6)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.9)
            .allowsTightening(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}
