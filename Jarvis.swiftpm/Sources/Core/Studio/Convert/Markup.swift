import Foundation

/// Markdown → HTML (headings, emphasis, code, lists, quotes, links, images, tables, rules).
enum MarkdownFormat {
    static func html(_ markdown: String, title: String = "Document") -> String {
        var out: [String] = []
        let lines = markdown.components(separatedBy: .newlines)
        var i = 0
        var paragraph: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { out.append("<p>" + inline(paragraph.joined(separator: " ")) + "</p>") }
            paragraph = []
        }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(t.prefix(3))
                let lang = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                out.append("<pre><code\(lang.isEmpty ? "" : " class=\"language-\(escape(lang))\"")>" + escape(code.joined(separator: "\n")) + "</code></pre>")
                i += 1
                continue
            }
            if t.isEmpty { flushParagraph(); i += 1; continue }
            if let level = heading(t) {
                flushParagraph()
                let text = t.dropFirst(level).trimmingCharacters(in: CharacterSet(charactersIn: " #"))
                out.append("<h\(level) id=\"\(slug(text))\">\(inline(text))</h\(level)>")
                i += 1
                continue
            }
            if t == "---" || t == "***" || t == "___" {
                flushParagraph()
                out.append("<hr>")
                i += 1
                continue
            }
            if t.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append("<blockquote>" + inline(quote.joined(separator: " ")) + "</blockquote>")
                continue
            }
            if t.hasPrefix("|") && i + 1 < lines.count && lines[i + 1].contains("---") && lines[i + 1].contains("|") {
                flushParagraph()
                let header = cells(t)
                i += 2
                var rows: [[String]] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                var table = "<table><thead><tr>" + header.map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
                for r in rows { table += "<tr>" + r.map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }
                out.append(table + "</tbody></table>")
                continue
            }
            if isListItem(t) {
                flushParagraph()
                let ordered = t.first?.isNumber == true
                var items: [String] = []
                while i < lines.count, isListItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let item = lines[i].trimmingCharacters(in: .whitespaces)
                    let text: String
                    if ordered, let dot = item.firstIndex(where: { $0 == "." || $0 == ")" }) {
                        text = String(item[item.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                    } else {
                        text = String(item.dropFirst(2))
                    }
                    let task = text.hasPrefix("[ ] ") ? "<input type=\"checkbox\" disabled> " + inline(String(text.dropFirst(4)))
                        : text.lowercased().hasPrefix("[x] ") ? "<input type=\"checkbox\" checked disabled> " + inline(String(text.dropFirst(4))) : inline(text)
                    items.append("<li>\(task)</li>")
                    i += 1
                }
                out.append((ordered ? "<ol>" : "<ul>") + items.joined() + (ordered ? "</ol>" : "</ul>"))
                continue
            }
            paragraph.append(t)
            i += 1
        }
        flushParagraph()
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        body{font:16px/1.6 -apple-system,system-ui,"Segoe UI",sans-serif;max-width:46rem;margin:2rem auto;padding:0 1rem;color:#1d1d1f;background:#fff}
        @media (prefers-color-scheme:dark){body{color:#e8e8ed;background:#111}code,pre{background:#222!important}th,td{border-color:#444!important}}
        pre{background:#f4f4f6;padding:.8rem;border-radius:8px;overflow:auto}code{background:#f4f4f6;padding:.1rem .3rem;border-radius:4px}
        pre code{padding:0}blockquote{border-left:4px solid #8884;margin:0;padding:.2rem 1rem;color:#666}
        table{border-collapse:collapse}th,td{border:1px solid #ddd;padding:.3rem .6rem}img{max-width:100%}
        </style>
        </head>
        <body>
        \(out.joined(separator: "\n"))
        </body>
        </html>

        """
    }

    private static func heading(_ t: String) -> Int? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), t.count > hashes, t[t.index(t.startIndex, offsetBy: hashes)] == " " else { return nil }
        return hashes
    }

    private static func isListItem(_ t: String) -> Bool {
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        let digits = t.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count < 4 else { return false }
        let rest = t.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func cells(_ row: String) -> [String] {
        var r = row
        if r.hasPrefix("|") { r.removeFirst() }
        if r.hasSuffix("|") { r.removeLast() }
        return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func slug(_ s: String) -> String {
        String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }).split(separator: "-").joined(separator: "-")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Inline markup: code spans first (protected), then images, links, bold, italic, strike.
    static func inline(_ text: String) -> String {
        var codes: [String] = []
        var s = Packager.replacing(text, pattern: "`([^`]+)`") { m in
            codes.append("<code>" + escape(String(m.dropFirst().dropLast())) + "</code>")
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        s = escape(s)
        s = Packager.replacing(s, pattern: #"!\[([^\]]*)\]\(([^)\s]+)\)"#) { m in
            let parts = m.dropFirst(2).components(separatedBy: "](")
            return "<img alt=\"\(parts[0])\" src=\"\(parts.count > 1 ? String(parts[1].dropLast()) : "")\">"
        }
        s = Packager.replacing(s, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#) { m in
            let parts = m.dropFirst().components(separatedBy: "](")
            return "<a href=\"\(parts.count > 1 ? String(parts[1].dropLast()) : "#")\">\(parts[0])</a>"
        }
        s = Packager.replacing(s, pattern: #"\*\*([^*]+)\*\*|__([^_]+)__"#) { m in "<strong>" + String(m.dropFirst(2).dropLast(2)) + "</strong>" }
        s = Packager.replacing(s, pattern: #"(?<![*\w])\*([^*\n]+)\*(?![*\w])|(?<![_\w])_([^_\n]+)_(?![_\w])"#) { m in "<em>" + String(m.dropFirst().dropLast()) + "</em>" }
        s = Packager.replacing(s, pattern: "~~([^~]+)~~") { m in "<del>" + String(m.dropFirst(2).dropLast(2)) + "</del>" }
        for (k, c) in codes.enumerated() { s = s.replacingOccurrences(of: "\u{1}\(k)\u{1}", with: c) }
        return s
    }
}

enum HTMLText {
    /// Readable text from HTML: scripts and styles dropped, block elements become line breaks.
    static func text(_ html: String) -> String {
        var s = Packager.replacing(html, pattern: "<(script|style|head)\\b.*?</\\1>") { _ in "" }
        s = Packager.replacing(s, pattern: "<br\\s*/?>|</(p|div|h[1-6]|li|tr|section|article|header|footer|blockquote|pre)>") { _ in "\n" }
        s = Packager.replacing(s, pattern: "<li\\b[^>]*>") { _ in "• " }
        s = Packager.replacing(s, pattern: "<[^>]+>") { _ in "" }
        s = XMLFormat.decodeEntities(s)
        let lines = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for l in lines {
            if l.isEmpty && (out.last?.isEmpty ?? true) { continue }
            out.append(l)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Plain text → a simple web page.
    static func page(_ text: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(MarkdownFormat.escape(title))</title>
        <style>body{font:15px/1.5 ui-monospace,Menlo,monospace;margin:1.5rem;white-space:pre-wrap;word-wrap:break-word}</style>
        </head><body>\(MarkdownFormat.escape(text))</body></html>

        """
    }
}

/// Simple triangle-mesh formats: OBJ, STL (ASCII and binary) and PLY (ASCII).
struct TriangleMesh {
    var vertices: [SIMD3<Float>] = []
    var faces: [[Int]] = []

    static func parse(_ bytes: [UInt8], ext: String) throws -> TriangleMesh {
        switch ext {
        case "obj": return parseOBJ(String(decoding: bytes, as: UTF8.self))
        case "stl":
            let head = String(decoding: bytes.prefix(80), as: UTF8.self)
            if head.hasPrefix("solid") && String(decoding: bytes.prefix(2000), as: UTF8.self).contains("facet") {
                return parseASCIISTL(String(decoding: bytes, as: UTF8.self))
            }
            return try parseBinarySTL(bytes)
        case "ply": return try parsePLY(String(decoding: bytes, as: UTF8.self))
        default: throw DataFormatError.unsupported("not a mesh format: \(ext)")
        }
    }

    static func parseOBJ(_ text: String) -> TriangleMesh {
        var m = TriangleMesh()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let tag = parts.first else { continue }
            if tag == "v", parts.count >= 4 {
                m.vertices.append(SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0))
            } else if tag == "f", parts.count >= 4 {
                let idx = parts.dropFirst().compactMap { p -> Int? in
                    guard let v = Int(p.split(separator: "/").first ?? "") else { return nil }
                    return v < 0 ? m.vertices.count + v : v - 1
                }
                if idx.count >= 3 { m.faces.append(idx) }
            }
        }
        return m
    }

    static func parseASCIISTL(_ text: String) -> TriangleMesh {
        var m = TriangleMesh()
        var face: [Int] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.first == "vertex", parts.count >= 4 {
                m.vertices.append(SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0))
                face.append(m.vertices.count - 1)
            } else if parts.first == "endfacet" {
                if face.count >= 3 { m.faces.append(face) }
                face = []
            }
        }
        return m
    }

    static func parseBinarySTL(_ b: [UInt8]) throws -> TriangleMesh {
        let r = ByteReader(b)
        guard let count = r.u32(80) else { throw DataFormatError.unsupported("STL file too short") }
        var m = TriangleMesh()
        for t in 0..<Int(count) {
            let base = 84 + t * 50 + 12
            var face: [Int] = []
            for v in 0..<3 {
                let o = base + v * 12
                guard let x = r.u32(o), let y = r.u32(o + 4), let z = r.u32(o + 8) else { throw DataFormatError.unsupported("STL file truncated") }
                m.vertices.append(SIMD3(Float(bitPattern: x), Float(bitPattern: y), Float(bitPattern: z)))
                face.append(m.vertices.count - 1)
            }
            m.faces.append(face)
        }
        return m
    }

    static func parsePLY(_ text: String) throws -> TriangleMesh {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "ply" else { throw DataFormatError.unsupported("not a PLY file") }
        guard lines.contains(where: { $0.hasPrefix("format ascii") }) else { throw DataFormatError.unsupported("only text (ASCII) PLY files are supported") }
        var vertexCount = 0, faceCount = 0, start = 0
        for (k, l) in lines.enumerated() {
            if l.hasPrefix("element vertex") { vertexCount = Int(l.split(separator: " ").last ?? "") ?? 0 }
            if l.hasPrefix("element face") { faceCount = Int(l.split(separator: " ").last ?? "") ?? 0 }
            if l == "end_header" { start = k + 1; break }
        }
        var m = TriangleMesh()
        for k in 0..<vertexCount where start + k < lines.count {
            let p = lines[start + k].split(separator: " ").compactMap { Float($0) }
            if p.count >= 3 { m.vertices.append(SIMD3(p[0], p[1], p[2])) }
        }
        for k in 0..<faceCount where start + vertexCount + k < lines.count {
            let p = lines[start + vertexCount + k].split(separator: " ").compactMap { Int($0) }
            if let n = p.first, p.count >= n + 1 { m.faces.append(Array(p[1...n])) }
        }
        return m
    }

    var triangles: [(Int, Int, Int)] {
        faces.flatMap { f -> [(Int, Int, Int)] in
            guard f.count >= 3 else { return [] }
            return (1..<(f.count - 1)).map { (f[0], f[$0], f[$0 + 1]) }
        }
    }

    func obj() -> String {
        var out = "# Converted by Jarvis\n"
        for v in vertices { out += "v \(v.x) \(v.y) \(v.z)\n" }
        for f in faces { out += "f " + f.map { String($0 + 1) }.joined(separator: " ") + "\n" }
        return out
    }

    func stlBinary() -> [UInt8] {
        var w = ByteWriter()
        w.append([UInt8](repeating: 0, count: 80))
        let tris = triangles.filter { $0.0 < vertices.count && $0.1 < vertices.count && $0.2 < vertices.count }
        w.u32(UInt32(tris.count))
        for (a, b, c) in tris {
            let p0 = vertices[a], p1 = vertices[b], p2 = vertices[c]
            let e1 = p1 - p0, e2 = p2 - p0
            var n = SIMD3<Float>(e1.y * e2.z - e1.z * e2.y, e1.z * e2.x - e1.x * e2.z, e1.x * e2.y - e1.y * e2.x)
            let len = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
            if len > 0 { n /= len }
            for v in [n, p0, p1, p2] { w.u32(v.x.bitPattern); w.u32(v.y.bitPattern); w.u32(v.z.bitPattern) }
            w.u16(0)
        }
        return w.bytes
    }

    func ply() -> String {
        var out = "ply\nformat ascii 1.0\ncomment Converted by Jarvis\nelement vertex \(vertices.count)\nproperty float x\nproperty float y\nproperty float z\n"
        out += "element face \(faces.count)\nproperty list uchar int vertex_indices\nend_header\n"
        for v in vertices { out += "\(v.x) \(v.y) \(v.z)\n" }
        for f in faces { out += "\(f.count) " + f.map(String.init).joined(separator: " ") + "\n" }
        return out
    }
}
