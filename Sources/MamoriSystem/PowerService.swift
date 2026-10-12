import Foundation
import IOKit.pwr_mgt

/// Owns a temporary assertion without changing the Mac's power preferences.
@MainActor
public final class PowerService {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isActive: Bool { assertionID != nil }

    public func enable() throws {
        guard assertionID == nil else { return }
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Mamori is keeping this work session awake" as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else {
            throw PowerServiceError(operation: "enable keep awake", code: result)
        }
        assertionID = identifier
    }

    public func disable() throws {
        guard let identifier = assertionID else { return }
        let result = IOPMAssertionRelease(identifier)
        guard result == kIOReturnSuccess else {
            throw PowerServiceError(operation: "release keep awake", code: result)
        }
        assertionID = nil
    }
}

public struct PowerServiceError: LocalizedError, Sendable {
    public let operation: String
    public let code: IOReturn

    public var errorDescription: String? {
        "Could not \(operation) (IOKit 0x\(String(code, radix: 16)))."
    }
}
