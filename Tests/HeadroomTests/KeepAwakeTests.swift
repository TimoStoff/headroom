import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Headroom

/// Serialized: these share UserDefaults and the process's power assertions.
@Suite(.serialized)
final class KeepAwakeTests {
    private let awake = KeepAwake()

    init() {
        Prefs.register()
        UserDefaults.standard.set(false, forKey: Prefs.awakeForAgents)
        UserDefaults.standard.set(false, forKey: Prefs.awakeDisplay)
    }

    deinit {
        awake.release()
        UserDefaults.standard.removeObject(forKey: Prefs.awakeForAgents)
        UserDefaults.standard.removeObject(forKey: Prefs.awakeDisplay)
    }

    /// Names and types of the power assertions this test process currently holds.
    private func assertions() -> [(name: String, type: String)] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let all = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return (all[NSNumber(value: getpid())] ?? []).map {
            ($0[kIOPMAssertionNameKey] as? String ?? "", $0[kIOPMAssertionTypeKey] as? String ?? "")
        }
    }

    @Test func offByDefault() {
        awake.update()
        #expect(!awake.manual)
        #expect(assertions().isEmpty)
    }

    @Test func timedSession() throws {
        awake.set(.hours(2))
        #expect(awake.manual)
        let until = try #require(awake.until)
        #expect(abs(until.timeIntervalSinceNow - 7200) < 5)
        #expect(assertions().map(\.name) == ["Keep awake"])

        awake.set(.off)
        #expect(!awake.manual)
        #expect(assertions().isEmpty)
    }

    @Test func indefinitely() {
        awake.set(.indefinitely)
        #expect(awake.until == .distantFuture)
        #expect(awake.manual)
        #expect(assertions().count == 1)
    }

    @Test func displayPreferenceSwitchesAssertionType() {
        awake.set(.indefinitely)
        #expect(assertions().map(\.type) == [kIOPMAssertPreventUserIdleSystemSleep as String])

        UserDefaults.standard.set(true, forKey: Prefs.awakeDisplay)
        awake.update()
        #expect(assertions().map(\.type) == [kIOPMAssertPreventUserIdleDisplaySleep as String])
    }

    @Test func agentModeFollowsRecentActivity() {
        awake.agentActivity = Date()
        awake.update()
        #expect(!awake.agentsWorking, "agent mode is opt in")
        #expect(assertions().isEmpty)

        UserDefaults.standard.set(true, forKey: Prefs.awakeForAgents)
        awake.update()
        #expect(awake.agentsWorking)
        #expect(assertions().map(\.name) == ["Claude Code or Grok is working"])

        awake.agentActivity = Date().addingTimeInterval(-KeepAwake.agentGrace - 1)
        awake.update()
        #expect(!awake.agentsWorking)
        #expect(assertions().isEmpty)
    }

    @Test func manualTakesOverAgentAssertion() {
        UserDefaults.standard.set(true, forKey: Prefs.awakeForAgents)
        awake.agentActivity = Date()
        awake.update()
        awake.set(.hours(1))
        #expect(assertions().map(\.name) == ["Keep awake"])
    }

    @Test func statusText() {
        let store = Store()
        #expect(awakeStatus(store) == "Sleep allowed")
        store.awakeForAgents = true
        #expect(awakeStatus(store) == "Awake while Claude Code, Grok or Codex works")
        store.awakeUntil = .distantFuture
        #expect(awakeStatus(store) == "Awake indefinitely")
        store.awakeUntil = Date().addingTimeInterval(3600 + 30)
        #expect(awakeStatus(store).hasPrefix("Awake for 1h 0m, until "))
    }
}
