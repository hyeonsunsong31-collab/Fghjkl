import Foundation

/// Line diffs (Myers) as unified diffs, and applying unified diffs with some tolerance.
enum TextDiff {
    enum Op: Equatable { case same(String), add(String), remove(String) }

    static func diff(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        let maxD = n + m
        if maxD == 0 { return [] }
        var v = [Int](repeating: 0, count: 2 * maxD + 2)
        var trace: [[Int]] = []
        let offset = maxD + 1
        outer: for d in 0...maxD {
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) { x = v[offset + k + 1] } else { x = v[offset + k - 1] + 1 }
                var y = x - k
                while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
                v[offset + k] = x
                if x >= n && y >= m { trace.append(v); break outer }
                k += 2
            }
        }
        // Walk back through the trace.
        var ops: [Op] = []
        var x = n, y = m
        for d in stride(from: trace.count - 2, through: 0, by: -1) {
            let vd = trace[d]
            let k = x - y
            let prevK: Int
            if k == -d || (k != d && vd[offset + k - 1] < vd[offset + k + 1]) { prevK = k + 1 } else { prevK = k - 1 }
            let prevX = vd[offset + prevK]
            let prevY = prevX - prevK
            while x > prevX && y > prevY { ops.append(.same(a[x - 1])); x -= 1; y -= 1 }
            if d > 0 {
                if x == prevX { ops.append(.add(b[y - 1])); y -= 1 } else { ops.append(.remove(a[x - 1])); x -= 1 }
            }
        }
        while x > 0 && y > 0 { ops.append(.same(a[x - 1])); x -= 1; y -= 1 }
        return ops.reversed()
    }

    static func lines(_ s: String) -> [String] {
        var l = s.components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return l
    }

    /// Unified diff text ("--- a/x", "+++ b/x", "@@ -l,c +l,c @@").
    static func unified(_ old: String, _ new: String, oldName: String = "a", newName: String = "b", context: Int = 3) -> String {
        let ops = diff(lines(old), lines(new))
        var changes: [Int] = []
        var positions: [(Int, Int)] = []
        var oldLine = 1, newLine = 1
        for (i, op) in ops.enumerated() {
            positions.append((oldLine, newLine))
            switch op {
            case .same: oldLine += 1; newLine += 1
            case .add: newLine += 1; changes.append(i)
            case .remove: oldLine += 1; changes.append(i)
            }
        }
        guard !changes.isEmpty else { return "" }
        // Group changes closer than 2 × context into one hunk.
        var ranges: [(Int, Int)] = []
        var groupStart = changes[0], groupEnd = changes[0]
        for c in changes.dropFirst() {
            if c - groupEnd > 2 * context {
                ranges.append((groupStart, groupEnd))
                groupStart = c
            }
            groupEnd = c
        }
        ranges.append((groupStart, groupEnd))
        var out = ["--- \(oldName)", "+++ \(newName)"]
        for (first, last) in ranges {
            let s = Swift.max(0, first - context)
            let e = Swift.min(ops.count, last + context + 1)
            let hunk = ops[s..<e]
            let oCount = hunk.filter { if case .add = $0 { return false }; return true }.count
            let nCount = hunk.filter { if case .remove = $0 { return false }; return true }.count
            let (o, n) = positions[s]
            out.append("@@ -\(oCount == 0 ? o - 1 : o),\(oCount) +\(nCount == 0 ? n - 1 : n),\(nCount) @@")
            for op in hunk {
                switch op {
                case .same(let t): out.append(" " + t)
                case .add(let t): out.append("+" + t)
                case .remove(let t): out.append("-" + t)
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    struct Hunk {
        var oldStart: Int
        var lines: [String]   // with " ", "+", "-" prefixes
    }

    enum ApplyError: Error, CustomStringConvertible {
        case noHunks
        case mismatch(Int)
        var description: String {
            switch self {
            case .noHunks: return "the patch has no changes"
            case .mismatch(let n): return "hunk \(n) doesn't match the file"
            }
        }
    }

    static func hunks(_ patch: String) -> [Hunk] {
        var out: [Hunk] = []
        var current: Hunk?
        let body = patch.hasSuffix("\n") ? String(patch.dropLast()) : patch
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                if let c = current { out.append(c) }
                let nums = line.dropFirst(3).split(separator: " ").first?.dropFirst().split(separator: ",").first.flatMap { Int($0) } ?? 1
                current = Hunk(oldStart: nums, lines: [])
            } else if current != nil, let first = line.first, first == " " || first == "+" || first == "-" {
                if line.hasPrefix("---") || line.hasPrefix("+++") { continue }
                current!.lines.append(line)
            } else if current != nil && line.isEmpty {
                current!.lines.append(" ")
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    /// Apply a unified diff, searching near the stated line when the file has shifted.
    static func apply(_ patch: String, to text: String) throws -> String {
        var file = lines(text)
        let hs = hunks(patch)
        guard !hs.isEmpty else { throw ApplyError.noHunks }
        var shift = 0
        for (n, h) in hs.enumerated() {
            let old = h.lines.filter { !$0.hasPrefix("+") }.map { String($0.dropFirst()) }
            let new = h.lines.filter { !$0.hasPrefix("-") }.map { String($0.dropFirst()) }
            let expected = old.isEmpty ? Swift.max(0, h.oldStart + shift) : Swift.max(0, h.oldStart - 1 + shift)
            guard let at = locate(old, in: file, near: expected) else { throw ApplyError.mismatch(n + 1) }
            file.replaceSubrange(at..<(at + old.count), with: new)
            shift += new.count - old.count + (at - expected)
        }
        return file.joined(separator: "\n") + (text.hasSuffix("\n") || text.isEmpty ? "\n" : "")
    }

    private static func locate(_ block: [String], in file: [String], near: Int) -> Int? {
        if block.isEmpty { return Swift.min(near, file.count) }
        func matches(_ at: Int, loose: Bool) -> Bool {
            guard at >= 0, at + block.count <= file.count else { return false }
            for k in 0..<block.count {
                let a = file[at + k], b = block[k]
                if loose ? a.trimmingCharacters(in: .whitespaces) != b.trimmingCharacters(in: .whitespaces) : a != b { return false }
            }
            return true
        }
        for loose in [false, true] {
            for distance in 0...Swift.max(file.count, 1) {
                if matches(near - distance, loose: loose) { return near - distance }
                if distance > 0 && matches(near + distance, loose: loose) { return near + distance }
            }
        }
        return nil
    }
}
