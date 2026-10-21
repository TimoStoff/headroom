import Foundation
import SQLite3
import Testing
@testable import Headroom

@Test func openCodeTurnsAreBucketedPerHourAndModel() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("opencode-\(UUID()).db").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    var db: OpaquePointer?
    #expect(sqlite3_open(path, &db) == SQLITE_OK)
    let hour: Int64 = 500_000 * 3_600_000
    let turn = #"{"model":{"id":"glm-5.3"},"tokens":{"input":10,"output":5,"reasoning":2,"cache":{"read":100,"write":1}}}"#
    let sql = """
        CREATE TABLE session_message (id text PRIMARY KEY, session_id text, type text, seq integer,
                                      time_created integer, time_updated integer, data text);
        INSERT INTO session_message VALUES ('a', 's', 'assistant', 1, \(hour), \(hour + 9), '\(turn)');
        INSERT INTO session_message VALUES ('b', 's', 'assistant', 2, \(hour + 60_000), \(hour + 61_000), '\(turn)');
        INSERT INTO session_message VALUES ('c', 's', 'user', 3, \(hour), \(hour), '{"tokens":{"input":999}}');
        INSERT INTO session_message VALUES ('d', 's', 'assistant', 4, \(hour), \(hour), '{"model":{"id":"glm-5.3"}}');
        INSERT INTO session_message VALUES ('e', 's', 'assistant', 5, \(hour - 3_600_000), \(hour), '\(turn)');
        """
    #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)

    let r = try #require(Ledger.queryOpenCode(path, since: hour))
    #expect(r.hours.count == 1)
    let a = try #require(r.hours[500_000]?["glm-5.3"])
    #expect(a.input == 20 && a.output == 14 && a.cacheRead == 200 && a.cacheWrite5m == 2 && a.calls == 2)
    #expect(r.last == Date(timeIntervalSince1970: Double(hour + 61_000) / 1000))
    #expect(Ledger.queryOpenCode("/nonexistent/opencode.db", since: 0) == nil)
}
