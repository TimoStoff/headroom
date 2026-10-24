import Foundation
import Testing
@testable import Headroom

struct ClaudeAccountsTests {
    @Test func keychainServiceHashesConfigPath() {
        // Checked against the entry Claude Code 2.1 created for CLAUDE_CONFIG_DIR=/Users/sanc/.claude-work.
        #expect(ClaudeLimitsClient.keychainService("/Users/sanc/.claude-work") == "Claude Code-credentials-6e0b6930")
    }

    @Test func rowsGroupLimitsByNameAcrossAccounts() {
        func e(_ name: String, _ p: Double) -> LimitEntry { LimitEntry(id: name, name: name, percent: p) }
        let a = ClaudeLimits(all: [e("Session (5h)", 2), e("Weekly", 28), e("Weekly Fable", 2)], fetchedAt: Date())
        let b = ClaudeLimits(all: [e("Weekly", 40), e("Weekly Sonnet", 5), e("Session (5h)", 10)], fetchedAt: Date(), account: "Work")
        let rows = limitRows([a, b])
        #expect(rows.map { $0[0].entry.name } == ["Session (5h)", "Weekly", "Weekly Fable", "Weekly Sonnet"])
        #expect(rows[0].map(\.account) == [0, 1])
        #expect(rows[1].map(\.entry.percent) == [28, 40])
        #expect(rows[3].map(\.account) == [1])
    }
}
