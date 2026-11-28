import Foundation

/// What a file is, from its first bytes (magic numbers) with the extension as a hint.
struct FileKind: Equatable, CustomStringConvertible {
    enum Category: String, Codable {
        case archive, executable, rom, image, audio, video, document, data, text, code, database, font, model3D, binary
    }

    var id: String            // "zip", "pe", "gba", "png", "json", …
    var name: String          // human description
    var category: Category
    var ext: String           // canonical extension

    var description: String { "\(name) (.\(ext))" }
    var isText: Bool { category == .text || category == .code || (category == .data && id != "sqlite" && id != "bplist") }

    static let codeExtensions: Set<String> = [
        "swift", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "c", "h", "cc", "cpp", "hpp", "cs", "java", "kt", "kts",
        "m", "mm", "php", "lua", "sh", "bash", "zsh", "ps1", "bat", "cmd", "pl", "r", "dart", "scala", "sql", "html", "htm", "css",
        "scss", "less", "vue", "svelte", "gd", "glsl", "metal", "hlsl", "asm", "s", "zig", "nim", "ex", "exs", "erl", "hs", "ml", "fs",
        "clj", "groovy", "gradle", "cmake", "make", "mk", "dockerfile", "v", "vhd", "sv", "jl", "f90", "pas", "vb", "coffee",
    ]
    static let dataExtensions: Set<String> = ["json", "yaml", "yml", "toml", "ini", "cfg", "conf", "xml", "plist", "csv", "tsv", "env", "properties",
                                              "strings", "po", "srt", "vtt", "ndjson", "jsonl", "geojson", "svg", "tbl"]
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "rst", "log", "rtf", "tex", "adoc", "org", "nfo", "diz"]

    /// Detect the kind of `bytes`; `filename` breaks ties (e.g. a ZIP that is really a .docx).
    static func detect(_ bytes: [UInt8], filename: String = "") -> FileKind {
        let r = ByteReader(bytes)
        let ext = (filename as NSString).pathExtension.lowercased()
        func k(_ id: String, _ name: String, _ c: Category, _ e: String) -> FileKind { FileKind(id: id, name: name, category: c, ext: e) }

        // Archives and containers.
        if ZipArchive.isZip(bytes) {
            switch ext {
            case "jar": return k("jar", "Java archive", .archive, "jar")
            case "apk": return k("apk", "Android app package", .archive, "apk")
            case "ipa": return k("ipa", "iOS app archive", .archive, "ipa")
            case "docx": return k("docx", "Word document", .document, "docx")
            case "xlsx": return k("xlsx", "Excel workbook", .document, "xlsx")
            case "pptx": return k("pptx", "PowerPoint presentation", .document, "pptx")
            case "epub": return k("epub", "EPUB e-book", .document, "epub")
            case "sb3": return k("sb3", "Scratch project", .archive, "sb3")
            case "usdz": return k("usdz", "USDZ 3D model", .model3D, "usdz")
            case "xpi", "crx": return k(ext, "browser extension", .archive, ext)
            default: return k("zip", "ZIP archive", .archive, "zip")
            }
        }
        if Gzip.isGzip(bytes) { return ext == "tgz" || filename.lowercased().hasSuffix(".tar.gz") ? k("tgz", "gzipped tar archive", .archive, "tar.gz") : k("gzip", "gzip-compressed file", .archive, "gz") }
        if TarArchive.isTar(bytes) { return k("tar", "tar archive", .archive, "tar") }
        if r.hasPrefix([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return k("7z", "7-Zip archive", .archive, "7z") }
        if r.hasPrefix(Array("Rar!".utf8)) { return k("rar", "RAR archive", .archive, "rar") }
        if r.hasPrefix([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return k("xz", "xz-compressed file", .archive, "xz") }
        if r.hasPrefix(Array("BZh".utf8)) { return k("bzip2", "bzip2-compressed file", .archive, "bz2") }
        if r.hasPrefix([0x28, 0xB5, 0x2F, 0xFD]) { return k("zstd", "Zstandard-compressed file", .archive, "zst") }

        // Executables.
        if r.hasPrefix(Array("MZ".utf8)) {
            if let pe = r.u32(0x3C).map({ Int($0) }), r.hasPrefix([0x50, 0x45, 0, 0], at: pe) {
                let dll = (r.u16(pe + 22) ?? 0) & 0x2000 != 0
                return dll ? k("pe", "Windows DLL", .executable, "dll") : k("pe", "Windows program", .executable, ext == "scr" || ext == "sys" ? ext : "exe")
            }
            return k("mz", "DOS program", .executable, "exe")
        }
        if r.hasPrefix([0x7F, 0x45, 0x4C, 0x46]) { return k("elf", "Linux/Unix ELF binary", .executable, ext.isEmpty ? "elf" : ext) }
        if r.hasPrefix([0xCF, 0xFA, 0xED, 0xFE]) || r.hasPrefix([0xCE, 0xFA, 0xED, 0xFE]) || r.hasPrefix([0xFE, 0xED, 0xFA, 0xCF]) || r.hasPrefix([0xFE, 0xED, 0xFA, 0xCE]) {
            return k("macho", "Mach-O binary (Apple)", .executable, ext.isEmpty ? "macho" : ext)
        }
        if r.hasPrefix([0xCA, 0xFE, 0xBA, 0xBE]) {
            // Java class files have a large major version; fat Mach-O files a small architecture count.
            let n = r.u32be(4) ?? 0
            return n < 30 ? k("macho", "universal Mach-O binary (Apple)", .executable, "macho") : k("class", "Java class file", .executable, "class")
        }
        if r.hasPrefix([0x00, 0x61, 0x73, 0x6D]) { return k("wasm", "WebAssembly module", .executable, "wasm") }
        if r.hasPrefix(Array("dex\n".utf8)) { return k("dex", "Android Dalvik bytecode", .executable, "dex") }
        if r.hasPrefix([0x1B, 0x4C, 0x75, 0x61]) { return k("luac", "compiled Lua bytecode", .executable, "luac") }

        // Game ROMs.
        if bytes.count >= 0xC0 && r.u8(0xB2) == 0x96 && r.hasPrefix([0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21], at: 4) {
            return k("gba", "Game Boy Advance ROM", .rom, "gba")
        }
        if bytes.count >= 0x150 && r.hasPrefix([0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B], at: 0x104) {
            let cgb = r.u8(0x143) ?? 0
            return cgb & 0x80 != 0 ? k("gbc", "Game Boy Color ROM", .rom, "gbc") : k("gb", "Game Boy ROM", .rom, "gb")
        }
        if r.hasPrefix([0x4E, 0x45, 0x53, 0x1A]) { return k("nes", "NES ROM (iNES)", .rom, "nes") }
        if bytes.count > 0x160 && r.hasPrefix([0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21], at: 0xC0) { return k("nds", "Nintendo DS ROM", .rom, "nds") }
        if r.hasPrefix([0x80, 0x37, 0x12, 0x40]) || r.hasPrefix([0x37, 0x80, 0x40, 0x12]) || r.hasPrefix([0x40, 0x12, 0x37, 0x80]) {
            return k("n64", "Nintendo 64 ROM", .rom, "z64")
        }
        if bytes.count > 0x110 && (r.ascii(0x100, 4) == "SEGA") { return k("md", "Sega Mega Drive/Genesis ROM", .rom, "md") }
        if ["sfc", "smc"].contains(ext) { return k("snes", "Super Nintendo ROM", .rom, ext) }
        if r.hasPrefix(Array("PATCH".utf8)) { return k("ips", "IPS patch", .rom, "ips") }
        if r.hasPrefix(Array("BPS1".utf8)) { return k("bps", "BPS patch", .rom, "bps") }
        if r.hasPrefix(Array("UPS1".utf8)) { return k("ups", "UPS patch", .rom, "ups") }

        // Media.
        if r.hasPrefix([0x89, 0x50, 0x4E, 0x47]) { return k("png", "PNG image", .image, "png") }
        if r.hasPrefix([0xFF, 0xD8, 0xFF]) { return k("jpeg", "JPEG image", .image, "jpg") }
        if r.hasPrefix(Array("GIF8".utf8)) { return k("gif", "GIF image", .image, "gif") }
        if r.hasPrefix(Array("BM".utf8)) && bytes.count > 26 && (r.u32(2).map { Int($0) <= bytes.count + 16 } ?? false) { return k("bmp", "BMP image", .image, "bmp") }
        if r.hasPrefix(Array("RIFF".utf8)) {
            switch r.ascii(8, 4) {
            case "WEBP": return k("webp", "WebP image", .image, "webp")
            case "WAVE": return k("wav", "WAV audio", .audio, "wav")
            case "AVI ": return k("avi", "AVI video", .video, "avi")
            default: break
            }
        }
        if r.hasPrefix([0x49, 0x49, 0x2A, 0x00]) || r.hasPrefix([0x4D, 0x4D, 0x00, 0x2A]) { return k("tiff", "TIFF image", .image, "tiff") }
        if r.hasPrefix([0x00, 0x00, 0x01, 0x00]) { return k("ico", "Windows icon", .image, "ico") }
        if r.ascii(4, 4) == "ftyp" {
            let brand = r.ascii(8, 4) ?? ""
            if ["heic", "heix", "mif1", "msf1", "heis"].contains(brand) { return k("heic", "HEIC image", .image, "heic") }
            if brand.hasPrefix("M4A") { return k("m4a", "AAC audio (M4A)", .audio, "m4a") }
            if brand == "qt  " { return k("mov", "QuickTime movie", .video, "mov") }
            if brand.hasPrefix("avif") { return k("avif", "AVIF image", .image, "avif") }
            return k("mp4", "MPEG-4 video", .video, ext == "m4v" ? "m4v" : "mp4")
        }
        if r.hasPrefix(Array("ID3".utf8)) || (bytes.count > 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0 && ext == "mp3") { return k("mp3", "MP3 audio", .audio, "mp3") }
        if r.hasPrefix(Array("fLaC".utf8)) { return k("flac", "FLAC audio", .audio, "flac") }
        if r.hasPrefix(Array("OggS".utf8)) { return k("ogg", "Ogg audio", .audio, "ogg") }
        if r.hasPrefix(Array("FORM".utf8)) && r.ascii(8, 4) == "AIFF" { return k("aiff", "AIFF audio", .audio, "aiff") }
        if r.hasPrefix(Array("caff".utf8)) { return k("caf", "Core Audio file", .audio, "caf") }
        if r.hasPrefix([0x1A, 0x45, 0xDF, 0xA3]) { return ext == "webm" ? k("webm", "WebM video", .video, "webm") : k("mkv", "Matroska video", .video, "mkv") }
        if r.hasPrefix(Array("MThd".utf8)) { return k("midi", "MIDI music", .audio, "mid") }

        // Documents, data, fonts.
        if r.hasPrefix(Array("%PDF".utf8)) { return k("pdf", "PDF document", .document, "pdf") }
        if r.hasPrefix(Array("{\\rtf".utf8)) { return k("rtf", "rich text document", .document, "rtf") }
        if r.hasPrefix(Array("SQLite format 3".utf8)) { return k("sqlite", "SQLite database", .database, "sqlite") }
        if r.hasPrefix(Array("bplist00".utf8)) { return k("bplist", "binary property list", .data, "plist") }
        if r.hasPrefix([0x00, 0x01, 0x00, 0x00]) && ["ttf", "otf"].contains(ext) || r.hasPrefix(Array("OTTO".utf8)) { return k("font", "font", .font, ext.isEmpty ? "ttf" : ext) }
        if r.hasPrefix(Array("wOF2".utf8)) || r.hasPrefix(Array("wOFF".utf8)) { return k("woff", "web font", .font, "woff2") }
        if r.hasPrefix(Array("glTF".utf8)) { return k("glb", "glTF binary 3D model", .model3D, "glb") }
        if r.hasPrefix(Array("PCK".utf8)) || r.hasPrefix(Array("GDPC".utf8)) { return k("pck", "Godot game data", .archive, "pck") }
        if r.hasPrefix(Array("UnityFS".utf8)) { return k("unity", "Unity asset bundle", .archive, "unity3d") }

        // Text: valid UTF-8 (or UTF-16 with BOM) without control bytes.
        if let text = TextSniffer.decode(bytes) {
            return textKind(text, ext: ext)
        }
        switch ext {
        case "stl": return k("stl", "STL 3D model", .model3D, "stl")
        case "ply": return k("ply", "PLY 3D model", .model3D, "ply")
        default: return k("binary", "binary data", .binary, ext.isEmpty ? "bin" : ext)
        }
    }

    static func textKind(_ text: String, ext: String) -> FileKind {
        func k(_ id: String, _ name: String, _ c: Category, _ e: String) -> FileKind { FileKind(id: id, name: name, category: c, ext: e) }
        let head = text.prefix(600).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = head.lowercased()
        switch ext {
        case "json", "geojson": return k("json", "JSON data", .data, ext)
        case "yaml", "yml": return k("yaml", "YAML data", .data, ext)
        case "toml": return k("toml", "TOML settings", .data, "toml")
        case "ini", "cfg", "conf": return k("ini", "INI settings", .data, ext)
        case "xml": return k("xml", "XML document", .data, "xml")
        case "plist": return k("plist", "property list", .data, "plist")
        case "csv": return k("csv", "CSV table", .data, "csv")
        case "tsv": return k("tsv", "TSV table", .data, "tsv")
        case "svg": return k("svg", "SVG image", .image, "svg")
        case "md", "markdown": return k("markdown", "Markdown text", .text, "md")
        case "html", "htm": return k("html", "web page", .code, "html")
        case "obj": return k("obj", "OBJ 3D model", .model3D, "obj")
        case "stl": return k("stl", "STL 3D model (text)", .model3D, "stl")
        case "ply": return k("ply", "PLY 3D model (text)", .model3D, "ply")
        default: break
        }
        if codeExtensions.contains(ext) { return k(ext, languageName(ext) + " source", .code, ext) }
        if dataExtensions.contains(ext) { return k(ext, ext.uppercased() + " data", .data, ext) }
        if textExtensions.contains(ext) { return k(ext, ext == "log" ? "log file" : "text", .text, ext) }
        // Sniff the content.
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") { return k("html", "web page", .code, "html") }
        if lower.hasPrefix("<?xml") { return lower.contains("<plist") ? k("plist", "property list", .data, "plist") : k("xml", "XML document", .data, "xml") }
        if lower.hasPrefix("<svg") { return k("svg", "SVG image", .image, "svg") }
        if head.hasPrefix("{") || head.hasPrefix("[") && !head.hasPrefix("[[") && head.contains("\""), (try? JSONValueParser.parse(text)) != nil {
            return k("json", "JSON data", .data, "json")
        }
        if head.hasPrefix("#!") {
            let line = head.prefix { $0 != "\n" }
            if line.contains("python") { return k("py", "Python script", .code, "py") }
            if line.contains("node") { return k("js", "JavaScript program", .code, "js") }
            return k("sh", "shell script", .code, "sh")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).prefix(40)
        let sectionLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("]") }.count
        let assignLines = lines.filter { $0.contains("=") && !$0.contains("==") }.count
        if sectionLines > 0 && assignLines > 0 { return k("ini", "INI settings", .data, "ini") }
        let colonLines = lines.filter { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("#") && t.contains(": ") || t.hasSuffix(":") || t.hasPrefix("- ")
        }.count
        if lines.count >= 2 && colonLines * 10 >= lines.count * 7 && !text.contains(";") && !text.contains("{") { return k("yaml", "YAML data", .data, "yaml") }
        let commaLines = lines.filter { $0.contains(",") }.count
        if lines.count >= 2 && commaLines == lines.count {
            let counts = Set(lines.prefix(10).map { $0.filter { $0 == "," }.count })
            if counts.count == 1 { return k("csv", "CSV table", .data, "csv") }
        }
        if lower.contains("function ") || lower.contains("const ") || lower.contains("=>") { return k("js", "JavaScript", .code, "js") }
        if lower.contains("def ") && lower.contains(":") || lower.hasPrefix("import ") { return k("py", "Python", .code, "py") }
        return k("txt", "plain text", .text, ext.isEmpty ? "txt" : ext)
    }

    static func languageName(_ ext: String) -> String {
        let names: [String: String] = [
            "swift": "Swift", "js": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript (React)",
            "jsx": "JavaScript (React)", "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust", "c": "C", "h": "C header",
            "cc": "C++", "cpp": "C++", "hpp": "C++ header", "cs": "C#", "java": "Java", "kt": "Kotlin", "kts": "Kotlin script",
            "m": "Objective-C", "mm": "Objective-C++", "php": "PHP", "lua": "Lua", "sh": "shell", "bash": "Bash", "zsh": "zsh",
            "ps1": "PowerShell", "bat": "Windows batch", "cmd": "Windows batch", "pl": "Perl", "r": "R", "dart": "Dart",
            "scala": "Scala", "sql": "SQL", "html": "HTML", "htm": "HTML", "css": "CSS", "scss": "SCSS", "less": "Less", "vue": "Vue",
            "svelte": "Svelte", "gd": "GDScript", "glsl": "GLSL", "metal": "Metal", "hlsl": "HLSL", "asm": "assembly", "s": "assembly",
            "zig": "Zig", "nim": "Nim", "ex": "Elixir", "exs": "Elixir", "erl": "Erlang", "hs": "Haskell", "ml": "OCaml", "fs": "F#",
            "clj": "Clojure", "groovy": "Groovy", "jl": "Julia", "f90": "Fortran", "pas": "Pascal", "vb": "Visual Basic", "coffee": "CoffeeScript",
        ]
        return names[ext] ?? ext.uppercased()
    }
}

/// Decides whether bytes are text and decodes them (UTF-8, UTF-16 with BOM, CP949/Latin-1 fallbacks).
enum TextSniffer {
    static func decode(_ bytes: [UInt8]) -> String? {
        if bytes.isEmpty { return "" }
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE { return String(bytes: bytes.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF { return String(bytes: bytes.dropFirst(2), encoding: .utf16BigEndian) }
        let sample = bytes.prefix(8192)
        var control = 0
        for b in sample where b < 0x20 && b != 9 && b != 10 && b != 13 && b != 12 && b != 27 {
            if b == 0 { return nil }
            control += 1
        }
        if control * 100 > sample.count { return nil }
        var body = bytes
        if body.count >= 3 && body[0] == 0xEF && body[1] == 0xBB && body[2] == 0xBF { body.removeFirst(3) }
        if let s = String(bytes: body, encoding: .utf8) { return s }
        // Truncated multi-byte sequence at the end of a sample is fine; real files must decode.
        #if canImport(Darwin)
        let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        if let s = String(bytes: body, encoding: cp949) { return s }
        #endif
        let high = body.filter { $0 >= 0x80 }.count
        if high * 20 < body.count { return String(bytes: body, encoding: .isoLatin1) }
        return nil
    }
}
