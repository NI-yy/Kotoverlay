import CoreGraphics

public enum ScreenCapturePermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system consent flow only when explicitly requested.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        guard !isGranted else { return true }
        return CGRequestScreenCaptureAccess()
    }
}
