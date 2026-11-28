import Foundation

/// A file going into a package.
struct PackageFile: Equatable {
    var path: String
    var data: [UInt8]
    var executable = false

    init(path: String, data: [UInt8], executable: Bool = false) {
        self.path = path
        self.data = data
        self.executable = executable
    }
}

/// Turns files into things people can run or open anywhere: a Windows .exe launcher,
/// a macOS .app, a self-extracting .sh, a single-file web page, or a ZIP.
enum Packager {
    // MARK: Windows .exe

    static let headerMagic = Array("JRVSPKG1".utf8)
    static let footerMagic = Array("JRVSEND1".utf8)

    struct WindowsPackage {
        var name: String
        var open: String
        var openAfterExtract: Bool
        var extractNextToExe: Bool
        var files: [PackageFile]
    }

    /// A real Windows (x64) program: running it restores `files` and opens `open` with its default app.
    static func windowsExe(name: String, files: [PackageFile], open: String?, extractNextToExe: Bool = false) -> [UInt8] {
        var w = ByteWriter()
        w.append(ExeStub.bytes)
        let headerOffset = w.bytes.count
        var flags: UInt32 = 0
        if open != nil { flags |= 1 }
        if extractNextToExe { flags |= 2 }
        w.append(headerMagic)
        w.u32(1)
        w.u32(flags)
        w.u32(UInt32(files.count))
        let nameBytes = Array(sanitizedName(name).utf8)
        w.u32(UInt32(nameBytes.count))
        w.append(nameBytes)
        let openBytes = Array((open ?? "").utf8)
        w.u32(UInt32(openBytes.count))
        w.append(openBytes)
        for f in files {
            let p = Array(f.path.replacingOccurrences(of: "\\", with: "/").utf8)
            w.u32(UInt32(p.count))
            w.append(p)
            w.u64(UInt64(f.data.count))
            w.append(f.data)
        }
        w.u64(UInt64(headerOffset))
        w.append(footerMagic)
        return w.bytes
    }

    /// Read back a package made by `windowsExe` (to inspect or unpack it).
    static func readWindowsPackage(_ bytes: [UInt8]) -> WindowsPackage? {
        let r = ByteReader(bytes)
        guard bytes.count > 32, r.hasPrefix(footerMagic, at: bytes.count - 8), let headerAt = r.u64(bytes.count - 16).map({ Int($0) }),
              r.hasPrefix(headerMagic, at: headerAt), r.u32(headerAt + 8) == 1 else { return nil }
        var p = headerAt + 12
        guard let flags = r.u32(p), let count = r.u32(p + 4) else { return nil }
        p += 8
        func string() -> String? {
            guard let n = r.u32(p).map({ Int($0) }), let s = r.slice(p + 4, n) else { return nil }
            p += 4 + n
            return String(decoding: s, as: UTF8.self)
        }
        guard let name = string(), let open = string() else { return nil }
        var files: [PackageFile] = []
        for _ in 0..<count {
            guard let path = string(), let size = r.u64(p).map({ Int($0) }), let data = r.slice(p + 8, size) else { return nil }
            p += 8 + size
            files.append(PackageFile(path: path, data: Array(data)))
        }
        return WindowsPackage(name: name, open: open, openAfterExtract: flags & 1 != 0, extractNextToExe: flags & 2 != 0, files: files)
    }

    // MARK: macOS .app

    /// A macOS app bundle (zipped) whose launcher opens the packaged main file.
    static func macApp(name: String, files: [PackageFile], open: String) -> [UInt8] {
        let app = sanitizedName(name) + ".app"
        let bundleID = "local.jarvis." + sanitizedName(name).lowercased().filter { $0.isLetter || $0.isNumber }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>launcher</string>
            <key>CFBundleIdentifier</key><string>\(xmlEscape(bundleID))</string>
            <key>CFBundleName</key><string>\(xmlEscape(name))</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>1.0</string>
            <key>CFBundleVersion</key><string>1</string>
            <key>LSMinimumSystemVersion</key><string>11.0</string>
        </dict>
        </plist>
        """
        let launcher = """
        #!/bin/sh
        # Opens the packaged file with its default app (made by Jarvis).
        HERE="$(cd "$(dirname "$0")/../Resources/payload" && pwd)"
        exec open "$HERE/\(shellEscape(open))"
        """
        var items = [ZipArchive.Item(path: "\(app)/Contents/Info.plist", data: Array(plist.utf8)),
                     ZipArchive.Item(path: "\(app)/Contents/MacOS/launcher", data: Array(launcher.utf8), executable: true)]
        for f in files {
            items.append(ZipArchive.Item(path: "\(app)/Contents/Resources/payload/\(f.path)", data: f.data, executable: f.executable))
        }
        return ZipArchive.build(items)
    }

    // MARK: Self-extracting shell script (Linux, macOS)

    static func shellInstaller(name: String, files: [PackageFile], open: String?) -> [UInt8] {
        let safe = sanitizedName(name)
        let tar = TarArchive.build(files.map { TarArchive.Entry(path: $0.path, data: $0.data, mode: $0.executable ? 0o755 : 0o644) })
        let payload = Gzip.compress(tar)
        var openLine = ""
        if let open {
            openLine = """
            F="$DEST/\(shellEscape(open))"
            if command -v xdg-open >/dev/null 2>&1; then xdg-open "$F" >/dev/null 2>&1 &
            elif command -v open >/dev/null 2>&1; then open "$F"
            else echo "Open $F"; fi
            """
        }
        let script = """
        #!/bin/sh
        # \(safe) — self-extracting package made by Jarvis. Run: sh "\(safe).sh"
        set -e
        DEST="${JARVIS_DEST:-${TMPDIR:-/tmp}/jarvis-\(shellEscape(safe))}"
        mkdir -p "$DEST"
        LINE=$(awk '/^__JARVIS_PAYLOAD__$/ { print NR + 1; exit 0 }' "$0")
        tail -n +"$LINE" "$0" | gzip -dc | tar -xf - -C "$DEST"
        echo "Extracted to $DEST"
        \(openLine)
        exit 0
        __JARVIS_PAYLOAD__

        """
        return Array(script.utf8) + payload
    }

    // MARK: Single-file web page

    /// Inline local CSS, scripts and images into one HTML file that works offline anywhere.
    static func singleHTML(files: [PackageFile], entry: String) -> String {
        var byPath: [String: PackageFile] = [:]
        for f in files { byPath[normalize(f.path)] = f }
        guard let main = byPath[normalize(entry)] else { return "" }
        let base = (normalize(entry) as NSString).deletingLastPathComponent
        func resolve(_ ref: String) -> PackageFile? {
            if ref.hasPrefix("http:") || ref.hasPrefix("https:") || ref.hasPrefix("data:") || ref.hasPrefix("//") { return nil }
            let clean = ref.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? ref
            let joined = base.isEmpty ? clean : base + "/" + clean
            return byPath[normalize(joined)] ?? byPath[normalize(clean)]
        }
        var html = String(decoding: main.data, as: UTF8.self)
        html = replacing(html, pattern: #"<link\b[^>]*rel=["']?stylesheet["']?[^>]*>"#) { tag in
            guard let href = attribute("href", in: tag), let css = resolve(href) else { return tag }
            return "<style>\n" + inlineCSSURLs(String(decoding: css.data, as: UTF8.self), resolve: resolve) + "\n</style>"
        }
        html = replacing(html, pattern: #"<script\b[^>]*\bsrc=["'][^"']+["'][^>]*>\s*</script>"#) { tag in
            guard let src = attribute("src", in: tag), let js = resolve(src) else { return tag }
            let type = attribute("type", in: tag).map { " type=\"\($0)\"" } ?? ""
            let code = String(decoding: js.data, as: UTF8.self).replacingOccurrences(of: "</script", with: "<\\/script")
            return "<script\(type)>\n" + code + "\n</script>"
        }
        html = replacing(html, pattern: #"<(img|audio|video|source)\b[^>]*\bsrc=["'][^"']+["'][^>]*>"#) { tag in
            guard let src = attribute("src", in: tag), let file = resolve(src) else { return tag }
            return tag.replacingOccurrences(of: src, with: dataURI(file))
        }
        html = inlineCSSURLs(html, resolve: resolve)
        return html
    }

    static func dataURI(_ f: PackageFile) -> String {
        "data:\(MIME.type(forPath: f.path));base64," + Data(f.data).base64EncodedString()
    }

    private static func inlineCSSURLs(_ css: String, resolve: (String) -> PackageFile?) -> String {
        replacing(css, pattern: #"url\(\s*["']?([^"')]+)["']?\s*\)"#) { match in
            let inner = match.dropFirst(4).dropLast().trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            guard let f = resolve(inner) else { return match }
            return "url(\"\(dataURI(f))\")"
        }
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let r = Range(m.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }

    static func replacing(_ text: String, pattern: String, _ transform: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return text }
        var out = ""
        var last = text.startIndex
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            out += text[last..<r.lowerBound]
            out += transform(String(text[r]))
            last = r.upperBound
        }
        out += text[last...]
        return out
    }

    // MARK: Helpers

    static func zip(_ files: [PackageFile], folder: String? = nil) -> [UInt8] {
        ZipArchive.build(files.map { ZipArchive.Item(path: (folder.map { $0 + "/" } ?? "") + $0.path, data: $0.data, executable: $0.executable) })
    }

    static func sanitizedName(_ name: String) -> String {
        let cleaned = name.map { (ch: Character) -> Character in "/\\:*?\"<>|".contains(ch) ? "-" : ch }
        let s = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Package" : String(s.prefix(60))
    }

    static func normalize(_ path: String) -> String {
        var parts: [String] = []
        for p in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            if p == "." || p.isEmpty { continue }
            if p == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(String(p))
        }
        return parts.joined(separator: "/")
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`")
    }
}

/// MIME types for serving and data URIs.
enum MIME {
    static let types: [String: String] = [
        "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8", "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8", "json": "application/json; charset=utf-8",
        "txt": "text/plain; charset=utf-8", "md": "text/markdown; charset=utf-8", "csv": "text/csv; charset=utf-8",
        "xml": "application/xml", "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "ico": "image/x-icon", "bmp": "image/bmp", "avif": "image/avif",
        "wasm": "application/wasm", "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "m4a": "audio/mp4",
        "mp4": "video/mp4", "webm": "video/webm", "mov": "video/quicktime", "woff": "font/woff", "woff2": "font/woff2",
        "ttf": "font/ttf", "otf": "font/otf", "pdf": "application/pdf", "zip": "application/zip", "glb": "model/gltf-binary",
        "gltf": "model/gltf+json", "obj": "text/plain", "usdz": "model/vnd.usdz+zip", "py": "text/x-python; charset=utf-8",
        "map": "application/json", "webmanifest": "application/manifest+json", "data": "application/octet-stream",
    ]

    static func type(forPath path: String) -> String {
        types[(path as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
    }
}
