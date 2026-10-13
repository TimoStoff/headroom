import Foundation
import IOKit.pwr_mgt

enum AwakeSession {
    case off
    case hours(Double)
    case indefinitely
}

/// Keeps the Mac from idle sleeping with an IOKit power assertion (what `caffeinate` and Amphetamine use).
/// macOS drops the assertion when Headroom quits or crashes, so the Mac can never get stuck awake.
/// Closing the lid, choosing Sleep, or a critically low battery still sleep as usual.
final class KeepAwake {
    /// Agent mode holds the assertion this long after the last transcript write, which covers
    /// long tool calls and thinking pauses without keeping an idle session awake forever.
    static let agentGrace: TimeInterval = 600

    /// End of the manual session; .distantFuture means indefinitely.
    private(set) var until: Date?
    /// Last time a Claude Code or Grok transcript was written.
    var agentActivity = Date.distantPast

    private var assertion: IOPMAssertionID = 0
    private var assertedDisplay = false
    private var assertedManual = false

    var manual: Bool { until.map { $0 > Date() } ?? false }
    var agentsWorking: Bool {
        Prefs.bool(Prefs.awakeForAgents) && Date().timeIntervalSince(agentActivity) < Self.agentGrace
    }

    func set(_ session: AwakeSession) {
        switch session {
        case .off: until = nil
        case .hours(let h): until = Date().addingTimeInterval(h * 3600)
        case .indefinitely: until = .distantFuture
        }
        update()
    }

    /// Takes or releases the assertion to match the current state. Cheap enough to call on every sample.
    func update() {
        if let u = until, u <= Date() { until = nil }
        let want = manual || agentsWorking
        let display = Prefs.bool(Prefs.awakeDisplay)
        if want == (assertion != 0) && (!want || (display == assertedDisplay && manual == assertedManual)) { return }
        release()
        guard want else { return }
        let type = display ? kIOPMAssertPreventUserIdleDisplaySleep : kIOPMAssertPreventUserIdleSystemSleep
        let reason = (manual ? "Keep awake" : "Claude Code or Grok is working") as CFString
        if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess {
            assertedDisplay = display
            assertedManual = manual
        } else {
            assertion = 0
        }
    }

    func release() {
        if assertion != 0 { IOPMAssertionRelease(assertion) }
        assertion = 0
    }
}
