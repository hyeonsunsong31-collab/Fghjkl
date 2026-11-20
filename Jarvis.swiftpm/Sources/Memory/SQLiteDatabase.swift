import Foundation
import SQLite3

/// Minimal, dependency-free SQLite wrapper (WAL mode, prepared statements).
final class SQLiteDatabase {
    enum DBError: Error, CustomStringConvertible {
        case open(String), prepare(String), step(String)
        var description: String {
            switch self {
            case .open(let m): return "open: \(m)"
            case .prepare(let m): return "prepare: \(m)"
            case .step(let m): return "step: \(m)"
            }
        }
    }

    enum Value {
        case text(String), int(Int64), real(Double), null

        static func optionalText(_ s: String?) -> Value { s.map { .text($0) } ?? .null }
        static func optionalReal(_ d: Double?) -> Value { d.map { .real($0) } ?? .null }
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw DBError.open(String(cString: sqlite3_errmsg(db)))
        }
        handle = db
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit { sqlite3_close_v2(handle) }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? lastError
            sqlite3_free(err)
            throw DBError.step(message)
        }
    }

    func run(_ sql: String, _ values: [Value] = []) throws {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(lastError) }
    }

    func query(_ sql: String, _ values: [Value] = []) throws -> [[String: Value]] {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Value]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError.step(lastError) }
            var row: [String: Value] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT: row[name] = .text(sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "")
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.prepare("\(lastError) — \(sql)")
        }
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}

extension Dictionary where Key == String, Value == SQLiteDatabase.Value {
    func string(_ key: String) -> String? {
        if case .text(let s)? = self[key] { return s }
        return nil
    }
    func double(_ key: String) -> Double? {
        switch self[key] {
        case .real(let d)?: return d
        case .int(let n)?: return Double(n)
        default: return nil
        }
    }
    func int(_ key: String) -> Int? {
        switch self[key] {
        case .int(let n)?: return Int(n)
        case .real(let d)?: return Int(d)
        default: return nil
        }
    }
}
