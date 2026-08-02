@preconcurrency import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public struct CapturedWindow: @unchecked Sendable {
    public let image: CGImage
    public let windowID: CGWindowID
    public let title: String
    public let frame: CGRect
    public let scaleFactor: CGFloat

    public init(
        image: CGImage,
        windowID: CGWindowID,
        title: String,
        frame: CGRect,
        scaleFactor: CGFloat
    ) {
        self.image = image
        self.windowID = windowID
        self.title = title
        self.frame = frame
        self.scaleFactor = scaleFactor
    }
}

public enum WindowCaptureError: Error, LocalizedError, Sendable {
    case permissionRequired
    case applicationNotFound(bundleIdentifier: String)
    case windowNotFound(bundleIdentifier: String)
    case invalidWindowSize
    case captureUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "Screen Recording permission is required. Run ocrprobe --prompt, then enable it in System Settings."
        case let .applicationNotFound(bundleIdentifier):
            "No shareable application was found for bundle identifier \(bundleIdentifier)."
        case let .windowNotFound(bundleIdentifier):
            "The application \(bundleIdentifier) is running, but no on-screen window is shareable."
        case .invalidWindowSize:
            "The selected window has an invalid capture size."
        case let .captureUnavailable(reason):
            "Discord window capture failed: \(reason)"
        }
    }
}

public struct DiscordWindowCapturer: Sendable {
    public init() {}

    public func capture(
        bundleIdentifier: String = "com.hnc.Discord"
    ) async throws -> CapturedWindow {
        guard ScreenCapturePermission.isGranted else {
            throw WindowCaptureError.permissionRequired
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            guard ScreenCapturePermission.isGranted else {
                throw WindowCaptureError.permissionRequired
            }
            throw WindowCaptureError.captureUnavailable(reason: error.localizedDescription)
        }
        let applications = content.applications.filter {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard !applications.isEmpty else {
            throw WindowCaptureError.applicationNotFound(bundleIdentifier: bundleIdentifier)
        }

        let windows = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == bundleIdentifier
                && window.frame.width > 100
                && window.frame.height > 100
        }
        guard let window = windows.max(by: { visibleArea($0.frame) < visibleArea($1.frame) }) else {
            throw WindowCaptureError.windowNotFound(bundleIdentifier: bundleIdentifier)
        }

        let scaleFactor = captureScale(for: window.frame, displays: content.displays)
        let pixelWidth = Int((window.frame.width * scaleFactor).rounded())
        let pixelHeight = Int((window.frame.height * scaleFactor).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw WindowCaptureError.invalidWindowSize
        }

        let configuration = SCStreamConfiguration()
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            guard ScreenCapturePermission.isGranted else {
                throw WindowCaptureError.permissionRequired
            }
            throw WindowCaptureError.captureUnavailable(reason: error.localizedDescription)
        }
        return CapturedWindow(
            image: image,
            windowID: window.windowID,
            title: window.title ?? "",
            frame: window.frame,
            scaleFactor: scaleFactor
        )
    }

    private func captureScale(for windowFrame: CGRect, displays: [SCDisplay]) -> CGFloat {
        guard let display = displays.max(by: {
            visibleArea($0.frame.intersection(windowFrame))
                < visibleArea($1.frame.intersection(windowFrame))
        }), display.frame.width > 0 else {
            return 1
        }
        return max(1, CGFloat(display.width) / display.frame.width)
    }

    private func visibleArea(_ frame: CGRect) -> CGFloat {
        guard !frame.isNull, !frame.isInfinite else { return 0 }
        return max(0, frame.width) * max(0, frame.height)
    }
}
