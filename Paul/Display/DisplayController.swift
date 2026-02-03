import Foundation
import IOKit
import IOKit.pwr_mgt

class DisplayController {
    static let shared = DisplayController()

    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false

    func wakeDisplay() {
        let task = Process()
        task.launchPath = "/usr/bin/caffeinate"
        task.arguments = ["-u", "-t", "1"]
        try? task.run()
    }

    func preventSleep() {
        guard !isPreventingSleep else { return }

        let reason = "Paul Voice Assistant aktiv" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isPreventingSleep = true
        }
    }

    func allowSleep() {
        guard isPreventingSleep else { return }
        IOPMAssertionRelease(assertionID)
        isPreventingSleep = false
    }
}
