import XCTest
@testable import JarvisCore

final class StudioConvertTests: XCTestCase {
    let ini = """
    ; game settings
    title = Space Hopper
    [graphics]
    width = 1280
    height = 720
    vsync = true
    scale = 1.5
    [audio]
    volume = 80 ; percent
    muted = false
    """

    func testINIToEveryDataFormatAndBack() async throws {
        let value = INIFormat.parse(ini)
        XCTAssertEqual(value["title"], .string("Space Hopper"))
        XCTAssertEqual(value["graphics"]?["width"], .int(1280))
        XCTAssertEqual(value["graphics"]?["vsync"], .bool(true))
        XCTAssertEqual(value["graphics"]?["scale"], .double(1.5))
        XCTAssertEqual(value["audio"]?["volume"], .int(80))
        for format in ["json", "yaml", "toml", "xml", "plist", "ini"] {
            let text = try XCTUnwrap(FormatConverter.writeData(value, format: format))
            let back = try FormatConverter.parseData(Array(text.utf8), format: format)
            let normalized = format == "xml" ? back["root"] ?? back : back
            XCTAssertEqual(normalized, value, "round trip through \(format):\n\(text)")
        }
        let csv = try await FormatConverter.convert(Array(ini.utf8), filename: "settings.ini", to: "csv")
        XCTAssertTrue(String(decoding: csv.data, as: UTF8.self).hasPrefix("title,graphics.width"))
    }

    func testYAMLConfig() throws {
        let yaml = """
        # deployment
        name: jarvis-site
        version: 2.1
        enabled: yes
        servers:
          - host: alpha.local
            port: 8080
          - host: beta.local
            port: 8081
        tags: [web, "fast game", 3]
        owner: {name: Tony, team: R&D}
        notes: |
          line one
          line two
        empty:
        quoted: "a: b # not a comment"
        """
        let v = try YAMLFormat.parse(yaml)
        XCTAssertEqual(v["name"], .string("jarvis-site"))
        XCTAssertEqual(v["version"], .double(2.1))
        XCTAssertEqual(v["enabled"], .bool(true))
        guard case .array(let servers)? = v["servers"] else { return XCTFail("servers") }
        XCTAssertEqual(servers.count, 2)
        XCTAssertEqual(servers[1]["port"], .int(8081))
        XCTAssertEqual(v["tags"], .array([.string("web"), .string("fast game"), .int(3)]))
        XCTAssertEqual(v["owner"]?["team"], .string("R&D"))
        XCTAssertEqual(v["notes"], .string("line one\nline two\n"))
        XCTAssertEqual(v["empty"], .null)
        XCTAssertEqual(v["quoted"], .string("a: b # not a comment"))
        XCTAssertEqual(try YAMLFormat.parse(YAMLFormat.write(v)), v)
    }

    func testTOML() throws {
        let toml = """
        [package]
        name = "jarvis"
        version = "0.1.0"
        authors = ["A", "B"]

        [dependencies]
        serde = { version = "1.0", features = ["derive"] }

        [[bin]]
        name = "cli"
        path = "src/main.rs"

        [[bin]]
        name = "server"
        """
        let v = try TOMLFormat.parse(toml)
        XCTAssertEqual(v["package"]?["authors"], .array([.string("A"), .string("B")]))
        XCTAssertEqual(v["dependencies"]?["serde"]?["features"], .array([.string("derive")]))
        guard case .array(let bins)? = v["bin"] else { return XCTFail("bin") }
        XCTAssertEqual(bins.map { $0["name"] }, [.string("cli"), .string("server")])
        XCTAssertEqual(try TOMLFormat.parse(TOMLFormat.write(v)), v)
    }

    func testJSONXMLCSVAndMarkdown() throws {
        let json = try JSONValueParser.parse(#"{"users": [{"name": "Ana", "age": 31}, {"name": "Bo", "age": 27, "note": "likes \"games\""}], /* c */ "count": 2,}"#)
        XCTAssertEqual(json["count"], .int(2))
        let csv = CSVFormat.write(json["users"]!)
        XCTAssertEqual(csv, "name,age,note\nAna,31,\nBo,27,\"likes \"\"games\"\"\"\n")
        XCTAssertEqual(CSVFormat.parse(csv), .array([
            .object([DataPair(key: "name", value: .string("Ana")), DataPair(key: "age", value: .int(31)), DataPair(key: "note", value: .string(""))]),
            .object([DataPair(key: "name", value: .string("Bo")), DataPair(key: "age", value: .int(27)), DataPair(key: "note", value: .string("likes \"games\""))]),
        ]))
        let xml = try XMLFormat.parse("<?xml version=\"1.0\"?><!-- c --><library open=\"yes\"><book id=\"1\">Dune</book><book id=\"2\"><![CDATA[<Neuromancer>]]></book><owner>Ana &amp; Bo</owner></library>")
        XCTAssertEqual(xml["library"]?["@open"], .bool(true))
        XCTAssertEqual(xml["library"]?["owner"], .string("Ana & Bo"))
        guard case .array(let books)? = xml["library"]?["book"] else { return XCTFail("books") }
        XCTAssertEqual(books[1]["#text"], .string("<Neuromancer>"))
        let html = MarkdownFormat.html("# Title\n\nSome **bold** and *it* with `code`.\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```js\nlet a = 1 < 2;\n```")
        for piece in ["<h1 id=\"title\">Title</h1>", "<strong>bold</strong>", "<em>it</em>", "<code>code</code>", "<ul><li>one</li><li>two</li></ul>",
                      "<td>1</td>", "<pre><code class=\"language-js\">let a = 1 &lt; 2;</code></pre>"] {
            XCTAssertTrue(html.contains(piece), piece)
        }
        XCTAssertEqual(HTMLText.text("<html><head><style>x{}</style></head><body><h1>Hi</h1><p>A &amp; B</p><ul><li>x</li></ul></body></html>"), "Hi\nA & B\n• x\n")
    }

    func testProgramsArchivesAndMeshes() async throws {
        let exe = try await FormatConverter.convert(Array(ini.utf8), filename: "settings.ini", to: ".exe")
        XCTAssertEqual(exe.filename, "settings.exe")
        XCTAssertNotNil(PEInfo.parse(exe.data))
        let pkg = try XCTUnwrap(Packager.readWindowsPackage(exe.data))
        XCTAssertEqual(pkg.files.first?.path, "settings.ini")
        XCTAssertEqual(pkg.open, "settings.ini")
        XCTAssertTrue(pkg.extractNextToExe)
        XCTAssertTrue(exe.note.contains("launcher"))

        let site = Packager.zip([PackageFile(path: "site/index.html", data: Array("<link rel=\"stylesheet\" href=\"style.css\"><script src=\"app.js\"></script><img src=\"logo.png\">".utf8)),
                                 PackageFile(path: "site/style.css", data: Array("body{background:url(logo.png)}".utf8)),
                                 PackageFile(path: "site/app.js", data: Array("console.log('</script>')".utf8)),
                                 PackageFile(path: "site/logo.png", data: [0x89, 0x50, 0x4E, 0x47])])
        let app = try await FormatConverter.convert(site, filename: "site.zip", to: "app")
        let appZip = try ZipArchive(bytes: app.data)
        XCTAssertNotNil(appZip.entry(named: "site.app/Contents/MacOS/launcher"))
        XCTAssertEqual(appZip.entry(named: "site.app/Contents/MacOS/launcher")?.unixMode.map { $0 & 0o111 != 0 }, true)
        let web = try await FormatConverter.convert(site, filename: "site.zip", to: "exe")
        XCTAssertEqual(Packager.readWindowsPackage(web.data)?.open, "site/index.html")
        XCTAssertTrue(web.note.contains("browser"))
        let tgz = try await FormatConverter.convert(site, filename: "site.zip", to: "tar.gz")
        XCTAssertEqual(try FormatConverter.unpack(tgz.data, filename: tgz.filename).count, 4)
        let sh = try await FormatConverter.convert(site, filename: "site.zip", to: "sh")
        XCTAssertTrue(String(decoding: sh.data.prefix(200), as: UTF8.self).hasPrefix("#!/bin/sh"))

        let single = Packager.singleHTML(files: try FormatConverter.unpack(site, filename: "site.zip"), entry: "site/index.html")
        XCTAssertTrue(single.contains("<style>"))
        XCTAssertTrue(single.contains("data:image/png;base64,iVBORw=="))
        XCTAssertTrue(single.contains("<\\/script>"))
        XCTAssertFalse(single.contains("src=\"app.js\""))

        let obj = "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 2 3\nf 1 2 4\nf 1 3 4 2\n"
        let stl = try await FormatConverter.convert(Array(obj.utf8), filename: "shape.obj", to: "stl")
        XCTAssertEqual(ByteReader(stl.data).u32(80), 4)
        let ply = try await FormatConverter.convert(stl.data, filename: "shape.stl", to: "ply")
        XCTAssertTrue(String(decoding: ply.data, as: UTF8.self).contains("element face 4"))

        do {
            _ = try await FormatConverter.convert(ExeStub.bytes, filename: "tool.exe", to: "py")
            XCTFail("an .exe can't become Python by conversion")
        } catch {
            XCTAssertTrue(String(describing: error).contains("machine code"))
        }
    }
}
