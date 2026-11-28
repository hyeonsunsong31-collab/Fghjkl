import Foundation

/// Mutable ordered tree used while parsing formats that address nested keys by path (TOML, YAML).
final class DataNode {
    enum Content {
        case scalar(DataValue)
        case object(DataNode)
        case list([DataNode])
    }
    var keys: [String] = []
    var values: [String: Content] = [:]
    var scalarValue: DataValue?     // set when this node stands for a scalar list item

    func child(_ key: String) -> DataNode {
        if case .object(let n)? = values[key] { return n }
        if case .list(let l)? = values[key], let last = l.last { return last }
        let n = DataNode()
        set(key, .object(n))
        return n
    }

    func set(_ key: String, _ content: Content) {
        if values[key] == nil { keys.append(key) }
        values[key] = content
    }

    func appendTable(_ key: String) -> DataNode {
        let n = DataNode()
        if case .list(var l)? = values[key] {
            l.append(n)
            values[key] = .list(l)
        } else {
            set(key, .list([n]))
        }
        return n
    }

    var value: DataValue {
        if let s = scalarValue { return s }
        return .object(keys.map { key -> DataPair in
            switch values[key]! {
            case .scalar(let v): return DataPair(key: key, value: v)
            case .object(let n): return DataPair(key: key, value: n.value)
            case .list(let l): return DataPair(key: key, value: .array(l.map(\.value)))
            }
        })
    }
}

// MARK: - INI

enum INIFormat {
    static func parse(_ text: String) -> DataValue {
        var top: [DataPair] = []
        var sections: [DataPair] = []
        var current: [DataPair]?
        var currentName = ""
        func flush() {
            if let c = current { sections.append(DataPair(key: currentName, value: .object(c))) }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = []
                continue
            }
            let sep = line.firstIndex(where: { $0 == "=" || $0 == ":" })
            guard let s = sep else { continue }
            let key = line[..<s].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: s)...].trimmingCharacters(in: .whitespaces)
            // Inline comments after whitespace.
            for marker in [" ;", " #", "\t;", "\t#"] {
                if let r = value.range(of: marker), !value.hasPrefix("\"") { value = String(value[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
            }
            let typed: DataValue
            if value.count >= 2 && (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'")) {
                typed = .string(String(value.dropFirst().dropLast()))
            } else {
                typed = DataValue.infer(value)
            }
            if current != nil { current!.append(DataPair(key: key, value: typed)) } else { top.append(DataPair(key: key, value: typed)) }
        }
        flush()
        return .object(top + sections)
    }

    static func write(_ v: DataValue) -> String {
        guard case .object(let pairs) = v else { return "value = " + v.scalarText + "\n" }
        var out: [String] = []
        let scalars = pairs.filter { !isSection($0.value) }
        for p in scalars { out.append("\(p.key) = \(iniValue(p.value))") }
        func section(_ name: String, _ value: DataValue) {
            guard case .object(let inner) = value else { return }
            if !out.isEmpty { out.append("") }
            out.append("[\(name)]")
            for p in inner where !isSection(p.value) { out.append("\(p.key) = \(iniValue(p.value))") }
            for p in inner where isSection(p.value) { section(name + "." + p.key, p.value) }
        }
        for p in pairs where isSection(p.value) { section(p.key, p.value) }
        return out.joined(separator: "\n") + "\n"
    }

    private static func isSection(_ v: DataValue) -> Bool { if case .object = v { return true }; return false }

    private static func iniValue(_ v: DataValue) -> String {
        switch v {
        case .string(let s): return s.contains(";") || s.contains("#") || s.hasPrefix(" ") || s.hasSuffix(" ") ? "\"\(s)\"" : s
        case .array(let a) where !a.allSatisfy(\.isScalar): return JSONWriter.write(v, pretty: false)
        default: return v.scalarText
        }
    }
}

/// KEY=VALUE files (.env, .properties).
enum KeyValueFormat {
    static func parse(_ text: String) -> DataValue {
        var pairs: [DataPair] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let s = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = line[..<s].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: s)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2 && (value.hasPrefix("\"") && value.hasSuffix("\"") || value.hasPrefix("'") && value.hasSuffix("'")) { value = String(value.dropFirst().dropLast()) }
            pairs.append(DataPair(key: key, value: DataValue.infer(value)))
        }
        return .object(pairs)
    }

    static func write(_ v: DataValue) -> String {
        v.flattened().map { (k, value) in
            let key = k.uppercased().replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "-", with: "_")
            let s = value.scalarText
            return "\(key)=\(s.contains(" ") || s.contains("#") ? "\"\(s)\"" : s)"
        }.joined(separator: "\n") + "\n"
    }
}

// MARK: - YAML (the common subset: block mappings and sequences, flow collections, block scalars)

enum YAMLFormat {
    private struct Line { var indent: Int; var text: String; var number: Int }

    static func parse(_ text: String) throws -> DataValue {
        var lines: [Line] = []
        var blockScalarIndent: Int?
        for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
            let indent = raw.prefix { $0 == " " }.count
            let body = String(raw.dropFirst(indent))
            if let b = blockScalarIndent {
                if body.isEmpty || indent > b { lines.append(Line(indent: indent, text: body, number: n + 1)); continue }
                blockScalarIndent = nil
            }
            let stripped = stripComment(body).trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped == "---" || stripped == "..." || stripped.hasPrefix("%") { continue }
            lines.append(Line(indent: indent, text: stripped, number: n + 1))
            if stripped.hasSuffix("|") || stripped.hasSuffix(">") || stripped.hasSuffix("|-") || stripped.hasSuffix(">-") { blockScalarIndent = indent }
        }
        var i = 0
        guard !lines.isEmpty else { return .null }
        return try block(&i, lines, indent: lines[0].indent)
    }

    private static func stripComment(_ s: String) -> String {
        var inSingle = false, inDouble = false
        var prev: Character = " "
        for (k, ch) in s.enumerated() {
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle && prev != "\\" { inDouble.toggle() }
            if ch == "#" && !inSingle && !inDouble && (k == 0 || prev == " " || prev == "\t") {
                return String(s.prefix(k))
            }
            prev = ch
        }
        return s
    }

    private static func block(_ i: inout Int, _ lines: [Line], indent: Int) throws -> DataValue {
        guard i < lines.count else { return .null }
        if lines[i].text.hasPrefix("- ") || lines[i].text == "-" {
            var items: [DataValue] = []
            while i < lines.count && lines[i].indent == indent && (lines[i].text.hasPrefix("- ") || lines[i].text == "-") {
                let rest = lines[i].text == "-" ? "" : String(lines[i].text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let itemIndent = indent + 2
                if rest.isEmpty {
                    i += 1
                    items.append(i < lines.count && lines[i].indent > indent ? try block(&i, lines, indent: lines[i].indent) : .null)
                } else if let (key, value) = splitKey(rest), !rest.hasPrefix("\""), !rest.hasPrefix("'"), !rest.hasPrefix("{") {
                    // "- key: value" starts a mapping item; its other keys sit at indent + 2.
                    var pairs: [DataPair] = []
                    i += 1
                    pairs.append(DataPair(key: key, value: try mappingValue(value, &i, lines, parentIndent: itemIndent - 1)))
                    while i < lines.count && lines[i].indent == itemIndent && !lines[i].text.hasPrefix("- ") {
                        guard let (k, v) = splitKey(lines[i].text) else { throw DataFormatError.syntax("expected key: value", line: lines[i].number) }
                        i += 1
                        pairs.append(DataPair(key: k, value: try mappingValue(v, &i, lines, parentIndent: itemIndent)))
                    }
                    items.append(.object(pairs))
                } else {
                    items.append(try scalar(rest))
                    i += 1
                }
            }
            return .array(items)
        }
        if splitKey(lines[i].text) != nil {
            var pairs: [DataPair] = []
            while i < lines.count && lines[i].indent == indent {
                guard let (key, value) = splitKey(lines[i].text) else { throw DataFormatError.syntax("expected key: value", line: lines[i].number) }
                i += 1
                pairs.append(DataPair(key: key, value: try mappingValue(value, &i, lines, parentIndent: indent)))
            }
            return .object(pairs)
        }
        let v = try scalar(lines[i].text)
        i += 1
        return v
    }

    private static func mappingValue(_ value: String, _ i: inout Int, _ lines: [Line], parentIndent: Int) throws -> DataValue {
        if value == "|" || value == ">" || value == "|-" || value == ">-" {
            var collected: [String] = []
            var blockIndent: Int?
            while i < lines.count && (lines[i].indent > parentIndent || lines[i].text.isEmpty) {
                if blockIndent == nil && !lines[i].text.isEmpty { blockIndent = lines[i].indent }
                let extra = Swift.max(0, lines[i].indent - (blockIndent ?? lines[i].indent))
                collected.append(String(repeating: " ", count: extra) + lines[i].text)
                i += 1
            }
            let joined = value.hasPrefix("|") ? collected.joined(separator: "\n") : collected.joined(separator: " ")
            return .string(value.hasSuffix("-") ? joined : joined + "\n")
        }
        if value.isEmpty {
            if i < lines.count && (lines[i].indent > parentIndent || (lines[i].indent == parentIndent && lines[i].text.hasPrefix("- "))) {
                return try block(&i, lines, indent: lines[i].indent)
            }
            return .null
        }
        return try scalar(value)
    }

    /// "key: value" → (key, value); nil when the line has no mapping colon.
    private static func splitKey(_ s: String) -> (String, String)? {
        var inQuote: Character?
        var depth = 0
        let chars = Array(s)
        for (k, ch) in chars.enumerated() {
            if let q = inQuote { if ch == q { inQuote = nil }; continue }
            if ch == "\"" || ch == "'" { if k == 0 { inQuote = ch }; continue }
            if ch == "[" || ch == "{" { depth += 1 }
            if ch == "]" || ch == "}" { depth -= 1 }
            if ch == ":" && depth == 0 && (k == chars.count - 1 || chars[k + 1] == " ") {
                var key = String(chars[0..<k]).trimmingCharacters(in: .whitespaces)
                if key.count >= 2 && (key.hasPrefix("\"") && key.hasSuffix("\"") || key.hasPrefix("'") && key.hasSuffix("'")) { key = String(key.dropFirst().dropLast()) }
                let value = k + 1 < chars.count ? String(chars[(k + 1)...]).trimmingCharacters(in: .whitespaces) : ""
                return (key, value)
            }
        }
        return nil
    }

    static func scalar(_ s: String) throws -> DataValue {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[") || t.hasPrefix("{") {
            // Flow collections: reuse the lenient JSON parser after quoting bare words.
            if let v = try? JSONValueParser.parse(t) { return v }
            return try flow(t)
        }
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 { return .string((try? JSONValueParser.parse(t)).map { $0.scalarText } ?? String(t.dropFirst().dropLast())) }
        if t.hasPrefix("'") && t.hasSuffix("'") && t.count >= 2 { return .string(String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")) }
        return DataValue.infer(t)
    }

    private static func flow(_ t: String) throws -> DataValue {
        let chars = Array(t)
        var i = 0
        func parse() throws -> DataValue {
            while i < chars.count && chars[i] == " " { i += 1 }
            guard i < chars.count else { return .null }
            if chars[i] == "[" {
                i += 1
                var items: [DataValue] = []
                while i < chars.count && chars[i] != "]" {
                    items.append(try parse())
                    while i < chars.count && (chars[i] == " " || chars[i] == ",") { i += 1 }
                }
                i += 1
                return .array(items)
            }
            if chars[i] == "{" {
                i += 1
                var pairs: [DataPair] = []
                while i < chars.count && chars[i] != "}" {
                    while i < chars.count && chars[i] == " " { i += 1 }
                    let start = i
                    while i < chars.count && chars[i] != ":" && chars[i] != "}" { i += 1 }
                    let key = String(chars[start..<i]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    if i < chars.count && chars[i] == ":" { i += 1 }
                    pairs.append(DataPair(key: key, value: try parse()))
                    while i < chars.count && (chars[i] == " " || chars[i] == ",") { i += 1 }
                }
                i += 1
                return .object(pairs)
            }
            let start = i
            var quote: Character?
            while i < chars.count {
                let c = chars[i]
                if let q = quote { if c == q { quote = nil } } else if c == "\"" || c == "'" { quote = c } else if c == "," || c == "]" || c == "}" { break }
                i += 1
            }
            return try scalar(String(chars[start..<i]))
        }
        return try parse()
    }

    static func write(_ v: DataValue) -> String {
        var out: [String] = []
        emit(v, indent: 0, into: &out)
        return out.joined(separator: "\n") + "\n"
    }

    private static func emit(_ v: DataValue, indent: Int, into out: inout [String]) {
        let pad = String(repeating: "  ", count: indent)
        switch v {
        case .object(let pairs):
            if pairs.isEmpty { out.append(pad + "{}"); return }
            for p in pairs {
                switch p.value {
                case .object(let inner) where !inner.isEmpty:
                    out.append(pad + key(p.key) + ":")
                    emit(p.value, indent: indent + 1, into: &out)
                case .array(let items) where !items.isEmpty:
                    out.append(pad + key(p.key) + ":")
                    emit(p.value, indent: indent + 1, into: &out)
                default:
                    out.append(pad + key(p.key) + ": " + scalarText(p.value))
                }
            }
        case .array(let items):
            if items.isEmpty { out.append(pad + "[]"); return }
            for item in items {
                switch item {
                case .object(let pairs) where !pairs.isEmpty:
                    var sub: [String] = []
                    emit(item, indent: indent + 1, into: &sub)
                    if let first = sub.first {
                        out.append(pad + "- " + first.dropFirst((indent + 1) * 2))
                        out.append(contentsOf: sub.dropFirst())
                    }
                case .array(let inner) where !inner.isEmpty:
                    out.append(pad + "-")
                    emit(item, indent: indent + 1, into: &out)
                default:
                    out.append(pad + "- " + scalarText(item))
                }
            }
        default:
            out.append(pad + scalarText(v))
        }
    }

    private static func key(_ k: String) -> String {
        k.isEmpty || k.contains(":") || k.contains("#") || k.hasPrefix(" ") || k.contains("\"") ? JSONWriter.escape(k) : k
    }

    private static func scalarText(_ v: DataValue) -> String {
        switch v {
        case .null: return "null"
        case .string(let s):
            let needsQuote = s.isEmpty || s.contains(": ") || s.contains(" #") || s.hasPrefix(" ") || s.hasSuffix(" ") || s.contains("\n")
                || "-?:,[]{}#&*!|>'\"%@`".contains(s.first!) || DataValue.infer(s) != .string(s)
            return needsQuote ? JSONWriter.escape(s) : s
        case .object, .array: return JSONWriter.write(v, pretty: false)
        default: return v.scalarText
        }
    }
}

// MARK: - TOML (tables, arrays of tables, dotted keys, inline tables, multi-line arrays)

enum TOMLFormat {
    static func parse(_ text: String) throws -> DataValue {
        let root = DataNode()
        var current = root
        let lines = text.components(separatedBy: .newlines)
        var n = 0
        while n < lines.count {
            var line = stripComment(lines[n]).trimmingCharacters(in: .whitespaces)
            let lineNumber = n + 1
            n += 1
            if line.isEmpty { continue }
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                let path = splitPath(String(line.dropFirst(2).dropLast(2)))
                var node = root
                for p in path.dropLast() { node = node.child(p) }
                current = node.appendTable(path.last ?? "")
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = root
                for p in splitPath(String(line.dropFirst().dropLast())) { current = current.child(p) }
                continue
            }
            guard let eq = indexOfEquals(line) else { throw DataFormatError.syntax("expected key = value", line: lineNumber) }
            // Multi-line arrays and strings continue on the next lines.
            while !balanced(String(line[line.index(after: eq)...])) && n < lines.count {
                line += "\n" + stripComment(lines[n])
                n += 1
            }
            let keyPath = splitPath(String(line[..<eq]))
            let valueText = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            var node = current
            for p in keyPath.dropLast() { node = node.child(p) }
            node.set(keyPath.last ?? "", .scalar(try value(valueText, line: lineNumber)))
        }
        return root.value
    }

    private static func stripComment(_ s: String) -> String {
        var inBasic = false, inLiteral = false
        var prev: Character = " "
        for (k, ch) in s.enumerated() {
            if ch == "\"" && !inLiteral && prev != "\\" { inBasic.toggle() }
            if ch == "'" && !inBasic { inLiteral.toggle() }
            if ch == "#" && !inBasic && !inLiteral { return String(s.prefix(k)) }
            prev = ch
        }
        return s
    }

    private static func indexOfEquals(_ s: String) -> String.Index? {
        var quote: Character?
        for idx in s.indices {
            let ch = s[idx]
            if let q = quote { if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; continue }
            if ch == "=" { return idx }
        }
        return nil
    }

    private static func balanced(_ s: String) -> Bool {
        var depth = 0
        var quote: Character?
        var triple = 0
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"\"\"") || t.hasPrefix("'''") {
            let marker = String(t.prefix(3))
            triple = t.components(separatedBy: marker).count - 1
            return triple >= 2
        }
        for ch in s {
            if let q = quote { if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch }
            else if ch == "[" || ch == "{" { depth += 1 }
            else if ch == "]" || ch == "}" { depth -= 1 }
        }
        return depth <= 0
    }

    private static func splitPath(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { quote = ch; continue }
            if ch == "." { parts.append(current.trimmingCharacters(in: .whitespaces)); current = ""; continue }
            current.append(ch)
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    static func value(_ raw: String, line: Int) throws -> DataValue {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("\"\"\"") {
            var body = String(t.dropFirst(3).dropLast(3))
            if body.hasPrefix("\n") { body.removeFirst() }
            return .string(body)
        }
        if t.hasPrefix("'''") {
            var body = String(t.dropFirst(3).dropLast(3))
            if body.hasPrefix("\n") { body.removeFirst() }
            return .string(body)
        }
        if t.hasPrefix("\"") { return .string((try? JSONValueParser.parse(t)).map(\.scalarText) ?? String(t.dropFirst().dropLast())) }
        if t.hasPrefix("'") { return .string(String(t.dropFirst().dropLast())) }
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if t.hasPrefix("[") {
            let inner = String(t.dropFirst().dropLast())
            return .array(try splitTopLevel(inner).map { try value($0, line: line) })
        }
        if t.hasPrefix("{") {
            let inner = String(t.dropFirst().dropLast())
            let node = DataNode()
            for item in try splitTopLevel(inner) {
                guard let eq = indexOfEquals(item) else { throw DataFormatError.syntax("bad inline table", line: line) }
                let path = splitPath(String(item[..<eq]))
                var target = node
                for p in path.dropLast() { target = target.child(p) }
                target.set(path.last ?? "", .scalar(try value(String(item[item.index(after: eq)...]), line: line)))
            }
            return node.value
        }
        let numeric = t.replacingOccurrences(of: "_", with: "")
        if let i = Int(numeric) { return .int(i) }
        if numeric.hasPrefix("0x"), let i = Int(numeric.dropFirst(2), radix: 16) { return .int(i) }
        if numeric.hasPrefix("0o"), let i = Int(numeric.dropFirst(2), radix: 8) { return .int(i) }
        if numeric.hasPrefix("0b"), let i = Int(numeric.dropFirst(2), radix: 2) { return .int(i) }
        if let d = Double(numeric) { return .double(d) }
        if t == "inf" || t == "+inf" { return .double(.infinity) }
        if t.isEmpty { throw DataFormatError.syntax("missing value", line: line) }
        return .string(t)   // dates and times stay as text
    }

    private static func splitTopLevel(_ s: String) throws -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for ch in s {
            if let q = quote { current.append(ch); if ch == q { quote = nil }; continue }
            if ch == "\"" || ch == "'" { quote = ch; current.append(ch); continue }
            if ch == "[" || ch == "{" { depth += 1 }
            if ch == "]" || ch == "}" { depth -= 1 }
            if ch == "," && depth == 0 {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(current) }
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(current) }
        return items
    }

    static func write(_ v: DataValue) -> String {
        guard case .object(let pairs) = v else { return "value = " + inline(v) + "\n" }
        var out: [String] = []
        emitTable(pairs, path: [], into: &out)
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func isTable(_ v: DataValue) -> Bool { if case .object = v { return true }; return false }
    private static func isTableArray(_ v: DataValue) -> Bool {
        if case .array(let a) = v, !a.isEmpty { return a.allSatisfy(isTable) }
        return false
    }

    private static func emitTable(_ pairs: [DataPair], path: [String], into out: inout [String]) {
        for p in pairs where !isTable(p.value) && !isTableArray(p.value) {
            out.append(key(p.key) + " = " + inline(p.value))
        }
        for p in pairs where isTable(p.value) {
            guard case .object(let inner) = p.value else { continue }
            out.append("")
            out.append("[" + (path + [p.key]).map(key).joined(separator: ".") + "]")
            emitTable(inner, path: path + [p.key], into: &out)
        }
        for p in pairs where isTableArray(p.value) {
            guard case .array(let items) = p.value else { continue }
            for item in items {
                guard case .object(let inner) = item else { continue }
                out.append("")
                out.append("[[" + (path + [p.key]).map(key).joined(separator: ".") + "]]")
                emitTable(inner, path: path + [p.key], into: &out)
            }
        }
    }

    private static func key(_ k: String) -> String {
        k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } && !k.isEmpty ? k : JSONWriter.escape(k)
    }

    private static func inline(_ v: DataValue) -> String {
        switch v {
        case .null: return "\"\""
        case .string(let s): return JSONWriter.escape(s)
        case .array(let a): return "[" + a.map(inline).joined(separator: ", ") + "]"
        case .object(let pairs): return "{ " + pairs.map { key($0.key) + " = " + inline($0.value) }.joined(separator: ", ") + " }"
        default: return v.scalarText
        }
    }
}

// MARK: - CSV / TSV

enum CSVFormat {
    static func rows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func parse(_ text: String, delimiter: Character = ",") -> DataValue {
        let r = rows(text, delimiter: delimiter)
        guard let header = r.first else { return .array([]) }
        return .array(r.dropFirst().map { cells in
            .object(header.enumerated().map { (k, name) in
                DataPair(key: name, value: k < cells.count ? DataValue.infer(cells[k]) : .null)
            })
        })
    }

    static func write(_ v: DataValue, delimiter: Character = ",") -> String {
        var records: [[DataPair]] = []
        switch v {
        case .array(let items):
            for item in items {
                if case .object(let pairs) = item { records.append(pairs) } else { records.append([DataPair(key: "value", value: item)]) }
            }
        case .object(let pairs):
            // A single object: one row, or a table under its only array key.
            if pairs.count == 1, case .array = pairs[0].value { return write(pairs[0].value, delimiter: delimiter) }
            records.append(pairs.flatMap { p -> [DataPair] in
                p.value.flattened(prefix: p.key).map { DataPair(key: $0.0, value: $0.1) }
            })
        default:
            records.append([DataPair(key: "value", value: v)])
        }
        var header: [String] = []
        for r in records { for p in r where !header.contains(p.key) { header.append(p.key) } }
        func cell(_ value: DataValue?) -> String {
            guard let value else { return "" }
            let s = value.isScalar ? value.scalarText : JSONWriter.write(value, pretty: false)
            return s.contains(delimiter) || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var lines = [header.map { cell(.string($0)) }.joined(separator: String(delimiter))]
        for r in records {
            lines.append(header.map { h in cell(r.first { $0.key == h }?.value) }.joined(separator: String(delimiter)))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - XML and property lists

final class XMLNode {
    var name: String
    var attributes: [(String, String)] = []
    var children: [XMLNode] = []
    var text = ""

    init(name: String) { self.name = name }
}

enum XMLFormat {
    static func parseTree(_ text: String) throws -> XMLNode {
        let s = Array(text.unicodeScalars)
        var i = 0
        let root = XMLNode(name: "#document")
        var stack = [root]
        func line() -> Int { s[0..<Swift.min(i, s.count)].filter { $0 == "\n" }.count + 1 }
        while i < s.count {
            if s[i] == "<" {
                if starts(s, i, "<!--") {
                    i = find(s, i + 4, "-->").map { $0 + 3 } ?? s.count
                } else if starts(s, i, "<![CDATA[") {
                    let end = find(s, i + 9, "]]>") ?? s.count
                    stack.last!.text += String(String.UnicodeScalarView(s[(i + 9)..<end]))
                    i = end + 3
                } else if starts(s, i, "<?") || starts(s, i, "<!") {
                    // Prolog, processing instructions, DOCTYPE (with an optional internal subset).
                    var depth = 0
                    while i < s.count {
                        if s[i] == "[" { depth += 1 }
                        if s[i] == "]" { depth -= 1 }
                        if s[i] == ">" && depth <= 0 { break }
                        i += 1
                    }
                    i += 1
                } else if i + 1 < s.count && s[i + 1] == "/" {
                    let end = find(s, i, ">") ?? s.count
                    let name = String(String.UnicodeScalarView(s[(i + 2)..<end])).trimmingCharacters(in: .whitespaces)
                    guard stack.count > 1, stack.last!.name == name else { throw DataFormatError.syntax("unexpected </\(name)>", line: line()) }
                    stack.removeLast()
                    i = end + 1
                } else {
                    var end = i + 1
                    var quote: Unicode.Scalar?
                    while end < s.count {
                        if let q = quote { if s[end] == q { quote = nil } } else if s[end] == "\"" || s[end] == "'" { quote = s[end] } else if s[end] == ">" { break }
                        end += 1
                    }
                    guard end < s.count else { throw DataFormatError.syntax("unterminated tag", line: line()) }
                    var inside = String(String.UnicodeScalarView(s[(i + 1)..<end]))
                    let selfClosing = inside.hasSuffix("/")
                    if selfClosing { inside.removeLast() }
                    let node = try element(inside, line: line())
                    stack.last!.children.append(node)
                    if !selfClosing { stack.append(node) }
                    i = end + 1
                }
            } else {
                let end = find(s, i, "<") ?? s.count
                let raw = String(String.UnicodeScalarView(s[i..<end]))
                stack.last!.text += decodeEntities(raw)
                i = end
            }
        }
        guard stack.count == 1 else { throw DataFormatError.syntax("<\(stack.last!.name)> is never closed", line: line()) }
        guard let top = root.children.first else { throw DataFormatError.syntax("no root element", line: 1) }
        return top
    }

    private static func element(_ inside: String, line: Int) throws -> XMLNode {
        let trimmed = inside.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameEnd = trimmed.firstIndex(where: { $0.isWhitespace }) ?? trimmed.endIndex
        let node = XMLNode(name: String(trimmed[..<nameEnd]))
        var rest = Substring(trimmed[nameEnd...])
        while true {
            rest = rest.drop { $0.isWhitespace }
            guard let eq = rest.firstIndex(of: "=") else { break }
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: eq)...].drop { $0.isWhitespace }
            guard let q = rest.first, q == "\"" || q == "'" else { throw DataFormatError.syntax("attribute \(key) needs quotes", line: line) }
            rest = rest.dropFirst()
            guard let close = rest.firstIndex(of: q) else { throw DataFormatError.syntax("unterminated attribute", line: line) }
            node.attributes.append((key, decodeEntities(String(rest[..<close]))))
            rest = rest[rest.index(after: close)...]
        }
        return node
    }

    private static func starts(_ s: [Unicode.Scalar], _ i: Int, _ prefix: String) -> Bool {
        let p = Array(prefix.unicodeScalars)
        guard i + p.count <= s.count else { return false }
        for k in 0..<p.count where s[i + k] != p[k] { return false }
        return true
    }

    private static func find(_ s: [Unicode.Scalar], _ from: Int, _ needle: String) -> Int? {
        let n = Array(needle.unicodeScalars)
        var i = from
        while i + n.count <= s.count {
            if starts(s, i, needle) { return i }
            i += 1
        }
        return nil
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].firstIndex(of: ";"), s.distance(from: i, to: semi) <= 10 {
                let entity = String(s[s.index(after: i)..<semi])
                var replacement: String?
                switch entity {
                case "lt": replacement = "<"
                case "gt": replacement = ">"
                case "amp": replacement = "&"
                case "quot": replacement = "\""
                case "apos": replacement = "'"
                case "nbsp": replacement = "\u{A0}"
                default:
                    if entity.hasPrefix("#x"), let v = UInt32(entity.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                    else if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst()), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
                }
                if let r = replacement {
                    out += r
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    /// XML → data: attributes as "@name", text as "#text", repeated children as arrays.
    static func parse(_ text: String) throws -> DataValue {
        let root = try parseTree(text)
        if root.name == "plist" { return try PlistFormat.value(root) }
        return .object([DataPair(key: root.name, value: value(root))])
    }

    static func value(_ node: XMLNode) -> DataValue {
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if node.attributes.isEmpty && node.children.isEmpty { return text.isEmpty ? .null : DataValue.infer(text) }
        var pairs: [DataPair] = node.attributes.map { DataPair(key: "@" + $0.0, value: DataValue.infer($0.1)) }
        var order: [String] = []
        var groups: [String: [DataValue]] = [:]
        for c in node.children {
            if groups[c.name] == nil { order.append(c.name) }
            groups[c.name, default: []].append(value(c))
        }
        for name in order {
            let items = groups[name]!
            pairs.append(DataPair(key: name, value: items.count == 1 ? items[0] : .array(items)))
        }
        if !text.isEmpty { pairs.append(DataPair(key: "#text", value: .string(text))) }
        return .object(pairs)
    }

    static func write(_ v: DataValue) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        if case .object(let pairs) = v, pairs.count == 1 {
            emit(pairs[0].key, pairs[0].value, indent: 0, into: &out)
        } else {
            emit("root", v, indent: 0, into: &out)
        }
        return out
    }

    private static func tagName(_ s: String) -> String {
        let cleaned = s.map { (c: Character) -> Character in c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." || c == ":" ? c : "_" }
        let name = String(cleaned)
        return name.first.map { $0.isLetter || $0 == "_" } == true ? name : "_" + name
    }

    private static func emit(_ name: String, _ v: DataValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "  ", count: indent)
        let tag = tagName(name)
        switch v {
        case .array(let items):
            for item in items { emit(name, item, indent: indent, into: &out) }
        case .object(let pairs):
            let attrs = pairs.filter { $0.key.hasPrefix("@") }.map { " \(tagName(String($0.key.dropFirst())))=\"\(Packager.xmlEscape($0.value.scalarText))\"" }.joined()
            let children = pairs.filter { !$0.key.hasPrefix("@") && $0.key != "#text" }
            let text = pairs.first { $0.key == "#text" }?.value.scalarText ?? ""
            if children.isEmpty {
                out += "\(pad)<\(tag)\(attrs)>\(Packager.xmlEscape(text))</\(tag)>\n"
            } else {
                out += "\(pad)<\(tag)\(attrs)>\n"
                if !text.isEmpty { out += pad + "  " + Packager.xmlEscape(text) + "\n" }
                for c in children { emit(c.key, c.value, indent: indent + 1, into: &out) }
                out += "\(pad)</\(tag)>\n"
            }
        case .null:
            out += "\(pad)<\(tag)/>\n"
        default:
            out += "\(pad)<\(tag)>\(Packager.xmlEscape(v.scalarText))</\(tag)>\n"
        }
    }
}

enum PlistFormat {
    static func value(_ node: XMLNode) throws -> DataValue {
        let n = node.name == "plist" ? (node.children.first ?? node) : node
        switch n.name {
        case "dict":
            var pairs: [DataPair] = []
            var k = 0
            while k + 1 < n.children.count {
                guard n.children[k].name == "key" else { k += 1; continue }
                pairs.append(DataPair(key: n.children[k].text, value: try value(n.children[k + 1])))
                k += 2
            }
            return .object(pairs)
        case "array": return .array(try n.children.map(value))
        case "string", "date": return .string(n.text)
        case "data": return .string(n.text.filter { !$0.isWhitespace })
        case "integer": return .int(Int(n.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        case "real": return .double(Double(n.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "plist": return .null
        default: throw DataFormatError.unsupported("unknown plist element <\(n.name)>")
        }
    }

    /// Binary property lists through Foundation (key order is not preserved there; keys are sorted).
    static func parseBinary(_ bytes: [UInt8]) throws -> DataValue {
        let object = try PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil)
        return from(object)
    }

    private static func from(_ any: Any) -> DataValue {
        switch any {
        case let d as [String: Any]: return .object(d.keys.sorted().map { DataPair(key: $0, value: from(d[$0]!)) })
        case let a as [Any]: return .array(a.map(from))
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let i as Int: return .int(i)
        case let n as Double: return .double(n)
        case let date as Date: return .string(ISO8601DateFormatter().string(from: date))
        case let data as Data: return .string(data.base64EncodedString())
        default: return .string(String(describing: any))
        }
    }

    static func write(_ v: DataValue) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """
        emit(v, indent: 0, into: &out)
        return out + "</plist>\n"
    }

    private static func emit(_ v: DataValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "\t", count: indent)
        switch v {
        case .null: out += "\(pad)<string></string>\n"
        case .bool(let b): out += "\(pad)<\(b ? "true" : "false")/>\n"
        case .int(let i): out += "\(pad)<integer>\(i)</integer>\n"
        case .double(let d): out += "\(pad)<real>\(d)</real>\n"
        case .string(let s): out += "\(pad)<string>\(Packager.xmlEscape(s))</string>\n"
        case .array(let items):
            out += "\(pad)<array>\n"
            for item in items { emit(item, indent: indent + 1, into: &out) }
            out += "\(pad)</array>\n"
        case .object(let pairs):
            out += "\(pad)<dict>\n"
            for p in pairs {
                out += "\(pad)\t<key>\(Packager.xmlEscape(p.key))</key>\n"
                emit(p.value, indent: indent + 1, into: &out)
            }
            out += "\(pad)</dict>\n"
        }
    }
}
