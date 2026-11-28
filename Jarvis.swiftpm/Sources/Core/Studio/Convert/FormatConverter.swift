import Foundation

struct ConversionResult {
    var data: [UInt8]
    var filename: String
    /// What was done, in plain words (and what a format change can and cannot mean).
    var note: String
}

enum ConversionError: Error, CustomStringConvertible {
    case impossible(String)
    var description: String { if case .impossible(let s) = self { return s }; return "" }
}

/// Converts files between formats. Formats that hold the same kind of content convert
/// directly (data ↔ data, text ↔ web page, archive ↔ archive, mesh ↔ mesh, media ↔ media);
/// "into a program" means packaging the content into a launcher that runs on that system.
enum FormatConverter {
    /// Images, audio, video, PDF and USDZ need Apple frameworks: the app installs this hook.
    nonisolated(unsafe) static var mediaConverter: ((_ bytes: [UInt8], _ filename: String, _ target: String) async throws -> ConversionResult?)?

    static let dataFormats: Set<String> = ["json", "yaml", "toml", "ini", "xml", "plist", "csv", "tsv", "env", "properties"]
    static let archiveFormats: Set<String> = ["zip", "tar", "tgz", "gz"]
    static let meshFormats: Set<String> = ["obj", "stl", "ply"]
    static let programTargets: Set<String> = ["exe", "app", "sh"]
    static let mediaTargets: Set<String> = ["png", "jpg", "heic", "tiff", "bmp", "gif", "pdf", "ico", "m4a", "wav", "caf", "aiff",
                                            "mp4", "mov", "m4v", "usdz", "txt-from-pdf"]

    /// Canonical target name for what the user typed ("JPEG", ".yml", "windows", "실행 파일").
    static func normalizeTarget(_ raw: String) -> String {
        var t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix(".") { t.removeFirst() }
        let aliases: [String: String] = [
            "yml": "yaml", "jpeg": "jpg", "htm": "html", "web": "html", "webpage": "html", "website": "html", "markdown": "md",
            "text": "txt", "windows": "exe", "win": "exe", "program": "exe", "executable": "exe", "실행파일": "exe", "실행 파일": "exe",
            "mac": "app", "macos": "app", "linux": "sh", "run": "sh", "shell": "sh", "tar.gz": "tgz", "gzip": "gz", "base64": "b64",
            "cfg": "ini", "conf": "ini", "tif": "tiff", "aac": "m4a", "mpeg4": "mp4", "quicktime": "mov", "웹페이지": "html", "압축": "zip",
        ]
        if let a = aliases[t] { t = a }
        return t
    }

    static func kindID(_ bytes: [UInt8], _ filename: String) -> String {
        let kind = FileKind.detect(bytes, filename: filename)
        switch kind.id {
        case "yml": return "yaml"
        case "cfg", "conf": return "ini"
        case "markdown": return "md"
        case "tgz": return "tgz"
        case "gzip": return "gz"
        default: return kind.id
        }
    }

    static func convert(_ bytes: [UInt8], filename: String, to rawTarget: String, open: String? = nil) async throws -> ConversionResult {
        let target = normalizeTarget(rawTarget)
        let base = baseName(filename)
        let source = kindID(bytes, filename)
        let kind = FileKind.detect(bytes, filename: filename)
        func result(_ data: [UInt8], _ ext: String, _ note: String) -> ConversionResult {
            ConversionResult(data: data, filename: base + "." + ext, note: note)
        }
        func text(_ s: String, _ ext: String, _ note: String) -> ConversionResult { result(Array(s.utf8), ext, note) }

        if target == source || target == kind.ext {
            return ConversionResult(data: bytes, filename: filename, note: "It is already a \(kind.name); nothing to convert.")
        }

        // Programs: package the content so it runs (or opens) on that system.
        if programTargets.contains(target) {
            let files = (try? unpack(bytes, filename: filename)) ?? [PackageFile(path: filename, data: bytes)]
            let entry = open ?? mainEntry(files) ?? filename
            let web = files.contains { $0.path.lowercased().hasSuffix(".html") }
            let what: String
            if web { what = "the web app opens in the default browser" }
            else if kind.category == .data || kind.category == .text { what = "it restores \(entry) and opens it in the system's default app for that file type" }
            else { what = "it restores \(entry) and opens it with the default app" }
            let honesty = kind.category == .executable ? "" : " A \(kind.name) is not a program by itself, so this is a launcher package — ask me to build a program that *uses* the file if that is what you need."
            switch target {
            case "exe":
                let data = Packager.windowsExe(name: base, files: files, open: entry, extractNextToExe: !web && files.count == 1)
                return result(data, "exe", "Windows (x64) program: when run, \(what).\(honesty) Windows SmartScreen may warn because it isn't code-signed (More info → Run anyway).")
            case "app":
                return result(Packager.macApp(name: base, files: files, open: entry), "app.zip",
                              "macOS app (zipped): unzip and open it; \(what).\(honesty) It isn't signed, so the first time use right-click → Open.")
            default:
                return result(Packager.shellInstaller(name: base, files: files, open: entry), "sh",
                              "Self-extracting script for Linux and macOS (run: sh \(base).sh); \(what).\(honesty)")
            }
        }

        // Archives.
        if archiveFormats.contains(target) || target == "folder" {
            let files = (try? unpack(bytes, filename: filename)) ?? [PackageFile(path: filename, data: bytes)]
            switch target {
            case "zip": return result(Packager.zip(files), "zip", "ZIP archive with \(files.count) file(s).")
            case "tar": return result(TarArchive.build(files.map { TarArchive.Entry(path: $0.path, data: $0.data) }), "tar", "tar archive with \(files.count) file(s).")
            case "tgz": return result(Gzip.compress(TarArchive.build(files.map { TarArchive.Entry(path: $0.path, data: $0.data) })), "tar.gz", "gzipped tar archive with \(files.count) file(s).")
            case "gz":
                if files.count == 1 { return ConversionResult(data: Gzip.compress(files[0].data, name: files[0].path), filename: files[0].path + ".gz", note: "gzip-compressed.") }
                return result(Gzip.compress(TarArchive.build(files.map { TarArchive.Entry(path: $0.path, data: $0.data) })), "tar.gz", "Several files: made a .tar.gz.")
            default: break
            }
        }

        // Structured data ↔ structured data (and data → table pages).
        let textValue = TextSniffer.decode(bytes)
        if dataFormats.contains(source) || source == "bplist", let value = try? parseData(bytes, format: source) {
            if let out = writeData(value, format: target) {
                return text(out, target == "env" ? "env" : target, "Converted \(source.uppercased()) to \(target.uppercased()) (\(summary(value))).")
            }
            if target == "html" { return text(htmlTable(value, title: base), "html", "Data shown as a web page table.") }
            if target == "md" { return text(markdownTable(value), "md", "Data as a Markdown table.") }
            if target == "txt" { return text(JSONWriter.write(value), "txt", "Data as readable text.") }
        }

        // Text, Markdown and web pages.
        if let t = textValue {
            switch (source, target) {
            case ("md", "html"): return text(MarkdownFormat.html(t, title: base), "html", "Markdown rendered as a web page.")
            case ("html", "txt"), ("html", "md"): return text(HTMLText.text(t), target, "Text extracted from the web page.")
            case (_, "html") where kind.category == .text || kind.category == .code:
                if source == "html" { break }
                return text(HTMLText.page(t, title: filename), "html", "Text shown as a web page.")
            case (_, "md") where kind.category == .text: return text(t, "md", "Plain text saved as Markdown.")
            case (_, "txt") where kind.category == .code || kind.category == .text || kind.category == .data:
                return text(t, "txt", "Saved as plain text.")
            case (_, "json") where source == "md" || kind.category == .text:
                return text(JSONWriter.write(.object([DataPair(key: "text", value: .string(t))])), "json", "Text wrapped in JSON.")
            default: break
            }
            if (kind.category == .text || kind.category == .code), FileKind.codeExtensions.contains(target) {
                return text(t, target, "Saved with the .\(target) extension (contents unchanged). To translate code into another language, ask me to rewrite it.")
            }
        }

        // Base64 and hex.
        if target == "b64" { return result(Array(Data(bytes).base64EncodedString(options: [.lineLength76Characters]).utf8), "b64", "Base64 text of the file.") }
        if source == "b64" || filename.lowercased().hasSuffix(".b64"), let t = textValue, let decoded = Data(base64Encoded: t, options: .ignoreUnknownCharacters) {
            return ConversionResult(data: [UInt8](decoded), filename: base + "." + target, note: "Decoded from Base64.")
        }
        if target == "hex" { return result(Array(BinaryTools.hexdump(bytes, offset: 0, length: bytes.count).utf8), "hex.txt", "Hex dump of every byte.") }

        // 3D meshes.
        if meshFormats.contains(source) && meshFormats.contains(target) {
            let mesh = try TriangleMesh.parse(bytes, ext: source)
            guard !mesh.faces.isEmpty else { throw ConversionError.impossible("No faces found in the \(source.uppercased()) file.") }
            let note = "Converted \(mesh.vertices.count) vertices and \(mesh.faces.count) faces."
            switch target {
            case "obj": return text(mesh.obj(), "obj", note)
            case "stl": return result(mesh.stlBinary(), "stl", note)
            default: return text(mesh.ply(), "ply", note)
            }
        }

        // Web page for media.
        if target == "html" && (kind.category == .image || kind.category == .audio || kind.category == .video) {
            let uri = Packager.dataURI(PackageFile(path: kind.ext == "jpg" ? base + ".jpg" : filename, data: bytes))
            let tag: String
            switch kind.category {
            case .image: tag = "<img src=\"\(uri)\" alt=\"\(Packager.xmlEscape(base))\" style=\"max-width:100%\">"
            case .audio: tag = "<audio controls src=\"\(uri)\"></audio>"
            default: tag = "<video controls style=\"max-width:100%\" src=\"\(uri)\"></video>"
            }
            return text("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(Packager.xmlEscape(base))</title></head><body style=\"margin:0;display:grid;place-items:center;min-height:100vh;background:#111\">\(tag)</body></html>\n",
                        "html", "Self-contained web page with the \(kind.category.rawValue) embedded.")
        }

        // Images, audio, video, PDF, USDZ: Apple frameworks on the device.
        if let media = mediaConverter, let converted = try await media(bytes, filename, target) { return converted }

        throw ConversionError.impossible(impossibleReason(kind: kind, target: target))
    }

    static func impossibleReason(kind: FileKind, target: String) -> String {
        if kind.category == .executable && target != "zip" {
            return "\(kind.name) holds machine code; it can't become a .\(target) by converting bytes. I can inspect or patch it, extract what it contains, or rebuild its features as a new program."
        }
        if kind.category == .code && FileKind.codeExtensions.contains(target) {
            return "Translating \(FileKind.languageName(kind.ext)) into \(FileKind.languageName(target)) is a rewrite, not a format change — ask me to rewrite it and I'll build and test the new version."
        }
        return "A \(kind.name) can't be turned into .\(target) directly. Possible targets: \(targets(for: kind).joined(separator: ", "))."
    }

    /// Formats a file of this kind can become.
    static func targets(for kind: FileKind) -> [String] {
        var t: [String] = ["zip", "exe", "app", "sh"]
        switch kind.category {
        case .data: t = Array(dataFormats).sorted() + ["html", "md", "txt"] + t
        case .text: t = ["html", "md", "txt", "json"] + t
        case .code: t = ["html", "txt"] + t
        case .image: t = ["png", "jpg", "heic", "tiff", "bmp", "gif", "pdf", "ico", "html"] + t
        case .audio: t = ["m4a", "wav", "caf", "aiff", "html"] + t
        case .video: t = ["mp4", "mov", "m4v", "m4a", "gif", "html"] + t
        case .document: t = kind.id == "pdf" ? ["png", "txt"] + t : t
        case .model3D: t = ["obj", "stl", "ply", "usdz"] + t
        case .archive: t = ["zip", "tar", "tgz", "exe", "app", "sh"]
        default: break
        }
        return t.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Helpers

    static func baseName(_ filename: String) -> String {
        var name = (filename as NSString).lastPathComponent
        for double in [".tar.gz", ".app.zip"] where name.lowercased().hasSuffix(double) { name = String(name.dropLast(double.count)); return name }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
    }

    /// Files inside an archive (ZIP, tar, tar.gz, a Jarvis .exe package); throws for anything else.
    static func unpack(_ bytes: [UInt8], filename: String) throws -> [PackageFile] {
        if ZipArchive.isZip(bytes) {
            let z = try ZipArchive(bytes: bytes)
            return try z.files.compactMap { e in
                guard let path = ZipArchive.safePath(e.path) else { return nil }
                return PackageFile(path: path, data: try z.data(for: e), executable: (e.unixMode ?? 0) & 0o111 != 0)
            }
        }
        if Gzip.isGzip(bytes) {
            let inner = try Gzip.decompress(bytes)
            if TarArchive.isTar(inner.data) { return try unpack(inner.data, filename: "x.tar") }
            return [PackageFile(path: inner.name ?? baseName(filename), data: inner.data)]
        }
        if TarArchive.isTar(bytes) {
            return try TarArchive.read(bytes).filter { !$0.isDirectory }.compactMap { e in
                ZipArchive.safePath(e.path).map { PackageFile(path: $0, data: e.data, executable: e.mode & 0o111 != 0) }
            }
        }
        if let pkg = Packager.readWindowsPackage(bytes) { return pkg.files }
        if let pe = PEInfo.parse(bytes), let z = pe.embeddedZipOffset {
            return try unpack(Array(bytes[z...]), filename: "embedded.zip")
        }
        throw ConversionError.impossible("\(filename) is not an archive")
    }

    /// The file to open: index.html, a main program, or the only file.
    static func mainEntry(_ files: [PackageFile]) -> String? {
        let paths = files.map(\.path)
        for preferred in ["index.html", "index.htm", "main.html", "game.html", "app.html"] {
            if let p = paths.first(where: { $0.lowercased() == preferred }) { return p }
        }
        if let p = paths.filter({ $0.lowercased().hasSuffix("/index.html") }).min(by: { $0.count < $1.count }) { return p }
        if let p = paths.first(where: { $0.lowercased().hasSuffix(".html") }) { return p }
        return paths.count == 1 ? paths[0] : paths.first { ["main.py", "main.js", "readme.md", "readme.txt"].contains($0.lowercased()) }
    }

    static func parseData(_ bytes: [UInt8], format: String) throws -> DataValue {
        if format == "bplist" { return try PlistFormat.parseBinary(bytes) }
        guard let text = TextSniffer.decode(bytes) else { throw DataFormatError.unsupported("not text") }
        switch format {
        case "json": return try JSONValueParser.parse(text)
        case "yaml": return try YAMLFormat.parse(text)
        case "toml": return try TOMLFormat.parse(text)
        case "ini": return INIFormat.parse(text)
        case "xml", "plist": return try XMLFormat.parse(text)
        case "csv": return CSVFormat.parse(text)
        case "tsv": return CSVFormat.parse(text, delimiter: "\t")
        case "env", "properties": return KeyValueFormat.parse(text)
        default: throw DataFormatError.unsupported("not a data format: \(format)")
        }
    }

    static func writeData(_ v: DataValue, format: String) -> String? {
        switch format {
        case "json": return JSONWriter.write(v)
        case "yaml": return YAMLFormat.write(v)
        case "toml": return TOMLFormat.write(v)
        case "ini": return INIFormat.write(v)
        case "xml": return XMLFormat.write(v)
        case "plist": return PlistFormat.write(v)
        case "csv": return CSVFormat.write(v)
        case "tsv": return CSVFormat.write(v, delimiter: "\t")
        case "env", "properties": return KeyValueFormat.write(v)
        default: return nil
        }
    }

    static func summary(_ v: DataValue) -> String {
        switch v {
        case .object(let p): return "\(p.count) top-level key(s)"
        case .array(let a): return "\(a.count) item(s)"
        default: return "a single value"
        }
    }

    static func tableRows(_ v: DataValue) -> (header: [String], rows: [[String]]) {
        let csv = CSVFormat.write(v)
        let rows = CSVFormat.rows(csv)
        return (rows.first ?? [], Array(rows.dropFirst()))
    }

    static func htmlTable(_ v: DataValue, title: String) -> String {
        let t = tableRows(v)
        var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>\(Packager.xmlEscape(title))</title>"
        html += "<style>body{font:14px system-ui,sans-serif;margin:1.5rem}table{border-collapse:collapse}th,td{border:1px solid #ccc;padding:.35rem .6rem;text-align:left}th{background:#eef}</style></head><body>"
        html += "<h1>\(Packager.xmlEscape(title))</h1><table><thead><tr>" + t.header.map { "<th>\(Packager.xmlEscape($0))</th>" }.joined() + "</tr></thead><tbody>"
        for r in t.rows { html += "<tr>" + r.map { "<td>\(Packager.xmlEscape($0))</td>" }.joined() + "</tr>" }
        return html + "</tbody></table></body></html>\n"
    }

    static func markdownTable(_ v: DataValue) -> String {
        let t = tableRows(v)
        guard !t.header.isEmpty else { return "" }
        func row(_ cells: [String]) -> String { "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |" }
        return ([row(t.header), "|" + String(repeating: " --- |", count: t.header.count)] + t.rows.map(row)).joined(separator: "\n") + "\n"
    }
}
