import Foundation

/// A key/value pair of an ordered object (key order matters to people reading converted files).
struct DataPair: Equatable {
    var key: String
    var value: DataValue
}

/// Structured data shared by every text data format (JSON, YAML, TOML, INI, XML, plist, CSV).
indirect enum DataValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([DataValue])
    case object([DataPair])

    subscript(key: String) -> DataValue? {
        if case .object(let pairs) = self { return pairs.first { $0.key == key }?.value }
        return nil
    }

    var isScalar: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }

    /// Text form of a scalar (for INI, CSV, XML text).
    var scalarText: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : String(d)
        case .string(let s): return s
        case .array(let a): return a.map(\.scalarText).joined(separator: ",")
        case .object: return ""
        }
    }

    /// Infer a typed scalar from text ("42" → int, "true" → bool), as INI/CSV values carry no types.
    static func infer(_ text: String) -> DataValue {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() {
        case "true", "yes", "on": return .bool(true)
        case "false", "no", "off": return .bool(false)
        case "null", "~": return .null
        default: break
        }
        if let i = Int(t), !(t.hasPrefix("0") && t.count > 1) { return .int(i) }
        if t.contains("."), let d = Double(t), !t.hasPrefix("."), t.rangeOfCharacter(from: .letters) == nil { return .double(d) }
        return .string(text)
    }

    /// Flatten nested objects into dotted keys ("server.port") for flat formats.
    func flattened(prefix: String = "") -> [(String, DataValue)] {
        switch self {
        case .object(let pairs):
            var out: [(String, DataValue)] = []
            for p in pairs { out += p.value.flattened(prefix: prefix.isEmpty ? p.key : prefix + "." + p.key) }
            return out
        default:
            return [(prefix, self)]
        }
    }
}

enum DataFormatError: Error, CustomStringConvertible {
    case syntax(String, line: Int)
    case unsupported(String)

    var description: String {
        switch self {
        case .syntax(let s, let line): return "syntax error on line \(line): \(s)"
        case .unsupported(let s): return s
        }
    }
}

// MARK: - JSON

/// Order-preserving JSON parser (also accepts comments and trailing commas).
enum JSONValueParser {
    static func parse(_ text: String) throws -> DataValue {
        var p = Parser(Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i >= p.s.count else { throw DataFormatError.syntax("unexpected text after the JSON value", line: p.line) }
        return v
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        var line: Int { s[0..<Swift.min(i, s.count)].filter { $0 == "\n" }.count + 1 }

        mutating func skipSpace() {
            while i < s.count {
                let c = s[i]
                if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{FEFF}" { i += 1; continue }
                if c == "/" && i + 1 < s.count && s[i + 1] == "/" {
                    while i < s.count && s[i] != "\n" { i += 1 }
                    continue
                }
                if c == "/" && i + 1 < s.count && s[i + 1] == "*" {
                    i += 2
                    while i + 1 < s.count && !(s[i] == "*" && s[i + 1] == "/") { i += 1 }
                    i += 2
                    continue
                }
                break
            }
        }

        mutating func value() throws -> DataValue {
            guard i < s.count else { throw DataFormatError.syntax("unexpected end", line: line) }
            switch s[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"", "'": return .string(try string())
            case "t": try literal("true"); return .bool(true)
            case "f": try literal("false"); return .bool(false)
            case "n": try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            for ch in word.unicodeScalars {
                guard i < s.count, s[i] == ch else { throw DataFormatError.syntax("expected \(word)", line: line) }
                i += 1
            }
        }

        mutating func object() throws -> DataValue {
            i += 1
            var pairs: [DataPair] = []
            skipSpace()
            while i < s.count && s[i] != "}" {
                let key: String
                if s[i] == "\"" || s[i] == "'" { key = try string() } else {
                    // Unquoted keys (JSON5 style).
                    let start = i
                    while i < s.count && (CharacterSet.alphanumerics.contains(s[i]) || s[i] == "_" || s[i] == "$") { i += 1 }
                    guard i > start else { throw DataFormatError.syntax("expected a key", line: line) }
                    key = String(String.UnicodeScalarView(s[start..<i]))
                }
                skipSpace()
                guard i < s.count, s[i] == ":" else { throw DataFormatError.syntax("expected ':' after \"\(key)\"", line: line) }
                i += 1
                skipSpace()
                pairs.append(DataPair(key: key, value: try value()))
                skipSpace()
                if i < s.count && s[i] == "," { i += 1; skipSpace() } else { break }
            }
            guard i < s.count, s[i] == "}" else { throw DataFormatError.syntax("expected '}'", line: line) }
            i += 1
            return .object(pairs)
        }

        mutating func array() throws -> DataValue {
            i += 1
            var items: [DataValue] = []
            skipSpace()
            while i < s.count && s[i] != "]" {
                items.append(try value())
                skipSpace()
                if i < s.count && s[i] == "," { i += 1; skipSpace() } else { break }
            }
            guard i < s.count, s[i] == "]" else { throw DataFormatError.syntax("expected ']'", line: line) }
            i += 1
            return .array(items)
        }

        mutating func string() throws -> String {
            let quote = s[i]
            i += 1
            var out = String.UnicodeScalarView()
            while i < s.count && s[i] != quote {
                if s[i] == "\\" {
                    i += 1
                    guard i < s.count else { break }
                    switch s[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "b": out.append("\u{8}")
                    case "f": out.append("\u{C}")
                    case "u":
                        guard i + 4 < s.count, let v = UInt32(String(String.UnicodeScalarView(s[(i + 1)...(i + 4)])), radix: 16) else {
                            throw DataFormatError.syntax("bad \\u escape", line: line)
                        }
                        i += 4
                        if v >= 0xD800 && v < 0xDC00, i + 6 < s.count, s[i + 1] == "\\", s[i + 2] == "u",
                           let low = UInt32(String(String.UnicodeScalarView(s[(i + 3)...(i + 6)])), radix: 16), low >= 0xDC00 && low < 0xE000 {
                            i += 6
                            out.append(Unicode.Scalar(0x10000 + ((v - 0xD800) << 10) + (low - 0xDC00)) ?? "?")
                        } else {
                            out.append(Unicode.Scalar(v) ?? "?")
                        }
                    default: out.append(s[i])
                    }
                    i += 1
                } else {
                    out.append(s[i])
                    i += 1
                }
            }
            guard i < s.count else { throw DataFormatError.syntax("unterminated string", line: line) }
            i += 1
            return String(out)
        }

        mutating func number() throws -> DataValue {
            let start = i
            while i < s.count && "+-0123456789.eExXabcdefABCDEF_".unicodeScalars.contains(s[i]) { i += 1 }
            let text = String(String.UnicodeScalarView(s[start..<i])).replacingOccurrences(of: "_", with: "")
            if let v = Int(text) { return .int(v) }
            if text.lowercased().hasPrefix("0x"), let v = Int(text.dropFirst(2), radix: 16) { return .int(v) }
            if let d = Double(text) { return .double(d) }
            throw DataFormatError.syntax(text.isEmpty ? "unexpected character" : "bad number \(text)", line: line)
        }
    }
}

enum JSONWriter {
    static func write(_ v: DataValue, pretty: Bool = true) -> String {
        var out = ""
        emit(v, indent: 0, pretty: pretty, into: &out)
        return out + (pretty ? "\n" : "")
    }

    static func escape(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    private static func emit(_ v: DataValue, indent: Int, pretty: Bool, into out: inout String) {
        let pad = pretty ? String(repeating: "  ", count: indent + 1) : ""
        let close = pretty ? String(repeating: "  ", count: indent) : ""
        let nl = pretty ? "\n" : ""
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += d.isFinite ? (d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : String(d)) : "null"
        case .string(let s): out += escape(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            if items.allSatisfy(\.isScalar) && pretty && items.count <= 12 {
                out += "[" + items.map { write($0, pretty: false) }.joined(separator: ", ") + "]"
                return
            }
            out += "[" + nl
            for (k, item) in items.enumerated() {
                out += pad
                emit(item, indent: indent + 1, pretty: pretty, into: &out)
                out += (k < items.count - 1 ? "," : "") + nl
            }
            out += close + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{" + nl
            for (k, p) in pairs.enumerated() {
                out += pad + escape(p.key) + (pretty ? ": " : ":")
                emit(p.value, indent: indent + 1, pretty: pretty, into: &out)
                out += (k < pairs.count - 1 ? "," : "") + nl
            }
            out += close + "}"
        }
    }
}
