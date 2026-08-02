@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public struct AccessibilityScanOptions: Sendable {
    public var bundleIdentifier: String
    public var maximumElements: Int
    public var maximumDepth: Int
    public var timeout: Duration
    public var messagingTimeoutSeconds: Float
    public var enableElectronAccessibility: Bool

    public init(
        bundleIdentifier: String = "com.hnc.Discord",
        maximumElements: Int = 2_000,
        maximumDepth: Int = 30,
        timeout: Duration = .milliseconds(250),
        messagingTimeoutSeconds: Float = 0.1,
        enableElectronAccessibility: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.maximumElements = max(1, maximumElements)
        self.maximumDepth = max(0, maximumDepth)
        self.timeout = max(.zero, timeout)
        self.messagingTimeoutSeconds = max(0.01, messagingTimeoutSeconds)
        self.enableElectronAccessibility = enableElectronAccessibility
    }
}

public struct AccessibilityScanReport: Sendable {
    public let applicationName: String
    public let processIdentifier: pid_t
    public let elapsed: Duration
    public let snapshots: [AXElementSnapshot]
    public let stoppedBecause: StopReason?
    public let manualAccessibilityResult: Int32?

    public enum StopReason: String, Sendable {
        case cancelled
        case elementLimit
        case timeout
    }
}

public enum AccessibilityScanError: Error, LocalizedError, Sendable {
    case permissionRequired
    case applicationNotRunning(bundleIdentifier: String)
    case noUsableWindow

    public var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Accessibility permission is required. Run axprobe --prompt, then enable it in System Settings."
        case let .applicationNotRunning(bundleIdentifier):
            "No running application was found for bundle identifier \(bundleIdentifier)."
        case .noUsableWindow:
            "The application is running, but no accessible window was found."
        }
    }
}

public struct AccessibilityScanner {
    public init() {}

    public func scan(
        options: AccessibilityScanOptions = .init(),
        shouldCancel: () -> Bool = { false }
    ) throws -> AccessibilityScanReport {
        guard AccessibilityPermission.isGranted else {
            throw AccessibilityScanError.permissionRequired
        }
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: options.bundleIdentifier)
            .first(where: { !$0.isTerminated }) else {
            throw AccessibilityScanError.applicationNotRunning(bundleIdentifier: options.bundleIdentifier)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, options.messagingTimeoutSeconds)
        let manualAccessibilityResult: Int32? = if options.enableElectronAccessibility {
            AXUIElementSetAttributeValue(
                appElement,
                "AXManualAccessibility" as CFString,
                true as CFTypeRef
            ).rawValue
        } else {
            nil
        }
        guard let root = preferredWindow(of: appElement) else {
            throw AccessibilityScanError.noUsableWindow
        }

        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: options.timeout)
        var snapshots: [AXElementSnapshot] = []
        var stack: [(element: AXUIElement, depth: Int, path: [Int])] = [(root, 0, [])]
        var stopReason: AccessibilityScanReport.StopReason?

        while let current = stack.popLast() {
            if shouldCancel() {
                stopReason = .cancelled
                break
            }
            if clock.now >= deadline {
                stopReason = .timeout
                break
            }
            if snapshots.count >= options.maximumElements {
                stopReason = .elementLimit
                break
            }

            snapshots.append(snapshot(of: current.element, depth: current.depth, path: current.path))
            guard current.depth < options.maximumDepth else { continue }

            let children = copyElements(current.element, attribute: kAXChildrenAttribute as CFString)
            for (index, child) in children.enumerated().reversed() {
                stack.append((child, current.depth + 1, current.path + [index]))
            }
        }

        return AccessibilityScanReport(
            applicationName: application.localizedName ?? options.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            elapsed: started.duration(to: clock.now),
            snapshots: snapshots,
            stoppedBecause: stopReason,
            manualAccessibilityResult: manualAccessibilityResult
        )
    }

    private func preferredWindow(of application: AXUIElement) -> AXUIElement? {
        if let focused = copyElement(application, attribute: kAXFocusedWindowAttribute as CFString) {
            return focused
        }
        if let main = copyElement(application, attribute: kAXMainWindowAttribute as CFString) {
            return main
        }
        return copyElements(application, attribute: kAXWindowsAttribute as CFString).first
    }

    private func snapshot(of element: AXUIElement, depth: Int, path: [Int]) -> AXElementSnapshot {
        let role = copyString(element, attribute: kAXRoleAttribute as CFString) ?? "unknown"
        let text = firstNonempty([
            copyString(element, attribute: kAXValueAttribute as CFString),
            copyString(element, attribute: kAXTitleAttribute as CFString),
            copyString(element, attribute: kAXDescriptionAttribute as CFString)
        ])
        return AXElementSnapshot(role: role, text: text, frame: copyFrame(element), depth: depth, path: path)
    }

    private func firstNonempty(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            if let candidate,
               !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    private func copyString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func copyElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func copyElements(_ element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let values = value as? [AXUIElement] else { return [] }
        return values
    }

    private func copyFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = copyPoint(element, attribute: kAXPositionAttribute as CFString),
              let size = copySize(element, attribute: kAXSizeAttribute as CFString) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func copyPoint(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copySize(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}
