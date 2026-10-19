import IOKit

/// Lid-closed ("clamshell") sleep control without root, via the IOPMrootDomain user client
/// (the approach used by Amphetamine Enhancer). Private API: selector from IOPMLibDefs.h.
///
/// The setting is system-wide and survives the calling process, so callers must always restore it.
public enum Clamshell {
    private static let setClamshellSleepStateSelector: UInt32 = 12 // kPMSetClamshellSleepState

    /// - Returns: `true` if the kernel accepted the request.
    @discardableResult
    public static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }

        var input: [UInt64] = [disabled ? 1 : 0]
        var outputCount: UInt32 = 0
        return IOConnectCallScalarMethod(connection, setClamshellSleepStateSelector, &input, 1, nil, &outputCount)
            == KERN_SUCCESS
    }
}
