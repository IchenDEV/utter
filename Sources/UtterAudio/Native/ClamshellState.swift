import Foundation
import IOKit

/// Reads the MacBook lid state from the power-management root domain.
///
/// Apple hardware disconnects the built-in microphone in hardware while the lid
/// is closed, so capture must route elsewhere instead of trying to re-enable it.
/// Desktops without a lid report no clamshell entry and are treated as open.
package enum ClamshellState {
    package static var isClosed: Bool {
        isClosed(fromClamshellState: registryClamshellValue)
    }

    /// Pure parse of the `AppleClamshellState` registry value; unit-testable.
    package static func isClosed(fromClamshellState value: Any?) -> Bool {
        ClamshellValue.isClosed(value)
    }

    private static var registryClamshellValue: Any? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }
}
