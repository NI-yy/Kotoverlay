@preconcurrency import ApplicationServices

public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Requests access only when the caller explicitly opts in.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        guard !isGranted else { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
